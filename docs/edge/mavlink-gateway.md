# MAVLink Gateway

Phase 28 implements the Aegis Edge MAVLink gateway foundation for fake/in-memory protocol mediation. It parses MAVLink frames, classifies supported messages, maps supported commands into Edge `CommandRequest` values, evaluates those requests through the Phase 27 policy engine, and records bounded audit events.

This is not real-flight readiness. The gateway does not open serial ports, UDP sockets, PX4 SITL, ArduPilot SITL, ROS2 endpoints, or customer hardware. It is for deterministic simulation, bench-oriented protocol review, and local tests.

## Gateway Modes

- `observe`: parse, classify, audit, and forward valid messages in fake transport. Denied policy results are logged but not blocked.
- `enforce`: evaluate mapped commands and block denied or approval-required messages because no operator approval runtime exists in Phase 28.
- `ci` / `redteam`: non-interactive. `ask` becomes deny and unknown command sources fail closed.
- `simulation`: reserved for fake transport scenarios. Provenance is labeled `fake_transport/simulation`.
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
