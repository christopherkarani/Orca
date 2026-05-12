# Phase 42 30-Day Drone Customer Acquisition

## Assumptions

- The prompt-named `README_START_HERE.md`, `CODEX_MASTER_PROMPT_EDGE.md`, `context/`, `sales_customer/`, and `phases/42_30_DAY_DRONE_CUSTOMER_ACQUISITION.md` files are absent from this checkout by exact path. The active contract is the Phase 42 prompt, existing `customer_pilot/` and Edge customer-proof docs, Aegis memory, and `tasks/lessons.md`.
- Phase 42 is customer acquisition enablement only: go-to-market docs, outreach/call/pilot templates, CRM/metrics templates, safety-claim guidance, targeting guidance, founder execution calendar, validation checks, and output summary.
- Phase 42 must not add SaaS, hosted dashboard, billing, license enforcement, automated outreach sending, scraping, telemetry by default, real drone hardware operation, real-flight deployment, live aircraft control, certification workflows, regulatory approval workflows, detect-and-avoid, autopilot replacement behavior, or weapons/kinetic initial targeting.
- Positioning remains simulation/SITL/bench-preparation customer evaluation: safety-policy runtime, bounded MAVLink mediation, safety-envelope evaluator, audit/replay, red-team/fault-injection harness, safety-case evidence generator, and paid-pilot evaluation package.

## Research And False-Positive Check

- [x] Read Aegis memory for phase discipline, required regression lanes, and Edge no-real-flight/no-certification/no-autopilot-replacement boundaries.
- [x] Load the TDD workflow skill and use a failing Phase 42 validation test before creating the go-to-market package.
- [x] Confirm absent prompt-named governing files instead of inventing their contents.
- [x] Read `tasks/lessons.md` for tracked-file hygiene, fake/SITL provenance, overclaim control, and clean-checkout review requirements.
- [x] Inspect current `customer_pilot/` package for demo commands, pilot boundaries, legal-template markings, and customer-facing safety language to reuse.
- [x] Inspect existing Edge demo/proof/red-team command surfaces and customer-proof artifacts for exact commands and artifact paths.
- [x] Re-check Phase 42 materials for banned claims, private contact data, fake secrets, spam automation, legal-template markings, and internal/editable pricing language.

## TDD / Implementation Checklist

- [x] Add failing Phase 42 tests for required `go_to_market/` docs, outreach templates, call scripts, pilot materials, launch drafts, CRM/metrics files, safety claims guide, targeting filters, output summary, and validation script.
- [x] Run the focused Phase 42 test and verify it fails before implementation.
- [x] Create `go_to_market/` package with 30-day plan, ICP, target-account templates, qualification framework, checklist, optional landing-page copy, targeting guidance, and README.
- [x] Create founder-led outreach templates that are concise, technical, manually sent, and explicitly safety-bounded.
- [x] Create discovery/demo/technical/safety-review call scripts and objections/answers grounded in existing Edge demos and proof artifacts.
- [x] Create paid-pilot offer, pricing guidance, close plan, mutual action plan, and success scorecard with editable/internal pricing and legal-review template markings where relevant.
- [x] Create launch drafts, CRM templates, acquisition metrics dashboards, and strict safety-claims guidance.
- [x] Add lightweight local validation checks for required files, banned overclaims, secrets/private contact data, legal-template labels, internal pricing labels, and absence of spam automation.
- [x] Create `go_to_market/PHASE_42_OUTPUT_SUMMARY.md`.

## Verification Checklist

- [x] Focused Phase 42 test fails before implementation.
- [x] Focused Phase 42 test passes after implementation.
- [x] `scripts/validate-go-to-market.sh`
- [x] `zig build`
- [x] `zig build test`
- [x] `./zig-out/bin/aegis --help`
- [x] `./zig-out/bin/aegis version`
- [x] `./zig-out/bin/aegis redteam --ci`
- [x] `./zig-out/bin/aegis-edge --help`
- [x] `./zig-out/bin/aegis-edge doctor`
- [x] `./zig-out/bin/aegis-edge redteam --ci`
- [x] `./zig-out/bin/aegis-edge docs check`
- [x] `./zig-out/bin/aegis-edge demo run geofence-deny`
- [x] `./zig-out/bin/aegis-edge proof generate --demo geofence-deny`
- [x] Manual review: `go_to_market/README.md` readable, 30-day plan actionable, outreach concise, call scripts useful, pilot offer clear, safety claims strict, no real-flight/certification/autopilot/detect-and-avoid claims, no real customer data, no fake secrets, no spam automation, product behavior unchanged.

