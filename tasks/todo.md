# Phase 39 Customer Pilot Package and Safety Report

## Assumptions

- The prompt-named `README_START_HERE.md`, `CODEX_MASTER_PROMPT_EDGE.md`, `context/`, `sales_customer/`, `checklists/`, and `phases/39_CUSTOMER_PILOT_PACKAGE_AND_SAFETY_REPORT.md` files are absent from this checkout by exact path. The active contract is the Phase 39 prompt, existing Edge docs/examples/tests, Aegis memory, and `tasks/lessons.md`.
- Phase 39 is limited to a local customer pilot package, pilot templates, deterministic sample reports, customer-facing safety boundaries, optional local pilot CLI helpers, docs integration, and validation checks.
- Phase 39 must not add Phase 40 hardening review, Phase 41 production release, Phase 42 customer acquisition execution, SaaS, hosted dashboard, enterprise control plane, billing, license enforcement, hosted telemetry, real hardware operation, real-flight deployment, certification workflows, regulatory approval workflows, detect-and-avoid, autopilot replacement behavior, or live aircraft control.
- All pilot materials must remain fake/example data only, offline by default, no real secrets, no real customer names, no real-flight procedures, and no unsupported legal claims. SOW/MSA/security-style templates must be marked as draft templates requiring legal review.

## Research And False-Positive Check

- [x] Read Aegis memory for Edge phase boundaries, no-real-flight language, offline fixture expectations, and required root/Edge regression lanes.
- [x] Load TDD, writing-plans, and verification-before-completion skills.
- [x] Confirm absent prompt-named governing files instead of inventing their contents.
- [x] Read `tasks/lessons.md` for tracked-file hygiene, fake/SITL provenance, docs overclaiming, and CLI proof/demo pitfalls.
- [x] Inspect Edge CLI docs/demo/proof command patterns and docs-check implementation.
- [x] Inspect Phase 38 customer-proof docs/examples for links and boundary wording to reuse without duplicating unsupported claims.
- [x] Re-check all customer pilot docs/templates/examples for banned phrases, real-secret patterns, fake-vs-SITL-vs-bench provenance, legal-template disclaimers, and no pricing unless explicitly placeholder/internal.

## TDD / Implementation Checklist

- [x] Add failing Phase 39 tests for required `customer_pilot/` docs, templates, examples, safety/legal disclaimers, banned overclaim scans, sample-report limitations, docs links, and optional pilot CLI behavior.
- [x] Run the focused Phase 39 test and verify it fails for missing pilot files/commands.
- [x] Create `customer_pilot/` package docs: README, overview, boundaries, success criteria, timeline, deliverables, intake/discovery/safety questionnaires, readiness checklist, simulation/SITL plan, demo script, report/evidence/red-team/final templates, limitations, and FAQ.
- [x] Create `customer_pilot/templates/` draft templates for SOW, mutual NDA notes, security review responses, customer follow-up email, and design partner proposal with legal-review markings where needed.
- [x] Create deterministic fake/example outputs under `customer_pilot/examples/` for pilot, safety, red-team, and evidence-bundle reports.
- [x] Add local-only `aegis-edge pilot checklist`, `pilot package`, and `pilot demo` helpers if the CLI extension stays small and consistent with existing architecture; otherwise document script/template-only support.
- [x] Update `docs/edge/README.md` and `packages/edge/README.md` with customer pilot links and no-real-flight safety boundary reminders.
- [x] Run the focused Phase 39 test and verify it passes.
- [x] Run full required regression commands: `zig build`, `zig build test`, root CLI smokes, Edge CLI smokes, docs check, demo/proof, red-team, and pilot commands if implemented.
- [x] Manually review customer pilot readability, boundaries, report templates, samples, legal-template markings, no hardcoded pricing, no real-flight/certification/autopilot/detect-and-avoid claims, no fake secrets in persistent outputs, and Phase 38 demo regression.

## Review

