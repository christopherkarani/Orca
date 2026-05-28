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

pub fn command(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len > 0 and (std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h"))) {
        _ = try help.writeCommand(stdout, "decide");
        return exit_codes.success;
    }
    if (argv.len == 0) {
        _ = try help.writeCommand(stdout, "decide");
        return exit_codes.usage;
    }

    const kind = DecisionKind.parse(argv[0]) orelse {
        try stderr.print("orca decide: unknown decision kind '{s}'. Expected command, file, prompt, or tool.\n", .{argv[0]});
        return exit_codes.usage;
    };

    return decideCommand(kind, argv[1..], stdout, stderr);
}

// ---------------------------------------------------------------------------
// Decision kind
// ---------------------------------------------------------------------------

const DecisionKind = enum {
    command,
    file,
    prompt,
    tool,

    pub fn parse(value: []const u8) ?DecisionKind {
        if (std.mem.eql(u8, value, "command")) return .command;
        if (std.mem.eql(u8, value, "file")) return .file;
        if (std.mem.eql(u8, value, "prompt")) return .prompt;
        if (std.mem.eql(u8, value, "tool")) return .tool;
        return null;
    }
};

// ---------------------------------------------------------------------------
// CLI decision command
// ---------------------------------------------------------------------------

fn decideCommand(kind: DecisionKind, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var json_payload: ?[]const u8 = null;
    var use_stdin = false;
    var ci_mode = false;

    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        const arg = argv[index];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try stdout.writeAll(
                \\Usage:
                \\  orca decide command --json '{"command":"<cmd>"}'
                \\  orca decide file    --json '{"path":"<p>","operation":"read|write"}'
                \\  orca decide prompt  --json '{"text":"<text>"}'
                \\  orca decide tool    --json '{"name":"<name>"}'
                \\  orca decide <kind> --stdin
                \\  orca decide <kind> --json <payload> [--ci]
                \\  orca decide <kind> --stdin [--ci]
                \\
                \\Options:
                \\  --json   Provide JSON payload inline.
                \\  --stdin  Read JSON payload from stdin.
                \\  --ci     CI mode: ask decisions become block.
                \\
            );
            return exit_codes.success;
        }
        if (std.mem.eql(u8, arg, "--json")) {
            if (index + 1 >= argv.len) {
                try stderr.writeAll("orca decide: --json requires a value.\n");
                return exit_codes.usage;
            }
            json_payload = argv[index + 1];
            index += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--stdin")) {
            use_stdin = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--ci")) {
            ci_mode = true;
            continue;
        }
        try stderr.print("orca decide: unknown option '{s}'.\n", .{arg});
        return exit_codes.usage;
    }

    if (json_payload == null and !use_stdin) {
        try stderr.writeAll("orca decide: expected --json <payload> or --stdin.\n");
        return exit_codes.usage;
    }
    if (!use_stdin) {
        if (json_payload.?.len > max_payload_len) {
            try stderr.writeAll("orca decide: JSON payload exceeds maximum size.\n");
            return exit_codes.general;
        }
    }

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    // Read payload
    const payload_text = if (use_stdin)
        readBoundedStdin(allocator, max_payload_len) catch |err| {
            if (err == error.PayloadTooLarge) {
                try stderr.writeAll("orca decide: JSON payload exceeds maximum size.\n");
                return exit_codes.general;
            }
            return err;
        }
    else
        try allocator.dupe(u8, json_payload.?);
    defer allocator.free(payload_text);

    // Parse JSON payload
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, payload_text, .{}) catch |err| {
        try stderr.print("orca decide: invalid JSON ({s}).\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer parsed.deinit();

    // Load policy
    const root = supervisor.resolveWorkspaceRoot(allocator, null, ".") catch try allocator.dupe(u8, ".");
    defer allocator.free(root);
    var loaded = core_api.discoverPolicy(allocator, null, root) catch |err| {
        try stderr.print("orca decide: failed to load policy: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer loaded.deinit();

    // Evaluate decision
    var result = evaluateDecision(allocator, loaded.innerPtr(), kind, parsed.value, ci_mode) catch |err| {
        try stderr.print("orca decide: evaluation failed: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer result.deinit(allocator);

    // Emit JSON response to stdout
    try writeDecisionJson(stdout, result);

    // Log debug info to stderr only
    if (result.rule) |rule| {
        try stderr.print("[decide] matched rule: {s}\n", .{rule});
    }

    return result.decision.exitCode();
}

// ---------------------------------------------------------------------------
// Decision evaluation
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

    pub fn exitCode(self: PluginDecision) u8 {
        return switch (self) {
            .allow, .context_only => exit_codes.success,
            .block => exit_codes.denial,
            .ask => exit_codes.ask,
            .warn => exit_codes.warn,
            .err => exit_codes.general,
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

const DecisionOutput = struct {
    version: u8 = 1,
    decision: PluginDecision,
    risk: RiskLevel,
    category: []const u8,
    reason: []const u8,
    rule: ?[]const u8,
    message: []const u8,
    redactions: []RedactionEntry,

    fn deinit(self: *DecisionOutput, allocator: std.mem.Allocator) void {
        allocator.free(self.reason);
        allocator.free(self.message);
        allocator.free(self.category);
        if (self.rule) |r| allocator.free(r);
        for (self.redactions) |r| {
            allocator.free(r.field);
            allocator.free(r.reason);
        }
        allocator.free(self.redactions);
        self.* = undefined;
    }
};

const RedactionEntry = struct {
    field: []const u8,
    reason: []const u8,
};

fn evaluateDecision(
    allocator: std.mem.Allocator,
    policy_value: *const policy.schema.Policy,
    kind: DecisionKind,
    payload: std.json.Value,
    ci_mode: bool,
) !DecisionOutput {
    var redactions: std.ArrayList(RedactionEntry) = .empty;

    switch (kind) {
        .command => {
            const command_text = extractString(payload, "command") orelse extractString(payload, "name") orelse return error.MissingRequiredField;
            const evaluation = try core_api.explainAction(allocator, @ptrCast(policy_value), .command, command_text);
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
            };
        },
        .file => {
            const path = extractString(payload, "path") orelse return error.MissingRequiredField;
            const operation = extractString(payload, "operation") orelse "read";
            if (!std.mem.eql(u8, operation, "read") and !std.mem.eql(u8, operation, "write")) {
                return error.InvalidFileOperation;
            }

            const explain_kind: policy.explain.ExplainKind = if (std.mem.eql(u8, operation, "write")) .file_write else .file_read;
            const category_text = if (std.mem.eql(u8, operation, "write")) "file.write" else "file.read";

            const evaluation = try core_api.explainAction(allocator, @ptrCast(policy_value), explain_kind, path);
            defer evaluation.deinit(allocator);

            const decision = PluginDecision.fromDecisionResult(evaluation.decision.result, ci_mode);
            const risk = RiskLevel.fromScore(evaluation.decision.risk_score);

            return .{
                .decision = decision,
                .risk = risk,
                .category = try allocator.dupe(u8, category_text),
                .reason = try allocator.dupe(u8, evaluation.decision.reason),
                .rule = if (evaluation.matched_rule) |rule| try allocator.dupe(u8, rule.id) else null,
                .message = try buildMessage(allocator, decision, category_text),
                .redactions = try redactions.toOwnedSlice(allocator),
            };
        },
        .prompt => {
            const text = extractString(payload, "text") orelse
                extractString(payload, "prompt") orelse
                extractString(payload, "user_message") orelse
                "";

            // Redact prompt text to check for secrets
            var redact_buf: [4096]u8 = undefined;
            const redacted = core_api.redactStringBounded(text, &redact_buf);
            const had_secrets = redacted.len != text.len or !std.mem.eql(u8, redacted, text);

            if (had_secrets) {
                try redactions.append(allocator, .{
                    .field = try allocator.dupe(u8, "text"),
                    .reason = try allocator.dupe(u8, "potential secret detected"),
                });
            }

            // Prompt decisions use policy env evaluation as a proxy for sensitivity
            const evaluation = try core_api.explainAction(allocator, @ptrCast(policy_value), .env, "USER_PROMPT");
            defer evaluation.deinit(allocator);

            // Override decision if secrets detected
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
            };
        },
        .tool => {
            const tool_name = extractString(payload, "name") orelse
                extractString(payload, "tool") orelse
                extractNestedString(payload, &.{ "tool", "name" }) orelse
                return error.MissingRequiredField;
            const evaluation = try core_api.explainAction(allocator, @ptrCast(policy_value), .mcp, tool_name);
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
            };
        },
    }
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

fn writeDecisionJson(stdout: anytype, result: DecisionOutput) !void {
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
    try stdout.writeAll("  ]\n");
    try stdout.writeAll("}\n");
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn readBoundedStdin(allocator: std.mem.Allocator, max_len: usize) ![]u8 {
    const stdin_file = std.fs.File.stdin();
    return readBoundedReader(allocator, max_len, stdin_file);
}

fn readBoundedReader(allocator: std.mem.Allocator, max_len: usize, reader: anytype) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);

    var chunk: [4096]u8 = undefined;
    while (true) {
        const n = try reader.read(&chunk);
        if (n == 0) break;
        if (buf.items.len + n > max_len) return error.PayloadTooLarge;
        try buf.appendSlice(allocator, chunk[0..n]);
    }

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

test "PluginDecision exitCode mapping" {
    const cases = [_]struct { PluginDecision, u8 }{
        .{ .allow, exit_codes.success },
        .{ .context_only, exit_codes.success },
        .{ .block, exit_codes.denial },
        .{ .ask, exit_codes.ask },
        .{ .warn, exit_codes.warn },
        .{ .err, exit_codes.general },
    };
    for (cases) |entry| {
        try std.testing.expectEqual(entry[1], entry[0].exitCode());
    }
}

test "decide command help and invalid kind" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const help_code = try command(&.{"--help"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, help_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "decide") != null);

    stdout_stream.reset();
    stderr_stream.reset();
    const bad_code = try command(&.{"unknown"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, bad_code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "unknown decision kind") != null);
}

test "decide command with safe command returns allow" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try decideCommand(.command, &.{
        "--json", "{\"command\":\"echo hello\"}",
    }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "\"decision\": \"allow\"") != null);
}

test "decide command with dangerous command returns block" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try decideCommand(.command, &.{
        "--json", "{\"command\":\"rm -rf /\"}",
    }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.denial, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "\"decision\": \"block\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"category\": \"command\"") != null);
}

