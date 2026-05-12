# Aegis Edge

Aegis Edge is the drone and robotics safety-policy and audit package for local policy evaluation. Phase 28 adds a MAVLink gateway foundation for fake/in-memory simulation and protocol mediation. Phase 29 adds PX4 SITL integration for opt-in local simulation evidence and deterministic fake-PX4 scenarios. Phase 30 adds ArduPilot SITL integration for opt-in local simulation evidence and deterministic fake-ArduPilot scenarios. Phase 31 adds reusable flight safety enforcement for fake-adapter, PX4 SITL, and ArduPilot SITL contexts. Phase 32 adds bounded operator approvals and emergency fallback decisions. Phase 33 adds Edge audit/replay, safety-case reports, evidence bundles, traceability, and scenario result classification. Phase 34 adds deterministic red-team and fault-injection evidence for fake-adapter and optional SITL contexts. Phase 35 adds the data guard for telemetry/data classification, endpoint classification, simulated egress policy, redaction, exfiltration findings, and data/network evidence. Phase 36 adds deployment diagnostics, Linux ARM64 package metadata, runtime asset verification, deployment profiles, smoke scripts, and explicit no-actuation bench-readiness reports.

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
- Deterministic Edge red-team fixtures, simulation-only fault injection, scorecards, JSON output, and red-team safety-case evidence.
- Reusable data guard evaluation for payload classification, telemetry channel policy, endpoint policy, link classification, redaction/minimization, audit events, red-team fixtures, and safety-case reports.
- Deployment profiles, runtime asset diagnostics, package manifests, Linux amd64/arm64 artifact naming, disabled-by-default service examples, and non-privileged container examples.
- Honest `aegis-edge doctor`, `aegis-edge deployment`, `aegis-edge bench`, `aegis-edge schema`, `aegis-edge policy`, `aegis-edge safety`, `aegis-edge safety-case`, `aegis-edge replay`, `aegis-edge mavlink`, `aegis-edge px4`, `aegis-edge ardupilot`, `aegis-edge data`, and `aegis-edge network` commands.

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
aegis-edge redteam validate
aegis-edge redteam --ci
aegis-edge redteam --json
aegis-edge redteam --category geofence
aegis-edge redteam --category data-guard
aegis-edge redteam --report safety-case
aegis-edge data doctor
aegis-edge data classify --payload examples/edge/data-guard/payloads/mission-plan.json
aegis-edge data evaluate --policy examples/edge/data-guard/policies/data-guard-strict.yaml --payload examples/edge/data-guard/payloads/mission-plan.json --endpoint examples/edge/data-guard/endpoints/webhook-site.json
aegis-edge data redact --payload examples/edge/data-guard/payloads/fake-secret-payload.json
aegis-edge data scenario run --policy examples/edge/data-guard/policies/data-guard-strict.yaml --scenario examples/edge/data-guard/scenarios/mission-plan-to-webhook-deny.yaml
aegis-edge network explain --policy examples/edge/data-guard/policies/data-guard-strict.yaml --endpoint examples/edge/data-guard/endpoints/unknown-direct-ip.json
aegis-edge deployment doctor
aegis-edge deployment assets
aegis-edge deployment check --profile examples/edge/deployment/profiles/source-local-fake.yaml
aegis-edge deployment package-info --arch linux-arm64
aegis-edge bench doctor
aegis-edge bench check --policy examples/edge/safety/policies/safety-strict.yaml
aegis-edge bench report --policy examples/edge/safety/policies/safety-strict.yaml --scenario examples/edge/safety/scenarios/geofence-deny.yaml
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

## Red-Team And Fault Injection

Phase 34 red-team fixtures live under `examples/edge/redteam`. Required
fake/simulation fixtures run by default and PX4/ArduPilot SITL fixtures are
optional. The runner classifies results as `passed`, `failed`, `skipped`,
`unsupported`, or `inconclusive`; skipped, unsupported, and inconclusive are not
counted as pass.

