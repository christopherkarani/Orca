# Contributing

## Development Requirements

- Use Zig `0.16.0` (see `.zigversion`).
- Prefer the pinned wrapper so the correct compiler is always used:
  - `./scripts/ensure-zig-toolchain.sh --install` (first time)
  - `./scripts/zig build`, `./scripts/zig build test-fast`, and `./scripts/zig build test`
  - Or: `direnv allow` (`.envrc`) / `eval "$(./scripts/ensure-zig-toolchain.sh --export)"` then `zig` is 0.16.0 on PATH.
- Day-to-day: `./scripts/test-fast.sh` (build + focused tests + quick-install checks).
- Before merge/PR: `./scripts/verify-pre-merge.sh` (fast gate + full `zig build test`).
- Coding agents: read `AGENTS.md` → **Zig toolchain**.
- Keep changes scoped to the active phase.
- Do not add dependencies without documenting them in `docs/dev/dependencies.md`.
- Do not add SaaS, telemetry, billing, monetization, cloud dashboards, or model-provider integrations unless a future phase explicitly requires them.

## Security-sensitive Work

- Do not persist raw secrets in logs, fixtures, reports, docs, tests, or snapshots.
- Route future enforcement decisions through the policy layer.
- Route future persistent security events through the audit/redaction path.
- Document unsupported protection as `limited`, `observe`, or `unavailable`; do not call it active.
