# Aegis Edge Examples

These examples are simulation policy-evaluation fixtures only. MAVLink examples are deterministic fake-transport fixtures. PX4 examples use deterministic fake-PX4 by default and can document opt-in local PX4 SITL checks. ArduPilot examples use deterministic fake-ArduPilot by default and can document opt-in local ArduPilot SITL checks. They do not connect to drones, ROS2, serial hardware, or real hardware.

Run from the repository root:

```bash
./zig-out/bin/aegis-edge policy check examples/edge/policies/geofence-basic.yaml
./zig-out/bin/aegis-edge policy evaluate examples/edge/policies/geofence-basic.yaml --request examples/edge/requests/waypoint-outside-geofence.json --state examples/edge/states/fresh-state.json
./zig-out/bin/aegis-edge mavlink simulate --policy examples/edge/mavlink/policies/geofence-mavlink-basic.yaml --scenario examples/edge/mavlink/scenarios/geofence-deny.yaml
./zig-out/bin/aegis-edge px4 scenario run --policy examples/edge/px4/policies/px4-geofence-basic.yaml --scenario examples/edge/px4/scenarios/waypoint-outside-geofence-deny.yaml
./zig-out/bin/aegis-edge ardupilot scenario run --policy examples/edge/ardupilot/policies/ardupilot-geofence-basic.yaml --scenario examples/edge/ardupilot/scenarios/waypoint-outside-geofence-deny.yaml
```

PX4 and ArduPilot SITL scenarios are simulation evidence only and must not be treated as real-flight readiness.
