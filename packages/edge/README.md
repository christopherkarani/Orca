# Aegis Edge

Aegis Edge is the drone and robotics safety-policy and audit package for local policy evaluation. Phase 28 adds a MAVLink gateway foundation for fake/in-memory simulation and protocol mediation. Phase 29 adds PX4 SITL integration for opt-in local simulation evidence and deterministic fake-PX4 scenarios. Phase 30 adds ArduPilot SITL integration for opt-in local simulation evidence and deterministic fake-ArduPilot scenarios. Phase 31 adds reusable flight safety enforcement for fake-adapter, PX4 SITL, and ArduPilot SITL contexts. Phase 32 adds bounded operator approvals and emergency fallback decisions. Phase 33 adds Edge audit/replay, safety-case reports, evidence bundles, traceability, and scenario result classification.

Fake MAVLink remains the default deterministic path. PX4 SITL and ArduPilot SITL are optional and local-only; normal tests do not require PX4 or ArduPilot. Aegis Edge does not support ROS2 control, real hardware integration, or real-flight deployment. Aegis Edge is not a flight controller, not an autopilot replacement, not detect-and-avoid, not regulatory approval or certification, and is not ready for real flight. It must not be used for real flight.

The package currently provides:

- Explicit vehicle, command, state, coordinate, geofence, battery, link, sensor, risk, and safety-envelope types.
- Strict Edge policy parsing and validation for policy version `1`.
- A shared-Core decision API for Edge command requests: `allow`, `ask`, `deny`, and `observe`.
- Reusable `edge.safety` evaluation with structured findings, compiled safety envelopes, mission safety checks, fallback recommendations, and prepared audit events.
- Circular WGS84 geofence checks, altitude/velocity/battery/freshness/mode/authority constraints, and command-risk defaults.
- MAVLink v1/v2 frame parsing, supported-message classification, command mapping, fake gateway decisions, generic mission upload tracking, and MAVLink2 signing presence detection.
- PX4 SITL configuration/status reporting, deterministic fake-PX4 telemetry and command fixtures, policy-mediated PX4 scenarios, and redacted scenario artifacts.
- ArduPilot SITL configuration/status reporting, deterministic fake-ArduPilot telemetry and command fixtures, policy-mediated ArduPilot scenarios, and redacted scenario artifacts.
- Hash-chained Edge sessions under `.aegis-edge` using the Aegis Core audit writer and replay verifier.
- JSON and Markdown safety-case reports, evidence bundles, and traceability matrices for fake/SITL/bench-preparation evidence.
- Honest `aegis-edge doctor`, `aegis-edge schema`, `aegis-edge policy`, `aegis-edge safety`, `aegis-edge safety-case`, `aegis-edge replay`, `aegis-edge mavlink`, `aegis-edge px4`, and `aegis-edge ardupilot` commands.

## CLI

```bash
aegis-edge policy check examples/edge/policies/geofence-basic.yaml
aegis-edge policy explain examples/edge/policies/geofence-basic.yaml set_waypoint
aegis-edge policy evaluate examples/edge/policies/geofence-basic.yaml --request examples/edge/requests/waypoint-outside-geofence.json --state examples/edge/states/fresh-state.json
aegis-edge safety doctor
aegis-edge safety check --policy examples/edge/safety/policies/safety-geofence-basic.yaml
aegis-edge safety evaluate --policy examples/edge/safety/policies/safety-geofence-basic.yaml --request examples/edge/safety/requests/waypoint-outside-geofence.json --state examples/edge/safety/states/fresh-state.json
aegis-edge safety scenario run --policy examples/edge/safety/policies/safety-strict.yaml --scenario examples/edge/safety/scenarios/mission-outside-geofence-deny.yaml
aegis-edge mavlink doctor
aegis-edge mavlink inspect-frame examples/edge/mavlink/frames/command-arm.hex
aegis-edge mavlink classify examples/edge/mavlink/frames/command-takeoff.hex
aegis-edge mavlink simulate --policy examples/edge/mavlink/policies/geofence-mavlink-basic.yaml --scenario examples/edge/mavlink/scenarios/geofence-deny.yaml
aegis-edge px4 doctor
aegis-edge px4 scenario run --policy examples/edge/px4/policies/px4-geofence-basic.yaml --scenario examples/edge/px4/scenarios/waypoint-outside-geofence-deny.yaml
aegis-edge ardupilot doctor
aegis-edge ardupilot scenario run --policy examples/edge/ardupilot/policies/ardupilot-geofence-basic.yaml --scenario examples/edge/ardupilot/scenarios/waypoint-outside-geofence-deny.yaml
aegis-edge safety-case generate --scenario examples/edge/safety/scenarios/geofence-deny.yaml --policy examples/edge/safety/policies/safety-strict.yaml
aegis-edge safety-case show --session last
aegis-edge safety-case verify --session last
aegis-edge safety-case bundle --session last
aegis-edge replay --session last --verify
```

