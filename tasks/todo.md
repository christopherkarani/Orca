# Phase 26 Edge Domain Model and Safety Schema

## Assumptions

- The Edge governing documents named in the task prompt are not present in this checkout. The task prompt, current package contracts, Phase 23-25 docs/tests, security invariants, architecture contracts, and memory notes are the active contract.
- Phase 26 is a foundational Edge domain/schema phase only. It may define types, units, coordinate frames, schemas, documentation, and validation helpers, but must not implement command mediation, MAVLink/PX4/ArduPilot/ROS2 integration, real-flight behavior, operator approval runtime flows, telemetry, SaaS, monetization, or regulatory/certification claims.
- Aegis Edge is a future policy and audit runtime between autonomous agents and control bridges. It is not a flight controller, autopilot replacement, detect-and-avoid system, or certification product.
- Edge must continue importing Aegis Core successfully and CLI v1.1 behavior must not regress.
- Unknown, stale, expired, fake, or ambiguous state must fail validation where fresh/known state is required.
- Units, coordinate frames, altitude references, timestamp sources, and provenance must be explicit and preserved for later audit/reporting phases.

## Research And False-Positive Check

- [x] Reviewed memory for Aegis phase discipline, verification gates, and prior Edge scaffold boundaries.
- [x] Confirmed the prompt-named Phase 26/context files are absent from this checkout and should not be fabricated.
- [x] Review current Edge package, build targets, schema placeholders, docs, and tests.
- [x] Compare requested Phase 26 scope against existing Phase 23-25 scaffold to avoid deleting useful honesty boundaries.
- [x] Confirm whether `aegis-edge` already exists and whether schema commands fit without implying active mediation.

## TDD / Implementation Checklist

- [x] Add failing/targeted tests for coordinate validation, altitude references, frame mismatch behavior, battery/altitude/speed/geofence limits, command policy conflicts, vehicle state freshness/provenance, command requests, risk classification, schemas, and Core import.
- [x] Implement/harden Edge domain module structure under `packages/edge/src/domain/`.
- [x] Implement/harden Edge schema module structure under `packages/edge/src/schema/`.
- [x] Add versioned Edge policy, event, and safety-report schema surfaces with Zig validation structs and JSON schema files.
- [x] Update `aegis-edge` only with honest `doctor`/`schema` commands if it fits the current architecture.
- [x] Update Edge docs: package README plus domain model, safety policy, coordinate frames, and safety schemas.
- [x] Add documentation regressions for no real-flight, no active MAVLink/PX4/ArduPilot, and no certification claims.

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
- [x] `./zig-out/bin/aegis-edge schema list`
- [x] `./zig-out/bin/aegis-edge schema print edge-policy-v1`
- [x] Manual docs/schema safety review.
- [x] Fake secret persistence check.
- [x] `git diff --check`

## Review

- Added Phase 26 Edge domain modules for vehicle/platform, coordinates/units/frames, state, commands, mission, geofence, battery, link, sensors, risk, safety envelope, and validation.
- Added versioned Edge policy, Edge event, and safety-report schema descriptors plus JSON schema files.
- Added `aegis-edge schema list` and `aegis-edge schema print edge-policy-v1` as honest schema discovery commands; command mediation remains not implemented.
- Added Phase 26 contract tests covering coordinate bounds, altitude reference requirements, NED/ENU mismatch behavior, safety envelope validation, geofence validation, vehicle state freshness/provenance, command request construction, risk classification, schema discoverability, Core import, and docs safety claims.
- Updated Edge docs and schema docs to document Phase 26 while preserving no-real-flight/no-certification/no-active-integration boundaries.
- Verification passed. `zig build test --summary all` reports 28/28 steps succeeded, 283/289 tests passed, 6 skipped.
