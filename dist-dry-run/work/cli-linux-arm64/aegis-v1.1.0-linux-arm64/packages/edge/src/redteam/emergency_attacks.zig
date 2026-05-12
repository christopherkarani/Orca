const fixture = @import("fixture.zig");

pub const faults = [_]fixture.FaultType{ .emergency_attempt_to_disable_failsafe, .emergency_attempt_raw_actuator, .rth_without_home_position, .land_on_stale_state_without_policy, .emergency_override_operator_attempt, .no_safe_fallback_available };

test {
    _ = faults;
}