## Review

- Implemented Phase 42 only: created `go_to_market/` with 30-day acquisition plan, ICP, account templates, qualification framework, outreach templates, call scripts, pilot offer/pricing/close/MAP/scorecard docs, launch drafts, CRM/metrics templates, safety claims guidance, targeting guidance, customer safety filter, optional landing-page copy, checklist, and output summary.
- Added `tests/phase42_drone_customer_acquisition.zig` and wired it into `zig build test`; the focused test failed before docs existed and passes after implementation.
- Added `scripts/validate-go-to-market.sh` to verify required GTM docs, secret-like markers, private contact data, banned overclaims outside negative safety context, legal-review marking, editable/internal pricing guidance, and absence of sender/scraping automation.
- Safety boundary preserved: materials consistently scope Aegis Edge to simulation/SITL/bench-preparation customer evaluation and avoid aircraft operation, certification, regulatory approval, detect-and-avoid, replacement of customer safety systems, universal MAVLink coverage, weapons/kinetic initial targeting, private-data scraping, and bulk outreach tooling.
- Verification complete: Phase 42 focused test, GTM validator, `zig build`, `zig build test`, required Aegis CLI commands, required Edge commands, `git diff --check`, and manual content review passed.

# Phase 41 Edge + CLI Production Release

## Assumptions

- The prompt-named `README_START_HERE.md`, `CODEX_MASTER_PROMPT_EDGE.md`, `context/`, `checklists/`, and `phases/41_EDGE_CLI_PRODUCTION_RELEASE.md` files are absent from this checkout by exact path. The active contract is the Phase 41 prompt, existing code/docs/tests/scripts, Aegis memory, and `tasks/lessons.md`.
- Phase 41 is release preparation only: version metadata, release artifacts, checksums, optional signing hook, SBOM hook/inventory, package manifests, install docs, release notes, release checklist, validation scripts, GitHub release copy, tagging instructions, and production-readiness reporting.
- Phase 41 must not add Phase 42 customer acquisition execution, SaaS, hosted dashboard, billing, license enforcement, hosted telemetry, real drone hardware operation, real-flight deployment, live aircraft control, certification workflows, regulatory approval workflows, detect-and-avoid, autopilot replacement behavior, or major new product features.
- Aegis CLI may use `v1.1.0` release metadata. Aegis Edge must be described as production-ready only for local simulation/SITL/customer evaluation, with no real-flight, certification, autopilot replacement, detect-and-avoid, or guarantee-of-safety claims.
- Existing `orca`/`orca-edge` binary names remain compatibility implementation details; Phase 41 release-facing assets must support the requested `aegis` and `aegis-edge` surfaces.

## Research And False-Positive Check

- [x] Read Aegis memory for phase discipline, Edge safety boundaries, no-real-flight language, release-gate handoff expectations, and exact root/Edge smoke gates.
- [x] Load the TDD workflow skill and use test-first checks for release metadata/artifact/docs/script behavior.
- [x] Confirm absent prompt-named governing files instead of inventing their contents.
- [x] Read `tasks/lessons.md` for release archive drift, tracked-file hygiene, fake/SITL provenance, docs overclaiming, and smoke-gate lessons.
- [x] Inspect existing release scripts, package manifests, install scripts, and CI workflows for CLI-only assumptions and stale `orca` naming.
- [x] Inspect Edge runtime asset discovery/package checks to prevent shipping artifacts with missing schemas/policies/examples/docs/customer-proof materials.
- [x] Inspect release docs/customer pilot materials for overclaims, fake secrets, unsupported pricing/customer names, and legal-template markings.
- [x] Re-check all assumptions after initial tests fail to avoid false positives or accidental future-phase work.

## TDD / Implementation Checklist

