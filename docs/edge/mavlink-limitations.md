# MAVLink Limitations

Phase 28 is a gateway foundation, not a deployment package. Phase 29 adds PX4 SITL simulation through the `aegis-edge px4` command surface.

Not implemented:

- Real serial MAVLink endpoints.
- Real UDP MAVLink endpoints.
- ArduPilot integration.
- ArduPilot SITL.
- ROS2 integration.
- Real-flight deployment.
- Customer hardware bench procedure.
- Operator approval runtime.
- MAVLink signing key management.
- MAVLink signing verification.
- Payload confidentiality.
- Detect-and-avoid.
- Autopilot replacement behavior.
- Regulatory approval, certification, or airworthiness claims.

MAVLink2 signing detection records whether a signing block is present. Verification is reported as unavailable because Aegis Edge does not manage keys or verify signatures in Phase 29.

Mission handling is generic MAVLink transaction tracking only. It tracks count, sequence, duplicates, partial uploads, ACK, clear, set-current, completion, and denial state. It does not emulate PX4 or ArduPilot mission semantics.
