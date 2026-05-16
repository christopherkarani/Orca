const std = @import("std");

const engine = @import("core_engine");
const audit = engine.audit;
const core_mod = engine.core;
const policy = engine.policy;

pub const Decision = core_mod.decision.Decision;
pub const DecisionResult = core_mod.decision.DecisionResult;
pub const Evaluation = policy.schema.Evaluation;
pub const EvaluationContext = policy.schema.EvaluationContext;
pub const Preset = policy.presets.Preset;
pub const ReplayOptions = audit.replay.ReplayOptions;
pub const ReplaySession = audit.replay.ReplaySession;
pub const VerifyResult = audit.replay.VerifyResult;
pub const AuditWriter = audit.writer.SessionWriter;
pub const SummaryInput = audit.summary.SummaryInput;
pub const Mode = core_mod.types.Mode;
pub const Path = core_mod.types.Path;
pub const PathKind = core_mod.types.PathKind;
pub const Timestamp = core_mod.time.Timestamp;
pub const Session = core_mod.session.Session;
pub const SessionId = core_mod.session.SessionId;
pub const EventId = core_mod.event.EventId;

pub const Policy = struct {
    raw: *anyopaque,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Policy) void {
        const inner_policy = self.innerMut();
        inner_policy.deinit();
        self.allocator.destroy(inner_policy);
        self.* = undefined;
    }

    fn inner(self: *const Policy) *const policy.schema.Policy {
        return @ptrCast(@alignCast(self.raw));
    }

    fn innerMut(self: *Policy) *policy.schema.Policy {
        return @ptrCast(@alignCast(self.raw));
    }
};

pub const LoadSource = policy.schema.LoadSource;

pub const LoadedPolicy = struct {
    policy: Policy,
    source: LoadSource,
    path: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *LoadedPolicy) void {
        self.policy.deinit();
        self.allocator.free(self.path);
        self.* = undefined;
    }
};

pub const ActorKind = enum {
    user,
    agent,
    process,
    core,
    unknown,
};

pub const Actor = struct {
    kind: ActorKind,
    id: ?[]const u8 = null,
    display: ?[]const u8 = null,
};

pub const TargetKind = enum {
    env_var,
    file_path,
    command,
    network_endpoint,
    approval,
    staging_area,
    extension,
    session,
    unknown,
};

pub const Target = struct {
    kind: TargetKind,
    value: []const u8,
};

pub const EnvAction = struct {
    name: []const u8,
};

pub const FileAction = struct {
    path: Path,
};

pub const CommandAction = struct {
    argv: []const []const u8,
};

pub const NetworkAction = struct {
    host: []const u8,
    port: ?u16 = null,
    scheme: ?[]const u8 = null,
};

pub const ApprovalAction = struct {
    target: Target,
    requested_scope: []const u8,
};

pub const StagingAction = struct {
    path: Path,
};

pub const ExtensionAction = struct {
    domain: []const u8,
    operation: []const u8,
    target: []const u8,
};

pub const Action = union(enum) {
    env_read: EnvAction,
    file_read: FileAction,
    file_write: FileAction,
    command_exec: CommandAction,
    network_connect: NetworkAction,
    approval_decision: ApprovalAction,
    staging_decision: StagingAction,
    extension: ExtensionAction,

    pub fn targetKind(self: Action) TargetKind {
        return switch (self) {
            .env_read => .env_var,
            .file_read, .file_write => .file_path,
            .command_exec => .command,
            .network_connect => .network_endpoint,
            .approval_decision => .approval,
            .staging_decision => .staging_area,
            .extension => .extension,
        };
    }
};

pub const EventType = enum {
    session_start,
    session_exit,
    policy_loaded,
    backend_capability,
    process_launch,
    file_read_attempt,
    file_read_allowed,
    file_read_denied,
    file_write_attempt,
    file_write_staged,
    file_write_denied,
    file_apply,
    file_discard,
    command_attempt,
    command_approval_requested,
    command_allowed,
    command_denied,
    network_connect_attempt,
    network_connect_allowed,
    network_connect_denied,
    network_exfiltration_suspected,
    secret_redacted,
    user_approval,
    user_denial,
};

pub const DecisionInput = struct {
    result: DecisionResult,
    reason: []const u8,
    rule_id: ?[]const u8 = null,
    risk_score: ?u8 = null,
    requires_user: bool = false,
    ci_may_proceed: bool = false,
};

pub const AuditEventInput = struct {
    session_id: SessionId,
    event_id: EventId,
    timestamp: Timestamp,
    event_type: EventType,
    actor: Actor,
    target: Target,
    decision: ?Decision = null,
    redactions: core_mod.event.RedactionSummary = .{},
};

pub fn generateSessionId(now: Timestamp) !SessionId {
    return core_mod.session.generateSessionId(now);
}

