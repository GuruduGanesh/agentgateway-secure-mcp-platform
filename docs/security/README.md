# Security Model

The demo security model is intentionally simple but enterprise-shaped.

## Identity

- Identity provider: local Keycloak.
- Realm: `agentgateway`.
- Client: `agentgateway-demo`.
- Token claims: `tenant` and `roles`.

## Personas

- `alice-reader`: tenant `tenant-a`, role `reader`.
- `oliver-operator`: tenant `tenant-b`, role `operator`.

## Authorization Intent

- Readers can discover and call read-only tools.
- Operators can call read and write tools scoped to their tenant.
- Cross-tenant requests should be denied.
- Real deployments should map roles/groups from enterprise IdP claims rather than demo local users.

## Secret Handling

- `.env`, private keys, local databases, logs, traces, and scratch output are ignored.
- Local-only working files and private notes are git-ignored and never staged.