test "decide file write to protected path returns block" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try decideCommand(.file, &.{
        "--json", "{\"path\":\"/etc/passwd\",\"operation\":\"write\"}",
    }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.denial, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "\"decision\": \"block\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"category\": \"file.write\"") != null);
}

test "decide file rejects unknown operation instead of downgrading to read" {
    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try decideCommand(.file, &.{
        "--json", "{\"path\":\"./src/main.zig\",\"operation\":\"delete\"}",
    }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expect(code != exit_codes.success);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "InvalidFileOperation") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "\"category\": \"file.read\"") == null);
}

test "decide rejects missing required command and file fields" {
    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const missing_command = try decideCommand(.command, &.{
        "--json", "{}",
    }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expect(missing_command != exit_codes.success);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "MissingRequiredField") != null);
    try std.testing.expectEqualStrings("", stdout_stream.getWritten());

    stdout_stream.reset();
    stderr_stream.reset();
    const missing_file_path = try decideCommand(.file, &.{
        "--json", "{\"operation\":\"read\"}",
    }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expect(missing_file_path != exit_codes.success);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "MissingRequiredField") != null);
    try std.testing.expectEqualStrings("", stdout_stream.getWritten());

    stdout_stream.reset();
    stderr_stream.reset();
    const missing_tool_name = try decideCommand(.tool, &.{
        "--json", "{}",
    }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expect(missing_tool_name != exit_codes.success);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "MissingRequiredField") != null);
    try std.testing.expectEqualStrings("", stdout_stream.getWritten());
}

