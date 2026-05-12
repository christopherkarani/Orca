const findings_mod = @import("health_findings.zig");
const watchdog = @import("watchdog.zig");

pub const CommandTimeoutStatus = struct {
    command_id: []const u8,
    age_ms: u64,
    timed_out: bool,
    acked: bool = false,
    finding: ?findings_mod.HealthFinding = null,
};

pub fn evaluateCommandTimeout(command_id: []const u8, age_ms: u64, acked: bool, now_ms: i128, provenance: findings_mod.Provenance, policy: watchdog.WatchdogPolicy) CommandTimeoutStatus {
    if (acked or age_ms <= policy.command_timeout_ms) return .{ .command_id = command_id, .age_ms = age_ms, .timed_out = false, .acked = acked };
    return .{
        .command_id = command_id,
        .age_ms = age_ms,
        .timed_out = true,
        .acked = false,
        .finding = findings_mod.HealthFinding.init(.{
            .finding_id = "health-command-timeout",
            .domain = .core,
            .status = .critical,
            .severity = .critical,
            .reason = "command timeout; missing ACK is not success",
            .observed_value = "command age exceeded timeout",
            .threshold = "watchdog.command_timeout_ms",
            .timestamp_ms = now_ms,
            .provenance = provenance,
            .matched_rule = "watchdog.command_timeout_ms",
            .recommended_behavior = .fail_closed,
            .audit_event_reference = "health.command_timeout",
        }),
    };
}
