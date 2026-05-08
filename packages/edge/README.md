# Aegis Edge

Aegis Edge is the drone and robotics safety-policy and audit package for local policy evaluation. Phase 28 adds a MAVLink gateway foundation for fake/in-memory simulation and protocol mediation. Phase 29 adds PX4 SITL integration for opt-in local simulation evidence and deterministic fake-PX4 scenarios.

Fake MAVLink remains the default deterministic path. PX4 SITL is optional and local-only; normal tests do not require PX4. Aegis Edge does not support ArduPilot SITL, ROS2 control, real hardware integration, or real-flight deployment. Aegis Edge is not a flight controller, not an autopilot replacement, not detect-and-avoid, not regulatory approval or certification, and is not ready for real flight. It must not be used for real flight.

The package currently provides:

- Explicit vehicle, command, state, coordinate, geofence, battery, link, sensor, risk, and safety-envelope types.
- Strict Edge policy parsing and validation for policy version `1`.
- A shared-Core decision API for Edge command requests: `allow`, `ask`, `deny`, and `observe`.
- Circular WGS84 geofence checks, altitude/velocity/battery/freshness/mode/authority constraints, and prepared audit events.
- MAVLink v1/v2 frame parsing, supported-message classification, command mapping, fake gateway decisions, generic mission upload tracking, and MAVLink2 signing presence detection.
- PX4 SITL configuration/status reporting, deterministic fake-PX4 telemetry and command fixtures, policy-mediated PX4 scenarios, and redacted scenario artifacts.
- Honest `aegis-edge doctor`, `aegis-edge schema`, `aegis-edge policy`, `aegis-edge mavlink`, and `aegis-edge px4` commands.

## CLI

```bash
aegis-edge policy check examples/edge/policies/geofence-basic.yaml
aegis-edge policy explain examples/edge/policies/geofence-basic.yaml set_waypoint
aegis-edge policy evaluate examples/edge/policies/geofence-basic.yaml --request examples/edge/requests/waypoint-outside-geofence.json --state examples/edge/states/fresh-state.json
aegis-edge mavlink doctor
aegis-edge mavlink inspect-frame examples/edge/mavlink/frames/command-arm.hex
aegis-edge mavlink classify examples/edge/mavlink/frames/command-takeoff.hex
aegis-edge mavlink simulate --policy examples/edge/mavlink/policies/geofence-mavlink-basic.yaml --scenario examples/edge/mavlink/scenarios/geofence-deny.yaml
aegis-edge px4 doctor
aegis-edge px4 scenario run --policy examples/edge/px4/policies/px4-geofence-basic.yaml --scenario examples/edge/px4/scenarios/waypoint-outside-geofence-deny.yaml
```

These commands evaluate policy and simulated MAVLink/PX4 records. They do not send a command to a real vehicle or real flight controller. PX4 SITL checks are opt-in and must be labeled `sitl_px4`; fake-PX4 evidence remains labeled `fake_adapter`.

## What Does Not Belong Here

- ArduPilot integration.
- ROS2 control integration.
- Real drone command forwarding or enforcement.
- Real serial or hardware MAVLink endpoints.
- ArduPilot SITL.
- Flight-controller or autopilot replacement behavior.
- Detect-and-avoid.
- Operator approval runtime flows.
- Emergency runtime behavior beyond policy decisions and recommendations.
- Regulatory approval, certification, or airworthiness claims.
- Real hardware dependencies, external network services, SaaS, telemetry, or monetization.

## Safety Boundary

Unknown, stale, expired, or ambiguous state is not treated as safe. Coordinate frames and altitude references must be explicit. Fake adapter state must remain labeled as fake adapter state. MAVLink fake transport provenance is reported as `fake_transport` or `fake_transport/simulation`; fake-PX4 state uses `fake_adapter`; opt-in PX4 SITL state uses `sitl_px4`. SITL evidence is simulation evidence, not real-flight validation.

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
- `docs/edge/px4-sitl.md`
- `docs/edge/px4-scenarios.md`
- `docs/edge/px4-limitations.md`
- `docs/edge/simulation-vs-flight.md`