test "decide prompt with fake secret returns warn" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try decideCommand(.prompt, &.{
        "--json", "{\"text\":\"my token is ghp_fake_secret_value\"}",
    }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.warn, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "\"decision\": \"warn\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"category\": \"prompt\"") != null);
    // Ensure redaction is noted
    try std.testing.expect(std.mem.indexOf(u8, output, "redactions") != null);
}

test "decide prompt accepts host prompt field and redacts fake secret" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try decideCommand(.prompt, &.{
        "--json", "{\"prompt\":\"fake_p05_secret_value\"}",
    }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.warn, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "\"decision\": \"warn\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"category\": \"prompt\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "fake_p05_secret_value") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "redactions") != null);
}

test "decide tool returns valid JSON" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try decideCommand(.tool, &.{
        "--json", "{\"name\":\"read_file\"}",
    }, stdout_stream.writer(), stderr_stream.writer());
    const output = stdout_stream.getWritten();
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, output, .{});
    defer parsed.deinit();

    const decision = parsed.value.object.get("decision").?.string;
    if (std.mem.eql(u8, decision, "allow")) {
        try std.testing.expectEqual(exit_codes.success, code);
    } else if (std.mem.eql(u8, decision, "ask")) {
        try std.testing.expectEqual(exit_codes.ask, code);
    } else {
        try std.testing.expect(false);
    }

    try std.testing.expect(parsed.value.object.get("decision") != null);
    try std.testing.expect(parsed.value.object.get("risk") != null);
    try std.testing.expect(parsed.value.object.get("category") != null);
    try std.testing.expect(parsed.value.object.get("reason") != null);
    try std.testing.expect(parsed.value.object.get("message") != null);
}

