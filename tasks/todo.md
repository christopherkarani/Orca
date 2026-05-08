# Phase 31 Flight Safety Enforcement

## Assumptions

- The prompt-named `README_START_HERE.md`, `CODEX_MASTER_PROMPT_EDGE.md`, `context/`, `checklists/`, and `phases/31_FLIGHT_SAFETY_ENFORCEMENT.md` files are absent from this checkout. The active contract is the Phase 31 prompt, existing Edge docs/code, current Phase 27-30 implementation, and project lessons.
- Phase 31 is fake-adapter, PX4 SITL, and ArduPilot SITL safety enforcement only. It must not add operator approval runtime, emergency-mode runtime beyond recommended fallback decisions, hardware bench deployment, real drone hardware integration, real-flight deployment, customer hardware procedures, SaaS, monetization, telemetry services, regulatory/certification claims, detect-and-avoid, autopilot replacement behavior, or real-flight instructions.
- The existing Phase 27 evaluator already enforces a subset of geofence, altitude, velocity, battery, freshness, mode, authority, and command-risk constraints. Phase 31 should harden and modularize that behavior rather than fork a competing decision engine.
- Normal tests must remain deterministic and offline. PX4 and ArduPilot SITL remain opt-in and may skip or fail closed when no live simulator transport exists.

## Research And False-Positive Check

- [x] Read Aegis memory and `tasks/lessons.md` for phase discipline, tracked-file hygiene, redaction, and SITL fake-vs-real boundaries.
- [x] Confirm absent prompt-named governing files instead of inventing their contents.
- [x] Inspect Edge domain, policy loader/evaluator, MAVLink gateway, PX4 adapter, ArduPilot adapter, audit, schema, docs, and examples.
- [x] Verify current baseline tests before implementation where useful.
- [x] Re-check that new code does not overclaim real hardware, detect-and-avoid, autopilot replacement, or certification.

## TDD / Implementation Checklist

- [x] Add Phase 31 safety tests first for envelope validation, structured findings, command risk defaults, geofence, altitude, velocity, battery, freshness, mode/authority, mission safety, CLI output, audit/redaction, and MAVLink/PX4/ArduPilot integration.
- [x] Add reusable `packages/edge/src/safety/` modules for compiled envelopes, evaluator, constraint helpers, structured findings, mission checks, and reports.
- [x] Keep `policy.evaluateEdgeAction` compatible while exposing the new safety evaluator API.
- [x] Harden policy/envelope validation for positive velocity limits, positive geofence radius, battery thresholds, deny-priority command conflicts, unsupported geofence shape reporting, and explicit altitude references.
- [x] Add mission safety request/state parsing and deterministic mission evaluation for upload/start decisions.
- [x] Wire safety event names and structured finding payloads through Core audit where current event model allows bounded redacted payloads.
- [x] Wire MAVLink, PX4, and ArduPilot fake/SITL paths through the safety evaluator without relabeling fake evidence as SITL.
- [x] Add `aegis-edge safety check`, `safety evaluate`, `safety explain`, `safety scenario run`, and `safety doctor`.
- [x] Create deterministic examples under `examples/edge/safety/` for policies, requests, states, and scenarios.
- [x] Update docs under `docs/edge/` and `packages/edge/README.md` with supported/unsupported safety behavior and simulation-only limits.

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
- [x] `./zig-out/bin/aegis-edge safety doctor`
- [x] `./zig-out/bin/aegis-edge safety evaluate --policy examples/edge/safety/policies/safety-geofence-basic.yaml --request examples/edge/safety/requests/waypoint-outside-geofence.json --state examples/edge/safety/states/fresh-state.json`
- [x] `./zig-out/bin/aegis-edge safety evaluate --policy examples/edge/safety/policies/safety-battery-basic.yaml --request examples/edge/safety/requests/takeoff-low-battery.json --state examples/edge/safety/states/low-battery-state.json`
- [x] `./zig-out/bin/aegis-edge safety evaluate --policy examples/edge/safety/policies/safety-geofence-basic.yaml --request examples/edge/safety/requests/land.json --state examples/edge/safety/states/stale-state.json`
- [x] `./zig-out/bin/aegis-edge safety scenario run --policy examples/edge/safety/policies/safety-strict.yaml --scenario examples/edge/safety/scenarios/mission-outside-geofence-deny.yaml`
- [x] Manual safety checks from the Phase 31 prompt.
- [x] `git diff --check`

## Review

- Implemented Phase 31 as a reusable `edge.safety` package with compiled envelopes, structured findings, command evaluation, mission evaluation, reports, deterministic scenario artifacts, and CLI commands.
- Added `aegis-edge safety doctor/check/evaluate/explain/scenario run`.
- MAVLink gateway now calls the safety evaluator directly; PX4 and ArduPilot adapters inherit that through their existing gateway delegation while preserving fake/PX4/ArduPilot provenance labels.
- Added deterministic safety policies, requests, states, and scenarios under `examples/edge/safety/`.
- Added docs for flight safety enforcement, envelope compilation, geofence, altitude/velocity, battery, state freshness, mission safety, findings, and simulation-vs-flight boundaries.
- Added Core and Edge schema event names for safety evaluation/finding/mission events and extended safety report schema with structured findings.
- Fixed the Edge CLI JSON request/state parser lifetime bug by adding owned parse handles for CLI evaluation paths.
- Verification passed: `zig build`, `zig build test`, `git diff --check`, requested Aegis CLI smokes, requested `aegis-edge` safety smokes, PX4 fake scenario, ArduPilot fake scenario, secret-redaction grep, and docs boundary grep.
- Known limitations: circle geofences only; no polygon support; no coordinate-frame conversion; no altitude-reference conversion; no real hardware integration; SITL remains opt-in; no operator approval runtime; no emergency runtime beyond fallback recommendations; no detect-and-avoid; no certification or real-flight readiness.

## Review Fix Plan

- [x] Add regression tests proving stale `land` and `return_to_home` deny when the policy disables those emergency actions, even if the command list allows them.
- [x] Patch freshness evaluation so emergency stale-state handling has an explicit deny path instead of only skipping the allow exception.
- [x] Re-run focused and full Zig verification, then document the result here.

## Review Fix Result

- Added a failing Phase 31 regression for stale `land` and `return_to_home` when `safety.emergency.allow_land` or `allow_return_to_home` is false while command rules still allow the action.
- Fixed `evaluateFreshness` to return an explicit stale-state denial and audit event for disabled emergency stale-state actions before falling through to ordinary command allow behavior.
- Verification: new regression first failed with stale `land` returning `allow`; after the fix, `zig build test --summary all`, `zig build`, `zig build test`, and `git diff --check` passed.
