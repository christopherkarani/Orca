const std = @import("std");

const domain = @import("../domain/mod.zig");
const schema = @import("../schema/mod.zig");
const decision_mod = @import("approval_decision.zig");
const request_mod = @import("approval_request.zig");
const scope_mod = @import("approval_scope.zig");
const token = @import("approval_token.zig");

pub const ApprovalValidationStatus = enum {
    valid,
    missing,
    invalid_decision,
    expired,
    revoked,
    vehicle_mismatch,
    policy_mismatch,
    command_mismatch,
    state_mismatch,
    safety_constraints_mismatch,
    provenance_mismatch,
    scope_mismatch,
    max_uses_exceeded,
    non_overridable_command,
    operator_required,
    broad_scope_not_allowed,
    safety_envelope_failed,
};

pub const ApprovalValidationResult = struct {
    status: ApprovalValidationStatus,
    reason: []u8,
    audit_event: []const u8,

    pub fn deinit(self: *ApprovalValidationResult, allocator: std.mem.Allocator) void {
        allocator.free(self.reason);
        self.* = undefined;
    }

    pub fn isValid(self: ApprovalValidationResult) bool {
        return self.status == .valid;
    }
};

pub fn validateApproval(allocator: std.mem.Allocator, decision: decision_mod.ApprovalDecision, args: anytype) !ApprovalValidationResult {
    if (decision.decision == .revoked) return result(allocator, .revoked, "approval was revoked");
    if (decision.decision != .approved) return result(allocator, .invalid_decision, "approval decision is not approved");
    if (args.now_ms > decision.expires_at_ms) return result(allocator, .expired, "approval expired");
    if (decision.used_count >= decision.approved_scope.max_uses) return result(allocator, .max_uses_exceeded, "approval max uses exceeded");
    if (isNonOverridable(args.command.action) and !args.policy.safety.approval.allow_non_overridable_override) {
        return result(allocator, .non_overridable_command, "command is non-overridable by default");
    }
    if (args.policy.safety.approval.require_operator_identity and decision.operator_id.len == 0) {
        return result(allocator, .operator_required, "operator identity is required");
    }
    if (!std.mem.eql(u8, decision.vehicle_id, args.command.vehicle_id.value)) return result(allocator, .vehicle_mismatch, "approval vehicle does not match command vehicle");
    if (!std.mem.eql(u8, decision.vehicle_id, args.state.vehicle_id.value)) return result(allocator, .vehicle_mismatch, "approval vehicle does not match state vehicle");
    const expected_env = request_mod.ApprovalEnvironment.fromState(args.policy, args.state);
    if (decision.environment != expected_env) return result(allocator, .provenance_mismatch, "approval provenance/environment changed");

    const policy_hash = try token.hashPolicy(allocator, args.policy);
    defer allocator.free(policy_hash);
    if (!std.mem.eql(u8, decision.policy_hash, policy_hash) and !args.policy.safety.approval.allow_compatible_policy_hash) {
        return result(allocator, .policy_mismatch, "policy hash changed");
    }

    if (args.policy.safety.approval.require_safety_constraints_hash) {
        const constraints_hash = try token.hashSafetyConstraints(allocator, args.policy);
        defer allocator.free(constraints_hash);
        if (!std.mem.eql(u8, decision.safety_constraints_hash, constraints_hash)) {
            return result(allocator, .safety_constraints_mismatch, "safety constraints changed");
        }
    }

    if (args.policy.safety.approval.require_state_hash) {
        const state_hash = try token.hashVehicleState(allocator, args.state);
        defer allocator.free(state_hash);
        if (!std.mem.eql(u8, decision.state_snapshot_hash, state_hash)) {
            return result(allocator, .state_mismatch, "state snapshot changed");
        }
    }

    if (args.evaluation.decision.result == .deny) {
        return result(allocator, .safety_envelope_failed, "approval cannot override a deny safety envelope by default");
    }

    switch (decision.approved_scope.kind) {
        .exact_action_only => {
            const command_hash = try token.hashCommandRequest(allocator, args.command);
            defer allocator.free(command_hash);
            if (!std.mem.eql(u8, decision.command_request_hash, command_hash)) return result(allocator, .command_mismatch, "command request hash changed");
        },
        .command_type => {
            if (!args.policy.safety.approval.allow_broad_scopes) return result(allocator, .broad_scope_not_allowed, "command-type approvals require explicit policy support");
            if (decision.command_type != args.command.action) return result(allocator, .scope_mismatch, "approval command type does not match");
        },
        .mission_id, .scenario_id, .vehicle_id, .time_window => {
            if (!args.policy.safety.approval.allow_broad_scopes) return result(allocator, .broad_scope_not_allowed, "broad approvals require explicit policy support");
            if (!scopeAllows(decision.approved_scope, args.command)) return result(allocator, .scope_mismatch, "approval scope does not allow this command");
        },
    }
    return result(allocator, .valid, "approval valid for exact bounded command");
}

fn scopeAllows(scope: scope_mod.ApprovalScope, command: domain.commands.CommandRequest) bool {
    if (!std.mem.eql(u8, scope.vehicle_id, command.vehicle_id.value)) return false;
    return switch (scope.kind) {
        .exact_action_only => false,
        .command_type => scope.command_type == command.action,
        .mission_id => scope.mission_id != null and command.mission_id != null and std.mem.eql(u8, scope.mission_id.?, command.mission_id.?),
        .scenario_id, .vehicle_id, .time_window => true,
    };
}

pub fn isNonOverridable(action: domain.commands.CommandAction) bool {
    return switch (action) {
        .disable_failsafe,
        .disable_geofence,
        .raw_actuator_output,
        .override_operator,
        .firmware_update,
        .companion_computer_reboot,
        .payload_release,
        => true,
        else => false,
    };
}

fn result(allocator: std.mem.Allocator, status: ApprovalValidationStatus, reason_text: []const u8) !ApprovalValidationResult {
    return .{
        .status = status,
        .reason = try allocator.dupe(u8, reason_text),
        .audit_event = if (status == .valid) "operator.approval_used" else if (status == .expired) "operator.approval_expired" else "operator.approval_invalid",
    };
}
