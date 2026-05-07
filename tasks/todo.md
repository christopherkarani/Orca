# Phase 28 MAVLink Gateway Production

## Assumptions

- The prompt-named governing documents (`README_START_HERE.md`, `CODEX_MASTER_PROMPT_EDGE.md`, `context/...`, `checklists/MAVLINK_PX4_ARDUPILOT_REQUIREMENTS.md`, and `phases/28_MAVLINK_GATEWAY_PRODUCTION.md`) are not present in this checkout under those exact paths. The active contract is the user prompt, existing Edge Phase 26/27 domain and policy code, current Aegis Core audit/redaction APIs, existing docs, and prior project lessons.
- Phase 28 is a MAVLink gateway foundation only. It must stay local, deterministic, fake-transport based, and must not implement PX4 SITL, ArduPilot SITL, ROS2, real serial/UDP endpoints, real-flight deployment, SaaS, monetization, telemetry, certification claims, or operator approval runtime beyond policy decision hooks.
- MAVLink CRC validation will be implemented for the supported common-dialect subset with fixed CRC extra values. Unknown-message CRC validation will be reported as unsupported rather than guessed.
- `aegis-edge` exists and should gain `mavlink` subcommands while preserving existing `doctor`, `policy`, and `schema` behavior.

## Research And False-Positive Check

- [x] Read memory for Aegis phase discipline, Zig 0.15.2 workflow, and acceptance-smoke expectations.
- [x] Confirm the prompt-named governing docs are absent in this checkout and do not fabricate their contents.
- [x] Check MAVLink primary docs for packet formats, MAVLink2 signing flag, command protocol, mission protocol, and supported common-message constants.
- [x] Inspect Edge domain/policy APIs for exact `CommandRequest`, required parameters, state/provenance, and Core decision integration.
- [x] Inspect Core audit/redaction/event surfaces and `aegis-edge` CLI wiring before writing code.
- [x] Re-check docs/examples wording for no PX4/ArduPilot/SITL/real-flight/certification claims.

## TDD / Implementation Checklist

- [x] Add Phase 28 MAVLink tests first for framing/parser recovery, malformed input, bounded payloads, CRC, signing detection, classification, command mapping, endpoint policy, mission tracking, gateway decisions, fake transport, audit/redaction, and CLI behavior.
- [x] Implement `packages/edge/src/mavlink/` modules for framing, parser, CRC, dialect constants, typed supported messages, command mapping, classifier, mission state, signing detection, gateway, audit payloads, and fake transport.
- [x] Map supported MAVLink commands/messages into existing Edge `CommandRequest` actions and evaluate every mapped command through the Phase 27 Edge policy engine.
- [x] Implement gateway modes: observe, enforce, ci/redteam, simulation, bench-reserved, and disabled with safe default behavior for unknown commands/endpoints.
- [x] Track generic MAVLink mission uploads and deny/flag unsafe or incomplete mission items without autopilot-specific behavior.
- [x] Add deterministic fake MAVLink transport helpers for tests and examples with explicit fake/simulation provenance.
- [x] Wire `aegis-edge mavlink doctor`, `inspect-frame`, `classify`, `simulate`, and `gateway --fake` without opening real endpoints.
- [x] Add deterministic examples under `examples/edge/mavlink/`.
- [x] Update docs under `docs/edge/` and `packages/edge/README.md` with supported subset, limitations, fake transport, signing detection vs verification, mission limitations, endpoint policies, and no-real-flight boundaries.

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
- [x] `./zig-out/bin/aegis-edge mavlink doctor`
- [x] `./zig-out/bin/aegis-edge mavlink inspect-frame examples/edge/mavlink/frames/command-arm.hex`
- [x] `./zig-out/bin/aegis-edge mavlink classify examples/edge/mavlink/frames/command-takeoff.hex`
- [x] `./zig-out/bin/aegis-edge mavlink simulate --policy examples/edge/mavlink/policies/geofence-mavlink-basic.yaml --scenario examples/edge/mavlink/scenarios/geofence-deny.yaml`
- [x] `./zig-out/bin/aegis-edge mavlink simulate --policy examples/edge/mavlink/policies/geofence-mavlink-basic.yaml --scenario examples/edge/mavlink/scenarios/disable-failsafe-deny.yaml`
- [x] Manual: malformed frames fail safely.
- [x] Manual: waypoint outside geofence is denied.
- [x] Manual: disable_failsafe is denied.
- [x] Manual: land is allowed/logged according to policy.
- [x] Manual: unknown command is not treated as safe.
- [x] Manual: mission outside geofence is denied or flagged.
- [x] Manual: fake transport provenance is explicit.
- [x] Manual: fake secrets do not appear in persistent outputs.
- [x] Manual: docs do not claim PX4/ArduPilot integration, real-flight readiness, certification, detect-and-avoid, or autopilot replacement.
- [x] Manual: Aegis CLI behavior unchanged.
- [x] `git diff --check`
- [x] `git diff --name-only` and `git ls-files --others --exclude-standard` reviewed for clean-checkout completeness.

