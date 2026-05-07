# Aegis v1.0.0 Release-Candidate Audit

## Assumptions

- This is a final release-candidate audit, not a feature phase.
- Fixes are allowed only for confirmed release blockers in the requested scope.
- The local branch `release/v1.0.0-rc1` is the candidate under test.
- Runtime behavior, tests, and scripts are the source of truth; docs must not overclaim beyond those results.
- Fake secret fixtures and demo values must remain synthetic and must not appear in persistent audit or user-facing outputs.

## Research And False-Positive Check

- [x] Review lessons and prior project memory for known Aegis release-gate pitfalls.
- [x] Inventory current build steps, scripts, policies, examples, docs, and runtime assets.
- [x] Run independent read-only checks for docs/schema/security/platform surfaces before deciding whether any failure is a blocker.
- [x] Re-check each suspected issue against runtime behavior or exact source evidence before patching.

## TDD / Release Validation Checklist

- [x] Baseline `zig build`.
- [x] Baseline `zig build test`.
- [x] Baseline `./zig-out/bin/aegis redteam --ci`.
- [x] Baseline `./zig-out/bin/aegis doctor`.
- [x] Baseline `./zig-out/bin/aegis version`.
- [x] Baseline `./zig-out/bin/aegis version --json`.
- [x] Run `scripts/v1-smoke-test.sh` if available.
- [x] Run `zig build fuzz` if available.
- [x] Validate every preset policy and every example policy.
- [x] Verify README quickstart commands against the current CLI.
- [x] Verify the leaky-agent demo works.
- [x] Verify replay detects audit tampering.
- [x] Verify fake secret values are absent from events, summaries, replay output, doctor output, demo output, README, and docs.
- [x] Verify unsupported platform features are not reported as active.
- [x] Verify MCP stdout remains protocol-only.
- [x] Verify CI mode never prompts.
- [x] Verify release artifacts build or release scripts clearly document how to build them.
- [x] Verify install scripts do not collect telemetry.
- [x] Verify docs do not claim perfect sandboxing or universal transparent network/filesystem enforcement.

## Fix Scope

- [x] If a release blocker is confirmed, add or run the smallest failing check that proves it.
- [x] Patch only the blocker and directly related tests/docs/scripts.
- [x] Re-run the affected checks plus the core release matrix.

## Review

- Fixed verified replay tamper handling: unknown event fields now fail verification, summary metadata has a `summary_hash`, verified replay rejects summary display tampering, and JSON replay output is rebuilt from known canonical event fields instead of raw lines.
- Fixed review follow-up tamper hardening: `updateFinalHash` now verifies the existing `summary_hash` before rewriting `summary.json`, with a regression test proving modified summaries are not re-signed.
- Updated v1.0.0 release metadata across `build.zig`, `build.zig.zon`, release/install scripts, package templates, SBOM output, docs, and MCP client info.
- Added `schemas/policy-v1.json`, `schemas/event-v1.json`, and `schemas/mcp-manifest-v1.json`; schema JSON validates and the files are included in the tracked patch surface.
- Fixed release/install script issues: `install.ps1` now derives its default URL from the selected version, and `build-release.ps1` writes checksums/SBOM natively instead of depending on POSIX shell helpers.
- Added `scripts/v1-smoke-test.sh` and verified it.
- Corrected docs for policy load order and Linux capability reporting; docs no longer claim active Linux strong sandbox or transparent filesystem enforcement.
- Final verification passed: `zig build`, `zig build test`, `./zig-out/bin/aegis redteam --ci`, `./zig-out/bin/aegis doctor`, `./zig-out/bin/aegis version`, `./zig-out/bin/aegis version --json`, `scripts/v1-smoke-test.sh`, `zig build fuzz`, all policy checks, README quickstart, leaky-agent demo, replay tamper checks, MCP protocol-only stdout, CI no-prompt behavior, release artifact build/checksum verification with v1 schema files present in tar/zip artifacts, local install from artifact, docs validation, JSON/shell/Ruby syntax checks, `zig fetch --debug-hash .`, and `git diff --check`.

Remaining release blocker:

- `LICENSE` still records "License pending" and says not to distribute release artifacts until the project owner chooses and records the final license. I did not choose a license.

---

# Phase 23 Product Split And Monorepo Contract

