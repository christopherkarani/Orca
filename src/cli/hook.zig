const std = @import("std");
const core = @import("orca_core").core;
const supervisor = core.supervisor;
const core_api = @import("orca_core").api;
const policy = @import("orca_core").policy;

const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");

// Maximum JSON payload size to prevent memory exhaustion from hostile hosts.
const max_payload_len = 256 * 1024; // 256 KiB

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

    if (host == .hermes and isHermesInformationalEvent(request_event)) {
        var redactions: std.ArrayList(RedactionEntry) = .empty;
        var limitations: std.ArrayList([]const u8) = .empty;
        try limitations.append(allocator, try allocator.dupe(u8, "Hook enforcement is additive; does not replace orca run supervision."));
        try limitations.append(allocator, try allocator.dupe(u8, "Hermes informational event: no policy evaluation needed."));

        var result = try makeInformationalResponse(allocator, .allow, .low, "session", "informational event", "Hermes event acknowledged by Orca.", &redactions, &limitations);
        defer result.deinit(allocator);
        try writeHookResponse(stdout, result);
        return exit_codes.success;
    }

    // Load policy
    const root = supervisor.resolveWorkspaceRoot(io, allocator, null, ".") catch try allocator.dupe(u8, ".");
    defer allocator.free(root);
    var loaded = core_api.discoverPolicy(io, allocator, null, root) catch |err| {
        try stderr.print("orca hook: failed to load policy: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer loaded.deinit();

    // Extract payload object
    var empty_payload: std.json.ObjectMap = .empty;
    defer empty_payload.deinit(allocator);
    const hook_payload = parsed.value.object.get("payload") orelse std.json.Value{ .object = empty_payload };

    // Evaluate via host adapter
    var result = evaluateHook(allocator, loaded.innerPtr(), host, event, hook_payload, ci_mode) catch |err| {
        try stderr.print("orca hook: evaluation failed: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer result.deinit(allocator);

    // Emit JSON response to stdout
    try writeHookResponse(stdout, result);

    // Log debug info to stderr only
    if (result.rule) |rule| {
        try stderr.print("[hook] matched rule: {s}\n", .{rule});
    }

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

    fn deinit(self: *HookResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.reason);
        allocator.free(self.message);
        allocator.free(self.category);
        if (self.rule) |r| allocator.free(r);
        for (self.redactions) |r| r.deinit(allocator);
        allocator.free(self.redactions);
        for (self.host_limitations) |l| allocator.free(l);
        allocator.free(self.host_limitations);
        self.* = undefined;
    }
};

fn evaluateHook(
    allocator: std.mem.Allocator,
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
            // Try to extract command from various payload shapes
            const command_text = extractString(payload, "command") orelse
                extractNestedString(payload, &.{ "tool", "command" }) orelse
                extractNestedString(payload, &.{ "tool_input", "command" }) orelse
                extractNestedString(payload, &.{ "args", "command" }) orelse
                extractNestedString(payload, &.{ "params", "command" }) orelse
                extractNestedString(payload, &.{ "input", "command" }) orelse
                extractNestedString(payload, &.{ "data", "command" }) orelse
                extractNestedString(payload, &.{ "data", "input", "command" }) orelse
                extractNestedString(payload, &.{ "kwargs", "command" }) orelse
                extractNestedString(payload, &.{ "kwargs", "args", "command" }) orelse
                extractNestedString(payload, &.{ "kwargs", "params", "command" }) orelse
                extractNestedString(payload, &.{ "kwargs", "tool_input", "command" });
            const tool_name = extractString(payload, "tool") orelse
                extractString(payload, "tool_name") orelse
                extractString(payload, "name") orelse
                extractNestedString(payload, &.{ "tool", "name" });

            if (command_text) |cmd| {
                // Shell-like tool usage: evaluate as command
                const evaluation = try core_api.explainAction(allocator, @ptrCast(policy_value), .command, cmd);
                defer evaluation.deinit(allocator);

                const decision = PluginDecision.fromDecisionResult(evaluation.decision.result, ci_mode);
                const risk = RiskLevel.fromScore(evaluation.decision.risk_score);

                return .{
                    .decision = decision,
                    .risk = risk,
                    .category = try allocator.dupe(u8, "command"),
                    .reason = try allocator.dupe(u8, evaluation.decision.reason),
                    .rule = if (evaluation.matched_rule) |rule| try allocator.dupe(u8, rule.id) else null,
                    .message = try buildMessage(allocator, decision, "command"),
                    .redactions = try redactions.toOwnedSlice(allocator),
                    .host_limitations = try limitations.toOwnedSlice(allocator),
                };
            } else {
                // Check if this is a file-editing tool with a path
                const path = extractString(payload, "path") orelse
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
                const is_file_tool = if (tool_name) |name| isFileTool(name) else false;

                if (path) |p| {
                    if (is_file_tool) {
                        const evaluation = try core_api.explainAction(allocator, @ptrCast(policy_value), .file_write, p);
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
                    }
                }

                // Generic tool: evaluate as MCP/tool
                const generic_tool_name = tool_name orelse return error.MissingRequiredField;
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
            }
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

fn isFileTool(tool_name: []const u8) bool {
    const file_tools = &[_][]const u8{ "edit", "write", "file_write", "file_edit", "apply", "create_file", "write_file" };
    for (file_tools) |ft| {
        if (std.ascii.eqlIgnoreCase(tool_name, ft)) return true;
    }
    return false;
}

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
    var result = try evaluateHook(allocator, @ptrCast(@alignCast(policy_obj)), .codex, .SessionStart, std.json.Value{ .object = empty_obj }, false);
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

    var result = try evaluateHook(allocator, @ptrCast(@alignCast(policy_obj)), .claude, .UserPromptSubmit, std.json.Value{ .object = payload_obj }, false);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.warn, result.decision);
    try std.testing.expectEqual(RiskLevel.high, result.risk);
    try std.testing.expect(std.mem.indexOf(u8, result.message, "sensitive data") != null);
    try std.testing.expect(result.redactions.len > 0);
}

test "hook codex PreToolUse with safe command returns allow" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var policy_obj = try core_api.loadPolicyPreset(allocator, .strict);
    defer policy_obj.deinit();

    var payload_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload_obj.deinit(allocator);
    try payload_obj.put(allocator, "command", std.json.Value{ .string = "git status" });

    var result = try evaluateHook(allocator, @ptrCast(@alignCast(policy_obj)), .codex, .PreToolUse, std.json.Value{ .object = payload_obj }, false);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.allow, result.decision);
    // Risk may be low or unknown depending on whether policy assigns a score
    try std.testing.expect(result.risk == .low or result.risk == .unknown);
}

