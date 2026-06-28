# Demo Runbook

A verified, reproducible walkthrough of the local enterprise secure-MCP platform on
agentgateway. Every command below was run end-to-end on Windows + Docker Desktop with
agentgateway `v1.3.1` and Ollama `llama3.2:3b` (last full re-run 2026-06-28, all six
milestones green). See [../STATUS.md](../STATUS.md) for the milestone source of truth.

The structure is deliberate: a **pre-flight** that warms the heavy pieces off-camera,
then a tight **on-camera** sequence that runs only fast proofs. That keeps the recorded
walkthrough in the 5-8 minute window without waiting on image pulls or cluster startup.

---

## What you are showing

One local data plane (agentgateway) sitting in front of both LLM and MCP traffic, with:

- Strict API-key auth on the LLM path (no key → 401, valid key → real completion).
- LLM failover across two backends (dead primary → live backup).
- Virtual MCP federating three tool servers (stdio-style, HTTP, OpenAPI) behind one endpoint.
- Keycloak OAuth2/JWT plus tool-level RBAC (reader vs operator, tenant-scoped).
- Full observability — Prometheus metrics, a Grafana dashboard, Jaeger traces.
- A Kubernetes promotion on kind with the same gateway as Gateway API + agentgateway CRDs.

All local. No paid keys. Ollama stays on the host the whole time.

---

## The demo at a glance

### What we mean by "the demo"

"The demo" is the running local platform — agentgateway sitting in front of local LLM and
MCP traffic, with identity, RBAC, observability, and a Kubernetes promotion. **Testing** is
the set of smoke tests under `tests/smoke/` that assert each milestone behaves correctly.
**Demonstrating** is walking a viewer through that proven behavior on screen. So we test to
prove it works, then demonstrate what it means.

### Systems involved

| System | Role in the demo | Endpoint |
| --- | --- | --- |
| agentgateway — laptop (M1) | LLM data plane, strict API-key auth, OpenAI-compatible | `:3000` |
| agentgateway — failover (M2) | LLM data plane with a dead primary + live backup | `:3003` |
| agentgateway — mcp-secure (M3/M4) | MCP data plane, JWT auth + CEL RBAC, Virtual MCP | `:3002/mcp` |
| Ollama (on host) | Local model runtime serving `llama3.2:3b` | host `:11434` |
| Keycloak | OAuth2/OIDC identity provider, issues the JWTs | `:8080` |
| sqlite-tools | stdio-style MCP tool server (read/write incidents) | `:7003` |
| http-tools | streamable-HTTP MCP tool server (service health/restart) | `:7001` |
| openapi-app | REST app exposed as MCP tools (tickets) | `:7002` |
| OTel Collector | Receives gateway traces, exports to Jaeger | `:4317/:4318` |
| Prometheus | Scrapes gateway metrics from the stats listener `:15020` | `:9090` |
| Grafana | Dashboards over the Prometheus datasource | `:3001` |
| Jaeger | Distributed-trace UI | `:16686` |
| kind + Helm (M6) | Kubernetes promotion of the same gateway as CRDs | port-forward |

### How they are connected

```mermaid
flowchart LR
  Client["Client / smoke test"]
  subgraph Gateways["agentgateway data plane"]
    LLM[":3000 LLM"]
    FO[":3003 failover"]
    MCP[":3002 secure MCP"]
  end
  Ollama["Ollama (host :11434)\nllama3.2:3b"]
  KC["Keycloak :8080\nJWT issuer"]
  subgraph Tools["Virtual MCP tool servers"]
    SQ["sqlite-tools :7003"]
    HT["http-tools :7001"]
    OA["openapi-app :7002"]
  end
  subgraph Obs["Observability"]
    OT["OTel Collector"]
    PR["Prometheus :9090"]
    GR["Grafana :3001"]
    JG["Jaeger :16686"]
  end

  Client -->|API key| LLM --> Ollama
  Client -->|API key| FO --> Ollama
  Client -->|JWT| MCP --> SQ & HT & OA
  KC -->|JWKS / token| MCP
  Gateways -->|traces| OT --> JG
  PR -->|scrape :15020| Gateways
  GR --> PR
```

The client never talks to Ollama or the tool servers directly — every request goes through
a gateway that authenticates it, applies policy, routes it, and emits metrics and traces.

### Sequence of events

1. **Pre-flight** brings the stack up. Keycloak imports the realm, each gateway loads its
   config, and `agentgateway-mcp-secure` is restarted so it fetches JWKS after Keycloak is ready.
2. **LLM call (M1):** client sends an OpenAI-compatible request to `:3000` with an API key.
   The gateway rejects no-key calls (401), authenticates a valid key, forwards to host Ollama,
   and returns a real completion.
3. **Observability (M5):** that traffic increments `agentgateway_requests_total` (scraped by
   Prometheus, shown in Grafana) and produces traces exported through the OTel Collector to Jaeger.
4. **MCP federation (M3):** client gets a JWT from Keycloak, opens an MCP session to `:3002`,
   and `tools/list` returns six tools federated from three servers with stable `sqlite_/http_/openapi_` prefixes.
