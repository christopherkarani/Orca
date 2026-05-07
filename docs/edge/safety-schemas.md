# Aegis Edge Safety Schemas

Phase 26 introduces versioned schema surfaces for later Edge policy, audit, replay, and safety report work. These schemas are documentation and validation contracts only. They do not mean MAVLink, PX4, ArduPilot, ROS2, command mediation, real hardware integration, regulatory certification, or real-flight readiness exists. Aegis Edge is not ready for real flight and must not be used for real flight.

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

Event types are reserved for future audit/replay phases:

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
- `emergency.land_allowed`
- `emergency.return_home_allowed`
- `adapter.message_received`
- `adapter.message_forwarded`
- `adapter.message_denied`

Phase 26 defines names only. It does not emit these events as active command mediation.

## Safety Report V1

Safety reports support report id, version, vehicle profile, adapter profile, policy hash, scenario name/source, test environment, checks run, commands allowed/denied, violations, audit event references, limitations, and a non-certification disclaimer.

Valid test environment labels are fake adapter, PX4 SITL, ArduPilot SITL, bench, and other. These labels support future reporting distinctions; they are not claims that Phase 26 runs SITL or real flight.
