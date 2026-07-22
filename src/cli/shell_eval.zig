//! Shared shell command evaluation for `orca hook`, `orca run`, and shims.
//!
//! Security decisions are owned exclusively by the in-process Zig shell_engine
//! (default / `ORCA_SHELL_EVAL=zig`). `ORCA_SHELL_EVAL=rust` is rejected — the
//! legacy Rust daemon Evaluate backend is no longer a supported product path.

const std = @import("std");

const core = @import("orca_core").core;
const core_api = @import("orca_core").api;
const policy = @import("orca_core").policy;
const intercept = @import("../intercept/mod.zig");
const shell_engine = @import("../shell_engine/mod.zig");
const daemon = @import("daemon.zig");
const rust_visibility = @import("rust_visibility.zig");
const feed_writer = @import("feed_writer.zig");
const pack_config = @import("pack_config.zig");
const supervisor = core.supervisor;

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

pub const ShellEvalBackend = enum { zig, rust };

/// Resolve shell evaluator backend. Default is Zig. `.rust` is detected only so
/// callers can hard-error — it must never select `daemon.evaluate`.
pub fn resolveShellEvalBackend() ShellEvalBackend {
    const value_z = std.c.getenv("ORCA_SHELL_EVAL") orelse return .zig;
    const value = std.mem.span(value_z);
    if (std.ascii.eqlIgnoreCase(value, "rust")) return .rust;
    return .zig;
}

fn resolveEffectiveCwd(allocator: std.mem.Allocator, cwd: ?[]const u8) daemon.DaemonError![]const u8 {
    const path = cwd orelse ".";
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    const resolved_z = std.Io.Dir.cwd().realPathFileAlloc(io, path, allocator) catch return error.InvalidWorkingDirectory;
    defer allocator.free(resolved_z);
    return allocator.dupe(u8, resolved_z) catch error.OutOfMemory;
}

/// Build a daemon-shaped Evaluate JSON response from a Zig shell_engine result.
pub fn synthesizeDaemonResponseFromZig(
    allocator: std.mem.Allocator,
    eval: shell_engine.Evaluation,
) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    const status = switch (eval.decision) {
        .allow => "Allow",
        .deny => "Deny",
    };
    const payload = struct {
        id: u64 = 1,
        result: struct {
            status: []const u8,
            reason: []const u8,
            pack_id: ?[]const u8 = null,
            pattern_name: ?[]const u8 = null,
            severity: []const u8,
            explanation: ?[]const u8 = null,
        },
    }{
        .result = .{
            .status = status,
            .reason = eval.reason,
            .pack_id = eval.pack_id,
            .pattern_name = eval.pattern_name,
            .severity = eval.severity.toString(),
            .explanation = eval.explanation,
        },
    };
    const json_str = std.json.Stringify.valueAlloc(allocator, payload, .{}) catch return error.OutOfMemory;
    defer allocator.free(json_str);
    return std.json.parseFromSlice(daemon.DaemonResponse, allocator, json_str, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) catch return error.ResponseParseFailed;
}

fn zigEvaluator(
    allocator: std.mem.Allocator,
    shell_event: ShellCommandEvent,
) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    // Load cwd-scoped pack config so opt-in packs / disables actually apply.
    // Missing config → baseline only. Unreadable / oversized config fails closed.
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    // Discover enclosing workspace/repo root so nested cwds still load /repo/.orca.toml.
    const cwd_hint = shell_event.cwd orelse ".";
    const workspace = supervisor.resolveWorkspaceRoot(io, allocator, null, cwd_hint) catch cwd_hint;
    defer if (workspace.ptr != cwd_hint.ptr) allocator.free(workspace);
    var packs = pack_config.loadPackIdsForWorkspace(io, allocator, workspace) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.HomeDirectoryNotFound => pack_config.LoadedPackIds{},
        error.FileNotFound => pack_config.LoadedPackIds{},
        else => {
            // Fail closed: do not silently drop opt-in packs under config IO errors.
            const deny_eval = shell_engine.Evaluation{
                .decision = .deny,
                .rule_id = "zig.shell:pack-config",
                .pack_id = "zig.shell",
                .pattern_name = "pack-config-load",
                .severity = .critical,
                .reason = "Pack configuration could not be loaded (fail-closed).",
                .explanation = "Workspace/user pack config was unreadable or invalid; shell evaluation denies.",
                .owned = false,
            };
            return synthesizeDaemonResponseFromZig(allocator, deny_eval);
        },
    };
    defer packs.deinit(allocator);

    var eval = shell_engine.evaluateCommand(allocator, shell_event.command, .{
        .cwd = shell_event.cwd,
        .default_packs_only = true,
        .extra_enabled = packs.enabled,
        .disabled = packs.disabled,
    }) catch return error.OutOfMemory;
    defer eval.deinit(allocator);
    return synthesizeDaemonResponseFromZig(allocator, eval);
}

