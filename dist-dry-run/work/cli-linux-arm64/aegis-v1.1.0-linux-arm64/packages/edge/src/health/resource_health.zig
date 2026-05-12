const std = @import("std");

const findings_mod = @import("health_findings.zig");
const report_mod = @import("health_report.zig");
const watchdog = @import("watchdog.zig");

pub const ResourceSample = struct {
    memory_mb: u64 = 0,
    cpu_percent: u8 = 0,
    event_queue_depth: u64 = 0,
    scenario_timeout_exceeded: bool = false,
    command_timeout_exceeded: bool = false,
    adapter_timeout_exceeded: bool = false,
    now_ms: i128,
    provenance: findings_mod.Provenance = .unknown,
};

pub fn evaluateResourceHealth(
    allocator: std.mem.Allocator,
    sample: ResourceSample,
    policy: watchdog.WatchdogPolicy,
) !report_mod.HealthReport {
    var builder: report_mod.Builder = .{ .allocator = allocator };
    errdefer builder.deinit();
    if (sample.memory_mb > policy.resource.max_memory_mb) {
        try builder.addFinding(finding("memory limit exceeded", "memory_mb exceeded policy", "watchdog resource max memory", sample));
    }
    if (sample.cpu_percent > policy.resource.max_cpu_percent) {
        try builder.addFinding(finding("cpu limit exceeded", "cpu_percent exceeded policy", "watchdog resource max cpu", sample));
    }
    if (sample.event_queue_depth > policy.resource.max_event_queue_depth) {
        try builder.addFinding(finding("event queue depth exceeded", "event_queue_depth exceeded policy", "watchdog resource max event queue depth", sample));
    }
    if (sample.scenario_timeout_exceeded) try builder.addFinding(finding("scenario timeout exceeded", "scenario_timeout=true", "scenario_timeout=false", sample));
    if (sample.command_timeout_exceeded) try builder.addFinding(finding("command processing timeout exceeded", "command_timeout=true", "command_timeout=false", sample));
    if (sample.adapter_timeout_exceeded) try builder.addFinding(finding("adapter timeout exceeded", "adapter_timeout=true", "adapter_timeout=false", sample));
    if (builder.findings.items.len == 0) try builder.addStatus(.resource_usage, .healthy);
    return builder.finish("lightweight resource health evaluated without hosted telemetry or external network");
}

fn finding(reason: []const u8, observed: []const u8, threshold: []const u8, sample: ResourceSample) findings_mod.HealthFinding {
    return findings_mod.HealthFinding.init(.{
        .finding_id = "health-resource-usage",
        .domain = .resource_usage,
        .status = .degraded,
        .severity = .warning,
        .reason = reason,
        .observed_value = observed,
        .threshold = threshold,
        .timestamp_ms = sample.now_ms,
        .provenance = sample.provenance,
        .matched_rule = "watchdog.resource",
        .recommended_behavior = .deny_high_risk,
        .audit_event_reference = "health.watchdog.finding",
    });
}
