param(
  [string]$KeycloakUrl = "http://localhost:8080",
  [string]$GatewayMcpUrl = "http://localhost:3002/mcp"
)

# End-to-end MCP authorization and tenant-isolation check through agentgateway.
# Every assertion distinguishes a JSON-RPC policy rejection from a transport,
# gateway, or response-parsing failure so an outage cannot produce a false pass.

$ErrorActionPreference = "Stop"
$fail = 0

function Check($label, [bool]$ok, $details) {
  if ($ok) { Write-Host "PASS  $label" -ForegroundColor Green }
  else { Write-Host "FAIL  $label ($details)" -ForegroundColor Red; $script:fail++ }
}

function ConvertFrom-McpResponse($content) {
  $text = [string]$content
  $dataLines = [regex]::Matches($text, '(?m)^data:\s?(.*)$') |
    ForEach-Object { $_.Groups[1].Value }
  if ($dataLines.Count -gt 0) { $text = $dataLines -join "`n" }
  if ([string]::IsNullOrWhiteSpace($text)) { throw "MCP response body was empty" }
  return ($text | ConvertFrom-Json)
}

function Invoke-McpRequest($headers, $body) {
  try {
    $r = Invoke-WebRequest -Method Post -Uri $GatewayMcpUrl -ContentType "application/json" `
      -Headers $headers -Body $body -UseBasicParsing -ErrorAction Stop
    return @{ StatusCode = [int]$r.StatusCode; Headers = $r.Headers; Json = (ConvertFrom-McpResponse $r.Content) }
  } catch {
    # Preserve expected HTTP error responses for assertion in both Windows
    # PowerShell 5.1 (WebException) and PowerShell 7 (HttpResponseException).
    # Re-throw genuine connection failures rather than treating them as denials.
    $httpResponse = $_.Exception.Response
    if (-not $httpResponse) { throw }
    $content = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { "" }
    if ([string]::IsNullOrWhiteSpace($content) -and ($httpResponse.PSObject.Properties.Name -contains "Content")) {
      $content = $httpResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    } elseif ([string]::IsNullOrWhiteSpace($content)) {
      $reader = New-Object System.IO.StreamReader($httpResponse.GetResponseStream())
      $content = $reader.ReadToEnd()
      $reader.Dispose()
    }
    $json = if ([string]::IsNullOrWhiteSpace($content)) { $null } else { ConvertFrom-McpResponse $content }
    return @{ StatusCode = [int]$httpResponse.StatusCode; Headers = $httpResponse.Headers; Json = $json }
  }
}

function New-McpSession($token, $clientName) {
  $headers = @{ Authorization = "Bearer $token"; Accept = "application/json, text/event-stream" }
  $body = (@{ jsonrpc="2.0"; id=1; method="initialize"; params=@{ protocolVersion="2025-06-18"; capabilities=@{}; clientInfo=@{ name=$clientName; version="1.0" } } } | ConvertTo-Json -Depth 8)
  $response = Invoke-McpRequest $headers $body
  if ($response.StatusCode -ne 200 -or $response.Json.error) { throw "MCP initialize failed: HTTP $($response.StatusCode) $($response.Json.error | ConvertTo-Json -Compress)" }
  $sessionId = ([string[]]$response.Headers["Mcp-Session-Id"])[0]
  if (-not $sessionId) { throw "MCP initialize did not return Mcp-Session-Id" }
  return @{ Authorization = "Bearer $token"; Accept = "application/json, text/event-stream"; "Mcp-Session-Id" = $sessionId }
}

function Get-Tools($headers) {
  $body = '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
  $response = Invoke-McpRequest $headers $body
  if ($response.StatusCode -ne 200 -or $response.Json.error) { throw "tools/list failed: HTTP $($response.StatusCode) $($response.Json.error | ConvertTo-Json -Compress)" }
  return @($response.Json.result.tools | ForEach-Object { [string]$_.name })
}

function Get-ToolArgs($name) {
  if ($name -match 'write_incident_note$') { return @{ note = "local smoke note" } }
  if ($name -match 'write_restart_request$') { return @{ service = "payments" } }
  if ($name -match 'writeTicket$') { return @{ message = "local smoke ticket" } }
  return @{}
}

function Invoke-Tool($headers, $name) {
  $body = (@{ jsonrpc="2.0"; id=9; method="tools/call"; params=@{ name=$name; arguments=(Get-ToolArgs $name) } } | ConvertTo-Json -Depth 8)
  return Invoke-McpRequest $headers $body
}

function Check-Allowed($label, $response) {
  Check $label ($response.StatusCode -eq 200 -and -not $response.Json.error) "HTTP $($response.StatusCode); error=$($response.Json.error | ConvertTo-Json -Compress)"
}

function Check-Rejected($label, $response) {
  # agentgateway intentionally hides filtered tools as an MCP "Unknown tool"
  # JSON-RPC error. This is a policy rejection, not a transport failure.
  $isJsonRpcError = $null -ne $response.Json.error -and $response.Json.error.code -eq -32602
  Check $label $isJsonRpcError "HTTP $($response.StatusCode); error=$($response.Json.error | ConvertTo-Json -Compress)"
}

function Check-ExactTools($label, $tools, [string[]]$expectedTools) {
  $actual = @($tools | Sort-Object -Unique)
  $expected = @($expectedTools | Sort-Object -Unique)
  $matches = $actual.Count -eq $expected.Count -and -not (Compare-Object -ReferenceObject $expected -DifferenceObject $actual)
  Check $label $matches "actual=$($actual -join ', '); expected=$($expected -join ', ')"
}

$readerA = & "$PSScriptRoot\get-keycloak-token.ps1" -BaseUrl $KeycloakUrl -User alice-reader   -Password reader-password
$readerB = & "$PSScriptRoot\get-keycloak-token.ps1" -BaseUrl $KeycloakUrl -User brenda-reader  -Password reader-password
$operatorB = & "$PSScriptRoot\get-keycloak-token.ps1" -BaseUrl $KeycloakUrl -User oliver-operator -Password operator-password
if (-not $readerA -or -not $readerB -or -not $operatorB) { Write-Error "RBAC smoke: could not obtain all test tokens."; exit 1 }

# 1) No token -> 401
$anonymous = Invoke-McpRequest @{ Accept = "application/json, text/event-stream" } '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
Check "no-token rejected with HTTP 401" ($anonymous.StatusCode -eq 401) "HTTP $($anonymous.StatusCode)"

# 2) Reader A may use only tenant-a read tools. Its tenant-b resources and its
# own write tools are filtered from tools/list and rejected on direct call.
$readerAHeaders = New-McpSession $readerA "smoke-reader-a"
$readerATools = Get-Tools $readerAHeaders
Check-ExactTools "reader-a sees exactly the tenant-a read tools" $readerATools @("tenant-a-sqlite_read_incidents", "tenant-a-http_read_service_health", "tenant-a-openapi_readTickets")
$readerARead = Invoke-Tool $readerAHeaders "tenant-a-sqlite_read_incidents"
Check-Allowed "reader-a reads tenant-a incidents" $readerARead
if ($readerARead.StatusCode -eq 200 -and -not $readerARead.Json.error) {
  $readerAData = $readerARead.Json.result.content[0].text | ConvertFrom-Json
  Check "reader-a backend result is tenant-a" ($readerAData.tenant -eq "tenant-a") "tenant=$($readerAData.tenant)"
} else {
  Check "reader-a backend result is tenant-a" $false "the allowed tool call did not succeed"
}
Check-Rejected "reader-a cross-tenant read is rejected" (Invoke-Tool $readerAHeaders "tenant-b-sqlite_read_incidents")
Check-Rejected "reader-a write is rejected" (Invoke-Tool $readerAHeaders "tenant-a-sqlite_write_incident_note")

# 3) Reader B has the same role but independently receives only tenant-b tools.
$readerBHeaders = New-McpSession $readerB "smoke-reader-b"
$readerBTools = Get-Tools $readerBHeaders
Check-ExactTools "reader-b sees exactly the tenant-b read tools" $readerBTools @("tenant-b-sqlite_read_incidents", "tenant-b-http_read_service_health", "tenant-b-openapi_readTickets")
$readerBRead = Invoke-Tool $readerBHeaders "tenant-b-openapi_readTickets"
Check-Allowed "reader-b reads tenant-b tickets" $readerBRead
if ($readerBRead.StatusCode -eq 200 -and -not $readerBRead.Json.error) {
  Check "reader-b backend result is tenant-b" ($readerBRead.Json.result.structuredContent.tenant -eq "tenant-b") "tenant=$($readerBRead.Json.result.structuredContent.tenant)"
} else {
  Check "reader-b backend result is tenant-b" $false "the allowed tool call did not succeed"
}
Check-Rejected "reader-b cross-tenant read is rejected" (Invoke-Tool $readerBHeaders "tenant-a-openapi_readTickets")

# 4) Operator B sees the six tenant-b tools and can write only inside tenant-b.
$operatorBHeaders = New-McpSession $operatorB "smoke-operator-b"
$operatorBTools = Get-Tools $operatorBHeaders
Check-ExactTools "operator-b sees exactly the tenant-b tools" $operatorBTools @("tenant-b-sqlite_read_incidents", "tenant-b-sqlite_write_incident_note", "tenant-b-http_read_service_health", "tenant-b-http_write_restart_request", "tenant-b-openapi_readTickets", "tenant-b-openapi_writeTicket")
Check-Allowed "operator-b writes tenant-b incident note" (Invoke-Tool $operatorBHeaders "tenant-b-sqlite_write_incident_note")
Check-Rejected "operator-b cross-tenant write is rejected" (Invoke-Tool $operatorBHeaders "tenant-a-sqlite_write_incident_note")

if ($fail -eq 0) { Write-Host "`nRBAC tenant-isolation smoke test passed." -ForegroundColor Green; exit 0 }
else { Write-Host "`nRBAC tenant-isolation smoke test FAILED ($fail check(s))." -ForegroundColor Red; exit 1 }