- Implemented Phase 39 only: added `customer_pilot/` package docs, questionnaires, readiness checklist, simulation/SITL plan, customer demo script, safety/evidence/red-team/final report templates, FAQ, limitations, legal-marked templates, deterministic sample reports, docs links, validation tests, and local-only pilot CLI helpers.
- Pilot CLI status: `aegis-edge pilot checklist`, `aegis-edge pilot package`, `aegis-edge pilot demo`, `pilot init --customer <placeholder>`, and `pilot report --session last` are local helpers only. `pilot package` writes a local `.aegis-edge/pilot-package/index.md` index and does not require network, hardware, real secrets, or real customer names.
- Docs validation status: `aegis-edge docs check` now includes customer pilot files, scans secret-like markers, scans banned overclaim phrases across all occurrences, and preserves the Phase 38 success banner for compatibility.
- Verification complete: `zig build`, `zig build test --summary all`, root CLI smokes, Edge CLI smokes, Edge red-team, docs check, geofence demo/proof, pilot commands, Phase 38 `demo run all`, fake-secret persistent-output scan, pricing placeholder scan, and `git diff --check` passed.
- Known limitations: customer pilot materials are simulation/SITL/bench-preparation/customer-evaluation only; no real flight, live aircraft control, certification, regulatory approval, detect-and-avoid, autopilot replacement, hosted telemetry, SaaS, billing, or license enforcement was added.
- Phase 40 readiness: the repo is ready to start Phase 40 from the Phase 39 acceptance perspective, but this is not production release or real-flight readiness.

# Phase 38 Edge Docs, Demos, and Customer Proof

## Assumptions

- The prompt-named `README_START_HERE.md`, `CODEX_MASTER_PROMPT_EDGE.md`, `context/`, `checklists/`, and `phases/38_EDGE_DOCS_DEMOS_AND_CUSTOMER_PROOF.md` files are absent from this checkout by exact path. The active contract is the Phase 38 prompt, current Edge code/docs/examples, Aegis memory, and `tasks/lessons.md`.
- Phase 38 is customer-facing documentation, deterministic fake/SITL demos, proof artifacts, docs validation, and CLI wrappers around existing Edge capabilities.
- Phase 38 must not add Phase 39 pilot-package execution, Phase 40 final hardening, Phase 41 production release, Phase 42 acquisition, paid SaaS, hosted telemetry, real hardware operation, real-flight deployment, detect-and-avoid, autopilot replacement, or certification claims.
- Demo and proof commands must remain offline by default, fake/SITL/bench-preparation only, non-interactive in CI, and must not persist raw fake secrets.

## Research And False-Positive Check

- [x] Read Aegis memory for Edge phase boundaries, audit/replay/safety-case output paths, red-team fixture locations, smoke gates, and handoff expectations.
- [x] Load TDD and verification-before-completion skills for test-first implementation and evidence-backed handoff.
- [x] Confirm absent prompt-named governing files instead of inventing their contents.
- [x] Read `tasks/lessons.md` for tracked-file hygiene, fake/SITL provenance, redaction, no-overclaiming, and smoke-gate lessons.
- [x] Inspect current Edge CLI, safety-case, red-team, data guard, health/watchdog, deployment assets, docs, and examples.
- [x] Re-check docs/proof artifacts for banned overclaim phrases, secret leakage, fake/SITL/bench/real-flight boundary clarity, and pricing/monetization absence.

## TDD / Implementation Checklist

- [x] Add failing Phase 38 tests for required docs, customer-proof docs, capability matrix, FAQs, demo recording script, demo asset directories, scripts, proof artifacts, and claim validation.
- [x] Add failing CLI tests for `aegis-edge demo list`, `demo run geofence-deny`, `demo run all`, `proof generate --demo geofence-deny`, and `docs check`.
- [x] Create/update `packages/edge/README.md`, `docs/edge/README.md`, `docs/edge/quickstart.md`, `docs/edge/troubleshooting.md`, `docs/edge/architecture.md`, and `docs/edge/capability-matrix.md`.
- [x] Create `docs/edge/customer-proof/` docs for proof boundaries, demo script, evidence package, safety-case/red-team examples, SITL-vs-flight, buyer/technical FAQs, technical brief, recording script, and red-team summary.
- [x] Create deterministic demo suite under `examples/edge/demos/` with ten demo folders, policies, scenarios, expected output, scripts, sample reports/replay, and limitations.
- [x] Add top-level demo runners `examples/edge/demos/run-all.sh` and `scripts/edge-demo.sh` with offline fake/SITL behavior and clear output paths.
- [x] Add customer proof artifacts under `examples/edge/customer-proof/` with limitations, provenance, non-certification disclaimers, hashes/references, and no secrets.
- [x] Add lightweight docs/demo validation implementation and CLI surface.
- [x] Wire `aegis-edge demo`, `aegis-edge proof`, and `aegis-edge docs check` without changing real-control behavior.

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
- [x] `./zig-out/bin/aegis-edge redteam --ci`
- [x] `./zig-out/bin/aegis-edge demo list`
- [x] `./zig-out/bin/aegis-edge demo run geofence-deny`
- [x] `./zig-out/bin/aegis-edge demo run all`
- [x] `./zig-out/bin/aegis-edge proof generate --demo geofence-deny`
- [x] `./zig-out/bin/aegis-edge docs check`
- [x] `examples/edge/demos/run-all.sh`
- [x] `scripts/edge-demo.sh`
- [x] Manual check: customer proof docs are readable and contain no pricing.
- [x] Manual check: demos distinguish fake adapter, PX4 SITL, ArduPilot SITL, bench, and real flight.
- [x] Manual check: docs/proof artifacts do not claim real-flight readiness, certification, autopilot replacement, or detect-and-avoid.
- [x] Manual check: fake secrets do not appear in persistent outputs.
- [x] Manual check: PX4, ArduPilot, safety enforcement, operator/emergency, data guard, health/watchdog, deployment/bench, Edge red-team, and CLI behavior unchanged.
- [x] `git diff --check`

