# Aegis Edge

Aegis Edge is the drone and robotics safety-policy and audit runtime scaffold for future Aegis work.

## What Belongs Here

- Edge domain types such as vehicle state, command request, safety decision, and safety envelope.
- Edge policy contracts and audit event shapes.
- Adapter interfaces and local fake adapters used for deterministic tests.
- Honest doctor and capability reporting for scaffolded or unavailable Edge capabilities.

## What Does Not Belong Here

- MAVLink gateways.
- PX4 or ArduPilot integration.
- Real drone command enforcement.
- Flight-controller or autopilot replacement behavior.
- Detect-and-avoid.
- Regulatory approval, certification, or airworthiness claims.
- Real hardware dependencies, external network services, SaaS, telemetry, or monetization.

## Current Status

Phase 24 remains scaffold-only for Edge behavior. Edge can now import Aegis Core and evaluate placeholder Edge actions through the shared Core decision contract. Aegis Edge is not a flight controller, not an autopilot replacement, not detect-and-avoid, and not regulatory approval or certification. It must not be used for real flight until later simulation, bench, and customer safety validation phases are complete.

If installed, `aegis-edge` prints an honest scaffold message and reports unsupported capabilities as unavailable or not implemented.

## Future Phases

Later phases may add simulation-only policy evaluation, bench validation, and adapter work. MAVLink, PX4, ArduPilot, and real-flight behavior remain out of scope for Phase 24.
