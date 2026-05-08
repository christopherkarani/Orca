# Edge Limitations

Aegis Edge Phase 29 implements policy evaluation, a MAVLink gateway foundation for fake/in-memory protocol mediation, deterministic fake-PX4 scenarios, and opt-in PX4 SITL simulation checks. It is not command forwarding to a real flight controller.

Not implemented:

- ArduPilot integration.
- ROS2 integration.
- ArduPilot SITL control.
- Real serial or hardware MAVLink endpoints.
- Real hardware integration.
- Real-flight deployment.
- Customer hardware bench procedure.
- Operator approval runtime.
- Emergency runtime behavior beyond policy decisions and fallback recommendations.
- MAVLink signing key management or signing verification.
- SaaS, monetization, telemetry, certification, or regulatory claims.

Coordinate frames and altitude references must be explicit. Unsupported geospatial conversions fail clearly. Polygon geofences and dialect-specific fence messages are reserved but not enforced in Phase 29.

Fake, fake-PX4, and PX4 SITL examples are simulation fixtures. They are not flight validation and must not be used as real-flight readiness evidence.
