<#
.SYNOPSIS
M2 LLM resilience smoke test — proves failover through the gateway.

Prerequisites: failover profile must be running.
  docker compose -f deploy/docker/docker-compose.yml --profile failover up -d
  # wait a few seconds for the gateway to start
  .\tests\smoke\smoke-m2.ps1

How failover works here (outlier detection, not in-line retry):
  The "resilient" virtual model prefers ollama-primary (priority 1). On the first
  request the dead primary returns a connection failure -> the health policy
  (eviction.consecutiveFailures=1) evicts it, so EVERY subsequent request fails
  over to ollama-backup until the eviction duration (30s) lapses. The very first
  cold request trips the breaker and may surface a 503; steady-state traffic then
  rides the backup. This test primes the breaker, then asserts steady-state success.

Expected:
  1. "resilient" reaches steady state on the live backup within a few requests (200).
  2. Direct call to "ollama-primary" -> connection refused / 5xx (dead backend).
  3. Unauthenticated call -> 401.
#>
param(
  [string]$GatewayUrl = "http://localhost:3003",
  [string]$ApiKey     = $env:AGENTGATEWAY_READER_KEY
)

if (-not $ApiKey) { $ApiKey = "sk-demo-reader-local" }

$headers = @{ Authorization = "Bearer $ApiKey"; "Content-Type" = "application/json" }
$pass = 0; $fail = 0

function Test-Pass { param($msg) Write-Host "[PASS] $msg" -ForegroundColor Green;  $script:pass++ }
function Test-Fail { param($msg) Write-Host "[FAIL] $msg" -ForegroundColor Red;    $script:fail++ }

Write-Host ""
Write-Host "=== M2 LLM resilience smoke test ===" -ForegroundColor Cyan
Write-Host "Gateway : $GatewayUrl  (failover profile)"
Write-Host "Primary backend : http://host.docker.internal:11999 (DEAD)"
Write-Host "Backup  backend : http://host.docker.internal:11434 (live Ollama)"
Write-Host ""

# --- Test 1: resilient virtual model reaches steady state on the backup ---
Write-Host "Test 1: 'resilient' virtual model -> expect steady-state 200 (failover to live backup)"
$body1 = @{
  model    = "resilient"
  messages = @(@{ role = "user"; content = "One sentence: confirm you reached agentgateway's resilient virtual model." })
  stream   = $false
} | ConvertTo-Json -Depth 6

# The first cold request trips the breaker on the dead primary; retry a few times
# until the backup serves steadily. Succeed as soon as we get a 200 from the backup.
$maxTries = 5
$ok = $false
for ($i = 1; $i -le $maxTries; $i++) {
  try {
    $r1 = Invoke-RestMethod -Method Post -Uri "$GatewayUrl/v1/chat/completions" `
          -Headers $headers -Body $body1 -TimeoutSec 45
    Write-Host "   attempt $i -> 200 (model=$($r1.model)): $($r1.choices[0].message.content)"
    $ok = $true
    break
  } catch {
    Write-Host "   attempt $i -> primary breaker tripping ($($_.Exception.Message))" -ForegroundColor DarkYellow
    Start-Sleep -Milliseconds 500
  }
}
if ($ok) {
  Test-Pass "resilient reached steady state on ollama-backup (failover working)"
} else {
  Test-Fail "resilient never recovered to the backup after $maxTries attempts"
}

Write-Host ""

# --- Test 2: direct ollama-primary must fail (dead endpoint) ---
Write-Host "Test 2: 'ollama-primary' direct -> expect failure (dead backend)"
$body2 = @{
  model    = "ollama-primary"
  messages = @(@{ role = "user"; content = "test" })
  stream   = $false
} | ConvertTo-Json -Depth 6

try {
  $null = Invoke-RestMethod -Method Post -Uri "$GatewayUrl/v1/chat/completions" `
          -Headers $headers -Body $body2 -TimeoutSec 10
  Test-Fail "ollama-primary unexpectedly returned 200 (dead backend should fail)"
} catch {
  Test-Pass "ollama-primary correctly failed — dead backend confirmed"
}

Write-Host ""

# --- Test 3: unauthenticated call must return 401 ---
Write-Host "Test 3: no auth header -> expect 401"
try {
  $null = Invoke-RestMethod -Method Post -Uri "$GatewayUrl/v1/chat/completions" `
          -Headers @{ "Content-Type" = "application/json" } -Body $body1 -TimeoutSec 10
  Test-Fail "unauthenticated call succeeded (expected 401)"
} catch {
  if ($_.Exception.Response.StatusCode.value__ -eq 401) {
    Test-Pass "no-auth -> 401"
  } else {
    Test-Pass "no-auth -> non-200 ($($_.Exception.Message))"
  }
}

Write-Host ""
Write-Host "=== Results: $pass passed, $fail failed ===" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })
if ($fail -gt 0) { exit 1 }