pub fn generateEventId(now: Timestamp) !EventId {
    return core_mod.event.generateEventId(now);
}

pub fn detectOs() core_mod.platform.Os {
    return core_mod.platform.detectOs();
}

pub fn parsePolicyFromSlice(allocator: std.mem.Allocator, text: []const u8, source_path: ?[]const u8) !Policy {
    var parsed = try policy.load.parseFromSlice(allocator, text, source_path);
    errdefer parsed.deinit();
    return wrapPolicy(allocator, parsed);
}

pub fn loadPolicyFile(allocator: std.mem.Allocator, path: []const u8) !Policy {
    var loaded = try policy.load.loadFile(allocator, path);
    errdefer loaded.deinit();
    return wrapPolicy(allocator, loaded);
}

pub fn loadPolicyPreset(allocator: std.mem.Allocator, preset: Preset) !Policy {
    var loaded = try policy.load.loadPreset(allocator, preset);
    errdefer loaded.deinit();
    return wrapPolicy(allocator, loaded);
}

pub fn discoverPolicy(allocator: std.mem.Allocator, explicit_path: ?[]const u8, workspace_root: []const u8) !LoadedPolicy {
    var loaded = try policy.load.discover(allocator, explicit_path, workspace_root);
    errdefer loaded.deinit();
    const wrapped = try wrapPolicy(allocator, loaded.policy);
    return .{
        .policy = wrapped,
        .source = loaded.source,
        .path = loaded.path,
        .allocator = allocator,
    };
}

pub fn validatePolicy(value: *const Policy) !void {
    return policy.validate.policy(value.inner());
}

