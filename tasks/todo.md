# Phase 25 Aegis CLI v1.1 Hardening

## Assumptions

- Phase 25 is a CLI hardening phase after the Core/CLI/Edge split, not a new runtime-feature phase.
- The Edge governing documents named in the task are not present in this checkout; the task prompt, current repo docs, package READMEs, security invariants, architecture contracts, prior lessons, and Phase 23/24 handoffs are the active contract.
- `aegis` remains the stable desktop/CI CLI product and all v1.0 commands must keep working.
- Aegis Core remains the single policy, decision, audit, replay, redaction, schema, and shared red-team engine.
- Aegis Edge remains scaffold-only. No MAVLink, PX4, ArduPilot, drone command enforcement, flight safety enforcement, real-flight behavior, operator approval flows, telemetry, SaaS, monetization, or regulatory/certification claims belong in this phase.

## Research And False-Positive Check

- [x] Reviewed memory, `tasks/lessons.md`, package contracts, security docs, policy docs, MCP docs, replay docs, release docs, and package templates.
- [x] Baseline `zig build`, `zig build test`, and representative v1.0/v1.1 smoke commands passed before patching.
- [x] Inventoried CLI policy/audit/redaction/replay/schema call sites and routed confirmed product calls through `src/core/api.zig`.
- [x] Re-checked suspected MCP/docs/package issues against source evidence and command output before patching.
- [x] Re-checked docs and package templates for Edge real-flight, autopilot, MAVLink, PX4, ArduPilot, certification, telemetry, SaaS, and monetization claims.

## TDD / Implementation Checklist

- [x] Added Phase 25 hardening tests for command/package/docs/Core contract regression.
- [x] Hardened CLI policy paths through Core-backed load/discover/explain APIs.
- [x] Hardened CLI audit/replay paths through Core-backed writer, summary, redaction, and replay APIs.
- [x] Kept mode behavior covered by existing run/redteam tests plus CI ask-to-deny smoke checks.
- [x] Validated built-in policies, presets, example policies, invalid policy paths, explanations, and deny-over-allow behavior.
- [x] Hardened MCP inspect policy UX, MCP proxy invalid-policy error handling, JSON-RPC stdout verification, manifest check, and dynamic MCP client version metadata.
- [x] Re-verified command, file, network, shim, staging, URL redaction, and capability reporting coverage.
- [x] Re-verified doctor output for version, policy, audit/replay, red-team fixtures, MCP, command guard, file staging, network capabilities, backend levels, and no secret leakage.
- [x] Updated CLI docs, package docs, install/release docs, MCP docs, and packaging templates for v1.1 and post-split accuracy.
- [x] Updated source only for confirmed Phase 25 gaps; Edge remains scaffold-only.

## Verification Checklist

- [x] `zig build`
- [x] `zig build test`
- [x] `zig build fuzz`
- [x] `./zig-out/bin/aegis --help`
- [x] `./zig-out/bin/aegis version`
- [x] `./zig-out/bin/aegis version --json`
- [x] `./zig-out/bin/aegis init`
- [x] `./zig-out/bin/aegis init --preset generic-agent`
- [x] `./zig-out/bin/aegis init --preset strict-local`
- [x] `./zig-out/bin/aegis init --preset trusted-local`
- [x] `./zig-out/bin/aegis doctor`
- [x] `./zig-out/bin/aegis run -- echo hello`
- [x] `./zig-out/bin/aegis replay --session last`
- [x] `./zig-out/bin/aegis replay --session last --verify`
- [x] `./zig-out/bin/aegis policy check` for every built-in and preset policy: 15 files.
- [x] `./zig-out/bin/aegis policy check` for every example policy: 3 policy files.
- [x] `./zig-out/bin/aegis policy explain file.read .env`
- [x] `./zig-out/bin/aegis policy explain command "rm -rf /"`
- [x] `./zig-out/bin/aegis policy explain network api.github.com`
- [x] `./zig-out/bin/aegis diff`
- [x] `./zig-out/bin/aegis apply`
- [x] `./zig-out/bin/aegis discard`
- [x] `./zig-out/bin/aegis mcp inspect`
- [x] `./zig-out/bin/aegis mcp proxy` with `fixtures/mcp/fake_client.py` stdin.
- [x] `./zig-out/bin/aegis mcp list`
- [x] `./zig-out/bin/aegis mcp manifest check examples/mcp/demo-manifest.yaml`
- [x] `./zig-out/bin/aegis redteam`
- [x] `./zig-out/bin/aegis redteam --json`
- [x] `./zig-out/bin/aegis redteam --ci`
- [x] `./zig-out/bin/aegis completions bash`
- [x] `./zig-out/bin/aegis completions zsh`
- [x] `./zig-out/bin/aegis completions fish`
- [x] `./zig-out/bin/aegis completions powershell`
- [x] `./zig-out/bin/aegis-edge --help`
- [x] `./zig-out/bin/aegis-edge doctor`
- [x] CLI quickstart still works in a temp workspace.
- [x] Leaky-agent demo still works.
- [x] Replay verify detects tampering.
- [x] Fake secrets do not appear in repo `.aegis`, temp persistent outputs, or replay output.
- [x] MCP fake server tests and manual proxy smoke pass.
- [x] Temporary release artifacts include runtime assets: policies, schemas, fixtures, examples, packages, packaging, scripts, and docs.
- [x] Install/release docs and package templates match CLI artifacts.
- [x] Edge scaffold docs do not claim active drone support.
- [x] `./scripts/validate-docs.sh`
- [x] Package syntax checks for shell, Ruby, JSON, and npm wrapper JavaScript.
- [x] `git diff --check`

## Review Fix Checklist

- [x] Regenerated checked-in `dist/` release artifacts for `v1.1.0`.
- [x] Removed stale `v1.0.0` archives and generated `dist/work/` payloads from the committed release surface.
- [x] Removed accidental binary archive committed as `EdgeRunner_MLX_long_prompt_report.md`.

## Review

- Added `src/core/api.zig` as the in-tree Core facade and re-exported it through `packages/core/src/api.zig`.
- Routed CLI policy, replay, doctor, run, MCP, apply, discard, and shim audit/replay/policy calls through Core API wrappers instead of product-local engine calls.
- Hardened MCP inspect so `--policy` now evaluates listed tools through Core policy; hardened MCP proxy invalid-policy errors; removed hard-coded `1.0.0` MCP client metadata.
- Added Phase 25 regression coverage for release payload assets, Windows package layout, npm placeholder honesty, MCP docs, Edge scaffold boundaries, Core facade behavior, and deterministic security mutations under default `zig build test`.
- Updated v1.1.0 version metadata, install/release scripts, package templates, docs, MCP examples, and package READMEs.
- Docker build could not be run because the local Docker daemon is not running. `docker --version` works, but `docker build` cannot connect to `/Users/chriskarani/.docker/run/docker.sock`.
