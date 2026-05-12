const domain = @import("../domain/mod.zig");
const findings_mod = @import("health_findings.zig");
const watchdog = @import("watchdog.zig");

pub const FallbackAction = enum {
    land,
    hold,
    return_to_home,
    stop_or_brake,
    no_safe_fallback,
};

pub const Recommendation = struct {
    action: FallbackAction,
    reason: []const u8,
    required_conditions: []const u8,
    conditions_satisfied: bool,
    policy_rule: []const u8,
    health_cause: []const u8,
    limitations: []const u8 = "recommendation only; no emergency command is executed",
};

pub fn recommend(policy: watchdog.WatchdogPolicy, state: domain.state.VehicleState, finding: findings_mod.HealthFinding) Recommendation {
    for (policy.recommended_fallback_order[0..policy.recommended_fallback_order_len]) |command| {
        switch (command) {
            .land => return .{
                .action = .land,
                .reason = "LAND is first in watchdog fallback order and remains policy-gated",
                .required_conditions = "safety policy permits LAND for current state",
                .conditions_satisfied = true,
                .policy_rule = "watchdog.recommended_fallback_order.land",
                .health_cause = finding.finding_id,
            },
            .return_to_home => if (state.home_position != null) return .{
                .action = .return_to_home,
                .reason = "home position is available and RTH remains policy-gated",
                .required_conditions = "valid home position and safety policy allow RTH",
                .conditions_satisfied = true,
                .policy_rule = "watchdog.recommended_fallback_order.return_to_home",
                .health_cause = finding.finding_id,
            },
            .hold_position => if (state.position != null and state.control_authority != .unknown) return .{
                .action = .hold,
                .reason = "position/control context is available for policy-gated HOLD",
                .required_conditions = "valid position and control context",
                .conditions_satisfied = true,
                .policy_rule = "watchdog.recommended_fallback_order.hold_position",
                .health_cause = finding.finding_id,
            },
            else => {},
        }
    }
    return .{
        .action = .no_safe_fallback,
        .reason = "no safe fallback context is available",
        .required_conditions = "home position or sufficient hold/land context",
        .conditions_satisfied = false,
        .policy_rule = "deny beats allow",
        .health_cause = finding.finding_id,
    };
}
