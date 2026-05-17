# Aegis v1.1.0 Release Notes

Release status: production release candidate for Orca and Edge evaluation artifacts.

## Orca

Orca v1.1.0 provides local command supervision, policy checks, redaction before persistence, audit/replay, MCP mediation, plugin helpers, and deterministic red-team checks. Install from source or from a checksum-verified release artifact.

Security model: local-first enforcement and evidence. No hosted telemetry is enabled by default, and no secrets are required for normal install or tests.

Known limitations: transparent OS-level enforcement depends on platform capability reports from `orca doctor`; unsupported or unavailable backends must not be treated as active protection.

## Edge

Edge v1.1.0 release artifacts are production-prepared for simulation/SITL/customer-evaluation and bench-preparation only. Edge is not a flight controller, not an autopilot replacement, not detect-and-avoid, not regulatory approval or certification, and not real-flight readiness.

Included capabilities:

- MAVLink gateway for bounded fake/SITL mediation.
- PX4 SITL support, opt-in local simulation only.
- ArduPilot SITL support, opt-in local simulation only.
- Safety enforcement for geofence, altitude, velocity, battery, mission, freshness, and command-risk checks.
- Operator approvals, emergency modes, data guard, runtime health, and watchdog diagnostics.
- Red-team/fault injection fixtures, audit/replay, safety-case reports, deployment/ARM64 metadata, customer pilot package, and known limitations.

Install:

```sh
./scripts/build-release.sh
cd dist && sha256sum -c checksums.txt
```

Do not use these artifacts for real flight, live aircraft control, certification, regulatory approval, BVLOS authorization, detect-and-avoid, or autopilot replacement.
