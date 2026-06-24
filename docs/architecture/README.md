# Architecture Notes

This repo models an enterprise agent connectivity platform around agentgateway as the shared control point for LLM and MCP traffic.

## Planes

- Client plane: OpenAI-compatible clients, MCP clients, and operator workflows.
- Gateway plane: agentgateway standalone locally, with a kind/Helm promotion path.
- Identity plane: Keycloak-issued JWTs with tenant and role claims.
- Tool plane: Virtual MCP composed from stdio, HTTP, and OpenAPI-backed tools.
- Model plane: Ollama only, using `llama3.2:3b` for the laptop recording path, `qwen3.6:35b` for the high-reasoning workstation profile, and `gpt-oss:120b` / `deepseek-r1:671b-0528-q4_K_M` as heavyweight/max-reasoning references.
- Observability plane: OpenTelemetry Collector, Prometheus, Grafana, and Jaeger.

## Design Rules

- Keep demo workloads in `examples/`; keep platform config in `config/`.
- Keep deployment concerns in `deploy/`, separated by Docker vs Kubernetes.
- Treat upstream `agentgateway/agentgateway` as reference-only; do not vendor source code here.
- Prefer least privilege and tenant-aware examples even in local demos.