5. **RBAC (M4):** the same endpoint, different identity — `alice-reader` can call read tools but
   is denied writes, while `oliver-operator` can write. Authorization is listener-level CEL on the bare tool name.
6. **Failover (M2):** the `resilient` virtual model on `:3003` prefers a dead primary. The first
   cold request trips the breaker, `health.eviction` evicts it, and steady-state traffic rides the live backup.
7. **Kubernetes (M6):** the same gateway, promoted to kind as Gateway API + agentgateway CRDs.
   A port-forwarded request flows through the in-cluster gateway to host Ollama via `host.docker.internal`.

### What each step proves

| Step | We are testing | We are demonstrating |
| --- | --- | --- |
| M1 | Auth gate + real completion through the gateway | One governed front door for LLM traffic |
| M5 | Metrics scraped, dashboard live, traces received | Full visibility into every request |
| M3 | Six tools federated and prefixed through one endpoint | Virtual MCP across mixed transports |
| M4 | Reader/operator allow-deny, tenant-scoped, 7/7 | Least-privilege, multi-tenant tool access |
| M2 | Dead primary → live backup, 3/3 | Resilient LLM routing |
| M6 | Gateway Programmed + live call on kind | A real promotion path to Kubernetes |

---

## Pre-flight (do this BEFORE you hit record)

**Fast path:** `pwsh ./demo.ps1` (or double-click `demo.cmd`) does all of the Docker
pre-flight below — checks, compose up, the Keycloak/JWKS restart, readiness — and prints
the URLs and credentials. Add `-WithKubernetes` to also set up M6, and `-Verify` to run
the smoke tests. The manual steps below are the same thing spelled out.

These steps pull images, warm Keycloak, and create the kind cluster so nothing stalls
on camera. Budget ~10 minutes the first time, ~2 minutes after images are cached.

```powershell
cd C:\Ganesh\GaneshPersonal\agentgateway-secure-mcp-platform

# 1. Local env + model
Copy-Item .env.example .env -Force
ollama pull llama3.2:3b

# 2. Warm every Docker profile (LLM + observability + security + failover)
docker compose -f deploy/docker/docker-compose.yml `
  --profile observability --profile laptop --profile security --profile failover up -d

# 3. The MCP gateway fetches JWKS at boot and can race ahead of Keycloak.
#    Wait for the realm, then restart it so it picks up JWKS cleanly.
do { Start-Sleep 3 } until (
  try { (Invoke-RestMethod "http://localhost:8080/realms/agentgateway/.well-known/openid-configuration" -TimeoutSec 3).issuer } catch { $null }
)
docker compose -f deploy/docker/docker-compose.yml --profile security up -d agentgateway-mcp-secure

# 4. Stand up the Kubernetes promotion (kind + Helm + manifests + a warm-up call)
kind create cluster --config deploy/kubernetes/kind/kind-cluster.yaml
.\tests\smoke\smoke-k8s.ps1 -Apply -E2E
```

Pre-flight is good when:

- `docker compose ps` shows the gateway, observability, tool servers, and Keycloak up.
- `agentgateway-mcp-secure` is **running** (not exited).
- `smoke-k8s.ps1 -Apply -E2E` prints a 200 completion through the cluster.

Quick health snapshot:

```powershell
docker compose -f deploy/docker/docker-compose.yml ps
```

---

## On-camera sequence

### 0. Setup shot (~30s)

Show the repo tree and say the promise: one local gateway for LLM + MCP, identity via
Keycloak, full observability, and a Kubernetes path — all free and local. Point out that
Ollama runs on the host at `:11434` and the app never talks to it directly.

### 1. M1 — Standalone LLM gateway (~60s)

```powershell
# No key -> 401 (strict API-key auth)
try { Invoke-RestMethod -Method Post "http://localhost:3000/v1/chat/completions" `
  -ContentType "application/json" `
  -Body '{"model":"laptop-demo","messages":[{"role":"user","content":"hi"}]}' } catch { $_.Exception.Response.StatusCode.value__ }

