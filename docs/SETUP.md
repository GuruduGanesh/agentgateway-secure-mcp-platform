# Local Setup Guide (End to End)

How to stand up this entire architecture locally from a clean machine. This is the authoritative "do it again in the future" runbook. For the on-camera flow see [DEMO.md](demo/DEMO.md); for status/checklist see [STATUS.md](STATUS.md).

> Verified on Windows 11 + Docker Desktop, agentgateway `v1.3.1`, Ollama `llama3.2:3b` (2026-06-24). M2 failover (`smoke-m2.ps1` 3/3), M3 OpenAPI mapping (`smoke-rbac.ps1` 7/7), and M6 Kubernetes on kind v0.32.0 (`smoke-k8s.ps1 -E2E`) all verified end-to-end 2026-06-24. Items not yet verified end-to-end are flagged inline.

---

## 1. Software prerequisites

| Software | Version (tested / pinned) | Required for | Notes |
| --- | --- | --- | --- |
| Docker Desktop (Windows) | Engine 29.x, Compose v2 (5.1.3) | everything | must be running before any `docker` command |
| PowerShell | 7+ or Windows PowerShell 5.1 | smoke scripts | scripts are `.ps1` |
| Ollama | 0.30.x | LLM gateway | runs on the host, not in a container |
| Node.js | 20+ (tested 24) | MCP sample servers, syntax checks | |
| kubectl | bundled w/ Docker Desktop | Kubernetes milestone (optional) | |
| kind | v0.32.0 | Kubernetes milestone | `winget install Kubernetes.kind` |
| Helm | v4.2.2 (tested; v3 also works) | Kubernetes milestone | `winget install Helm.Helm` — v4 works with the OCI charts |

Container images (pulled automatically by Compose; pinned in `.env.example`):
`agentgateway v1.3.1`, `keycloak 26.6.3`, `otel-collector-contrib 0.154.0`, `prometheus v3.12.0`, `grafana 13.0.2`, `jaeger 2.8.0`.

---

## 2. One-time bootstrap

```powershell
cd C:\Ganesh\GaneshPersonal\agentgateway-secure-mcp-platform

# 2a. Environment file (safe local defaults)
Copy-Item .env.example .env

# 2b. Pull the lightweight model (required). ~2 GB.
ollama pull llama3.2:3b
# Optional second alias for the aliasing demo (~4.7 GB):
ollama pull qwen2.5:7b

# 2c. Confirm Ollama is serving on the host
Invoke-RestMethod http://localhost:11434/api/tags | Out-Null   # no error = good
```

> The high-reasoning profile (`qwen3.6:35b` / `gpt-oss:120b` / `deepseek-r1:671b`) is **workstation-only and optional** — do not pull on a normal laptop.

---

## 3. Milestone 1 — Standalone LLM gateway (VERIFIED)

```powershell
docker compose -f deploy/docker/docker-compose.yml --profile laptop --profile observability up -d
docker compose -f deploy/docker/docker-compose.yml ps
```

Verify:

```powershell
.\tests\smoke\smoke-llm.ps1
```

Expected (confirmed locally):
- Unauthenticated POST to `http://localhost:3000/v1/chat/completions` → **401**.
- With `Authorization: Bearer sk-demo-reader-local` → **200** + a real completion from `llama3.2:3b`.
- Metrics at `http://localhost:15020/metrics` → 200 (~44 KB).

Teardown when done:

```powershell
docker compose -f deploy/docker/docker-compose.yml --profile laptop --profile observability down
```

---

## 3b. Milestone 2 — LLM resilience / failover (VERIFIED)

Two backends behind a `resilient` virtual model with `failover` routing. `ollama-primary` is pointed at a dead port (`:11999`) to prove failover to the live `ollama-backup` (`:11434`).

**How it works:** `failover` routing alone does not move traffic — failover is driven by **outlier detection**. Each model carries a `health.eviction` policy; a 5xx/connection failure evicts the model (after `consecutiveFailures`), so the next priority group serves. The `llm:` shorthand has no in-line retry, so the **first** cold request to the dead primary surfaces a 503 that trips the breaker, then all steady-state traffic rides the backup until the eviction `duration` lapses.

