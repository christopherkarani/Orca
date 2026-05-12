# Heartbeat Monitoring

Phase 37 heartbeats record source, source id, timestamp, timestamp source, optional sequence, provenance, last-seen age, status, and a health finding when stale, expired, missing, or unavailable.

Fake heartbeats remain labeled `fake_adapter`. PX4 SITL heartbeats remain labeled `px4_sitl`. ArduPilot SITL heartbeats remain labeled `ardupilot_sitl`. Missing heartbeat state is not treated as healthy.

Heartbeat monitoring is not real-flight readiness, not an autopilot replacement, not detect-and-avoid, and not regulatory certification.
