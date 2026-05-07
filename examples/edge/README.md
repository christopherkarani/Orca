# Aegis Edge Examples

These examples are fake/simulation policy-evaluation fixtures only. MAVLink examples are deterministic fake-transport fixtures; they do not connect to drones, PX4, ArduPilot, ROS2, SITL, serial devices, UDP endpoints, or real hardware.

Run from the repository root:

```bash
./zig-out/bin/aegis-edge policy check examples/edge/policies/geofence-basic.yaml
./zig-out/bin/aegis-edge policy evaluate examples/edge/policies/geofence-basic.yaml --request examples/edge/requests/waypoint-outside-geofence.json --state examples/edge/states/fresh-state.json
./zig-out/bin/aegis-edge mavlink simulate --policy examples/edge/mavlink/policies/geofence-mavlink-basic.yaml --scenario examples/edge/mavlink/scenarios/geofence-deny.yaml
```
