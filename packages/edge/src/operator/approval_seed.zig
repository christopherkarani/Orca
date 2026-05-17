const std = @import("std");

const approval_decision = @import("approval_decision.zig");
const approval_request = @import("approval_request.zig");

pub const ApprovalSeedKind = enum {
    none,
    valid_once,
    expired,
    denied,
    revoked,
    mismatched_policy,
    mismatched_command,
    mismatched_vehicle,
    mismatched_state,
    broad_command_type,
    reused_once,
};

pub fn parseSeedKind(value: []const u8) !ApprovalSeedKind {
    const trimmed = std.mem.trim(u8, value, " \t\r\n\"'");
    if (trimmed.len == 0 or std.mem.eql(u8, trimmed, "none")) return .none;
    if (std.mem.indexOf(u8, trimmed, "expired") != null) return .expired;
    if (std.mem.indexOf(u8, trimmed, "revoked") != null) return .revoked;
    if (std.mem.indexOf(u8, trimmed, "denied") != null or std.mem.indexOf(u8, trimmed, "deny") != null) return .denied;
    if (std.mem.indexOf(u8, trimmed, "mismatched-policy") != null or std.mem.eql(u8, trimmed, "mismatched_policy")) return .mismatched_policy;
    if (std.mem.indexOf(u8, trimmed, "mismatched-command") != null or std.mem.eql(u8, trimmed, "mismatched_command")) return .mismatched_command;
    if (std.mem.indexOf(u8, trimmed, "mismatched-vehicle") != null or std.mem.eql(u8, trimmed, "mismatched_vehicle")) return .mismatched_vehicle;
    if (std.mem.indexOf(u8, trimmed, "mismatched-state") != null or std.mem.eql(u8, trimmed, "mismatched_state")) return .mismatched_state;
    if (std.mem.indexOf(u8, trimmed, "broad") != null or std.mem.eql(u8, trimmed, "broad_command_type")) return .broad_command_type;
    if (std.mem.indexOf(u8, trimmed, "reused") != null or std.mem.eql(u8, trimmed, "used_once")) return .reused_once;
    if (std.mem.indexOf(u8, trimmed, "valid") != null or std.mem.eql(u8, trimmed, "valid_once")) return .valid_once;
    return error.InvalidApprovalSeed;
}

pub fn createSeededDecision(allocator: std.mem.Allocator, kind: ApprovalSeedKind, args: anytype) !?approval_decision.ApprovalDecision {
    if (kind == .none) return null;

    var request = try approval_request.createApprovalRequest(allocator, .{
        .policy = args.policy,
        .command = args.command,
        .state = args.state,
        .evaluation = args.evaluation,
        .requested_decision = .allow_once,
        .created_at_ms = args.now_ms,
        .expires_at_ms = args.now_ms + @as(i128, @intCast(args.policy.safety.approval.approval_ttl_ms)),
        .actor_id = if (comptime @hasField(@TypeOf(args), "actor_id")) args.actor_id else "edge-scenario",
        .operator_id = null,
        .reason = "scenario-seeded bounded operator approval",
    });
    defer request.deinit(allocator);

    var decision = if (kind == .denied)
        try approval_decision.ApprovalDecision.deny(allocator, request, "operator-scenario", args.now_ms + 100, "scenario denial")
    else
        try approval_decision.ApprovalDecision.approve(allocator, request, .{
            .operator_id = "operator-scenario",
            .timestamp_ms = args.now_ms + 100,
            .note = "scenario approval fixture",
        });
    errdefer decision.deinit(allocator);

    switch (kind) {
        .none, .valid_once, .denied => {},
        .expired => {
            decision.expires_at_ms = args.now_ms - 1;
            decision.approved_scope.expires_at_ms = args.now_ms - 1;
        },
        .revoked => {
            decision.decision = .revoked;
            try replaceOwned(allocator, &decision.audit_event_reference, "operator.approval_revoked");
        },
        .mismatched_policy => {
            flipOwned(decision.policy_hash);
            flipOwned(decision.approved_scope.policy_hash);
        },
        .mismatched_command => {
            flipOwned(decision.command_request_hash);
            flipOwned(decision.approved_scope.command_request_hash);
        },
        .mismatched_vehicle => {
            flipOwned(decision.vehicle_id);
            flipOwned(decision.approved_scope.vehicle_id);
        },
        .mismatched_state => {
            flipOwned(decision.state_snapshot_hash);
            flipOwned(decision.approved_scope.state_snapshot_hash);
        },
        .broad_command_type => {
            decision.approved_scope.kind = .command_type;
        },
        .reused_once => {
            decision.used_count = decision.approved_scope.max_uses;
        },
    }
    return decision;
}

fn flipOwned(value: []u8) void {
    if (value.len == 0) return;
    value[0] = if (value[0] == '0') '1' else '0';
}

fn replaceOwned(allocator: std.mem.Allocator, target: *[]u8, replacement: []const u8) !void {
    allocator.free(target.*);
    target.* = try allocator.dupe(u8, replacement);
}
