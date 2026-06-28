# Project Status

This status file keeps the public README honest. **It is the single source of truth for what is done vs. pending.**

## How this project is tracked (living docs)

Keep these files current on every change — they are the canonical record:

| File | Purpose |
| --- | --- |
| [STATUS.md](STATUS.md) (this file) | Milestone states, config-correction log, and the open action-item checklist |
| [SETUP.md](SETUP.md) | End-to-end local setup runbook (software, ports, credentials, troubleshooting) |
| [DEMO.md](demo/DEMO.md) | On-camera recording flow |
| [operations/README.md](operations/README.md) | Profiles, common commands, quick troubleshooting |

Maintenance convention (**mandatory, every change**): in the *same* change that touches configs, ports, versions, or steps, update **all three** of —
1. the **Work log** (append a dated row with state: ✅ done / 🔄 in progress / ⏳ open),
2. the **milestone table row** and the **Open action items checkbox**, and
3. **SETUP.md** (and DEMO.md if the on-camera flow changed).

Nothing is "done" until its work-log row says ✅ and its checklist box is `[x]`. Start a step → add a 🔄 row; finish it → flip to ✅. Never silently complete work without recording it here.

Last local validation: 2026-06-28 (full M1–M6 re-run) on Windows + Docker Desktop, agentgateway `v1.3.1`, Ollama `llama3.2:3b`.

| Milestone | State | What is true now | Next work |
| --- | --- | --- | --- |
| 1. Standalone Docker + Ollama | **Verified runnable** | Laptop profile (`llama3.2:3b`) loads and serves through agentgateway. Confirmed end-to-end via Compose: unauthenticated call → **401**; valid `Authorization: Bearer` → **200** with a real completion; token rate limit + `tokenize` active. | Capture the recording. |
| 2. LLM resilience/governance | **Verified** | Failover proven end-to-end. `resilient` virtual model (`failover` routing) + per-model `health.eviction` (outlier detection) in both `llm-laptop.yaml` and the dedicated proof `llm-m2.yaml` (dead primary :11999 → live backup :11434). `smoke-m2.ps1` passes 3/3: dead primary trips the breaker on call 1, traffic fails over to the backup on call 2+; direct dead-primary call fails; no-auth → 401. | Optional: add load-balancing (weighted) + content-based routing variants. |
| 3. MCP federation | **Verified** | All three tool servers run over HTTP (`mcp:`/`openapi:` targets) — no in-container runtime needed. Federation proven through the gateway: `initialize`, `tools/list` (6 tools, correctly prefixed `sqlite_/http_/openapi_`), and `tools/call` all work. OpenAPI query-param mapping now proven: `readTickets` round-trips `tenant` when args are nested under `query` (regression-guarded in `smoke-rbac.ps1`). | — (complete; covered with auth in M4) |
| 4. Security/RBAC | **Verified** | JWT auth + RBAC proven end-to-end through the gateway. `smoke-rbac.ps1` passes 7/7: no-token→401; reader sees/calls only read tools (writes filtered from `tools/list` + denied on call); OpenAPI query-param round-trips to the backend; operator (tenant-b) can call writes. | Add a same-role/other-tenant user to demo cross-tenant denial explicitly. |
| 5. Observability | **Verified** | After 5 authenticated LLM calls: Prometheus `agentgateway` target UP scraping `:15020` (`agentgateway_requests_total=5`); Grafana healthy with Prometheus datasource + provisioned dashboard; Jaeger shows 5 `agentgateway` traces. OTLP export works once the collector is on-network. | Eyeball Grafana panels in-browser; add MCP/token panels. |
| 6. Kubernetes/Helm | **Verified** | kind v0.32.0 cluster up; Gateway API v1.5.0 CRDs + agentgateway v1.3.1 (CRDs + control plane) installed via Helm v4. Manifests corrected to the live `agentgateway.dev/v1alpha1` CRDs and applied: Gateway **Programmed**, AgentgatewayBackend **Accepted**, AgentgatewayPolicy **Accepted+Attached**. A real `llama3.2:3b` chat completion flows through the in-cluster gateway to host Ollama (`smoke-k8s.ps1 -E2E`). | Promote M4 auth (JWT/RBAC) + rate-limit into the `spec.traffic` policy block once a JWKS source is reachable in-cluster. |
| Blog draft | Draft added | First-person hands-on article draft exists under `docs/blog/`. | Revise with the real gotchas found in testing (distroless image, invalid top-level `admin`/`telemetry` keys, tracing schema, metrics port). |

