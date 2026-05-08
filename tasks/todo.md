# Phase 30 ArduPilot SITL Integration

## Assumptions

- The prompt-named `README_START_HERE.md`, `CODEX_MASTER_PROMPT_EDGE.md`, `context/`, `checklists/`, and `phases/30_ARDUPILOT_SITL_INTEGRATION.md` files are absent from this checkout. The active contract is the Phase 30 prompt, existing Edge docs/code, current Phase 28-29 implementation, and project lessons.
- Phase 30 is ArduPilot SITL simulation integration only. It must not add real drone hardware integration, real-flight deployment, customer hardware procedures, SaaS, monetization, telemetry services, regulatory/certification claims, detect-and-avoid, or autopilot replacement behavior.
- ArduPilot SITL may not be installed locally. Normal `zig build test` must pass with deterministic fake-ArduPilot coverage only; real ArduPilot SITL checks must be opt-in and clearly skipped or unavailable otherwise.
- The Phase 28 MAVLink gateway remains the command mediation core. ArduPilot code should wrap it and preserve MAVLink policy semantics rather than fork command policy logic.
- Phase 29 PX4 SITL behavior is a regression boundary. ArduPilot support must not relabel fake results as SITL, must not change PX4 provenance, and must not claim PX4 and ArduPilot semantics are identical.

## Research And False-Positive Check

- [x] Read Aegis memory and `tasks/lessons.md` for phase discipline, Zig verification expectations, and Phase 29 SITL gating lessons.
- [x] Confirm absent prompt-named governing files instead of inventing their contents.
- [x] Inspect Edge domain, policy, MAVLink gateway, PX4 adapter, CLI, and audit/redaction surfaces.
- [x] Verify fake-vs-SITL provenance boundaries in existing state and command types.
- [x] Check docs/examples for claims that need updating or preserving.

## TDD / Implementation Checklist

- [x] Add Phase 30 tests first for fake ArduPilot telemetry mapping, command mediation, scenario artifacts, doctor output, redaction, and SITL gating.
- [x] Add `packages/edge/src/ardupilot/` modules for configuration, connection status, vehicle kind, fake adapter, telemetry mapping, command mediation, scenario runner, health/doctor reporting, and audit artifacts.
- [x] Reuse the Phase 28 MAVLink gateway for mapped command decisions in observe/enforce/simulation/ci/redteam modes.
- [x] Add deterministic fake-ArduPilot adapter behavior with heartbeat, position, battery, ACK-like records, and explicit `fake_ardupilot_adapter` provenance.
- [x] Add opt-in ArduPilot SITL detection and integration-test gating using `AEGIS_EDGE_RUN_ARDUPILOT_SITL_TESTS=1`, endpoint configuration, and vehicle type.
- [x] Wire `aegis-edge ardupilot doctor`, `ardupilot scenario run`, `ardupilot observe`, `ardupilot gateway`, and `ardupilot test-fixture` with safe defaults and honest limitations.
- [x] Add deterministic examples under `examples/edge/ardupilot/`.
- [x] Add/update docs under `docs/edge/` and `packages/edge/README.md` without hardware, real-flight, detect-and-avoid, autopilot replacement, or certification claims.

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
- [x] `./zig-out/bin/aegis-edge ardupilot doctor`
- [x] `./zig-out/bin/aegis-edge ardupilot scenario run --policy examples/edge/ardupilot/policies/ardupilot-geofence-basic.yaml --scenario examples/edge/ardupilot/scenarios/waypoint-outside-geofence-deny.yaml`
- [x] `./zig-out/bin/aegis-edge ardupilot scenario run --policy examples/edge/ardupilot/policies/ardupilot-geofence-basic.yaml --scenario examples/edge/ardupilot/scenarios/land-allow.yaml`
- [x] `./zig-out/bin/aegis-edge ardupilot scenario run --policy examples/edge/ardupilot/policies/ardupilot-geofence-basic.yaml --scenario examples/edge/ardupilot/scenarios/rtl-allow.yaml`
- [x] `./zig-out/bin/aegis-edge ardupilot scenario run --policy examples/edge/ardupilot/policies/ardupilot-geofence-basic.yaml --scenario examples/edge/ardupilot/scenarios/disable-failsafe-deny.yaml`
- [x] Manual: fake ArduPilot scenario distinguishes fake adapter from ArduPilot SITL.
- [x] Manual: missing ArduPilot SITL causes a clear skip, not a fake pass.
- [x] Manual: waypoint outside geofence is denied.
- [x] Manual: disable_failsafe is denied.
- [x] Manual: land is allowed/logged according to policy.
- [x] Manual: RTL/RTH is allowed/logged according to policy.
- [x] Manual: unknown commands are not treated as safe.
- [x] Manual: fake secrets do not appear in persistent outputs.
- [x] Manual: docs do not claim real hardware or real-flight readiness.
- [x] Manual: docs distinguish ArduPilot from PX4.
- [x] Manual: PX4 behavior is unchanged.
- [x] Manual: CLI behavior is unchanged.
- [x] `git diff --check`

## Review

