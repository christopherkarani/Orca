//! Shared Rust-daemon shell command evaluation for `orca hook`, `orca run`, and shims.
//!
//! Shell-command security decisions are owned by the Rust daemon. Zig policy YAML
//! command rules and argv classifiers are not used for the security decision here;
//! classification metadata is retained for approval UX only.

const std = @import("std");

const core = @import("orca_core").core;
const policy = @import("orca_core").policy;
const intercept = @import("../intercept/mod.zig");
const daemon = @import("daemon.zig");
const rust_visibility = @import("rust_visibility.zig");
const feed_writer = @import("feed_writer.zig");

pub const ShellCommandEvent = struct {
    command: []const u8,
    cwd: ?[]const u8 = null,
};

pub const ShellCommandEvaluatorFn = *const fn (
    std.mem.Allocator,
    ShellCommandEvent,
) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse);

pub const ShellAuditOptions = struct {
    io: std.Io,
    workspace_root: []const u8,
    event_source: []const u8,
    host: ?[]const u8 = null,
    session_id: ?[]const u8 = null,
    verified: bool = false,
};

const event_source_run = rust_visibility.event_source_run;

fn resolveEffectiveCwd(allocator: std.mem.Allocator, cwd: ?[]const u8) daemon.DaemonError![]const u8 {
    const path = cwd orelse ".";
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    const resolved_z = std.Io.Dir.cwd().realPathFileAlloc(io, path, allocator) catch return error.InvalidWorkingDirectory;
    defer allocator.free(resolved_z);
    return allocator.dupe(u8, resolved_z) catch error.OutOfMemory;
}

pub fn defaultEvaluator(
    allocator: std.mem.Allocator,
    shell_event: ShellCommandEvent,
) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    const absolute_cwd = try resolveEffectiveCwd(allocator, shell_event.cwd);
    defer allocator.free(absolute_cwd);
    return daemon.evaluate(allocator, shell_event.command, absolute_cwd);
}

pub fn daemonUnavailableReason(err: daemon.DaemonError) []const u8 {
    return switch (err) {
        error.HomeDirectoryNotFound => "daemon unavailable: HOME not set",
        error.DaemonBinaryNotFound => "daemon unavailable: orca-daemon binary not found",
        error.DaemonBinaryNotExecutable => "daemon unavailable: orca-daemon is not executable",
        error.DaemonSpawnFailed => "daemon unavailable: failed to spawn orca-daemon",
        error.DaemonStartTimeout => "daemon unavailable: startup timed out",
        error.DaemonNotReady => "daemon unavailable: daemon not ready",
        error.StaleSocket => "daemon unavailable: stale socket artifact",
        error.SocketConnectFailed => "daemon unavailable: socket connect failed",
        error.SocketWriteFailed => "daemon unavailable: socket write failed",
        error.SocketReadFailed => "daemon unavailable: socket read failed",
        error.InvalidWorkingDirectory => "daemon unavailable: command working directory does not exist",
        error.RequestSerializationFailed => "daemon unavailable: request serialization failed",
        error.ResponseParseFailed => "daemon unavailable: malformed daemon response",
        error.DaemonProtocolError => "daemon unavailable: protocol error",
        error.MissingHandshake => "daemon unavailable: missing protocol handshake",
        error.HandshakeMalformed => "daemon unavailable: malformed protocol handshake",
        error.ProtocolMismatch => "daemon unavailable: incompatible daemon protocol",
        error.OutOfMemory => "daemon unavailable: out of memory",
    };
}

pub const PluginDecision = enum {
    allow,
    block,
    warn,
    ask,

    pub fn applyCiMode(self: PluginDecision, ci_mode: bool) PluginDecision {
        return switch (self) {
            .ask, .warn => if (ci_mode) .block else self,
            else => self,
        };
    }
};

pub const RiskLevel = enum {
    low,
    medium,
    high,
    critical,
    unknown,

    pub fn toRiskScore(self: RiskLevel) u8 {
        return switch (self) {
            .low => 20,
            .medium => 50,
            .high => 80,
            .critical => 95,
            .unknown => 60,
        };
    }
};

