const std = @import("std");

const domain = @import("../domain/mod.zig");
const core = @import("aegis_core");

pub const FindingCategory = enum {
    geofence,
    altitude,
    velocity,
    battery,
    stale_state,
    mode_constraint,
    authority_constraint,
    command_risk,
    mission,
    endpoint,
    unsupported,
    unknown,
};

pub const Severity = enum {
    info,
    warning,
    high,
    critical,
};

pub const Finding = struct {
    finding_id: []u8,
    category: FindingCategory,
    severity: Severity,
    command_id: ?[]u8 = null,
    vehicle_id: ?[]u8 = null,
    constraint_id: ?[]u8 = null,
    observed_value: ?[]u8 = null,
    limit_value: ?[]u8 = null,
    frame_reference_unit: ?[]u8 = null,
    decision: core.decision.DecisionResult,
    explanation: []u8,
    timestamp_ms: i128,
    provenance: []u8,
    audit_event_reference: ?[]u8 = null,

    pub fn deinit(self: Finding, allocator: std.mem.Allocator) void {
        allocator.free(self.finding_id);
        if (self.command_id) |value| allocator.free(value);
        if (self.vehicle_id) |value| allocator.free(value);
        if (self.constraint_id) |value| allocator.free(value);
        if (self.observed_value) |value| allocator.free(value);
        if (self.limit_value) |value| allocator.free(value);
        if (self.frame_reference_unit) |value| allocator.free(value);
        allocator.free(self.explanation);
        allocator.free(self.provenance);
        if (self.audit_event_reference) |value| allocator.free(value);
    }
};

pub const FindingInput = struct {
    category: FindingCategory,
    severity: Severity,
    command_id: ?[]const u8 = null,
    vehicle_id: ?[]const u8 = null,
    constraint_id: ?[]const u8 = null,
    observed_value: ?[]const u8 = null,
    limit_value: ?[]const u8 = null,
    frame_reference_unit: ?[]const u8 = null,
    decision: core.decision.DecisionResult,
    explanation: []const u8,
    timestamp_ms: i128,
    provenance: domain.state.StateProvenance,
    audit_event_reference: ?[]const u8 = null,
};

pub fn initFinding(allocator: std.mem.Allocator, index: usize, input: FindingInput) !Finding {
    return .{
        .finding_id = try std.fmt.allocPrint(allocator, "safety-finding-{d}", .{index}),
        .category = input.category,
        .severity = input.severity,
        .command_id = try dupeOpt(allocator, input.command_id),
        .vehicle_id = try dupeOpt(allocator, input.vehicle_id),
        .constraint_id = try dupeOpt(allocator, input.constraint_id),
        .observed_value = try dupeOpt(allocator, input.observed_value),
        .limit_value = try dupeOpt(allocator, input.limit_value),
        .frame_reference_unit = try dupeOpt(allocator, input.frame_reference_unit),
        .decision = input.decision,
        .explanation = try allocator.dupe(u8, input.explanation),
        .timestamp_ms = input.timestamp_ms,
        .provenance = try allocator.dupe(u8, @tagName(input.provenance)),
        .audit_event_reference = try dupeOpt(allocator, input.audit_event_reference),
    };
}

fn dupeOpt(allocator: std.mem.Allocator, value: ?[]const u8) !?[]u8 {
    if (value) |actual| return try allocator.dupe(u8, actual);
    return null;
}