- [x] Add failing Phase 41 tests for version metadata: `aegis version`, `aegis version --json`, `aegis-edge version`, and `aegis-edge version --json` include product, release channel, target triple, commit/build date fields, and safety boundary where applicable.
- [x] Add failing Phase 41 tests for release artifact naming, release manifest JSON, checksum coverage for both CLI and Edge artifacts, SBOM hook/inventory status, signing status honesty, and required runtime asset lists.
- [x] Add failing Phase 41 tests for release scripts: `build-release.sh`, `build-cli-release.sh`, `build-edge-release.sh`, `verify-release.sh`, `release-dry-run.sh`, `edge-release-smoke-test.sh`, checksum/SBOM generation, no network/secrets/hardware requirements, and clear limitations output.
- [x] Add failing Phase 41 tests for package manifests/install scripts: Homebrew, Scoop, Winget, npm wrapper if present, Docker/Edge templates if present, no auto-enabled services, checksum verification wording, no telemetry enablement, no unsafe hardware endpoints, and placeholder checksum/version fields.
- [x] Add failing Phase 41 tests for docs/release artifacts: `RELEASE_NOTES.md`, `CHANGELOG.md`, `GITHUB_RELEASE_DRAFT.md`, `release-checklist.md`, `docs/release-tagging.md`, `reports/production-readiness-report.md`, `docs/edge/production-release-checklist.md`, known limitations, install docs, and Edge release-artifact docs.
- [x] Add failing Phase 41 tests for customer-pilot bundle safety: index exists, legal templates marked legal-review required, no real customer names/secrets, no real-flight/certification/detect-and-avoid/autopilot replacement claims.
- [x] Implement final version metadata and CLI/Edge `version` commands without requiring CI metadata for local builds.
- [x] Harden release artifact generation for CLI and Edge, including required runtime assets, manifest, checksums, SBOM hook/inventory, optional signing hook, and package manifests.
- [x] Update install docs, release notes, changelog, known limitations, GitHub release draft, tagging instructions, release checklist, and production-readiness report with prominent safety boundary language.
- [x] Update CI workflows for build/test/red-team/docs check/release dry-run/artifact/checksum verification without hardware, secrets, hosted telemetry, or required SITL.
- [x] Run focused Phase 41 tests and iterate until green.

## Verification Checklist

- [x] `zig build`
- [x] `zig build test`
- [x] `./zig-out/bin/aegis --help`
- [x] `./zig-out/bin/aegis version`
- [x] `./zig-out/bin/aegis version --json`
- [x] `./zig-out/bin/aegis doctor`
- [x] `./zig-out/bin/aegis run -- echo hello`
- [x] `./zig-out/bin/aegis replay --session last --verify`
- [x] `./zig-out/bin/aegis redteam --ci`
- [x] `./zig-out/bin/aegis-edge --help`
- [x] `./zig-out/bin/aegis-edge version`
- [x] `./zig-out/bin/aegis-edge version --json`
- [x] `./zig-out/bin/aegis-edge doctor`
- [x] `./zig-out/bin/aegis-edge redteam --ci`
- [x] `./zig-out/bin/aegis-edge docs check`
- [x] `./zig-out/bin/aegis-edge demo run all`
- [x] `./zig-out/bin/aegis-edge proof generate --demo geofence-deny`
- [x] `./zig-out/bin/aegis-edge safety-case verify --session last`
- [x] `./zig-out/bin/aegis-edge deployment doctor`
- [x] `./zig-out/bin/aegis-edge deployment assets`
- [x] `./zig-out/bin/aegis-edge bench doctor`
- [x] `./zig-out/bin/aegis-edge health doctor`
- [x] `./zig-out/bin/aegis-edge data doctor`
- [x] `scripts/release-dry-run.sh`
- [x] `scripts/build-release.sh`
- [x] `scripts/verify-release.sh`
- [x] `scripts/edge-release-smoke-test.sh`
- [x] `scripts/edge-package-smoke-test.sh`
- [x] `scripts/generate-checksums.sh`
- [x] `scripts/generate-sbom.sh`
- [x] Manual artifact checks: artifacts produced; required runtime assets included; checksums verify; extracted artifacts run smoke tests where host-compatible; release notes/GitHub draft accurate; limitations visible; safety boundary prominent; no unsafe overclaims; fake secrets absent; PX4/ArduPilot/safety/operator/data/health/deployment/redteam/CLI behavior unchanged.

## Review

- Implemented Phase 41 only: final CLI/Edge version metadata, Edge `version` command, Aegis artifact naming, release scripts, checksum/SBOM hooks, release manifest generation, optional signing status, install/package docs, release notes, changelog, GitHub release draft, tagging instructions, production readiness report, release checklists, customer pilot release aliases, CI release checks, and Phase 41 regression tests.
- Artifact status: `dist/` contains `aegis-v1.1.0-{darwin-amd64,darwin-arm64,linux-amd64,linux-arm64}.tar.gz`, `aegis-v1.1.0-windows-amd64.zip`, `aegis-edge-v1.1.0-linux-{amd64,arm64}.tar.gz`, `checksums.txt`, `release-manifest.json`, and `sbom.json`. Checksums verify.
- SBOM status: hook-only dependency/build-target/runtime-asset inventory, not a claimed complete third-party SBOM.
- Signing status: optional hook available; not configured locally and not claimed as signed.
- Safety boundary: release docs and manifests state simulation/SITL/customer-evaluation and bench-preparation only; no real-flight readiness, certification, detect-and-avoid, autopilot replacement, hosted telemetry, real hardware operation, SaaS, billing, or license enforcement was added.
- Verification complete: `zig build`, `zig build test`, required root CLI smokes, required Edge smokes, release dry-run, artifact build, checksum/SBOM generation, release verification, Edge release/package/general smoke scripts, overclaim scan, secret scan, and `git diff --check` passed.
- Phase 42 readiness: ready to start Phase 42 customer acquisition planning from a release-prep standpoint, but not as real-flight readiness or certification.

