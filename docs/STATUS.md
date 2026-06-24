# Project Status

This status file keeps the public README honest for a maintainer-facing recording. **It is the single source of truth for what is done vs. pending.**

## How this project is tracked (living docs)

Keep these files current on every change — they are the canonical record:

| File | Purpose |
| --- | --- |
| [STATUS.md](STATUS.md) (this file) | Milestone states, config-correction log, and the open action-item checklist |
| [SETUP.md](SETUP.md) | End-to-end local setup runbook (software, ports, credentials, troubleshooting) |
| [DEMO.md](demo/DEMO.md) | On-camera recording flow |
| [operations/README.md](operations/README.md) | Profiles, common commands, quick troubleshooting |

Maintenance convention: when configs, ports, versions, or steps change, update STATUS.md (checkbox + milestone row) **and** SETUP.md in the same change.

Last local validation: 2026-06-23 on Windows + Docker Desktop, agentgateway `v1.3.1`, Ollama `llama3.2:3b`.

| Milestone | State | What is true now | Next work |
| --- | --- | --- | --- |
| 1. Standalone Docker + Ollama | **Verified runnable** | Laptop profile (`llama3.2:3b`) loads and serves through agentgateway. Confirmed end-to-end via Compose: unauthenticated call → **401**; valid `Authorization: Bearer` → **200** with a real completion; token rate limit + `tokenize` active. | Capture the recording. |
| 2. LLM resilience/governance | Partial | Model aliases, API keys, and local token budgets are configured and load. | Add real failover/load balancing and content-based routing (needs multiple backends behind one alias), then validate. |
| 3. MCP federation | **Verified (no-auth)** | All three tool servers now run over HTTP (`mcp:`/`openapi:` targets) — no in-container runtime needed. Federation proven through the gateway: `initialize`, `tools/list` (6 tools, correctly prefixed `sqlite_/http_/openapi_`), and `tools/call` all work. The distroless stdio blocker is resolved (sqlite tools moved to HTTP; stdio variant kept standalone). | Prove the same through the gateway *with* JWT auth + RBAC (M4). Fix OpenAPI arg→query mapping (tenant came through null). |
| 4. Security/RBAC | **Verified** | JWT auth + RBAC proven end-to-end through the gateway. `smoke-rbac.ps1` passes 6/6: no-token→401; reader sees/calls only read tools (writes filtered + denied); operator (tenant-b) can call writes. | Add a same-role/other-tenant user to demo cross-tenant denial explicitly. |
| 5. Observability | Stack ready; gateway wiring fixed & partly verified | OTel/Prometheus/Grafana/Jaeger wired. Gateway tracing fixed to `config.tracing.otlpEndpoint`; metrics endpoint corrected to the stats listener on **:15020** (verified serving 44 KB of metrics). | Confirm Jaeger traces + Grafana panels after a real run with the observability profile. |
| 6. Kubernetes/Helm | Skeleton | kind, Helm values, Gateway, HTTPRoute, Backend, and placeholder Policy exist. | Promote real auth/rate-limit/tracing policies into CRDs and validate with a kind run (helm/kind not yet installed locally). |
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

## Open action items / checklist

Single source of truth for done vs. pending. `[x]` = verified locally; `[~]` = configured but not yet proven end-to-end; `[ ]` = not started.

### Done (verified locally)
- [x] Repo scaffold, enterprise folder structure, pinned version matrix
- [x] `.gitignore` keeps `PROJECT_BRIEF.md`, `A1_AgentGateway/`, and secrets out of git
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

### Configured, not yet proven (next up)
- [~] Observability end-to-end (M5) — confirm Prometheus target UP, Grafana dashboard loads, Jaeger shows gateway traces after real calls

### Done (verified locally) — M4
- [x] JWT auth at the MCP gateway (no-token → 401; valid Keycloak token accepted)
- [x] RBAC allow/deny through the gateway, automated in `smoke-rbac.ps1` (6/6 pass)
- [x] reader tool-list filtering (writes hidden from reader)
- [x] Keycloak fixes: pinned issuer (`KC_HOSTNAME`), user profile fields, audience mapper + `audiences`

### Done (verified locally) — M3
- [x] MCP federation through the gateway (no-auth): `initialize` + `tools/list` + `tools/call` for all 3 targets, prefixes confirmed
- [x] stdio→HTTP conversion: sqlite tools served over HTTP (`sqlite-tools` container) so the distroless gateway needs no in-container runtime
- [ ] Fix OpenAPI arg→query mapping (the `tenant` argument reached the backend as null)

### Pending (not started)
- [ ] LLM resilience (M2) — failover / load balancing / content-based routing (multiple backends behind one alias)
- [ ] Kubernetes (M6) — promote real auth/rate-limit/tracing into CRDs; install kind + Helm; validate a cluster run
- [ ] Blog draft revision with the real gotchas (distroless image, invalid `admin`/`telemetry` keys, tracing schema, metrics port)
- [ ] Manual localhost pass: Prometheus `/targets` UP, Grafana login, Jaeger traces

## Recording Guidance

Record Milestone 1 first using the **laptop profile** (`--profile laptop`, `llama3.2:3b`). The high-reasoning profile (`llm.yaml`) is an **optional workstation-only** configuration, never the default recording path.
