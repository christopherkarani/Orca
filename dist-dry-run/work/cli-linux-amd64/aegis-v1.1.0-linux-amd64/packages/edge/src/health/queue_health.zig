const std = @import("std");

const findings_mod = @import("health_findings.zig");
const report_mod = @import("health_report.zig");
const watchdog = @import("watchdog.zig");

pub const CommandLifecycle = enum {
    requested,
    evaluated,
    forwarded,
    blocked,
    observed,
    timed_out,
    acked,
    missing_ack,
};

pub const CommandQueueSample = struct {
    pending_count: u64 = 0,
    queue_depth: u64 = 0,
    oldest_pending_age_ms: u64 = 0,
    overflowed: bool = false,
    dropped: bool = false,
    now_ms: i128,
    provenance: findings_mod.Provenance = .unknown,
};

pub fn evaluateCommandQueue(
    allocator: std.mem.Allocator,
    sample: CommandQueueSample,
    policy: watchdog.WatchdogPolicy,
) !report_mod.HealthReport {
    var builder: report_mod.Builder = .{ .allocator = allocator };
    errdefer builder.deinit();
    if (sample.queue_depth > policy.max_command_queue_depth or sample.overflowed) {
        try builder.addFinding(findQueueOverflow(sample));
    }
    if (sample.oldest_pending_age_ms > policy.command_timeout_ms) {
        try builder.addFinding(findTimeout(sample));
    }
    if (builder.findings.items.len == 0) try builder.addStatus(.core, .healthy);
    return builder.finish("command queue health evaluated with bounded queue and no unbounded retry loop");
}

fn findQueueOverflow(sample: CommandQueueSample) findings_mod.HealthFinding {
    return findings_mod.HealthFinding.init(.{
        .finding_id = "health-command-queue-overflow",
        .domain = .core,
        .status = .critical,
        .severity = .critical,
        .reason = "command queue overflow",
        .observed_value = "queue_depth exceeded max_command_queue_depth",
        .threshold = "watchdog.max_command_queue_depth",
        .timestamp_ms = sample.now_ms,
        .provenance = sample.provenance,
        .matched_rule = "watchdog.max_command_queue_depth",
        .recommended_behavior = .fail_closed,
        .audit_event_reference = "health.command_queue_overflow",
    });
}

fn findTimeout(sample: CommandQueueSample) findings_mod.HealthFinding {
    return findings_mod.HealthFinding.init(.{
        .finding_id = "health-command-timeout",
        .domain = .core,
        .status = .critical,
        .severity = .critical,
        .reason = "command timed out and is not treated as successful",
        .observed_value = "oldest_pending_age_ms exceeded command_timeout_ms",
        .threshold = "watchdog.command_timeout_ms",
        .timestamp_ms = sample.now_ms,
        .provenance = sample.provenance,
        .matched_rule = "watchdog.command_timeout_ms",
        .recommended_behavior = .fail_closed,
        .audit_event_reference = "health.command_timeout",
    });
}