## Config corrections applied (found by an actual gateway run)

- Removed invalid top-level `admin:` / `telemetry:` keys — v1.3.1 rejects them. Moved to `config.adminAddr`, `config.statsAddr`, `config.logging.level`.
- Fixed tracing: `frontendPolicies.tracing` (which expects a `host` backend) was crashing startup; switched to `config.tracing.otlpEndpoint`.
- Prometheus now scrapes metrics on **:15020** (the stats listener), not the admin port :15000 (which 404s on `/metrics`).
- `smoke-llm.ps1` now sends the demo Bearer key (strict API-key auth rejects unauthenticated calls).
- MCP stdio target replaced with an HTTP `mcp:` target (`sqlite-tools` container) — the distroless gateway has no `node`.
- `mcpAuthorization` must be at the **listener level** (`mcp.policies.mcpAuthorization`); per-target `policies` parsed into config but were not enforced.
- In authz CEL, `mcp.tool.name` is the **bare** name (`read_incidents`), not the prefixed `tools/list` name (`sqlite_read_incidents`).
- Keycloak: `KC_HOSTNAME` pins the issuer; users need profile fields (email/first/last) or token fails `Account is not fully set up`; an audience mapper + `mcpAuthentication.audiences` are required.
- The MCP gateway must start **after** Keycloak is ready (it fetches JWKS at boot); restart it if it raced ahead.
- **K8s CRD group is `agentgateway.dev`, not `gateway.agentgateway.dev`.** The skeleton manifests used the wrong group on the HTTPRoute `backendRef`, the `AgentgatewayBackend`, and the `AgentgatewayPolicy`. The live CRDs (Helm v1.3.1) are `agentgatewaybackends/policies/parameters.agentgateway.dev` (`v1alpha1`).
- **K8s `AgentgatewayBackend` AI shape is `spec.ai.groups[].providers[]`.** Not `spec.ai.provider.openai.{host,port,path}`. Provider-level `host`/`port`/`pathPrefix` override a managed provider (used to point an `openai` provider at host Ollama `:11434` `/v1`); `openai.model` overrides the request model.
- **K8s CORS is `spec.traffic.cors` on `AgentgatewayPolicy`.** Not `spec.policy.cors`. The `spec.traffic` block also holds `jwtAuthentication`, `rateLimit`, and `authorization` — the path to promote the standalone M4 security model into CRDs.
- **kind has no cloud LoadBalancer.** The control plane creates a `LoadBalancer` Service per Gateway with a random NodePort; patching it to NodePort 30080 reverts. Use `kubectl port-forward svc/local-agentgateway` for host access. `host.docker.internal` *does* resolve from pods on Docker Desktop, so the in-cluster gateway reaches host Ollama directly.
- **OpenAPI tool args are nested by parameter location.** agentgateway generates the MCP tool input schema grouping OpenAPI parameters into `query` / `path` / `body` objects. So `readTickets` (which has a `tenant` *query* param) must be called with `arguments={query:{tenant:"…"}}`. A flat `{tenant:"…"}` is silently dropped and the backend sees `null` — this was the "tenant came through null" symptom, not a gateway defect.
- **M2 failover needs a health policy.** `virtualModels.routing.failover` alone does **not** fail over — a dead primary just returns 503. Failover is driven by outlier detection: add `health.eviction` (e.g. `consecutiveFailures: 1`, `duration: 30s`) to the model. With it, the first failure evicts the primary and subsequent requests route to the next priority group. The `llm:` shorthand has **no in-line retry** (route-level `retry`/`FilterOrPolicy` is not exposed there), so failover is cross-request: the first cold request to a dead primary surfaces a 503, then steady-state traffic rides the backup.

