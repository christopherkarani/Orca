# Aegis Edge Safety Schemas

Phase 26 introduced versioned schema surfaces for Edge policy, audit, replay, and safety report work. Phase 27 uses the Edge policy schema for local policy evaluation. Phase 28 adds MAVLink fake-transport protocol mediation. Phase 29 adds fake-PX4 scenarios and opt-in PX4 SITL simulation evidence. Phase 30 adds fake-ArduPilot scenarios and opt-in ArduPilot SITL simulation evidence. These schemas do not mean ROS2, real hardware integration, regulatory certification, or real-flight readiness exists. Aegis Edge is not ready for real flight and must not be used for real flight.

## Schemas

- `schemas/edge-policy-v1.json`: versioned policy shape for vehicle profile, safety envelope, command policy, network policy, and audit policy.
- `schemas/edge-event-v1.json`: event name surface for future Edge audit events.
- `schemas/safety-report-v1.json`: future customer safety report shape with limitations and non-certification disclaimer fields.

## Edge Policy V1

The policy shape includes:

- `version: 1`
- vehicle kind, autopilot, and adapter
- state freshness policy
- geofence policy
- velocity limits
- battery thresholds
- command allow/ask/deny/operator-approval lists
- network mode
- audit level and redaction flag

Command list duplicates are invalid. Deny priority is documented for future fail-closed resolution, but duplicates should be rejected during policy validation.

## Edge Events V1

Event types cover local policy decisions and fake MAVLink protocol mediation:

- `edge.session_start`
- `edge.session_exit`
- `vehicle.state_observed`
- `vehicle.command_requested`
- `vehicle.command_allowed`
- `vehicle.command_denied`
- `vehicle.command_approval_required`
- `safety.geofence_violation`
- `safety.altitude_violation`
- `safety.velocity_violation`
- `safety.stale_state_denied`
- `safety.battery_constraint`
- `safety.mode_constraint`
- `safety.authority_constraint`
- `emergency.land_allowed`
- `emergency.return_home_allowed`
- `adapter.message_received`
- `adapter.message_forwarded`
- `adapter.message_denied`
- `mavlink.frame_received`
- `mavlink.message_classified`
- `mavlink.command_mapped`
- `mavlink.command_denied`
- `mavlink.message_blocked`

Phase 30 prepares Core audit events for local policy decisions, fake MAVLink gateway decisions, fake-PX4/fake-ArduPilot scenarios, and opt-in PX4/ArduPilot SITL simulation evidence using these names. It still does not emit real-flight events.

## Safety Report V1

Safety reports support report id, version, vehicle profile, adapter profile, policy hash, scenario name/source, test environment, checks run, commands allowed/denied, violations, audit event references, limitations, and a non-certification disclaimer.

Valid test environment labels are fake adapter, PX4 SITL, ArduPilot SITL, bench, and other. PX4 SITL and ArduPilot SITL are opt-in local simulation labels in Phase 30. These labels are not claims of real flight.
