# PX4 Limitations

PX4 support in Phase 29 is simulation-only.

Supported:

- Deterministic fake-PX4 telemetry and command fixtures.
- PX4 SITL configuration and honest doctor output.
- MAVLink command mediation through existing Edge policy.
- Redacted scenario audit/replay artifacts.
- Opt-in PX4 SITL integration-test gating.

Not supported:

- Real drone hardware.
- Real-flight deployment.
- Customer hardware bench procedures.
- ArduPilot behavior inside PX4 commands; use `aegis-edge ardupilot` for ArduPilot simulation evidence.
- ROS2 control.
- Detect-and-avoid.
- Autopilot replacement behavior.
- Regulatory approval, certification, or airworthiness claims.

Fake-PX4 artifacts use `fake_adapter` provenance. PX4 SITL artifacts must use `sitl_px4` provenance. A fake adapter pass must never be presented as PX4 SITL success.
