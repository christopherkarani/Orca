const fixture = @import("fixture.zig");

pub const faults = [_]fixture.FaultType{ .expired_approval, .mismatched_policy_hash, .mismatched_command_hash, .mismatched_vehicle_id, .mismatched_state_hash, .reused_one_time_approval, .broad_approval_not_allowed, .approval_attempt_for_non_overridable_command };

test {
    _ = faults;
}
