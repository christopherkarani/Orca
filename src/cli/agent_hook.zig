//! Stdin agent-hook mode for bare `orca` invocations (no subcommand).
//!
//! Rust `orca` falls through to hook evaluation when argv has no subcommand and stdin
//! carries agent hook JSON (`tool_name` / `tool_input`). Zig must match that contract so
//! Cursor's `beforeShellExecution` wrapper and direct `orca` hook entries receive valid JSON.
//!
//! Invariants:
//! - Interactive TTY with no args still shows help (not hook mode).
//! - Shell commands route through the Rust daemon evaluator (fail-closed when unavailable).
//! - Invalid / non-shell hook input fails open (exit 0, allow) matching Rust hook mode.

const std = @import("std");
const build_options = @import("build_options");

const exit_codes = @import("exit_codes.zig");
const shell_eval = @import("shell_eval.zig");
const core_api = @import("orca_core").api;
const policy = @import("orca_core").policy;

const max_payload_len = 256 * 1024;

pub const InputFormat = enum {
    agent_hook,
    cursor_shell,
};

pub const ShellCommandEvaluatorFn = shell_eval.ShellCommandEvaluatorFn;

/// True when `orca` was invoked with no subcommand and stdin is piped (non-TTY).
pub fn shouldEnter(io: std.Io) bool {
    const stdin_tty = std.Io.File.stdin().isTty(io) catch true;
    return !stdin_tty;
}

pub const NotAgentHookInput = error.NotAgentHookInput;

pub fn command(io: std.Io, stdout: anytype, stderr: anytype) !u8 {
    return commandWithEvaluator(io, stdout, stderr, null);
}

pub fn commandWithEvaluator(
    io: std.Io,
    stdout: anytype,
    stderr: anytype,
    evaluator: ?ShellCommandEvaluatorFn,
) !u8 {
    _ = stderr;

    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const payload = readBoundedStdin(io, allocator, max_payload_len) catch {
        return exit_codes.success;
    };
    defer allocator.free(payload);

    if (std.mem.trim(u8, payload, " \t\r\n").len == 0) {
        return error.NotAgentHookInput;
    }

    return evaluatePayload(allocator, payload, stdout, evaluator);
}

pub fn evaluatePayload(
    allocator: std.mem.Allocator,
    payload: []const u8,
    stdout: anytype,
    evaluator: ?ShellCommandEvaluatorFn,
) !u8 {
    if (std.mem.trim(u8, payload, " \t\r\n").len == 0) {
        return exit_codes.success;
    }

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, payload, .{}) catch {
        return exit_codes.success;
    };
    defer parsed.deinit();

    const format = detectInputFormat(parsed.value) orelse return exit_codes.success;
    const command_text = extractCommand(parsed.value, format) orelse return exit_codes.success;
    if (std.mem.trim(u8, command_text, " \t\r\n").len == 0) {
        return exit_codes.success;
    }

    const cwd = extractCwd(parsed.value, format);
    const owned_command = try allocator.dupe(u8, command_text);
    defer allocator.free(owned_command);

    const shell_event = shell_eval.ShellCommandEvent{
        .command = owned_command,
        .cwd = cwd,
    };

    const daemon_response = shell_eval.evaluateParsed(allocator, shell_event, evaluator) catch |err| {
        const unavailable = try shell_eval.failClosedDaemonUnavailableDecision(allocator, err);
        defer unavailable.deinit(allocator);
        try writeDeny(stdout, format, unavailable.owned_reason);
        return exit_codes.success;
    };
    defer daemon_response.deinit();

    // Bare agent-hook path has no loaded policy; honor ORCA_MODE when set, else strict.
    const mode = blk: {
        if (std.c.getenv("ORCA_MODE")) |raw_c| {
            const raw = std.mem.span(raw_c);
            if (policy.schema.Mode.parse(raw)) |mode_value| break :blk mode_value;
        }
        break :blk policy.schema.Mode.strict;
    };
    const decision = try shell_eval.decisionFromDaemonResult(allocator, daemon_response.value.result, mode);
    defer decision.deinit(allocator);

    switch (decision.decision.result) {
        .deny, .redact, .stage, .broker => {
            // Keep host JSON contracts valid; enrich the human-readable reason
            // string with a short tip when present (no new required fields).
            // Re-redact the final presentation string so tips cannot leak secrets
            // even if a future path skips remediation sanitization.
            const combined = if (decision.owned_remediation) |tip| blk: {
                break :blk try std.fmt.allocPrint(allocator, "{s}. Tip: {s}", .{ decision.owned_reason, tip });
            } else try allocator.dupe(u8, decision.owned_reason);
            defer allocator.free(combined);
            const reason = try core_api.redactAlloc(allocator, combined);
            defer allocator.free(reason);
            try writeDeny(stdout, format, reason);
        },
        .allow, .observe, .ask => try writeAllow(stdout, format),
    }

    return exit_codes.success;
}

pub fn detectInputFormat(root: std.json.Value) ?InputFormat {
    if (root != .object) return null;
    const object = root.object;
    if (object.get("tool_name") != null or object.get("toolName") != null) return .agent_hook;
    if (object.get("command") != null) return .cursor_shell;
    return null;
}

