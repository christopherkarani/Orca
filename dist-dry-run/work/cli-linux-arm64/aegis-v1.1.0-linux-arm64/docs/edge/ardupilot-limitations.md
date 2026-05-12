# ArduPilot Limitations

ArduPilot support in Phase 30 is simulation-only.

Implemented:

- ArduPilot SITL configuration and honest doctor output.
- Deterministic fake-ArduPilot telemetry and command fixtures.
- Copter-oriented telemetry mapping for heartbeat, global/local position, attitude, battery, GPS, link freshness, and selected custom modes.
- MAVLink command mediation through the existing Phase 28 gateway and Phase 27 policy engine.
- Scenario artifacts with redaction and explicit environment/provenance labels.
- Opt-in ArduPilot SITL integration-test gating.

Not implemented:

- Real drone hardware.
- Real serial or hardware MAVLink endpoints.
- Real-flight deployment.
- Customer hardware bench procedures.
- Operator approval runtime.
- Detect-and-avoid.
- Autopilot replacement behavior.
- Regulatory approval, certification, or airworthiness claims.

Fake-ArduPilot artifacts use `fake_ardupilot_adapter` provenance. ArduPilot SITL artifacts must use `sitl_ardupilot` provenance. A fake adapter pass must never be presented as ArduPilot SITL success.

ArduPilot modes are mapped only where Phase 30 has an explicit conservative mapping. Unknown or unsupported modes remain `unknown`.
