<#
.SYNOPSIS
  One-click local demo launcher for the agentgateway secure-MCP platform.
  Brings up the whole local stack, handles the Keycloak/JWKS boot race,
  optionally sets up the Kubernetes promotion and runs the smoke tests,
  then prints the high-level demo steps, URLs, and credentials.

.EXAMPLE
  pwsh ./demo.ps1                  # bring up the Docker demo + print the guide
  pwsh ./demo.ps1 -Verify         # also run the smoke tests to prove each milestone
  pwsh ./demo.ps1 -WithKubernetes # also set up the kind/Helm M6 promotion
  pwsh ./demo.ps1 -Down           # tear everything down (Docker + kind)
#>
[CmdletBinding()]
param(
  [switch]$Verify,
  [switch]$WithKubernetes,
  [switch]$Down
)

$ErrorActionPreference = "Stop"
$Root        = $PSScriptRoot
$Compose     = @("compose", "-f", (Join-Path $Root "deploy/docker/docker-compose.yml"))
$Profiles    = @("--profile","observability","--profile","laptop","--profile","security","--profile","failover")
$KindCluster = "agentgateway-secure-mcp"

function Section($t) { Write-Host ""; Write-Host "===== $t =====" -ForegroundColor Cyan }
function Step($t)    { Write-Host "  -> $t" -ForegroundColor Gray }
function Ok($t)      { Write-Host "  [ok] $t" -ForegroundColor Green }
function Warn($t)    { Write-Host "  [! ] $t" -ForegroundColor Yellow }
function Bad($t)     { Write-Host "  [x ] $t" -ForegroundColor Red }
function Invoke-Compose { param([string[]]$A) & docker @Compose @A }

Write-Host ""
Write-Host "  agentgateway secure-MCP platform - local demo launcher" -ForegroundColor White

# ---------------------------------------------------------------- teardown ----
if ($Down) {
  Section "Tearing down"
  Step "stopping Docker profiles"
  Invoke-Compose ($Profiles + @("down")) | Out-Null
  Ok "Docker profiles down"
  if (kind get clusters 2>$null | Select-String -SimpleMatch $KindCluster) {
    Step "deleting kind cluster"
    kind delete cluster --name $KindCluster | Out-Null
    Ok "kind cluster deleted"
  }
  Write-Host ""
  Ok "Everything is torn down."
  return
}

# -------------------------------------------------------------- pre-flight ----
Section "Pre-flight checks"
try { docker version --format '{{.Server.Version}}' | Out-Null; Ok "Docker daemon reachable" }
catch { Bad "Docker daemon not reachable - start Docker Desktop and retry"; exit 1 }

if (-not (Test-Path (Join-Path $Root ".env"))) {
  Copy-Item (Join-Path $Root ".env.example") (Join-Path $Root ".env")
  Ok ".env created from .env.example"
} else { Ok ".env present" }

try {
  $models = (Invoke-RestMethod "http://localhost:11434/api/tags" -TimeoutSec 5).models.name
  if ($models -contains "llama3.2:3b") { Ok "Ollama up, llama3.2:3b present" }
  else { Warn "llama3.2:3b missing - pulling it now (one-time)"; ollama pull llama3.2:3b; Ok "model pulled" }
} catch { Bad "Ollama not reachable at :11434 - start Ollama on the host and retry"; exit 1 }

# ------------------------------------------------------------ start stack ----
Section "Starting the local stack (Docker)"
Step "compose up: observability + laptop + security + failover"
Invoke-Compose ($Profiles + @("up","-d")) | Out-Null
Ok "containers started"

# --------------------------------------------------- identity + secure MCP ----
Section "Identity (Keycloak) + secure MCP gateway"
Step "waiting for the agentgateway realm to import..."
$ready = $false
foreach ($i in 1..40) {
  try { if ((Invoke-RestMethod "http://localhost:8080/realms/agentgateway/.well-known/openid-configuration" -TimeoutSec 3).issuer) { $ready = $true; break } }
  catch { Start-Sleep 3 }
}
if ($ready) { Ok "Keycloak realm ready" } else { Warn "Keycloak not ready yet - the RBAC step may need another minute" }

Step "restarting agentgateway-mcp-secure (handles the JWKS-at-boot race)"
Invoke-Compose ($Profiles + @("up","-d","agentgateway-mcp-secure")) | Out-Null
Start-Sleep 4
Ok "secure MCP gateway running"

