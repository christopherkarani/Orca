const std = @import("std");
const core = @import("orca_core").core;
const supervisor = core.supervisor;
const core_api = @import("orca_core").api;
const policy = @import("orca_core").policy;

const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");
const daemon = @import("daemon.zig");
const shell_eval = @import("shell_eval.zig");
const rust_visibility = @import("rust_visibility.zig");
const feed_writer = @import("feed_writer.zig");

// Maximum JSON payload size to prevent memory exhaustion from hostile hosts.
const max_payload_len = 256 * 1024; // 256 KiB

// ---------------------------------------------------------------------------
// Hook evaluator dispatch (Phase 2E)
//
// PreToolUse shell-command events route to the Rust daemon `Evaluate` method.
// All other events (prompt, permission, session, stop, post-tool, informational,
// and non-shell PreToolUse) stay on the existing Zig policy path.
//
// Invariants:
// - No shell-command PreToolUse may fall back to Zig native command evaluation.
// - Daemon transport or protocol failures for shell commands fail closed (deny).
// - Non-shell tools with incidental `command` fields stay on the Zig path.
// - Shell tools with missing/invalid command fields fail closed before evaluation.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Top-level dispatch
// ---------------------------------------------------------------------------

pub fn command(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len > 0 and (std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h"))) {
        _ = try help.writeCommand(io, stdout, "hook");
        return exit_codes.success;
    }
    if (argv.len == 0) {
        _ = try help.writeCommand(io, stdout, "hook");
        return exit_codes.usage;
    }

    const host = Host.parse(argv[0]) orelse {
        try stderr.print("orca hook: unknown host '{s}'. Expected codex, claude, opencode, openclaw, or hermes.\n", .{argv[0]});
        return exit_codes.usage;
    };

    if (argv.len < 2) {
        try stderr.writeAll("orca hook: expected event name.\n");
        return exit_codes.usage;
    }

    // For OpenCode and OpenClaw, map dot-separated event names to internal events
    const event_name = argv[1];
    const event = if (host == .opencode)
        mapOpenCodeEvent(event_name) orelse {
            // If mapOpenCodeEvent returns null, it may be an informational event
            if (isOpenCodeInformationalEvent(event_name)) {
                return hookCommand(io, host, .SessionStart, event_name, argv[2..], stdout, stderr);
            }
            try stderr.print("orca hook: unknown OpenCode event '{s}'.\n", .{event_name});
            return exit_codes.usage;
        }
    else if (host == .openclaw)
        mapOpenClawEvent(event_name) orelse {
            // If mapOpenClawEvent returns null, it may be an informational event
            if (isOpenClawInformationalEvent(event_name)) {
                return hookCommand(io, host, .SessionStart, event_name, argv[2..], stdout, stderr);
            }
            try stderr.print("orca hook: unknown OpenClaw event '{s}'.\n", .{event_name});
            return exit_codes.usage;
        }
    else if (host == .hermes)
        mapHermesEvent(event_name) orelse {
            if (isHermesInformationalEvent(event_name)) {
                return hookCommand(io, host, .SessionStart, event_name, argv[2..], stdout, stderr);
            }
            try stderr.print("orca hook: unknown Hermes event '{s}'.\n", .{event_name});
            return exit_codes.usage;
        }
    else
        Event.parse(event_name) orelse {
            try stderr.print("orca hook: unknown event '{s}'.\n", .{event_name});
            return exit_codes.usage;
        };

    return hookCommand(io, host, event, event_name, argv[2..], stdout, stderr);
}

// ---------------------------------------------------------------------------
// Host and event types
// ---------------------------------------------------------------------------

const Host = enum {
    codex,
    claude,
    opencode,
    openclaw,
    hermes,

    pub fn parse(value: []const u8) ?Host {
        if (std.mem.eql(u8, value, "codex")) return .codex;
        if (std.mem.eql(u8, value, "claude")) return .claude;
        if (std.mem.eql(u8, value, "opencode")) return .opencode;
        if (std.mem.eql(u8, value, "openclaw")) return .openclaw;
        if (std.mem.eql(u8, value, "hermes") or std.mem.eql(u8, value, "hermess")) return .hermes;
        return null;
    }
};

const Event = enum {
    SessionStart,
    UserPromptSubmit,
    PreToolUse,
    PermissionRequest,
    PostToolUse,
    Stop,
    SessionEnd,

    pub fn parse(value: []const u8) ?Event {
        inline for (@typeInfo(Event).@"enum".fields) |field| {
            if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
        }
        return null;
    }
};

// OpenCode uses dot-separated event names. Map them to internal events.
// Some OpenCode events are purely informational and do not have a matching
// internal evaluation path; those are handled as informational in hookCommand.
fn mapOpenCodeEvent(event_name: []const u8) ?Event {
    if (std.mem.eql(u8, event_name, "session.created")) return .SessionStart;
    if (std.mem.eql(u8, event_name, "tool.execute.before")) return .PreToolUse;
    if (std.mem.eql(u8, event_name, "tool.execute.after")) return .PostToolUse;
    if (std.mem.eql(u8, event_name, "permission.asked")) return .PermissionRequest;
    if (std.mem.eql(u8, event_name, "permission.replied")) return null; // informational
    if (std.mem.eql(u8, event_name, "file.edited")) return null; // informational
    if (std.mem.eql(u8, event_name, "command.executed")) return null; // informational
    if (std.mem.eql(u8, event_name, "session.updated")) return null; // informational
    if (std.mem.eql(u8, event_name, "session.idle")) return null; // informational
    if (std.mem.eql(u8, event_name, "session.error")) return null; // informational
    if (std.mem.eql(u8, event_name, "shell.env")) return null; // informational
    return null;
}

// Check if an OpenCode event is purely informational (no policy evaluation needed)
fn isOpenCodeInformationalEvent(event_name: []const u8) bool {
    return std.mem.eql(u8, event_name, "permission.replied") or
        std.mem.eql(u8, event_name, "file.edited") or
        std.mem.eql(u8, event_name, "command.executed") or
        std.mem.eql(u8, event_name, "session.updated") or
        std.mem.eql(u8, event_name, "session.idle") or
        std.mem.eql(u8, event_name, "session.error") or
        std.mem.eql(u8, event_name, "shell.env");
}

// OpenClaw uses dot-separated event names. Map them to internal events.
fn mapOpenClawEvent(event_name: []const u8) ?Event {
    if (std.mem.eql(u8, event_name, "session.start")) return .SessionStart;
    if (std.mem.eql(u8, event_name, "tool.before")) return .PreToolUse;
    if (std.mem.eql(u8, event_name, "tool.after")) return .PostToolUse;
    if (std.mem.eql(u8, event_name, "permission.before")) return .PermissionRequest;
    if (std.mem.eql(u8, event_name, "permission.after")) return null; // informational
    if (std.mem.eql(u8, event_name, "session.end")) return .SessionEnd;
    return null;
}

// Check if an OpenClaw event is purely informational (no policy evaluation needed)
fn isOpenClawInformationalEvent(event_name: []const u8) bool {
    return std.mem.eql(u8, event_name, "permission.after") or
        std.mem.eql(u8, event_name, "session.end");
}

fn mapHermesEvent(event_name: []const u8) ?Event {
    if (std.mem.eql(u8, event_name, "on_session_start")) return .SessionStart;
    if (std.mem.eql(u8, event_name, "pre_tool_call")) return .PreToolUse;
    if (std.mem.eql(u8, event_name, "post_tool_call")) return .PostToolUse;
    if (std.mem.eql(u8, event_name, "pre_llm_call")) return .UserPromptSubmit;
    if (std.mem.eql(u8, event_name, "on_session_end")) return .SessionEnd;
    if (std.mem.eql(u8, event_name, "on_session_finalize")) return .SessionEnd;
    if (std.mem.eql(u8, event_name, "on_session_reset")) return .SessionEnd;
    if (std.mem.eql(u8, event_name, "post_llm_call")) return null;
    if (std.mem.eql(u8, event_name, "subagent_stop")) return null;
    return null;
}

fn isHermesInformationalEvent(event_name: []const u8) bool {
    return std.mem.eql(u8, event_name, "post_llm_call") or
        std.mem.eql(u8, event_name, "subagent_stop");
}

// ---------------------------------------------------------------------------
// Hook command
// ---------------------------------------------------------------------------