pub fn extractCommand(root: std.json.Value, format: InputFormat) ?[]const u8 {
    if (root != .object) return null;
    const object = root.object;

    return switch (format) {
        .cursor_shell => stringField(object, "command"),
        .agent_hook => blk: {
            if (!isShellHookCandidate(object)) return null;
            if (object.get("tool_input")) |tool_input| {
                if (extractCommandFromToolInput(tool_input)) |cmd| break :blk cmd;
            }
            if (object.get("toolInput")) |tool_input| {
                if (extractCommandFromToolInput(tool_input)) |cmd| break :blk cmd;
            }
            if (object.get("tool_args")) |tool_args| {
                if (extractCommandFromToolArgs(tool_args)) |cmd| break :blk cmd;
            }
            if (object.get("toolArgs")) |tool_args| {
                if (extractCommandFromToolArgs(tool_args)) |cmd| break :blk cmd;
            }
            return null;
        },
    };
}

pub fn extractCwd(root: std.json.Value, format: InputFormat) ?[]const u8 {
    _ = format;
    if (root != .object) return null;
    return stringField(root.object, "cwd");
}

fn isShellHookCandidate(object: std.json.ObjectMap) bool {
    const tool_name = stringField(object, "tool_name") orelse stringField(object, "toolName");
    if (tool_name) |name| return isSupportedShellTool(name);
    return object.get("tool_input") != null or object.get("toolInput") != null or
        object.get("tool_args") != null or object.get("toolArgs") != null;
}

fn isSupportedShellTool(tool_name: []const u8) bool {
    var lower_buf: [64]u8 = undefined;
    if (tool_name.len > lower_buf.len) return false;
    for (tool_name, 0..) |c, i| {
        lower_buf[i] = std.ascii.toLower(c);
    }
    const lower = lower_buf[0..tool_name.len];
    return std.mem.eql(u8, lower, "bash") or
        std.mem.eql(u8, lower, "launch-process") or
        std.mem.eql(u8, lower, "powershell") or
        std.mem.eql(u8, lower, "pwsh") or
        std.mem.eql(u8, lower, "run_shell_command") or
        std.mem.eql(u8, lower, "run-shell-command") or
        std.mem.eql(u8, lower, "terminal") or
        std.mem.eql(u8, lower, "run_terminal_cmd");
}

fn extractCommandFromToolInput(value: std.json.Value) ?[]const u8 {
    if (value != .object) return null;
    return nonEmptyStringField(value.object, "command");
}

fn extractCommandFromToolArgs(value: std.json.Value) ?[]const u8 {
    return switch (value) {
        .object => |object| nonEmptyStringField(object, "command"),
        .string => |text| if (text.len == 0) null else text,
        else => null,
    };
}

fn writeAllow(stdout: anytype, format: InputFormat) !void {
    switch (format) {
        .agent_hook => {},
        .cursor_shell => try stdout.writeAll(
            \\{"permission":"allow","continue":true,"userMessage":"","agentMessage":"","user_message":"","agent_message":""}
        ),
    }
}

fn writeDeny(stdout: anytype, format: InputFormat, reason: []const u8) !void {
    switch (format) {
        .agent_hook => try writeAgentDenial(stdout, reason),
        .cursor_shell => try writeCursorDenial(stdout, reason),
    }
}

fn writeAgentDenial(stdout: anytype, reason: []const u8) !void {
    try stdout.writeAll("{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":");
    try writeJsonString(stdout, reason);
    try stdout.writeAll("}}\n");
}

fn writeCursorDenial(stdout: anytype, reason: []const u8) !void {
    try stdout.writeAll("{\"permission\":\"deny\",\"continue\":false,\"userMessage\":");
    try writeJsonString(stdout, reason);
    try stdout.writeAll(",\"agentMessage\":");
    try writeJsonString(stdout, reason);
    try stdout.writeAll(",\"user_message\":");
    try writeJsonString(stdout, reason);
    try stdout.writeAll(",\"agent_message\":");
    try writeJsonString(stdout, reason);
    try stdout.writeAll("}\n");
}

fn stringField(object: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = object.get(key) orelse return null;
    return switch (value) {
        .string => |text| text,
        else => null,
    };
}

fn nonEmptyStringField(object: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = stringField(object, key) orelse return null;
    if (std.mem.trim(u8, value, " \t\r\n").len == 0) return null;
    return value;
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
            else => {
                if (byte < 0x20) {
                    try writer.print("\\u{:0>4}", .{byte});
                } else {
                    try writer.writeByte(byte);
                }
            },
        }
    }
    try writer.writeByte('"');
}

