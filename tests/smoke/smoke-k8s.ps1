<#
.SYNOPSIS
M6 Kubernetes smoke test — verifies the agentgateway control plane + Gateway API
resources are healthy on the local kind cluster, then drives a real LLM call
through the in-cluster gateway to host Ollama.

.PARAMETER Apply
  Install Gateway API CRDs, the agentgateway Helm charts, and apply the manifests
  before checking. Omit to only check (assumes already installed).

.PARAMETER E2E
  Port-forward the data-plane service and send a chat completion through it.

Prereqs: kind cluster up (deploy/kubernetes/kind/kind-cluster.yaml), kubectl
context = kind-agentgateway-secure-mcp, Ollama serving llama3.2:3b on the host.
#>
param(
  [switch]$Apply,
  [switch]$E2E
)

$ns = "agentgateway-demo"
$sys = "agentgateway-system"

function Get-ConditionStatus($kind, $name, $conditionType) {
  $resource = kubectl -n $ns get $kind $name -o json | ConvertFrom-Json
  $conditions = $resource.status.conditions
  if (-not $conditions -and $resource.status.ancestors) {
    $conditions = $resource.status.ancestors[0].conditions
  }
  return [string](($conditions | Where-Object { $_.type -eq $conditionType } | Select-Object -First 1).status)
}

if ($Apply) {
  kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml
  helm upgrade --install agentgateway-crds oci://cr.agentgateway.dev/charts/agentgateway-crds --version v1.4.0 -n $sys --create-namespace
  helm upgrade --install agentgateway     oci://cr.agentgateway.dev/charts/agentgateway      --version v1.4.0 -n $sys -f deploy/kubernetes/helm/values.yaml
  kubectl apply -f deploy/kubernetes/manifests/

  # The control plane needs a moment to roll out and program the Gateway. Without
  # this wait, a fresh -Apply checks status too early and reports "not Programmed".
  Write-Host "Waiting for control plane rollout + Gateway Programmed..." -ForegroundColor Cyan
  kubectl -n $sys rollout status deploy/agentgateway --timeout=180s
  foreach ($i in 1..30) {
    $p = Get-ConditionStatus "gateway" "local-agentgateway" "Programmed"
    if ($p -eq "True") { break }
    Start-Sleep 4
  }
}

Write-Host "=== Control plane + Gateway API state ===" -ForegroundColor Cyan
kubectl get crd gateways.gateway.networking.k8s.io | Out-Null
kubectl get gatewayclass agentgateway
kubectl -n $sys get pods
kubectl -n $ns get gateway,httproute,agentgatewaybackend,agentgatewaypolicy

# Assert the Gateway is Programmed and the backend/policy are accepted.
$prog = Get-ConditionStatus "gateway" "local-agentgateway" "Programmed"
$acc = Get-ConditionStatus "agentgatewaybackend" "ollama-local" "Accepted"
$policyAccepted = Get-ConditionStatus "agentgatewaypolicy" "local-security-observability" "Accepted"
$policyAttached = Get-ConditionStatus "agentgatewaypolicy" "local-security-observability" "Attached"
Write-Host "Gateway Programmed = $prog ; Backend Accepted = $acc ; Policy Accepted/Attached = $policyAccepted/$policyAttached"
if ($prog -ne "True") { Write-Error "Gateway not Programmed"; exit 1 }
if ($acc -ne "True") { Write-Error "AgentgatewayBackend not Accepted"; exit 1 }
if ($policyAccepted -ne "True" -or $policyAttached -ne "True") { Write-Error "AgentgatewayPolicy not Accepted and Attached"; exit 1 }

if ($E2E) {
  Write-Host "=== End-to-end LLM call through the cluster ===" -ForegroundColor Cyan
  # kind has no cloud LoadBalancer, so port-forward the data-plane service.
  $job = Start-Job { kubectl -n agentgateway-demo port-forward svc/local-agentgateway 8088:80 }
  try {
    Start-Sleep 5
    $body = @{ model="llama3.2:3b"; messages=@(@{role="user";content="One short sentence confirming this went through agentgateway on Kubernetes."}); stream=$false } | ConvertTo-Json -Depth 6
    $r = Invoke-RestMethod -Method Post -Uri "http://localhost:8088/v1/chat/completions" -ContentType "application/json" -Body $body -TimeoutSec 60
    Write-Host "E2E -> 200 (model=$($r.model)): $($r.choices[0].message.content)" -ForegroundColor Green
  } catch {
    Write-Error "E2E call failed: $($_.Exception.Message)"
    Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue
    exit 1
  }
  Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue
}

Write-Host "Kubernetes smoke checks completed." -ForegroundColor Green