fn hookCommand(io: std.Io, host: Host, event: Event, original_event_name: []const u8, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var ci_mode = false;

    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try stdout.writeAll(
                \\Usage:
                \\  orca hook codex SessionStart
                \\  orca hook codex UserPromptSubmit
                \\  orca hook codex PreToolUse
                \\  orca hook codex PermissionRequest
                \\  orca hook codex PostToolUse
                \\  orca hook codex Stop
                \\  orca hook claude SessionStart
                \\  orca hook claude UserPromptSubmit
                \\  orca hook claude PreToolUse
                \\  orca hook claude PermissionRequest
                \\  orca hook claude PostToolUse
                \\  orca hook claude SessionEnd
                \\  orca hook opencode session.created
                \\  orca hook opencode tool.execute.before
                \\  orca hook opencode tool.execute.after
                \\  orca hook opencode permission.asked
                \\  orca hook opencode permission.replied
                \\  orca hook opencode file.edited
                \\  orca hook opencode command.executed
                \\  orca hook opencode session.updated
                \\  orca hook opencode session.idle
                \\  orca hook opencode session.error
                \\  orca hook opencode shell.env
                \\  orca hook openclaw session.start
                \\  orca hook openclaw tool.before
                \\  orca hook openclaw tool.after
                \\  orca hook openclaw permission.before
                \\  orca hook openclaw permission.after
                \\  orca hook openclaw session.end
                \\  orca hook hermes on_session_start
                \\  orca hook hermes pre_tool_call
                \\  orca hook hermes post_tool_call
                \\  orca hook hermes pre_llm_call
                \\  orca hook hermes post_llm_call
                \\  orca hook hermes on_session_end
                \\  orca hook hermes on_session_finalize
                \\  orca hook hermes on_session_reset
                \\  orca hook hermes subagent_stop
                \\
                \\Options:
                \\  --ci     CI mode: ask decisions become block.
                \\
            );
            return exit_codes.success;
        }
        if (std.mem.eql(u8, arg, "--ci")) {
            ci_mode = true;
            continue;
        }
        try stderr.print("orca hook: unknown option '{s}'.\n", .{arg});
        return exit_codes.usage;
    }

    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    // Read payload from stdin (hooks always read from stdin)
    const payload_text = readBoundedStdin(io, allocator, max_payload_len) catch |err| {
        if (err == error.PayloadTooLarge) {
            if (host == .codex and event == .PreToolUse) {
                try writeCodexGuardBlock(stderr, "orca hook: JSON payload exceeds maximum size; Orca blocked it before evaluation.");
                return codex_deny_exit_code;
            }
            try stderr.writeAll("orca hook: JSON payload exceeds maximum size.\n");
            return exit_codes.general;
        }
        return err;
    };
    defer allocator.free(payload_text);

    if (payload_text.len == 0) {
        try stderr.writeAll("orca hook: no JSON payload received on stdin.\n");
        return exit_codes.usage;
    }

    // Parse JSON payload
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, payload_text, .{}) catch |err| {
        try stderr.print("orca hook: invalid JSON ({s}).\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer parsed.deinit();

    // Validate version
    const version_value = extractInteger(parsed.value, "version") orelse 0;
    if (version_value != 1) {
        try stderr.print("orca hook: unsupported schema version {d}. Expected 1.\n", .{version_value});
        return exit_codes.general;
    }

    // Validate host matches
    const request_host = extractString(parsed.value, "host") orelse "";
    if (!std.mem.eql(u8, request_host, @tagName(host))) {
        try stderr.print("orca hook: host mismatch. Expected '{s}', got '{s}'.\n", .{ @tagName(host), request_host });
        return exit_codes.general;
    }

    // Validate event matches (for OpenCode/OpenClaw, compare against original event name)
    const request_event = extractString(parsed.value, "event") orelse "";
    const expected_event = if (host == .opencode or host == .openclaw or host == .hermes) original_event_name else @tagName(event);
    if (!std.mem.eql(u8, request_event, expected_event)) {
        try stderr.print("orca hook: event mismatch. Expected '{s}', got '{s}'.\n", .{ expected_event, request_event });
        return exit_codes.general;
    }

    // Handle informational OpenCode events that don't need policy evaluation
    if (host == .opencode and isOpenCodeInformationalEvent(request_event)) {
        var redactions: std.ArrayList(RedactionEntry) = .empty;
        var limitations: std.ArrayList([]const u8) = .empty;
        try limitations.append(allocator, try allocator.dupe(u8, "Hook enforcement is additive; does not replace orca run supervision."));
        try limitations.append(allocator, try allocator.dupe(u8, "OpenCode informational event: no policy evaluation needed."));

        var result = try makeInformationalResponse(allocator, .allow, .low, "session", "informational event", "OpenCode event acknowledged by Orca.", &redactions, &limitations);
        defer result.deinit(allocator);
        try writeHookResponse(stdout, result);
        return exit_codes.success;
    }

    // Handle informational OpenClaw events that don't need policy evaluation
    if (host == .openclaw and isOpenClawInformationalEvent(request_event)) {
        var redactions: std.ArrayList(RedactionEntry) = .empty;
        var limitations: std.ArrayList([]const u8) = .empty;
        try limitations.append(allocator, try allocator.dupe(u8, "Hook enforcement is additive; does not replace orca run supervision."));
        try limitations.append(allocator, try allocator.dupe(u8, "OpenClaw informational event: no policy evaluation needed."));

        var result = try makeInformationalResponse(allocator, .allow, .low, "session", "informational event", "OpenClaw event acknowledged by Orca.", &redactions, &limitations);
        defer result.deinit(allocator);
        try writeHookResponse(stdout, result);
        return exit_codes.success;
    }

    const root = supervisor.resolveWorkspaceRoot(io, allocator, null, ".") catch try allocator.dupe(u8, ".");
    defer allocator.free(root);

    // Extract payload object
    var empty_payload: std.json.ObjectMap = .empty;
    defer empty_payload.deinit(allocator);
    const hook_payload = parsed.value.object.get("payload") orelse std.json.Value{ .object = empty_payload };

    if (host == .hermes and isHermesInformationalEvent(request_event)) {
        var redactions: std.ArrayList(RedactionEntry) = .empty;
        var limitations: std.ArrayList([]const u8) = .empty;
        try limitations.append(allocator, try allocator.dupe(u8, "Hook enforcement is additive; does not replace orca run supervision."));
        try limitations.append(allocator, try allocator.dupe(u8, "Hermes informational event: no policy evaluation needed."));

        var result = try makeInformationalResponse(allocator, .allow, .low, "session", "informational event", "Hermes event acknowledged by Orca.", &redactions, &limitations);
        defer result.deinit(allocator);
        if (std.mem.eql(u8, request_event, "subagent_stop"))
            recordHermesHookActivity(io, allocator, root, request_event, hook_payload, result);
        try writeHookResponse(stdout, result);
        return exit_codes.success;
    }

    // Load policy
    var loaded = core_api.discoverPolicy(io, allocator, null, root) catch |err| {
        try stderr.print("orca hook: failed to load policy: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer loaded.deinit();

    // Evaluate via host adapter
    var result = evaluateHook(io, allocator, root, @tagName(host), loaded.innerPtr(), host, event, hook_payload, ci_mode) catch |err| {
        try stderr.print("orca hook: evaluation failed: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer result.deinit(allocator);

    if (host == .hermes) recordHermesHookActivity(io, allocator, root, request_event, hook_payload, result);

    if (isCodexDenyOutput(host, result.decision)) {
        // Codex 0.125.0+ ignores stdout JSON on deny; exit 2 + stderr is the enforced block path.
        // Sentinel-first so agents scraping stderr can distinguish a guard block from a
        // program error: provenance (guard) + consequence (no side effects) + recourse.
        // Humans never reach this branch — non-Codex hosts render the JSON `message` themselves.
        try writeCodexGuardBlock(stderr, result.message);
    } else {
        try writeHookResponse(stdout, result);
        if (result.rule) |rule| {
            try stderr.print("[hook] matched rule: {s}\n", .{rule});
        }
    }

    return hookExitCode(host, result.decision, ci_mode);
}

/// Machine-readable sentinel prepended to the *agent-audience* deny stderr so an agent
/// scraping stderr can distinguish a guard block from a program error. Provenance +
/// consequence + recourse, parse-friendly, stable. Never shown to humans — it is emitted
/// only on the Codex stderr block path (see `isCodexDenyOutput`), not the JSON host path.
const guard_sentinel_prefix: []const u8 =
    "[[ORCA-GUARD]] blocked. Command did not execute; no side effects. " ++
    "Recourse: orca explain \"<command>\"; orca allow-once <code>; orca allowlist list\n";

/// Codex hook deny exit code (documented Codex CLI contract; distinct from usage errors).
const codex_deny_exit_code: u8 = 2;

fn writeCodexGuardBlock(stderr: anytype, message: []const u8) !void {
    try stderr.writeAll(guard_sentinel_prefix);
    try stderr.writeAll(message);
    try stderr.writeAll("\n");
}

fn isCodexDenyOutput(host: Host, decision: PluginDecision) bool {
    return host == .codex and decision == .block;
}

/// Host-aware hook process exit code after evaluation completes.
fn hookExitCode(host: Host, decision: PluginDecision, ci_mode: bool) u8 {
    _ = ci_mode;
    if (isCodexDenyOutput(host, decision)) return codex_deny_exit_code;
    return exit_codes.success;
}

// ---------------------------------------------------------------------------
// Host adapter evaluation
// ---------------------------------------------------------------------------

const PluginDecision = enum {
    allow,
    block,
    warn,
    ask,
    context_only,
    err,

    pub fn fromDecisionResult(result: core.decision.DecisionResult, ci_mode: bool) PluginDecision {
        return switch (result) {
            .allow => .allow,
            .deny => .block,
            .ask => if (ci_mode) .block else .ask,
            .observe => .context_only,
            .redact => .warn,
            .stage => if (ci_mode) .block else .ask,
            .broker => .err,
        };
    }

    pub fn toString(self: PluginDecision) []const u8 {
        return switch (self) {
            .err => "error",
            else => @tagName(self),
        };
    }
};

const RiskLevel = enum {
    low,
    medium,
    high,
    critical,
    unknown,

    pub fn fromScore(score: ?u8) RiskLevel {
        const s = score orelse return .unknown;
        return if (s <= 25) .low else if (s <= 50) .medium else if (s <= 75) .high else .critical;
    }
};

const RedactionEntry = struct {
    field: []const u8,
    reason: []const u8,

    fn deinit(self: RedactionEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.field);
        allocator.free(self.reason);
    }
};

const HookResponse = struct {
    version: u8 = 1,
    decision: PluginDecision,
    risk: RiskLevel,
    category: []const u8,
    reason: []const u8,
    rule: ?[]const u8,
    message: []const u8,
    redactions: []RedactionEntry,
    host_limitations: [][]const u8,
    /// Additive agent-facing fields (optional). Omitted on Codex minimal deny path.
    suggestions: [][]const u8 = &.{},
    remediation_commands: [][]const u8 = &.{},

    fn deinit(self: *HookResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.reason);
        allocator.free(self.message);
        allocator.free(self.category);
        if (self.rule) |r| allocator.free(r);
        for (self.redactions) |r| r.deinit(allocator);
        allocator.free(self.redactions);
        for (self.host_limitations) |l| allocator.free(l);
        allocator.free(self.host_limitations);
        for (self.suggestions) |s| allocator.free(s);
        if (self.suggestions.len > 0) allocator.free(self.suggestions);
        for (self.remediation_commands) |c| allocator.free(c);
        if (self.remediation_commands.len > 0) allocator.free(self.remediation_commands);
        self.* = undefined;
    }
};

const ShellCommandEvent = shell_eval.ShellCommandEvent;

const NonShellHookEvent = enum {
    file_write,
    generic_tool,
    prompt,
    permission,
    informational,
};

const HookEventClassification = union(enum) {
    shell_command: ShellCommandEvent,
    non_shell: NonShellHookEvent,
    malformed: []const u8,
    unknown_unsupported: []const u8,
    ambiguous: []const u8,
};

const PreToolUseRoute = union(enum) {
    shell_command: ShellCommandEvent,
    zig_native: NonShellHookEvent,
    fail_closed: []const u8,
};

const ShellCommandEvaluatorFn = shell_eval.ShellCommandEvaluatorFn;

fn defaultShellCommandEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    return shell_eval.defaultEvaluator(allocator, shell_event);
}

fn evaluateHookForTest(
    allocator: std.mem.Allocator,
    policy_value: *const policy.schema.Policy,
    host: Host,
    event: Event,
    payload: std.json.Value,
    ci_mode: bool,
) !HookResponse {
    return evaluateHook(std.testing.io, allocator, "/tmp/orca-hook-test", @tagName(host), policy_value, host, event, payload, ci_mode);
}

fn evaluatePreToolUseForTest(
    allocator: std.mem.Allocator,
    policy_value: *const policy.schema.Policy,
    payload: std.json.Value,
    ci_mode: bool,
    redactions: *std.ArrayList(RedactionEntry),
    limitations: *std.ArrayList([]const u8),
    shell_evaluator: ?ShellCommandEvaluatorFn,
) !HookResponse {
    return evaluatePreToolUse(
        std.testing.io,
        allocator,
        "/tmp/orca-hook-test",
        "claude",
        policy_value,
        payload,
        ci_mode,
        redactions,
        limitations,
        shell_evaluator,
    );
}

fn evaluateHook(
    io: std.Io,
    allocator: std.mem.Allocator,
    workspace_root: []const u8,
    host_name: []const u8,
    policy_value: *const policy.schema.Policy,
    _: Host,
    event: Event,
    payload: std.json.Value,
    ci_mode: bool,
) !HookResponse {
    var redactions: std.ArrayList(RedactionEntry) = .empty;
    var limitations: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (redactions.items) |entry| entry.deinit(allocator);
        redactions.deinit(allocator);
        for (limitations.items) |item| allocator.free(item);
        limitations.deinit(allocator);
    }

    // Add host limitation note
    try limitations.append(allocator, try allocator.dupe(u8, "Hook enforcement is additive; does not replace orca run supervision."));

    switch (event) {
        .SessionStart => {
            return try makeInformationalResponse(allocator, .allow, .low, "session", "session started", "Session start acknowledged by Orca.", &redactions, &limitations);
        },
        .Stop, .SessionEnd => {
            return try makeInformationalResponse(allocator, .allow, .low, "session", "session ended", "Session end acknowledged by Orca.", &redactions, &limitations);
        },
        .PostToolUse => {
            return try makeInformationalResponse(allocator, .allow, .low, "tool", "tool use completed", "Post-tool-use acknowledged by Orca.", &redactions, &limitations);
        },
        .UserPromptSubmit => {
            const prompt_text = extractString(payload, "prompt") orelse
                extractString(payload, "text") orelse
                extractString(payload, "user_message") orelse
                extractNestedString(payload, &.{ "kwargs", "user_message" }) orelse
                extractNestedString(payload, &.{ "extra", "user_message" }) orelse
                "";

            // Redact prompt text to check for secrets
            var redact_buf: [4096]u8 = undefined;
            const redacted = core_api.redactStringBounded(prompt_text, &redact_buf);
            const had_secrets = redacted.len != prompt_text.len or !std.mem.eql(u8, redacted, prompt_text);

            if (had_secrets) {
                try redactions.append(allocator, .{
                    .field = try allocator.dupe(u8, "prompt"),
                    .reason = try allocator.dupe(u8, "potential secret detected"),
                });
            }

            // Use policy env evaluation as a proxy for sensitivity
            const evaluation = try core_api.explainAction(allocator, @ptrCast(policy_value), .env, "USER_PROMPT");
            defer evaluation.deinit(allocator);

            const decision: PluginDecision = if (had_secrets)
                .warn
            else
                PluginDecision.fromDecisionResult(evaluation.decision.result, ci_mode);

            const risk: RiskLevel = if (had_secrets) .high else RiskLevel.fromScore(evaluation.decision.risk_score);

            return .{
                .decision = decision,
                .risk = risk,
                .category = try allocator.dupe(u8, "prompt"),
                .reason = if (had_secrets)
                    try allocator.dupe(u8, "prompt contains potential secret")
                else
                    try allocator.dupe(u8, evaluation.decision.reason),
                .rule = if (evaluation.matched_rule) |rule| try allocator.dupe(u8, rule.id) else null,
                .message = if (had_secrets)
                    try allocator.dupe(u8, "Prompt may contain sensitive data. Review before submitting.")
                else
                    try buildMessage(allocator, decision, "prompt"),
                .redactions = try redactions.toOwnedSlice(allocator),
                .host_limitations = try limitations.toOwnedSlice(allocator),
            };
        },
        .PreToolUse => {
            return try evaluatePreToolUse(io, allocator, workspace_root, host_name, policy_value, payload, ci_mode, &redactions, &limitations, null);
        },
        .PermissionRequest => {
            const permission_kind = extractString(payload, "kind") orelse extractString(payload, "permission") orelse return error.MissingRequiredField;
            const target = extractString(payload, "target") orelse extractString(payload, "resource") orelse return error.MissingRequiredField;

            // Evaluate based on permission kind
            // Destructive file operations (delete, create, append, move, rename, remove)
            // are classified as file_write so they are evaluated under write policy.
            const explain_kind: policy.explain.ExplainKind = if (std.mem.indexOf(u8, permission_kind, "file") != null)
                if (std.mem.indexOf(u8, permission_kind, "write") != null or
                    std.mem.indexOf(u8, permission_kind, "edit") != null or
                    std.mem.indexOf(u8, permission_kind, "delete") != null or
                    std.mem.indexOf(u8, permission_kind, "create") != null or
                    std.mem.indexOf(u8, permission_kind, "append") != null or
                    std.mem.indexOf(u8, permission_kind, "move") != null or
                    std.mem.indexOf(u8, permission_kind, "rename") != null or
                    std.mem.indexOf(u8, permission_kind, "remove") != null)
                    .file_write
                else
                    .file_read
            else if (std.mem.indexOf(u8, permission_kind, "command") != null or std.mem.indexOf(u8, permission_kind, "shell") != null)
                .command
            else if (std.mem.indexOf(u8, permission_kind, "network") != null)
                .network
            else
                .env;

            const evaluation = try core_api.explainAction(allocator, @ptrCast(policy_value), explain_kind, target);
            defer evaluation.deinit(allocator);

            const decision = PluginDecision.fromDecisionResult(evaluation.decision.result, ci_mode);
            const risk = RiskLevel.fromScore(evaluation.decision.risk_score);

            return .{
                .decision = decision,
                .risk = risk,
                .category = try allocator.dupe(u8, @tagName(explain_kind)),
                .reason = try allocator.dupe(u8, evaluation.decision.reason),
                .rule = if (evaluation.matched_rule) |rule| try allocator.dupe(u8, rule.id) else null,
                .message = try buildMessage(allocator, decision, permission_kind),
                .redactions = try redactions.toOwnedSlice(allocator),
                .host_limitations = try limitations.toOwnedSlice(allocator),
            };
        },
    }
}

fn makeInformationalResponse(
    allocator: std.mem.Allocator,
    decision: PluginDecision,
    risk: RiskLevel,
    category: []const u8,
    reason: []const u8,
    message: []const u8,
    redactions: *std.ArrayList(RedactionEntry),
    limitations: *std.ArrayList([]const u8),
) !HookResponse {
    return .{
        .decision = decision,
        .risk = risk,
        .category = try allocator.dupe(u8, category),
        .reason = try allocator.dupe(u8, reason),
        .rule = null,
        .message = try allocator.dupe(u8, message),
        .redactions = try redactions.toOwnedSlice(allocator),
        .host_limitations = try limitations.toOwnedSlice(allocator),
    };
}

fn buildMessage(allocator: std.mem.Allocator, decision: PluginDecision, category: []const u8) ![]const u8 {
    return switch (decision) {
        .allow => try std.fmt.allocPrint(allocator, "{s} allowed by Orca policy.", .{category}),
        .block => try std.fmt.allocPrint(allocator, "{s} blocked by Orca policy.", .{category}),
        .warn => try std.fmt.allocPrint(allocator, "{s} flagged by Orca policy. Review before proceeding.", .{category}),
        .ask => try std.fmt.allocPrint(allocator, "{s} requires user approval per Orca policy.", .{category}),
        .context_only => try std.fmt.allocPrint(allocator, "{s} allowed for context only. No side effects permitted.", .{category}),
        .err => try std.fmt.allocPrint(allocator, "Orca could not evaluate {s}. Fail closed.", .{category}),
    };
}

fn evaluatePreToolUse(
    io: std.Io,
    allocator: std.mem.Allocator,
    workspace_root: []const u8,
    host_name: []const u8,
    policy_value: *const policy.schema.Policy,
    payload: std.json.Value,
    ci_mode: bool,
    redactions: *std.ArrayList(RedactionEntry),
    limitations: *std.ArrayList([]const u8),
    shell_evaluator: ?ShellCommandEvaluatorFn,
) !HookResponse {
    return switch (preToolUseRoute(payload)) {
        .shell_command => |shell_event| evaluateShellCommandRoute(
            io,
            allocator,
            workspace_root,
            host_name,
            shell_event,
            ci_mode,
            redactions,
            limitations,
            shell_evaluator,
        ),
        .zig_native => |native_event| evaluateNativePreToolUseRoute(
            allocator,
            policy_value,
            payload,
            native_event,
            ci_mode,
            redactions,
            limitations,
        ),
        .fail_closed => |reason| makeFailClosedHookResponse(
            allocator,
            "command",
            reason,
            "Shell command hook payload is malformed. Orca blocked it before evaluation.",
            redactions,
            limitations,
        ),
    };
}

fn evaluateShellCommandRoute(
    io: std.Io,
    allocator: std.mem.Allocator,
    workspace_root: []const u8,
    host_name: []const u8,
    shell_event: ShellCommandEvent,
    ci_mode: bool,
    redactions: *std.ArrayList(RedactionEntry),
    limitations: *std.ArrayList([]const u8),
    evaluator_override: ?ShellCommandEvaluatorFn,
) !HookResponse {
    const evaluator = evaluator_override orelse defaultShellCommandEvaluator;
    const daemon_response = evaluator(allocator, shell_event) catch |err| {
        if (!std.mem.eql(u8, host_name, "hermes")) recordShellHookUnavailable(io, allocator, workspace_root, host_name, err);
        return try makeFailClosedHookResponse(
            allocator,
            "command",
            daemonUnavailableReason(err),
            "Shell command blocked: Orca daemon evaluation unavailable.",
            redactions,
            limitations,
        );
    };
    defer daemon_response.deinit();

    if (!std.mem.eql(u8, host_name, "hermes")) {
        var health = try rust_visibility.probeGuiDaemonHealth(allocator);
        defer health.deinit(allocator);
        recordShellHookDecision(io, allocator, workspace_root, host_name, health.status, daemon_response.value.result);
    }

    return try hookResponseFromDaemonEvaluate(
        allocator,
        daemon_response.value.result,
        ci_mode,
        redactions,
        limitations,
    );
}

fn recordShellHookUnavailable(
    io: std.Io,
    allocator: std.mem.Allocator,
    workspace_root: []const u8,
    host_name: []const u8,
    err: daemon.DaemonError,
) void {
    var record = rust_visibility.buildFeedRecordFromUnavailable(
        allocator,
        io,
        workspace_root,
        rust_visibility.event_source_hook,
        host_name,
        err,
        null,
        false,
    ) catch return;
    defer record.deinit(allocator);
    feed_writer.appendRecordBestEffort(io, allocator, workspace_root, record);
}

fn recordShellHookDecision(
    io: std.Io,
    allocator: std.mem.Allocator,
    workspace_root: []const u8,
    host_name: []const u8,
    daemon_status: []const u8,
    result: std.json.Value,
) void {
    var record = rust_visibility.buildFeedRecordFromDaemon(
        allocator,
        io,
        workspace_root,
        rust_visibility.event_source_hook,
        host_name,
        daemon_status,
        result,
        null,
        false,
    ) catch return;
    defer record.deinit(allocator);
    feed_writer.appendRecordBestEffort(io, allocator, workspace_root, record);
}

fn recordHermesHookActivity(
    io: std.Io,
    allocator: std.mem.Allocator,
    workspace_root: []const u8,
    event_name: []const u8,
    payload: std.json.Value,
    result: HookResponse,
) void {
    const shell_tool = std.mem.eql(u8, event_name, "pre_tool_call") and switch (preToolUseRoute(payload)) {
        .shell_command => true,
        .zig_native, .fail_closed => false,
    };
    var health: ?rust_visibility.GuiDaemonHealth = if (shell_tool) rust_visibility.probeGuiDaemonHealth(allocator) catch null else null;
    defer if (health) |*value| value.deinit(allocator);

    const decision_source = if (shell_tool) rust_visibility.decision_source_rust else rust_visibility.decision_source_zig;
    const daemon_status = if (health) |value| value.status else if (shell_tool) "unavailable" else "not_applicable";
    var target_buf: [160]u8 = undefined;
    var record = rust_visibility.buildFeedRecordFromHookActivity(
        allocator,
        io,
        workspace_root,
        rust_visibility.event_source_hook,
        decision_source,
        "hermes",
        daemon_status,
        hermesFeedEventType(event_name, result.decision),
        hermesFeedDecisionTag(result.decision),
        result.reason,
        hermesTargetSummary(payload, event_name, &target_buf),
        extractHermesSessionId(payload, event_name),
        false,
    ) catch return;
    defer record.deinit(allocator);
    feed_writer.appendRecordBestEffort(io, allocator, workspace_root, record);
}

fn extractHermesSessionId(payload: std.json.Value, event_name: []const u8) ?[]const u8 {
    const keys = if (std.mem.eql(u8, event_name, "subagent_stop"))
        &[_][]const u8{ "parent_session_id", "session_id", "task_id" }
    else
        &[_][]const u8{ "session_id", "task_id", "parent_session_id" };
    for (keys) |key| {
        if (extractHermesIdentifier(payload, key)) |candidate| return candidate;
    }
    return null;
}

fn extractHermesIdentifier(payload: std.json.Value, key: []const u8) ?[]const u8 {
    const candidate = extractString(payload, key) orelse
        extractNestedString(payload, &.{ "kwargs", key }) orelse
        extractNestedString(payload, &.{ "extra", key }) orelse return null;
    core.session.validateSessionIdText(candidate) catch return null;
    return candidate;
}

fn hermesFeedDecisionTag(decision: PluginDecision) []const u8 {
    return switch (decision) {
        .allow => "allow",
        .block => "deny",
        .warn => "warn",
        .ask => "ask",
        .context_only => "observe",
        .err => "error",
    };
}

fn hermesFeedEventType(event_name: []const u8, decision: PluginDecision) []const u8 {
    if (std.mem.eql(u8, event_name, "on_session_start")) return "hermes_session_started";
    if (std.mem.eql(u8, event_name, "pre_tool_call")) return switch (decision) {
        .block, .warn, .ask, .err => "hermes_tool_call_blocked",
        else => "hermes_tool_call",
    };
    if (std.mem.eql(u8, event_name, "post_tool_call")) return "hermes_tool_call_completed";
    if (std.mem.eql(u8, event_name, "pre_llm_call")) return "hermes_prompt_review";
    if (std.mem.eql(u8, event_name, "subagent_stop")) return "hermes_subagent_stopped";
    return "hermes_session_ended";
}

fn hermesTargetSummary(payload: std.json.Value, event_name: []const u8, buffer: []u8) []const u8 {
    if (std.mem.eql(u8, event_name, "pre_tool_call")) return "tool call (redacted)";
    if (std.mem.eql(u8, event_name, "post_tool_call")) return "completed tool call (redacted)";
    if (std.mem.eql(u8, event_name, "pre_llm_call")) return "prompt (redacted)";
    if (std.mem.eql(u8, event_name, "subagent_stop")) {
        if (extractHermesIdentifier(payload, "task_id")) |task_id|
            return std.fmt.bufPrint(buffer, "subagent task {s} stopped", .{task_id}) catch "subagent stopped";
        if (extractHermesIdentifier(payload, "agent_id")) |agent_id|
            return std.fmt.bufPrint(buffer, "subagent {s} stopped", .{agent_id}) catch "subagent stopped";
        return "subagent stopped";
    }
    return "Hermes session";
}

fn daemonUnavailableReason(err: daemon.DaemonError) []const u8 {
    return shell_eval.daemonUnavailableReason(err);
}

fn shellEvalPluginDecisionToHook(decision: shell_eval.PluginDecision) PluginDecision {
    return switch (decision) {
        .allow => .allow,
        .block => .block,
        .warn => .warn,
        .ask => .ask,
    };
}

fn applyCiModeToShellDecision(decision: PluginDecision, ci_mode: bool) PluginDecision {
    return switch (decision) {
        .ask, .warn => if (ci_mode) .block else decision,
        else => decision,
    };
}

fn pluginDecisionFromDaemonAllow(result: std.json.Value) PluginDecision {
    return shellEvalPluginDecisionToHook(shell_eval.pluginDecisionFromDaemonAllow(result));
}

fn riskFromDaemonSeverity(severity: ?[]const u8) RiskLevel {
    return switch (shell_eval.riskLevelFromDaemonSeverity(severity)) {
        .low => .low,
        .medium => .medium,
        .high => .high,
        .critical => .critical,
        .unknown => .unknown,
    };
}

fn recordDaemonMetadataRedaction(
    allocator: std.mem.Allocator,
    redactions: *std.ArrayList(RedactionEntry),
    field: []const u8,
) !void {
    try redactions.append(allocator, .{
        .field = try allocator.dupe(u8, field),
        .reason = try allocator.dupe(u8, "daemon evaluator metadata withheld from agent-visible output"),
    });
}

fn buildAgentVisibleDaemonDeny(
    allocator: std.mem.Allocator,
    result: std.json.Value,
    ci_mode: bool,
    redactions: *std.ArrayList(RedactionEntry),
) !struct {
    decision: PluginDecision,
    risk: RiskLevel,
    reason: []const u8,
    rule: ?[]const u8,
    message: []const u8,
    suggestions: [][]const u8,
    remediation_commands: [][]const u8,
} {
    if (daemon.responseStringField(result, "matched_text_preview")) |_| {
        try recordDaemonMetadataRedaction(allocator, redactions, "matched_text_preview");
    }

    const decision = applyCiModeToShellDecision(.block, ci_mode);
    const risk = riskFromDaemonSeverity(daemon.responseStringField(result, "severity"));
    var deny = try shell_eval.buildDaemonDenyReason(allocator, result);
    errdefer {
        if (deny.reason.len > 0) allocator.free(deny.reason);
        if (deny.rule) |rule| allocator.free(rule);
    }
    const safe_reason = try core_api.redactAlloc(allocator, deny.reason);
    errdefer allocator.free(safe_reason);
    allocator.free(deny.reason);
    deny.reason = "";
    const safe_rule = if (deny.rule) |rule| blk: {
        const safe = try core_api.redactAlloc(allocator, rule);
        allocator.free(rule);
        deny.rule = null;
        break :blk safe;
    } else null;
    errdefer if (safe_rule) |rule| allocator.free(rule);

    const message = if (daemon.responseStringField(result, "explanation")) |explanation| blk: {
        const safe = try core_api.redactAlloc(allocator, explanation);
        defer allocator.free(safe);
        break :blk try std.fmt.allocPrint(allocator, "command blocked by Orca policy: {s}", .{safe});
    } else try buildMessage(allocator, decision, "command");

    const suggestions = try collectDaemonSuggestionTexts(allocator, result);
    errdefer {
        for (suggestions) |s| allocator.free(s);
        allocator.free(suggestions);
    }
    const remediation_commands = try buildRemediationCommands(allocator, safe_rule);
    errdefer {
        for (remediation_commands) |c| allocator.free(c);
        allocator.free(remediation_commands);
    }

    return .{
        .decision = decision,
        .risk = risk,
        .reason = safe_reason,
        .rule = safe_rule,
        .message = message,
        .suggestions = suggestions,
        .remediation_commands = remediation_commands,
    };
}

fn collectDaemonSuggestionTexts(allocator: std.mem.Allocator, result: std.json.Value) ![][]const u8 {
    const items = daemon.responseArrayField(result, "suggestions") orelse return try allocator.alloc([]const u8, 0);
    var list: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (list.items) |s| allocator.free(s);
        list.deinit(allocator);
    }
    for (items) |item| {
        if (item != .object) continue;
        const description = switch (item.object.get("description") orelse .null) {
            .string => |s| s,
            else => null,
        };
        const suggestion_cmd = switch (item.object.get("command") orelse .null) {
            .string => |s| s,
            else => null,
        };
        if (description) |desc| {
            if (suggestion_cmd) |cmd| {
                const text = try std.fmt.allocPrint(allocator, "{s} ({s})", .{ desc, cmd });
                const safe = try core_api.redactAlloc(allocator, text);
                allocator.free(text);
                try list.append(allocator, safe);
                continue;
            }
            try list.append(allocator, try core_api.redactAlloc(allocator, desc));
        } else if (suggestion_cmd) |cmd| {
            try list.append(allocator, try core_api.redactAlloc(allocator, cmd));
        }
    }
    return try list.toOwnedSlice(allocator);
}