const OwnedRunDecision = struct {
    decision: core.decision.Decision,
    owned_reason: []const u8,
    owned_rule_id: ?[]const u8 = null,

    pub fn deinit(self: OwnedRunDecision, allocator: std.mem.Allocator) void {
        allocator.free(self.owned_reason);
        if (self.owned_rule_id) |rule_id| allocator.free(rule_id);
    }
};

fn severityEquals(severity: []const u8, expected: []const u8) bool {
    return std.ascii.eqlIgnoreCase(severity, expected);
}

pub fn riskLevelFromDaemonSeverity(severity: ?[]const u8) RiskLevel {
    const value = severity orelse return .high;
    if (severityEquals(value, "critical")) return .critical;
    if (severityEquals(value, "high")) return .high;
    if (severityEquals(value, "medium")) return .medium;
    if (severityEquals(value, "low")) return .low;
    return .unknown;
}

pub fn pluginDecisionFromDaemonAllow(result: std.json.Value) PluginDecision {
    const object = switch (result) {
        .object => |map| map,
        else => return .allow,
    };
    const graduated = object.get("graduated_response") orelse return .allow;
    const grad_type = switch (graduated) {
        .object => |map| map.get("type"),
        else => null,
    };
    const type_name = switch (grad_type orelse return .allow) {
        .string => |s| s,
        else => return .allow,
    };
    if (std.mem.eql(u8, type_name, "Warning")) return .warn;
    if (std.mem.eql(u8, type_name, "SoftBlock")) return .ask;
    if (std.mem.eql(u8, type_name, "HardBlock")) return .block;
    return .allow;
}

fn decisionResultFromPluginDecision(plugin_decision: PluginDecision) core.decision.DecisionResult {
    return switch (plugin_decision) {
        .allow => .allow,
        .block => .deny,
        .warn => .observe,
        .ask => .ask,
    };
}

pub fn buildDaemonDenyReason(
    allocator: std.mem.Allocator,
    result: std.json.Value,
) !struct {
    reason: []const u8,
    rule: ?[]const u8,
} {
    const rule = if (daemon.responseDenyRule(result)) |rule_name| try allocator.dupe(u8, rule_name) else null;
    errdefer if (rule) |rule_name| allocator.free(rule_name);

    const reason = if (rule) |rule_name|
        try std.fmt.allocPrint(allocator, "blocked by Orca policy rule: {s}", .{rule_name})
    else blk: {
        // Never echo raw daemon reason strings; they may include matched command fragments.
        break :blk try allocator.dupe(u8, "command denied by Orca policy");
    };

    return .{ .reason = reason, .rule = rule };
}

pub fn evaluateParsed(
    allocator: std.mem.Allocator,
    shell_event: ShellCommandEvent,
    evaluator_override: ?ShellCommandEvaluatorFn,
) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    const evaluator = evaluator_override orelse defaultEvaluator;
    return evaluator(allocator, shell_event);
}

pub fn decisionFromDaemonResult(
    allocator: std.mem.Allocator,
    result: std.json.Value,
    ci_mode: bool,
) !OwnedRunDecision {
    return switch (daemon.responseStatus(result)) {
        .allow => blk: {
            const plugin_decision = pluginDecisionFromDaemonAllow(result).applyCiMode(ci_mode);
            const decision_result = decisionResultFromPluginDecision(plugin_decision);
            const reason = try allocator.dupe(
                u8,
                daemon.responseReason(result) orelse "command allowed by daemon evaluator",
            );
            break :blk OwnedRunDecision{
                .decision = .{
                    .result = decision_result,
                    .reason = reason,
                    .risk_score = if (plugin_decision == .warn) RiskLevel.medium.toRiskScore() else RiskLevel.low.toRiskScore(),
                    .requires_user = decision_result == .ask,
                    .ci_may_proceed = decision_result == .allow or decision_result == .observe,
                },
                .owned_reason = reason,
            };
        },
        .deny => blk: {
            const deny = try buildDaemonDenyReason(allocator, result);
            const risk = riskLevelFromDaemonSeverity(daemon.responseStringField(result, "severity"));
            break :blk OwnedRunDecision{
                .decision = .{
                    .result = .deny,
                    .rule_id = deny.rule,
                    .reason = deny.reason,
                    .risk_score = risk.toRiskScore(),
                    .requires_user = false,
                    .ci_may_proceed = false,
                },
                .owned_reason = deny.reason,
                .owned_rule_id = deny.rule,
            };
        },
        .error_status => try failClosedRunDecision(
            allocator,
            daemon.responseErrorMessage(result) orelse "daemon evaluation error",
        ),
        .pong, .cli_execution, .unknown => try failClosedRunDecision(
            allocator,
            "unexpected daemon response for shell command evaluation",
        ),
    };
}

