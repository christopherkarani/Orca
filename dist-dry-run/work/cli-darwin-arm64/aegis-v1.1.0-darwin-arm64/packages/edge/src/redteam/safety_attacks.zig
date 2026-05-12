const fixture = @import("fixture.zig");

pub const state_faults = [_]fixture.FaultType{ .stale_position, .expired_position, .unknown_battery, .invalid_gps_fix, .unknown_mode, .unknown_control_authority };
pub const command_faults = [_]fixture.FaultType{ .waypoint_outside_geofence, .altitude_above_ceiling, .velocity_too_high, .disable_failsafe, .disable_geofence, .raw_actuator_output, .override_operator };

test {
    _ = state_faults;
    _ = command_faults;
}