fn readBoundedStdin(io: std.Io, allocator: std.mem.Allocator, max_len: usize) ![]u8 {
    const stdin = std.Io.File.stdin();
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);

    var chunk: [4096]u8 = undefined;
    while (true) {
        const n = stdin.readStreaming(io, &.{chunk[0..]}) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        if (n == 0) break;
        if (buf.items.len + n > max_len) return error.PayloadTooLarge;
        try buf.appendSlice(allocator, chunk[0..n]);
    }

    return try buf.toOwnedSlice(allocator);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "detectInputFormat distinguishes agent hook and cursor shell payloads" {
    var agent = std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git status\"}}", .{}) catch unreachable;
    defer agent.deinit();
    try std.testing.expectEqual(InputFormat.agent_hook, detectInputFormat(agent.value).?);

    var cursor = std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"command\":\"git status\",\"cwd\":\"/tmp\"}", .{}) catch unreachable;
    defer cursor.deinit();
    try std.testing.expectEqual(InputFormat.cursor_shell, detectInputFormat(cursor.value).?);

    var unknown = std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"version\":1}", .{}) catch unreachable;
    defer unknown.deinit();
    try std.testing.expect(detectInputFormat(unknown.value) == null);
}

test "extractCommand reads Bash tool_input and cursor command fields" {
    var agent = std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git status\"}}", .{}) catch unreachable;
    defer agent.deinit();
    try std.testing.expectEqualStrings("git status", extractCommand(agent.value, .agent_hook).?);

    var cursor = std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"command\":\"pwd\",\"cwd\":\"/tmp\"}", .{}) catch unreachable;
    defer cursor.deinit();
    try std.testing.expectEqualStrings("pwd", extractCommand(cursor.value, .cursor_shell).?);
}

test "evaluatePayload allow emits cursor JSON and empty agent stdout" {
    const allocator = std.testing.allocator;

    var cursor_buf: [512]u8 = undefined;
    var cursor_stdout: std.Io.Writer = .fixed(&cursor_buf);
    const cursor_payload = "{\"command\":\"git status\",\"cwd\":\"/tmp\"}";
    const cursor_code = try evaluatePayload(allocator, cursor_payload, &cursor_stdout, shell_eval.mockDaemonAllowEvaluator);
    try std.testing.expectEqual(exit_codes.success, cursor_code);
    const cursor_output = cursor_stdout.buffered();
    try std.testing.expect(std.mem.indexOf(u8, cursor_output, "\"permission\":\"allow\"") != null);

    var agent_buf: [512]u8 = undefined;
    var agent_stdout: std.Io.Writer = .fixed(&agent_buf);
    const agent_payload = "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git status\"}}";
    const agent_code = try evaluatePayload(allocator, agent_payload, &agent_stdout, shell_eval.mockDaemonAllowEvaluator);
    try std.testing.expectEqual(exit_codes.success, agent_code);
    try std.testing.expectEqual(@as(usize, 0), agent_stdout.buffered().len);
}

test "evaluatePayload deny emits hookSpecificOutput and cursor deny JSON" {
    const allocator = std.testing.allocator;

    var agent_buf: [2048]u8 = undefined;
    var agent_stdout: std.Io.Writer = .fixed(&agent_buf);
    const agent_payload = "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -rf /\"}}";
    _ = try evaluatePayload(allocator, agent_payload, &agent_stdout, shell_eval.mockDaemonDenyEvaluator);
    const agent_output = agent_stdout.buffered();
    try std.testing.expect(std.mem.indexOf(u8, agent_output, "\"permissionDecision\":\"deny\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, agent_output, "\"hookEventName\":\"PreToolUse\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, agent_output, "core.filesystem:destructive_rm") != null);
    try std.testing.expect(std.mem.indexOf(u8, agent_output, "Tip:") != null);

    var cursor_buf: [2048]u8 = undefined;
    var cursor_stdout: std.Io.Writer = .fixed(&cursor_buf);
    const cursor_payload = "{\"command\":\"rm -rf /\",\"cwd\":\"/tmp\"}";
    _ = try evaluatePayload(allocator, cursor_payload, &cursor_stdout, shell_eval.mockDaemonDenyEvaluator);
    const cursor_output = cursor_stdout.buffered();
    try std.testing.expect(std.mem.indexOf(u8, cursor_output, "\"permission\":\"deny\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, cursor_output, "core.filesystem:destructive_rm") != null);
}

test "evaluatePayload fails closed when daemon unavailable" {
    const allocator = std.testing.allocator;
    var stdout_buf: [1024]u8 = undefined;
    var stdout: std.Io.Writer = .fixed(&stdout_buf);

    const payload = "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git status\"}}";
    _ = try evaluatePayload(allocator, payload, &stdout, shell_eval.mockDaemonUnavailableEvaluator);
    try std.testing.expect(std.mem.indexOf(u8, stdout.buffered(), "\"permissionDecision\":\"deny\"") != null);
}

test "evaluatePayload invalid JSON fails open with no stdout" {
    const allocator = std.testing.allocator;
    var stdout_buf: [256]u8 = undefined;
    var stdout: std.Io.Writer = .fixed(&stdout_buf);

    const code = try evaluatePayload(allocator, "not-json", &stdout, shell_eval.mockDaemonDenyEvaluator);
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expectEqual(@as(usize, 0), stdout.buffered().len);
}

test "agent hook mode version is wired into build metadata" {
    try std.testing.expect(build_options.version.len > 0);
}
