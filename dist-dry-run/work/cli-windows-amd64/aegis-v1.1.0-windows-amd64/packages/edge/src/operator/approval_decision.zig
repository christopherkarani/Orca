const std = @import("std");

const domain = @import("../domain/mod.zig");
const scope_mod = @import("approval_scope.zig");
const request_mod = @import("approval_request.zig");
const token = @import("approval_token.zig");

pub const OperatorDecision = enum {
    approved,
    denied,
    expired,
    revoked,
    invalid,
};

pub const ApprovalDecision = struct {
    approval_decision_id: []u8,
    approval_request_id: []u8,
    operator_id: []u8,
    decision: OperatorDecision,
    approved_scope: scope_mod.ApprovalScope,
    expires_at_ms: i128,
    operator_note: ?[]u8 = null,
    timestamp_ms: i128,
    audit_event_reference: []u8,
    vehicle_id: []u8,
    command_type: domain.commands.CommandAction,
    command_request_hash: []u8,
    policy_hash: []u8,
    state_snapshot_hash: []u8,
    safety_evaluation_hash: []u8,
    safety_constraints_hash: []u8,
    environment: request_mod.ApprovalEnvironment,
    used_count: u32 = 0,

    pub fn approve(allocator: std.mem.Allocator, request: request_mod.ApprovalRequest, args: anytype) !ApprovalDecision {
        return initFromRequest(allocator, request, .approved, args.operator_id, if (comptime @hasField(@TypeOf(args), "note")) args.note else null, args.timestamp_ms);
    }

    pub fn deny(allocator: std.mem.Allocator, request: request_mod.ApprovalRequest, operator_id: []const u8, timestamp_ms: i128, note: ?[]const u8) !ApprovalDecision {
        return initFromRequest(allocator, request, .denied, operator_id, note, timestamp_ms);
    }

    pub fn deinit(self: *ApprovalDecision, allocator: std.mem.Allocator) void {
        allocator.free(self.approval_decision_id);
        allocator.free(self.approval_request_id);
        allocator.free(self.operator_id);
        self.approved_scope.deinit(allocator);
        if (self.operator_note) |note| allocator.free(note);
        allocator.free(self.audit_event_reference);
        allocator.free(self.vehicle_id);
        allocator.free(self.command_request_hash);
        allocator.free(self.policy_hash);
        allocator.free(self.state_snapshot_hash);
        allocator.free(self.safety_evaluation_hash);
        allocator.free(self.safety_constraints_hash);
        self.* = undefined;
    }
};

fn initFromRequest(
    allocator: std.mem.Allocator,
    request: request_mod.ApprovalRequest,
    decision: OperatorDecision,
    operator_id: []const u8,
    note: ?[]const u8,
    timestamp_ms: i128,
) !ApprovalDecision {
    if (operator_id.len == 0) return error.MissingOperatorId;
    const decision_id = try token.decisionId(allocator, request.approval_request_id, operator_id, timestamp_ms, @tagName(decision));
    errdefer allocator.free(decision_id);
    return .{
        .approval_decision_id = decision_id,
        .approval_request_id = try allocator.dupe(u8, request.approval_request_id),
        .operator_id = try allocator.dupe(u8, operator_id),
        .decision = decision,
        .approved_scope = try request.scope.clone(allocator),
        .expires_at_ms = request.expires_at_ms,
        .operator_note = if (note) |value| try allocator.dupe(u8, value) else null,
        .timestamp_ms = timestamp_ms,
        .audit_event_reference = try allocator.dupe(u8, if (decision == .approved) "operator.approval_granted" else "operator.approval_denied"),
        .vehicle_id = try allocator.dupe(u8, request.vehicle_id),
        .command_type = request.command_type,
        .command_request_hash = try allocator.dupe(u8, request.command_request_hash),
        .policy_hash = try allocator.dupe(u8, request.policy_hash),
        .state_snapshot_hash = try allocator.dupe(u8, request.state_snapshot_hash),
        .safety_evaluation_hash = try allocator.dupe(u8, request.safety_evaluation_hash),
        .safety_constraints_hash = try allocator.dupe(u8, request.safety_constraints_hash),
        .environment = request.environment,
    };
}
