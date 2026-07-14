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
    return daemon.errors.shellUnavailableReason(err);
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

/// Mode × severity matrix for shell denials returned by the Rust daemon.
///
/// Daemon Evaluate returns Allow/Deny with optional pack severity. Orca modes
/// map those engine hits into product outcomes in one place so run/hook/shim
/// stay aligned.
///
/// | Mode    | Critical (always-deny) | High / unknown | Medium | Low  |
/// |---------|------------------------|----------------|--------|------|
/// | observe | deny                   | warn-allow     | allow  | allow|
/// | ask     | deny                   | ask            | warn   | allow|
/// | strict  | deny                   | deny           | deny   | allow|
/// | ci      | deny                   | deny           | deny   | allow|
///
/// Critical remains deny in every mode (catastrophic always-on rules such as
/// core.filesystem root wipe / core.git reset --hard). Daemon unavailable is
/// fail-closed deny and is not routed through this matrix.
pub fn pluginDecisionFromModeAndSeverity(mode: policy.schema.Mode, severity: RiskLevel) PluginDecision {
    // Critical / catastrophic: never softened by mode.
    if (severity == .critical) return .block;

    return switch (mode) {
        .observe, .trusted => switch (severity) {
            .high, .unknown => .warn,
            .medium, .low => .allow,
            .critical => .block,
        },
        .ask => switch (severity) {
            .high, .unknown => .ask,
            .medium => .warn,
            .low => .allow,
            .critical => .block,
        },
        .strict, .redteam => switch (severity) {
            .high, .unknown, .medium => .block,
            .low => .allow,
            .critical => .block,
        },
        .ci => switch (severity) {
            .high, .unknown, .medium => .block,
            .low => .allow,
            .critical => .block,
        },
    };
}

/// Human-facing reason when mode softens a daemon deny into allow/warn/ask.
pub fn modeSoftenedReason(mode: policy.schema.Mode, severity: RiskLevel, plugin: PluginDecision) []const u8 {
    _ = severity;
    return switch (plugin) {
        .allow => switch (mode) {
            .observe, .trusted => "allowed in observe; would deny in strict",
            .ask => "allowed in ask mode for low-severity pack hit",
            .strict, .redteam => "allowed in strict for low-severity pack hit",
            .ci => "allowed in ci for low-severity pack hit",
        },
        .warn => switch (mode) {
            .observe, .trusted => "allowed in observe (warn); would deny in strict",
            .ask => "warning in ask mode; would deny in strict",
            else => "allowed with warning; would deny in strict",
        },
        .ask => "requires approval in ask mode; would deny in strict",
        .block => "blocked by Orca policy",
    };
}

const OwnedRunDecision = struct {
    decision: core.decision.Decision,
    owned_reason: []const u8,
    owned_rule_id: ?[]const u8 = null,
    owned_remediation: ?[]const u8 = null,
    /// Typed fail-closed marker for Evaluate transport/engine failures.
    fail_closed: bool = false,

    pub fn deinit(self: OwnedRunDecision, allocator: std.mem.Allocator) void {
        allocator.free(self.owned_reason);
        if (self.owned_rule_id) |rule_id| allocator.free(rule_id);
        if (self.owned_remediation) |remediation| allocator.free(remediation);
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
    // Prefer pack:pattern (e.g. core.git:reset-hard) over bare pattern_name.
    const rule = try rust_visibility.ruleIdFromDaemonResult(allocator, result);
    errdefer if (rule) |rule_name| allocator.free(rule_name);

    const reason = if (rule) |rule_name|
        try std.fmt.allocPrint(allocator, "blocked by Orca rule: {s}", .{rule_name})
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
    mode: policy.schema.Mode,
) !OwnedRunDecision {
    const ci_mode = mode == .ci;
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
            const risk = riskLevelFromDaemonSeverity(daemon.responseStringField(result, "severity"));
            const plugin_decision = pluginDecisionFromModeAndSeverity(mode, risk).applyCiMode(ci_mode);

            if (plugin_decision == .block) {
                const deny = try buildDaemonDenyReason(allocator, result);
                errdefer {
                    allocator.free(deny.reason);
                    if (deny.rule) |rule| allocator.free(rule);
                }
                const remediation = try rust_visibility.remediationFromDaemonResult(allocator, result);
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
                    .owned_remediation = remediation,
                };
            }

            // Mode softens a would-be deny (observe/ask/low-severity paths).
            const rule = try rust_visibility.ruleIdFromDaemonResult(allocator, result);
            errdefer if (rule) |rule_name| allocator.free(rule_name);
            const reason = try allocator.dupe(u8, modeSoftenedReason(mode, risk, plugin_decision));
            errdefer allocator.free(reason);
            const decision_result = decisionResultFromPluginDecision(plugin_decision);
            break :blk OwnedRunDecision{
                .decision = .{
                    .result = decision_result,
                    .rule_id = rule,
                    .reason = reason,
                    .risk_score = risk.toRiskScore(),
                    .requires_user = decision_result == .ask,
                    .ci_may_proceed = decision_result == .allow or decision_result == .observe,
                },
                .owned_reason = reason,
                .owned_rule_id = rule,
            };
        },
        // Engine Error / unexpected shapes are fail-closed via the typed flag on
        // OwnedRunDecision — entrypoints must not re-parse reason strings.
        .error_status => try failClosedEvaluationError(allocator, daemon.responseErrorMessage(result)),
        .pong, .cli_execution, .unknown => try failClosedRunDecision(
            allocator,
            "unexpected daemon response for shell command evaluation",
        ),
    };
}

