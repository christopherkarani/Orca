# ArduPilot SITL Examples

These examples are deterministic Aegis Edge ArduPilot simulation scenarios. They use `fake_ardupilot` by default so normal tests do not require ArduPilot SITL.

Run:

```bash
./zig-out/bin/aegis-edge ardupilot scenario run --policy examples/edge/ardupilot/policies/ardupilot-geofence-basic.yaml --scenario examples/edge/ardupilot/scenarios/waypoint-outside-geofence-deny.yaml
./zig-out/bin/aegis-edge ardupilot scenario run --policy examples/edge/ardupilot/policies/ardupilot-geofence-basic.yaml --scenario examples/edge/ardupilot/scenarios/land-allow.yaml
./zig-out/bin/aegis-edge ardupilot scenario run --policy examples/edge/ardupilot/policies/ardupilot-geofence-basic.yaml --scenario examples/edge/ardupilot/scenarios/rtl-allow.yaml
./zig-out/bin/aegis-edge ardupilot scenario run --policy examples/edge/ardupilot/policies/ardupilot-geofence-basic.yaml --scenario examples/edge/ardupilot/scenarios/disable-failsafe-deny.yaml
```

ArduPilot SITL is opt-in local simulation only. Set `AEGIS_EDGE_RUN_ARDUPILOT_SITL_TESTS=1`, `AEGIS_EDGE_ARDUPILOT_ENDPOINT=127.0.0.1:14550`, and `AEGIS_EDGE_ARDUPILOT_VEHICLE=copter` only when a local ArduPilot SITL instance is intentionally running.

Fake-ArduPilot evidence uses `fake_ardupilot` environment and `fake_ardupilot_adapter` provenance. ArduPilot SITL evidence must use `ardupilot_sitl` environment and `sitl_ardupilot` provenance. A fake pass is not SITL success.

These examples do not connect to real hardware, do not provide real-flight instructions, and do not claim certification or detect-and-avoid capability.
