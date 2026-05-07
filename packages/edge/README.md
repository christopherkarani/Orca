# Aegis Edge

Aegis Edge is the drone and robotics safety-policy and audit package for local policy evaluation. Phase 28 adds a MAVLink gateway foundation for fake/in-memory simulation and protocol mediation.

It does not open real serial, UDP, PX4, ArduPilot, ROS2, SITL, or hardware endpoints. Aegis Edge is not a flight controller, not an autopilot replacement, not detect-and-avoid, not regulatory approval or certification, and is not ready for real flight. It must not be used for real flight.

The package currently provides:

- Explicit vehicle, command, state, coordinate, geofence, battery, link, sensor, risk, and safety-envelope types.
- Strict Edge policy parsing and validation for policy version `1`.
- A shared-Core decision API for Edge command requests: `allow`, `ask`, `deny`, and `observe`.
- Circular WGS84 geofence checks, altitude/velocity/battery/freshness/mode/authority constraints, and prepared audit events.
- MAVLink v1/v2 frame parsing, supported-message classification, command mapping, fake gateway decisions, generic mission upload tracking, and MAVLink2 signing presence detection.
- Honest `aegis-edge doctor`, `aegis-edge schema`, `aegis-edge policy`, and `aegis-edge mavlink` commands.

## CLI

```bash
aegis-edge policy check examples/edge/policies/geofence-basic.yaml
aegis-edge policy explain examples/edge/policies/geofence-basic.yaml set_waypoint
aegis-edge policy evaluate examples/edge/policies/geofence-basic.yaml --request examples/edge/requests/waypoint-outside-geofence.json --state examples/edge/states/fresh-state.json
aegis-edge mavlink doctor
aegis-edge mavlink inspect-frame examples/edge/mavlink/frames/command-arm.hex
aegis-edge mavlink classify examples/edge/mavlink/frames/command-takeoff.hex
aegis-edge mavlink simulate --policy examples/edge/mavlink/policies/geofence-mavlink-basic.yaml --scenario examples/edge/mavlink/scenarios/geofence-deny.yaml
```

These commands evaluate policy and fake MAVLink frames only. They do not open real endpoints or send a command to a real vehicle, simulator, or flight controller.

## What Does Not Belong Here

- PX4 or ArduPilot integration.
- ROS2 control integration.
- Real drone command forwarding or enforcement.
- Real serial or UDP MAVLink endpoints.
- PX4 SITL or ArduPilot SITL.
- Flight-controller or autopilot replacement behavior.
- Detect-and-avoid.
- Operator approval runtime flows.
- Emergency runtime behavior beyond policy decisions and recommendations.
- Regulatory approval, certification, or airworthiness claims.
- Real hardware dependencies, external network services, SaaS, telemetry, or monetization.

## Safety Boundary

Unknown, stale, expired, or ambiguous state is not treated as safe. Coordinate frames and altitude references must be explicit. Fake adapter state must remain labeled as fake adapter state. MAVLink fake transport provenance is reported as `fake_transport` or `fake_transport/simulation`. SITL, bench, and customer-adapter provenance values are modeled for later audit/reporting phases, but Phase 28 does not implement real hardware behavior.

See:

- `docs/edge/policy-engine.md`
- `docs/edge/safety-policy.md`
- `docs/edge/geofence-policy.md`
- `docs/edge/command-risk.md`
- `docs/edge/state-freshness.md`
- `docs/edge/battery-policy.md`
- `docs/edge/limitations.md`
- `docs/edge/mavlink-gateway.md`
- `docs/edge/mavlink-supported-messages.md`
- `docs/edge/mavlink-limitations.md`
- `docs/edge/mavlink-simulation.md`
