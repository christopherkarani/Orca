# Phase 29 PX4 SITL Integration

## Assumptions

- The prompt-named governing documents under `context/`, `phases/`, and `checklists/` are absent from this checkout. The active contract is the Phase 29 prompt, existing Edge docs/code, and prior Aegis phase lessons.
- Phase 29 is PX4 SITL simulation integration only. It must not add ArduPilot SITL, real drone hardware integration, real-flight deployment, customer hardware procedures, SaaS, monetization, telemetry services, certification claims, or detect-and-avoid claims.
- PX4 SITL may not be installed locally. Normal `zig build test` must pass with deterministic fake-PX4 coverage only; real PX4 checks must be opt-in and clearly skipped or unavailable otherwise.
- The Phase 28 MAVLink gateway remains the command mediation core. PX4 code should wrap it and preserve MAVLink policy semantics rather than fork command policy logic.

## Research And False-Positive Check

- [x] Read Aegis memory for phase discipline, Zig verification expectations, and Phase 28 MAVLink implementation notes.
- [x] Confirm absent prompt-named `context/`, `phases/`, and `checklists/` files instead of inventing their contents.
- [x] Inspect Edge domain, policy, MAVLink gateway, CLI, and audit/redaction surfaces.
- [x] Verify fake-vs-SITL provenance boundaries in existing state and command types.
- [x] Check docs/examples for claims that need updating or preserving.

## TDD / Implementation Checklist

- [x] Add Phase 29 tests first for fake PX4 telemetry mapping, command mediation, scenario artifacts, doctor output, redaction, and SITL gating.
- [x] Add `packages/edge/src/px4/` modules for configuration, connection status, fake adapter, telemetry mapping, command mediation, scenario runner, health/doctor reporting, and audit artifacts.
- [x] Reuse Phase 28 MAVLink gateway for mapped command decisions in observe/enforce/simulation/ci modes.
- [x] Add deterministic fake-PX4 adapter behavior with heartbeat, position, battery, ACK-like records, and explicit `fake_px4_adapter`/`fake_adapter` provenance.
- [x] Add opt-in PX4 SITL detection and integration-test gating using `AEGIS_EDGE_RUN_PX4_SITL_TESTS=1` and endpoint configuration.
- [x] Wire `aegis-edge px4 doctor`, `px4 scenario run`, `px4 observe`, `px4 gateway`, and `px4 test-fixture` with safe defaults and honest limitations.
- [x] Add deterministic examples under `examples/edge/px4/`.
- [x] Add/update docs under `docs/edge/` and `packages/edge/README.md` without real-flight, hardware, ArduPilot, detect-and-avoid, or certification claims.

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
- [x] `./zig-out/bin/aegis-edge px4 doctor`
- [x] `./zig-out/bin/aegis-edge px4 scenario run --policy examples/edge/px4/policies/px4-geofence-basic.yaml --scenario examples/edge/px4/scenarios/waypoint-outside-geofence-deny.yaml`
- [x] `./zig-out/bin/aegis-edge px4 scenario run --policy examples/edge/px4/policies/px4-geofence-basic.yaml --scenario examples/edge/px4/scenarios/land-allow.yaml`
- [x] `./zig-out/bin/aegis-edge px4 scenario run --policy examples/edge/px4/policies/px4-geofence-basic.yaml --scenario examples/edge/px4/scenarios/disable-failsafe-deny.yaml`
- [x] Manual: fake PX4 scenario distinguishes fake adapter from PX4 SITL.
- [x] Manual: missing PX4 SITL causes a clear skip/unavailable result, not a fake pass.
- [x] Manual: waypoint outside geofence is denied.
- [x] Manual: disable_failsafe is denied.
- [x] Manual: land is allowed/logged according to policy.
- [x] Manual: unknown commands are not treated as safe.
- [x] Manual: fake secrets do not appear in persistent outputs.
- [x] Manual: docs do not claim ArduPilot integration, real hardware, real-flight readiness, detect-and-avoid, or certification.
- [x] `git diff --check`

## Review

