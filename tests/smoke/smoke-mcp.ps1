param(
  [string]$KeycloakUrl = "http://localhost:8080",
  [string]$GatewayMcpUrl = "http://localhost:3002/mcp"
)

# M3 gateway federation smoke. The tool backends deliberately have no host ports;
# this verifies the HTTP MCP target through the authenticated gateway boundary.
$ErrorActionPreference = "Stop"

function ConvertFrom-McpResponse($content) {
  $text = [string]$content
  $data = [regex]::Matches($text, '(?m)^data:\s?(.*)$') | ForEach-Object { $_.Groups[1].Value }
  if ($data.Count -gt 0) { $text = $data -join "`n" }
  if ([string]::IsNullOrWhiteSpace($text)) { throw "MCP response body was empty" }
  return $text | ConvertFrom-Json
}

function Invoke-McpRequest($headers, $body) {
  $response = Invoke-WebRequest -Method Post -Uri $GatewayMcpUrl -ContentType "application/json" `
    -Headers $headers -Body $body -UseBasicParsing -ErrorAction Stop
  return @{ Headers = $response.Headers; Json = (ConvertFrom-McpResponse $response.Content) }
}

try {
  $token = & "$PSScriptRoot\get-keycloak-token.ps1" -BaseUrl $KeycloakUrl -User oliver-operator -Password operator-password
  if (-not $token) { throw "Could not obtain the operator token" }

  $headers = @{ Authorization = "Bearer $token"; Accept = "application/json, text/event-stream" }
  $initialize = @{ jsonrpc="2.0"; id=1; method="initialize"; params=@{ protocolVersion="2025-06-18"; capabilities=@{}; clientInfo=@{ name="smoke-mcp"; version="1.0" } } } | ConvertTo-Json -Depth 8
  $session = Invoke-McpRequest $headers $initialize
  if ($session.Json.error) { throw "MCP initialize failed: $($session.Json.error | ConvertTo-Json -Compress)" }
  $sessionId = ([string[]]$session.Headers["Mcp-Session-Id"])[0]
  if (-not $sessionId) { throw "MCP initialize did not return Mcp-Session-Id" }
  $headers["Mcp-Session-Id"] = $sessionId

  $list = Invoke-McpRequest $headers '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
  $tools = @($list.Json.result.tools | ForEach-Object { $_.name })
  $expected = @(
    "tenant-b-sqlite_read_incidents", "tenant-b-sqlite_write_incident_note",
    "tenant-b-http_read_service_health", "tenant-b-http_write_restart_request",
    "tenant-b-openapi_readTickets", "tenant-b-openapi_writeTicket"
  )
  if ($tools.Count -ne 6 -or @($expected | Where-Object { $_ -notin $tools }).Count -ne 0) {
    throw "Unexpected operator tool set: $($tools -join ', ')"
  }

  $call = Invoke-McpRequest $headers '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"tenant-b-http_read_service_health","arguments":{}}}'
  if ($call.Json.error) { throw "HTTP MCP tool call failed: $($call.Json.error | ConvertTo-Json -Compress)" }
  $result = $call.Json.result.content[0].text | ConvertFrom-Json
  if ($result.tenant -ne "tenant-b" -or $result.status -ne "healthy") { throw "Unexpected HTTP MCP result: $($result | ConvertTo-Json -Compress)" }

  Write-Host "MCP gateway federation smoke test passed." -ForegroundColor Green
} catch {
  Write-Error "MCP gateway federation smoke test failed: $($_.Exception.Message)"
  exit 1
}
