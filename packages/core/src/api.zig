const std = @import("std");
const aegis = @import("aegis");

pub const Action = aegis.core.types.Action;
pub const Decision = aegis.core.decision.Decision;
pub const DecisionResult = aegis.core.decision.DecisionResult;
pub const Evaluation = aegis.policy.schema.Evaluation;
pub const EvaluationContext = aegis.policy.schema.EvaluationContext;
pub const Policy = aegis.policy.schema.Policy;
pub const ReplayOptions = aegis.audit.replay.ReplayOptions;
pub const ReplaySession = aegis.audit.replay.ReplaySession;
pub const VerifyResult = aegis.audit.replay.VerifyResult;
pub const AuditWriter = aegis.audit.writer.SessionWriter;

pub const DecisionInput = struct {
    result: DecisionResult,
    reason: []const u8,
    rule_id: ?[]const u8 = null,
    risk_score: ?u8 = null,
    requires_user: bool = false,
    ci_may_proceed: bool = false,
};

pub const AuditEventInput = struct {
    session_id: aegis.core.session.SessionId,
    event_id: aegis.core.event.EventId,
    timestamp: aegis.core.time.Timestamp,
    event_type: aegis.core.event.EventType,
    actor: aegis.core.types.Actor,
    target: aegis.core.types.Target,
    decision: ?Decision = null,
    redactions: aegis.core.event.RedactionSummary = .{},
};

pub fn parsePolicyFromSlice(allocator: std.mem.Allocator, text: []const u8, source_path: ?[]const u8) !Policy {
    return aegis.policy.load.parseFromSlice(allocator, text, source_path);
}

pub fn loadPolicyFile(allocator: std.mem.Allocator, path: []const u8) !Policy {
    return aegis.policy.load.loadFile(allocator, path);
}

pub fn validatePolicy(policy: *const Policy) !void {
    return aegis.policy.validate.policy(policy);
}

pub fn evaluateAction(allocator: std.mem.Allocator, policy: *const Policy, action: Action, context: EvaluationContext) !Evaluation {
    return aegis.policy.evaluate.action(policy, action, context, allocator);
}

pub fn makeDecision(input: DecisionInput) Decision {
    return .{
        .result = input.result,
        .rule_id = input.rule_id,
        .reason = input.reason,
        .risk_score = input.risk_score,
        .requires_user = input.requires_user,
        .ci_may_proceed = input.ci_may_proceed,
    };
}

pub fn createAuditEvent(input: AuditEventInput) !aegis.core.event.Event {
    return .{
        .session_id = input.session_id,
        .event_id = input.event_id,
        .timestamp = input.timestamp,
        .event_type = input.event_type,
        .actor = input.actor,
        .target = input.target,
        .decision = input.decision,
        .redactions = input.redactions,
    };
}

pub fn createAuditWriter(allocator: std.mem.Allocator, session: aegis.core.session.Session) !AuditWriter {
    return AuditWriter.init(allocator, session);
}

pub fn openAuditWriter(allocator: std.mem.Allocator, workspace_root: []const u8, session_id: []const u8) !AuditWriter {
    return AuditWriter.openExisting(allocator, workspace_root, session_id);
}

pub fn appendAuditEvent(writer: *AuditWriter, event: aegis.core.event.Event) !void {
    try writer.appendEvent(event);
}

pub fn redactString(value: []const u8) []const u8 {
    return aegis.audit.redact_bridge.redactString(value);
}

pub fn redactStringBounded(value: []const u8, buffer: []u8) []const u8 {
    return aegis.audit.redact_bridge.redactStringBounded(value, buffer);
}

pub fn redactTargetValueBounded(kind_name: []const u8, value: []const u8, buffer: []u8) []const u8 {
    return aegis.audit.redact_bridge.redactTargetValueBounded(kind_name, value, buffer);
}

pub fn verifyReplay(allocator: std.mem.Allocator, session_dir_path: []const u8) !VerifyResult {
    return aegis.audit.replay.verifySessionDir(allocator, session_dir_path);
}

pub fn loadReplay(allocator: std.mem.Allocator, workspace_root: []const u8, options: ReplayOptions) !ReplaySession {
    return aegis.audit.replay.load(allocator, workspace_root, options);
}

pub fn writeReplayJson(writer: anytype, replay: ReplaySession) !void {
    try aegis.audit.replay.writeJson(writer, replay);
}

pub fn writeReplayHuman(writer: anytype, replay: ReplaySession, show_verify: bool) !void {
    try aegis.audit.replay.writeHuman(writer, replay, show_verify);
}

test "api module exposes policy evaluation without product-specific imports" {
    var selected = try parsePolicyFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: strict
        \\commands:
        \\  allow:
        \\    - "echo *"
    , "api-test.yaml");
    defer selected.deinit();

    var evaluation = try evaluateAction(std.testing.allocator, &selected, .{ .command_exec = .{ .argv = &.{ "echo", "ok" } } }, .{});
    defer evaluation.deinit(std.testing.allocator);
    try std.testing.expectEqual(DecisionResult.allow, evaluation.decision.result);
}