## Assumptions

- Phase 23 is a product-structure phase, not a runtime-feature phase.
- The Edge-specific prompt files named by the task are not present in this checkout; the task prompt, existing architecture contracts, security invariants, and lessons are the active contract.
- Existing `src/` modules are stable Aegis CLI v1.0 implementation surface and should not be mass-moved if wrapper package roots can preserve behavior with lower risk.
- `aegis` must remain the existing CLI binary.
- Any `aegis-edge` binary added in this phase must be an honest scaffold only.

## Research And False-Positive Check

- [x] Review memory and `tasks/lessons.md` for phase-boundary, security, and clean-checkout pitfalls.
- [x] Check whether named Edge governing docs exist in this checkout.
- [x] Inspect current build/module layout before deciding whether to move code or add package wrapper roots.
- [x] Verify current CLI behavior before making source changes where practical.
- [x] Re-check all Edge wording for unsupported real-flight, certification, detect-and-avoid, autopilot, PX4, ArduPilot, and MAVLink claims.

## TDD / Implementation Checklist

- [x] Baseline `zig build`.
- [x] Baseline `zig build test`.
- [x] Baseline `./zig-out/bin/aegis redteam --ci`.
- [x] Create `packages/core/src` and `packages/core/tests` as the shared package contract over policy, decision, audit, replay, redaction, schema, fixture/red-team, capability, and platform-independent utilities.
- [x] Create `packages/cli/src` and `packages/cli/tests` as the CLI package contract over existing desktop/CI command behavior.
- [x] Create `packages/edge/src` and `packages/edge/tests` with scaffold-only domain types, adapter contract, fake adapter placeholder, safety decision/envelope, audit placeholder, and doctor/capability placeholder.
- [x] Add package READMEs for core, cli, and edge with purpose, belongs/does-not-belong, current status, and future phases.
- [x] Update build configuration so core, cli, and edge package modules build/test; keep `aegis` output unchanged.
- [x] Add an honest `aegis-edge` placeholder binary only if it can be kept scaffold-only and low risk.
- [x] Add tests for package build roots, Edge scaffold honesty, docs real-flight readiness claims, and fake secret persistence guardrails.
- [x] Preserve existing CLI behavior and imports; avoid rewrites unless a test proves they are necessary.

## Verification Checklist

- [x] `zig build`
- [x] `zig build test`
- [x] `./zig-out/bin/aegis --help`
- [x] `./zig-out/bin/aegis version`
- [x] `./zig-out/bin/aegis version --json`
- [x] `./zig-out/bin/aegis doctor`
- [x] `./zig-out/bin/aegis run -- echo hello`
- [x] `./zig-out/bin/aegis replay --session last --verify`
- [x] `./zig-out/bin/aegis policy check`
- [x] `./zig-out/bin/aegis redteam --ci`
- [x] If added: `./zig-out/bin/aegis-edge --help`
- [x] If added: `./zig-out/bin/aegis-edge doctor`
- [x] `git diff --check`

## Review

- Added `packages/core`, `packages/cli`, and `packages/edge` package roots with focused contract tests.
- Kept the stable v1.0 implementation in `src/` and used package roots as the Phase 23 monorepo contract to avoid risky import rewrites.
- Added scaffold-only Edge domain, policy, adapter, audit, capability, doctor, and `aegis-edge` placeholder surfaces.
- Updated `build.zig` so core, cli, edge, package contract tests, Phase 23 docs/security contract tests, and the existing `aegis` binary build together.
- Updated `README.md`, `docs/README.md`, and package READMEs with product boundaries and explicit Edge non-flight limitations.
- Made no-arg `aegis policy check` validate the built-in default policy so the exact Phase 23 smoke command succeeds without creating `.aegis/policy.yaml`.
- Final verification passed: `zig build`, `zig build test`, `aegis --help`, `aegis version`, `aegis version --json`, `aegis doctor`, `aegis run -- echo hello`, `aegis replay --session last --verify`, `aegis policy check`, `aegis redteam --ci`, `aegis-edge --help`, `aegis-edge doctor`, `.aegis` fake-secret grep, and `git diff --check`.

---

# Phase 24 Aegis Core Library And ABI

## Assumptions