```powershell
docker compose -f deploy/docker/docker-compose.yml --profile failover up -d
# Give the gateway ~5 s to start and load tokenizers
Start-Sleep 5
.\tests\smoke\smoke-m2.ps1
```

Expected (3/3 PASS, confirmed locally 2026-06-24):
1. `resilient` reaches steady-state **200** on `ollama-backup` (attempt 1 trips the breaker on the dead primary; attempt 2+ succeeds).
2. Direct call to `ollama-primary` → **connection refused / 5xx** (dead endpoint confirmed).
3. Unauthenticated call → **401**.

Config: [`config/agentgateway/standalone/llm-m2.yaml`](../config/agentgateway/standalone/llm-m2.yaml). Gateway on port **3003** (does not conflict with the laptop profile on 3000). The default laptop profile (`llm-laptop.yaml`) also exposes the `resilient` model (both backends live) so the demo can show it without the dead-endpoint setup.

Teardown:

```powershell
docker compose -f deploy/docker/docker-compose.yml --profile failover down
```

---

## 4. Milestone 5 — Observability (VERIFIED)

Brought up by the `observability` profile in step 3. After generating a few authenticated LLM calls, all three surfaces were confirmed:

| URL | What to check | Verified result |
| --- | --- | --- |
| http://localhost:15020/metrics | gateway metrics | 200, `agentgateway_*` metrics |
| http://localhost:9090/targets | `agentgateway` job scraping `:15020` | state **UP**; `agentgateway_requests_total` increments |
| http://localhost:3001 | Grafana (`admin`/`admin`), dashboard **agentgateway Secure MCP Local Demo** | healthy, Prometheus datasource default, dashboard provisioned |
| http://localhost:16686 | Jaeger, service `agentgateway` | traces present (one per request) |

> First run downloads ~1.5 GB of images (Prometheus/Grafana/Jaeger/OTel) — expect a slow initial `up`. Traces only export when the `observability` profile (otel-collector) is running on the same network.

---

## 5. Milestone 3 — MCP federation (VERIFIED, no-auth)

All three tool servers run over HTTP, so the distroless gateway needs no in-container runtime. Federation through the gateway is verified (`initialize`, `tools/list`, `tools/call`).

```powershell
docker compose -f deploy/docker/docker-compose.yml --profile security up -d
.\tests\smoke\smoke-mcp.ps1   # checks the sample servers directly
```

Manually verify federation **through the gateway** (MCP endpoint on :3002). Note: the secure config requires a JWT (see M4); for a transport-only check use an auth-free config. Expected `tools/list` result (6 tools, prefixed by target):

```
sqlite_read_incidents   sqlite_write_incident_note
http_read_service_health   http_write_restart_request
openapi_readTickets   openapi_writeTicket
```

The MCP handshake is: POST `/mcp` `initialize` (returns an `Mcp-Session-Id` header) → reuse that header for `tools/list` and `tools/call`. Responses are SSE-framed (`data: {...}`). Use `Accept: application/json, text/event-stream`.

**OpenAPI tool arguments are nested by parameter location.** The generated `openapi_readTickets` tool expects its `tenant` (a query parameter) under a `query` object — call it with `arguments={"query":{"tenant":"tenant-a"}}`. A flat `{"tenant":"tenant-a"}` is dropped and the backend receives `null`. `smoke-rbac.ps1` guards this with an explicit round-trip assertion.

## 5b. Milestone 4 — RBAC through the gateway (VERIFIED)

JWT auth + tool-level RBAC are proven end-to-end. The MCP gateway fetches JWKS at boot, so it must start **after** Keycloak is ready (restart it if it raced):

```powershell
docker compose -f deploy/docker/docker-compose.yml up -d agentgateway-mcp-secure  # restart if it exited
.\tests\smoke\smoke-rbac.ps1
```