fn failClosedRunDecision(allocator: std.mem.Allocator, reason: []const u8) !OwnedRunDecision {
    const owned = try allocator.dupe(u8, reason);
    return .{
        .decision = .{
            .result = .deny,
            .reason = owned,
            .risk_score = RiskLevel.high.toRiskScore(),
            .requires_user = false,
            .ci_may_proceed = false,
        },
        .owned_reason = owned,
    };
}

pub fn failClosedDaemonUnavailableDecision(allocator: std.mem.Allocator, err: daemon.DaemonError) !OwnedRunDecision {
    return failClosedRunDecision(allocator, daemonUnavailableReason(err));
}

/// Evaluate a shell command via the Rust daemon and return a run/shim `CommandDecision`.
pub fn evaluateCommand(
    allocator: std.mem.Allocator,
    effective_mode: policy.schema.Mode,
    argv: []const []const u8,
    cwd: ?[]const u8,
    evaluator_override: ?ShellCommandEvaluatorFn,
    metadata_out: ?*core.event.EventMetadata,
    audit_options: ?ShellAuditOptions,
) !intercept.commands.CommandDecision {
    const display = try intercept.commands.displayArgvAlloc(allocator, argv);
    defer allocator.free(display);

    const classification = intercept.commands.classifyArgv(argv);
    const ci_mode = effective_mode == .ci;

    const shell_event = ShellCommandEvent{ .command = display, .cwd = cwd };
    const daemon_response = evaluateParsed(allocator, shell_event, evaluator_override) catch |err| {
        if (metadata_out) |out| {
            out.* = try rust_visibility.metadataForUnavailable(allocator, event_source_run, null, err);
        }
        if (audit_options) |options| {
            var record = try rust_visibility.buildFeedRecordFromUnavailable(
                allocator,
                options.io,
                options.workspace_root,
                options.event_source,
                options.host,
                err,
                options.session_id,
                options.verified,
            );
            defer record.deinit(allocator);
            feed_writer.appendRecordBestEffort(options.io, allocator, options.workspace_root, record);
        }
        const unavailable = try failClosedDaemonUnavailableDecision(allocator, err);
        const explanation = try allocator.dupe(u8, "evaluated by Rust daemon (unavailable)");
        errdefer allocator.free(explanation);
        const owned_reason = unavailable.owned_reason;
        return .{
            .classification = classification,
            .policy_evaluation = .{
                .decision = unavailable.decision,
                .explanation = explanation,
            },
            .decision = unavailable.decision,
            .owned_reason = owned_reason,
            .owned_rule_id = null,
        };
    };
    defer daemon_response.deinit();

    const daemon_status = blk: {
        var health = try rust_visibility.probeGuiDaemonHealth(allocator);
        defer health.deinit(allocator);
        break :blk try allocator.dupe(u8, health.status);
    };
    defer allocator.free(daemon_status);

    if (metadata_out) |out| {
        out.* = try rust_visibility.metadataFromDaemonResult(
            allocator,
            event_source_run,
            null,
            daemon_status,
            daemon_response.value.result,
        );
    }
    if (audit_options) |options| {
        var record = try rust_visibility.buildFeedRecordFromDaemon(
            allocator,
            options.io,
            options.workspace_root,
            options.event_source,
            options.host,
            daemon_status,
            daemon_response.value.result,
            options.session_id,
            options.verified,
        );
        defer record.deinit(allocator);
        feed_writer.appendRecordBestEffort(options.io, allocator, options.workspace_root, record);
    }

    const translated = try decisionFromDaemonResult(allocator, daemon_response.value.result, ci_mode);

    const explanation = try allocator.dupe(u8, "evaluated by Rust daemon");
    errdefer allocator.free(explanation);

    const owned_reason = translated.owned_reason;
    const owned_rule_id = translated.owned_rule_id;

    return .{
        .classification = classification,
        .policy_evaluation = .{
            .decision = translated.decision,
            .matched_rule = if (owned_rule_id) |rule| .{ .id = rule, .pattern = rule } else null,
            .explanation = explanation,
            .owned_rule_id = null,
        },
        .decision = translated.decision,
        .owned_reason = owned_reason,
        .owned_rule_id = owned_rule_id,
    };
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

pub var test_last_evaluate_command: ?[]const u8 = null;
pub var test_last_evaluate_cwd: ?[]const u8 = null;

var test_last_command_buf: [512]u8 = undefined;
var test_last_command_len: usize = 0;
var test_last_cwd_buf: [512]u8 = undefined;
var test_last_cwd_len: usize = 0;

fn recordMockShellEvent(shell_event: ShellCommandEvent) void {
    const cmd_len = @min(shell_event.command.len, test_last_command_buf.len);
    @memcpy(test_last_command_buf[0..cmd_len], shell_event.command[0..cmd_len]);
    test_last_command_len = cmd_len;
    test_last_evaluate_command = test_last_command_buf[0..cmd_len];

    if (shell_event.cwd) |cwd| {
        const cwd_len = @min(cwd.len, test_last_cwd_buf.len);
        @memcpy(test_last_cwd_buf[0..cwd_len], cwd[0..cwd_len]);
        test_last_cwd_len = cwd_len;
        test_last_evaluate_cwd = test_last_cwd_buf[0..cwd_len];
    } else {
        test_last_cwd_len = 0;
        test_last_evaluate_cwd = null;
    }
}

pub fn mockDaemonResponse(allocator: std.mem.Allocator, line: []const u8) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    return daemon.parseResponse(allocator, line);
}