fn rustEvaluator(
    allocator: std.mem.Allocator,
    shell_event: ShellCommandEvent,
) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    _ = allocator;
    _ = shell_event;
    // Hard error: never call daemon.evaluate for shell security.
    return error.RustShellEvalRemoved;
}

pub fn defaultEvaluator(
    allocator: std.mem.Allocator,
    shell_event: ShellCommandEvent,
) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    return switch (resolveShellEvalBackend()) {
        .zig => zigEvaluator(allocator, shell_event),
        .rust => rustEvaluator(allocator, shell_event),
    };
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

/// Mode × severity matrix for shell denials returned by the Zig shell evaluator.
///
/// Daemon Evaluate returns Allow/Deny with optional pack severity. Orca modes
/// map those engine hits into product outcomes in one place so run/hook/shim
/// stay aligned.
///
/// Mode × severity matrix (plugin vocabulary: allow | warn | ask | block):
///
/// | Mode           | Critical (hard fence) | High / unknown | Medium | Low  |
/// |----------------|-----------------------|----------------|--------|------|
/// | observe/trusted| block (unsoftenable)  | warn           | allow  | allow|
/// | ask            | block (unsoftenable)  | ask            | warn   | allow|
/// | **yolo**       | block (unsoftenable)  | ask            | warn   | allow|
/// | strict/redteam | block (unsoftenable)  | block          | block  | allow|
/// | ci             | block (unsoftenable)  | block          | block  | block|
///
/// **YOLO = seatbelt hero:** first-class mode sharing the **ask** row — agent
/// continues under sandbox + hard fence; rare ask only for high/unknown pack
/// hits. YOLO is **not** refuse-all and **not** disable-security.
///
/// **Hard fence:** critical severity always `PluginDecision.block` for every
/// mode (yolo, ask, strict, …). Catastrophic always-on rules (e.g. root wipe,
/// git reset --hard) cannot be softened by YOLO, sticky, or allowlist.
/// Daemon unavailable is fail-closed deny and is not routed through this matrix.
pub fn pluginDecisionFromModeAndSeverity(mode: policy.schema.Mode, severity: RiskLevel) PluginDecision {
    // Critical / catastrophic: never softened by mode (YOLO cannot unlock).
    if (severity == .critical) return .block;

    return switch (mode) {
        .observe, .trusted => switch (severity) {
            .high, .unknown => .warn,
            .medium, .low => .allow,
            .critical => unreachable,
        },
        // YOLO shares the ask matrix (seatbelt hero).
        .ask, .yolo => switch (severity) {
            .high, .unknown => .ask,
            .medium => .warn,
            .low => .allow,
            .critical => unreachable,
        },
        .strict, .redteam => switch (severity) {
            .high, .unknown, .medium => .block,
            .low => .allow,
            .critical => unreachable,
        },
        .ci => switch (severity) {
            .high, .unknown, .medium, .low => .block,
            .critical => unreachable,
        },
    };
}

/// Mode×severity outcome for daemon Deny, including CI hardening of ask/warn.
pub fn pluginDecisionForDaemonDeny(mode: policy.schema.Mode, severity: RiskLevel) PluginDecision {
    return pluginDecisionFromModeAndSeverity(mode, severity).applyCiMode(mode == .ci);
}

/// Human-facing reason when mode softens a daemon deny into allow/warn/ask.
pub fn modeSoftenedReason(mode: policy.schema.Mode, severity: RiskLevel, plugin: PluginDecision) []const u8 {
    _ = severity;
    return switch (plugin) {
        .allow => switch (mode) {
            .observe, .trusted => "allowed in observe; would deny in strict",
            // YOLO shares ask soft-allow messaging (seatbelt, not refuse-all).
            .ask, .yolo => "allowed in ask mode for low-severity pack hit",
            .strict, .redteam => "allowed in strict for low-severity pack hit",
            // CI never softens Deny to allow (matrix always blocks); keep exhaustive.
            .ci => unreachable,
        },
        .warn => switch (mode) {
            .observe, .trusted => "allowed in observe (warn); would deny in strict",
            .ask, .yolo => "warning in ask mode; would deny in strict",
            else => "allowed with warning; would deny in strict",
        },
        .ask => "requires approval in ask mode; would deny in strict",
        .block => "blocked by Orca policy",
    };
}

// ---------------------------------------------------------------------------
// WP2 — Strict permit-list refuse (post hard-fence)
//
// Evaluation order (product path; sticky wired separately in WP4):
//   hard fence (critical) → sticky → strict refuse → mode×severity
//
// CRITICAL: do **not** use shell_engine.evaluateCommand options.allowlists —
// that path allows *before* packs and can unlock catastrophe. Permit matching
// here reuses shell_engine.allowlist.Layered as a pure matcher only.
// ---------------------------------------------------------------------------

