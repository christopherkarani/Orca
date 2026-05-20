const std = @import("std");
const core = @import("orca_core");
const data_classification = @import("data_classification.zig");
const endpoint_policy = @import("endpoint_policy.zig");

pub const FindingCategory = enum {
    data_policy,
    endpoint_policy,
    telemetry_policy,
    exfiltration,
    redaction,
    link_guard,
    payload_classification,
    endpoint_classification,

    pub fn toString(self: FindingCategory) []const u8 {
        return @tagName(self);
    }
};

pub const Severity = enum {
    info,
    low,
    medium,
    high,
    critical,

    pub fn toString(self: Severity) []const u8 {
        return @tagName(self);
    }
};

pub const MatchedRule = struct {
    id: []const u8,
    description: []const u8,
};

pub const NetworkFinding = struct {
    category: FindingCategory,
    severity: Severity,
    reason: []u8,
    endpoint_kind: endpoint_policy.EndpointKind = .unknown,
    data_class: ?data_classification.DataClass = null,
    decision: core.decision.DecisionResult,
    matched_rule: ?[]const u8 = null,
    audit_event_reference: []const u8 = "data.egress_requested",

    pub fn deinit(self: NetworkFinding, allocator: std.mem.Allocator) void {
        allocator.free(self.reason);
    }
};

pub fn appendFinding(
    allocator: std.mem.Allocator,
    findings: *std.ArrayList(NetworkFinding),
    category: FindingCategory,
    severity: Severity,
    decision: core.decision.DecisionResult,
    endpoint_kind: endpoint_policy.EndpointKind,
    data_class: ?data_classification.DataClass,
    audit_event_reference: []const u8,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    try findings.append(allocator, .{
        .category = category,
        .severity = severity,
        .reason = try std.fmt.allocPrint(allocator, fmt, args),
        .endpoint_kind = endpoint_kind,
        .data_class = data_class,
        .decision = decision,
        .audit_event_reference = audit_event_reference,
    });
}
