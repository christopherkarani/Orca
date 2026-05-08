# Phase 33 Edge Audit/Replay and Safety Case

## Assumptions

- The prompt-named `README_START_HERE.md`, `CODEX_MASTER_PROMPT_EDGE.md`, `context/`, `checklists/`, and `phases/33_EDGE_AUDIT_REPLAY_AND_SAFETY_CASE.md` files are absent from this checkout. The active contract is the Phase 33 prompt, root Aegis contracts, current Edge docs/code, existing examples, Phase 32 notes, and `tasks/lessons.md`.
- Phase 33 is limited to evidence production: Edge audit sessions, replay, safety-case reports, evidence bundles, traceability, scenario result classification, docs, examples, and regression tests.
- Phase 33 must not add Phase 34 red-team/fault-injection work, Phase 35 telemetry/data guard work, hardware bench deployment, real drone integration, real-flight procedures, SaaS, monetization, telemetry, detect-and-avoid, autopilot replacement behavior, or certification/regulatory claims.
- Edge audit persistence must reuse Aegis Core audit writer/replay/hash-chain APIs. Any Edge-specific session layout must be a namespaced use of the Core writer rather than a duplicate independent writer.
- Normal tests must remain deterministic, offline, bounded, and fake/SITL-aware. Missing PX4 or ArduPilot SITL must be skipped/unsupported, not passed.

## Research And False-Positive Check

- [x] Read Aegis memory and `tasks/lessons.md` for phase discipline, Core audit reuse, redaction, fake-vs-SITL boundaries, tracked-file hygiene, and requested smoke-gate expectations.
- [x] Confirm absent prompt-named governing files instead of inventing their contents.
- [x] Inspect Core audit writer/replay/hash-chain summary interfaces and identify the smallest compatible namespace change for `.aegis-edge`.
- [x] Inspect Edge safety, MAVLink, PX4, ArduPilot, approval, and emergency scenario flows for reusable evidence inputs.
- [x] Inspect docs/examples/schemas/tests for no-real-flight claims, missing report examples, and Phase 33 coverage gaps.
- [x] Re-check before handoff that docs and outputs do not imply real-flight readiness, certification, detect-and-avoid, or autopilot replacement.

## TDD / Implementation Checklist

- [x] Add Phase 33 tests for Edge audit sessions: `.aegis-edge/last`, `events.jsonl`, `summary.json`, `summary.md`, hash-chain success, tampered/deleted/reordered failure, redaction before persistence, bounded payloads, and Core writer reuse.
- [x] Add replay tests for `last`, `--verify`, `--json`, `--findings`, `--commands`, `--approvals`, missing-session errors, provenance display, and fake-secret non-leakage.
- [x] Add safety-case tests for geofence-deny, low-battery emergency, mission-deny, JSON shape, Markdown limitations/disclaimer, policy hash, event references, safety findings, fake/PX4/ArduPilot provenance distinctions, and no real-flight claims.
- [x] Add evidence bundle tests for policy/scenario copies, environment metadata, event log, replay, reports, findings, commands, approvals, limitations, final hash, missing evidence errors, and secret exclusion.
- [x] Add traceability tests linking denied commands to rules/findings/events, findings to events, approvals to commands, emergency decisions to reasons/findings, and skipped/unsupported statuses.
- [x] Add scenario-result classification tests for passed, failed, skipped, unsupported, and inconclusive, including missing SITL not being counted as pass.
- [x] Implement `packages/edge/src/audit/` modules for Edge events, sessions, replay, summaries, artifacts, hash-chain verification, safety reports, evidence bundles, traceability, and tests.
- [x] Extend Core audit APIs only as needed to support a namespaced `.aegis-edge` session root while preserving existing `.aegis` CLI compatibility.
- [x] Wire `aegis-edge replay ...` and `aegis-edge safety-case ...` commands with human output by default and bounded JSON where requested.
- [x] Generate deterministic example safety-case reports under `examples/edge/safety-case/`.
- [x] Update Edge docs and package README for audit/replay, safety-case reports, evidence bundles, traceability, scenario results, customer reports, and simulation-vs-flight boundaries.

## Verification Checklist

- [x] `zig build`
- [x] `zig build test`
- [x] `./zig-out/bin/aegis --help`
- [x] `./zig-out/bin/aegis version`
- [x] `./zig-out/bin/aegis doctor`
- [x] `./zig-out/bin/aegis run -- echo hello`
- [x] `./zig-out/bin/aegis replay --session last --verify`
- [x] `./zig-out/bin/aegis redteam --ci`
- [x] `./zig-out/bin/aegis-edge --help`
- [x] `./zig-out/bin/aegis-edge doctor`
- [x] `./zig-out/bin/aegis-edge safety-case generate --scenario examples/edge/safety/scenarios/geofence-deny.yaml --policy examples/edge/safety/policies/safety-strict.yaml`
- [x] `./zig-out/bin/aegis-edge safety-case show --session last`
- [x] `./zig-out/bin/aegis-edge safety-case verify --session last`
- [x] `./zig-out/bin/aegis-edge safety-case bundle --session last`
- [x] `./zig-out/bin/aegis-edge replay --session last --verify`
- [x] `./zig-out/bin/aegis-edge replay --session last --findings`
- [x] `./zig-out/bin/aegis-edge replay --session last --commands`
- [x] `./zig-out/bin/aegis-edge replay --session last --approvals`
- [x] Manual checks: reports generated in JSON and Markdown, limitations and non-certification disclaimer present, fake/PX4 SITL/ArduPilot SITL provenance distinct, missing SITL not pass, fake secrets absent from persistent outputs, tamper verification fails, traceability links denied command to rule/finding/event, docs avoid real hardware or real-flight readiness claims, PX4/ArduPilot/safety/operator/CLI behavior unchanged.
- [x] `git diff --check`

## Review Fixes

- [x] Include Phase 33 source, test, doc, and example additions in the review diff via intent-to-add so clean-checkout builds can resolve `packages/edge/src/audit/mod.zig` and `tests/phase33_edge_audit_replay_safety_case.zig`.
- [x] Remove duplicate `errdefer allocator.free(order)` in `packages/edge/src/emergency/mod.zig` so the fallback ladder has a single error-path owner for the reordered command slice.
- [x] Remove tracked generated `.aegis-edge/sessions/last` approval artifacts from the patch and keep generated Edge session state ignored.
- [x] Re-run focused build/test and status checks after review fixes.

## Review

- Phase 33 implementation is complete within the requested boundary. Edge now has Core-backed `.aegis-edge` audit sessions, replay surfaces, safety-case JSON/Markdown reports, directory evidence bundles, traceability artifacts, scenario status classification, docs, examples, and regression coverage.
- Verification passed locally for the requested build/test/CLI commands. PX4 and ArduPilot SITL-missing paths are represented as skipped or unsupported, not passed. The generated reports and docs keep fake/SITL/bench provenance distinct and include non-certification/no-real-flight limitations.
- Known limitation: bundle packaging currently emits a deterministic directory bundle, not a `.tar.gz` archive. Real hardware, real-flight deployment, detect-and-avoid, certification, telemetry, SaaS, and Phase 34 fault-injection work remain intentionally unsupported.