# Valid Bearer -> 200 + a real llama3.2:3b completion
.\tests\smoke\smoke-llm.ps1
```

**Expected:** `401` first, then `LLM smoke test passed.` with assistant content.
**Talk track:** the client hits `localhost:3000`, not Ollama. The gateway enforces the
key and keeps an OpenAI-compatible shape, so existing OpenAI clients just repoint.

### 2. M5 — Observability (~60s)

```powershell
# Generate a little traffic, then look at the signals
$h=@{Authorization="Bearer sk-demo-reader-local"}
1..5 | % { Invoke-RestMethod -Method Post "http://localhost:3000/v1/chat/completions" -Headers $h `
  -ContentType "application/json" -Body '{"model":"laptop-demo","messages":[{"role":"user","content":"ping"}],"stream":false}' | Out-Null }
.\tests\smoke\smoke-observability.ps1
```

Then open in the browser and narrate:

- Prometheus `http://localhost:9090` → Status ▸ Targets: the `agentgateway` target is **UP**
  scraping `:15020`. Query `agentgateway_requests_total` and watch it climb.
- Grafana `http://localhost:3001` (admin/admin) → dashboard **agentgateway Secure MCP Local Demo**.
- Jaeger `http://localhost:16686` → service `agentgateway`, open a trace.

**Talk track:** identity, route, backend, and tool call are all tied together in one trace.

### 3. M3 — MCP federation (~60s)

```powershell
# Federation through the gateway: one endpoint, six prefixed tools
$op = .\tests\smoke\get-keycloak-token.ps1 -User oliver-operator -Password operator-password
$H  = @{ Authorization = "Bearer $op"; Accept = "application/json, text/event-stream" }
$r  = Invoke-WebRequest -Method Post "http://localhost:3002/mcp" -ContentType "application/json" -Headers $H `
       -Body '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"demo","version":"0"}}}' -UseBasicParsing
$sid = ([string[]]$r.Headers["Mcp-Session-Id"])[0]
$H2  = $H + @{ "Mcp-Session-Id" = $sid }
$lr  = Invoke-WebRequest -Method Post "http://localhost:3002/mcp" -ContentType "application/json" -Headers $H2 `
       -Body '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' -UseBasicParsing
(($lr.Content -replace '^data: ','' | ConvertFrom-Json).result.tools).name
```

**Expected:** six tools — `sqlite_read_incidents`, `sqlite_write_incident_note`,
`http_read_service_health`, `http_write_restart_request`, `openapi_readTickets`,
`openapi_writeTicket`.
**Talk track:** three different transports (stdio-style over HTTP, streamable HTTP, and an
OpenAPI REST app) federated into one Virtual MCP endpoint with stable, prefixed names.

### 4. M4 — Security / RBAC (~75s)

```powershell
.\tests\smoke\smoke-rbac.ps1
```

**Expected:** 7/7 — no token → 401; `alice-reader` (tenant-a) can call read tools but is
**denied** writes (and writes are filtered from her `tools/list`); the OpenAPI query param
round-trips to the backend; `oliver-operator` (tenant-b) can call writes.
**Talk track:** authorization is listener-level CEL on the bare tool name. Same gateway,
different identity, different allowed tools — least privilege, tenant-aware.

### 5. M2 — LLM failover (~45s)

```powershell
.\tests\smoke\smoke-m2.ps1
```

**Expected:** 3/3 — the `resilient` virtual model prefers a dead primary (`:11999`); the
first cold request trips the breaker (a 503), then `health.eviction` evicts it and traffic
rides the live backup (`:11434`); a direct call to the dead primary fails; no-auth → 401.
**Talk track:** failover here is outlier detection, not in-line retry — the honest behavior
is "first cold request surfaces the failure, steady-state traffic is on the backup."

### 6. M6 — Kubernetes promotion (~60s)

```powershell
.\tests\smoke\smoke-k8s.ps1 -E2E
```

**Expected:** GatewayClass Accepted, Gateway **Programmed=True**, Backend **Accepted=True**,
Policy **Accepted+Attached=True**, then a 200 completion through the in-cluster gateway.
**Talk track:** the same gateway promoted to Kubernetes as Gateway API + agentgateway CRDs.
Install order is Gateway API CRDs → agentgateway CRDs + control plane → Gateway/Route/
Backend/Policy. kind has no cloud LoadBalancer, so we reach it with `port-forward`, and the
pod reaches host Ollama through `host.docker.internal`.

### Closing (~30s)

Be honest about the line between demo and production. This proves the secure LLM + MCP
paths, RBAC, observability, and the Kubernetes promotion locally. Before production:
TLS/mTLS, HA control/data planes, real enterprise identity groups, external secret
management, policy review, SLOs, and GitOps for the CRDs.

---

## Teardown

```powershell
# Docker stacks
docker compose -f deploy/docker/docker-compose.yml `
  --profile observability --profile laptop --profile security --profile failover down

# Kubernetes
kind delete cluster --name agentgateway-secure-mcp
```

---

## Troubleshooting (gotchas seen during verification)

| Symptom | Cause | Fix |
| --- | --- | --- |
| `agentgateway-mcp-secure` exited (1) right after start | It fetches JWKS at boot and raced ahead of Keycloak | Re-run `docker compose ... --profile security up -d agentgateway-mcp-secure` once the realm endpoint answers (pre-flight step 3) |
| M2 first call returns 503 | Expected — the cold request trips the breaker on the dead primary | The smoke test primes the breaker, then asserts steady-state success on the backup |
| `smoke-k8s.ps1 -Apply` says "Gateway not Programmed" | Status checked before the control plane finished rolling out | The script now waits for rollout + Programmed after `-Apply`; just re-run `smoke-k8s.ps1 -E2E` |
| OpenAPI tool returns `tenant=null` | agentgateway nests OpenAPI params by location | Call with `arguments={query:{tenant:...}}`, not a flat `{tenant:...}` |
| Prometheus `agentgateway` target down | Scrape pointed at the admin port | Metrics are on the stats listener `:15020`, not `:15000` |