fn buildRemediationCommands(allocator: std.mem.Allocator, rule_id: ?[]const u8) ![][]const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (list.items) |s| allocator.free(s);
        list.deinit(allocator);
    }
    try list.append(allocator, try allocator.dupe(u8, "orca explain \"<command>\""));
    try list.append(allocator, try allocator.dupe(u8, "orca allow-once <code>"));
    if (rule_id) |rid| {
        try list.append(allocator, try std.fmt.allocPrint(allocator, "orca allowlist add {s} -r \"reason\"", .{rid}));
    } else {
        try list.append(allocator, try allocator.dupe(u8, "orca allowlist list"));
    }
    return try list.toOwnedSlice(allocator);
}

fn hookResponseFromDaemonEvaluate(
    allocator: std.mem.Allocator,
    result: std.json.Value,
    ci_mode: bool,
    redactions: *std.ArrayList(RedactionEntry),
    limitations: *std.ArrayList([]const u8),
) !HookResponse {
    return switch (daemon.responseStatus(result)) {
        .allow => blk: {
            const decision = applyCiModeToShellDecision(pluginDecisionFromDaemonAllow(result), ci_mode);
            const safe_reason = try core_api.redactAlloc(allocator, daemon.responseReason(result) orelse "command allowed by daemon evaluator");
            break :blk HookResponse{
                .decision = decision,
                .risk = if (decision == .warn) .medium else .low,
                .category = try allocator.dupe(u8, "command"),
                .reason = safe_reason,
                .rule = null,
                .message = try buildMessage(allocator, decision, "command"),
                .redactions = try redactions.toOwnedSlice(allocator),
                .host_limitations = try limitations.toOwnedSlice(allocator),
            };
        },
        .deny => blk: {
            const deny = try buildAgentVisibleDaemonDeny(allocator, result, ci_mode, redactions);
            break :blk HookResponse{
                .decision = deny.decision,
                .risk = deny.risk,
                .category = try allocator.dupe(u8, "command"),
                .reason = deny.reason,
                .rule = deny.rule,
                .message = deny.message,
                .redactions = try redactions.toOwnedSlice(allocator),
                .host_limitations = try limitations.toOwnedSlice(allocator),
                .suggestions = deny.suggestions,
                .remediation_commands = deny.remediation_commands,
            };
        },
        .error_status => blk: {
            const safe_error = try core_api.redactAlloc(allocator, daemon.responseErrorMessage(result) orelse "daemon evaluation error");
            defer allocator.free(safe_error);
            break :blk try makeFailClosedHookResponse(
                allocator,
                "command",
                safe_error,
                "Shell command blocked: Orca daemon returned an evaluation error.",
                redactions,
                limitations,
            );
        },
        .pong, .cli_execution, .unknown => try makeFailClosedHookResponse(
            allocator,
            "command",
            "unexpected daemon response for shell command evaluation",
            "Shell command blocked: Orca daemon returned an unexpected response.",
            redactions,
            limitations,
        ),
    };
}