- The Edge governing documents named in the task are not present in this checkout; the task prompt, existing package READMEs, security invariants, architecture contracts, and lessons are the active source of truth.
- Phase 24 is a shared-library/API hardening phase, not an Edge runtime phase.
- Existing CLI implementation under `src/` is stable v1.0 behavior and should continue to compile and run through Core compatibility wrappers.
- `packages/core` should expose the reusable engine contract first; source relocation can wait unless tests prove it is necessary.
- Edge action types remain placeholder/domain-ready only and must not mediate real drone commands.
- Any C ABI surface added in this phase is experimental unless it has dedicated compile tests and clear ownership docs.

## Research And False-Positive Check

- [x] Review memory and `tasks/lessons.md` for Aegis phase-boundary, audit, schema, and secret-redaction pitfalls.
- [x] Check whether the requested governing docs exist in this checkout.
- [x] Inspect policy/action/decision paths before deciding API shape.
- [x] Inspect audit/redaction/replay/schema/red-team paths before deciding API shape.
- [x] Confirm pre-existing dirty changes and avoid overwriting user-owned edits.
- [x] Re-check all Edge and ABI wording for real-flight, certification, stable-ABI, MAVLink, PX4, and ArduPilot overclaims.

## TDD / Implementation Checklist

- [x] Add failing Core contract coverage for shared CLI and Edge action evaluation through one policy API.
- [x] Add failing Core contract coverage for redaction, audit writing, replay verification, schema lookup, and fake secret persistence guards.
- [x] Add failing Edge import coverage proving Edge can call Core policy, decision, audit, and redaction APIs without copying logic.
- [x] Add or harden Core entrypoints for policy load/validate/evaluate, decision creation, action modeling, audit event creation/writing, replay verification, redaction, schema lookup, and fixture helpers.
- [x] Add Edge placeholder action cases to the shared action model without implementing real command enforcement.
- [x] Add schema registry entries for policy, event, MCP manifest, Edge policy placeholder, Edge event placeholder, and safety report placeholder.
- [x] Add optional experimental C ABI skeleton only if it stays low risk, documented, and compile-tested.
- [x] Update CLI package wrappers/usages so CLI behavior is demonstrably still going through Core.
- [x] Update dependency notes if any dependency changes; otherwise document no new dependency.

## Verification Checklist

- [x] Baseline and final `zig build`
- [x] Baseline and final `zig build test`
- [x] `./zig-out/bin/aegis --help`
- [x] `./zig-out/bin/aegis version`
- [x] `./zig-out/bin/aegis version --json`
- [x] `./zig-out/bin/aegis doctor`
- [x] `./zig-out/bin/aegis run -- echo hello`
- [x] `./zig-out/bin/aegis replay --session last --verify`
- [x] `./zig-out/bin/aegis redteam --ci`
- [x] If present: `./zig-out/bin/aegis-edge --help`
- [x] If present: `./zig-out/bin/aegis-edge doctor`
- [x] Manually grep persistent outputs for synthetic fake secrets.
- [x] `git diff --check`

## Review

- Added a deliberate `packages/core` facade: `api` for policy load/validate/evaluate, decision creation, audit event creation/writing, replay verification/loading/output, and redaction; `actions` for shared action types; `schemas` for registry lookup; and `abi` for the experimental C ABI skeleton.
- Extended the shared Core action model with Edge placeholder actions for vehicle state reads, command requests, mission uploads, geofence evaluation, telemetry egress, emergency command requests, and safety-envelope evaluation.
- Routed Edge placeholder evaluation through the same Core policy evaluation path as CLI actions; Edge placeholder actions return observe-only decisions and do not implement real drone command enforcement.
- Added schema registry entries and placeholder schema files for Edge policy, Edge event, and safety report schemas while preserving existing policy, event, and MCP manifest schemas.
- Added Core, CLI, and Edge contract tests for shared policy evaluation, CI non-interactive behavior, deny priority, audit writing, replay/hash verification, schema discovery, fake-secret persistence guards, Edge Core import, and ABI redaction compilation.
- Added `packages/core/ABI.md` and updated package/docs/dependency notes to state no new dependencies and ABI experimental status.
- Verification passed: `zig build`, `zig build test`, required `aegis` smokes, `aegis-edge` smokes, red-team CI, fake-secret grep over `.aegis`, Edge/ABI wording review, and `git diff --check`.