/// Reason substring for Strict off-list refuse (deny, never ask).
pub const strict_not_on_allowlist_reason = "strict: not on allowlist";

/// Product decision after hard fence / strict refuse / mode×severity.
pub const AfterHardFenceDecision = struct {
    decision: PluginDecision,
    /// Static reason when hard-fence or strict-refuse applied; null for plain matrix.
    reason: ?[]const u8 = null,
};

/// Modes that apply configured shell permit-list refuse (Strict + redteam).
pub fn isStrictPermitMode(mode: policy.schema.Mode) bool {
    return switch (mode) {
        .strict, .redteam => true,
        else => false,
    };
}

/// Exact/prefix permit match via shell_engine.allowlist.Layered (post-hard-fence only).
pub fn commandOnPermitList(command: []const u8, permit: shell_engine.allowlist.Layered) bool {
    return permit.allows(command);
}

/// If Strict-like mode has a **non-empty** permit list and `command` is off-list,
/// returns `.block` (refuse). Returns `null` when refuse does not apply so the
/// caller continues to mode×severity.
///
/// Does **not** inspect severity — hard fence must be checked first by
/// `decideAfterHardFence` (or the host wiring).
pub fn strictRefuseIfOffList(
    mode: policy.schema.Mode,
    command: []const u8,
    permit: shell_engine.allowlist.Layered,
) ?PluginDecision {
    if (!isStrictPermitMode(mode)) return null;
    if (permit.entries.len == 0) return null;
    if (commandOnPermitList(command, permit)) return null;
    return .block;
}

/// Post-hard-fence product decision for unit tests and WP4 host wiring:
/// 1. critical severity → always `block` (hard fence; reason is not strict refuse)
/// 2. strict/redteam + non-empty permit + off-list → `block` + `strict: not on allowlist`
/// 3. else mode×severity matrix
///
/// `permit` with zero entries disables the refuse step (matrix-only Strict).
pub fn decideAfterHardFence(
    mode: policy.schema.Mode,
    severity: RiskLevel,
    command: []const u8,
    permit: shell_engine.allowlist.Layered,
) AfterHardFenceDecision {
    // 1. Hard fence always wins — even if command is on the permit list.
    if (severity == .critical) {
        return .{
            .decision = .block,
            .reason = "blocked by Orca policy",
        };
    }

    // 2. Strict refuse off-list (never ask-spam).
    if (strictRefuseIfOffList(mode, command, permit) != null) {
        return .{
            .decision = .block,
            .reason = strict_not_on_allowlist_reason,
        };
    }

    // 3. Mode × severity (on-list does not auto-allow high/medium under strict).
    return .{
        .decision = pluginDecisionFromModeAndSeverity(mode, severity),
        .reason = null,
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
    // Missing severity on Deny must not soften: treat as critical so observe/ask
    // cannot warn-allow catastrophic hits that omitted the field.
    const value = severity orelse return .critical;
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
            // Align with hook.zig: daemon allow reasons may embed command fragments / secrets.
            const reason = try core_api.redactAlloc(
                allocator,
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
            const plugin_decision = pluginDecisionForDaemonDeny(mode, risk);

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
    // Redact before surfacing: Error messages may embed command fragments or secret-like tokens.
    // Keep stable prefixes for diagnostics without treating them as a second security authority.
    if (std.mem.startsWith(u8, msg, "daemon evaluation error") or std.mem.startsWith(u8, msg, "daemon unavailable")) {
        return failClosedOwned(try core_api.redactAlloc(allocator, msg));
    }
    const formatted = try std.fmt.allocPrint(allocator, "daemon evaluation error: {s}", .{msg});
    defer allocator.free(formatted);
    return failClosedOwned(try core_api.redactAlloc(allocator, formatted));
}

pub fn failClosedDaemonUnavailableDecision(allocator: std.mem.Allocator, err: daemon.DaemonError) !OwnedRunDecision {
    return failClosedRunDecision(allocator, daemonUnavailableReason(err));
}

/// Evaluate a shell command via Zig `shell_engine` and return a run/shim `CommandDecision`.
/// `ORCA_SHELL_EVAL=rust` fails closed (`RustShellEvalRemoved`) without daemon Evaluate.
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
        // Free owned decision if explanation allocation fails before transfer.
        errdefer unavailable.deinit(allocator);
        const unavailable_msg: []const u8 = if (resolveShellEvalBackend() == .zig and evaluator_override == null)
            "evaluated by Zig shell_engine (unavailable)"
        else
            "evaluated by shell evaluator (unavailable)";
        const explanation = try allocator.dupe(u8, unavailable_msg);
        errdefer allocator.free(explanation);
        // Success: transfer owned_reason; errdefer deinit does not run.
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
        if (resolveShellEvalBackend() == .zig and evaluator_override == null) {
            break :blk try allocator.dupe(u8, "zig");
        }
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
    // Free owned decision if explanation allocation fails before transfer.
    errdefer translated.deinit(allocator);

    const success_msg: []const u8 = if (resolveShellEvalBackend() == .zig and evaluator_override == null)
        "evaluated by Zig shell_engine"
    else
        "evaluated by shell evaluator";
    const explanation = try allocator.dupe(u8, success_msg);
    errdefer allocator.free(explanation);

    // Success: transfer owned fields; errdefer deinit does not run.
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

fn mockDaemonDenyPackHitEvaluator(
    allocator: std.mem.Allocator,
    shell_event: ShellCommandEvent,
    pack_id: []const u8,
    pattern_name: []const u8,
    severity_field: ?[]const u8,
    explanation: []const u8,
) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    recordMockShellEvent(shell_event);
    const json = if (severity_field) |severity| blk: {
        break :blk try std.fmt.allocPrint(
            allocator,
            "{{\"id\":1,\"result\":{{\"status\":\"Deny\",\"reason\":\"Command denied by evaluator\",\"pack_id\":\"{s}\",\"pattern_name\":\"{s}\",\"severity\":\"{s}\",\"explanation\":\"{s}\"}}}}",
            .{ pack_id, pattern_name, severity, explanation },
        );
    } else blk: {
        break :blk try std.fmt.allocPrint(
            allocator,
            "{{\"id\":1,\"result\":{{\"status\":\"Deny\",\"reason\":\"Command denied by evaluator\",\"pack_id\":\"{s}\",\"pattern_name\":\"{s}\",\"explanation\":\"{s}\"}}}}",
            .{ pack_id, pattern_name, explanation },
        );
    };
    defer allocator.free(json);
    return mockDaemonResponse(allocator, json);
}

pub fn mockDaemonDenyHighEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    return mockDaemonDenyPackHitEvaluator(allocator, shell_event, "core.git", "force-push", "high", "force push rewrites remote history");
}

pub fn mockDaemonDenyMediumEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    return mockDaemonDenyPackHitEvaluator(allocator, shell_event, "containers.docker", "image-prune", "medium", "prunes docker images");
}

pub fn mockDaemonDenyLowEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    return mockDaemonDenyPackHitEvaluator(allocator, shell_event, "advisory", "noisy-pattern", "low", "advisory only");
}

pub fn mockDaemonDenyUnknownSeverityEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    return mockDaemonDenyPackHitEvaluator(allocator, shell_event, "core.git", "unclassified-hit", "bogus", "unrecognized severity string");
}

pub fn mockDaemonDenyMissingSeverityEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    return mockDaemonDenyPackHitEvaluator(allocator, shell_event, "core.git", "missing-severity", null, "severity field omitted");
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

fn mockDaemonAllowWithSecretReasonEvaluator(
    allocator: std.mem.Allocator,
    shell_event: ShellCommandEvent,
) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    recordMockShellEvent(shell_event);
    return mockDaemonResponse(
        allocator,
        "{\"id\":1,\"result\":{\"status\":\"Allow\",\"reason\":\"allowed; OPENAI_API_KEY=sk-fakeSyntheticOpenAIKey1234567890\"}}",
    );
}

fn mockDaemonErrorWithSecretMessageEvaluator(
    allocator: std.mem.Allocator,
    shell_event: ShellCommandEvent,
) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    _ = shell_event;
    return mockDaemonResponse(
        allocator,
        "{\"id\":1,\"result\":{\"status\":\"Error\",\"message\":\"eval failed token=sk-fakeSyntheticOpenAIKey1234567890\"}}",
    );
}

