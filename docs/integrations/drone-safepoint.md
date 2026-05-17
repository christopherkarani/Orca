# Orca Drone Plugin Safepoint — P00

> Generated: 2026-05-09  
> Branch: `phase-35-edge-network-telemetry-data-guard`  
> Commit: `5b271b9` (Phase 35 committed)  
> Version: 1.1.0

---

## 1. Detected Drone-Related Files / Modules

Drone functionality is concentrated in the **Edge** product (`packages/edge/`). The main CLI (`orca`) has **no drone commands or subcommands**.

### 1.1 Edge Source Code (`packages/edge/src/`)

| Family | Files | Description |
|--------|-------|-------------|
| **CLI / Facade** | `main.zig`, `root.zig` | `edge` binary entrypoint and public API exports. All drone-specific commands live here. |
| **Domain Model** | `domain/{vehicle,commands,state,mission,geofence,safety_envelope,risk,validation,coordinates,battery,link,sensors}.zig` | Vehicle kinds, command actions, mission plans, geofence/altitude/battery constraints, risk classification. |
| **MAVLink Protocol** | `mavlink/{parser,framing,classifier,mapping,commands,messages,gateway,mission,signing,fake_transport,dialect,crc,audit}.zig` | MAVLink v1/v2 frame parsing, command mapping, fake transport, gateway mediation, signing detection. |
| **PX4 Adapter** | `px4/{connection,health,fake_adapter,sitl_adapter,telemetry_mapping,command_mapping,scenario,audit}.zig` | Fake-PX4 scenarios + opt-in PX4 SITL configuration/health. |
| **ArduPilot Adapter** | `ardupilot/{connection,health,fake_adapter,sitl_adapter,telemetry_mapping,command_mapping,vehicle_kind,scenario,audit}.zig` | Fake-ArduPilot scenarios + opt-in ArduPilot SITL. |
| **Flight Safety** | `safety/{evaluator,mission_safety,geofence,altitude,velocity,battery,freshness,mode_authority,command_limits,findings,report,scenario,envelope}.zig` | Safety envelope evaluation: geofence, altitude, velocity, battery, freshness, authority checks. |
| **Operator Approval** | `operator/{approval_scope,approval_request,approval_decision,approval_validation,approval_token,approval_store,approval_audit,approval_prompt,approval_seed}.zig` | Bounded operator approval system for drone commands. |
| **Emergency Fallback** | `emergency/mod.zig` | Policy-controlled LAND / HOLD / RTH decisions. |
| **Data / Network Guard** | `data_guard/{data_classification,telemetry_policy,endpoint_policy,egress_evaluator,payload_redaction,mission_data_guard,sensor_data_guard,link_guard,network_finding,network_audit}.zig` | Telemetry/data egress policy, payload classification, endpoint classification, redaction. |
| **Audit / Replay** | `audit/{edge_event,edge_replay,edge_session,edge_hash_chain,edge_summary,safety_case,safety_report,evidence_bundle,traceability,edge_artifacts}.zig` | Hash-chained Edge sessions, safety-case reports, evidence bundles, replay verification. |
| **Redteam / Fault Injection** | `redteam/{fixture,runner,report,scorecard,fault_injection,mission_attacks,mavlink_attacks,safety_attacks,approval_attacks,emergency_attacks}.zig` | Deterministic simulation-only red-team and fault-injection fixtures. |
| **Policy / Schema** | `policy/{load,evaluate}.zig`, `schema/{edge_event_schema,edge_policy_schema,safety_report_schema}.zig` | Edge policy parsing/evaluation and versioned schema contracts. |

### 1.2 Drone-Related Tests

| Test File | Phase | Coverage |
|-----------|-------|----------|
| `tests/phase26_edge_domain.zig` | 26 | Edge domain model |
| `tests/phase27_edge_policy_engine.zig` | 27 | Edge policy engine |
| `tests/phase28_mavlink_gateway.zig` | 28 | MAVLink parser, classifier, gateway |
| `tests/phase29_px4_sitl.zig` | 29 | PX4 fake adapter + opt-in SITL |
| `tests/phase30_ardupilot_sitl.zig` | 30 | ArduPilot fake adapter + opt-in SITL |
| `tests/phase31_flight_safety_enforcement.zig` | 31 | Flight safety enforcement |
| `tests/phase32_operator_emergency.zig` | 32 | Operator approvals + emergency fallback |
| `tests/phase33_edge_audit_replay_safety_case.zig` | 33 | Audit, replay, safety-case |
| `tests/phase34_edge_redteam_fault_injection.zig` | 34 | Red-team / fault injection |
| `tests/phase35_edge_data_guard.zig` | 35 | Data / network guard |
| `packages/edge/tests/contract.zig` | — | Edge package API contract |

