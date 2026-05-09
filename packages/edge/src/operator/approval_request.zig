const std = @import("std");

const domain = @import("../domain/mod.zig");
const schema = @import("../schema/mod.zig");
const scope_mod = @import("approval_scope.zig");
const token = @import("approval_token.zig");

pub const ApprovalEnvironment = enum {
    fake_adapter,
    fake_px4_adapter,
    fake_ardupilot_adapter,
    px4_sitl,
    ardupilot_sitl,
    bench,
    unknown,

    pub fn fromState(policy: *const schema.edge_policy_schema.EdgePolicyV1, state: domain.state.VehicleState) ApprovalEnvironment {
        return switch (state.provenance) {
            .fake_adapter => if (policy.vehicle.autopilot == .px4) .fake_px4_adapter else .fake_adapter,
            .fake_ardupilot_adapter => .fake_ardupilot_adapter,
            .sitl_px4 => .px4_sitl,
            .sitl_ardupilot => .ardupilot_sitl,
            .bench => .bench,
            .customer_adapter, .unknown => .unknown,
        };
    }
};

pub const RequestedApprovalDecision = enum {
    allow_once,
    allow_for_scenario,
    allow_for_mission,
    allow_for_command_class,
    deny,
};

pub const ApprovalRequest = struct {
    approval_request_id: []u8,
    vehicle_id: []u8,
    command_id: []u8,
    command_type: domain.commands.CommandAction,
    command_request_hash: []u8,
    policy_hash: []u8,
    state_snapshot_hash: []u8,
    safety_evaluation_hash: []u8,
    safety_constraints_hash: []u8,
    actor_id: []u8,
    operator_id: ?[]u8,
    environment: ApprovalEnvironment,
    requested_decision: RequestedApprovalDecision,
    scope: scope_mod.ApprovalScope,
    expires_at_ms: i128,
    created_at_ms: i128,
    reason: []u8,
    risk_class: domain.commands.RiskCategory,
    safety_findings_summary: []u8,
    matched_policy_rules: []u8,
    non_certification_disclaimer: []u8,

    pub fn deinit(self: *ApprovalRequest, allocator: std.mem.Allocator) void {
        allocator.free(self.approval_request_id);
        allocator.free(self.vehicle_id);
        allocator.free(self.command_id);
        allocator.free(self.command_request_hash);
        allocator.free(self.policy_hash);
        allocator.free(self.state_snapshot_hash);
        allocator.free(self.safety_evaluation_hash);
        allocator.free(self.safety_constraints_hash);
        allocator.free(self.actor_id);
        if (self.operator_id) |operator_id| allocator.free(operator_id);
        self.scope.deinit(allocator);
        allocator.free(self.reason);
        allocator.free(self.safety_findings_summary);
        allocator.free(self.matched_policy_rules);
        allocator.free(self.non_certification_disclaimer);
        self.* = undefined;
    }
};

pub fn createApprovalRequest(allocator: std.mem.Allocator, args: anytype) !ApprovalRequest {
    const policy_hash = try token.hashPolicy(allocator, args.policy);
    errdefer allocator.free(policy_hash);
    const command_hash = try token.hashCommandRequest(allocator, args.command);
    errdefer allocator.free(command_hash);
    const state_hash = try token.hashVehicleState(allocator, args.state);
    errdefer allocator.free(state_hash);
    const safety_hash = try token.hashSafetyEvaluation(allocator, args.evaluation);
    errdefer allocator.free(safety_hash);
    const constraints_hash = try token.hashSafetyConstraints(allocator, args.policy);
    errdefer allocator.free(constraints_hash);
    const expires_at_ms = if (comptime @hasField(@TypeOf(args), "expires_at_ms")) args.expires_at_ms else args.created_at_ms + @as(i128, @intCast(args.policy.safety.approval.approval_ttl_ms));
    if (expires_at_ms <= args.created_at_ms) return error.ApprovalExpiryRequired;
    const max_uses = args.policy.safety.approval.max_uses_default;
    var scope = try scope_mod.ApprovalScope.exact(allocator, args.command, expires_at_ms, max_uses, policy_hash, state_hash, constraints_hash, command_hash);
    errdefer scope.deinit(allocator);
    const findings_summary = try summarizeEvaluation(allocator, args.evaluation);
    errdefer allocator.free(findings_summary);
    const matched_rules = try matchedRulesSummary(allocator, args.evaluation);
    errdefer allocator.free(matched_rules);
    const request_id = try token.requestId(allocator, &.{ policy_hash, command_hash, state_hash, safety_hash });
    errdefer allocator.free(request_id);
    return .{
        .approval_request_id = request_id,
        .vehicle_id = try allocator.dupe(u8, args.command.vehicle_id.value),
        .command_id = try allocator.dupe(u8, args.command.command_id),
        .command_type = args.command.action,
        .command_request_hash = command_hash,
        .policy_hash = policy_hash,
        .state_snapshot_hash = state_hash,
        .safety_evaluation_hash = safety_hash,
        .safety_constraints_hash = constraints_hash,
        .actor_id = try allocator.dupe(u8, args.actor_id),
        .operator_id = if (comptime @hasField(@TypeOf(args), "operator_id")) if (args.operator_id) |id| try allocator.dupe(u8, id) else null else null,
        .environment = ApprovalEnvironment.fromState(args.policy, args.state),
        .requested_decision = args.requested_decision,
        .scope = scope,
        .expires_at_ms = expires_at_ms,
        .created_at_ms = args.created_at_ms,
        .reason = try allocator.dupe(u8, args.reason),
        .risk_class = args.command.risk_classification,
        .safety_findings_summary = findings_summary,
        .matched_policy_rules = matched_rules,
        .non_certification_disclaimer = try allocator.dupe(u8, "Operator approval is bounded simulation/SITL/bench evidence only; it is not real-flight readiness, detect-and-avoid, autopilot replacement, or regulatory certification."),
    };
}

fn summarizeEvaluation(allocator: std.mem.Allocator, evaluation: anytype) ![]u8 {
    const explanation = if (comptime @hasField(@TypeOf(evaluation), "explanation")) evaluation.explanation else "approval evaluation";
    if (explanation.len <= 512) return allocator.dupe(u8, explanation);
    return allocator.dupe(u8, explanation[0..512]);
}

fn matchedRulesSummary(allocator: std.mem.Allocator, evaluation: anytype) ![]u8 {
    if (comptime @hasField(@TypeOf(evaluation), "matched_rule")) {
        if (evaluation.matched_rule) |rule| return std.fmt.allocPrint(allocator, "{s}: {s}", .{ rule.id, rule.description });
    }
    return allocator.dupe(u8, "none");
}
