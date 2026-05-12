# MAVLink Simulation

MAVLink examples are deterministic and local-only.

```bash
aegis-edge mavlink doctor
aegis-edge mavlink inspect-frame examples/edge/mavlink/frames/command-arm.hex
aegis-edge mavlink classify examples/edge/mavlink/frames/command-takeoff.hex
aegis-edge mavlink simulate --policy examples/edge/mavlink/policies/geofence-mavlink-basic.yaml --scenario examples/edge/mavlink/scenarios/geofence-deny.yaml
aegis-edge mavlink simulate --policy examples/edge/mavlink/policies/geofence-mavlink-basic.yaml --scenario examples/edge/mavlink/scenarios/disable-failsafe-deny.yaml
```

The simulator uses fake frame generation and in-memory gateway evaluation. It does not open a network socket, serial device, SITL process, ROS2 graph, or flight controller connection.

Scenario files in `examples/edge/mavlink/scenarios/` are labels for deterministic built-in fake frames. Frame files in `examples/edge/mavlink/frames/` are hex-encoded MAVLink frames for parser and classifier checks.

Expected examples:

- `geofence-deny.yaml`: outside-geofence global setpoint is denied and blocked.
- `land-allow.yaml`: land is allowed and logged according to policy.
- `disable-failsafe-deny.yaml`: disable-failsafe-like `PARAM_SET` is denied and blocked.
- `mission-outside-geofence-deny.yaml`: mission waypoint outside geofence is denied or flagged.

Audit output should identify fake provenance as `fake_transport` or `fake_transport/simulation`.
