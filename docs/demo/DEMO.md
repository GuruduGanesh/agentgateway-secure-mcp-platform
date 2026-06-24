# Demo Runbook

This is the 5-8 minute recording path for the local enterprise secure-MCP demo.

## 0. Setup Shot

Show the repo and explain the promise:

- Fully local.
- No paid LLM keys.
- agentgateway as the control point for LLM and MCP traffic.
- Keycloak for identity, OpenTelemetry for visibility.

```powershell
Copy-Item .env.example .env
ollama pull llama3.2:3b
ollama pull qwen2.5:7b
```

Expected: Ollama has the laptop-safe recording models available. The high-reasoning profile uses `qwen3.6:35b`, but do not record against it unless the workstation can run it comfortably.

## 1. Standalone LLM Gateway

Start observability and agentgateway with the laptop-safe Ollama config.

```powershell
docker compose -f deploy/docker/docker-compose.yml --profile observability --profile laptop up -d
.\tests\smoke\smoke-llm.ps1
```

On screen, point out:

- Client calls `localhost:3000`, not Ollama directly.
- Ollama stays local on `localhost:11434`.
- The app can keep an OpenAI-compatible API shape.

Expected: HTTP 200 response with assistant content.

## 2. LLM Routing and Budget Narrative

Show `config/agentgateway/standalone/llm-laptop.yaml`, then briefly show `config/agentgateway/standalone/llm.yaml` as the high-reasoning profile.

Talk track:

- The recording model name is the alias `laptop-demo`.
- The high-reasoning alias is `enterprise-reasoning-latest`.
- Backends are local Ollama models.
- API keys and a local token budget are configured.
- In this local demo, cost is token counting, not real provider spend.
- Failover and content-based routing remain planned, not shown as working.

Optional:

```powershell
ollama pull qwen3.6:35b
docker compose -f deploy/docker/docker-compose.yml --profile observability --profile llm up -d
.\tests\smoke\smoke-llm.ps1 -Model enterprise-reasoning-latest
```

## 3. Local MCP Tool Sources

Start the local MCP sample services through Docker Compose, or run the Node services directly for isolated testing.

```powershell
docker compose -f deploy/docker/docker-compose.yml --profile security up -d keycloak http-tools openapi-app agentgateway-mcp-secure
```

In another terminal:

```powershell
.\tests\smoke\smoke-mcp.ps1
```

Talk track:

- The demo has one stdio-style tools server, one HTTP tools server, and one REST app with OpenAPI.
- agentgateway Virtual MCP is configured to federate these into one MCP endpoint.
- Tool names should remain stable and tenant-aware.
- Validate the gateway session in the admin UI before claiming the full federation segment in a recording.

## 4. Keycloak and RBAC

Start Keycloak and request tokens.

```powershell
docker compose -f deploy/docker/docker-compose.yml --profile security up -d keycloak http-tools openapi-app agentgateway-mcp-secure
.\tests\smoke\get-keycloak-token.ps1 -User alice-reader -Password reader-password
.\tests\smoke\get-keycloak-token.ps1 -User oliver-operator -Password operator-password
.\tests\smoke\smoke-rbac.ps1
```

Expected:

- Reader token contains `tenant-a` and `reader`.
- Operator token contains `tenant-b` and `operator`.
- Reader/operator tokens are real.
- Gateway-side tool authorization is configured with target-level CEL rules; verify the end-to-end tool calls before recording this as complete.

## 5. Observability

Start the telemetry stack.

```powershell
docker compose -f deploy/docker/docker-compose.yml --profile observability up -d
.\tests\smoke\smoke-observability.ps1
```

Open:

- Prometheus: `http://localhost:9090`
- Grafana: `http://localhost:3001`
- Jaeger: `http://localhost:16686`

Talk track:

- Gateway latency, errors, and admin metrics.
- MCP tool calls by tenant/tool.
- Token usage by virtual key or model alias.
- Traces tie identity, route, backend, and tool call together.

## 6. Kubernetes Promotion

Show the kind and Helm files.

```powershell
kind create cluster --config deploy/kubernetes/kind/kind-cluster.yaml
.\tests\smoke\smoke-k8s.ps1 -Apply
```

Talk track:

- Gateway API CRDs first.
- agentgateway CRDs and control plane second.
- Gateway, routes, backends, and policies last.
- Ollama remains on the host through `host.docker.internal` for laptop speed.

## Closing

Close honestly:

- This demo proves the laptop-safe LLM path and shows the configured security/observability/MCP architecture honestly.
- Before production: TLS, HA, real identity groups, real policy review, external secrets, SLOs, and GitOps.