Expected (7/7 PASS):
- no token → 401
- `alice-reader` (tenant-a): read tools ALLOWED, write tools DENIED (and hidden from `tools/list`)
- OpenAPI query-param maps to backend (`tenant-a` round-trips, not null)
- `oliver-operator` (tenant-b): write tools ALLOWED

Key gotchas (see also §8): authz must be at the **listener level** (`mcp.policies.mcpAuthorization`); in CEL `mcp.tool.name` is the **bare** name (`read_incidents`, not `sqlite_read_incidents`); Keycloak needs `KC_HOSTNAME` (issuer), user profile fields, and an audience mapper. Keycloak admin console: http://localhost:8080 (`admin`/`admin`).

---

## 6. Milestone 6 — Kubernetes (VERIFIED on kind)

Verified end-to-end 2026-06-24 on kind v0.32.0 + Helm v4.2.2. **Install order matters** (Gateway API CRDs → agentgateway CRDs → control plane → manifests).

```powershell
# 0. One-time tool install (winget); kubectl ships with Docker Desktop
winget install -e --id Kubernetes.kind
winget install -e --id Helm.Helm
# open a new shell so kind/helm are on PATH

# 1. Cluster (extraPortMappings expose 30080/30443 on the host)
kind create cluster --config deploy/kubernetes/kind/kind-cluster.yaml
kubectl config use-context kind-agentgateway-secure-mcp

# 2. Kubernetes Gateway API CRDs FIRST
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml

# 3. agentgateway CRDs, then the control plane (Helm v4 works with the OCI charts)
helm install agentgateway-crds oci://cr.agentgateway.dev/charts/agentgateway-crds --version v1.3.1 -n agentgateway-system --create-namespace
helm install agentgateway     oci://cr.agentgateway.dev/charts/agentgateway      --version v1.3.1 -n agentgateway-system -f deploy/kubernetes/helm/values.yaml

# 4. Apply the demo manifests (namespace, Gateway, HTTPRoute, AgentgatewayBackend, AgentgatewayPolicy)
kubectl apply -f deploy/kubernetes/manifests/
```

Verify (or run `.\tests\smoke\smoke-k8s.ps1 -E2E`, which also drives a live LLM call):

```powershell
kubectl get gatewayclass agentgateway                      # ACCEPTED=True
kubectl -n agentgateway-demo get gateway,httproute,agentgatewaybackend,agentgatewaypolicy
# Gateway PROGRAMMED=True, Backend ACCEPTED=True, Policy ACCEPTED+ATTACHED=True
```

**Access on kind (no cloud LoadBalancer):** the control plane creates a `LoadBalancer` Service per Gateway whose external IP stays `<pending>`. Reach it via port-forward, then call it like the standalone LLM gateway:

```powershell
kubectl -n agentgateway-demo port-forward svc/local-agentgateway 8088:80
# in another shell:
curl http://localhost:8088/v1/chat/completions -H "content-type: application/json" `
  -d '{"model":"llama3.2:3b","messages":[{"role":"user","content":"hi"}]}'
