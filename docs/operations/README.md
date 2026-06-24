# Operations Notes

## Local Profiles

- `laptop`: agentgateway standalone to local Ollama with `llama3.2:3b`.
- `llm`: high-reasoning agentgateway standalone profile for larger workstations.
- `security`: Keycloak plus the secure MCP gateway, HTTP tools, and OpenAPI app.
- `observability`: OpenTelemetry Collector, Prometheus, Grafana, and Jaeger.

## Common Commands

```powershell
docker compose -f deploy/docker/docker-compose.yml --profile observability --profile laptop up -d
docker compose -f deploy/docker/docker-compose.yml --profile observability --profile llm up -d
docker compose -f deploy/docker/docker-compose.yml --profile security up -d
docker compose -f deploy/docker/docker-compose.yml --profile observability up -d
docker compose -f deploy/docker/docker-compose.yml down
```

## Validation

Smoke tests live in `tests/smoke/`:

```powershell
.\tests\smoke\smoke-llm.ps1
.\tests\smoke\smoke-mcp.ps1
.\tests\smoke\smoke-rbac.ps1
.\tests\smoke\smoke-observability.ps1
```

## Troubleshooting

- If LLM smoke tests fail, confirm Ollama is running on `http://localhost:11434`.
- If Docker cannot reach Ollama, confirm `host.docker.internal` resolves from the container.
- If Keycloak tokens fail, wait for Keycloak startup to finish realm import.
- If Grafana is empty, confirm Prometheus can scrape the OpenTelemetry Collector.
- LLM call returns 401: strict API-key auth — send `Authorization: Bearer sk-demo-reader-local`.
- `/metrics` 404 on `:15000`: metrics are on the stats listener `:15020`, not the admin port.
- Gateway exits 1 on `unknown field 'admin'` or `SimpleLocalBackend`: invalid config keys — see SETUP.md troubleshooting.
- stdio MCP target fails (`exec node: not found`): the gateway image is distroless; run the stdio server as its own container/sidecar.
- `port is already allocated` / ports exposed-but-not-published: `docker compose ... down` then `up -d --force-recreate`.

Full setup, ports, credentials, and troubleshooting table: [../SETUP.md](../SETUP.md).
