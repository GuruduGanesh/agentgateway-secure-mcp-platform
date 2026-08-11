<#
.SYNOPSIS
M2 LLM resilience smoke test. It proves cross-request failover through the
gateway after the dead primary is evicted by its health policy.

.NOTES
Start the required local services first:
  docker compose --env-file .env -f deploy/docker/docker-compose.yml --profile failover --profile observability up -d
#>
param(
  [string]$GatewayUrl = "http://localhost:3003",
  [string]$ApiKey = $env:AGENTGATEWAY_READER_KEY
)

$ErrorActionPreference = "Stop"
if (-not $ApiKey) { $ApiKey = "sk-demo-reader-local" }
$headers = @{ Authorization = "Bearer $ApiKey"; "Content-Type" = "application/json" }
$pass = 0
$fail = 0

function Pass($message) {
  Write-Host "PASS  $message" -ForegroundColor Green
  $script:pass++
}

function Fail($message) {
  Write-Host "FAIL  $message" -ForegroundColor Red
  $script:fail++
}

function New-ChatBody($model, $content) {
  return (@{
    model = $model
    messages = @(@{ role = "user"; content = $content })
    stream = $false
  } | ConvertTo-Json -Depth 6)
}

Write-Host "M2 LLM resilience smoke test" -ForegroundColor Cyan
Write-Host "Gateway: $GatewayUrl"

# The first request may surface the dead primary while the health policy evicts
# it. Subsequent requests must reach the configured backup.
$resilientBody = New-ChatBody "resilient" "Confirm the resilient virtual model."
$backupReached = $false
for ($attempt = 1; $attempt -le 5; $attempt++) {
  try {
    $response = Invoke-RestMethod -Method Post -Uri "$GatewayUrl/v1/chat/completions" -Headers $headers -Body $resilientBody -TimeoutSec 45
    if ($response.choices[0].message.content) {
      Write-Host "  attempt $attempt returned a completion from $($response.model)"
      $backupReached = $true
      break
    }
  } catch {
    Write-Host "  attempt $attempt tripped or observed the dead primary" -ForegroundColor DarkYellow
    Start-Sleep -Milliseconds 500
  }
}
if ($backupReached) { Pass "resilient model reached the live backup" }
else { Fail "resilient model did not reach the backup within five attempts" }

# A direct route to the intentionally dead primary must not return success.
try {
  $null = Invoke-RestMethod -Method Post -Uri "$GatewayUrl/v1/chat/completions" -Headers $headers -Body (New-ChatBody "ollama-primary" "test") -TimeoutSec 10
  Fail "dead primary unexpectedly returned success"
} catch {
  Pass "direct dead primary request failed"
}

# The external authentication boundary remains active on the resilience route.
try {
  $null = Invoke-RestMethod -Method Post -Uri "$GatewayUrl/v1/chat/completions" -Headers @{ "Content-Type" = "application/json" } -Body $resilientBody -TimeoutSec 10
  Fail "unauthenticated request unexpectedly returned success"
} catch {
  if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 401) {
    Pass "unauthenticated request returned 401"
  } else {
    Fail "unauthenticated request did not return 401"
  }
}

if ($fail -eq 0) {
  Write-Host "M2 smoke test passed: $pass checks." -ForegroundColor Green
  exit 0
}
Write-Host "M2 smoke test failed: $fail check(s)." -ForegroundColor Red
exit 1