These commands evaluate policy and simulated MAVLink/PX4/ArduPilot records. They do not send a command to a real vehicle or real flight controller. PX4 SITL checks are opt-in and must be labeled `sitl_px4`; fake-PX4 evidence remains labeled `fake_adapter`. ArduPilot SITL checks are opt-in and must be labeled `sitl_ardupilot`; fake-ArduPilot evidence remains labeled `fake_ardupilot_adapter`.

The safety evaluator itself never forwards commands. Gateway and adapter layers call it, then apply observe/enforce/CI forwarding semantics.

## What Does Not Belong Here

- ROS2 control integration.
- Real drone command forwarding or enforcement.
- Real serial or hardware MAVLink endpoints.
- Flight-controller or autopilot replacement behavior.
- Detect-and-avoid.
- Regulatory approval, certification, or airworthiness claims.
- Real hardware dependencies, external network services, SaaS, telemetry, or monetization.

## Safety Boundary

Unknown, stale, expired, or ambiguous state is not treated as safe. Coordinate frames and altitude references must be explicit. Fake adapter state must remain labeled as fake adapter state. MAVLink fake transport provenance is reported as `fake_transport` or `fake_transport/simulation`; fake-PX4 state uses `fake_adapter`; opt-in PX4 SITL state uses `sitl_px4`; fake-ArduPilot state uses `fake_ardupilot_adapter`; opt-in ArduPilot SITL state uses `sitl_ardupilot`. SITL evidence is simulation evidence, not real-flight validation.

## Operator Approval and Emergency Modes

Phase 32 adds bounded local operator approval and policy-controlled emergency fallback decisions. Approval requests bind policy, vehicle, command, state, safety evaluation, safety constraints, provenance, scope, expiry, and use count. Exact-action one-use approval is the default. CI and red-team modes convert ask decisions to deny without prompting.

Emergency evaluation supports policy-controlled LAND, HOLD, and RETURN_TO_HOME decisions in fake/SITL contexts. Emergency mode is not a policy bypass and does not enable disable-failsafe, disable-geofence, raw actuator output, or operator override commands by default.

These features do not make Aegis Edge a flight controller, autopilot replacement, detect-and-avoid capability, regulatory certification, or real-flight validation.

## Audit Replay And Safety Case

Phase 33 records Edge evidence under `.aegis-edge/sessions/<session-id>/`. The authoritative event log is `events.jsonl`, persisted by the Aegis Core audit writer with redaction and hash chaining. Edge replay uses Core verification and keeps fake, PX4 SITL, ArduPilot SITL, bench, and unknown provenance distinct.

Safety-case generation writes `safety-report.json`, `safety-report.md`, `evidence/traceability.*`, findings, commands, approvals, limitations, policy/scenario copies, and a final hash. These artifacts are customer-evaluation engineering reports only. They do not claim real-flight readiness, certification, detect-and-avoid, autopilot replacement behavior, or real hardware approval.

See:

- `docs/edge/policy-engine.md`
- `docs/edge/flight-safety-enforcement.md`
- `docs/edge/safety-envelope.md`
- `docs/edge/geofence-enforcement.md`
- `docs/edge/altitude-velocity-enforcement.md`
- `docs/edge/battery-enforcement.md`
- `docs/edge/mission-safety.md`
- `docs/edge/safety-findings.md`
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
- `docs/edge/ardupilot-sitl.md`
- `docs/edge/ardupilot-scenarios.md`
- `docs/edge/ardupilot-limitations.md`
- `docs/edge/simulation-vs-flight.md`
- `docs/edge/audit-replay.md`
- `docs/edge/safety-case.md`
- `docs/edge/evidence-bundles.md`
- `docs/edge/traceability.md`
- `docs/edge/scenario-results.md`
- `docs/edge/customer-safety-reports.md`