# ------------------------------------------------------- LLM gateway ready ----
Section "LLM gateway readiness"
$llmOk = $false
foreach ($i in 1..15) {
  try {
    Invoke-RestMethod -Method Post "http://localhost:3000/v1/chat/completions" `
      -Headers @{ Authorization = "Bearer sk-demo-reader-local" } -ContentType "application/json" `
      -Body '{"model":"laptop-demo","messages":[{"role":"user","content":"hi"}],"stream":false}' -TimeoutSec 20 | Out-Null
    $llmOk = $true; break
  } catch { Start-Sleep 2 }
}
if ($llmOk) { Ok "LLM gateway answering on :3000" } else { Warn "LLM gateway not answering yet - give it a few more seconds" }

# ------------------------------------------------------- kubernetes (opt) ----
if ($WithKubernetes) {
  Section "Kubernetes promotion (kind + Helm) - this takes a few minutes"
  if (kind get clusters 2>$null | Select-String -SimpleMatch $KindCluster) { Ok "kind cluster already exists" }
  else { Step "creating kind cluster"; kind create cluster --config (Join-Path $Root "deploy/kubernetes/kind/kind-cluster.yaml") | Out-Null; Ok "kind cluster created" }
  Step "installing Gateway API + agentgateway and running the in-cluster E2E call"
  & (Join-Path $Root "tests/smoke/smoke-k8s.ps1") -Apply -E2E
  Ok "Kubernetes promotion ready"
}

# ----------------------------------------------------------- verify (opt) ----
if ($Verify) {
  Section "Verifying milestones (smoke tests)"
  Write-Host "--- M1 LLM ---"          -ForegroundColor DarkCyan; & (Join-Path $Root "tests/smoke/smoke-llm.ps1")
  Write-Host "--- M5 observability ---" -ForegroundColor DarkCyan; & (Join-Path $Root "tests/smoke/smoke-observability.ps1")
  Write-Host "--- M4 RBAC ---"          -ForegroundColor DarkCyan; & (Join-Path $Root "tests/smoke/smoke-rbac.ps1")
  Write-Host "--- M2 failover ---"      -ForegroundColor DarkCyan; & (Join-Path $Root "tests/smoke/smoke-m2.ps1")
  if ($WithKubernetes) { Write-Host "--- M6 Kubernetes ---" -ForegroundColor DarkCyan; & (Join-Path $Root "tests/smoke/smoke-k8s.ps1") -E2E }
}

# --------------------------------------------------------------- summary ----
Section "Demo is ready"

Write-Host ""
Write-Host "  URLs" -ForegroundColor White
Write-Host "    LLM gateway (M1/M2)      http://localhost:3000/v1/chat/completions"
Write-Host "    Secure MCP gateway (M3/M4) http://localhost:3002/mcp"
Write-Host "    Failover gateway (M2)    http://localhost:3003/v1/chat/completions"
Write-Host "    Gateway metrics          http://localhost:15020/metrics"
Write-Host "    Prometheus               http://localhost:9090   (Status > Targets)"
Write-Host "    Grafana                  http://localhost:3001   (admin / admin)"
Write-Host "    Jaeger                   http://localhost:16686  (service: agentgateway)"
Write-Host "    Keycloak                 http://localhost:8080   (admin / admin)"

Write-Host ""
Write-Host "  Demo credentials" -ForegroundColor White
Write-Host "    API keys   sk-demo-reader-local , sk-demo-operator-local"
Write-Host "    reader     alice-reader / reader-password    (tenant-a, role reader)"
Write-Host "    operator   oliver-operator / operator-password (tenant-b, role operator)"

Write-Host ""
Write-Host "  High-level demo flow (full talk track: docs/demo/DEMO.md)" -ForegroundColor White
Write-Host "    1. M1  Standalone LLM gateway  - no key -> 401, valid key -> real completion"
Write-Host "    2. M5  Observability           - Prometheus target UP, Grafana dashboard, Jaeger traces"
Write-Host "    3. M3  MCP federation          - one endpoint, 6 prefixed tools (sqlite_/http_/openapi_)"
Write-Host "    4. M4  Security / RBAC         - reader vs operator, tenant-scoped, least privilege"
Write-Host "    5. M2  LLM failover            - dead primary -> live backup via health.eviction"
Write-Host "    6. M6  Kubernetes promotion    - same gateway as Gateway API + agentgateway CRDs on kind"

Write-Host ""
Write-Host "  Prove each milestone (smoke tests)" -ForegroundColor White
Write-Host "    .\tests\smoke\smoke-llm.ps1            # M1"
Write-Host "    .\tests\smoke\smoke-observability.ps1  # M5"
Write-Host "    .\tests\smoke\smoke-rbac.ps1           # M3 + M4 (7/7)"
Write-Host "    .\tests\smoke\smoke-m2.ps1             # M2 (3/3)"
Write-Host "    .\tests\smoke\smoke-k8s.ps1 -E2E       # M6 (needs -WithKubernetes setup)"

Write-Host ""
Write-Host "  Tear down when done:  pwsh ./demo.ps1 -Down" -ForegroundColor White
Write-Host ""
