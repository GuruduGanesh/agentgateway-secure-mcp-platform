param(
  [string]$GatewayUrl = "http://localhost:3000",
  [string]$ApiKey = $env:AGENTGATEWAY_READER_KEY,
  [string]$PrometheusUrl = "http://localhost:9090",
  [string]$GrafanaUrl = "http://localhost:3001",
  [string]$GrafanaUser = $env:GRAFANA_ADMIN_USER,
  [string]$GrafanaPassword = $env:GRAFANA_ADMIN_PASSWORD,
  [string]$JaegerUrl = "http://localhost:16686"
)

# M5 verifies a request is observed end-to-end, not just that the three UIs load.
$ErrorActionPreference = "Stop"
if (-not $ApiKey) { $ApiKey = "sk-demo-reader-local" }
if (-not $GrafanaUser) { $GrafanaUser = "admin" }
if (-not $GrafanaPassword) { $GrafanaPassword = "admin" }

try {
  $targets = Invoke-RestMethod -Uri "$PrometheusUrl/api/v1/targets"
  $gatewayTarget = @($targets.data.activeTargets | Where-Object { $_.labels.job -eq "agentgateway" -and $_.health -eq "up" })
  if ($gatewayTarget.Count -eq 0) { throw "Prometheus has no healthy agentgateway target" }

  $body = @{ model="laptop-demo"; messages=@(@{role="user";content="Generate one observability smoke request."}); stream=$false } | ConvertTo-Json -Depth 6
  $completion = Invoke-RestMethod -Method Post -Uri "$GatewayUrl/v1/chat/completions" `
    -Headers @{ Authorization = "Bearer $ApiKey" } -ContentType "application/json" -Body $body -TimeoutSec 60
  if (-not $completion.choices[0].message.content) { throw "Gateway did not return a completion" }

  Start-Sleep -Seconds 3
  $metric = Invoke-RestMethod -Uri "$PrometheusUrl/api/v1/query?query=agentgateway_requests_total"
  if (@($metric.data.result).Count -eq 0) { throw "agentgateway_requests_total is absent after the request" }

  $services = Invoke-RestMethod -Uri "$JaegerUrl/api/services"
  if ("agentgateway" -notin @($services.data)) { throw "Jaeger does not report the agentgateway service" }

  Invoke-WebRequest -Uri "$GrafanaUrl/api/health" -UseBasicParsing | Out-Null
  $grafanaAuth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${GrafanaUser}:${GrafanaPassword}"))
  $dashboards = Invoke-RestMethod -Uri "$GrafanaUrl/api/search?query=agentgateway" -Headers @{ Authorization = "Basic $grafanaAuth" }
  if (@($dashboards | Where-Object { $_.title -eq "agentgateway Secure MCP Local Demo" }).Count -eq 0) {
    throw "Grafana does not contain the provisioned agentgateway Secure MCP Local Demo dashboard"
  }

  Write-Host "Observability smoke test passed: healthy scrape target, gateway metric, Jaeger service, Grafana health, and provisioned dashboard." -ForegroundColor Green
} catch {
  Write-Error "Observability smoke test failed: $($_.Exception.Message)"
  exit 1
}
