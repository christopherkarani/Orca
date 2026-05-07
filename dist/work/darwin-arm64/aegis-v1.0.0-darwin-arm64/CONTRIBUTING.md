# Contributing

## Development Requirements

- Use Zig `0.15.2`.
- Run `zig build` and `zig build test` before handing off changes.
- Keep changes scoped to the active phase.
- Do not add dependencies without documenting them in `docs/dev/dependencies.md`.
- Do not add SaaS, telemetry, billing, monetization, cloud dashboards, or model-provider integrations unless a future phase explicitly requires them.

## Security-sensitive Work

- Do not persist raw secrets in logs, fixtures, reports, docs, tests, or snapshots.
- Route future enforcement decisions through the policy layer.
- Route future persistent security events through the audit/redaction path.
- Document unsupported protection as `limited`, `observe`, or `unavailable`; do not call it active.