fn evaluateNativePreToolUseRoute(
    allocator: std.mem.Allocator,
    policy_value: *const policy.schema.Policy,
    payload: std.json.Value,
    native_event: NonShellHookEvent,
    ci_mode: bool,
    redactions: *std.ArrayList(RedactionEntry),
    limitations: *std.ArrayList([]const u8),
) !HookResponse {
    switch (native_event) {
        .file_write => {
            const path = extractFilePath(payload) orelse return error.MissingRequiredField;
            const evaluation = try core_api.explainAction(allocator, @ptrCast(policy_value), .file_write, path);
            defer evaluation.deinit(allocator);

            const decision = PluginDecision.fromDecisionResult(evaluation.decision.result, ci_mode);
            const risk = RiskLevel.fromScore(evaluation.decision.risk_score);

            return .{
                .decision = decision,
                .risk = risk,
                .category = try allocator.dupe(u8, "file.write"),
                .reason = try allocator.dupe(u8, evaluation.decision.reason),
                .rule = if (evaluation.matched_rule) |rule| try allocator.dupe(u8, rule.id) else null,
                .message = try buildMessage(allocator, decision, "file.write"),
                .redactions = try redactions.toOwnedSlice(allocator),
                .host_limitations = try limitations.toOwnedSlice(allocator),
            };
        },
        .generic_tool => {
            const generic_tool_name = extractToolName(payload) orelse return error.MissingRequiredField;
            const evaluation = try core_api.explainAction(allocator, @ptrCast(policy_value), .mcp, generic_tool_name);
            defer evaluation.deinit(allocator);

            const decision = PluginDecision.fromDecisionResult(evaluation.decision.result, ci_mode);
            const risk = RiskLevel.fromScore(evaluation.decision.risk_score);

            return .{
                .decision = decision,
                .risk = risk,
                .category = try allocator.dupe(u8, "tool"),
                .reason = try allocator.dupe(u8, evaluation.decision.reason),
                .rule = if (evaluation.matched_rule) |rule| try allocator.dupe(u8, rule.id) else null,
                .message = try buildMessage(allocator, decision, "tool"),
                .redactions = try redactions.toOwnedSlice(allocator),
                .host_limitations = try limitations.toOwnedSlice(allocator),
            };
        },
        else => return error.MissingRequiredField,
    }
}

fn makeFailClosedHookResponse(
    allocator: std.mem.Allocator,
    category: []const u8,
    reason: []const u8,
    message: []const u8,
    redactions: *std.ArrayList(RedactionEntry),
    limitations: *std.ArrayList([]const u8),
) !HookResponse {
    return .{
        .decision = .block,
        .risk = .high,
        .category = try allocator.dupe(u8, category),
        .reason = try allocator.dupe(u8, reason),
        .rule = null,
        .message = try allocator.dupe(u8, message),
        .redactions = try redactions.toOwnedSlice(allocator),
        .host_limitations = try limitations.toOwnedSlice(allocator),
    };
}

// ---------------------------------------------------------------------------
// JSON output
// ---------------------------------------------------------------------------

fn writeHookResponse(stdout: anytype, result: HookResponse) !void {
    try stdout.writeAll("{\n");
    try stdout.print("  \"version\": {d},\n", .{result.version});
    try stdout.print("  \"decision\": \"{s}\",\n", .{result.decision.toString()});
    try stdout.print("  \"risk\": \"{s}\",\n", .{@tagName(result.risk)});
    try stdout.print("  \"category\": \"{s}\",\n", .{result.category});
    try stdout.writeAll("  \"reason\": ");
    try writeJsonString(stdout, result.reason);
    try stdout.writeAll(",\n");

    try stdout.writeAll("  \"rule\": ");
    if (result.rule) |rule| {
        try writeJsonString(stdout, rule);
    } else {
        try stdout.writeAll("null");
    }
    try stdout.writeAll(",\n");

    // Alias for agents that prefer rule_id (additive; mirrors `rule`).
    try stdout.writeAll("  \"rule_id\": ");
    if (result.rule) |rule| {
        try writeJsonString(stdout, rule);
    } else {
        try stdout.writeAll("null");
    }
    try stdout.writeAll(",\n");

    try stdout.writeAll("  \"message\": ");
    try writeJsonString(stdout, result.message);
    try stdout.writeAll(",\n");

    try stdout.writeAll("  \"redactions\": [\n");
    for (result.redactions, 0..) |r, i| {
        try stdout.writeAll("    {\n");
        try stdout.writeAll("      \"field\": ");
        try writeJsonString(stdout, r.field);
        try stdout.writeAll(",\n");
        try stdout.writeAll("      \"reason\": ");
        try writeJsonString(stdout, r.reason);
        try stdout.writeAll("\n    }");
        if (i < result.redactions.len - 1) try stdout.writeAll(",");
        try stdout.writeAll("\n");
    }
    try stdout.writeAll("  ],\n");

    try stdout.writeAll("  \"host_limitations\": [\n");
    for (result.host_limitations, 0..) |l, i| {
        try stdout.writeAll("    ");
        try writeJsonString(stdout, l);
        if (i < result.host_limitations.len - 1) try stdout.writeAll(",");
        try stdout.writeAll("\n");
    }
    try stdout.writeAll("  ],\n");

    try stdout.writeAll("  \"suggestions\": [\n");
    for (result.suggestions, 0..) |s, i| {
        try stdout.writeAll("    ");
        try writeJsonString(stdout, s);
        if (i < result.suggestions.len - 1) try stdout.writeAll(",");
        try stdout.writeAll("\n");
    }
    try stdout.writeAll("  ],\n");

    try stdout.writeAll("  \"remediation_commands\": [\n");
    for (result.remediation_commands, 0..) |c, i| {
        try stdout.writeAll("    ");
        try writeJsonString(stdout, c);
        if (i < result.remediation_commands.len - 1) try stdout.writeAll(",");
        try stdout.writeAll("\n");
    }
    try stdout.writeAll("  ]\n");

    try stdout.writeAll("}\n");
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn readBoundedStdin(io: std.Io, allocator: std.mem.Allocator, max_len: usize) ![]u8 {
    return readBoundedFile(io, allocator, max_len, std.Io.File.stdin());
}

fn readBoundedFile(io: std.Io, allocator: std.mem.Allocator, max_len: usize, file: std.Io.File) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);

    var chunk: [4096]u8 = undefined;
    while (true) {
        const n = file.readStreaming(io, &.{chunk[0..]}) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        if (n == 0) break;
        if (buf.items.len + n > max_len) return error.PayloadTooLarge;
        try buf.appendSlice(allocator, chunk[0..n]);
    }

    return try buf.toOwnedSlice(allocator);
}