```

`host.docker.internal` resolves from pods on Docker Desktop, so the in-cluster gateway reaches host Ollama directly — no in-cluster Ollama needed.

**Manifests were corrected to the live v1.3.1 CRDs** (the original skeleton used pre-release field names):
- CRD group is **`agentgateway.dev`** (not `gateway.agentgateway.dev`) for the HTTPRoute `backendRef`, `AgentgatewayBackend`, and `AgentgatewayPolicy`.
- `AgentgatewayBackend` AI shape is **`spec.ai.groups[].providers[]`** with provider-level `host`/`port`/`pathPrefix` override (not `spec.ai.provider.openai.{host,port,path}`).
- CORS on `AgentgatewayPolicy` is **`spec.traffic.cors`** (not `spec.policy.cors`); `spec.traffic` also holds `jwtAuthentication`/`rateLimit`/`authorization` for promoting M4.

Teardown:

```powershell
kind delete cluster --name agentgateway-secure-mcp
```

---

## 7. Port & credential reference

| Service | Host port | Notes |
| --- | --- | --- |
| Ollama (host) | 11434 | OpenAI-compatible at `/v1` |
| LLM gateway (HTTP) | 3000 | `laptop` / `llm` profiles |
| LLM gateway M2 failover test | 3003 | `failover` profile |
| LLM gateway admin | 15000 | admin API/UI (no `/metrics`) |
| LLM gateway stats/metrics | 15020 | Prometheus scrapes here |
| MCP gateway (HTTP) | 3002 | `security` profile |
| MCP gateway admin / stats | 15002 / 15022 | |
| SQLite MCP sample (HTTP) | 7003 | `/mcp`, `/healthz` |
| HTTP MCP sample | 7001 | `/mcp`, `/healthz` |
| OpenAPI sample | 7002 | `/openapi.yaml`, `/tickets` |
| Keycloak | 8080 | `admin`/`admin` |
| OTel Collector | 4317 / 4318 / 8889 | gRPC / HTTP / prom export |
| Prometheus | 9090 | |
| Grafana | 3001 | `admin`/`admin` |
| Jaeger UI | 16686 | |

| Credential | Value |
| --- | --- |
| Gateway API key (reader) | `sk-demo-reader-local` |
| Gateway API key (operator) | `sk-demo-operator-local` |
| Keycloak user (reader) | `alice-reader` / `reader-password` — `tenant-a`, role `reader` |
| Keycloak user (operator) | `oliver-operator` / `operator-password` — `tenant-b`, role `operator` |

All keys/passwords above are **local demo defaults only** — never reuse outside this local setup.

---

## 8. Troubleshooting (real issues hit during setup)

| Symptom | Cause | Fix |
| --- | --- | --- |
| Gateway exits 1, `unknown field 'admin'` | `admin:`/`telemetry:` are not valid top-level keys in v1.3.1 | use `config.adminAddr` / `config.statsAddr` / `config.logging.level` |
| Gateway exits 1, `no variant of enum SimpleLocalBackend` | `frontendPolicies.tracing` expects a `host` backend | use `config.tracing.otlpEndpoint` instead |
| `/metrics` returns 404 on :15000 | metrics live on the stats listener, not admin | scrape `:15020` |
| LLM call returns 401 | strict API-key auth | send `Authorization: Bearer sk-demo-reader-local` |
| `resilient` model returns 503, never fails over | `failover` routing without a health policy | add `health.eviction` to the model — failover is outlier-detection-driven, not automatic |
| First `resilient` call 503s but later calls work | expected: no in-line retry in the `llm:` shorthand | the first failure trips the breaker; steady-state traffic then rides the backup |
| stdio MCP tool fails / `exec node: not found` | gateway image is distroless (no node) | serve the tools over HTTP and use an `mcp:` target (done for `sqlite-tools`) |
| `port is already allocated` | a previous container still holds the port | `docker compose ... down`, or `docker rm -f <name>` |
| Ports show exposed but not published | stale container from a failed start | `docker compose ... up -d --force-recreate` |
| MCP gateway exits: `failed to load JWKS` | it started before Keycloak was ready | restart it: `docker compose ... up -d agentgateway-mcp-secure` |
| Token request 400 `Account is not fully set up` | realm user missing profile fields | add email/firstName/lastName + `requiredActions: []` |
| RBAC rules ignored (all tools allowed) | `mcpAuthorization` placed per-target | move it to listener level `mcp.policies.mcpAuthorization` |
| RBAC denies everything (incl. allowed reads) | rule used prefixed tool name | use the **bare** name in CEL (`read_incidents`, not `sqlite_read_incidents`) |
| OpenAPI tool returns `null` for a passed arg | flat args; gateway nests params by location | nest under `query`/`path`/`body`, e.g. `{"query":{"tenant":"…"}}` |
| LLM smoke fails to reach Ollama | host networking | confirm Ollama on `http://localhost:11434` and `host.docker.internal` resolves in containers |

---

## 9. Full teardown

```powershell
docker compose -f deploy/docker/docker-compose.yml --profile laptop --profile llm --profile security --profile observability down
```

This guide is a **living document** — update it whenever configs, ports, versions, or steps change. See [STATUS.md](STATUS.md) for the maintenance convention.