## Review

- Implemented Phase 38 only: customer-facing Edge README, docs hub, quickstart, troubleshooting, architecture diagrams, capability matrix, customer-proof docs, demo recording script, red-team summary, demo suite, proof artifacts, top-level demo scripts, CLI demo/proof/docs wrappers, and regression tests.
- Demo suite status: `aegis-edge demo run geofence-deny`, `aegis-edge demo run all`, `examples/edge/demos/run-all.sh`, and `scripts/edge-demo.sh` pass locally with fake/SITL/bench-preparation boundaries and no external network calls.
- Customer proof artifact status: checked-in examples include provenance, limitations, non-certification disclaimers, policy hashes, and audit references where applicable.
- Safety-case example status: `aegis-edge proof generate --demo geofence-deny` generates a hash-chained local safety-case session and points to checked-in customer proof artifacts.
- Docs validation status: `aegis-edge docs check` passes and scanned required docs/proof files for missing assets, raw fake-secret markers, and overclaim phrases with manual-review context for negative limitation text.
- Regression status: `zig build`, `zig build test`, root CLI smokes, Edge red-team, demo/proof/docs commands, and demo scripts passed. PX4 and ArduPilot SITL remain opt-in/skipped when not configured; fake adapter, safety enforcement, operator/emergency, data guard, health/watchdog, deployment/bench, Edge red-team, and root CLI behavior are unchanged.
- Known limitations: Phase 38 is still simulation/SITL/bench-preparation/customer-evaluation only; real flight, real aircraft control, certification, detect-and-avoid, autopilot replacement, hosted telemetry, and future customer pilot package work remain unsupported.
- Phase 39 readiness: ready to begin Phase 39 from a customer-proof/docs/demo standpoint, but not as real-flight or production-release readiness.

## Review Fix Checklist

- [x] Add regression coverage that unsupported Phase 38 proof demo IDs reject before printing success.
- [x] Patch `aegis-edge proof generate` so non-safety demos with checked-in artifacts do not route through safety-case generation.
- [x] Make Edge smoke/demo scripts resolve repo-relative inputs from the computed repo root when invoked from another cwd.
- [x] Remove local Playwright capture/screenshot artifacts that are not referenced by docs, build, or tests.
- [x] Re-run focused proof/script checks plus full build/test regression.

## Review Fix Results

- `aegis-edge proof generate --demo data-exfil-deny` now exits 64 before printing success and directs users to the checked-in data-exfil proof artifact/demo path.
- `scripts/edge-package-smoke-test.sh`, `scripts/edge-smoke-test.sh`, `scripts/edge-arm64-smoke-test.sh`, `scripts/edge-demo.sh`, `examples/edge/demos/run-all.sh`, and the PX4/ArduPilot fake demo wrappers were verified from `/tmp`.
- Removed tracked local Playwright MCP captures and root screenshot PNGs that were not referenced by docs, build, or tests.
- Verification after the review fix: `zig build`, `zig build test --summary all`, root CLI smokes, Edge CLI smokes, docs check, proof rejection, outside-cwd demo/smoke scripts, PX4/ArduPilot fake demo scripts, and `git diff --check` passed.

# Phase 37 Reliability Watchdog and Runtime Health

## Completion Pass Checklist

- [x] Reconcile the existing Phase 37 implementation against the current prompt without implementing future phases.
- [x] Add prompt-compatible health states, runtime modes, health domains, watchdog config aliases, command queue health, and command timeout support.
- [x] Add prompt-named deterministic health scenarios and CLI aliases for health watch/report/profile checks and watchdog simulate default policy behavior.
- [x] Run focused and full verification, including Aegis CLI and Aegis Edge health/watchdog/red-team smokes.
- [x] Update this review section with final evidence and limitations.

## Review Fix Checklist

