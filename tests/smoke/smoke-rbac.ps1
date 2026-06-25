param(
  [string]$KeycloakUrl = "http://localhost:8080",
  [string]$GatewayMcpUrl = "http://localhost:3002/mcp"
)

# End-to-end MCP RBAC check through agentgateway:
#  - no token            -> 401
#  - reader (tenant-a)   -> may call read tools, denied write tools
#  - operator (tenant-b) -> may call write tools
# Requires the `security` profile up (keycloak + tool servers + agentgateway-mcp-secure).

$ErrorActionPreference = "Stop"
$fail = 0
function Check($label, $got, $want) {
  if ($got -eq $want) { Write-Host "PASS  $label ($got)" -ForegroundColor Green }
  else { Write-Host "FAIL  $label (got=$got want=$want)" -ForegroundColor Red; $script:fail++ }
}

function New-McpSession($tok) {
  $H = @{ Authorization = "Bearer $tok"; Accept = "application/json, text/event-stream" }
  $init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke-rbac","version":"0"}}}'
  $r = Invoke-WebRequest -Method Post -Uri $GatewayMcpUrl -ContentType "application/json" -Headers $H -Body $init -UseBasicParsing
  $sid = ([string[]]$r.Headers["Mcp-Session-Id"])[0]
  return @{ Authorization = "Bearer $tok"; Accept = "application/json, text/event-stream"; "Mcp-Session-Id" = $sid }
}

# agentgateway groups OpenAPI parameters by location, so query params are nested
# under a `query` object in the generated tool schema (e.g. readTickets expects
# arguments={query:{tenant:...}}, NOT a flat {tenant:...} — a flat arg reaches the
# backend as null). mcp:/passthrough tools (sqlite_/http_) take flat args.
function Get-ToolArgs($name) {
  switch ($name) {
    "openapi_readTickets" { return @{ query = @{ tenant = "tenant-a" } } }
    default               { return @{ tenant = "tenant-a"; note = "x"; service = "payments" } }
  }
}

function Invoke-Tool($H, $name) {
  $body = (@{ jsonrpc="2.0"; id=9; method="tools/call"; params=@{ name=$name; arguments=(Get-ToolArgs $name) } } | ConvertTo-Json -Depth 8)
  try {
    $r = Invoke-WebRequest -Method Post -Uri $GatewayMcpUrl -ContentType "application/json" -Headers $H -Body $body -UseBasicParsing
    $j = ($r.Content -replace '^data: ','' | ConvertFrom-Json)
    if ($j.error) { return "DENIED" } else { return "ALLOWED" }
  } catch { return "DENIED" }
}

# Returns the tenant value echoed by the OpenAPI backend, to prove query-param
# mapping actually reaches the backend (regression guard for the null-tenant bug).
function Get-OpenApiTenant($H) {
  $body = (@{ jsonrpc="2.0"; id=10; method="tools/call"; params=@{ name="openapi_readTickets"; arguments=@{ query=@{ tenant="tenant-a" } } } } | ConvertTo-Json -Depth 8)
  try {
    $r = Invoke-WebRequest -Method Post -Uri $GatewayMcpUrl -ContentType "application/json" -Headers $H -Body $body -UseBasicParsing
    $j = ($r.Content -replace '^data: ','' | ConvertFrom-Json)
    return $j.result.structuredContent.tenant
  } catch { return "<error>" }
}

$reader   = & "$PSScriptRoot\get-keycloak-token.ps1" -BaseUrl $KeycloakUrl -User alice-reader   -Password reader-password
$operator = & "$PSScriptRoot\get-keycloak-token.ps1" -BaseUrl $KeycloakUrl -User oliver-operator -Password operator-password
if (-not $reader -or -not $operator) { Write-Error "RBAC smoke: could not obtain tokens."; exit 1 }

# 1) No token -> 401
try {
  Invoke-WebRequest -Method Post -Uri $GatewayMcpUrl -ContentType "application/json" `
    -Headers @{ Accept = "application/json, text/event-stream" } `
    -Body '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' -UseBasicParsing | Out-Null
  Check "no-token rejected" "200" "401"
} catch { Check "no-token rejected" "$($_.Exception.Response.StatusCode.value__)" "401" }

# 2) Reader: read allowed, write denied
$rh = New-McpSession $reader
Check "reader read  (sqlite_read_incidents)"      (Invoke-Tool $rh "sqlite_read_incidents")      "ALLOWED"
Check "reader read  (openapi_readTickets)"        (Invoke-Tool $rh "openapi_readTickets")        "ALLOWED"
Check "openapi query-param maps to backend"       (Get-OpenApiTenant $rh)                         "tenant-a"
Check "reader write (sqlite_write_incident_note)" (Invoke-Tool $rh "sqlite_write_incident_note") "DENIED"
Check "reader write (http_write_restart_request)" (Invoke-Tool $rh "http_write_restart_request") "DENIED"

# 3) Operator (tenant-b): write allowed
$oh = New-McpSession $operator
Check "operator write (sqlite_write_incident_note)" (Invoke-Tool $oh "sqlite_write_incident_note") "ALLOWED"

if ($fail -eq 0) { Write-Host "`nRBAC smoke test passed." -ForegroundColor Green; exit 0 }
else { Write-Host "`nRBAC smoke test FAILED ($fail check(s))." -ForegroundColor Red; exit 1 }
