# MAVLink Limitations

Phase 28 is a gateway foundation, not a deployment package.

Not implemented:

- Real serial MAVLink endpoints.
- Real UDP MAVLink endpoints.
- PX4 integration.
- ArduPilot integration.
- PX4 SITL or ArduPilot SITL.
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

MAVLink2 signing detection records whether a signing block is present. Verification is reported as unavailable because Phase 28 does not manage keys or verify signatures.

Mission handling is generic MAVLink transaction tracking only. It tracks count, sequence, duplicates, partial uploads, ACK, clear, set-current, completion, and denial state. It does not emulate PX4 or ArduPilot mission semantics.
