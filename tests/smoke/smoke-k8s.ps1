param(
  [switch]$Apply
)

if ($Apply) {
  kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml
  helm upgrade --install agentgateway-crds oci://cr.agentgateway.dev/charts/agentgateway-crds --version v1.3.1 -n agentgateway-system --create-namespace
  helm upgrade --install agentgateway oci://cr.agentgateway.dev/charts/agentgateway --version v1.3.1 -n agentgateway-system -f deploy/kubernetes/helm/values.yaml
  kubectl apply -f deploy/kubernetes/manifests/
}

kubectl get crd gateways.gateway.networking.k8s.io
kubectl get pods -n agentgateway-system
kubectl get gateway,httproute -A
Write-Host "Kubernetes smoke checks completed." -ForegroundColor Green