pub fn mockDaemonAllowEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    recordMockShellEvent(shell_event);
    return mockDaemonResponse(allocator, "{\"id\":1,\"result\":{\"status\":\"Allow\",\"reason\":\"Command allowed by evaluator\"}}");
}

pub fn mockDaemonDenyEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    recordMockShellEvent(shell_event);
    return mockDaemonResponse(allocator, "{\"id\":1,\"result\":{\"status\":\"Deny\",\"reason\":\"Command denied by evaluator\",\"pack_id\":\"git\",\"pattern_name\":\"destructive_rm\",\"severity\":\"critical\",\"explanation\":\"recursive delete of root\"}}");
}

pub fn mockDaemonSoftBlockAllowEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    recordMockShellEvent(shell_event);
    return mockDaemonResponse(allocator, "{\"id\":1,\"result\":{\"status\":\"Allow\",\"reason\":\"Command requires approval\",\"graduated_response\":{\"type\":\"SoftBlock\",\"occurrence\":1}}}");
}

pub fn mockDaemonWarnAllowEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    _ = shell_event;
    return mockDaemonResponse(allocator, "{\"id\":1,\"result\":{\"status\":\"Allow\",\"reason\":\"Command allowed with warning\",\"graduated_response\":{\"type\":\"Warning\",\"occurrence\":2}}}");
}

pub fn mockDaemonErrorEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    _ = shell_event;
    return mockDaemonResponse(allocator, "{\"id\":1,\"result\":{\"status\":\"Error\",\"message\":\"evaluator failure\"}}");
}

pub fn mockDaemonUnavailableEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    _ = allocator;
    _ = shell_event;
    return error.SocketConnectFailed;
}

pub fn mockDaemonProtocolMismatchEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    _ = allocator;
    _ = shell_event;
    return error.ProtocolMismatch;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "shell_eval allows safe command via mock daemon" {
    const allocator = std.testing.allocator;
    var decision = try evaluateCommand(allocator, .strict, &.{ "git", "status" }, "/tmp/repo", mockDaemonAllowEvaluator, null, null);
    defer decision.deinit(allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.allow, decision.decision.result);
    try std.testing.expectEqualStrings("git status", test_last_evaluate_command.?);
    try std.testing.expectEqualStrings("/tmp/repo", test_last_evaluate_cwd.?);
}

test "shell_eval denies dangerous command via mock daemon" {
    const allocator = std.testing.allocator;
    var decision = try evaluateCommand(allocator, .strict, &.{ "rm", "-rf", "/" }, null, mockDaemonDenyEvaluator, null, null);
    defer decision.deinit(allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, decision.decision.result);
    try std.testing.expect(decision.owned_rule_id != null);
    try std.testing.expectEqualStrings("destructive_rm", decision.owned_rule_id.?);
}

test "shell_eval fails closed when daemon unavailable" {
    const allocator = std.testing.allocator;
    var decision = try evaluateCommand(allocator, .strict, &.{ "git", "status" }, null, mockDaemonUnavailableEvaluator, null, null);
    defer decision.deinit(allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, decision.decision.result);
    try std.testing.expect(std.mem.indexOf(u8, decision.decision.reason, "daemon unavailable") != null);
}

test "shell_eval reports a missing command working directory explicitly" {
    try std.testing.expectError(
        error.InvalidWorkingDirectory,
        resolveEffectiveCwd(std.testing.allocator, "/definitely/missing/orca-working-directory"),
    );
    try std.testing.expectEqualStrings(
        "daemon unavailable: command working directory does not exist",
        daemonUnavailableReason(error.InvalidWorkingDirectory),
    );
}

test "shell_eval ci mode converts warn allow to deny" {
    const allocator = std.testing.allocator;
    var decision = try evaluateCommand(allocator, .ci, &.{ "git", "status" }, null, mockDaemonWarnAllowEvaluator, null, null);
    defer decision.deinit(allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, decision.decision.result);
}

test "shell_eval daemon error fails closed" {
    const allocator = std.testing.allocator;
    var decision = try evaluateCommand(allocator, .strict, &.{ "git", "status" }, null, mockDaemonErrorEvaluator, null, null);
    defer decision.deinit(allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, decision.decision.result);
}

test "shell_eval protocol mismatch fails closed" {
    const allocator = std.testing.allocator;
    var decision = try evaluateCommand(allocator, .strict, &.{ "git", "status" }, null, mockDaemonProtocolMismatchEvaluator, null, null);
    defer decision.deinit(allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, decision.decision.result);
    try std.testing.expect(std.mem.indexOf(u8, decision.decision.reason, "incompatible daemon protocol") != null);
}

test "hook and run parity for safe and dangerous commands" {
    const allocator = std.testing.allocator;

    var safe_run = try evaluateCommand(allocator, .strict, &.{ "git", "status" }, null, mockDaemonAllowEvaluator, null, null);
    defer safe_run.deinit(allocator);
    var safe_daemon = try mockDaemonAllowEvaluator(allocator, .{ .command = "git status", .cwd = null });
    defer safe_daemon.deinit();
    var safe_hook = try decisionFromDaemonResult(allocator, safe_daemon.value.result, false);
    defer safe_hook.deinit(allocator);
    try std.testing.expectEqual(safe_run.decision.result, safe_hook.decision.result);

    var dangerous_run = try evaluateCommand(allocator, .strict, &.{ "rm", "-rf", "/" }, null, mockDaemonDenyEvaluator, null, null);
    defer dangerous_run.deinit(allocator);
    var dangerous_daemon = try mockDaemonDenyEvaluator(allocator, .{ .command = "rm -rf /", .cwd = null });
    defer dangerous_daemon.deinit();
    var dangerous_hook = try decisionFromDaemonResult(allocator, dangerous_daemon.value.result, false);
    defer dangerous_hook.deinit(allocator);
    try std.testing.expectEqual(dangerous_run.decision.result, dangerous_hook.decision.result);
    try std.testing.expectEqualStrings(dangerous_run.owned_rule_id.?, dangerous_hook.owned_rule_id.?);
}