fn readBoundedIoReader(allocator: std.mem.Allocator, max_len: usize, reader: *std.Io.Reader) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);
    while (buf.items.len < max_len) {
        const chunk = reader.take(@min(4096, max_len - buf.items.len)) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        if (chunk.len == 0) break;
        try buf.appendSlice(allocator, chunk);
    }
    const extra = reader.take(1) catch |err| switch (err) {
        error.EndOfStream => return try buf.toOwnedSlice(allocator),
        else => return err,
    };
    if (extra.len > 0) return error.PayloadTooLarge;
    return try buf.toOwnedSlice(allocator);
}

fn extractString(payload: std.json.Value, key: []const u8) ?[]const u8 {
    if (payload != .object) return null;
    if (payload.object.get(key)) |v| {
        return switch (v) {
            .string => |s| s,
            else => null,
        };
    }
    return null;
}

fn extractInteger(payload: std.json.Value, key: []const u8) ?i64 {
    if (payload != .object) return null;
    if (payload.object.get(key)) |v| {
        return switch (v) {
            .integer => |i| i,
            else => null,
        };
    }
    return null;
}

fn extractNestedString(payload: std.json.Value, keys: []const []const u8) ?[]const u8 {
    var current = payload;
    for (keys) |key| {
        if (current != .object) return null;
        const next = current.object.get(key) orelse return null;
        current = next;
    }
    return switch (current) {
        .string => |s| s,
        else => null,
    };
}

fn classifyHookEvent(event: Event, payload: std.json.Value) HookEventClassification {
    return switch (event) {
        .PreToolUse => classifyPreToolUse(payload),
        .UserPromptSubmit => .{ .non_shell = .prompt },
        .PermissionRequest => .{ .non_shell = .permission },
        .SessionStart, .PostToolUse, .Stop, .SessionEnd => .{ .non_shell = .informational },
    };
}

fn classifyPreToolUse(payload: std.json.Value) HookEventClassification {
    const tool_name = extractToolName(payload);
    const command_state = extractShellCommand(payload);

    if (tool_name) |name| {
        if (isShellTool(name)) {
            return switch (command_state) {
                .found => |shell_event| .{ .shell_command = shell_event },
                .invalid => .{ .malformed = "shell command field must be a non-empty string" },
                .missing => .{ .malformed = "shell command missing command field" },
            };
        }

        // Non-shell tools stay on the Zig path even when payloads carry incidental command fields.
        if (extractFilePath(payload) != null and isFileTool(name)) {
            return .{ .non_shell = .file_write };
        }

        return .{ .non_shell = .generic_tool };
    }

    switch (command_state) {
        .found => |shell_event| return .{ .shell_command = shell_event },
        .invalid => return .{ .malformed = "shell command field must be a non-empty string" },
        .missing => {},
    }

    if (extractFilePath(payload) != null) {
        return .{ .ambiguous = "file path present without file tool name" };
    }

    return .{ .unknown_unsupported = "PreToolUse payload does not identify a supported tool action" };
}

fn preToolUseRoute(payload: std.json.Value) PreToolUseRoute {
    return switch (classifyPreToolUse(payload)) {
        .shell_command => |shell_event| .{ .shell_command = shell_event },
        .non_shell => |native_event| .{ .zig_native = native_event },
        .malformed => |reason| .{ .fail_closed = reason },
        .ambiguous => |reason| .{ .fail_closed = reason },
        .unknown_unsupported => |reason| .{ .fail_closed = reason },
    };
}

const CommandFieldState = union(enum) {
    found: ShellCommandEvent,
    invalid,
    missing,
};

fn extractShellCommand(payload: std.json.Value) CommandFieldState {
    inline for (command_field_paths) |path| {
        if (extractNestedValue(payload, path)) |value| {
            return switch (value) {
                .string => |command_text| {
                    const trimmed = std.mem.trim(u8, command_text, " \t\r\n");
                    if (trimmed.len == 0) return .invalid;
                    return .{ .found = .{ .command = command_text, .cwd = extractCwd(payload) } };
                },
                else => .invalid,
            };
        }
    }
    return .missing;
}

fn extractToolName(payload: std.json.Value) ?[]const u8 {
    return extractString(payload, "tool") orelse
        extractString(payload, "tool_name") orelse
        extractString(payload, "name") orelse
        extractNestedString(payload, &.{ "tool", "name" });
}

fn extractFilePath(payload: std.json.Value) ?[]const u8 {
    return extractString(payload, "path") orelse
        extractString(payload, "file") orelse
        extractNestedString(payload, &.{ "tool_input", "path" }) orelse
        extractNestedString(payload, &.{ "args", "path" }) orelse
        extractNestedString(payload, &.{ "params", "path" }) orelse
        extractNestedString(payload, &.{ "input", "path" }) orelse
        extractNestedString(payload, &.{ "data", "path" }) orelse
        extractNestedString(payload, &.{ "data", "input", "path" }) orelse
        extractNestedString(payload, &.{ "kwargs", "path" }) orelse
        extractNestedString(payload, &.{ "kwargs", "args", "path" }) orelse
        extractNestedString(payload, &.{ "kwargs", "params", "path" }) orelse
        extractNestedString(payload, &.{ "kwargs", "tool_input", "path" });
}

fn extractCwd(payload: std.json.Value) ?[]const u8 {
    return extractString(payload, "cwd") orelse
        extractString(payload, "workdir") orelse
        extractString(payload, "current_working_directory") orelse
        extractNestedString(payload, &.{ "tool_input", "cwd" }) orelse
        extractNestedString(payload, &.{ "input", "cwd" }) orelse
        extractNestedString(payload, &.{ "params", "cwd" }) orelse
        extractNestedString(payload, &.{ "kwargs", "cwd" });
}

fn extractNestedValue(payload: std.json.Value, keys: []const []const u8) ?std.json.Value {
    var current = payload;
    for (keys) |key| {
        if (current != .object) return null;
        current = current.object.get(key) orelse return null;
    }
    return current;
}

fn isFileTool(tool_name: []const u8) bool {
    const file_tools = &[_][]const u8{ "edit", "write", "file_write", "file_edit", "apply", "create_file", "write_file" };
    for (file_tools) |ft| {
        if (std.ascii.eqlIgnoreCase(tool_name, ft)) return true;
    }
    return false;
}

fn isShellTool(tool_name: []const u8) bool {
    const shell_tools = &[_][]const u8{
        "bash",
        "shell",
        "sh",
        "zsh",
        "terminal",
        "run_shell_command",
        "run_terminal_cmd",
        "powershell",
        "pwsh",
        "launch-process",
    };
    for (shell_tools) |st| {
        if (std.ascii.eqlIgnoreCase(tool_name, st)) return true;
    }
    return false;
}

const command_field_paths = [_][]const []const u8{
    &.{"command"},
    &.{ "tool", "command" },
    &.{ "tool_input", "command" },
    &.{ "args", "command" },
    &.{ "params", "command" },
    &.{ "input", "command" },
    &.{ "data", "command" },
    &.{ "data", "input", "command" },
    &.{ "kwargs", "command" },
    &.{ "kwargs", "args", "command" },
    &.{ "kwargs", "params", "command" },
    &.{ "kwargs", "tool_input", "command" },
};

fn writeJsonString(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |byte| {
        switch (byte) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0...8, 11...12, 14...0x1f => try writer.print("\\u{x:0>4}", .{byte}),
            else => try writer.writeByte(byte),
        }
    }
    try writer.writeByte('"');
}

// ---------------------------------------------------------------------------
// Daemon evaluation test helpers
// ---------------------------------------------------------------------------

fn mockDaemonAllowEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    return shell_eval.mockDaemonAllowEvaluator(allocator, shell_event);
}

fn mockDaemonDenyEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    return shell_eval.mockDaemonDenyEvaluator(allocator, shell_event);
}

fn mockDaemonWarnAllowEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    return shell_eval.mockDaemonWarnAllowEvaluator(allocator, shell_event);
}

fn mockDaemonErrorEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    return shell_eval.mockDaemonErrorEvaluator(allocator, shell_event);
}

fn mockDaemonSoftBlockAllowEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    return shell_eval.mockDaemonSoftBlockAllowEvaluator(allocator, shell_event);
}

fn mockDaemonDenyPackOnlyEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    _ = shell_event;
    return shell_eval.mockDaemonResponse(allocator, "{\"id\":1,\"result\":{\"status\":\"Deny\",\"reason\":\"matched rm -rf / in command\",\"pack_id\":\"git\",\"severity\":\"high\",\"explanation\":\"recursive delete of root\"}}");
}

fn mockDaemonDenyWithPreviewEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    _ = shell_event;
    return shell_eval.mockDaemonResponse(allocator, "{\"id\":1,\"result\":{\"status\":\"Deny\",\"reason\":\"matched rm -rf / in command\",\"pack_id\":\"git\",\"pattern_name\":\"destructive_rm\",\"severity\":\"Critical\",\"explanation\":\"recursive delete of root\",\"matched_text_preview\":\"rm -rf /\"}}");
}

fn mockDaemonMalformedEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    _ = shell_event;
    return daemon.parseResponse(allocator, "{not json");
}

fn mockDaemonUnavailableEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    return shell_eval.mockDaemonUnavailableEvaluator(allocator, shell_event);
}

fn mockDaemonTimeoutEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    _ = allocator;
    _ = shell_event;
    return error.SocketReadFailed;
}

fn mockDaemonProtocolMismatchEvaluator(allocator: std.mem.Allocator, shell_event: ShellCommandEvent) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    _ = allocator;
    _ = shell_event;
    return error.ProtocolMismatch;
}

fn shellRouteSetup(allocator: std.mem.Allocator, redactions: *std.ArrayList(RedactionEntry), limitations: *std.ArrayList([]const u8)) !void {
    _ = redactions;
    try limitations.append(allocator, try allocator.dupe(u8, "Hook enforcement is additive; does not replace orca run supervision."));
}

fn runShellRoute(
    allocator: std.mem.Allocator,
    command_text: []const u8,
    cwd: ?[]const u8,
    ci_mode: bool,
    evaluator: ShellCommandEvaluatorFn,
) !HookResponse {
    var redactions: std.ArrayList(RedactionEntry) = .empty;
    var limitations: std.ArrayList([]const u8) = .empty;
    try shellRouteSetup(allocator, &redactions, &limitations);
    return evaluateShellCommandRoute(
        std.testing.io,
        allocator,
        "/tmp/orca-hook-test",
        "claude",
        .{ .command = command_text, .cwd = cwd },
        ci_mode,
        &redactions,
        &limitations,
        evaluator,
    );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "hook command help and invalid host" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const help_code = try command(std.testing.io, &.{"--help"}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, help_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "hook") != null);

    stdout_writer = .fixed(&stdout_buf);
    stderr_writer = .fixed(&stderr_buf);
    const bad_code = try command(std.testing.io, &.{"unknown"}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.usage, bad_code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "unknown host") != null);
}

test "hook codex SessionStart returns allow" {
    // Note: Testing stdin-based commands in Zig inline tests is limited.
    // We test the evaluation logic directly instead.
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var policy_obj = try core_api.loadPolicyPreset(allocator, .strict);
    defer policy_obj.deinit();

    var empty_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer empty_obj.deinit(allocator);
    var result = try evaluateHookForTest(allocator, @ptrCast(@alignCast(policy_obj)), .codex, .SessionStart, std.json.Value{ .object = empty_obj }, false);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.allow, result.decision);
    try std.testing.expectEqual(RiskLevel.low, result.risk);
}

test "hook claude UserPromptSubmit with fake secret returns warn" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var policy_obj = try core_api.loadPolicyPreset(allocator, .strict);
    defer policy_obj.deinit();

    var payload_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload_obj.deinit(allocator);
    try payload_obj.put(allocator, "prompt", std.json.Value{ .string = "my token is ghp_fake_secret_value" });

    var result = try evaluateHookForTest(allocator, @ptrCast(@alignCast(policy_obj)), .claude, .UserPromptSubmit, std.json.Value{ .object = payload_obj }, false);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.warn, result.decision);
    try std.testing.expectEqual(RiskLevel.high, result.risk);
    try std.testing.expect(std.mem.indexOf(u8, result.message, "sensitive data") != null);
    try std.testing.expect(result.redactions.len > 0);
}

test "hook claude PreToolUse with file write to protected path returns block" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var policy_obj = try core_api.loadPolicyPreset(allocator, .strict);
    defer policy_obj.deinit();

    var payload_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload_obj.deinit(allocator);
    try payload_obj.put(allocator, "tool", std.json.Value{ .string = "edit" });
    try payload_obj.put(allocator, "path", std.json.Value{ .string = "/etc/passwd" });

    var result = try evaluateHookForTest(allocator, @ptrCast(@alignCast(policy_obj)), .claude, .PreToolUse, std.json.Value{ .object = payload_obj }, false);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.block, result.decision);
}