All Edge source files also contain **inline behavioral tests**.

### 1.3 Drone-Related Docs

Located in `docs/edge/` (40+ documents). Key categories:

- **Safety enforcement**: `flight-safety-enforcement.md`, `geofence-enforcement.md`, `altitude-velocity-enforcement.md`, `battery-enforcement.md`, `mission-safety.md`, `state-freshness.md`, `command-risk.md`
- **Policy / limits**: `safety-policy.md`, `geofence-policy.md`, `battery-policy.md`, `telemetry-policy.md`, `limitations.md`
- **MAVLink**: `mavlink-gateway.md`, `mavlink-simulation.md`, `mavlink-supported-messages.md`, `mavlink-limitations.md`
- **SITL**: `px4-sitl.md`, `px4-scenarios.md`, `px4-limitations.md`, `ardupilot-sitl.md`, `ardupilot-scenarios.md`, `ardupilot-limitations.md`, `sitl-redteam.md`
- **Audit / evidence**: `audit-replay.md`, `safety-case.md`, `evidence-bundles.md`, `traceability.md`, `scenario-results.md`, `customer-safety-reports.md`
- **Redteam**: `redteam.md`, `redteam-fixtures.md`, `redteam-scorecards.md`, `fault-injection.md`
- **Data guard**: `data-guard.md`, `data-classification.md`, `exfiltration-detection.md`, `sensitive-data-redaction.md`, `network-egress.md`
- **Operator / emergency**: `operator-approval.md`, `approval-scopes.md`, `emergency-modes.md`, `emergency-fallbacks.md`
- **Boundary**: `simulation-vs-flight.md`, `safety-envelope.md`, `safety-findings.md`

Also referenced in:
- `README.md` (top-level product split section)
- `packages/edge/README.md` (Edge product overview)

### 1.4 Drone-Related Configs / Examples

Located in `examples/edge/`:

- `policies/` — Edge policy YAML examples
- `requests/`, `states/` — JSON request/state fixtures
- `safety/{policies,requests,scenarios,states}/` — Safety envelope examples
- `mavlink/{frames,policies,scenarios}/` — MAVLink frame hex + policy examples
- `px4/{policies,scenarios}/` — PX4 scenario examples
- `ardupilot/{policies,scenarios}/` — ArduPilot scenario examples
- `operator/{policies,requests,approvals,scenarios,states}/` — Operator approval examples
- `data-guard/{payloads,endpoints,policies,scenarios}/` — Data guard examples
- `redteam/` — 50+ red-team fixture directories across geofence, altitude, battery, velocity, stale-state, mission, MAVLink, command-risk, approval-bypass, emergency-bypass, PX4 SITL, ArduPilot SITL, data-guard, audit-redaction

Versioned schemas in `schemas/`:
- `edge-policy-v1.json`
- `edge-event-v1.json`
- `safety-report-v1.json`

---

## 2. Safety-Sensitive Command / Operation Categories

The following categories are **critical risk** by default in any plugin context:

| Category | Risk Level | Why |
|----------|------------|-----|
| **Real drone command forwarding** | Critical | Could cause physical harm or property damage |
| **Actuator / motor control** | Critical | Direct hardware actuation |
| **Arming / disarming** | Critical | Enables/disables propulsion |
| **Takeoff / landing** | Critical | Physical flight state change |
| **Waypoint / mission upload** | High | Could redirect vehicle to unsafe location |
| **Geofence disable** | Critical | Removes spatial safety boundary |
| **Failsafe disable** | Critical | Removes automatic safety fallback |
| **Raw actuator output** | Critical | Bypasses flight-controller safety |
| **Operator override** | High | Could bypass policy decisions |
| **Telemetry exfiltration** | High | May leak location, mission, or secrets |
| **Live MAVLink endpoint** | High | Opens real hardware communication path |
| **SITL opt-in without explicit env** | Medium-High | Must be explicitly gated by environment variables |