test "shell_eval redacts secrets in allow reasons and evaluation errors" {
    const allocator = std.testing.allocator;

    var allowed = try evaluateCommand(
        allocator,
        .strict,
        &.{ "git", "status" },
        null,
        mockDaemonAllowWithSecretReasonEvaluator,
        null,
        null,
    );
    defer allowed.deinit(allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.allow, allowed.decision.result);
    try std.testing.expect(std.mem.indexOf(u8, allowed.owned_reason, "sk-fakeSyntheticOpenAIKey1234567890") == null);
    try std.testing.expect(std.mem.indexOf(u8, allowed.owned_reason, "[REDACTED]") != null);

    var engine_err = try evaluateCommand(
        allocator,
        .observe,
        &.{ "git", "status" },
        null,
        mockDaemonErrorWithSecretMessageEvaluator,
        null,
        null,
    );
    defer engine_err.deinit(allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, engine_err.decision.result);
    try std.testing.expect(engine_err.fail_closed);
    try std.testing.expect(std.mem.indexOf(u8, engine_err.owned_reason, "sk-fakeSyntheticOpenAIKey1234567890") == null);
    try std.testing.expect(std.mem.indexOf(u8, engine_err.owned_reason, "daemon evaluation error") != null);
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

extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;

fn restoreShellEvalEnv(previous: ?[*:0]const u8) void {
    if (previous) |value| {
        _ = setenv("ORCA_SHELL_EVAL", value, 1);
    } else {
        _ = unsetenv("ORCA_SHELL_EVAL");
    }
}

test "resolveShellEvalBackend defaults to zig when unset" {
    const previous = std.c.getenv("ORCA_SHELL_EVAL");
    defer restoreShellEvalEnv(previous);
    _ = unsetenv("ORCA_SHELL_EVAL");
    try std.testing.expectEqual(ShellEvalBackend.zig, resolveShellEvalBackend());
}

test "ORCA_SHELL_EVAL=rust rejects without daemon evaluate" {
    const allocator = std.testing.allocator;
    const previous = std.c.getenv("ORCA_SHELL_EVAL");
    defer restoreShellEvalEnv(previous);
    try std.testing.expectEqual(@as(c_int, 0), setenv("ORCA_SHELL_EVAL", "rust", 1));
    try std.testing.expectEqual(ShellEvalBackend.rust, resolveShellEvalBackend());
    try std.testing.expectError(
        error.RustShellEvalRemoved,
        defaultEvaluator(allocator, .{ .command = "git status", .cwd = null }),
    );
    try std.testing.expectEqualStrings(
        "ORCA_SHELL_EVAL=rust is no longer supported; Zig shell_engine is the sole Evaluate authority",
        daemonUnavailableReason(error.RustShellEvalRemoved),
    );
}

test "default zig evaluator denies destructive rm via shell_engine" {
    const allocator = std.testing.allocator;
    const previous = std.c.getenv("ORCA_SHELL_EVAL");
    defer restoreShellEvalEnv(previous);
    _ = unsetenv("ORCA_SHELL_EVAL");
    try std.testing.expectEqual(ShellEvalBackend.zig, resolveShellEvalBackend());

    var parsed = try defaultEvaluator(allocator, .{ .command = "rm -rf /", .cwd = null });
    defer parsed.deinit();
    try std.testing.expectEqual(daemon.ResponseStatus.deny, daemon.responseStatus(parsed.value.result));
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
        // Low: CI preserves the daemon denial while interactive modes may soften it.
        .{ .mode = .observe, .evaluator = mockDaemonDenyLowEvaluator, .expected = .allow },
        .{ .mode = .ask, .evaluator = mockDaemonDenyLowEvaluator, .expected = .allow },
        .{ .mode = .strict, .evaluator = mockDaemonDenyLowEvaluator, .expected = .allow },
        .{ .mode = .ci, .evaluator = mockDaemonDenyLowEvaluator, .expected = .deny },
        // Critical: always deny (even observe)
        .{ .mode = .observe, .evaluator = mockDaemonDenyEvaluator, .expected = .deny },
        .{ .mode = .ask, .evaluator = mockDaemonDenyEvaluator, .expected = .deny },
        .{ .mode = .strict, .evaluator = mockDaemonDenyEvaluator, .expected = .deny },
        .{ .mode = .ci, .evaluator = mockDaemonDenyEvaluator, .expected = .deny },
        // Unknown severity string follows high (warn in observe); omitted severity is critical (never softens).
        .{ .mode = .observe, .evaluator = mockDaemonDenyUnknownSeverityEvaluator, .expected = .observe },
        .{ .mode = .strict, .evaluator = mockDaemonDenyUnknownSeverityEvaluator, .expected = .deny },
        .{ .mode = .ci, .evaluator = mockDaemonDenyUnknownSeverityEvaluator, .expected = .deny },
        .{ .mode = .observe, .evaluator = mockDaemonDenyMissingSeverityEvaluator, .expected = .deny },
        .{ .mode = .strict, .evaluator = mockDaemonDenyMissingSeverityEvaluator, .expected = .deny },
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

test "pluginDecisionFromModeAndSeverity mode groups x severity" {
    const Row = struct {
        severity: RiskLevel,
        observe_like: PluginDecision,
        ask: PluginDecision,
        strict_like: PluginDecision,
        ci: PluginDecision,
    };

    const rows = [_]Row{
        .{ .severity = .critical, .observe_like = .block, .ask = .block, .strict_like = .block, .ci = .block },
        .{ .severity = .high, .observe_like = .warn, .ask = .ask, .strict_like = .block, .ci = .block },
        .{ .severity = .unknown, .observe_like = .warn, .ask = .ask, .strict_like = .block, .ci = .block },
        .{ .severity = .medium, .observe_like = .allow, .ask = .warn, .strict_like = .block, .ci = .block },
        .{ .severity = .low, .observe_like = .allow, .ask = .allow, .strict_like = .allow, .ci = .block },
    };

    const observe_modes = [_]policy.schema.Mode{ .observe, .trusted };
    // YOLO shares the ask matrix (seatbelt hero — not refuse-all).
    const ask_like_modes = [_]policy.schema.Mode{ .ask, .yolo };
    const strict_modes = [_]policy.schema.Mode{ .strict, .redteam };

    for (rows) |row| {
        for (observe_modes) |mode| {
            try std.testing.expectEqual(row.observe_like, pluginDecisionFromModeAndSeverity(mode, row.severity));
        }
        for (ask_like_modes) |mode| {
            try std.testing.expectEqual(row.ask, pluginDecisionFromModeAndSeverity(mode, row.severity));
        }
        for (strict_modes) |mode| {
            try std.testing.expectEqual(row.strict_like, pluginDecisionFromModeAndSeverity(mode, row.severity));
        }
        try std.testing.expectEqual(row.ci, pluginDecisionFromModeAndSeverity(.ci, row.severity));
    }

    // Security invariants: observe ≠ strict for high; ci never softens pack hits to allow.
    try std.testing.expect(pluginDecisionFromModeAndSeverity(.observe, .high) != pluginDecisionFromModeAndSeverity(.strict, .high));
    for ([_]RiskLevel{ .critical, .high, .medium, .low, .unknown }) |severity| {
        try std.testing.expect(pluginDecisionForDaemonDeny(.ci, severity) != .allow);
        try std.testing.expectEqual(PluginDecision.block, pluginDecisionForDaemonDeny(.ci, severity));
    }
}

test "Mode.parse yolo is first-class and shares ask core mapping" {
    // Monopath gate exercises shell_eval tests reliably; restate schema contract here.
    try std.testing.expectEqual(policy.schema.Mode.yolo, policy.schema.Mode.parse("yolo").?);
    try std.testing.expectEqualStrings("yolo", policy.schema.Mode.yolo.toString());
    try std.testing.expectEqual(core.types.Mode.ask, policy.schema.Mode.yolo.toCoreMode());
    try std.testing.expect(!policy.schema.Mode.yolo.isEnforcing());
}

test "hard fence: critical severity always block for yolo ask and strict" {
    // YOLO / ask / strict cannot soften catastrophic (hard fence) hits.
    const hard_fence_modes = [_]policy.schema.Mode{ .yolo, .ask, .strict };
    for (hard_fence_modes) |mode| {
        try std.testing.expectEqual(PluginDecision.block, pluginDecisionFromModeAndSeverity(mode, .critical));
        try std.testing.expectEqual(PluginDecision.block, pluginDecisionForDaemonDeny(mode, .critical));
    }
}

test "yolo severity matrix matches ask not refuse-all" {
    // High/unknown → ask; medium → warn; low → allow (same as ask).
    try std.testing.expectEqual(PluginDecision.ask, pluginDecisionFromModeAndSeverity(.yolo, .high));
    try std.testing.expectEqual(PluginDecision.ask, pluginDecisionFromModeAndSeverity(.yolo, .unknown));
    try std.testing.expectEqual(PluginDecision.warn, pluginDecisionFromModeAndSeverity(.yolo, .medium));
    try std.testing.expectEqual(PluginDecision.allow, pluginDecisionFromModeAndSeverity(.yolo, .low));
    // Not refuse-all: high under yolo is ask, under strict is block.
    try std.testing.expect(pluginDecisionFromModeAndSeverity(.yolo, .high) != pluginDecisionFromModeAndSeverity(.strict, .high));
    try std.testing.expectEqual(pluginDecisionFromModeAndSeverity(.ask, .high), pluginDecisionFromModeAndSeverity(.yolo, .high));
    try std.testing.expectEqual(pluginDecisionFromModeAndSeverity(.ask, .medium), pluginDecisionFromModeAndSeverity(.yolo, .medium));
    try std.testing.expectEqual(pluginDecisionFromModeAndSeverity(.ask, .low), pluginDecisionFromModeAndSeverity(.yolo, .low));
}

test "modeSoftenedReason handles yolo like ask" {
    try std.testing.expectEqualStrings(
        modeSoftenedReason(.ask, .low, .allow),
        modeSoftenedReason(.yolo, .low, .allow),
    );
    try std.testing.expectEqualStrings(
        modeSoftenedReason(.ask, .medium, .warn),
        modeSoftenedReason(.yolo, .medium, .warn),
    );
    // ask plugin decision reason is mode-agnostic string today; still exercise path.
    try std.testing.expectEqualStrings(
        modeSoftenedReason(.ask, .high, .ask),
        modeSoftenedReason(.yolo, .high, .ask),
    );
}

// --- WP2 Strict refuse (post hard-fence) ---
// Pure helpers: hard fence → strict off-list refuse → mode×severity.
// Do NOT use shell_engine.evaluateCommand options.allowlists (pre-pack short-circuit).

test "strict refuse table: post hard-fence permit list" {
    const git_only: shell_engine.allowlist.Layered = .{
        .entries = &.{.{ .pattern = "git status" }},
    };
    const empty: shell_engine.allowlist.Layered = .{ .entries = &.{} };

    const Row = struct {
        mode: policy.schema.Mode,
        permit: shell_engine.allowlist.Layered,
        command: []const u8,
        /// Engine-derived severity (critical = hard fence hit).
        severity: RiskLevel,
        expected: PluginDecision,
        /// When non-null, reason must contain this substring.
        reason_contains: ?[]const u8 = null,
        /// When true, refuse reason must NOT appear (hard fence wins over off-list).
        reason_not_contains: ?[]const u8 = null,
    };

    const rows = [_]Row{
        // On-list + safe (low / no pack hit path) → allow under strict matrix.
        .{
            .mode = .strict,
            .permit = git_only,
            .command = "git status",
            .severity = .low,
            .expected = .allow,
        },
        // Off-list under strict with configured list → refuse (deny, not ask).
        .{
            .mode = .strict,
            .permit = git_only,
            .command = "npm test",
            .severity = .low,
            .expected = .block,
            .reason_contains = "strict: not on allowlist",
        },
        // Hard fence: critical always block; refuse string is not the driver.
        .{
            .mode = .strict,
            .permit = git_only,
            .command = "rm -rf /",
            .severity = .critical,
            .expected = .block,
            .reason_not_contains = "strict: not on allowlist",
        },
        // Even when catastrophic command is ON the permit list, hard fence wins.
        .{
            .mode = .strict,
            .permit = .{ .entries = &.{.{ .pattern = "rm -rf /" }} },
            .command = "rm -rf /",
            .severity = .critical,
            .expected = .block,
            .reason_not_contains = "strict: not on allowlist",
        },
        // yolo/ask without list: npm test is NOT refuse.
        .{
            .mode = .yolo,
            .permit = empty,
            .command = "npm test",
            .severity = .low,
            .expected = .allow,
        },
        .{
            .mode = .ask,
            .permit = empty,
            .command = "npm test",
            .severity = .low,
            .expected = .allow,
        },
        // yolo/ask: hard fence still deny.
        .{
            .mode = .yolo,
            .permit = empty,
            .command = "rm -rf /",
            .severity = .critical,
            .expected = .block,
        },
        .{
            .mode = .ask,
            .permit = empty,
            .command = "rm -rf /",
            .severity = .critical,
            .expected = .block,
        },
        // redteam is strict-like for permit refuse.
        .{
            .mode = .redteam,
            .permit = git_only,
            .command = "npm test",
            .severity = .low,
            .expected = .block,
            .reason_contains = "strict: not on allowlist",
        },
        // Strict with empty permit list: refuse step skipped (matrix only — low allow).
        .{
            .mode = .strict,
            .permit = empty,
            .command = "npm test",
            .severity = .low,
            .expected = .allow,
        },
    };

    for (rows) |row| {
        const out = decideAfterHardFence(row.mode, row.severity, row.command, row.permit);
        try std.testing.expectEqual(row.expected, out.decision);
        if (row.reason_contains) |needle| {
            const reason = out.reason orelse {
                std.debug.print("expected reason containing '{s}' for cmd={s}\n", .{ needle, row.command });
                return error.TestExpectedEqual;
            };
            try std.testing.expect(std.mem.indexOf(u8, reason, needle) != null);
        }
        if (row.reason_not_contains) |needle| {
            if (out.reason) |reason| {
                try std.testing.expect(std.mem.indexOf(u8, reason, needle) == null);
            }
        }
    }
}

test "strictRefuseIfOffList only fires for strict-like with non-empty permit" {
    const permit: shell_engine.allowlist.Layered = .{
        .entries = &.{
            .{ .pattern = "git status" },
            .{ .pattern = "npm run ", .prefix = true },
        },
    };
    const empty: shell_engine.allowlist.Layered = .{ .entries = &.{} };

    // Off-list strict → refuse block.
    try std.testing.expectEqual(
        @as(?PluginDecision, .block),
        strictRefuseIfOffList(.strict, "npm test", permit),
    );
    try std.testing.expectEqual(
        @as(?PluginDecision, .block),
        strictRefuseIfOffList(.redteam, "curl evil.com", permit),
    );
    // On-list exact + prefix → no refuse.
    try std.testing.expectEqual(
        @as(?PluginDecision, null),
        strictRefuseIfOffList(.strict, "git status", permit),
    );
    try std.testing.expectEqual(
        @as(?PluginDecision, null),
        strictRefuseIfOffList(.strict, "npm run test", permit),
    );
    // Non-strict modes never refuse via permit list.
    try std.testing.expectEqual(
        @as(?PluginDecision, null),
        strictRefuseIfOffList(.yolo, "npm test", permit),
    );
    try std.testing.expectEqual(
        @as(?PluginDecision, null),
        strictRefuseIfOffList(.ask, "npm test", permit),
    );
    try std.testing.expectEqual(
        @as(?PluginDecision, null),
        strictRefuseIfOffList(.observe, "npm test", permit),
    );
    // Empty permit: refuse disabled (matrix handles severity alone).
    try std.testing.expectEqual(
        @as(?PluginDecision, null),
        strictRefuseIfOffList(.strict, "npm test", empty),
    );
}

test "commandOnPermitList exact and prefix match" {
    const permit: shell_engine.allowlist.Layered = .{
        .entries = &.{
            .{ .pattern = "git status" },
            .{ .pattern = "npm run ", .prefix = true },
        },
    };
    try std.testing.expect(commandOnPermitList("git status", permit));
    try std.testing.expect(commandOnPermitList("  git status  ", permit));
    try std.testing.expect(commandOnPermitList("npm run test", permit));
    try std.testing.expect(!commandOnPermitList("npm test", permit));
    try std.testing.expect(!commandOnPermitList("git reset --hard", permit));
}

test "riskLevelFromDaemonSeverity maps null to critical and nonsense to unknown" {
    try std.testing.expectEqual(RiskLevel.critical, riskLevelFromDaemonSeverity(null));
    try std.testing.expectEqual(RiskLevel.high, riskLevelFromDaemonSeverity("HIGH"));
    try std.testing.expectEqual(RiskLevel.critical, riskLevelFromDaemonSeverity("Critical"));
    try std.testing.expectEqual(RiskLevel.medium, riskLevelFromDaemonSeverity("medium"));
    try std.testing.expectEqual(RiskLevel.low, riskLevelFromDaemonSeverity("low"));
    try std.testing.expectEqual(RiskLevel.unknown, riskLevelFromDaemonSeverity("bogus"));
    try std.testing.expectEqual(RiskLevel.unknown, riskLevelFromDaemonSeverity(""));
}

test "PluginDecision.applyCiMode hardens ask and warn only" {
    try std.testing.expectEqual(PluginDecision.block, PluginDecision.ask.applyCiMode(true));
    try std.testing.expectEqual(PluginDecision.block, PluginDecision.warn.applyCiMode(true));
    try std.testing.expectEqual(PluginDecision.ask, PluginDecision.ask.applyCiMode(false));
    try std.testing.expectEqual(PluginDecision.warn, PluginDecision.warn.applyCiMode(false));
    try std.testing.expectEqual(PluginDecision.allow, PluginDecision.allow.applyCiMode(true));
    try std.testing.expectEqual(PluginDecision.block, PluginDecision.block.applyCiMode(true));
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

test "zigEvaluator applies opt-in packs from cwd .orca.toml" {
    const allocator = std.testing.allocator;

    // Clean project workspace without pack config → baseline allows docker prune.
    var baseline_tmp = std.testing.tmpDir(.{});
    defer baseline_tmp.cleanup();
    try baseline_tmp.dir.createDirPath(std.testing.io, ".git");
    const baseline_root = try baseline_tmp.dir.realPathFileAlloc(std.testing.io, ".", allocator);
    defer allocator.free(baseline_root);
    {
        var parsed = try zigEvaluator(allocator, .{
            .command = "docker system prune",
            .cwd = baseline_root,
        });
        defer parsed.deinit();
        try std.testing.expectEqual(daemon.ResponseStatus.allow, daemon.responseStatus(parsed.value.result));
    }

    // Project config enables containers.docker → deny.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, ".git");
    const body =
        \\[packs]
        \\enabled = ["containers.docker"]
        \\
    ;
    const file = try tmp.dir.createFile(std.testing.io, ".orca.toml", .{});
    defer file.close(std.testing.io);
    try file.writeStreamingAll(std.testing.io, body);

    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", allocator);
    defer allocator.free(root);
    {
        var parsed = try zigEvaluator(allocator, .{
            .command = "docker system prune",
            .cwd = root,
        });
        defer parsed.deinit();
        try std.testing.expectEqual(daemon.ResponseStatus.deny, daemon.responseStatus(parsed.value.result));
    }

    // Nested working directory under the repo must still load /repo/.orca.toml.
    try tmp.dir.createDirPath(std.testing.io, "src/nested");
    const nested = try tmp.dir.realPathFileAlloc(std.testing.io, "src/nested", allocator);
    defer allocator.free(nested);
    {
        var parsed = try zigEvaluator(allocator, .{
            .command = "docker system prune",
            .cwd = nested,
        });
        defer parsed.deinit();
        try std.testing.expectEqual(daemon.ResponseStatus.deny, daemon.responseStatus(parsed.value.result));
    }
}