test "hook codex PreToolUse with dangerous command returns block" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var policy_obj = try core_api.loadPolicyPreset(allocator, .strict);
    defer policy_obj.deinit();

    var payload_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload_obj.deinit(allocator);
    try payload_obj.put(allocator, "command", std.json.Value{ .string = "rm -rf /" });

    var result = try evaluateHook(allocator, @ptrCast(@alignCast(policy_obj)), .codex, .PreToolUse, std.json.Value{ .object = payload_obj }, false);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.block, result.decision);
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

    var result = try evaluateHook(allocator, @ptrCast(@alignCast(policy_obj)), .claude, .PreToolUse, std.json.Value{ .object = payload_obj }, false);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.block, result.decision);
}

test "hook rejects missing required PreToolUse and PermissionRequest fields" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var policy_obj = try core_api.loadPolicyPreset(allocator, .strict);
    defer policy_obj.deinit();

    var empty_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer empty_obj.deinit(allocator);
    const empty_payload = std.json.Value{ .object = empty_obj };

    try std.testing.expectError(error.MissingRequiredField, evaluateHook(allocator, @ptrCast(@alignCast(policy_obj)), .codex, .PreToolUse, empty_payload, false));
    try std.testing.expectError(error.MissingRequiredField, evaluateHook(allocator, @ptrCast(@alignCast(policy_obj)), .claude, .PermissionRequest, empty_payload, false));
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

test "hook ci mode turns ask into block" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var policy_obj = try core_api.loadPolicyPreset(allocator, .strict);
    defer policy_obj.deinit();

    var payload_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload_obj.deinit(allocator);
    try payload_obj.put(allocator, "command", std.json.Value{ .string = "unknown-tool --help" });

    var result = try evaluateHook(allocator, @ptrCast(@alignCast(policy_obj)), .codex, .PreToolUse, std.json.Value{ .object = payload_obj }, true);
    defer result.deinit(allocator);

    // In CI mode, unknown commands that would ask should become block
    try std.testing.expectEqual(PluginDecision.block, result.decision);
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
    var result = try evaluateHook(allocator, @ptrCast(@alignCast(policy_obj)), .opencode, .SessionStart, std.json.Value{ .object = empty_obj }, false);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.allow, result.decision);
    try std.testing.expectEqual(RiskLevel.low, result.risk);
}

test "hook opencode tool.execute.before with safe command returns allow" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var policy_obj = try core_api.loadPolicyPreset(allocator, .strict);
    defer policy_obj.deinit();

    var payload_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload_obj.deinit(allocator);
    try payload_obj.put(allocator, "command", std.json.Value{ .string = "git status" });

    var result = try evaluateHook(allocator, @ptrCast(@alignCast(policy_obj)), .opencode, .PreToolUse, std.json.Value{ .object = payload_obj }, false);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.allow, result.decision);
    try std.testing.expect(result.risk == .low or result.risk == .unknown);
}

