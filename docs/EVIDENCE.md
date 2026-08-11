# Evidence status

The files under `assets/screenshots/` and `artifacts/proof-text/` were captured on
2026-07-01 against the earlier v1.3.1-era demo. They are retained as historical
visual/context material only. In particular, the older RBAC capture shows the
superseded seven-check output and must not be used as evidence for the current
tenant-isolation implementation.

The current v1.4.0 evidence is executable and local:

- `tests/smoke/smoke-llm.ps1` for M1.
- `tests/smoke/smoke-m2.ps1` for M2.
- `tests/smoke/smoke-mcp.ps1` for M3.
- `tests/smoke/smoke-rbac.ps1` for the 13 M4 checks.
- `tests/smoke/smoke-observability.ps1` for M5.
- `tests/smoke/smoke-k8s.ps1 -Apply -E2E` for M6.

The CI workflow at `.github/workflows/validate.yml` guards PowerShell parsing,
Node syntax, and each standalone Compose profile. It should be included in the
next commit with the associated upgrade changes.
