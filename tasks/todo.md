# Phase 27 Edge Policy Engine Extensions

## Assumptions

- The prompt-named Edge governing documents (`README_START_HERE.md`, `CODEX_MASTER_PROMPT_EDGE.md`, `context/...`, and `phases/27_EDGE_POLICY_ENGINE_EXTENSIONS.md`) are not present in this checkout under those exact paths. The active contract for this phase is the user prompt, existing Phase 26 Edge domain/schema code, current Aegis architecture/security documents, and prior task lessons.
- Phase 27 must implement Edge policy loading, validation, policy decision APIs, CLI evaluation/explain/check commands, examples, docs, and tests. It must not send commands to MAVLink/PX4/ArduPilot/ROS2, real hardware, SITL, or any external service.
- Edge policy decisions must reuse the shared Aegis Core decision vocabulary and Core audit/redaction surfaces. Edge may have domain-specific evaluation structs, but not a disconnected decision model.
- Stale, expired, unknown, ambiguous, unitless, or frame-less state is unsafe unless a policy explicitly permits a narrow emergency-safe decision such as land-on-stale-state.
- Circular WGS84 geofence enforcement is in scope. Polygon geofences may remain schema-reserved/unsupported if validation and docs fail clearly.

## Research And False-Positive Check

- [x] Read memory for Aegis phase discipline, prior policy engine notes, and clean-checkout lessons.
- [x] Read current root execution/security/architecture documents that exist in this checkout.
- [x] Confirm prompt-named Edge governing files are absent and do not fabricate them.
- [x] Inspect Core policy, decision, audit, redaction APIs and decide the narrow integration point.
- [x] Inspect Phase 26 Edge domain/schema contracts and identify reusable validators.
- [x] Inspect `aegis-edge` CLI/build/test wiring and examples/docs conventions.
- [x] Re-check assumptions against explorer findings before implementation.

## TDD / Implementation Checklist

- [x] Add focused Phase 27 tests first for policy parsing/validation failures, command decisions, freshness, geofence, altitude, velocity, battery, mode/authority, audit/redaction, CLI behavior, and Core decision reuse.
- [x] Implement Edge policy load/parse/validate for versioned YAML and JSON-shaped inputs with strict unknown/invalid value behavior.
- [x] Implement Edge evaluation API returning Core decisions plus findings, violated constraints, matched rules, fallback recommendations, audit-safe context, and explanations.
- [x] Implement command policy semantics: deny priority, ask conversion in CI/non-interactive mode, critical default deny, emergency-safe land/RTH policy handling, and no command forwarding.
- [x] Implement state freshness, circular geofence, altitude, velocity, battery, mode, and control-authority evaluation.
- [x] Prepare Edge audit events through Core event/redaction APIs with bounded structured payloads and fake provenance labels.
- [x] Implement `aegis-edge policy check`, `policy explain`, `policy evaluate`, `schema list`, and `schema print edge-policy-v1` without implying live mediation.
- [x] Add deterministic fake/simulation examples under `examples/edge/`.
- [x] Update Edge package README and Edge policy docs, including limitations and no-flight/no-certification boundaries.
- [x] Run `git diff --name-only` and `git ls-files --others --exclude-standard` before final status so new modules/tests/examples are visible.

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
- [x] `./zig-out/bin/aegis-edge policy check examples/edge/policies/geofence-basic.yaml`
- [x] `./zig-out/bin/aegis-edge policy evaluate examples/edge/policies/geofence-basic.yaml --request examples/edge/requests/waypoint-outside-geofence.json --state examples/edge/states/fresh-state.json`
- [x] `./zig-out/bin/aegis-edge policy evaluate examples/edge/policies/geofence-basic.yaml --request examples/edge/requests/land.json --state examples/edge/states/stale-state.json`
- [x] Manual: waypoint outside geofence denied.
- [x] Manual: `disable_failsafe` denied.
- [x] Manual: land behavior follows emergency-safe policy.
- [x] Manual: stale state denies normal movement commands.
- [x] Manual: low battery behavior follows policy.
- [x] Manual: fake secrets absent from persistent outputs and replay output.
- [x] Manual: Edge docs do not claim MAVLink/PX4/ArduPilot support, real-flight readiness, or certification.
- [x] Manual: Aegis CLI behavior unchanged.
- [x] `git diff --check`

## Review

- Implemented Phase 27 Edge policy engine extensions under `packages/edge/src/policy/`.
- Added strict Edge policy YAML/JSON loading, validation, command request/state JSON parsing, Core decision reuse, local safety checks, and prepared Core audit events.
- Added `aegis-edge policy check`, `policy explain`, and `policy evaluate`; schema print now reads the checked-in schema.
- Added deterministic fake/simulation examples under `examples/edge/`.
- Updated Edge docs and schemas for policy-engine behavior while preserving no-command-mediation, no-real-flight, and no-certification boundaries.
- Verification passed, including `zig build`, `zig build test`, Aegis CLI regression smokes, Edge policy CLI smokes, manual decision checks, docs claim scan, fake-secret persistence scan, JSON schema/example parsing, and `git diff --check`.

## Review Fixes

- [x] Reject command request / vehicle state ID mismatches before safety evaluation.
- [x] Require matching parameters for `takeoff`, `set_waypoint`, `set_velocity`, `set_altitude`, `set_heading`, and `set_mode`.
- [x] Reject Edge policies missing schema-required top-level `safety` or `commands` sections.
- [x] Include `aegis-edge` in shell and PowerShell release artifacts.
- [x] Escape `policy check --json` path output.
- [x] Add regression tests for all review comments.
- [x] Rerun focused tests, `zig build test`, `zig build`, Edge CLI checks, and `git diff --check`.

## Review Fix Results

- Request/state vehicle ID mismatches now fail with `VehicleIdMismatch` before evaluation allocates or emits audit payloads.
- Parameterized movement/mode commands now fail closed when the required parameter payload is missing or the wrong parameter variant is provided.
- JSON command request parsing now supports `heading` payloads so `set_heading` can satisfy the required-parameter contract.
- Edge policy loading now enforces the published top-level schema contract for `safety` and `commands`.
- Release packaging now copies both `aegis` and `aegis-edge` on shell and PowerShell release paths.
- `aegis-edge policy check --json` now writes the policy path through Core JSON string escaping.
- Verification passed after these fixes: `git diff --check`, `zig build`, `zig build test --summary all`, Aegis CLI smoke checks, Edge CLI smoke checks, manual policy-decision probes, docs limitation scan, and persistent fake-secret scan.
