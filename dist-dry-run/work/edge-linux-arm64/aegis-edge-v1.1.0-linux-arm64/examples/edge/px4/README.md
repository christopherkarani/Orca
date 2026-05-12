# PX4 SITL Examples

These examples are deterministic Aegis Edge PX4 simulation scenarios. They use `fake_px4` by default so normal tests do not require PX4 SITL.

Run:

```bash
./zig-out/bin/aegis-edge px4 scenario run --policy examples/edge/px4/policies/px4-geofence-basic.yaml --scenario examples/edge/px4/scenarios/waypoint-outside-geofence-deny.yaml
./zig-out/bin/aegis-edge px4 scenario run --policy examples/edge/px4/policies/px4-geofence-basic.yaml --scenario examples/edge/px4/scenarios/land-allow.yaml
./zig-out/bin/aegis-edge px4 scenario run --policy examples/edge/px4/policies/px4-geofence-basic.yaml --scenario examples/edge/px4/scenarios/disable-failsafe-deny.yaml
```

PX4 SITL is opt-in local simulation only. Set `AEGIS_EDGE_RUN_PX4_SITL_TESTS=1` and `AEGIS_EDGE_PX4_ENDPOINT=127.0.0.1:14540` only when a local PX4 SITL instance is intentionally running.

These examples do not connect to real hardware, do not provide real-flight instructions, and do not claim certification or detect-and-avoid capability.
