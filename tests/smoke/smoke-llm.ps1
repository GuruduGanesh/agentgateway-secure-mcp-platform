param(
  [string]$GatewayUrl = "http://localhost:3000",
  [string]$Model = $env:LAPTOP_MODEL_ALIAS,
  [string]$ApiKey = $env:AGENTGATEWAY_READER_KEY
)

if (-not $Model) {
  $Model = "laptop-demo"
}

if (-not $ApiKey) {
  $ApiKey = "sk-demo-reader-local"
}

$body = @{
  model = $Model
  messages = @(
    @{ role = "system"; content = "You are a concise local demo assistant." },
    @{ role = "user"; content = "Reply with one sentence confirming this went through agentgateway to local Ollama." }
  )
  stream = $false
} | ConvertTo-Json -Depth 6

Write-Host "POST $GatewayUrl/v1/chat/completions"
try {
  $headers = @{ Authorization = "Bearer $ApiKey" }
  $response = Invoke-RestMethod -Method Post -Uri "$GatewayUrl/v1/chat/completions" -Headers $headers -ContentType "application/json" -Body $body
  $response | ConvertTo-Json -Depth 8
  Write-Host "LLM smoke test passed." -ForegroundColor Green
} catch {
  Write-Error "LLM smoke test failed: $($_.Exception.Message)"
  exit 1
}