---

## 3. Plugin Restrictions

### 3.1 Simulation-Only Demo Rule

**All plugin demos involving drone behavior must use deterministic fake adapters or clearly labeled simulation fixtures.**

- Fake MAVLink transport (`fake_transport`) is the default.
- Fake-PX4 (`fake_adapter`) and fake-ArduPilot (`fake_ardupilot_adapter`) are the default PX4/ArduPilot paths.
- PX4 SITL (`sitl_px4`) and ArduPilot SITL (`sitl_ardupilot`) are **opt-in only** and require explicit environment variables.
- No plugin demo may claim real-flight readiness, certification, detect-and-avoid, or autopilot replacement.

### 3.2 Live Drone Actuation / Control Patterns

**Live drone actuation or control patterns are critical risk by default.**

- Plugins must not expose tools that send commands to real vehicles.
- Plugins must not open real serial, UDP, or TCP MAVLink endpoints without explicit human opt-in.
- Plugins must not bypass the safety evaluator or approval system.
- Any live-control behavior requires explicit policy and human approval **outside** the plugin default path.

### 3.3 Ambiguous Drone Commands

**Ambiguous or unknown drone commands fail closed in strict / CI mode.**

- If a plugin encounters a command it cannot classify, the default must be `deny` in strict/ci modes.
- The `ask` mode may prompt, but CI mode converts `ask` to `deny` without prompting.

### 3.4 Plugin Default Path

- Plugins must **not** expose live drone actuation tools by default.
- Plugins must **not** auto-approve drone-related high-risk operations.
- Plugins must **not** print drone credentials, telemetry secrets, or connection strings.
- Plugins must **not** weaken existing drone safety tests, policies, or guardrails.

### 3.5 Test Preservation

- All existing drone tests must continue to pass.
- No plugin work may delete, skip, or weaken Edge red-team fixtures.
- No plugin work may change the default `fail-closed` behavior of the safety evaluator.

---

## 4. Tests That Must Keep Passing

| Test Suite | Last Known Result | Note |
|------------|-------------------|------|
| `zig build test` | Pass | All inline + package + phase tests |
| `tests/phase26_edge_domain.zig` | Pass | Domain model |
| `tests/phase27_edge_policy_engine.zig` | Pass | Edge policy |
| `tests/phase28_mavlink_gateway.zig` | Pass | MAVLink gateway |
| `tests/phase29_px4_sitl.zig` | Pass | PX4 (SITL skipped unless env set) |
| `tests/phase30_ardupilot_sitl.zig` | Pass | ArduPilot (SITL skipped unless env set) |
| `tests/phase31_flight_safety_enforcement.zig` | Pass | Flight safety |
| `tests/phase32_operator_emergency.zig` | Pass | Operator + emergency |
| `tests/phase33_edge_audit_replay_safety_case.zig` | Pass | Audit / replay / safety-case |
| `tests/phase34_edge_redteam_fault_injection.zig` | Pass | Red-team / fault injection |
| `tests/phase35_edge_data_guard.zig` | Pass | Data / network guard |
| `packages/edge/tests/contract.zig` | Pass | Edge package contract |
| `edge redteam --ci` | **58/58 required passed** | 5 PX4 SITL + 6 ArduPilot SITL skipped (expected) |

**SITL tests are skipped by design** unless `EDGE_BIN_RUN_PX4_SITL_TESTS` or `EDGE_BIN_RUN_ARDUPILOT_SITL_TESTS` are set. This is the intended safe default.

---

## 5. Known Unknowns

| Unknown | Impact | Mitigation |
|---------|--------|------------|
| Contents of `aegis_plugin_launch_plan_v2.zip` | Could contain plugin designs that conflict with safety model | Do not unpack/auto-apply without review |
| Future real-hardware adapter plans | Could introduce live-control paths | Must go through explicit safety review before any real-hardware support |
| ROS2 integration mentions in docs | Out of scope per README, but could resurface | Reject any plugin work targeting ROS2 control |
| Plugin manifest schema | Not yet designed | Must include drone-safety flags before any drone-related plugin is accepted |
| Cross-product plugin loading (CLI loading Edge plugins) | Could accidentally expose drone tools in desktop CLI | Must enforce product boundaries in plugin registry |

---

*End of P00 drone safepoint. No plugin implementation has started. No drone functionality has been weakened.*
