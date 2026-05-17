# Edge Security and Safety Hardening Review

Review date: TBD
Reviewed version: TBD

## Scope

Phase 40 reviews Orca and Edge before Phase 41 production release preparation. The scope is release-blocking bugs, safety invariant violations, redaction failures, audit/replay integrity, policy bypasses, unsafe command allowance, stale-state mistakes, approval and emergency-mode bypasses, MAVLink parser/gateway hardening, PX4/ArduPilot SITL provenance, fake/SITL/bench/real-flight separation, customer pilot materials, runtime assets, and broken tests.

## Out of scope

Phase 40 does not implement production release packaging, customer acquisition, SaaS, hosted telemetry, billing, license enforcement, real drone hardware operation, real-flight deployment, live aircraft control, regulatory approval, certification, detect-and-avoid, autopilot replacement behavior, or new autonomous flight features.

## Safety boundary

Edge is a local policy, mediation, audit, replay, red-team, and safety-case evidence tool for fake-adapter, PX4 SITL, ArduPilot SITL, and no-actuation bench-preparation evaluation. Edge must still not claim real-flight readiness. Edge is not a flight controller, not an autopilot replacement, not detect-and-avoid, and not regulatory approval or certification.

## Security invariants checked

- Redaction occurs before persistence.
- Raw fake secrets must not appear in `events.jsonl`, summaries, replay output, safety reports, safety-case reports, red-team reports, customer pilot reports, doctor/demo output, or evidence bundles.
- Audit hash chains detect modified, deleted, and reordered events.
- Safety-case verification checks the audit chain and generated report/evidence artifact integrity.
- Invalid policies fail closed in strict and CI paths.
- Audit writer failure and data guard failure fail closed where required.
- No normal test path requires external network, real hardware, hosted telemetry, or secrets.

## Safety invariants checked

- Unknown, unsupported, stale, or invalid state is not treated as safe.
- Unknown and unsupported commands are not treated as safe.
- Deny beats allow.
- Explicit allow still must pass geofence, altitude, velocity, battery, state, authority, and runtime health checks.
- CI mode never prompts.
- Operator approval is scoped, expiring, hash-bound, max-use-bound, and cannot override non-overridable critical commands or safety envelope defaults.
- Emergency behavior cannot disable failsafe, disable geofence, enable raw actuator output, or override operator authority.
- RTH requires a valid home position unless an explicit policy alternative exists.
- Fake adapter success is not SITL success. SITL success is not real-flight success. Bench evidence is not real-flight evidence.
- Skipped, unsupported, and inconclusive evidence never counts as pass.

## Test suites run

Required Phase 40 verification includes `zig build`, `zig build test`, root Orca smoke commands, Edge doctor/redteam/docs/demo/proof/safety-case/deployment/bench/health/data checks, and local review commands. PX4 and ArduPilot SITL paths remain opt-in and must pass or skip/unsupported honestly.

## Red-team coverage

The deterministic Edge red-team suite covers geofence, altitude, velocity, battery, stale state, mission, MAVLink parser/command, endpoint spoofing, approval bypass, emergency bypass, telemetry/data guard, health/watchdog, audit redaction, safety-case, unsupported feature, PX4 SITL, and ArduPilot SITL categories. Missing SITL is not counted as pass.

## Component status

- Parser hardening status: deterministic mutation tests cover malformed, truncated, oversized, bad-checksum, unknown command, unknown message, and high-volume stream handling without panics.
- MAVLink hardening status: gateway policy integration denies unsafe mapped commands, flags endpoint mismatch, bounds payload previews, detects MAVLink2 signing presence without claiming verification, and preserves provenance.
- PX4 SITL status: opt-in local simulation only; fake-PX4 provenance is distinct from PX4 SITL and real flight.
- ArduPilot SITL status: opt-in local simulation only; fake-ArduPilot provenance is distinct from ArduPilot SITL and real flight.
- Fake adapter status: deterministic local fixtures only, never SITL or real-flight evidence.
- Safety enforcement status: active for simulation/SITL/bench-preparation policies, not a flight controller.
- Operator approval status: local scoped approvals only; no safety-envelope bypass by default.
- Emergency behavior status: policy-controlled fallback recommendations only; no autopilot failsafe replacement.
- Telemetry/data guard status: local classification, redaction, and egress decisions; no hosted telemetry.
- Runtime health/watchdog status: local health findings and degraded-mode decisions; no external monitoring assumption.
- Audit/replay status: hash-chained local sessions with replay verification.
- Safety-case report status: local engineering evidence with limitations and non-certification disclaimer.
- Deployment/bench status: source/package/container/ARM64/bench-preparation diagnostics only; no actuation or real-flight deployment.
- Customer pilot material review: templates and examples are simulation/SITL/bench-preparation only, with legal/commercial review requirements where customer-sendable.

## Known limitations

See `docs/edge/known-limitations.md`. The main limitations are no real-flight readiness, no certification, no BVLOS approval, no detect-and-avoid, no autopilot replacement, incomplete MAVLink command coverage, unsupported geofence shapes, coordinate-frame and altitude-reference limits, SITL limitations, fake-adapter limitations, bench limitations, data guard limits, runtime health limits, approval/emergency limits, and customer-specific integration limits.

## Unresolved risks

See `docs/edge/risk-register.md`. Accepted limitations remain around real-flight validation, detect-and-avoid, full MAVLink coverage, SITL-to-flight equivalence, unsupported vehicle modes, customer-specific integrations, and customer overinterpretation of evidence.

## Release blockers

No Phase 40 release blockers remain after the hardening fixes in this phase. Any new failing required test, raw secret persistence, positive real-flight/certification claim, fake/SITL/bench provenance confusion, or skipped/unsupported result counted as pass is a release blocker.

## Recommendation

Recommendation: Ready for Phase 41 production release preparation.

This recommendation is not real-flight readiness, certification, regulatory approval, detect-and-avoid approval, or autopilot replacement approval.