pub fn evaluateAction(allocator: std.mem.Allocator, value: *const Policy, requested: Action, context: EvaluationContext) !Evaluation {
    return switch (requested) {
        .env_read => |env_action| policy.evaluate.action(value.inner(), .{ .env_read = .{ .name = env_action.name } }, context, allocator),
        .file_read => |file| policy.evaluate.action(value.inner(), .{ .file_read = .{ .path = file.path } }, context, allocator),
        .file_write => |file| policy.evaluate.action(value.inner(), .{ .file_write = .{ .path = file.path } }, context, allocator),
        .command_exec => |command_action| policy.evaluate.action(value.inner(), .{ .command_exec = .{ .argv = command_action.argv } }, context, allocator),
        .network_connect => |network_action| policy.evaluate.action(value.inner(), .{ .network_connect = .{
            .host = network_action.host,
            .port = network_action.port,
            .scheme = network_action.scheme,
        } }, context, allocator),
        .approval_decision => |approval| policy.evaluate.action(value.inner(), .{ .approval_decision = .{
            .target = toCoreTarget(approval.target),
            .requested_scope = approval.requested_scope,
        } }, context, allocator),
        .staging_decision => |staging| policy.evaluate.action(value.inner(), .{ .staging_decision = .{ .path = staging.path } }, context, allocator),
        .extension => |extension| evaluateExtensionAction(allocator, value, extension, context),
    };
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

pub fn createAuditEvent(input: AuditEventInput) !core_mod.event.Event {
    return .{
        .session_id = input.session_id,
        .event_id = input.event_id,
        .timestamp = input.timestamp,
        .event_type = toCoreEventType(input.event_type),
        .actor = toCoreActor(input.actor),
        .target = toCoreTarget(input.target),
        .decision = input.decision,
        .redactions = input.redactions,
    };
}

pub fn createAuditWriter(allocator: std.mem.Allocator, session: Session) !AuditWriter {
    return AuditWriter.init(allocator, session);
}

pub fn openAuditWriter(allocator: std.mem.Allocator, workspace_root: []const u8, session_id: []const u8) !AuditWriter {
    return AuditWriter.openExisting(allocator, workspace_root, session_id);
}

pub fn appendAuditEvent(writer: *AuditWriter, event: core_mod.event.Event) !void {
    try writer.appendEvent(event);
}

pub fn writeAuditSummary(allocator: std.mem.Allocator, session_dir_path: []const u8, input: SummaryInput) !void {
    try audit.summary.writeFiles(allocator, session_dir_path, input);
}

pub fn updateAuditSummaryFinalHash(allocator: std.mem.Allocator, session_dir_path: []const u8, event_count: usize, final_event_hash: []const u8) !void {
    try audit.summary.updateFinalHash(allocator, session_dir_path, event_count, final_event_hash);
}

pub fn redactString(value: []const u8) []const u8 {
    return audit.redact_bridge.redactString(value);
}

pub fn redactStringBounded(value: []const u8, buffer: []u8) []const u8 {
    return audit.redact_bridge.redactStringBounded(value, buffer);
}

pub fn redactTargetValueBounded(kind_name: []const u8, value: []const u8, buffer: []u8) []const u8 {
    return audit.redact_bridge.redactTargetValueBounded(kind_name, value, buffer);
}

pub fn verifyReplay(allocator: std.mem.Allocator, session_dir_path: []const u8) !VerifyResult {
    return audit.replay.verifySessionDir(allocator, session_dir_path);
}

pub fn loadReplay(allocator: std.mem.Allocator, workspace_root: []const u8, options: ReplayOptions) !ReplaySession {
    return audit.replay.load(allocator, workspace_root, options);
}

pub fn writeReplayJson(writer: anytype, replay: ReplaySession) !void {
    try audit.replay.writeJson(writer, replay);
}

pub fn writeReplayHuman(writer: anytype, replay: ReplaySession, show_verify: bool) !void {
    try audit.replay.writeHuman(writer, replay, show_verify);
}

fn evaluateExtensionAction(
    allocator: std.mem.Allocator,
    value: *const Policy,
    extension: ExtensionAction,
    context: EvaluationContext,
) !Evaluation {
    const mode = context.mode orelse value.inner().mode;
    const decision_value = modeDefault(mode);
    const actual = if (mode == .ci and decision_value == .ask) policy.schema.DecisionValue.deny else decision_value;
    const explanation = try std.fmt.allocPrint(
        allocator,
        "extension {s}.{s} on {s}: {s}",
        .{ extension.domain, extension.operation, extension.target, if (mode == .ci and decision_value == .ask) "ask converted to deny in ci mode" else actual.toString() },
    );
    return .{
        .decision = .{
            .result = actual.toDecisionResult(),
            .reason = explanation,
            .requires_user = actual == .ask,
            .ci_may_proceed = actual == .allow or actual == .observe,
        },
        .explanation = explanation,
    };
}

fn modeDefault(mode: policy.schema.Mode) policy.schema.DecisionValue {
    return switch (mode) {
        .observe => .observe,
        .ask, .trusted => .ask,
        .strict, .ci, .redteam => .deny,
    };
}

fn wrapPolicy(allocator: std.mem.Allocator, value: policy.schema.Policy) !Policy {
    const boxed = try allocator.create(policy.schema.Policy);
    boxed.* = value;
    return .{ .raw = boxed, .allocator = allocator };
}

fn toCoreActor(actor: Actor) core_mod.types.Actor {
    return .{
        .kind = switch (actor.kind) {
            .user => .user,
            .agent => .agent,
            .process => .process,
            .core => .aegis,
            .unknown => .unknown,
        },
        .id = actor.id,
        .display = actor.display,
    };
}

fn toCoreTarget(target: Target) core_mod.types.Target {
    return .{
        .kind = switch (target.kind) {
            .env_var => .env_var,
            .file_path => .file_path,
            .command => .command,
            .network_endpoint => .network_endpoint,
            .approval => .approval,
            .staging_area => .staging_area,
            .extension => .unknown,
            .session => .session,
            .unknown => .unknown,
        },
        .value = target.value,
    };
}

fn toCoreEventType(value: EventType) core_mod.event.EventType {
    return switch (value) {
        .session_start => .session_start,
        .session_exit => .session_exit,
        .policy_loaded => .policy_loaded,
        .backend_capability => .backend_capability,
        .process_launch => .process_launch,
        .file_read_attempt => .file_read_attempt,
        .file_read_allowed => .file_read_allowed,
        .file_read_denied => .file_read_denied,
        .file_write_attempt => .file_write_attempt,
        .file_write_staged => .file_write_staged,
        .file_write_denied => .file_write_denied,
        .file_apply => .file_apply,
        .file_discard => .file_discard,
        .command_attempt => .command_attempt,
        .command_approval_requested => .command_approval_requested,
        .command_allowed => .command_allowed,
        .command_denied => .command_denied,
        .network_connect_attempt => .network_connect_attempt,
        .network_connect_allowed => .network_connect_allowed,
        .network_connect_denied => .network_connect_denied,
        .network_exfiltration_suspected => .network_exfiltration_suspected,
        .secret_redacted => .secret_redacted,
        .user_approval => .user_approval,
        .user_denial => .user_denial,
    };
}

test "core API evaluates generic policy actions and redacts strings" {
    var selected = try parsePolicyFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: strict
        \\commands:
        \\  allow:
        \\    - "echo *"
    , "core-api-test.yaml");
    defer selected.deinit();

    var evaluation = try evaluateAction(std.testing.allocator, &selected, .{ .command_exec = .{ .argv = &.{ "echo", "ok" } } }, .{});
    defer evaluation.deinit(std.testing.allocator);
    try std.testing.expectEqual(DecisionResult.allow, evaluation.decision.result);

    const redacted = redactString("TOKEN=fake_secret_value_phase25");
    try std.testing.expect(std.mem.indexOf(u8, redacted, "fake_secret_value_phase25") == null);
}