## Review

- Implemented Phase 28 MAVLink gateway foundation under `packages/edge/src/mavlink/`.
- Added safe MAVLink v1/v2 framing, parser recovery, known-message CRC validation, supported common-dialect decoding, command classification/mapping, endpoint checks, fake transport, gateway decisions, mission transaction tracking, signing presence detection, and bounded/redacted MAVLink audit records.
- Wired `aegis-edge mavlink doctor`, `inspect-frame`, `classify`, `simulate`, and `gateway --fake`.
- Added deterministic MAVLink policies, frames, and scenarios under `examples/edge/mavlink/`.
- Updated Edge docs and capability reporting while preserving no-real-flight, no-PX4/ArduPilot/SITL/ROS2, no-real-endpoint, no-certification, and no-telemetry boundaries.
- Verification passed: `zig build`, `zig build test --summary all`, Aegis CLI smoke checks, Aegis Edge MAVLink CLI checks, manual safety cases, docs claim scan, fake-secret persistence scan, and `git diff --check`.

# Phase 28 MAVLink Review Fixes - 2026-05-08

## Assumptions

- Treat the reviewer comments as correctness bugs in the current dirty Phase 28 patch.
- Keep the fix scoped to MAVLink decoder/mapping/parser/simulation behavior and focused regression tests.
- Preserve fake-transport-only boundaries; do not add real serial, UDP, SITL, ROS2, or hardware behavior.

## TDD / Implementation Checklist

- [x] Add regressions for `MISSION_ITEM` float latitude/longitude decoding versus `MISSION_ITEM_INT` scaled integers.
- [x] Add regressions that global-relative altitude frames map to the home-relative altitude datum.
- [x] Add a parser regression for a batch containing multiple individually valid frames whose combined bytes exceed one frame buffer.
- [x] Add a simulation regression proving `--scenario` reads the YAML `frame:` field instead of inferring behavior from the filename.
- [x] Patch message decoding, command mapping, parser buffering/draining, and scenario-file loading with minimal changes.

## Verification Checklist

- [x] `zig build`
- [x] `zig build test --summary all`
- [x] Focused `aegis-edge mavlink simulate` smoke with a renamed scenario file.
- [x] `git diff --check`

## Review

- Split `MISSION_ITEM` and `MISSION_ITEM_INT` decoding so float-degree mission waypoints no longer get interpreted as scaled integer bit patterns.
- Preserved MAVLink global-relative altitude frames as `home_relative` and fail closed on unknown altitude frames instead of silently treating them as AMSL.
- Reworked parser feed buffering to drain valid frame batches incrementally when a read contains more than one maximum frame of valid data.
- Replaced scenario filename matching with YAML `frame:`, `expected_decision`, and `expected_forwarded` loading, resolving frames relative to the scenario file.
- Verification passed: `zig build`, `zig build test --summary all`, renamed-scenario `aegis-edge mavlink simulate`, and `git diff --check`.
