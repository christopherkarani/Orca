# Aegis Edge

Aegis Edge is the drone and robotics safety-policy and audit package for local policy evaluation. Phase 27 implements Edge policy loading, validation, and decision evaluation over fake/simulation/bench inputs.

It does not send commands to MAVLink, PX4, ArduPilot, ROS2, SITL, or real hardware. Aegis Edge is not a flight controller, not an autopilot replacement, not detect-and-avoid, not regulatory approval or certification, and is not ready for real flight. It must not be used for real flight.

The package currently provides:

- Explicit vehicle, command, state, coordinate, geofence, battery, link, sensor, risk, and safety-envelope types.
- Strict Edge policy parsing and validation for policy version `1`.
- A shared-Core decision API for Edge command requests: `allow`, `ask`, `deny`, and `observe`.
- Circular WGS84 geofence checks, altitude/velocity/battery/freshness/mode/authority constraints, and prepared audit events.
- Honest `aegis-edge doctor`, `aegis-edge schema`, and `aegis-edge policy` commands.

## CLI

```bash
aegis-edge policy check examples/edge/policies/geofence-basic.yaml
aegis-edge policy explain examples/edge/policies/geofence-basic.yaml set_waypoint
aegis-edge policy evaluate examples/edge/policies/geofence-basic.yaml --request examples/edge/requests/waypoint-outside-geofence.json --state examples/edge/states/fresh-state.json
```

These commands evaluate policy only. They do not mediate or forward a vehicle command.

## What Does Not Belong Here

- MAVLink gateways.
- PX4 or ArduPilot integration.
- ROS2 control integration.
- Real drone command forwarding or enforcement.
- Flight-controller or autopilot replacement behavior.
- Detect-and-avoid.
- Operator approval runtime flows.
- Emergency runtime behavior beyond policy decisions and recommendations.
- Regulatory approval, certification, or airworthiness claims.
- Real hardware dependencies, external network services, SaaS, telemetry, or monetization.

## Safety Boundary

Unknown, stale, expired, or ambiguous state is not treated as safe. Coordinate frames and altitude references must be explicit. Fake adapter state must remain labeled as fake adapter state. SITL, bench, and customer-adapter provenance values are modeled for later audit/reporting phases, but Phase 27 does not implement real hardware behavior.

See:

- `docs/edge/policy-engine.md`
- `docs/edge/safety-policy.md`
- `docs/edge/geofence-policy.md`
- `docs/edge/command-risk.md`
- `docs/edge/state-freshness.md`
- `docs/edge/battery-policy.md`
- `docs/edge/limitations.md`