# Phase 40 Security and Safety Hardening Review

## Review Fix Plan

- [x] Add regression coverage for block-style `watchdog.recommended_fallback_order` YAML lists.
- [x] Add regression coverage that `deployment_mode: packaged` rejects macOS package targets even though source macOS targets are supported.
- [x] Implement the minimal parser/deployment hardening required by those tests.
- [x] Re-run focused tests plus `zig build`, `zig build test`, Edge docs/review checks, and diff hygiene.

## Assumptions

- The prompt-named `README_START_HERE.md`, `CODEX_MASTER_PROMPT_EDGE.md`, `context/`, `checklists/`, and `phases/40_SECURITY_SAFETY_HARDENING_REVIEW.md` files are absent from this checkout by exact path. The active contract is the Phase 40 prompt, existing Edge code/docs/examples/tests, Aegis memory, and `tasks/lessons.md`.
- Phase 40 is a final security/safety hardening review before Phase 41. It may add reports, risk/limitations docs, regression tests, red-team fixtures, docs checks, and small hardening fixes only.
- Phase 40 must not add Phase 41 release packaging except test-required small fixes, Phase 42 customer acquisition, SaaS, hosted telemetry, billing, license enforcement, real drone hardware operation, real-flight deployment, live aircraft control, certification workflows, detect-and-avoid, or autopilot replacement behavior.
- Safety/security posture remains fail closed: unknown command/state/frame/provenance is not safe, stale state is not safe, deny beats allow, CI never prompts, approvals cannot bypass non-overridable safety envelope defaults, emergency modes cannot bypass policy/failsafes/geofence, and skipped/unsupported/inconclusive evidence is not a pass.

## Research And False-Positive Check

- [x] Read Aegis memory for phase discipline, Zig verification lanes, no-real-flight language, Edge red-team/reporting expectations, and clean-checkout hygiene.
- [x] Load the TDD skill and use red-green-refactor for any behavior changes.
- [x] Confirm absent prompt-named governing files instead of inventing their contents.
- [x] Read `tasks/lessons.md` for tracked-file hygiene, SITL/fake provenance, redaction, approval use, and docs-overclaim lessons.
- [x] Inspect current safety, operator/emergency, MAVLink, PX4, ArduPilot, data guard, health/watchdog, deployment/bench, audit/replay, safety-case, customer pilot, and docs-check surfaces for Phase 40 gaps.
- [x] Run or add an overclaim scan that surfaces suspicious phrases for manual review while allowing negative limitation contexts.
- [x] Re-check docs/examples/customer materials/scripts for real-flight/certification/autopilot/detect-and-avoid overclaims and fake secret leakage.

## TDD / Implementation Checklist

- [x] Add failing Phase 40 regression tests for security/safety review report, risk register, customer-readable known limitations, docs overclaim scan output, and review CLI/docs-check behavior if implemented.
- [x] Add failing safety invariant tests for unknown/unsupported commands, stale/unknown state, coordinate/altitude mismatch, allow-vs-envelope, deny precedence, CI no-prompt, approval limits, emergency limits, RTH/LAND policy, and fake/SITL/bench provenance.
- [x] Add failing security invariant tests for redaction before persistence, persistent artifact fake-secret absence, audit tamper/delete/reorder/modify detection, invalid policy fail-closed, audit/data-guard fail-closed, and release/doc secret-pattern scans.
- [x] Add deterministic MAVLink mutation/parser/gateway tests for arbitrary bytes, malformed/truncated/oversized frames, bad checksums, unknown commands/messages, unexpected sysid/compid, partial/duplicate/unsupported mission upload, bounded payload logging, and no panic/unbounded allocation.
- [x] Add or harden PX4/ArduPilot provenance, missing-SITL skip, opt-in gate, stale telemetry, command mediation, safety/data guard/health/safety-case integration tests.
- [x] Add or harden operator approval and emergency behavior tests for hash binding, expiry/max-use/revocation, broad-approval rejection, non-overridable commands, CI ask-to-deny, policy fallback ladder, and audit evidence.
- [x] Add or harden data guard and runtime health tests for unknown classification, endpoint/IP/webhook/tunnel/paste/high-entropy signals, geolocation coarsening, mission/video denial, no raw payload persistence, stale/missing heartbeat, degraded fail-closed behavior, and local-only/no-hosted-telemetry assumptions.
- [x] Add or harden deployment/bench/customer material tests for runtime asset errors, no-actuation boundary, disabled service templates, no privileged/host-network defaults except documented SITL-only cases, no hardware endpoints, legal-template disclaimers, and no real customer names/secrets/pricing overreach.
- [x] Implement narrow hardening fixes surfaced by the failing tests without adding future-phase features.
- [x] Create `docs/edge/security-safety-review.md`, `docs/edge/risk-register.md`, and `docs/edge/known-limitations.md` with honest status, limitations, unresolved risks, release blockers, and Phase 41 recommendation.
- [x] Update Edge docs/customer pilot materials/red-team fixtures/safety-case evidence only where the review identifies gaps.

