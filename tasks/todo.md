# Phase 32 Operator Approval and Emergency Modes

## Assumptions

- The prompt-named `README_START_HERE.md`, `CODEX_MASTER_PROMPT_EDGE.md`, `context/`, `checklists/`, and `phases/32_OPERATOR_APPROVAL_AND_EMERGENCY_MODES.md` files are absent from this checkout. The active contract is the Phase 32 prompt, root Aegis contracts, current Edge docs/code, Phase 31 task notes, and `tasks/lessons.md`.
- Phase 32 is limited to operator approval and emergency-mode decision behavior for fake-adapter, PX4 SITL, and ArduPilot SITL contexts. It must not add Phase 33 safety-case report generation, Phase 34 red-team/fault-injection suite, hardware bench deployment, real drone hardware integration, real-flight deployment, customer hardware procedures, SaaS, monetization, telemetry, regulatory/certification claims, detect-and-avoid, autopilot replacement behavior, or real-flight instructions.
- Existing Phase 31 safety enforcement is the integration point. Approval and emergency behavior should extend that evaluator and scenario flow rather than creating a separate command-decision engine.
- Normal tests must remain deterministic and offline. PX4 and ArduPilot SITL remain opt-in and must not be mislabeled as fake evidence or real-flight evidence.

## Research And False-Positive Check

- [x] Read Aegis memory and `tasks/lessons.md` for phase discipline, tracked-file hygiene, redaction, fake-vs-SITL boundaries, and Phase 31 explicit-deny regression.
- [x] Confirm absent prompt-named governing files instead of inventing their contents.
- [ ] Inspect current Edge domain, policy loader/evaluator, safety evaluator, MAVLink gateway, PX4 scenario runner, ArduPilot scenario runner, audit event model, CLI, docs, and examples.
- [ ] Verify current baseline tests before implementation where useful.
- [ ] Re-check that new code does not overclaim real hardware, detect-and-avoid, autopilot replacement, regulatory/certification status, or real-flight readiness.

## TDD / Implementation Checklist

- [ ] Add Phase 32 approval model tests first: request/decision creation, exact-action scope, expiry, default max uses, policy/command/vehicle/state binding, stale/mismatched/expired/revoked/reused rejection, broad-scope rejection, and non-overridable command denial.
- [ ] Add Phase 32 approval behavior tests: arm/takeoff ask creates approval request, exact valid approval allows only the bound action when the safety envelope passes, geofence/altitude failures still deny, CI mode ask becomes deny, and CI tests never prompt.
- [ ] Add Phase 32 emergency tests: LAND/RTH/HOLD evaluation, RTH home-position requirement, stale-state LAND policy gate, disarm not default-safe, unsafe commands remain denied, and fallback ladder selects the first valid safe fallback or no safe fallback.
- [ ] Add integration/audit/redaction tests for MAVLink fake, PX4 fake/SITL scenario flow, ArduPilot fake/SITL scenario flow, approval events, emergency events, secret redaction, replay-safe outputs, observe/enforce/CI semantics, and provenance preservation.
- [ ] Implement reusable `packages/edge/src/operator/` modules for request/decision/scope/token/validation/store/prompt/audit behavior with bounded local-only persistence.
- [ ] Implement reusable emergency-mode modules under `packages/edge/src/emergency/` or the closest existing Edge layout.
- [ ] Wire approval flow into the safety evaluator: `ask` produces a bounded approval request, valid approvals can turn ask into allow, invalid/missing approvals stay ask/deny by mode, and non-overridable/safety-envelope denials remain denied.
- [ ] Wire emergency fallback evaluation through policy-controlled safety behavior without creating a policy bypass.
- [ ] Wire MAVLink, PX4, and ArduPilot scenario paths to consume pre-seeded approvals, expired/mismatched approvals, emergency fallback recommendations, and preserved fake/SITL provenance.
- [ ] Add `aegis-edge operator ...` and `aegis-edge emergency ...` CLI commands plus approval/emergency info in `safety evaluate` where relevant.
- [ ] Add deterministic examples under `examples/edge/operator/` for policies, requests, states, approvals, and scenarios.
- [ ] Update docs under `docs/edge/` and `packages/edge/README.md` with approval lifecycle, scope/expiry/revocation, non-interactive CI behavior, emergency fallback behavior, simulation/SITL boundaries, and explicit non-flight limitations.

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
- [ ] `./zig-out/bin/aegis-edge operator list`
- [ ] `./zig-out/bin/aegis-edge operator request --policy examples/edge/operator/policies/approval-basic.yaml --request examples/edge/operator/requests/arm.json --state examples/edge/operator/states/fresh-state.json`
- [ ] `./zig-out/bin/aegis-edge emergency evaluate --policy examples/edge/operator/policies/emergency-basic.yaml --state examples/edge/operator/states/critical-battery-state.json --reason critical_battery`
- [ ] `./zig-out/bin/aegis-edge emergency scenario run --policy examples/edge/operator/policies/emergency-basic.yaml --scenario examples/edge/operator/scenarios/critical-battery-emergency-land.yaml`
- [ ] Manual Phase 32 checks from the prompt.
- [ ] `git diff --check`

## Review

- Pending implementation.
