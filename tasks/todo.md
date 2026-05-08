# Phase 34 Edge Red-Team and Fault Injection

## Assumptions

- The prompt-named `README_START_HERE.md`, `CODEX_MASTER_PROMPT_EDGE.md`, `context/`, `checklists/`, and `phases/34_EDGE_REDTEAM_AND_FAULT_INJECTION.md` files are absent from this checkout. The active contract is the Phase 34 prompt, root Aegis contracts, current Edge docs/code, existing examples, and `tasks/lessons.md`.
- Phase 34 is limited to deterministic Edge red-team and simulation-only fault injection for fake adapter, fake PX4/ArduPilot adapters, and opt-in PX4/ArduPilot SITL contexts.
- Phase 34 must not add Phase 35 telemetry/data guard work, hardware bench deployment, real drone integration, real-flight procedures, SaaS, monetization, telemetry, detect-and-avoid, autopilot replacement behavior, or certification/regulatory claims.
- Edge red-team evidence must reuse existing Edge safety evaluation, MAVLink, PX4/ArduPilot scenario, Core-backed Edge audit/replay, redaction, and safety-case report paths. No duplicate policy/audit/report engines.
- Normal tests must remain deterministic, offline, bounded, and fake/SITL-aware. Missing PX4 or ArduPilot SITL must be skipped/unsupported, not passed.

## Research And False-Positive Check

- [x] Read Aegis memory and `tasks/lessons.md` for phase discipline, red-team redaction, Core audit reuse, fake-vs-SITL boundaries, tracked-file hygiene, and smoke-gate expectations.
- [x] Confirm absent prompt-named governing files instead of inventing their contents.
- [x] Inspect Edge safety, MAVLink, PX4, ArduPilot, approval, emergency, audit, replay, and safety-case APIs for direct reuse points.
- [x] Inspect existing Phase 13 root `aegis redteam` implementation to avoid regressing CLI v1.1 behavior.
- [x] Inspect docs/examples for no-real-flight claims, redaction language, and Phase 34 documentation gaps.
- [x] Re-check before handoff that docs and outputs do not imply real-flight readiness, certification, detect-and-avoid, autopilot replacement, telemetry, SaaS, or real hardware support.

## TDD / Implementation Checklist

- [x] Add Phase 34 fixture parser/validation tests for valid fixtures, invalid fixtures, required expected decision, invalid category, duplicate IDs, required capabilities, skip conditions, and unsupported limitations.
- [x] Add runner/classification tests for discovery, category/fixture/environment filters, passed/failed/skipped/unsupported/inconclusive, CI exit behavior, JSON output, score calculation, and skipped/unsupported not counted as pass.
- [x] Add fault injection tests for stale position, low/critical battery, invalid GPS, waypoint/geofence, malformed MAVLink, expired approval, approval bypass, and emergency bypass faults.
- [x] Add required-fixture tests proving at least 30 required fake/simulation fixtures exist, pass, produce audit/replay evidence, check forbidden fake secrets, and do not require hardware/network.
- [x] Add PX4/ArduPilot red-team tests proving SITL fixtures skip unless enabled, fake PX4/ArduPilot fixtures run normally, missing SITL is not a pass, and provenance remains correct.
- [x] Add safety-case/redaction tests proving red-team reports include fixture results, limitations, non-certification disclaimer, traceability, and no fake secrets.
- [x] Implement `packages/edge/src/redteam/` modules for fixture format, scenario execution, simulation-only fault injection, attack categories, scorecard, JSON/Markdown reports, and tests.
- [x] Create required deterministic fixture corpus under `examples/edge/redteam/` or equivalent, with at least 30 required fake/simulation fixtures plus opt-in PX4/ArduPilot SITL fixtures.
- [x] Wire `aegis-edge redteam`, `list`, `validate`, filtering, JSON, CI, output directory, and safety-case report mode.
- [x] Update Edge docs and package README for red-team fixtures, fault injection, scorecards, SITL red-team, safety-case integration, and simulation-vs-flight boundaries.

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
- [x] `./zig-out/bin/aegis-edge redteam list`
- [x] `./zig-out/bin/aegis-edge redteam validate`
- [x] `./zig-out/bin/aegis-edge redteam`
- [x] `./zig-out/bin/aegis-edge redteam --json`
- [x] `./zig-out/bin/aegis-edge redteam --ci`
- [x] `./zig-out/bin/aegis-edge redteam --category geofence`
- [x] `./zig-out/bin/aegis-edge redteam --category approval-bypass`
- [x] `./zig-out/bin/aegis-edge redteam --category emergency-bypass`
- [x] `./zig-out/bin/aegis-edge redteam --report safety-case`
- [x] Manual check: at least 30 required fake/simulation Edge fixtures exist.
- [x] Manual check: `redteam --ci` exits non-zero if a required fixture is intentionally broken.
- [x] Manual check: skipped PX4/ArduPilot SITL fixtures are not counted as pass.
- [x] Manual check: unsupported features are not counted as pass.
- [x] Manual check: safety-case report includes limitations and non-certification disclaimer.
- [x] Manual check: fake secrets do not appear in persistent outputs.
- [x] Manual check: docs do not include real-world attack instructions.
- [x] Manual check: docs do not claim real hardware or real-flight readiness.
- [x] Manual check: PX4, ArduPilot, safety enforcement, operator/emergency, safety-case, and CLI behavior unchanged.
- [x] `git diff --check`

## Review

- Implemented Phase 34 only. Required Edge red-team corpus is 44 fake/simulation fixtures out of 56 total fixtures; 11 PX4/ArduPilot SITL fixtures skip by default and 1 unsupported polygon-geofence fixture is unsupported, not passed.
- `aegis-edge redteam --ci` passes 44/44 required fixtures; an intentionally broken required fixture returns exit code 6 in CI mode.
- Red-team scorecards, JSON output, audit/replay artifacts, and optional safety-case reports are generated under `.aegis-edge/redteam/<run-id>/` with fake-secret checks and simulation/non-certification limitations.
- Existing Aegis CLI red-team, replay, PX4/ArduPilot skip semantics, safety enforcement, operator/emergency, and safety-case test suites pass under `zig build test`.

## Review Fix Plan

- [x] Add regressions for invalid approval event mapping through Edge audit/Core replay.
- [x] Add regressions proving one-time approvals are consumed before an allow result can be reused.
- [x] Add regressions proving `require_safety_constraints_hash: false` permits compatible approvals with mismatched constraints hash.
- [x] Patch Edge audit mapping for `operator.approval_invalid`.
- [x] Patch approval validation/consumption and all call sites.
- [x] Force Phase 34 source, fixture, doc, and test files into the review diff.
- [x] Re-run targeted and full verification.