test "hook classifies PreToolUse command payload as shell command" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var payload_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload_obj.deinit(allocator);
    try payload_obj.put(allocator, "tool", std.json.Value{ .string = "Bash" });
    try payload_obj.put(allocator, "command", std.json.Value{ .string = "git status" });

    const classification = classifyHookEvent(.PreToolUse, std.json.Value{ .object = payload_obj });
    try std.testing.expectEqual(HookEventClassification.shell_command, std.meta.activeTag(classification));
    try std.testing.expectEqualStrings("git status", classification.shell_command.command);

    const route = preToolUseRoute(std.json.Value{ .object = payload_obj });
    try std.testing.expectEqual(PreToolUseRoute.shell_command, std.meta.activeTag(route));
}

test "hook classifies file PreToolUse payload as non-shell native route" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var payload_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload_obj.deinit(allocator);
    try payload_obj.put(allocator, "tool", std.json.Value{ .string = "edit" });
    try payload_obj.put(allocator, "path", std.json.Value{ .string = "/tmp/example.txt" });

    const classification = classifyHookEvent(.PreToolUse, std.json.Value{ .object = payload_obj });
    try std.testing.expectEqual(HookEventClassification.non_shell, std.meta.activeTag(classification));
    try std.testing.expectEqual(NonShellHookEvent.file_write, classification.non_shell);

    const route = preToolUseRoute(std.json.Value{ .object = payload_obj });
    try std.testing.expectEqual(PreToolUseRoute.zig_native, std.meta.activeTag(route));
}

test "hook classifies shell-like missing command as malformed and fail-closed route" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var payload_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload_obj.deinit(allocator);
    try payload_obj.put(allocator, "tool", std.json.Value{ .string = "run_shell_command" });

    const classification = classifyHookEvent(.PreToolUse, std.json.Value{ .object = payload_obj });
    try std.testing.expectEqual(HookEventClassification.malformed, std.meta.activeTag(classification));

    const route = preToolUseRoute(std.json.Value{ .object = payload_obj });
    try std.testing.expectEqual(PreToolUseRoute.fail_closed, std.meta.activeTag(route));
}

test "hook classifies shell-like non-string command as malformed" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var payload_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload_obj.deinit(allocator);
    try payload_obj.put(allocator, "tool", std.json.Value{ .string = "shell" });
    try payload_obj.put(allocator, "command", std.json.Value{ .integer = 123 });

    const classification = classifyHookEvent(.PreToolUse, std.json.Value{ .object = payload_obj });
    try std.testing.expectEqual(HookEventClassification.malformed, std.meta.activeTag(classification));
}

test "hook classifies empty shell command strings as malformed" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var payload_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload_obj.deinit(allocator);
    try payload_obj.put(allocator, "tool", std.json.Value{ .string = "bash" });
    try payload_obj.put(allocator, "command", std.json.Value{ .string = "" });

    const classification = classifyHookEvent(.PreToolUse, std.json.Value{ .object = payload_obj });
    try std.testing.expectEqual(HookEventClassification.malformed, std.meta.activeTag(classification));

    const route = preToolUseRoute(std.json.Value{ .object = payload_obj });
    try std.testing.expectEqual(PreToolUseRoute.fail_closed, std.meta.activeTag(route));
}

test "hook classifies whitespace-only shell command strings as malformed" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var payload_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload_obj.deinit(allocator);
    try payload_obj.put(allocator, "tool", std.json.Value{ .string = "shell" });
    try payload_obj.put(allocator, "command", std.json.Value{ .string = "   \n\t" });

    const classification = classifyHookEvent(.PreToolUse, std.json.Value{ .object = payload_obj });
    try std.testing.expectEqual(HookEventClassification.malformed, std.meta.activeTag(classification));

    const route = preToolUseRoute(std.json.Value{ .object = payload_obj });
    try std.testing.expectEqual(PreToolUseRoute.fail_closed, std.meta.activeTag(route));
}

test "hook classifies unsupported PreToolUse payload explicitly" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var payload_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload_obj.deinit(allocator);

    const classification = classifyHookEvent(.PreToolUse, std.json.Value{ .object = payload_obj });
    try std.testing.expectEqual(HookEventClassification.unknown_unsupported, std.meta.activeTag(classification));
}

test "hook malformed JSON keeps existing parse error behavior" {
    if (std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"version\":1", .{})) |parsed| {
        defer parsed.deinit();
        return error.TestExpectedError;
    } else |_| {}
}

test "hook fail-closes unsupported PreToolUse and rejects missing PermissionRequest fields" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var policy_obj = try core_api.loadPolicyPreset(allocator, .strict);
    defer policy_obj.deinit();

    var empty_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer empty_obj.deinit(allocator);
    const empty_payload = std.json.Value{ .object = empty_obj };

    var result = try evaluateHookForTest(allocator, @ptrCast(@alignCast(policy_obj)), .codex, .PreToolUse, empty_payload, false);
    defer result.deinit(allocator);
    try std.testing.expectEqual(PluginDecision.block, result.decision);
    try std.testing.expectEqualStrings("command", result.category);
    try std.testing.expectError(error.MissingRequiredField, evaluateHookForTest(allocator, @ptrCast(@alignCast(policy_obj)), .claude, .PermissionRequest, empty_payload, false));
}

test "hook response JSON format is valid" {
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);

    const response = HookResponse{
        .decision = .allow,
        .risk = .low,
        .category = "command",
        .reason = "matched allow rule",
        .rule = "commands.allow[0]",
        .message = "Allowed by Orca policy.",
        .redactions = &.{},
        .host_limitations = &.{},
    };

    try writeHookResponse(&stdout_writer, response);

    const output = stdout_writer.buffered();
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, output, .{});
    defer parsed.deinit();

    try std.testing.expectEqualStrings("allow", parsed.value.object.get("decision").?.string);
    try std.testing.expectEqualStrings("low", parsed.value.object.get("risk").?.string);
}

test "hook stdout does not include human logs" {
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);

    const response = HookResponse{
        .decision = .allow,
        .risk = .low,
        .category = "command",
        .reason = "test",
        .rule = null,
        .message = "test message",
        .redactions = &.{},
        .host_limitations = &.{},
    };

    try writeHookResponse(&stdout_writer, response);

    const output = stdout_writer.buffered();
    // Should be valid JSON only, no human-readable prefixes
    try std.testing.expect(std.mem.startsWith(u8, output, "{"));
    try std.testing.expect(std.mem.endsWith(u8, output, "}\n"));
}

test "hook opencode session.created returns allow" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var policy_obj = try core_api.loadPolicyPreset(allocator, .strict);
    defer policy_obj.deinit();

    var empty_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer empty_obj.deinit(allocator);
    var result = try evaluateHookForTest(allocator, @ptrCast(@alignCast(policy_obj)), .opencode, .SessionStart, std.json.Value{ .object = empty_obj }, false);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.allow, result.decision);
    try std.testing.expectEqual(RiskLevel.low, result.risk);
}

test "hook opencode informational events are allowed" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var redactions: std.ArrayList(RedactionEntry) = .empty;
    var limitations: std.ArrayList([]const u8) = .empty;
    try limitations.append(allocator, try allocator.dupe(u8, "Hook enforcement is additive; does not replace orca run supervision."));
    try limitations.append(allocator, try allocator.dupe(u8, "OpenCode informational event: no policy evaluation needed."));

    var result = try makeInformationalResponse(allocator, .allow, .low, "session", "informational event", "OpenCode event acknowledged by Orca.", &redactions, &limitations);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.allow, result.decision);
    try std.testing.expectEqual(RiskLevel.low, result.risk);
    try std.testing.expect(std.mem.indexOf(u8, result.message, "acknowledged") != null);
}

test "mapOpenCodeEvent maps known events correctly" {
    try std.testing.expectEqual(Event.SessionStart, mapOpenCodeEvent("session.created").?);
    try std.testing.expectEqual(Event.PreToolUse, mapOpenCodeEvent("tool.execute.before").?);
    try std.testing.expectEqual(Event.PostToolUse, mapOpenCodeEvent("tool.execute.after").?);
    try std.testing.expectEqual(Event.PermissionRequest, mapOpenCodeEvent("permission.asked").?);
    try std.testing.expectEqual(null, mapOpenCodeEvent("permission.replied"));
    try std.testing.expectEqual(null, mapOpenCodeEvent("unknown.event"));
}

test "isOpenCodeInformationalEvent identifies informational events" {
    try std.testing.expect(isOpenCodeInformationalEvent("permission.replied"));
    try std.testing.expect(isOpenCodeInformationalEvent("file.edited"));
    try std.testing.expect(isOpenCodeInformationalEvent("command.executed"));
    try std.testing.expect(isOpenCodeInformationalEvent("session.updated"));
    try std.testing.expect(isOpenCodeInformationalEvent("session.idle"));
    try std.testing.expect(isOpenCodeInformationalEvent("session.error"));
    try std.testing.expect(isOpenCodeInformationalEvent("shell.env"));
    try std.testing.expect(!isOpenCodeInformationalEvent("tool.execute.before"));
    try std.testing.expect(!isOpenCodeInformationalEvent("session.created"));
}

test "hook openclaw session.start returns allow" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var policy_obj = try core_api.loadPolicyPreset(allocator, .strict);
    defer policy_obj.deinit();

    var empty_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer empty_obj.deinit(allocator);
    var result = try evaluateHookForTest(allocator, @ptrCast(@alignCast(policy_obj)), .openclaw, .SessionStart, std.json.Value{ .object = empty_obj }, false);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.allow, result.decision);
    try std.testing.expectEqual(RiskLevel.low, result.risk);
}

test "hook openclaw informational events are allowed" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var redactions: std.ArrayList(RedactionEntry) = .empty;
    var limitations: std.ArrayList([]const u8) = .empty;
    try limitations.append(allocator, try allocator.dupe(u8, "Hook enforcement is additive; does not replace orca run supervision."));
    try limitations.append(allocator, try allocator.dupe(u8, "OpenClaw informational event: no policy evaluation needed."));

    var result = try makeInformationalResponse(allocator, .allow, .low, "session", "informational event", "OpenClaw event acknowledged by Orca.", &redactions, &limitations);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.allow, result.decision);
    try std.testing.expectEqual(RiskLevel.low, result.risk);
    try std.testing.expect(std.mem.indexOf(u8, result.message, "acknowledged") != null);
}

test "mapOpenClawEvent maps known events correctly" {
    try std.testing.expectEqual(Event.SessionStart, mapOpenClawEvent("session.start").?);
    try std.testing.expectEqual(Event.PreToolUse, mapOpenClawEvent("tool.before").?);
    try std.testing.expectEqual(Event.PostToolUse, mapOpenClawEvent("tool.after").?);
    try std.testing.expectEqual(Event.PermissionRequest, mapOpenClawEvent("permission.before").?);
    try std.testing.expectEqual(Event.SessionEnd, mapOpenClawEvent("session.end").?);
    try std.testing.expectEqual(null, mapOpenClawEvent("permission.after"));
    try std.testing.expectEqual(null, mapOpenClawEvent("unknown.event"));
}

test "isOpenClawInformationalEvent identifies informational events" {
    try std.testing.expect(isOpenClawInformationalEvent("permission.after"));
    try std.testing.expect(isOpenClawInformationalEvent("session.end"));
    try std.testing.expect(!isOpenClawInformationalEvent("tool.before"));
    try std.testing.expect(!isOpenClawInformationalEvent("session.start"));
    try std.testing.expect(!isOpenClawInformationalEvent("permission.before"));
}

test "hook hermes on_session_start returns allow" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var policy_obj = try core_api.loadPolicyPreset(allocator, .strict);
    defer policy_obj.deinit();

    var empty_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer empty_obj.deinit(allocator);

    var result = try evaluateHookForTest(allocator, @ptrCast(@alignCast(policy_obj)), .hermes, .SessionStart, std.json.Value{ .object = empty_obj }, false);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.allow, result.decision);
}

test "hook hermes pre_tool_call with nested protected file path returns block" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var policy_obj = try core_api.loadPolicyPreset(allocator, .strict);
    defer policy_obj.deinit();

    var input_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer input_obj.deinit(allocator);
    try input_obj.put(allocator, "path", std.json.Value{ .string = "/etc/passwd" });

    var payload_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload_obj.deinit(allocator);
    try payload_obj.put(allocator, "tool", std.json.Value{ .string = "write" });
    try payload_obj.put(allocator, "input", std.json.Value{ .object = input_obj });

    var result = try evaluateHookForTest(allocator, @ptrCast(@alignCast(policy_obj)), .hermes, .PreToolUse, std.json.Value{ .object = payload_obj }, false);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.block, result.decision);
}

