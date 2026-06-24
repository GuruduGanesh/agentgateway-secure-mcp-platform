param(
  [string]$HttpToolsUrl = "http://localhost:7001/mcp",
  [string]$OpenApiUrl = "http://localhost:7002"
)

Write-Host "Checking HTTP MCP demo server at $HttpToolsUrl"
$listBody = @{
  jsonrpc = "2.0"
  id = 1
  method = "tools/list"
} | ConvertTo-Json -Depth 5

try {
  $tools = Invoke-RestMethod -Method Post -Uri $HttpToolsUrl -ContentType "application/json" -Body $listBody
  $tools | ConvertTo-Json -Depth 8
  Invoke-RestMethod -Method Get -Uri "$OpenApiUrl/healthz" | ConvertTo-Json
  Write-Host "MCP sample smoke test passed." -ForegroundColor Green
} catch {
  Write-Error "MCP sample smoke test failed: $($_.Exception.Message)"
  exit 1
}
