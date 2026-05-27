# ArduPilot SITL Integration

Phase 30 adds ArduPilot SITL support for local simulation evidence. It uses the Phase 28 MAVLink gateway and Phase 27 Edge policy engine to evaluate mapped MAVLink commands before forwarding decisions are recorded.

Default commands use deterministic fake-ArduPilot fixtures:

```bash
./zig-out/bin/edge ardupilot doctor
./zig-out/bin/edge ardupilot scenario run --policy examples/edge/ardupilot/policies/ardupilot-geofence-basic.yaml --scenario examples/edge/ardupilot/scenarios/waypoint-outside-geofence-deny.yaml
```

ArduPilot SITL checks are opt-in:

```bash
EDGE_BIN_RUN_ARDUPILOT_SITL_TESTS=1 EDGE_BIN_ARDUPILOT_ENDPOINT=127.0.0.1:14550 EDGE_BIN_ARDUPILOT_VEHICLE=copter zig build test
```

The tested ArduPilot version is recorded as `documented-by-phase-30` unless `EDGE_BIN_ARDUPILOT_TESTED_VERSION` is set for a local run. Normal tests do not require ArduPilot.

Supported configuration fields are host, port, local bind host/port, protocol `udp` or `tcp`, sysid/compid allowlists, timeout, vehicle type `copter`, `plane`, `rover`, `sub`, or `unknown`, and mode `observe`, `enforce`, `simulation`, `ci`, or `redteam`.

Phase 30 starts with Copter-oriented scenarios. Plane, Rover, and Sub labels are parsed and reported, but their mode coverage is limited and unknown modes remain unknown.

This integration is not real-flight readiness, not a flight controller, not an autopilot replacement, not detect-and-avoid, and not regulatory approval or certification.
