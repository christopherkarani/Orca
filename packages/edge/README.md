# Aegis Edge

Aegis Edge is the drone and robotics safety-policy and audit runtime package for future Aegis work. Phase 26 defines the domain model and versioned safety schema that later phases can use for simulation, mediation, audit, replay, and safety reports.

## Current Status

Phase 25 keeps Edge scaffold-only. Phase 26 adds domain and schema contracts while preserving that safety boundary. Aegis Edge is not a flight controller, not an autopilot replacement, not detect-and-avoid, and not regulatory approval or certification. It is not ready for real flight and must not be used for real flight.

The package currently provides:

- Explicit vehicle, command, state, coordinate, geofence, battery, link, sensor, risk, and safety-envelope types.
- Validation helpers for units, coordinate frames, altitude references, stale state, unknown state, and command-policy conflicts.
- Versioned schema descriptors for Edge policy, Edge events, and future safety reports.
- A local fake adapter scaffold for deterministic tests.
- Honest `aegis-edge doctor` and `aegis-edge schema` output.

## What Does Not Belong Here

- MAVLink gateways.
- PX4 or ArduPilot integration.
- ROS2 control integration.
- Real drone command enforcement.
- Flight-controller or autopilot replacement behavior.
- Detect-and-avoid.
- Operator approval runtime flows.
- Regulatory approval, certification, or airworthiness claims.
- Real hardware dependencies, external network services, SaaS, telemetry, or monetization.

## Safety Boundary

Unknown, stale, expired, or ambiguous state is not treated as safe. Fake adapter state must remain labeled as fake adapter state. SITL, bench, and customer-adapter provenance values are modeled for later audit/reporting phases, but Phase 26 does not implement real hardware behavior.

See:

- `docs/edge/domain-model.md`
- `docs/edge/coordinate-frames.md`
- `docs/edge/safety-policy.md`
- `docs/edge/safety-schemas.md`
