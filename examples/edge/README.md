# Aegis Edge Examples

These examples are fake/simulation policy-evaluation fixtures only. They do not connect to drones, MAVLink, PX4, ArduPilot, ROS2, SITL, or real hardware.

Run from the repository root:

```bash
./zig-out/bin/aegis-edge policy check examples/edge/policies/geofence-basic.yaml
./zig-out/bin/aegis-edge policy evaluate examples/edge/policies/geofence-basic.yaml --request examples/edge/requests/waypoint-outside-geofence.json --state examples/edge/states/fresh-state.json
```

