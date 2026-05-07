# Edge Limitations

Aegis Edge Phase 27 implements policy evaluation, not command mediation.

Not implemented:

- MAVLink gateway.
- PX4 integration.
- ArduPilot integration.
- ROS2 integration.
- SITL control.
- Real hardware integration.
- Command forwarding to a flight controller.
- Flight execution.
- Operator approval runtime.
- Emergency runtime behavior beyond policy decisions and fallback recommendations.
- SaaS, monetization, telemetry, certification, or regulatory claims.

Coordinate frames and altitude references must be explicit. Unsupported geospatial conversions fail clearly. Polygon geofences are schema-reserved but not enforced.

Fake and simulation examples are deterministic policy fixtures. They are not flight validation and must not be used as real-flight readiness evidence.