test "hook hermes pre_llm_call reads canonical user_message" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var policy_obj = try core_api.loadPolicyPreset(allocator, .strict);
    defer policy_obj.deinit();

    var payload_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload_obj.deinit(allocator);
    try payload_obj.put(allocator, "user_message", std.json.Value{ .string = "my token is ghp_fake_secret_value" });

    var result = try evaluateHookForTest(allocator, @ptrCast(@alignCast(policy_obj)), .hermes, .UserPromptSubmit, std.json.Value{ .object = payload_obj }, false);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.warn, result.decision);
    try std.testing.expect(result.redactions.len > 0);
}

test "hook bounded reader rejects oversized payload instead of truncating" {
    var payload = try std.testing.allocator.alloc(u8, max_payload_len + 1);
    defer std.testing.allocator.free(payload);
    @memset(payload[0..max_payload_len], ' ');
    payload[0] = '{';
    payload[1] = '}';
    payload[max_payload_len] = 'x';

    var reader: std.Io.Reader = .fixed(payload);
    try std.testing.expectError(error.PayloadTooLarge, readBoundedIoReader(std.testing.allocator, max_payload_len, &reader));
}

test "mapHermesEvent maps known events correctly" {
    try std.testing.expectEqual(Event.SessionStart, mapHermesEvent("on_session_start").?);
    try std.testing.expectEqual(Event.PreToolUse, mapHermesEvent("pre_tool_call").?);
    try std.testing.expectEqual(Event.PostToolUse, mapHermesEvent("post_tool_call").?);
    try std.testing.expectEqual(Event.UserPromptSubmit, mapHermesEvent("pre_llm_call").?);
    try std.testing.expectEqual(Event.SessionEnd, mapHermesEvent("on_session_end").?);
    try std.testing.expectEqual(Event.SessionEnd, mapHermesEvent("on_session_finalize").?);
    try std.testing.expectEqual(Event.SessionEnd, mapHermesEvent("on_session_reset").?);
    try std.testing.expectEqual(null, mapHermesEvent("post_llm_call"));
    try std.testing.expectEqual(null, mapHermesEvent("unknown.event"));
}

test "isHermesInformationalEvent identifies informational events" {
    try std.testing.expect(isHermesInformationalEvent("post_llm_call"));
    try std.testing.expect(isHermesInformationalEvent("subagent_stop"));
    try std.testing.expect(!isHermesInformationalEvent("pre_tool_call"));
    try std.testing.expect(!isHermesInformationalEvent("on_session_start"));
}

test "hermes correlation extracts nested identifiers and prefers parent for subagents" {
    const allocator = std.testing.allocator;
    var kwargs = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer kwargs.deinit(allocator);
    try kwargs.put(allocator, "session_id", .{ .string = "child-session" });
    try kwargs.put(allocator, "parent_session_id", .{ .string = "parent-session" });
    try kwargs.put(allocator, "task_id", .{ .string = "task-42" });
    var payload = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload.deinit(allocator);
    try payload.put(allocator, "kwargs", .{ .object = kwargs });

    const value = std.json.Value{ .object = payload };
    try std.testing.expectEqualStrings("child-session", extractHermesSessionId(value, "pre_tool_call").?);
    try std.testing.expectEqualStrings("parent-session", extractHermesSessionId(value, "subagent_stop").?);
}

test "hermes activity preserves approval decisions and marks blocks as deny" {
    try std.testing.expectEqualStrings("allow", hermesFeedDecisionTag(.allow));
    try std.testing.expectEqualStrings("ask", hermesFeedDecisionTag(.ask));
    try std.testing.expectEqualStrings("warn", hermesFeedDecisionTag(.warn));
    try std.testing.expectEqualStrings("deny", hermesFeedDecisionTag(.block));
    try std.testing.expectEqualStrings("hermes_tool_call_blocked", hermesFeedEventType("pre_tool_call", .ask));
    try std.testing.expectEqualStrings("hermes_prompt_review", hermesFeedEventType("pre_llm_call", .warn));
    try std.testing.expectEqualStrings("hermes_session_started", hermesFeedEventType("on_session_start", .allow));
    try std.testing.expectEqualStrings("hermes_tool_call_completed", hermesFeedEventType("post_tool_call", .allow));
    try std.testing.expectEqualStrings("hermes_session_ended", hermesFeedEventType("on_session_end", .allow));
    try std.testing.expectEqualStrings("hermes_session_ended", hermesFeedEventType("on_session_finalize", .allow));
    try std.testing.expectEqualStrings("hermes_session_ended", hermesFeedEventType("on_session_reset", .allow));
    try std.testing.expectEqualStrings("hermes_subagent_stopped", hermesFeedEventType("subagent_stop", .allow));
}

test "hermes tool veto persists once with session and redacted reason" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", allocator);
    defer allocator.free(root);

    var payload = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload.deinit(allocator);
    try payload.put(allocator, "session_id", .{ .string = "hermes-session-42" });
    try payload.put(allocator, "tool_name", .{ .string = "write" });

    var redactions: std.ArrayList(RedactionEntry) = .empty;
    var limitations: std.ArrayList([]const u8) = .empty;
    var result = try makeInformationalResponse(
        allocator,
        .ask,
        .high,
        "tool",
        "approval required for OPENAI_API_KEY=sk-fakeSyntheticOpenAIKey1234567890",
        "Approval required by Orca.",
        &redactions,
        &limitations,
    );
    defer result.deinit(allocator);

    recordHermesHookActivity(std.testing.io, allocator, root, "pre_tool_call", .{ .object = payload }, result);
    const loaded = try feed_writer.loadRecent(std.testing.io, allocator, root, 4);
    defer {
        for (loaded) |*item| item.deinit(allocator);
        allocator.free(loaded);
    }

    try std.testing.expectEqual(@as(usize, 1), loaded.len);
    try std.testing.expectEqualStrings("ask", loaded[0].record.decision);
    try std.testing.expectEqualStrings("hermes_tool_call_blocked", loaded[0].record.event_type);
    try std.testing.expectEqualStrings("hermes-session-42", loaded[0].record.session_id.?);
    try std.testing.expect(rust_visibility.isBlockedFeedRecord(loaded[0].record));
    try std.testing.expect(std.mem.indexOf(u8, loaded[0].raw, "sk-fakeSyntheticOpenAIKey1234567890") == null);
}
test "hook codex PreToolUse with safe command returns allow" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var result = try runShellRoute(allocator, "git status", null, false, mockDaemonAllowEvaluator);
    defer result.deinit(allocator);
    try std.testing.expectEqual(PluginDecision.allow, result.decision);
    try std.testing.expectEqual(RiskLevel.low, result.risk);
}

test "hook codex PreToolUse with dangerous command returns block" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var result = try runShellRoute(allocator, "rm -rf /", null, false, mockDaemonDenyEvaluator);
    defer result.deinit(allocator);
    try std.testing.expectEqual(PluginDecision.block, result.decision);
}

test "hook opencode tool.execute.before with safe command returns allow" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var result = try runShellRoute(allocator, "git status", null, false, mockDaemonAllowEvaluator);
    defer result.deinit(allocator);
    try std.testing.expectEqual(PluginDecision.allow, result.decision);
}

test "hook opencode tool.execute.before with dangerous command returns block" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var result = try runShellRoute(allocator, "rm -rf /", null, false, mockDaemonDenyEvaluator);
    defer result.deinit(allocator);
    try std.testing.expectEqual(PluginDecision.block, result.decision);
}

test "hook openclaw tool.before with safe command returns allow" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var result = try runShellRoute(allocator, "git status", null, false, mockDaemonAllowEvaluator);
    defer result.deinit(allocator);
    try std.testing.expectEqual(PluginDecision.allow, result.decision);
}

test "hook openclaw tool.before with dangerous command returns block" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var result = try runShellRoute(allocator, "rm -rf /", null, false, mockDaemonDenyEvaluator);
    defer result.deinit(allocator);
    try std.testing.expectEqual(PluginDecision.block, result.decision);
}

test "hook hermes pre_tool_call with dangerous command returns block" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var result = try runShellRoute(allocator, "rm -rf /", null, false, mockDaemonDenyEvaluator);
    defer result.deinit(allocator);
    try std.testing.expectEqual(PluginDecision.block, result.decision);
}

test "hook hermes pre_tool_call with canonical tool_input command returns block" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var result = try runShellRoute(allocator, "rm -rf /", null, false, mockDaemonDenyEvaluator);
    defer result.deinit(allocator);
    try std.testing.expectEqual(PluginDecision.block, result.decision);
}

test "hook daemon Error does not produce allow for shell command" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var result = try runShellRoute(allocator, "git status", null, false, mockDaemonErrorEvaluator);
    defer result.deinit(allocator);
    try std.testing.expectEqual(PluginDecision.block, result.decision);
    try std.testing.expect(std.mem.indexOf(u8, result.message, "evaluation error") != null);
}

test "hook shell command forwards command and cwd to daemon Evaluate" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    shell_eval.test_last_evaluate_command = null;
    shell_eval.test_last_evaluate_cwd = null;

    var result = try runShellRoute(allocator, "git status", "/tmp/repo", false, mockDaemonAllowEvaluator);
    defer result.deinit(allocator);

    try std.testing.expectEqualStrings("git status", shell_eval.test_last_evaluate_command.?);
    try std.testing.expectEqualStrings("/tmp/repo", shell_eval.test_last_evaluate_cwd.?);
    try std.testing.expectEqual(PluginDecision.allow, result.decision);
}

test "hook daemon Deny preserves reason and rule metadata" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var result = try runShellRoute(allocator, "rm -rf /", null, false, mockDaemonDenyEvaluator);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.block, result.decision);
    try std.testing.expectEqual(RiskLevel.critical, result.risk);
    try std.testing.expectEqualStrings("core.filesystem:destructive_rm", result.rule.?);
    try std.testing.expect(std.mem.indexOf(u8, result.message, "recursive delete") != null);
}

test "hook daemon unavailable blocks shell command" {
    const reason = daemonUnavailableReason(error.SocketConnectFailed);
    try std.testing.expect(std.mem.indexOf(u8, reason, "socket connect failed") != null);
}

test "hook non-shell PreToolUse keeps zig native file evaluation" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var policy_obj = try core_api.loadPolicyPreset(allocator, .strict);
    defer policy_obj.deinit();

    var payload_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload_obj.deinit(allocator);
    try payload_obj.put(allocator, "tool", std.json.Value{ .string = "edit" });
    try payload_obj.put(allocator, "path", std.json.Value{ .string = "/etc/passwd" });

    var result = try evaluateHookForTest(allocator, @ptrCast(@alignCast(policy_obj)), .claude, .PreToolUse, std.json.Value{ .object = payload_obj }, false);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.block, result.decision);
    try std.testing.expectEqualStrings("file.write", result.category);
}

test "hookResponseFromDaemonEvaluate rejects unexpected daemon payload" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var redactions: std.ArrayList(RedactionEntry) = .empty;
    var limitations: std.ArrayList([]const u8) = .empty;
    try limitations.append(allocator, try allocator.dupe(u8, "limit"));

    var parsed = try daemon.parseResponse(allocator, "{\"id\":1,\"result\":{\"status\":\"Pong\"}}");
    defer parsed.deinit();

    var result = try hookResponseFromDaemonEvaluate(allocator, parsed.value.result, false, &redactions, &limitations);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.block, result.decision);
}

test "hook shell route honors ci mode for daemon warn allow" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var warn_result = try runShellRoute(allocator, "git status", null, false, mockDaemonWarnAllowEvaluator);
    defer warn_result.deinit(allocator);
    try std.testing.expectEqual(PluginDecision.warn, warn_result.decision);

    var block_result = try runShellRoute(allocator, "git status", null, true, mockDaemonWarnAllowEvaluator);
    defer block_result.deinit(allocator);
    try std.testing.expectEqual(PluginDecision.block, block_result.decision);
}

test "hook codex deny output skips stdout JSON" {
    try std.testing.expect(isCodexDenyOutput(.codex, .block));
    try std.testing.expect(!isCodexDenyOutput(.codex, .allow));
    try std.testing.expect(!isCodexDenyOutput(.claude, .block));
}

test "hook guard sentinel format is machine-parseable and stable" {
    // The sentinel is the single recognisable signal an agent scraping stderr can branch on.
    // Provenance + consequence + recourse, newline-terminated, starts with the parse tag.
    try std.testing.expect(std.mem.startsWith(u8, guard_sentinel_prefix, "[[ORCA-GUARD]]"));
    try std.testing.expect(std.mem.indexOf(u8, guard_sentinel_prefix, "did not execute") != null);
    try std.testing.expect(std.mem.indexOf(u8, guard_sentinel_prefix, "no side effects") != null);
    try std.testing.expect(std.mem.indexOf(u8, guard_sentinel_prefix, "Recourse") != null);
    try std.testing.expect(std.mem.indexOf(u8, guard_sentinel_prefix, "orca explain") != null);
    try std.testing.expect(guard_sentinel_prefix[guard_sentinel_prefix.len - 1] == '\n');
}