test "hook opencode tool.execute.before with dangerous command returns block" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var policy_obj = try core_api.loadPolicyPreset(allocator, .strict);
    defer policy_obj.deinit();

    var payload_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload_obj.deinit(allocator);
    try payload_obj.put(allocator, "command", std.json.Value{ .string = "rm -rf /" });

    var result = try evaluateHook(allocator, @ptrCast(@alignCast(policy_obj)), .opencode, .PreToolUse, std.json.Value{ .object = payload_obj }, false);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.block, result.decision);
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
    var result = try evaluateHook(allocator, @ptrCast(@alignCast(policy_obj)), .openclaw, .SessionStart, std.json.Value{ .object = empty_obj }, false);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.allow, result.decision);
    try std.testing.expectEqual(RiskLevel.low, result.risk);
}

test "hook openclaw tool.before with safe command returns allow" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var policy_obj = try core_api.loadPolicyPreset(allocator, .strict);
    defer policy_obj.deinit();

    var payload_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload_obj.deinit(allocator);
    try payload_obj.put(allocator, "command", std.json.Value{ .string = "git status" });

    var result = try evaluateHook(allocator, @ptrCast(@alignCast(policy_obj)), .openclaw, .PreToolUse, std.json.Value{ .object = payload_obj }, false);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.allow, result.decision);
    try std.testing.expect(result.risk == .low or result.risk == .unknown);
}

test "hook openclaw tool.before with dangerous command returns block" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var policy_obj = try core_api.loadPolicyPreset(allocator, .strict);
    defer policy_obj.deinit();

    var payload_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload_obj.deinit(allocator);
    try payload_obj.put(allocator, "command", std.json.Value{ .string = "rm -rf /" });

    var result = try evaluateHook(allocator, @ptrCast(@alignCast(policy_obj)), .openclaw, .PreToolUse, std.json.Value{ .object = payload_obj }, false);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.block, result.decision);
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

    var result = try evaluateHook(allocator, @ptrCast(@alignCast(policy_obj)), .hermes, .SessionStart, std.json.Value{ .object = empty_obj }, false);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.allow, result.decision);
}

test "hook hermes pre_tool_call with dangerous command returns block" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var policy_obj = try core_api.loadPolicyPreset(allocator, .strict);
    defer policy_obj.deinit();

    var input_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer input_obj.deinit(allocator);
    try input_obj.put(allocator, "command", std.json.Value{ .string = "rm -rf /" });

    var payload_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload_obj.deinit(allocator);
    try payload_obj.put(allocator, "tool", std.json.Value{ .string = "shell" });
    try payload_obj.put(allocator, "input", std.json.Value{ .object = input_obj });

    var result = try evaluateHook(allocator, @ptrCast(@alignCast(policy_obj)), .hermes, .PreToolUse, std.json.Value{ .object = payload_obj }, false);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.block, result.decision);
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

    var result = try evaluateHook(allocator, @ptrCast(@alignCast(policy_obj)), .hermes, .PreToolUse, std.json.Value{ .object = payload_obj }, false);
    defer result.deinit(allocator);

    try std.testing.expectEqual(PluginDecision.block, result.decision);
}

test "hook hermes pre_tool_call with canonical tool_input command returns block" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var policy_obj = try core_api.loadPolicyPreset(allocator, .strict);
    defer policy_obj.deinit();

    var tool_input_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer tool_input_obj.deinit(allocator);
    try tool_input_obj.put(allocator, "command", std.json.Value{ .string = "rm -rf /" });

    var payload_obj = try std.json.ObjectMap.init(allocator, &.{}, &.{});
    defer payload_obj.deinit(allocator);
    try payload_obj.put(allocator, "tool_name", std.json.Value{ .string = "terminal" });
    try payload_obj.put(allocator, "tool_input", std.json.Value{ .object = tool_input_obj });

    var result = try evaluateHook(allocator, @ptrCast(@alignCast(policy_obj)), .hermes, .PreToolUse, std.json.Value{ .object = payload_obj }, false);
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

    var result = try evaluateHook(allocator, @ptrCast(@alignCast(policy_obj)), .hermes, .UserPromptSubmit, std.json.Value{ .object = payload_obj }, false);
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
    try std.testing.expectEqual(null, mapHermesEvent("post_llm_call"));
    try std.testing.expectEqual(null, mapHermesEvent("unknown.event"));
}

test "isHermesInformationalEvent identifies informational events" {
    try std.testing.expect(isHermesInformationalEvent("post_llm_call"));
    try std.testing.expect(isHermesInformationalEvent("subagent_stop"));
    try std.testing.expect(!isHermesInformationalEvent("pre_tool_call"));
    try std.testing.expect(!isHermesInformationalEvent("on_session_start"));
}