Red-team fault injection is simulation-only. It exercises synthetic geofence,
altitude, velocity, battery, state freshness, mission, MAVLink parser, MAVLink
command, endpoint spoofing, approval bypass, emergency bypass, audit redaction,
and safety-case scenarios without real hardware or external network dependency.

Phase 35 adds data guard red-team fixtures for mission-data egress denial,
exact geolocation redaction/denial, fake-secret redaction/denial, video/image
egress denial, direct-IP/webhook/tunnel/paste endpoint denial, long-query and
high-entropy endpoint findings, explicit customer safety-report allow, and
explicit local ground-control telemetry allow.

## Audit Replay And Safety Case

Phase 33 records Edge evidence under `.aegis-edge/sessions/<session-id>/`. The authoritative event log is `events.jsonl`, persisted by the Aegis Core audit writer with redaction and hash chaining. Edge replay uses Core verification and keeps fake, PX4 SITL, ArduPilot SITL, bench, and unknown provenance distinct.

Safety-case generation writes `safety-report.json`, `safety-report.md`, `evidence/traceability.*`, findings, commands, approvals, limitations, policy/scenario copies, and a final hash. These artifacts are customer-evaluation engineering reports only. They do not claim real-flight readiness, certification, detect-and-avoid, autopilot replacement behavior, or real hardware approval.

Phase 35 safety-case output also writes `evidence/data-network-guard.json` and a Data/Network Guard section summarizing data classes, endpoints observed, allowed/denied endpoint decisions, redactions, exfiltration findings, and telemetry guard limitations. Sensitive payloads and endpoint query values are redacted before persistence.

## Deployment And Bench

Phase 36 deployment checks verify that the `aegis-edge` binary can find required schemas, policies, examples, fixtures, red-team fixtures, safety-case templates, and runtime docs from source or packaged layouts.

Linux package metadata uses:

- `aegis-edge-vX.Y.Z-linux-amd64.tar.gz`
- `aegis-edge-vX.Y.Z-linux-arm64.tar.gz`

Bench mode is explicitly `hardware_bench_no_actuation`. It requires an explicit policy, reports bench provenance separately from fake/PX4 SITL/ArduPilot SITL, and never claims real-flight readiness. The docs and templates intentionally avoid flight instructions, real aircraft operation steps, motor/propeller actuation procedures, autonomous flight procedures, real hardware service auto-enable, credentials, telemetry, detect-and-avoid claims, autopilot replacement claims, and regulatory/certification claims.

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
- `docs/edge/redteam.md`
- `docs/edge/data-guard.md`
- `docs/edge/telemetry-policy.md`
- `docs/edge/network-egress.md`
- `docs/edge/data-classification.md`
- `docs/edge/exfiltration-detection.md`
- `docs/edge/sensitive-data-redaction.md`
- `docs/edge/fault-injection.md`
- `docs/edge/redteam-fixtures.md`
- `docs/edge/redteam-scorecards.md`
- `docs/edge/sitl-redteam.md`
- `docs/edge/deployment.md`
- `docs/edge/arm64.md`
- `docs/edge/packaging.md`
- `docs/edge/runtime-assets.md`
- `docs/edge/hardware-bench.md`
- `docs/edge/bench-safety-boundary.md`
- `docs/edge/container.md`
- `docs/edge/release-artifacts.md`
## Phase 37 Runtime Health

Aegis Edge includes a local reliability watchdog and runtime-health layer for fake-adapter, PX4 SITL, ArduPilot SITL, and bench-preparation evidence. It monitors heartbeats, telemetry freshness, audit writer health, policy/safety engine health, data guard status, adapter/link status, and lightweight resource limits.

Unknown or stale health is not safe. Degraded modes can deny high-risk commands, deny movement, deny external egress, or fail closed. Emergency behavior remains policy-controlled and does not bypass the safety envelope.

This is not real-flight readiness, not an autopilot replacement, not detect-and-avoid, and not regulatory certification.
