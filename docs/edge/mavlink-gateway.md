# MAVLink Gateway

Phase 28 implements the Edge MAVLink gateway foundation for fake/in-memory protocol mediation. Phase 29 reuses this gateway for PX4 SITL simulation scenarios. Phase 30 reuses it for ArduPilot SITL simulation scenarios. It parses MAVLink frames, classifies supported messages, maps supported commands into Edge `CommandRequest` values, evaluates those requests through the Phase 27 policy engine, and records bounded audit events.

This is not real-flight readiness. The gateway does not open serial ports, ROS2 endpoints, or customer hardware. PX4 and ArduPilot SITL use is opt-in local simulation only. The default path is deterministic fake transport for simulation, bench-oriented protocol review, and local tests.

## Gateway Modes

- `observe`: parse, classify, audit, and forward valid messages in fake transport. Denied policy results are logged but not blocked.
- `enforce`: evaluate mapped commands and block denied or approval-required messages because no operator approval runtime exists in Phase 28.
- `ci` / `redteam`: non-interactive. `ask` becomes deny and unknown command sources fail closed.
- `simulation`: fake transport, fake-PX4, or fake-ArduPilot scenarios. Provenance is labeled `fake_transport/simulation` for MAVLink fixtures, `fake_adapter` for fake-PX4 state, or `fake_ardupilot_adapter` for fake-ArduPilot state.
- `bench`: reserved for later non-flight bench work. It is not a real hardware procedure.
- `disabled`: no forwarding.

## Endpoint Policy

Gateway policy can check source and target `sysid` / `compid`. Unexpected endpoints emit `mavlink.unexpected_endpoint`. Strict CI-style modes fail closed for unexpected command sources.

Audit context includes source sysid, source compid, target sysid, target compid, direction, message id, and command id when available.

## Policy Integration

Supported MAVLink commands are mapped into Edge command actions such as `arm`, `takeoff`, `land`, `return_to_home`, `set_waypoint`, `set_velocity`, `upload_mission`, `start_mission`, `set_mode`, `disable_failsafe`, `disable_geofence`, `raw_actuator_output`, `payload_release`, `firmware_update`, and `companion_computer_reboot`.

Unknown command ids are not treated as safe. Critical commands default to deny unless an explicit policy and safety envelope allow them. `LAND` and `RETURN_TO_HOME` are still audited and policy evaluated.

## Audit Events

MAVLink gateway events are represented with Core event names including:

- `mavlink.frame_received`
- `mavlink.frame_invalid`
- `mavlink.message_classified`
- `mavlink.command_mapped`
- `mavlink.command_allowed`
- `mavlink.command_denied`
- `mavlink.command_observed`
- `mavlink.message_forwarded`
- `mavlink.message_blocked`
- `mavlink.mission_upload_started`
- `mavlink.mission_item_observed`
- `mavlink.mission_item_denied`
- `mavlink.mission_upload_completed`
- `mavlink.signing_detected`
- `mavlink.unexpected_endpoint`
- `safety.geofence_violation`
- `safety.altitude_violation`

Payload previews are bounded and pass through Core redaction before persistent audit writing.