test "hook daemon deny includes remediation fields for flexible hosts" {
    const allocator = std.testing.allocator;
    const json =
        \\{"status":"Deny","reason":"blocked","pack_id":"core.filesystem","pattern_name":"destructive_rm","severity":"critical","explanation":"recursive delete","suggestions":[{"command":"rm -rf ./build","description":"Limit delete scope","platform":"any"}]}
    ;
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    var redactions: std.ArrayList(RedactionEntry) = .empty;
    defer {
        for (redactions.items) |r| r.deinit(allocator);
        redactions.deinit(allocator);
    }
    var limitations: std.ArrayList([]const u8) = .empty;
    defer {
        for (limitations.items) |l| allocator.free(l);
        limitations.deinit(allocator);
    }
    var result = try hookResponseFromDaemonEvaluate(allocator, parsed.value, false, &redactions, &limitations);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.block, result.decision);
    try std.testing.expect(result.rule != null);
    try std.testing.expect(result.suggestions.len >= 1);
    try std.testing.expect(result.remediation_commands.len >= 2);
    try std.testing.expect(std.mem.indexOf(u8, result.remediation_commands[0], "orca explain") != null);

    var out_buf: [4096]u8 = undefined;
    var out: std.Io.Writer = .fixed(&out_buf);
    try writeHookResponse(&out, result);
    const written = out.buffered();
    try std.testing.expect(std.mem.indexOf(u8, written, "\"rule_id\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "\"suggestions\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "\"remediation_commands\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "orca allowlist") != null);
}

test "hook guard sentinel is gated to the codex block audience" {
    // The sentinel prefix is only meaningful when emitted on the Codex deny stderr path;
    // non-Codex hosts and allow/warn decisions must never expose it. We assert the gate
    // (isCodexDenyOutput) stays exclusive so no future change leaks machine text to humans.
    inline for ([_]Host{ .codex, .claude, .opencode, .openclaw, .hermes }) |h| {
        inline for ([_]PluginDecision{ .allow, .block, .warn, .ask, .context_only, .err }) |d| {
            const gated = isCodexDenyOutput(h, d);
            try std.testing.expect(gated == (h == .codex and d == .block));
        }
    }
}

test "hook codex shell deny uses exit code 2" {
    try std.testing.expectEqual(@as(u8, 2), hookExitCode(.codex, .block, false));
    try std.testing.expectEqual(exit_codes.success, hookExitCode(.codex, .allow, false));
    try std.testing.expectEqual(exit_codes.success, hookExitCode(.claude, .block, false));
    try std.testing.expectEqual(@as(u8, 2), hookExitCode(.codex, .block, true));
}

test "hook classifies non-shell tool with incidental command as zig native route" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var payload_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload_obj.deinit(allocator);
    try payload_obj.put(allocator, "tool", std.json.Value{ .string = "edit" });
    try payload_obj.put(allocator, "path", std.json.Value{ .string = "/tmp/example.txt" });
    try payload_obj.put(allocator, "command", std.json.Value{ .string = "git status" });

    const route = preToolUseRoute(std.json.Value{ .object = payload_obj });
    try std.testing.expectEqual(PreToolUseRoute.zig_native, std.meta.activeTag(route));
    try std.testing.expectEqual(NonShellHookEvent.file_write, route.zig_native);
}

test "hook daemon deny redacts matched_text_preview from agent-visible output" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var result = try runShellRoute(allocator, "rm -rf /", null, false, mockDaemonDenyWithPreviewEvaluator);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.block, result.decision);
    try std.testing.expectEqual(RiskLevel.critical, result.risk);
    try std.testing.expect(std.mem.indexOf(u8, result.message, "rm -rf") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.reason, "rm -rf") == null);
    try std.testing.expect(result.redactions.len > 0);
}

test "hook daemon strings are redacted at agent-visible boundary" {
    const allocator = std.testing.allocator;
    const sentinel = "ghp_abcdefghijklmnopqrstuvwxyz123456";
    const json = try std.fmt.allocPrint(allocator, "{{\"status\":\"Deny\",\"reason\":\"token={s}\",\"explanation\":\"Authorization: Bearer {s}\",\"severity\":\"high\"}}", .{ sentinel, sentinel });
    defer allocator.free(json);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    var redactions: std.ArrayList(RedactionEntry) = .empty;
    defer redactions.deinit(allocator);
    var limitations: std.ArrayList([]const u8) = .empty;
    defer limitations.deinit(allocator);
    var result = try hookResponseFromDaemonEvaluate(allocator, parsed.value, false, &redactions, &limitations);
    defer result.deinit(allocator);
    try std.testing.expect(std.mem.indexOf(u8, result.reason, sentinel) == null);
    try std.testing.expect(std.mem.indexOf(u8, result.message, sentinel) == null);
}

test "hook daemon malformed response blocks shell command" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var result = try runShellRoute(allocator, "git status", null, false, mockDaemonMalformedEvaluator);
    defer result.deinit(allocator);
    try std.testing.expectEqual(PluginDecision.block, result.decision);
}

test "hook daemon unavailable blocks shell command via fail-closed route" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var result = try runShellRoute(allocator, "git status", null, false, mockDaemonUnavailableEvaluator);
    defer result.deinit(allocator);
    try std.testing.expectEqual(PluginDecision.block, result.decision);
    try std.testing.expect(std.mem.indexOf(u8, result.reason, "socket connect failed") != null);
}

test "hook daemon timeout blocks shell command via fail-closed route" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var result = try runShellRoute(allocator, "git status", null, false, mockDaemonTimeoutEvaluator);
    defer result.deinit(allocator);
    try std.testing.expectEqual(PluginDecision.block, result.decision);
    try std.testing.expect(std.mem.indexOf(u8, result.reason, "socket read failed") != null);
}

test "hook daemon protocol mismatch blocks shell command via fail-closed route" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var result = try runShellRoute(allocator, "git status", null, false, mockDaemonProtocolMismatchEvaluator);
    defer result.deinit(allocator);
    try std.testing.expectEqual(PluginDecision.block, result.decision);
    try std.testing.expect(std.mem.indexOf(u8, result.reason, "incompatible daemon protocol") != null);
}

test "hook daemon deny maps capitalized severity to risk level" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var result = try runShellRoute(allocator, "rm -rf /", null, false, mockDaemonDenyWithPreviewEvaluator);
    defer result.deinit(allocator);
    try std.testing.expectEqual(RiskLevel.critical, result.risk);
}

test "hook evaluatePreToolUse routes shell PreToolUse through daemon evaluator" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var policy_obj = try core_api.loadPolicyPreset(allocator, .strict);
    defer policy_obj.deinit();

    var payload_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload_obj.deinit(allocator);
    try payload_obj.put(allocator, "tool", std.json.Value{ .string = "bash" });
    try payload_obj.put(allocator, "command", std.json.Value{ .string = "git status" });

    var redactions: std.ArrayList(RedactionEntry) = .empty;
    var limitations: std.ArrayList([]const u8) = .empty;
    try shellRouteSetup(allocator, &redactions, &limitations);

    shell_eval.test_last_evaluate_command = null;
    shell_eval.test_last_evaluate_cwd = null;

    var result = try evaluatePreToolUseForTest(
        allocator,
        @ptrCast(@alignCast(policy_obj)),
        std.json.Value{ .object = payload_obj },
        false,
        &redactions,
        &limitations,
        mockDaemonAllowEvaluator,
    );
    defer result.deinit(allocator);

    try std.testing.expectEqualStrings("git status", shell_eval.test_last_evaluate_command.?);
    try std.testing.expectEqual(PluginDecision.allow, result.decision);
    try std.testing.expectEqualStrings("command", result.category);
}

test "hook PermissionRequest stays on zig policy path" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var policy_obj = try core_api.loadPolicyPreset(allocator, .strict);
    defer policy_obj.deinit();

    var payload_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload_obj.deinit(allocator);
    try payload_obj.put(allocator, "kind", std.json.Value{ .string = "file_write" });
    try payload_obj.put(allocator, "target", std.json.Value{ .string = "/etc/passwd" });

    var result = try evaluateHookForTest(allocator, @ptrCast(@alignCast(policy_obj)), .claude, .PermissionRequest, std.json.Value{ .object = payload_obj }, false);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.block, result.decision);
    try std.testing.expectEqualStrings("file_write", result.category);
}

test "hook session informational events stay on zig path without daemon" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var policy_obj = try core_api.loadPolicyPreset(allocator, .strict);
    defer policy_obj.deinit();

    var empty_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer empty_obj.deinit(allocator);
    const empty_payload = std.json.Value{ .object = empty_obj };

    for (&[_]Event{ .PostToolUse, .Stop, .SessionEnd }) |event| {
        var result = try evaluateHookForTest(allocator, @ptrCast(@alignCast(policy_obj)), .codex, event, empty_payload, false);
        defer result.deinit(allocator);
        try std.testing.expectEqual(PluginDecision.allow, result.decision);
        try std.testing.expectEqual(RiskLevel.low, result.risk);
    }
}

test "hook UserPromptSubmit stays on zig prompt path" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var policy_obj = try core_api.loadPolicyPreset(allocator, .trusted);
    defer policy_obj.deinit();

    var payload_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload_obj.deinit(allocator);
    try payload_obj.put(allocator, "prompt", std.json.Value{ .string = "summarize the repo" });

    var result = try evaluateHookForTest(allocator, @ptrCast(@alignCast(policy_obj)), .claude, .UserPromptSubmit, std.json.Value{ .object = payload_obj }, false);
    defer result.deinit(allocator);

    try std.testing.expect(result.decision == .allow or result.decision == .ask or result.decision == .warn);
    try std.testing.expectEqualStrings("prompt", result.category);
}

test "hook shell route ci mode converts daemon soft block to block" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var ask_result = try runShellRoute(allocator, "git status", null, false, mockDaemonSoftBlockAllowEvaluator);
    defer ask_result.deinit(allocator);
    try std.testing.expectEqual(PluginDecision.ask, ask_result.decision);

    var block_result = try runShellRoute(allocator, "git status", null, true, mockDaemonSoftBlockAllowEvaluator);
    defer block_result.deinit(allocator);
    try std.testing.expectEqual(PluginDecision.block, block_result.decision);
}

test "hook daemon allow maps to unified allow JSON output" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var result = try runShellRoute(allocator, "git status", null, false, mockDaemonAllowEvaluator);
    defer result.deinit(allocator);

    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    try writeHookResponse(&stdout_writer, result);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, stdout_writer.buffered(), .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("allow", parsed.value.object.get("decision").?.string);
    try std.testing.expectEqualStrings("low", parsed.value.object.get("risk").?.string);
    try std.testing.expectEqualStrings("command", parsed.value.object.get("category").?.string);
}

test "hook daemon deny maps to unified block JSON output" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var result = try runShellRoute(allocator, "rm -rf /", null, false, mockDaemonDenyEvaluator);
    defer result.deinit(allocator);
    try std.testing.expectEqual(PluginDecision.block, result.decision);

    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    try writeHookResponse(&stdout_writer, result);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, stdout_writer.buffered(), .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("block", parsed.value.object.get("decision").?.string);
    try std.testing.expectEqualStrings("critical", parsed.value.object.get("risk").?.string);
    try std.testing.expect(parsed.value.object.get("rule").?.string.len > 0);
}

test "hook daemon deny without pattern_name uses pack_id and redacts raw reason" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var result = try runShellRoute(allocator, "rm -rf /", null, false, mockDaemonDenyPackOnlyEvaluator);
    defer result.deinit(allocator);

    try std.testing.expectEqualStrings("git", result.rule.?);
    try std.testing.expect(std.mem.indexOf(u8, result.reason, "rm -rf") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.message, "recursive delete") != null);
}

test "hook evaluatePreToolUse fail-closes malformed shell payload before daemon call" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var policy_obj = try core_api.loadPolicyPreset(allocator, .strict);
    defer policy_obj.deinit();

    var payload_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload_obj.deinit(allocator);
    try payload_obj.put(allocator, "tool", std.json.Value{ .string = "bash" });

    var redactions: std.ArrayList(RedactionEntry) = .empty;
    var limitations: std.ArrayList([]const u8) = .empty;
    try shellRouteSetup(allocator, &redactions, &limitations);

    shell_eval.test_last_evaluate_command = null;

    var result = try evaluatePreToolUseForTest(
        allocator,
        @ptrCast(@alignCast(policy_obj)),
        std.json.Value{ .object = payload_obj },
        false,
        &redactions,
        &limitations,
        mockDaemonAllowEvaluator,
    );
    defer result.deinit(allocator);

    try std.testing.expect(shell_eval.test_last_evaluate_command == null);
    try std.testing.expectEqual(PluginDecision.block, result.decision);
}
