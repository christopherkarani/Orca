# Customer Demo Script

Opening positioning: Edge is a simulation/SITL/bench-preparation safety-policy runtime, MAVLink mediation layer, safety-envelope evaluator, audit/replay system, red-team harness, and safety-case evidence generator. It is not real flight, not live aircraft control, not certification, not detect-and-avoid, and not an autopilot replacement.

## demo 1: geofence deny

- Command to run: `./zig-out/bin/edge demo run geofence-deny`
- Expected output: deny.
- What to say: Edge denied a waypoint outside the configured geofence.
- What not to say: This proves aircraft airworthiness.
- Artifact generated: safety report and replay reference.
- Limitation to mention: fake adapter evidence unless a SITL scenario is explicitly configured.

## demo 2: disable_failsafe deny

- Command to run: `./zig-out/bin/edge demo run disable-failsafe-deny`
- Expected output: deny.
- What to say: Safety-critical failsafe changes are blocked by policy.
- What not to say: Aegis takes over or substitutes for autopilot failsafes.
- Artifact generated: demo report reference.
- Limitation to mention: customer-specific failsafe mappings still require review.

## demo 3: emergency LAND allowed/logged according to policy

- Command to run: `./zig-out/bin/edge demo run emergency-land`
- Expected output: allow.
- What to say: Emergency behavior still passes through policy and is audited.
- What not to say: Emergency mode bypasses the customer safety process.
- Artifact generated: audit event and replay reference.
- Limitation to mention: not live aircraft control.

## demo 4: stale telemetry deny

- Command to run: `./zig-out/bin/edge demo run stale-telemetry-deny`
- Expected output: deny.
- What to say: Stale state fails closed for movement.
- What not to say: Watchdog replaces aircraft health systems.
- Artifact generated: runtime health finding.
- Limitation to mention: simulator evidence only.

## demo 5: mission outside geofence deny

- Command to run: `./zig-out/bin/edge demo run all`
- Expected output: mission/geofence scenario denies.
- What to say: Mission items are evaluated against policy boundaries.
- What not to say: All mission protocols are covered.
- Artifact generated: scenario output and safety-case reference.
- Limitation to mention: covered message subset only.

## demo 6: telemetry/data exfil deny/redact

- Command to run: `./zig-out/bin/edge demo run data-exfil-deny`
- Expected output: deny/redact.
- What to say: Sensitive telemetry and mission data are evaluated before egress.
- What not to say: Aegis sends telemetry to a hosted service.
- Artifact generated: data guard finding.
- Limitation to mention: local-only evaluation; customer endpoint policy must be reviewed.

## demo 7: safety-case report

- Command to run: `./zig-out/bin/edge proof generate --demo geofence-deny`
- Expected output: local safety-case evidence paths.
- What to say: Reports summarize provenance, decisions, findings, replay, and limitations.
- What not to say: This is a certification report.
- Artifact generated: safety report and evidence references.
- Limitation to mention: non-certification evidence.

## demo 8: red-team scorecard

- Command to run: `./zig-out/bin/edge redteam --ci`
- Expected output: deterministic red-team scorecard.
- What to say: Skipped and unsupported cases are documented and are not passes.
- What not to say: The suite proves every unsafe action is blocked.
- Artifact generated: red-team scorecard.
- Limitation to mention: customer-specific cases may need expansion.

Closing CTA: If these boundaries match the evaluation need, propose a two-week pilot using the intake questionnaire, readiness checklist, and agreed success criteria.