/// Build a fail-closed decision that owns `owned_reason` (no re-dupe).
fn failClosedOwned(owned_reason: []u8) OwnedRunDecision {
    return .{
        .decision = .{
            .result = .deny,
            .reason = owned_reason,
            .risk_score = RiskLevel.high.toRiskScore(),
            .requires_user = false,
            .ci_may_proceed = false,
        },
        .owned_reason = owned_reason,
        .fail_closed = true,
    };
}

fn failClosedRunDecision(allocator: std.mem.Allocator, reason: []const u8) !OwnedRunDecision {
    return failClosedOwned(try allocator.dupe(u8, reason));
}

/// Human-facing reason for daemon Error status. Always `fail_closed = true` regardless of text.
fn failClosedEvaluationError(allocator: std.mem.Allocator, message: ?[]const u8) !OwnedRunDecision {
    const msg = message orelse return failClosedRunDecision(allocator, "daemon evaluation error");
    // Keep stable prefixes for diagnostics without treating them as a second security authority.
    if (std.mem.startsWith(u8, msg, "daemon evaluation error") or std.mem.startsWith(u8, msg, "daemon unavailable")) {
        return failClosedRunDecision(allocator, msg);
    }
    return failClosedOwned(try std.fmt.allocPrint(allocator, "daemon evaluation error: {s}", .{msg}));
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
            .fail_closed = true,
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

    const translated = try decisionFromDaemonResult(allocator, daemon_response.value.result, effective_mode);

    const explanation = try allocator.dupe(u8, "evaluated by Rust daemon");
    errdefer allocator.free(explanation);

    const owned_reason = translated.owned_reason;
    const owned_rule_id = translated.owned_rule_id;
    const owned_remediation = translated.owned_remediation;

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
        .owned_remediation = owned_remediation,
        .fail_closed = translated.fail_closed,
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
    return mockDaemonResponse(allocator, "{\"id\":1,\"result\":{\"status\":\"Deny\",\"reason\":\"Command denied by evaluator\",\"pack_id\":\"core.filesystem\",\"pattern_name\":\"destructive_rm\",\"severity\":\"critical\",\"explanation\":\"recursive delete of root\",\"suggestions\":[{\"command\":\"rm -rf ./build\",\"description\":\"Limit delete to a project build directory\",\"platform\":\"any\"}]}}");
}

pub fn mockDaemonDenyHighEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    recordMockShellEvent(shell_event);
    return mockDaemonResponse(allocator, "{\"id\":1,\"result\":{\"status\":\"Deny\",\"reason\":\"Command denied by evaluator\",\"pack_id\":\"core.git\",\"pattern_name\":\"force-push\",\"severity\":\"high\",\"explanation\":\"force push rewrites remote history\"}}");
}

pub fn mockDaemonDenyMediumEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    recordMockShellEvent(shell_event);
    return mockDaemonResponse(allocator, "{\"id\":1,\"result\":{\"status\":\"Deny\",\"reason\":\"Command denied by evaluator\",\"pack_id\":\"containers.docker\",\"pattern_name\":\"image-prune\",\"severity\":\"medium\",\"explanation\":\"prunes docker images\"}}");
}

pub fn mockDaemonDenyLowEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    recordMockShellEvent(shell_event);
    return mockDaemonResponse(allocator, "{\"id\":1,\"result\":{\"status\":\"Deny\",\"reason\":\"Command denied by evaluator\",\"pack_id\":\"advisory\",\"pattern_name\":\"noisy-pattern\",\"severity\":\"low\",\"explanation\":\"advisory only\"}}");
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
    try std.testing.expectEqualStrings("core.filesystem:destructive_rm", decision.owned_rule_id.?);
    try std.testing.expect(std.mem.indexOf(u8, decision.owned_reason, "blocked by Orca rule: core.filesystem:destructive_rm") != null);
    try std.testing.expect(decision.owned_remediation != null);
    try std.testing.expect(std.mem.indexOf(u8, decision.owned_remediation.?, "rm -rf ./build") != null);
}

