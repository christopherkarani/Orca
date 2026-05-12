# Edge Limitations

Aegis Edge through Phase 40 supports local policy evaluation, fake/in-memory MAVLink mediation, deterministic fake-PX4 and fake-ArduPilot scenarios, opt-in PX4/ArduPilot SITL simulation checks, safety enforcement, operator approval, emergency fallback evaluation, audit/replay, safety-case reports, red-team fixtures, data guard, runtime health/watchdog checks, deployment diagnostics, and no-actuation bench-preparation evidence.

It is not command forwarding to a real flight controller and is not ready for real flight.

Not implemented:

- ROS2 integration.
- Real serial, radio, or hardware MAVLink endpoints.
- Real hardware integration.
- Real-flight deployment.
- Live aircraft control.
- Flight instructions or autonomous operation procedures.
- Detect-and-avoid.
- Autopilot replacement behavior.
- Regulatory approval, airworthiness approval, certification, or BVLOS authorization.
- Hosted telemetry service.
- SaaS, billing, license enforcement, or customer acquisition workflows.
- Complete MAVLink dialect and command coverage.
- MAVLink signing key management or signing verification.

Coordinate frames and altitude references must be explicit. Unsupported geospatial conversions fail clearly. Polygon geofences and dialect-specific fence messages are reserved but not enforced in Phase 40.

Fake, fake-PX4, fake-ArduPilot, PX4 SITL, ArduPilot SITL, and bench-preparation examples are evaluation fixtures. They are not flight validation and must not be used as real-flight readiness evidence.
