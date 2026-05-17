# Edge Capability Matrix

| Capability | supported | partial | opt-in | unavailable | unsupported | notes | evidence/demo link |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Edge policy evaluation | yes | no | no | no | no | Local policy decisions for Edge commands. | `examples/edge/demos/01-geofence-deny/` |
| MAVLink parsing | yes | no | no | no | no | Bounded MAVLink v1/v2 frame parsing. | `docs/edge/mavlink-supported-messages.md` |
| MAVLink command mapping | no | yes | no | no | no | Supported subset only. | `examples/edge/mavlink/` |
| Mission safety checks | yes | no | no | no | no | Mission items checked against envelope where modeled. | `examples/edge/demos/05-mission-outside-geofence/` |
| Circular geofence | yes | no | no | no | no | Supported in safety policy. | `examples/edge/demos/01-geofence-deny/` |
| Polygon geofence | no | yes | no | no | no | Not full customer-ready coverage. | `examples/edge/redteam/geofence/unsupported-polygon/` |
| Altitude limits | yes | no | no | no | no | Floor and ceiling checks. | `docs/edge/altitude-velocity-enforcement.md` |
| Velocity limits | yes | no | no | no | no | Horizontal and vertical velocity checks. | `examples/edge/redteam/velocity/` |
| Battery constraints | yes | no | no | no | no | Takeoff, RTH, and LAND thresholds. | `docs/edge/battery-enforcement.md` |
| State freshness | yes | no | no | no | no | Stale state can deny movement. | `examples/edge/demos/04-stale-telemetry-deny/` |
| Operator approval | yes | no | no | no | no | Scoped local approvals, CI never prompts. | `examples/edge/demos/06-approval-expired-deny/` |
| Emergency LAND | yes | no | no | no | no | Policy-controlled, no real command is sent by demos. | `examples/edge/demos/03-emergency-land/` |
| Emergency RTH | yes | no | no | no | no | Policy and home-position gated. | `docs/edge/emergency-modes.md` |
| Emergency HOLD | yes | no | no | no | no | Policy controlled. | `docs/edge/emergency-fallbacks.md` |
| Data guard | yes | no | no | no | no | Local data/endpoint classification and redaction. | `examples/edge/demos/07-data-exfil-deny/` |
| Runtime health/watchdog | yes | no | no | no | no | Heartbeat, freshness, audit, queue, timeout checks. | `examples/edge/demos/08-health-watchdog-degraded/` |
| Audit/replay | yes | no | no | no | no | Hash-chained local sessions. | `examples/edge/customer-proof/audit-replay-example.md` |
| Safety-case reports | yes | no | no | no | no | Customer-evaluation evidence only. | `examples/edge/customer-proof/geofence-deny-safety-report.md` |
| Edge red-team | yes | no | no | no | no | Required fake/simulation fixtures plus optional SITL fixtures. | `docs/edge/customer-proof/redteam-summary.md` |
| PX4 fake adapter | yes | no | no | no | no | Deterministic fake-PX4, labeled separately. | `examples/edge/demos/09-px4-fake-sitl-proof/` |
| PX4 SITL opt-in | no | yes | yes | no | no | Local simulator evidence only. | `docs/edge/px4-sitl.md` |
| ArduPilot fake adapter | yes | no | no | no | no | Deterministic fake-ArduPilot, labeled separately. | `examples/edge/demos/10-ardupilot-fake-sitl-proof/` |
| ArduPilot SITL opt-in | no | yes | yes | no | no | Local simulator evidence only. | `docs/edge/ardupilot-sitl.md` |
| ARM64 packaging | yes | no | no | no | no | Linux arm64 package metadata and scripts. | `docs/edge/arm64.md` |
| Bench no-actuation profile | yes | no | no | no | no | Explicit no-actuation bench-preparation boundary. | `docs/edge/hardware-bench.md` |
| Real-flight support | no | no | no | no | yes | Explicitly unsupported in Phase 38. | `docs/edge/customer-proof/what-edge-does-not-prove.md` |
| Certification support | no | no | no | no | yes | No certification or regulatory approval claim. | `docs/edge/customer-proof/what-edge-does-not-prove.md` |
| Detect-and-avoid | no | no | no | no | yes | Not a detect-and-avoid system. | `docs/edge/customer-proof/what-edge-does-not-prove.md` |
| Autopilot replacement | no | no | no | no | yes | PX4/ArduPilot remain the autopilot. | `docs/edge/customer-proof/buyer-faq.md` |
