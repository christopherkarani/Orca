const std = @import("std");

const findings_mod = @import("health_findings.zig");
const report_mod = @import("health_report.zig");
const watchdog = @import("watchdog.zig");

pub const AuditHealthInput = struct {
    writer_available: bool = true,
    append_failed: bool = false,
    hash_chain_verified: bool = true,
    append_latency_ms: u64 = 0,
    provenance: findings_mod.Provenance = .unknown,
    now_ms: i128,
};

pub fn evaluateAuditHealth(
    allocator: std.mem.Allocator,
    input: AuditHealthInput,
    policy: watchdog.WatchdogPolicy,
) !report_mod.HealthReport {
    var builder: report_mod.Builder = .{ .allocator = allocator };
    errdefer builder.deinit();
    if (policy.audit.require_audit_writer and !input.writer_available) {
        try builder.addFinding(finding(.unavailable, "audit writer unavailable", "unavailable", "required", input, policy));
    }
    if (input.append_failed) {
        try builder.addFinding(finding(.critical, "audit append failed", "append_failed=true", "append succeeds", input, policy));
    }
    if (!input.hash_chain_verified) {
        try builder.addFinding(finding(.critical, "audit hash-chain verification failed", "hash_chain_verified=false", "hash_chain_verified=true", input, policy));
    }
    if (input.append_latency_ms > policy.audit.max_event_append_latency_ms) {
        try builder.addFinding(finding(.degraded, "audit append latency exceeded", "latency_ms exceeded policy", "watchdog audit max append latency", input, policy));
    }
    if (builder.findings.items.len == 0) try builder.addStatus(.audit_writer, .healthy);
    return builder.finish("audit writer health evaluated; strict/CI modes fail closed when required audit persistence is broken");
}

fn finding(status: @import("health_status.zig").HealthStatus, reason: []const u8, observed: []const u8, threshold: []const u8, input: AuditHealthInput, policy: watchdog.WatchdogPolicy) findings_mod.HealthFinding {
    _ = policy;
    return findings_mod.HealthFinding.init(.{
        .finding_id = "health-audit-writer",
        .domain = .audit_writer,
        .status = status,
        .severity = status.defaultSeverity(),
        .reason = reason,
        .observed_value = observed,
        .threshold = threshold,
        .timestamp_ms = input.now_ms,
        .provenance = input.provenance,
        .matched_rule = "watchdog.audit",
        .recommended_behavior = .fail_closed,
        .audit_event_reference = "health.audit.failure",
    });
}