## Verification Checklist

- [x] Focused Phase 40 test fails before implementation for newly required artifacts/behavior.
- [x] Focused Phase 40 test passes after implementation.
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
- [x] `./zig-out/bin/aegis-edge docs check`
- [x] `./zig-out/bin/aegis-edge demo run all`
- [x] `./zig-out/bin/aegis-edge proof generate --demo geofence-deny`
- [x] `./zig-out/bin/aegis-edge safety-case verify --session last`
- [x] `./zig-out/bin/aegis-edge deployment doctor`
- [x] `./zig-out/bin/aegis-edge bench doctor`
- [x] `./zig-out/bin/aegis-edge health doctor`
- [x] `./zig-out/bin/aegis-edge data doctor`
- [x] If review commands land: `./zig-out/bin/aegis-edge review run`, `review docs-check`, and `review report`.
- [x] Manual checks: risk register honest; limitations customer-readable; review report complete; no positive real-flight/certification claims; fake secrets absent from persistent outputs; skipped/unsupported not counted as pass; fake/SITL/bench/real-flight distinctions clear; customer pilot/SOW materials safe; regression behavior unchanged.

## Review

- Implemented Phase 40 only: added final security/safety review, risk register, customer-readable known limitations, review CLI commands, expanded docs/claim checks, deterministic Phase 40 regressions, safety-case artifact integrity verification, MAVLink unknown-message hardening, data-guard exfil fail-closed behavior, current-position geofence denial, and clearer fake/SITL/PX4/ArduPilot provenance.
- Blockers fixed: current-position-outside-geofence movement was not denied; data-guard heuristic exfil findings could remain observe/allow in strict paths; safety-case verification only proved the event hash chain and did not catch tampered generated report artifacts; unknown MAVLink messages were not consistently surfaced as unsupported; customer/legal materials and stale limitations docs needed stronger boundary wording.
- Review artifacts: `docs/edge/security-safety-review.md`, `docs/edge/risk-register.md`, and `docs/edge/known-limitations.md` are in place. The recommendation is ready for Phase 41 production release preparation, not real-flight readiness, certification, regulatory approval, detect-and-avoid, or autopilot replacement.
- Verification complete: `zig build`, `zig build test`, root CLI smokes, root red-team, Edge doctor/red-team/docs/demo/proof/safety-case/deployment/bench/health/data commands, review commands, and `git diff --check` passed.
- Remaining limitations and accepted risks: no real-flight validation, no certification/regulatory approval, no detect-and-avoid, no autopilot replacement, incomplete MAVLink command/message coverage, fake/SITL/bench evidence is not real-flight evidence, and PX4/ArduPilot SITL remain opt-in/skipped when unavailable.

## Review Fix Results

- Fixed P2 watchdog policy parsing: `watchdog.recommended_fallback_order` now accepts standard block-style YAML sequences while preserving inline list support and fallback-command validation.
- Fixed P2 packaged deployment checks: packaged profiles now require `TargetArch.packageStatus() == active`, so macOS source targets can remain supported while unsupported macOS package profiles are rejected.
- Added regressions in `tests/phase37_edge_runtime_health.zig` and `tests/phase36_edge_deployment_release.zig`. Both failed before the fix and pass after.
- Verification after review fixes: `zig build`, `zig build test --summary all`, `aegis-edge docs check`, `aegis-edge review docs-check`, `aegis-edge deployment doctor`, `aegis-edge health doctor`, and `git diff --check` passed.

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