- [x] Add regression coverage for Aegis Edge package Docker/install layout.
- [x] Copy the Docker image binary from the release archive `bin/aegis-edge` path.
- [x] Install the extracted release binary into `${PREFIX}/bin/aegis-edge`.
- [x] Force new Phase 37 source, tests, docs, and examples into `git diff` with intent-to-add.
- [x] Run focused and full verification after review fixes.
- [x] Document review-fix results.

## Assumptions

- The prompt-named `README_START_HERE.md`, `CODEX_MASTER_PROMPT_EDGE.md`, `context/`, `checklists/`, and `phases/37_RELIABILITY_WATCHDOG_AND_RUNTIME_HEALTH.md` files are absent from this checkout. The active contract is the Phase 37 prompt, existing Edge code/docs/examples, Aegis memory, and `tasks/lessons.md`.
- Phase 37 is limited to deterministic runtime health, heartbeat/freshness monitoring, watchdog policy, degraded-mode decisions, audit-health/resource-health checks, safety integration, red-team fixtures, safety-case evidence, CLI commands, examples, and docs for fake-adapter, PX4 SITL, ArduPilot SITL, and bench-preparation contexts.
- Phase 37 must not add Phase 38 customer demo/docs package, Phase 39 customer pilot package, Phase 40 final safety hardening, Phase 41 release, Phase 42 acquisition, SaaS, monetization, hosted telemetry, real-flight deployment, real hardware operation, detect-and-avoid, autopilot replacement behavior, or certification claims.
- Unknown, stale, unavailable, or missing health state is never safe. Deny beats allow. Emergency behavior still goes through policy and the safety envelope. CI/non-interactive mode never prompts.
- Health evidence must reuse existing Edge audit/replay, safety evaluator, MAVLink/PX4/ArduPilot fake/SITL boundaries, red-team runner, data guard, and safety-case report paths where practical.

## Research And False-Positive Check

- [x] Read Aegis memory for phase discipline, TDD, offline fixtures, redaction, smoke-gate expectations, and handoff format.
- [x] Load the TDD workflow skill and translate Phase 37 into test-first checkpoints.
- [x] Confirm absent prompt-named governing files instead of inventing their contents.
- [x] Read `tasks/lessons.md` for tracked-file hygiene, safety fail-closed patterns, fake/SITL provenance, redaction, and smoke-gate lessons.
- [x] Inspect Edge policy/schema loading and identify the narrow watchdog-policy extension point.
- [x] Inspect safety evaluator paths and identify where health findings can fail closed without bypassing existing policy/safety checks.
- [x] Inspect MAVLink, PX4, and ArduPilot fake/SITL health/heartbeat surfaces.
- [x] Inspect Edge audit/replay and safety-case report writers for health evidence insertion.
- [x] Inspect red-team fixture parser/runner for health/watchdog categories and faults.
- [x] Inspect CLI command routing for `health` and `watchdog` commands.
- [x] Re-check docs/examples/tests/persistent outputs for fake-secret leakage and forbidden real-flight/certification/autopilot-replacement claims.

## TDD / Implementation Checklist

