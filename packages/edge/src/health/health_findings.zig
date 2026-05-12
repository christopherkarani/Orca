const std = @import("std");

const degraded = @import("degraded_mode.zig");
const status_mod = @import("health_status.zig");
const domain = @import("../domain/mod.zig");

pub const HealthStatus = status_mod.HealthStatus;
pub const HealthDomain = status_mod.HealthDomain;
pub const Severity = status_mod.Severity;
pub const DegradedBehavior = degraded.DegradedBehavior;

pub const Provenance = enum {
    fake_adapter,
    fake_px4,
    fake_ardupilot,
    px4_sitl,
    ardupilot_sitl,
    bench,
    customer_evaluation,
    unknown,

    pub fn toString(self: Provenance) []const u8 {
        return @tagName(self);
    }

    pub fn fromState(value: domain.state.StateProvenance) Provenance {
        return switch (value) {
            .fake_adapter => .fake_adapter,
            .fake_ardupilot_adapter => .fake_ardupilot,
            .sitl_px4 => .px4_sitl,
            .sitl_ardupilot => .ardupilot_sitl,
            .bench => .bench,
            .customer_adapter => .customer_evaluation,
            .unknown => .unknown,
        };
    }
};

pub const HealthFindingInit = struct {
    finding_id: []const u8,
    domain: HealthDomain,
    status: HealthStatus,
    severity: Severity,
    reason: []const u8,
    observed_value: []const u8,
    threshold: []const u8,
    timestamp_ms: i128,
    provenance: Provenance,
    scenario_id: ?[]const u8 = null,
    vehicle_id: ?[]const u8 = null,
    matched_rule: ?[]const u8 = null,
    recommended_behavior: DegradedBehavior = .unknown,
    audit_event_reference: ?[]const u8 = null,
};

pub const HealthFinding = struct {
    finding_id: []const u8,
    domain: HealthDomain,
    status: HealthStatus,
    severity: Severity,
    reason: []const u8,
    observed_value: []const u8,
    threshold: []const u8,
    timestamp_ms: i128,
    provenance: Provenance,
    scenario_id: ?[]const u8 = null,
    vehicle_id: ?[]const u8 = null,
    matched_rule: ?[]const u8 = null,
    recommended_behavior: DegradedBehavior = .unknown,
    audit_event_reference: ?[]const u8 = null,

    pub fn init(args: HealthFindingInit) HealthFinding {
        return .{
            .finding_id = args.finding_id,
            .domain = args.domain,
            .status = args.status,
            .severity = args.severity,
            .reason = args.reason,
            .observed_value = args.observed_value,
            .threshold = args.threshold,
            .timestamp_ms = args.timestamp_ms,
            .provenance = args.provenance,
            .scenario_id = args.scenario_id,
            .vehicle_id = args.vehicle_id,
            .matched_rule = args.matched_rule,
            .recommended_behavior = args.recommended_behavior,
            .audit_event_reference = args.audit_event_reference,
        };
    }

    pub fn eventReference(self: HealthFinding) []const u8 {
        return self.audit_event_reference orelse "health.watchdog.finding";
    }
};

pub fn containsSecretText(finding: HealthFinding, forbidden: []const u8) bool {
    return std.mem.indexOf(u8, finding.reason, forbidden) != null or
        std.mem.indexOf(u8, finding.observed_value, forbidden) != null or
        std.mem.indexOf(u8, finding.threshold, forbidden) != null;
}
