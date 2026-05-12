const findings_mod = @import("health_findings.zig");
const report_mod = @import("health_report.zig");
const status_mod = @import("health_status.zig");

pub const AdapterSnapshot = struct {
    domain: status_mod.HealthDomain = .adapter,
    status: status_mod.HealthStatus = .unknown,
    reason: []const u8 = "adapter health unknown",
    provenance: findings_mod.Provenance = .unknown,
    now_ms: i128,
};

pub fn findingFromSnapshot(snapshot: AdapterSnapshot) findings_mod.HealthFinding {
    return findings_mod.HealthFinding.init(.{
        .finding_id = "health-adapter",
        .domain = snapshot.domain,
        .status = snapshot.status,
        .severity = snapshot.status.defaultSeverity(),
        .reason = snapshot.reason,
        .observed_value = snapshot.status.toString(),
        .threshold = "adapter healthy or explicitly unavailable",
        .timestamp_ms = snapshot.now_ms,
        .provenance = snapshot.provenance,
        .matched_rule = "watchdog.adapter",
        .recommended_behavior = .deny_high_risk,
        .audit_event_reference = "health.watchdog.finding",
    });
}

pub fn reportFromSnapshot(allocator: @import("std").mem.Allocator, snapshot: AdapterSnapshot) !report_mod.HealthReport {
    var builder: report_mod.Builder = .{ .allocator = allocator };
    errdefer builder.deinit();
    if (snapshot.status == .healthy) {
        try builder.addStatus(snapshot.domain, .healthy);
    } else {
        try builder.addFinding(findingFromSnapshot(snapshot));
    }
    return builder.finish("adapter health evaluated for fake/SITL/bench evidence only");
}
