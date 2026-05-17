# PX4 SITL Integration

Phase 29 adds PX4 SITL support for local simulation evidence. It uses the Phase 28 MAVLink gateway and Phase 27 Edge policy engine to evaluate mapped MAVLink commands before forwarding decisions are recorded.

Default commands use deterministic fake-PX4 fixtures:

```bash
./zig-out/bin/edge px4 doctor
./zig-out/bin/edge px4 scenario run --policy examples/edge/px4/policies/px4-geofence-basic.yaml --scenario examples/edge/px4/scenarios/waypoint-outside-geofence-deny.yaml
```

PX4 SITL checks are opt-in:

```bash
EDGE_BIN_RUN_PX4_SITL_TESTS=1 EDGE_BIN_PX4_ENDPOINT=127.0.0.1:14540 zig build test
```

The tested PX4 version is recorded as `documented-by-phase-29` unless `EDGE_BIN_PX4_TESTED_VERSION` is set for a local run. Normal tests do not require PX4.

Supported configuration fields are host, port, local bind host/port, protocol `udp` or `tcp`, sysid/compid allowlists, timeout, and mode `observe`, `enforce`, `simulation`, `ci`, or `redteam`.

This integration is not real-flight readiness, not a flight controller, not an autopilot replacement, not detect-and-avoid, and not regulatory approval or certification.
