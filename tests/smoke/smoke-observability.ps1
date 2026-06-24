param(
  [string]$PrometheusUrl = "http://localhost:9090",
  [string]$GrafanaUrl = "http://localhost:3001",
  [string]$JaegerUrl = "http://localhost:16686"
)

try {
  Invoke-RestMethod -Uri "$PrometheusUrl/-/ready" | Out-Null
  Invoke-WebRequest -Uri "$GrafanaUrl/api/health" -UseBasicParsing | Out-Null
  Invoke-WebRequest -Uri "$JaegerUrl/" -UseBasicParsing | Out-Null
  Write-Host "Observability smoke test passed." -ForegroundColor Green
} catch {
  Write-Error "Observability smoke test failed: $($_.Exception.Message)"
  exit 1
}