- [x] Add failing tests for `HealthStatus`, `HealthDomain`, `HealthFinding`, severity, provenance, and report aggregation.
- [x] Add failing tests for watchdog policy validation, strict/CI audit defaults, invalid thresholds, and invalid degraded behavior.
- [x] Add failing tests for heartbeat freshness: fresh, stale, expired, missing, fake, PX4 SITL, and ArduPilot SITL provenance.
- [x] Add failing tests for telemetry freshness: stale position, stale battery, missing GPS, missing home position, and unknown telemetry not safe.
- [x] Add failing tests for audit-health/resource-health: unavailable writer, append failure, latency, hash verification failure, queue depth, and redaction.
- [x] Add failing tests for degraded modes: deny high risk, deny movement, deny external egress, fail closed, emergency LAND policy, RTH home-position gate, HOLD context gate, and non-overridable critical commands.
- [x] Add integration tests proving safety evaluation consumes health reports and emits health findings/audit events.
- [x] Add integration tests proving MAVLink/PX4/ArduPilot fake/SITL heartbeats update health without real hardware or network dependencies.
- [x] Add CLI tests/smokes for `health`, `health --json`, `health doctor`, `health scenario run`, `watchdog doctor`, `watchdog simulate`, `watchdog status`, and `watchdog explain`.
- [x] Implement `packages/edge/src/health/` modules for status, findings, watchdog config, heartbeat, freshness, adapter/audit/policy/resource health, degraded modes, reports, audit projections, and scenarios.
- [x] Extend Edge policy schema/loading with `watchdog` support while preserving existing policy behavior.
- [x] Create deterministic examples under `examples/edge/health/` with fake/SITL/bench provenance only.
- [x] Extend Edge red-team fixtures with health/watchdog cases and ensure skipped/unsupported never count as pass.
- [x] Update safety-case/replay outputs to include runtime health policy/status/findings, heartbeat/freshness, degraded-mode decisions, fail-closed events, and limitations.
- [x] Update Edge docs and package README for runtime health/watchdog/degraded modes/heartbeat/audit-health/red-team/safety-case/simulation-vs-flight boundaries.

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
- [x] `./zig-out/bin/aegis-edge health`
- [x] `./zig-out/bin/aegis-edge health --json`
- [x] `./zig-out/bin/aegis-edge health doctor`
- [x] `./zig-out/bin/aegis-edge health scenario run --policy examples/edge/health/policies/watchdog-strict.yaml --scenario examples/edge/health/scenarios/stale-agent-deny-high-risk.yaml`
- [x] `./zig-out/bin/aegis-edge watchdog doctor`
- [x] `./zig-out/bin/aegis-edge watchdog simulate --policy examples/edge/health/policies/watchdog-strict.yaml --scenario examples/edge/health/scenarios/audit-failure-fail-closed.yaml`
- [x] `./zig-out/bin/aegis-edge redteam --category health`
- [x] `./zig-out/bin/aegis-edge redteam --category stale-state`
- [x] `./zig-out/bin/aegis-edge redteam --ci`
- [x] Manual check: stale agent heartbeat denies high-risk command.
- [x] Manual check: stale telemetry denies movement command.
- [x] Manual check: audit failure fails closed in strict/ci.
- [x] Manual check: critical battery emergency behavior follows policy.
- [x] Manual check: RTH without home position denies/flags.
- [x] Manual check: health findings appear in replay and safety-case report.
- [x] Manual check: fake secrets do not appear in persistent outputs.
- [x] Manual check: docs do not claim watchdog replaces autopilot failsafes or real-flight readiness.
- [x] Manual check: deployment/bench, data guard, PX4, ArduPilot, safety enforcement, operator/emergency, Edge red-team, and CLI behavior unchanged.
- [x] `git diff --check`

## Review

- Implemented Phase 37 runtime health/watchdog support only. No Phase 38+ customer package, pilot package, release, monetization, hosted telemetry, real hardware operation, real-flight deployment, detect-and-avoid, autopilot replacement, or certification claim was added.
- Added health/watchdog policy parsing, health domains/findings/reports, heartbeat/freshness/audit/resource checks, degraded-mode decisions, safety evaluator integration, health audit events, CLI health/watchdog commands, deterministic health examples, health red-team fixtures, safety-case health evidence, replay-visible findings, docs, and tests.
- Addressed initial review findings: fail-closed health now wins before emergency allowances; audit-health findings preserve `health.audit.failure`; health CLI validates `expected_decision` and command-specific `expected_behavior`; health CLI parses `health_fault` explicitly.
- Addressed follow-up review findings: new Phase 37 files are visible in `git diff` with intent-to-add; Edge Docker package copies `bin/aegis-edge`; `install-aegis-edge.sh` extracts the package and installs the binary to `${PREFIX}/bin/aegis-edge`.
- Addressed completion-pass review findings: prompt-shaped watchdog fields now parse and validate; `health watch`, `health report --session last`, `health check --profile`, and default-policy `watchdog simulate` are wired; `health report` reads runtime-health evidence or reports unknown/unavailable instead of a healthy placeholder; `health check` rejects ambiguous policy/profile input; runtime asset faults use `health.runtime_asset_missing`; queue overflow, command timeout, audit queue depth, state expiry, fallback order, and prompt-named health events are covered.
- Verification complete: `zig build`, `zig build test`, `zig build test --summary all`, required Aegis/Aegis Edge smoke commands, package smoke, installer smoke, health/red-team/safety-case/replay manual checks, schema JSON validation, fake-secret persistent-output scan, and docs claim scan passed.

# Phase 36 Review Fixes

## Checklist

- [x] Make all new Phase 36 source, tests, docs, examples, scripts, and packaging templates visible in `git diff` with intent-to-add.
- [x] Add standalone Edge package support distinction so macOS package-info returns unsupported while Linux amd64/arm64 remains supported.
- [x] Add regression coverage for Linux-only standalone Edge package targets.
- [x] Update lessons for the clean-checkout and release-artifact support mismatch.
- [x] Run `zig build test --summary all`.
- [x] Run package-info checks for default macOS failure, explicit macOS failure, and explicit Linux success.
- [x] Run `scripts/edge-package-smoke-test.sh`.
- [x] Run `git diff --check`.

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