test "shell_eval fail_closed is typed on Evaluate failures only" {
    const allocator = std.testing.allocator;
    const Case = struct {
        evaluator: ShellCommandEvaluatorFn,
        expect_fail_closed: bool,
        reason_sub: ?[]const u8 = null,
    };
    const cases = [_]Case{
        .{ .evaluator = mockDaemonUnavailableEvaluator, .expect_fail_closed = true, .reason_sub = "daemon unavailable" },
        .{ .evaluator = mockDaemonProtocolMismatchEvaluator, .expect_fail_closed = true, .reason_sub = "incompatible daemon protocol" },
        .{ .evaluator = mockDaemonErrorEvaluator, .expect_fail_closed = true, .reason_sub = "daemon evaluation error" },
        .{ .evaluator = mockDaemonDenyEvaluator, .expect_fail_closed = false },
        .{ .evaluator = mockDaemonAllowEvaluator, .expect_fail_closed = false },
    };
    for (cases) |case| {
        var decision = try evaluateCommand(allocator, .strict, &.{ "git", "status" }, null, case.evaluator, null, null);
        defer decision.deinit(allocator);
        try std.testing.expectEqual(case.expect_fail_closed, decision.fail_closed);
        if (case.expect_fail_closed) {
            try std.testing.expectEqual(core.decision.DecisionResult.deny, decision.decision.result);
        }
        if (case.reason_sub) |sub| {
            try std.testing.expect(std.mem.indexOf(u8, decision.decision.reason, sub) != null);
        }
    }
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

test "hook and run parity for safe and dangerous commands" {
    const allocator = std.testing.allocator;

    var safe_run = try evaluateCommand(allocator, .strict, &.{ "git", "status" }, null, mockDaemonAllowEvaluator, null, null);
    defer safe_run.deinit(allocator);
    var safe_daemon = try mockDaemonAllowEvaluator(allocator, .{ .command = "git status", .cwd = null });
    defer safe_daemon.deinit();
    var safe_hook = try decisionFromDaemonResult(allocator, safe_daemon.value.result, .strict);
    defer safe_hook.deinit(allocator);
    try std.testing.expectEqual(safe_run.decision.result, safe_hook.decision.result);

    var dangerous_run = try evaluateCommand(allocator, .strict, &.{ "rm", "-rf", "/" }, null, mockDaemonDenyEvaluator, null, null);
    defer dangerous_run.deinit(allocator);
    var dangerous_daemon = try mockDaemonDenyEvaluator(allocator, .{ .command = "rm -rf /", .cwd = null });
    defer dangerous_daemon.deinit();
    var dangerous_hook = try decisionFromDaemonResult(allocator, dangerous_daemon.value.result, .strict);
    defer dangerous_hook.deinit(allocator);
    try std.testing.expectEqual(dangerous_run.decision.result, dangerous_hook.decision.result);
    try std.testing.expectEqualStrings(dangerous_run.owned_rule_id.?, dangerous_hook.owned_rule_id.?);
}

test "mode x severity matrix maps daemon denials" {
    const allocator = std.testing.allocator;

    const Case = struct {
        mode: policy.schema.Mode,
        evaluator: ShellCommandEvaluatorFn,
        expected: core.decision.DecisionResult,
        reason_substr: ?[]const u8 = null,
    };

    const cases = [_]Case{
        // High severity: observe softens, ask asks, strict/ci deny
        .{ .mode = .observe, .evaluator = mockDaemonDenyHighEvaluator, .expected = .observe, .reason_substr = "allowed in observe" },
        .{ .mode = .ask, .evaluator = mockDaemonDenyHighEvaluator, .expected = .ask, .reason_substr = "requires approval" },
        .{ .mode = .strict, .evaluator = mockDaemonDenyHighEvaluator, .expected = .deny },
        .{ .mode = .ci, .evaluator = mockDaemonDenyHighEvaluator, .expected = .deny },
        // Medium: observe allow, ask warn, strict/ci deny
        .{ .mode = .observe, .evaluator = mockDaemonDenyMediumEvaluator, .expected = .allow, .reason_substr = "allowed in observe" },
        .{ .mode = .ask, .evaluator = mockDaemonDenyMediumEvaluator, .expected = .observe, .reason_substr = "warning in ask" },
        .{ .mode = .strict, .evaluator = mockDaemonDenyMediumEvaluator, .expected = .deny },
        .{ .mode = .ci, .evaluator = mockDaemonDenyMediumEvaluator, .expected = .deny },
        // Low: allow in all modes
        .{ .mode = .observe, .evaluator = mockDaemonDenyLowEvaluator, .expected = .allow },
        .{ .mode = .ask, .evaluator = mockDaemonDenyLowEvaluator, .expected = .allow },
        .{ .mode = .strict, .evaluator = mockDaemonDenyLowEvaluator, .expected = .allow },
        .{ .mode = .ci, .evaluator = mockDaemonDenyLowEvaluator, .expected = .allow },
        // Critical: always deny (even observe)
        .{ .mode = .observe, .evaluator = mockDaemonDenyEvaluator, .expected = .deny },
        .{ .mode = .ask, .evaluator = mockDaemonDenyEvaluator, .expected = .deny },
        .{ .mode = .strict, .evaluator = mockDaemonDenyEvaluator, .expected = .deny },
        .{ .mode = .ci, .evaluator = mockDaemonDenyEvaluator, .expected = .deny },
    };

    for (cases) |case| {
        var decision = try evaluateCommand(allocator, case.mode, &.{ "test", "cmd" }, null, case.evaluator, null, null);
        defer decision.deinit(allocator);
        try std.testing.expectEqual(case.expected, decision.decision.result);
        if (case.reason_substr) |substr| {
            try std.testing.expect(std.mem.indexOf(u8, decision.decision.reason, substr) != null);
        }
    }
}

test "mode matrix: daemon unavailable and engine error deny in observe" {
    const allocator = std.testing.allocator;

    var unavailable = try evaluateCommand(allocator, .observe, &.{ "git", "status" }, null, mockDaemonUnavailableEvaluator, null, null);
    defer unavailable.deinit(allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, unavailable.decision.result);
    try std.testing.expect(unavailable.fail_closed);
    try std.testing.expect(std.mem.indexOf(u8, unavailable.decision.reason, "daemon unavailable") != null);

    var engine_err = try evaluateCommand(allocator, .observe, &.{ "git", "status" }, null, mockDaemonErrorEvaluator, null, null);
    defer engine_err.deinit(allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, engine_err.decision.result);
    try std.testing.expect(engine_err.fail_closed);
    try std.testing.expect(std.mem.indexOf(u8, engine_err.decision.reason, "daemon evaluation error") != null);
}

test "pluginDecisionFromModeAndSeverity table" {
    // High
    try std.testing.expectEqual(PluginDecision.warn, pluginDecisionFromModeAndSeverity(.observe, .high));
    try std.testing.expectEqual(PluginDecision.ask, pluginDecisionFromModeAndSeverity(.ask, .high));
    try std.testing.expectEqual(PluginDecision.block, pluginDecisionFromModeAndSeverity(.strict, .high));
    try std.testing.expectEqual(PluginDecision.block, pluginDecisionFromModeAndSeverity(.ci, .high));
    // Medium
    try std.testing.expectEqual(PluginDecision.allow, pluginDecisionFromModeAndSeverity(.observe, .medium));
    try std.testing.expectEqual(PluginDecision.warn, pluginDecisionFromModeAndSeverity(.ask, .medium));
    try std.testing.expectEqual(PluginDecision.block, pluginDecisionFromModeAndSeverity(.strict, .medium));
    // Critical always block
    try std.testing.expectEqual(PluginDecision.block, pluginDecisionFromModeAndSeverity(.observe, .critical));
    try std.testing.expectEqual(PluginDecision.block, pluginDecisionFromModeAndSeverity(.ask, .critical));
    // Low always allow
    try std.testing.expectEqual(PluginDecision.allow, pluginDecisionFromModeAndSeverity(.ci, .low));
    try std.testing.expectEqual(PluginDecision.allow, pluginDecisionFromModeAndSeverity(.strict, .low));
}

test "mode-softened high severity maps to valid plugin decision vocabulary" {
    const allocator = std.testing.allocator;
    var decision = try evaluateCommand(allocator, .ask, &.{ "git", "push", "--force" }, null, mockDaemonDenyHighEvaluator, null, null);
    defer decision.deinit(allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.ask, decision.decision.result);
    try std.testing.expect(decision.decision.requires_user);
    // Plugin vocabulary: ask stays ask (not invent a new tag)
    try std.testing.expectEqual(PluginDecision.ask, pluginDecisionFromModeAndSeverity(.ask, .high));
    try std.testing.expectEqual(PluginDecision.warn, pluginDecisionFromModeAndSeverity(.observe, .high));
    try std.testing.expectEqual(PluginDecision.block, pluginDecisionFromModeAndSeverity(.strict, .high));
}
