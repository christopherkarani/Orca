const std = @import("std");

const mavlink_framing = @import("../mavlink/framing.zig");
const mavlink_dialect = @import("../mavlink/dialect.zig");
const findings_mod = @import("health_findings.zig");
const report_mod = @import("health_report.zig");
const status_mod = @import("health_status.zig");
const watchdog = @import("watchdog.zig");

pub const HealthStatus = status_mod.HealthStatus;
pub const HealthDomain = status_mod.HealthDomain;
pub const HealthFinding = findings_mod.HealthFinding;
pub const Provenance = findings_mod.Provenance;
pub const DegradedBehavior = @import("degraded_mode.zig").DegradedBehavior;

pub const HeartbeatSource = enum {
    runtime,
    agent,
    adapter,
    mavlink,
    px4_sitl,
    ardupilot_sitl,
    audit_writer,
    safety_engine,

    pub fn domain(self: HeartbeatSource) HealthDomain {
        return switch (self) {
            .runtime => .runtime,
            .agent => .agent,
            .adapter => .adapter,
            .mavlink => .mavlink,
            .px4_sitl => .px4_sitl,
            .ardupilot_sitl => .ardupilot_sitl,
            .audit_writer => .audit_writer,
            .safety_engine => .safety_engine,
        };
    }
};

pub const TimestampSource = enum {
    wall_clock,
    monotonic,
    mavlink,
    fake,
    unknown,
};

pub const Heartbeat = struct {
    source: HeartbeatSource,
    source_id: []const u8,
    timestamp_ms: i128,
    timestamp_source: TimestampSource,
    sequence: ?u64 = null,
    provenance: Provenance,
};

pub const HeartbeatStatus = struct {
    source: HeartbeatSource,
    source_id: []const u8,
    last_seen_ms: ?i128,
    age_ms: ?u64,
    status: HealthStatus,
    provenance: Provenance,
    finding: ?HealthFinding = null,
};

pub fn evaluateHeartbeat(
    heartbeat: Heartbeat,
    domain: HealthDomain,
    policy: watchdog.WatchdogPolicy,
    now_ms: i128,
) !HeartbeatStatus {
    const age = ageMs(heartbeat.timestamp_ms, now_ms);
    const threshold = policy.heartbeatMaxAge(domain);
    if (age <= threshold) {
        return .{
            .source = heartbeat.source,
            .source_id = heartbeat.source_id,
            .last_seen_ms = heartbeat.timestamp_ms,
            .age_ms = age,
            .status = .healthy,
            .provenance = heartbeat.provenance,
        };
    }
    const expired = age >= threshold * 2;
    const status: HealthStatus = if (expired) .critical else .degraded;
    return .{
        .source = heartbeat.source,
        .source_id = heartbeat.source_id,
        .last_seen_ms = heartbeat.timestamp_ms,
        .age_ms = age,
        .status = status,
        .provenance = heartbeat.provenance,
        .finding = HealthFinding.init(.{
            .finding_id = if (expired) "health-heartbeat-expired" else "health-heartbeat-stale",
            .domain = domain,
            .status = status,
            .severity = status.defaultSeverity(),
            .reason = if (expired) "heartbeat expired" else "heartbeat stale",
            .observed_value = "age_ms exceeded configured heartbeat threshold",
            .threshold = "watchdog heartbeat max age",
            .timestamp_ms = now_ms,
            .provenance = heartbeat.provenance,
            .matched_rule = "watchdog.heartbeat.max_age_ms",
            .recommended_behavior = behaviorForDomain(policy, domain),
            .audit_event_reference = "health.watchdog.finding",
        }),
    };
}

pub fn evaluateMissingHeartbeat(
    source: HeartbeatSource,
    policy: watchdog.WatchdogPolicy,
    now_ms: i128,
    provenance: Provenance,
) !HeartbeatStatus {
    const domain = source.domain();
    return .{
        .source = source,
        .source_id = "missing",
        .last_seen_ms = null,
        .age_ms = null,
        .status = .unavailable,
        .provenance = provenance,
        .finding = HealthFinding.init(.{
            .finding_id = "health-heartbeat-missing",
            .domain = domain,
            .status = .unavailable,
            .severity = .high,
            .reason = "heartbeat missing",
            .observed_value = "missing",
            .threshold = "watchdog heartbeat required",
            .timestamp_ms = now_ms,
            .provenance = provenance,
            .matched_rule = "watchdog.heartbeat.required",
            .recommended_behavior = behaviorForDomain(policy, domain),
            .audit_event_reference = "health.watchdog.finding",
        }),
    };
}

pub fn reportFromHeartbeats(
    allocator: std.mem.Allocator,
    statuses: []const HeartbeatStatus,
) !report_mod.HealthReport {
    var builder: report_mod.Builder = .{ .allocator = allocator };
    errdefer builder.deinit();
    for (statuses) |status| {
        try builder.addStatus(status.source.domain(), status.status);
        if (status.finding) |finding| try builder.addFinding(finding);
    }
    return builder.finish("heartbeat health evaluated for fake/SITL/bench evidence only");
}

pub fn heartbeatFromMavlinkFrame(frame: mavlink_framing.Frame, timestamp_ms: i128, provenance: Provenance) !Heartbeat {
    if (frame.msgid != mavlink_dialect.HEARTBEAT) return error.NotHeartbeat;
    return .{
        .source = .mavlink,
        .source_id = "mavlink-heartbeat",
        .timestamp_ms = timestamp_ms,
        .timestamp_source = .mavlink,
        .sequence = frame.sequence,
        .provenance = provenance,
    };
}

fn ageMs(timestamp_ms: i128, now_ms: i128) u64 {
    if (now_ms <= timestamp_ms) return 0;
    return @intCast(now_ms - timestamp_ms);
}

fn behaviorForDomain(policy: watchdog.WatchdogPolicy, domain: HealthDomain) DegradedBehavior {
    return switch (domain) {
        .agent => policy.degraded_mode.on_agent_stale,
        .adapter, .mavlink, .px4_sitl, .ardupilot_sitl, .link_state => policy.degraded_mode.on_adapter_stale,
        .telemetry, .vehicle_state, .battery_state, .gps_state => policy.degraded_mode.on_telemetry_stale,
        .audit_writer => policy.degraded_mode.on_audit_failure,
        .policy_engine, .safety_engine => policy.degraded_mode.on_policy_error,
        .data_guard => policy.degraded_mode.on_data_guard_failure,
        else => .deny_high_risk,
    };
}
