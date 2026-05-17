# Edge Runtime Health

Phase 37 adds local runtime-health checks for fake-adapter, PX4 SITL, ArduPilot SITL, and bench-preparation evidence. It monitors runtime, agent, adapter, MAVLink, telemetry, vehicle state, battery, GPS, link, audit writer, policy engine, safety engine, data guard, storage, resource usage, clock, and configuration domains.

Unknown, unavailable, stale, or critical health is not treated as safe. The watchdog can recommend degraded behavior such as `deny_high_risk`, `deny_movement`, `deny_external_egress`, or `fail_closed`.

This is not real-flight readiness, not an autopilot replacement, not detect-and-avoid, and not regulatory certification.
