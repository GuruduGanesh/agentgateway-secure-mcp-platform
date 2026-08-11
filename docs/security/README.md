# Security Model

The demo security model is intentionally simple but enterprise-shaped.

## Identity

- Identity provider: local Keycloak.
- Realm: `agentgateway`.
- Client: `agentgateway-demo`.
- Token claims: `tenant` and `roles`.

## Personas

- `alice-reader`: tenant `tenant-a`, role `reader`.
- `brenda-reader`: tenant `tenant-b`, role `reader`.
- `oliver-operator`: tenant `tenant-b`, role `operator`.

## Authorization Intent

- Readers can discover and call read-only tools.
- Operators can call read and write tools when their token carries the demo operator tenant claim.
- Tenant scope is bound to the authenticated tool target and to the selected tenant-scoped backend. The demo accepts no caller-controlled tenant argument, and the RBAC smoke test exercises cross-tenant negative calls for both readers and the operator.
- Real deployments should map roles/groups from enterprise IdP claims rather than demo local users.

## Secret Handling

- `.env`, private keys, local databases, logs, traces, and scratch output are ignored.
- Local-only working files and private notes are git-ignored and never staged.
