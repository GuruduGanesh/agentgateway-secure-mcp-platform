# Hands-On with agentgateway: Building a Local Secure MCP Demo

Draft status: working draft, to revise after the full demo has been run end to end.

## Working Title

From Explainer to Hands-On: What I Learned Building a Local Secure MCP Platform with agentgateway

## Draft

I originally wrote about agentgateway from the platform architect's point of view: one data plane for LLM, MCP, A2A, and service traffic. The natural follow-up question from the project was the right one: have you actually used it?

This demo repo is my answer. I wanted a setup that is fully local, reproducible on a laptop, and honest about what is demo-grade versus production-grade. The first working slice is intentionally small: agentgateway in Docker, Ollama on the host, an OpenAI-compatible chat completion flowing through the gateway, and local OpenTelemetry plumbing ready to show what happened.

The most useful design decision was keeping two model profiles. The recording path uses a small Ollama model so the demo works on normal hardware. The high-reasoning profile documents larger local models for workstation-class machines, but I do not want the main walkthrough to depend on that hardware.

The second useful decision was treating MCP as a platform concern from the beginning. The repo includes a stdio MCP tool server, a streamable HTTP-style tool server, and an OpenAPI sample app. The target architecture is Virtual MCP: one governed endpoint, multiple local tool sources, Keycloak-issued identity, and target-level authorization rules.

What worked well:

- The standalone LLM path is simple and approachable.
- The Keycloak realm import gives a clean reader/operator tenant model.
- The OpenTelemetry docs map cleanly to a local Collector, Prometheus, Grafana, and Jaeger stack.
- The agentgateway config model is compact enough to explain in a short recording.

Gotchas I hit:

- It is easy to overstate milestones before the config is actually proven.
- Local model choice matters. A 35B or 120B model may be impressive, but it can break the "runs on my laptop" promise.
- MCP federation needs end-to-end validation. Having sample servers is not the same thing as proving Virtual MCP through the gateway.
- Kubernetes manifests should not claim "same policies as local" until the CRD policy fields are validated against the current release.

What I would harden before production:

- Replace demo keys and passwords with enterprise secret management.
- Add TLS/mTLS and a real OIDC provider integration.
- Move from local rate limits to a shared/global rate-limit backend where exact enforcement matters.
- Run the gateway highly available.
- Treat MCP tool policies like production authorization code: reviewed, tested, and audited.
- Promote all working standalone policies into Gateway API and agentgateway CRDs under GitOps.

The larger takeaway is simple: agent connectivity needs the same seriousness we already apply to service connectivity. The gateway becomes valuable when it is not just a route, but the place where identity, policy, observability, and operational control meet.