test "decide non-ci mode returns ask exit code for unknown command" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try decideCommand(.command, &.{
        "--json", "{\"command\":\"unknown-tool --help\"}",
    }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.ask, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "\"decision\": \"ask\"") != null);
}

test "decide ci mode turns ask into block" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    // Use a command that typically asks; in CI it should block
    const code = try decideCommand(.command, &.{
        "--json", "{\"command\":\"unknown-tool --help\"}",
        "--ci",
    }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.denial, code);

    const output = stdout_stream.getWritten();
    // In CI mode, ask should become block
    // Note: the exact decision depends on policy; we just verify JSON validity
    try std.testing.expect(std.mem.indexOf(u8, output, "\"decision\"") != null);
}

test "decide rejects invalid JSON" {
    var stdout_buf: [256]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try decideCommand(.command, &.{
        "--json", "{not json",
    }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expect(code != exit_codes.success);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "invalid JSON") != null);
}

test "decide bounded reader rejects oversized payload instead of truncating" {
    var payload = try std.testing.allocator.alloc(u8, max_payload_len + 1);
    defer std.testing.allocator.free(payload);
    @memset(payload[0..max_payload_len], ' ');
    payload[0] = '{';
    payload[1] = '}';
    payload[max_payload_len] = 'x';

    var stream = std.io.fixedBufferStream(payload);
    try std.testing.expectError(error.PayloadTooLarge, readBoundedReader(std.testing.allocator, max_payload_len, stream.reader()));
}

test "decide rejects inline json payloads over limit" {
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(std.testing.allocator);
    try payload.appendSlice(std.testing.allocator, "{\"text\":\"");
    try payload.appendNTimes(std.testing.allocator, 'x', max_payload_len);
    try payload.appendSlice(std.testing.allocator, "\"}");

    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [2048]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try decideCommand(.prompt, &.{ "--json", payload.items }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.general, code);
    try std.testing.expectEqualStrings("", stdout_stream.getWritten());
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "JSON payload exceeds maximum size") != null);
}