- Implemented Phase 29 PX4 SITL integration as simulation-only Edge work.
- Added `packages/edge/src/px4/` with connection config/gating, fake-PX4 fixture adapter, telemetry-to-`VehicleState` mapping, gateway-backed command mediation, scenario runner, health/doctor output, and redacted audit/replay artifact writing.
- Reused the Phase 28 MAVLink gateway and Phase 27 Edge policy engine for command decisions. PX4 mediation now passes the command source provenance explicitly so fake-PX4 remains `fake_adapter` and opt-in PX4 SITL can use `sitl_px4`.
- Added deterministic fake-PX4 tests and examples for heartbeat/state mapping, geofence denial, land allow/logging, disable-failsafe denial, raw actuator denial, low-battery takeoff denial, scenario artifact redaction, doctor output, and PX4 SITL opt-in gating.
- Added `aegis-edge px4 doctor`, `px4 scenario run`, `px4 observe`, `px4 gateway`, and `px4 test-fixture` with safe simulation defaults and explicit limitations.
- Updated Edge docs, schemas prose, and examples to replace obsolete fake-only/PX4-unimplemented wording while preserving no ArduPilot, no hardware, no real-flight, no detect-and-avoid, and no certification boundaries.
- PX4 SITL support status: partial/configured and opt-in. No live PX4 endpoint was available or required during this run.
- Fake-PX4 adapter status: active for deterministic unit tests, examples, and scenario artifacts.
- Tested PX4 version policy: `documented-by-phase-29` by default; local opt-in runs can set `AEGIS_EDGE_PX4_TESTED_VERSION`.
- Integration-test gating: normal tests skip PX4 SITL; `AEGIS_EDGE_RUN_PX4_SITL_TESTS=1` plus `AEGIS_EDGE_PX4_ENDPOINT=host:port` is required for SITL integration runs.
- Security notes: scenario notes and artifact strings pass through Core redaction; synthetic fake secret values were not present in generated artifacts.
- Acceptance status: normal build/test and requested CLI smokes passed; Phase 30 can start from this Phase 29 baseline after review.

# Phase 29 Review Fixes - 2026-05-08

## Assumptions

- Review comments are actionable correctness defects, not feature requests for future phases.
- Fixes should remain scoped to PX4 SITL configuration ownership, SITL-required scenario gating, and the public Edge policy schema.
- Normal unit tests must still use fake-PX4 by default and must not require PX4 SITL.

## TDD / Implementation Checklist

- [x] Add a regression proving PX4 endpoint host slices returned from env/config helpers remain valid after the source env buffer is freed.
- [x] Add a regression proving `requires_px4_sitl: true` cannot record a fake-PX4 pass when the scenario metadata omits or misstates `environment: px4_sitl`.
- [x] Add schema regression coverage for circle geofence required fields and the runtime-supported `safety.altitude` block.
- [x] Fix `integrationTestGateFromEnv` ownership and add a harmless deinit path for owned gate data.
- [x] Fix PX4 scenario gating to reject inconsistent SITL-required metadata before fake execution.
- [x] Align `schemas/edge-policy-v1.json` with the policy loader for circle geofences and altitude limits.

## Verification Checklist

- [x] `zig build test --summary all`
- [x] `zig build`
- [x] `AEGIS_EDGE_RUN_PX4_SITL_TESTS=1 AEGIS_EDGE_PX4_ENDPOINT=127.0.0.1:14540 ./zig-out/bin/aegis-edge px4 doctor`
- [x] `./zig-out/bin/aegis-edge px4 scenario run --policy examples/edge/px4/policies/px4-geofence-basic.yaml --scenario examples/edge/px4/scenarios/waypoint-outside-geofence-deny.yaml`
- [x] `./zig-out/bin/aegis-edge px4 scenario run --policy examples/edge/px4/policies/px4-geofence-basic.yaml --scenario examples/edge/px4/scenarios/sitl-observe-heartbeat-skip.yaml`
- [x] `git diff --check`

## Review

- Fixed `integrationTestGateFromEnv` so env-derived endpoint hosts are copied into owned gate storage with `IntegrationGate.deinit`.
- Updated CLI PX4 doctor/scenario paths to keep the owned integration gate alive while reporting endpoint configuration and running scenarios.
- Rejected scenarios that set `requires_px4_sitl: true` without `environment: px4_sitl`, preventing fake-PX4 execution from masquerading as SITL-required evidence.
- Aligned `schemas/edge-policy-v1.json` with the runtime loader by requiring circle `center` and `max_radius_m`, constraining geofence type to implemented `circle`, removing advertised `vertices`, and adding the supported `safety.altitude` block.
- Added regressions for endpoint ownership, SITL-required metadata gating, and schema/runtime alignment.
- Verification passed: `zig build test --summary all`, `zig build`, env-enabled `aegis-edge px4 doctor`, fake geofence scenario, missing-SITL skip scenario, and `git diff --check`.
