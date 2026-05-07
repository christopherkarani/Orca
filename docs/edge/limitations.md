# Edge Limitations

Aegis Edge Phase 28 implements policy evaluation and a MAVLink gateway foundation for fake/in-memory protocol mediation. It is not command forwarding to a real flight controller.

Not implemented:

- PX4 integration.
- ArduPilot integration.
- ROS2 integration.
- PX4 SITL or ArduPilot SITL control.
- Real serial or UDP MAVLink endpoints.
- Real hardware integration.
- Real-flight deployment.
- Customer hardware bench procedure.
- Operator approval runtime.
- Emergency runtime behavior beyond policy decisions and fallback recommendations.
- MAVLink signing key management or signing verification.
- SaaS, monetization, telemetry, certification, or regulatory claims.

Coordinate frames and altitude references must be explicit. Unsupported geospatial conversions fail clearly. Polygon geofences and dialect-specific fence messages are reserved but not enforced in Phase 28.

Fake and simulation examples are deterministic policy/protocol fixtures. They are not flight validation and must not be used as real-flight readiness evidence.
