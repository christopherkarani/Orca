const std = @import("std");

const domain = @import("../domain/mod.zig");
const findings_mod = @import("health_findings.zig");
const report_mod = @import("health_report.zig");
const status_mod = @import("health_status.zig");
const watchdog = @import("watchdog.zig");

pub const Options = struct {
    now_ms: i128,
    scenario_id: ?[]const u8 = null,
};

pub fn evaluateTelemetryFreshness(
    allocator: std.mem.Allocator,
    policy: watchdog.WatchdogPolicy,
    state: domain.state.VehicleState,
    options: Options,
) !report_mod.HealthReport {
    var builder: report_mod.Builder = .{ .allocator = allocator };
    errdefer builder.deinit();
    const provenance = findings_mod.Provenance.fromState(state.provenance);
    const state_age = ageMs(state.timestamp.value, options.now_ms);
    if (state_age > policy.telemetry.vehicle_state_max_age_ms or state.state_freshness != .fresh) {
        try builder.addFinding(finding(.vehicle_state, .degraded, "vehicle state stale", state_age, policy.telemetry.vehicle_state_max_age_ms, options.now_ms, provenance, options.scenario_id, state.vehicle_id.value, .deny_movement));
    }
    if (state.position == null) {
        try builder.addFinding(plainFinding(.telemetry, .critical, "position missing", "missing", "position required", options.now_ms, provenance, options.scenario_id, state.vehicle_id.value, .deny_movement));
    } else if (state_age > policy.telemetry.position_max_age_ms) {
        try builder.addFinding(finding(.telemetry, .degraded, "position stale", state_age, policy.telemetry.position_max_age_ms, options.now_ms, provenance, options.scenario_id, state.vehicle_id.value, .deny_movement));
    }
    if (state.battery_state == null) {
        try builder.addFinding(plainFinding(.battery_state, .unavailable, "battery state missing", "missing", "battery required for high-risk commands", options.now_ms, provenance, options.scenario_id, state.vehicle_id.value, .deny_high_risk));
    } else if (state_age > policy.telemetry.battery_max_age_ms) {
        try builder.addFinding(finding(.battery_state, .degraded, "battery state stale", state_age, policy.telemetry.battery_max_age_ms, options.now_ms, provenance, options.scenario_id, state.vehicle_id.value, .deny_high_risk));
    }
    if (state.gps_state == null) {
        try builder.addFinding(plainFinding(.gps_state, .degraded, "gps state missing", "missing", "gps required for movement context", options.now_ms, provenance, options.scenario_id, state.vehicle_id.value, .deny_movement));
    } else if (state_age > policy.telemetry.gps_max_age_ms) {
        try builder.addFinding(finding(.gps_state, .degraded, "gps state stale", state_age, policy.telemetry.gps_max_age_ms, options.now_ms, provenance, options.scenario_id, state.vehicle_id.value, .deny_movement));
    }
    if (state.link_state == null) {
        try builder.addFinding(plainFinding(.link_state, .unavailable, "link state missing", "missing", "link heartbeat required", options.now_ms, provenance, options.scenario_id, state.vehicle_id.value, .deny_high_risk));
    } else if (state_age > policy.telemetry.link_max_age_ms) {
        try builder.addFinding(finding(.link_state, .degraded, "link state stale", state_age, policy.telemetry.link_max_age_ms, options.now_ms, provenance, options.scenario_id, state.vehicle_id.value, .deny_high_risk));
    }
    if (state.home_position == null) {
        try builder.addFinding(plainFinding(.vehicle_state, .degraded, "home position missing", "missing", "RTH requires valid home position", options.now_ms, provenance, options.scenario_id, state.vehicle_id.value, .deny_movement));
    }
    if (builder.findings.items.len == 0) {
        try builder.addStatus(.telemetry, .healthy);
    }
    return builder.finish("telemetry freshness evaluated; stale or missing telemetry is not treated as safe");
}

fn finding(domain_name: status_mod.HealthDomain, status: status_mod.HealthStatus, reason: []const u8, observed_age: u64, threshold: u64, now_ms: i128, provenance: findings_mod.Provenance, scenario_id: ?[]const u8, vehicle_id: []const u8, behavior: @import("degraded_mode.zig").DegradedBehavior) findings_mod.HealthFinding {
    _ = observed_age;
    _ = threshold;
    return findings_mod.HealthFinding.init(.{
        .finding_id = "health-telemetry-freshness",
        .domain = domain_name,
        .status = status,
        .severity = status.defaultSeverity(),
        .reason = reason,
        .observed_value = "age_ms exceeded configured telemetry threshold",
        .threshold = "watchdog telemetry max age",
        .timestamp_ms = now_ms,
        .provenance = provenance,
        .scenario_id = scenario_id,
        .vehicle_id = vehicle_id,
        .matched_rule = "watchdog.telemetry.max_age_ms",
        .recommended_behavior = behavior,
        .audit_event_reference = "health.watchdog.finding",
    });
}

fn plainFinding(domain_name: status_mod.HealthDomain, status: status_mod.HealthStatus, reason: []const u8, observed: []const u8, threshold: []const u8, now_ms: i128, provenance: findings_mod.Provenance, scenario_id: ?[]const u8, vehicle_id: []const u8, behavior: @import("degraded_mode.zig").DegradedBehavior) findings_mod.HealthFinding {
    return findings_mod.HealthFinding.init(.{
        .finding_id = "health-telemetry-missing",
        .domain = domain_name,
        .status = status,
        .severity = status.defaultSeverity(),
        .reason = reason,
        .observed_value = observed,
        .threshold = threshold,
        .timestamp_ms = now_ms,
        .provenance = provenance,
        .scenario_id = scenario_id,
        .vehicle_id = vehicle_id,
        .matched_rule = "watchdog.telemetry.required",
        .recommended_behavior = behavior,
        .audit_event_reference = "health.watchdog.finding",
    });
}

fn ageMs(timestamp_ms: i128, now_ms: i128) u64 {
    if (now_ms <= timestamp_ms) return 0;
    return @intCast(now_ms - timestamp_ms);
}