- Implemented Phase 30 ArduPilot SITL integration as simulation-only Edge work.
- Added `packages/edge/src/ardupilot/` with connection config/gating, vehicle-kind parsing, fake-ArduPilot fixture adapter, telemetry-to-`VehicleState` mapping, gateway-backed command mediation, scenario runner, health/doctor output, and redacted audit/replay artifact writing.
- Reused the Phase 28 MAVLink gateway and Phase 27 Edge policy engine for command decisions. ArduPilot mediation passes command source provenance explicitly so fake-ArduPilot remains `fake_ardupilot_adapter` and opt-in ArduPilot SITL can use `sitl_ardupilot`.
- Added deterministic fake-ArduPilot tests and examples for heartbeat/state mapping, geofence denial, land allow/logging, RTL allow/logging, disable-failsafe denial, raw actuator denial, low-battery takeoff denial, mission geofence denial, scenario artifact redaction, doctor output, and ArduPilot SITL opt-in gating.
- Added `aegis-edge ardupilot doctor`, `ardupilot scenario run`, `ardupilot observe`, `ardupilot gateway`, and `ardupilot test-fixture` with safe simulation defaults and explicit limitations.
- Updated Edge docs, schemas prose, and examples to replace obsolete ArduPilot-unimplemented wording while preserving no hardware, no real-flight, no detect-and-avoid, no autopilot replacement, and no certification boundaries.
- ArduPilot SITL support status: partial/configured and opt-in. No live ArduPilot SITL endpoint was available or required during this run.
- Live ArduPilot SITL scenario execution remains unavailable until a real transport exchange is implemented; SITL-labeled scenarios fail closed instead of executing fake frames as SITL evidence.
- Fake-ArduPilot adapter status: active for deterministic unit tests, examples, and scenario artifacts.
- Tested ArduPilot version policy: `documented-by-phase-30` by default; local opt-in runs can set `AEGIS_EDGE_ARDUPILOT_TESTED_VERSION`.
- Vehicle types supported: Copter-oriented scenarios are implemented first; Plane, Rover, Sub, and Unknown are parsed/reported with conservative mode mapping and unknown fallback.
- Integration-test gating: normal tests skip ArduPilot SITL; `AEGIS_EDGE_RUN_ARDUPILOT_SITL_TESTS=1` plus `AEGIS_EDGE_ARDUPILOT_ENDPOINT=host:port` and optional `AEGIS_EDGE_ARDUPILOT_VEHICLE=copter` is required for SITL integration runs.
- Security notes: scenario notes and artifact strings pass through Core redaction; synthetic fake secret values were not present in generated `.aegis/edge` artifacts.
- PX4 regression status: existing Phase 29 tests passed and a fake-PX4 geofence scenario still reports `fake_px4`/deny independently.
- CLI regression status: requested `aegis` help/version/doctor/run/replay/redteam checks passed.
- Acceptance status: normal build/test and requested CLI smokes passed; Phase 31 can start after review if no additional Phase 30 review findings are raised.

## Phase 30 Review Fixes

### Assumptions

- The reviewer findings are accepted as correctness issues to fix in this branch.
- Clean-checkout buildability requires the new Phase 30 files to be visible in the patch, not only present locally.
- Configured SITL environment metadata must not execute deterministic fake adapters and then label artifacts as SITL evidence.
- Built-in CLI schema printing must work from arbitrary cwd.
- Public schemas and runtime parsers must agree on supported event and policy fields.

### Checklist

- [x] Fail closed for configured PX4 SITL scenarios until a live PX4 transport exchange exists.
- [x] Add a PX4 regression proving configured SITL metadata cannot fake-pass.
- [x] Print Edge schemas from build-embedded checked-in schema documents instead of cwd paths.
- [x] Add CLI regressions for schema printing outside repo cwd and `policy explain` defaults for `set_heading`/`set_mode`.
- [x] Add runtime and JSON schema coverage for persisted `mavlink.*` audit event names.
- [x] Support `safety.geofence.home_position` in YAML and JSON policy loading.
- [x] Mark Phase 30 untracked files as part of the patch.
- [x] Regenerate release archives/checksums from the fixed tree.
- [x] Rerun required build, test, CLI smoke, artifact, and safety/doc checks.

### Current Evidence

- `zig build test --summary all` passed after review fixes: 37/37 build steps, 338/344 tests passed, 6 skipped.
- `zig build` passed.
- `zig build test` passed.
- `./scripts/build-release.sh` regenerated `dist/`; archive inspection confirmed `bin/aegis-edge`, ArduPilot docs/examples, and Phase 30 source files are present.
- `cd dist && shasum -a 256 -c checksums.txt` passed.
- `./zig-out/bin/aegis --help`, `version`, `doctor`, `run -- echo hello`, `replay --session last --verify`, and `redteam --ci` passed.
- `./zig-out/bin/aegis-edge --help`, `doctor`, `ardupilot doctor`, and requested ArduPilot scenario commands passed.
- Missing ArduPilot SITL skipped without a fake pass; configured ArduPilot and PX4 SITL scenario commands returned fail-closed live-transport unavailable errors.
- `git diff --check` passed.