## Work log (chronological)

Running journal of every work step and its state. **Append a dated entry whenever we start, advance, or finish a step** — never delete history; supersede with a newer entry. State key: ✅ done · 🔄 in progress · ⏳ open/blocked.

| Date | Step | State | Notes / artifacts |
| --- | --- | --- | --- |
| 2026-06-23 | M1 standalone LLM gateway verified | ✅ done | 401/200 auth + real completion; metrics on `:15020` |
| 2026-06-23 | M3 MCP federation (no-auth) verified | ✅ done | `initialize`/`tools/list`/`tools/call` for 3 targets |
| 2026-06-23 | M4 security/RBAC verified | ✅ done | `smoke-rbac.ps1` 6/6 pass |
| 2026-06-23 | M5 observability verified | ✅ done | Prom UP, Grafana healthy, Jaeger traces |
| 2026-06-24 | M2 failover config authored | ✅ done | `virtualModels.resilient` in `llm-laptop.yaml`; proof config `llm-m2.yaml` (dead primary → live backup) |
| 2026-06-24 | M2 `failover` compose profile + smoke test | ✅ done | `agentgateway-llm-m2` svc (port 3003); `smoke-m2.ps1` (3 assertions) |
| 2026-06-24 | M2 failover debugged against schema + **verified 3/3** | ✅ done | First config had no health policy → 503, no failover. Fix: added `health.eviction` (outlier detection) to `ollama-primary` in `llm-m2.yaml` **and** `llm-laptop.yaml`. Breaker trips on call 1 (dead primary), traffic fails over to backup on call 2+. `smoke-m2.ps1` rewritten to model the breaker; **3/3 pass**. Both profiles boot clean. |
| 2026-06-24 | M3 OpenAPI arg→query mapping fix (`tenant` reached backend null) | ✅ done | Root cause: **not** a gateway bug — agentgateway nests OpenAPI params by location, so `readTickets` expects `arguments={query:{tenant}}`, not flat `{tenant}`. A flat arg is dropped → backend sees null. Fixed `smoke-rbac.ps1` to nest the query arg + added a regression check asserting the tenant round-trips. RBAC smoke now **7/7 pass** (was 6). |
| 2026-06-24 | M6 Kubernetes/Helm — **complete & verified** | ✅ done | All 9 sub-steps done; LLM call flows through the in-cluster gateway. Manifests corrected to real CRDs; SETUP §6 rewritten. |
| 2026-06-24 | M6.1 preflight: check docker/kubectl/kind/helm | ✅ done | docker 29.5.2 ✓, kubectl ✓ (Docker Desktop), kind ✗, helm ✗, winget ✓ |
| 2026-06-24 | M6.2 install kind + Helm | ✅ done | winget: kind **v0.32.0** (matches pin), Helm **v4.2.2** (newer than the v3.21.2 note — verifying with OCI charts) |
| 2026-06-24 | M6.3 create kind cluster | ✅ done | `kind-agentgateway-secure-mcp` (node image v1.36.1), node Ready, context switched |
| 2026-06-24 | M6.4 install Gateway API CRDs | ✅ done | standard-install v1.5.0; gateways/gatewayclasses/httproutes CRDs present |
| 2026-06-24 | M6.5 install agentgateway (Helm) | ✅ done | Helm v4 works with OCI charts; control plane pod 1/1 Ready; GatewayClass `agentgateway` Accepted (controller `agentgateway.dev/agentgateway`) |
| 2026-06-24 | M6.6 validate/fix manifest CRD fields | ✅ done | Fixed 3 manifests vs live CRDs: (1) backendRef/backend/policy group `gateway.agentgateway.dev`→`agentgateway.dev`; (2) backend `spec.ai.provider.openai.{host,port,path}`→`spec.ai.groups[].providers[]` with host/port/pathPrefix override; (3) policy `spec.policy.cors`→`spec.traffic.cors`. All 4 pass `kubectl apply --dry-run=server`. |
| 2026-06-24 | M6.7 apply manifests | ✅ done | Gateway **PROGRAMMED=True**, Backend **ACCEPTED=True**, Policy **ACCEPTED+ATTACHED=True**; data-plane deploy `local-agentgateway` 1/1 Running |
| 2026-06-24 | M6.8 end-to-end LLM call through cluster | ✅ done | **200 + real llama3.2:3b completion** through the in-cluster gateway via `kubectl port-forward`. `host.docker.internal` resolves from the pod on Docker Desktop. `smoke-k8s.ps1 -E2E` automates it. NodePort 30080 left as optional (control plane owns a LoadBalancer svc; patching reverts). |
| 2026-06-24 | M6.9 update tracking docs | ✅ done | STATUS (work log + milestone + checklist + 4 new gotchas), SETUP §6 rewritten + prereq table + header date |
| 2026-06-24 | M6 CORS policy behavioral check | ✅ done | `OPTIONS` preflight through the port-forward → 200 with `Access-Control-Allow-Origin`/`-Allow-Headers`/`-Max-Age`. Confirms `spec.traffic.cors` is enforced (not just Attached). |
| 2026-06-24 | Full M1–M6 re-verification in one session | ✅ done | M1 200+401; M5 Prom targets UP + `agentgateway_requests_total` + 5 Jaeger traces; M2 `smoke-m2.ps1` 3/3; M3 6 prefixed tools; M4 `smoke-rbac.ps1` 7/7 + reader `tools/list` filtered to 3 read tools (operator sees 6); M6 `smoke-k8s.ps1 -E2E` 200 through in-cluster gateway. Also confirmed JWKS race gotcha (mcp-secure exits, restart fixes). |
| 2026-06-24 | Doc reconciliation | ✅ done | Fixed stale `smoke-rbac` 6/6→7/7 in milestone table + checklist; refreshed README "Current Status" table to match verified reality. |
| 2026-06-24 | Added Apache-2.0 `LICENSE` + README License section | ✅ done | Compliance: public repo now carries Apache-2.0 (matches upstream); states reference-only/not-a-fork. |
| 2026-06-25 | Governance/process scaffolding removed (kept the repo demo-focused) | ✅ done | Dropped the enterprise governance/process layer (`CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `DEVELOPMENT.md`, `CHANGELOG.md`, `.github/`, `Makefile`, `tasks.ps1`, `tests/validate.ps1`, `.gitattributes`, `.dockerignore`, `docs/README.md`) as out of scope for a local demo. README references trimmed (folder tree, setup section, docs map, contributing). The demo runs on plain `docker compose` + `tests/smoke/`. |
| 2026-06-28 | Full M1–M6 E2E re-verification + demo runbook rewrite | ✅ done | All six green in one session: M1 401/200 + real completion + metrics `:15020`; M5 Prom target UP (`agentgateway_requests_total`), Grafana dashboard `agentgateway Secure MCP Local Demo` + Prometheus datasource, Jaeger 7 `agentgateway` traces; M3 6 prefixed tools through the gateway; M4 `smoke-rbac.ps1` 7/7; M2 `smoke-m2.ps1` 3/3; M6 kind + Helm v1.3.1, Gateway Programmed + Backend/Policy Accepted+Attached, `smoke-k8s.ps1 -E2E` 200 through the in-cluster gateway. Confirmed the JWKS-race gotcha (mcp-secure exited → restart fixes). Rewrote `docs/demo/DEMO.md` as a verified pre-flight + on-camera runbook. Fixed `smoke-k8s.ps1` to wait for control-plane rollout + Gateway Programmed after `-Apply`. |
| — | Blog draft revision with real gotchas | ⏳ open | |

## Open action items / checklist

Single source of truth for done vs. pending. `[x]` = verified locally; `[~]` = configured but not yet proven end-to-end; `[ ]` = not started.

### Done (verified locally)
- [x] Repo scaffold, enterprise folder structure, pinned version matrix
- [x] `.gitignore` keeps local-only private references and secrets out of git
- [x] Keycloak realm: `reader`/`operator` roles, `tenant` attribute, role + tenant claim mappers
- [x] Lightweight laptop profile is the default (`llama3.2:3b`)
- [x] P0 config fixes: `admin`/`telemetry` → `config.*`; tracing → `config.tracing.otlpEndpoint`
- [x] Strict API-key auth proven: no key → 401, valid Bearer → 200 + real completion
- [x] `tokenize` + local token rate limit load and run
- [x] Metrics serve on stats listener `:15020` (Prometheus + compose pointed there)
- [x] `smoke-llm.ps1` sends the demo Bearer key
- [x] HTTP sample server accepts both `/mcp` and `/mcp/`
- [x] Sample MCP servers run standalone (stdio / HTTP / OpenAPI)
- [x] End-to-end setup runbook written ([SETUP.md](SETUP.md)) — software, ports, credentials, troubleshooting

### Done (verified locally) — M5
- [x] Prometheus `agentgateway` target UP (`:15020`), request metrics increment with traffic
- [x] Grafana healthy, Prometheus datasource + provisioned dashboard present
- [x] Jaeger receives gateway traces (5 traces after 5 calls); OTLP export confirmed

### Done (verified locally) — M4
- [x] JWT auth at the MCP gateway (no-token → 401; valid Keycloak token accepted)
- [x] RBAC allow/deny through the gateway, automated in `smoke-rbac.ps1` (7/7 pass)
- [x] reader tool-list filtering (writes hidden from reader)
- [x] Keycloak fixes: pinned issuer (`KC_HOSTNAME`), user profile fields, audience mapper + `audiences`

### Done (verified locally) — M3
- [x] MCP federation through the gateway (no-auth): `initialize` + `tools/list` + `tools/call` for all 3 targets, prefixes confirmed
- [x] stdio→HTTP conversion: sqlite tools served over HTTP (`sqlite-tools` container) so the distroless gateway needs no in-container runtime
- [x] OpenAPI arg→query mapping proven: nest query params under `query` (`{query:{tenant}}`); `tenant` round-trips to the backend, regression-guarded in `smoke-rbac.ps1` (7/7)

### Done (verified locally) — M2
- [x] LLM failover via `virtualModels.resilient` + `failover` routing, proven with `smoke-m2.ps1` (3/3)
- [x] Outlier-detection eviction (`health.eviction`) confirmed as the trigger — dead primary trips breaker, traffic moves to backup
- [x] Both demo profile (`llm-laptop.yaml`) and proof config (`llm-m2.yaml`) boot clean and serve the `resilient` model

### Done (verified locally) — M6
- [x] kind v0.32.0 + Helm v4.2.2 installed (winget); cluster `kind-agentgateway-secure-mcp` node Ready
- [x] Gateway API v1.5.0 CRDs + agentgateway v1.3.1 (CRDs + control plane) via Helm; control-plane pod 1/1, GatewayClass Accepted
- [x] Manifests corrected to live CRDs (group `agentgateway.dev`, `spec.ai.groups[].providers[]`, `spec.traffic.cors`) and applied: Gateway Programmed, Backend Accepted, Policy Accepted+Attached
- [x] End-to-end `llama3.2:3b` chat completion through the in-cluster gateway (`smoke-k8s.ps1 -E2E`)
- [ ] Promote M4 JWT/RBAC + rate-limit into `spec.traffic` policy CRDs (needs in-cluster-reachable JWKS)

### Pending (not started)
- [ ] Blog draft revision with the real gotchas (distroless image, invalid `admin`/`telemetry` keys, tracing schema, metrics port, M2 health-policy failover, OpenAPI nested args, M6 CRD group/shape fixes)
- [ ] Manual localhost pass: Prometheus `/targets` UP, Grafana login, Jaeger traces

## Recording Guidance

Record Milestone 1 first using the **laptop profile** (`--profile laptop`, `llama3.2:3b`). The high-reasoning profile (`llm.yaml`) is an **optional workstation-only** configuration, never the default recording path.
