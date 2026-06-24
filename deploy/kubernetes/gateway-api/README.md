# Gateway API Install Notes

Install Kubernetes Gateway API CRDs before installing the agentgateway control plane.

```powershell
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml
```

Then install agentgateway CRDs and the control plane:

```powershell
helm install agentgateway-crds oci://cr.agentgateway.dev/charts/agentgateway-crds --version v1.3.1 -n agentgateway-system --create-namespace
helm install agentgateway oci://cr.agentgateway.dev/charts/agentgateway --version v1.3.1 -n agentgateway-system -f deploy/kubernetes/helm/values.yaml
```
