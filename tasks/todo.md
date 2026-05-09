# Phase 35 Edge Network, Telemetry, and Data Guard

## Assumptions

- The prompt-named `README_START_HERE.md`, `CODEX_MASTER_PROMPT_EDGE.md`, `context/`, `checklists/`, and `phases/35_EDGE_NETWORK_TELEMETRY_DATA_GUARD.md` files are absent from this checkout. The active contract is the Phase 35 prompt, root Aegis contracts, current Edge docs/code, existing examples, and `tasks/lessons.md`.
- Phase 35 is limited to deterministic Edge data classification, telemetry/network policy evaluation, redaction/minimization, offline exfiltration heuristics, audit/report integration, examples, CLI commands, and red-team fixtures for fake adapter plus PX4/ArduPilot fake/SITL contexts.
- Phase 35 must not add Phase 36 hardware bench deployment, Phase 37 watchdog/runtime health, Phase 38 customer demo/docs package, Phase 39 customer pilot package, real drone hardware integration, real-flight deployment, customer hardware procedures, SaaS, hosted telemetry, monetization, regulatory/certification claims, detect-and-avoid, or autopilot replacement behavior.
- Data/network guard must reuse existing Edge audit, safety-case, policy, MAVLink, PX4, ArduPilot, and red-team surfaces where practical. No duplicate audit engine, no external network calls in normal tests, and no raw secret persistence.
- Unknown data classes and unknown endpoints are not safe. Deny wins over allow. CI mode converts ask to deny. Observe mode logs findings without claiming blocking.
- Fake adapters, PX4 SITL, ArduPilot SITL, and customer-evaluation endpoints must preserve provenance and must not be mislabeled as real flight.

## Research And False-Positive Check

- [x] Read Aegis memory for phase discipline, offline red-team fixtures, existing network egress guard, redaction, smoke-gate expectations, and handoff format.
- [x] Confirm absent prompt-named governing files instead of inventing their contents.
- [ ] Read `tasks/lessons.md` for project-specific corrections before implementation.
- [ ] Inspect Edge policy, schema, MAVLink, PX4, ArduPilot, audit, safety-case, red-team, and CLI modules for extension points.
- [ ] Inspect existing root network guard/redaction behavior for reusable patterns without conflating agent-network guard with Edge telemetry/data guard.
- [ ] Inspect docs/examples for no-real-flight, no-certification, no-detect-and-avoid, no-autopilot-replacement language.
- [ ] Re-check docs, examples, tests, and persistent outputs for fake-secret leakage and forbidden real-flight/certification claims before handoff.

## TDD / Implementation Checklist

- [ ] Add failing tests for data classification: vehicle state, exact geolocation, mission plan, video/image, fake secret/credential, and unknown payloads.
- [ ] Add failing tests for endpoint classification: localhost, private network, fake/SITL, ground-control, customer, direct IP, webhook, tunnel, paste, and unknown endpoints.
- [ ] Add failing tests for policy evaluation: allow/ask/deny, deny beats allow, CI ask-to-deny, observe logging, sensitive data to unknown endpoint denied, and explicit safety-report/customer allow.
- [ ] Add failing tests for redaction/minimization: fake secrets, tokens, URL query secrets, geolocation coarsening, mission-plan minimization, and raw image/video exclusion.
- [ ] Add failing tests for exfiltration heuristics: long query, high-entropy labels/components, base64-like fragments, direct IP, webhook/paste/tunnel, repeated unknown endpoints, MAVLink-like external payloads, and secret-like payloads.
- [ ] Add integration tests proving MAVLink fake, PX4 fake/SITL, and ArduPilot fake/SITL telemetry calls data guard before simulated egress/logging.
- [ ] Add audit/replay and safety-case tests proving data/network decisions are audited, redacted before persistence, replay-safe, and included in reports.
- [ ] Add Edge CLI tests/smokes for `data doctor`, `data classify`, `data evaluate`, `data redact`, `data scenario run`, and `network explain`.
- [ ] Implement `packages/edge/src/data_guard/` modules for classification, endpoint policy, telemetry policy, egress evaluation, redaction, mission/sensor guards, link guard, findings, audit projection, scenarios, and tests.
- [ ] Extend Edge policy schema/loading to include `data_guard` rules without breaking existing safety-policy behavior.
- [ ] Create deterministic examples under `examples/edge/data-guard/` with fake payloads/endpoints/policies/scenarios only.
- [ ] Extend Edge red-team fixtures with data/network guard categories and prove skipped/unsupported fixtures do not count as pass.
- [ ] Wire safety-case report data/network summaries, limitations, endpoints observed, data classes, redactions, and evidence references without leaking sensitive payloads.
- [ ] Update Edge docs and package README for data classes, channels, endpoint classification, policies, redaction, exfiltration detection, safety-case integration, and simulation/SITL limitations.

## Verification Checklist

- [ ] `zig build`
- [ ] `zig build test`
- [ ] `./zig-out/bin/aegis --help`
- [ ] `./zig-out/bin/aegis version`
- [ ] `./zig-out/bin/aegis doctor`
- [ ] `./zig-out/bin/aegis run -- echo hello`
- [ ] `./zig-out/bin/aegis replay --session last --verify`
- [ ] `./zig-out/bin/aegis redteam --ci`
- [ ] `./zig-out/bin/aegis-edge --help`
- [ ] `./zig-out/bin/aegis-edge doctor`
- [ ] `./zig-out/bin/aegis-edge data doctor`
- [ ] `./zig-out/bin/aegis-edge data classify --payload examples/edge/data-guard/payloads/mission-plan.json`
- [ ] `./zig-out/bin/aegis-edge data evaluate --policy examples/edge/data-guard/policies/data-guard-strict.yaml --payload examples/edge/data-guard/payloads/mission-plan.json --endpoint examples/edge/data-guard/endpoints/webhook-site.json`
- [ ] `./zig-out/bin/aegis-edge data redact --payload examples/edge/data-guard/payloads/fake-secret-payload.json`
- [ ] `./zig-out/bin/aegis-edge data scenario run --policy examples/edge/data-guard/policies/data-guard-strict.yaml --scenario examples/edge/data-guard/scenarios/mission-plan-to-webhook-deny.yaml`
- [ ] `./zig-out/bin/aegis-edge network explain --policy examples/edge/data-guard/policies/data-guard-strict.yaml --endpoint examples/edge/data-guard/endpoints/unknown-direct-ip.json`
- [ ] `./zig-out/bin/aegis-edge redteam --category data-guard`
- [ ] `./zig-out/bin/aegis-edge redteam --category audit-redaction`
- [ ] `./zig-out/bin/aegis-edge redteam --ci`
- [ ] Manual check: mission plan to webhook is denied.
- [ ] Manual check: exact geolocation to unknown endpoint is denied or redacted according to policy.
- [ ] Manual check: fake secret payload is redacted/denied and absent from persistent outputs.
- [ ] Manual check: video stream to unknown endpoint is denied.
- [ ] Manual check: safety report to allowed customer endpoint is allowed.
- [ ] Manual check: no external network calls are made in tests.
- [ ] Manual check: safety-case report includes data guard findings.
- [ ] Manual check: docs do not include real-world exfiltration instructions or real-flight/certification claims.
- [ ] Manual check: PX4, ArduPilot, safety enforcement, operator/emergency, Edge redteam, and CLI behavior unchanged.
- [ ] `git diff --check`

## Review

- Pending.

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
