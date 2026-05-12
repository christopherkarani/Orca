# MAVLink Supported Messages

Phase 28 intentionally supports a subset of common MAVLink messages and a safe unknown-message path.

## Parsed And Classified

- `HEARTBEAT`
- `SYS_STATUS`
- `GPS_RAW_INT`
- `GLOBAL_POSITION_INT`
- `LOCAL_POSITION_NED`
- `ATTITUDE`
- `BATTERY_STATUS`
- `COMMAND_LONG`
- `COMMAND_INT`
- `SET_MODE`
- `PARAM_SET` for safety-toggle detection
- `SET_POSITION_TARGET_GLOBAL_INT`
- `SET_POSITION_TARGET_LOCAL_NED`
- `MISSION_COUNT`
- `MISSION_ITEM`
- `MISSION_ITEM_INT`
- `MISSION_REQUEST`
- `MISSION_REQUEST_INT`
- `MISSION_ACK`
- `MISSION_CLEAR_ALL`
- `MISSION_SET_CURRENT`
- `MISSION_CURRENT`
- `COMMAND_ACK`

Known supported messages use fixed common-dialect CRC extra values for checksum validation. Unknown message ids are classified as unknown; their CRC extra is not guessed.

## Command Mapping

Mapped commands include arm/disarm, takeoff, land, return-to-home, waypoint/setpoint, velocity setpoint, mission upload/start/pause/resume, set mode, failsafe/geofence disable-like safety changes, raw actuator/servo output, reboot/component control, and payload-release reserved commands.

Unsupported command ids produce unknown or high-risk behavior and are not treated as safe.

## Geofence And Fence Messages

Generic mission and waypoint messages are evaluated against the Edge geofence/altitude policy when enough coordinate data is available. Dialect-specific fence messages are reserved but not implemented in Phase 28.
