const std = @import("std");
const build_options = @import("build_options");

const core = @import("orca_core").core;
const daemon = @import("daemon.zig");
const shell_eval = @import("shell_eval.zig");
const exit_codes = @import("exit_codes.zig");
const feed_writer = @import("feed_writer.zig");
const help = @import("help.zig");
const rust_visibility = @import("rust_visibility.zig");

const max_payload_len = 256 * 1024;
const api_schema_version: i64 = 1;
const daemon_protocol_version: i64 = 1;
const event_source_evaluate = "evaluate";

pub const exit_allowed: u8 = 0;
pub const exit_denied: u8 = 2;
pub const exit_evaluator_error: u8 = 3;
pub const exit_invalid_input: u8 = 64;
pub const exit_internal_error: u8 = 1;

pub const EvaluateRequest = struct {
    schema_version: i64,
    request_id: ?[]const u8 = null,
    session_id: ?[]const u8 = null,
    host: ?[]const u8 = null,
    command: []const u8,
    cwd: []const u8,

    fn deinit(self: EvaluateRequest, allocator: std.mem.Allocator) void {
        if (self.request_id) |id| allocator.free(id);
        if (self.session_id) |id| allocator.free(id);
        if (self.host) |host| allocator.free(host);
        allocator.free(self.command);
        allocator.free(self.cwd);
    }
};

pub const EvaluatorFn = *const fn (
    std.mem.Allocator,
    []const u8,
    ?[]const u8,
) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse);

const FeedDestination = union(enum) {
    disabled,
    process_home,
    explicit: []const u8,
};

const ErrorCode = enum {
    invalid_input,
    daemon_unavailable,
    daemon_incompatible,
    daemon_timeout,
    protocol_error,
    internal_error,

    fn toString(self: ErrorCode) []const u8 {
        return @tagName(self);
    }
};

const DaemonStatus = enum {
    healthy,
    unavailable,
    incompatible,
    timeout,
    unknown,

    fn toString(self: DaemonStatus) []const u8 {
        return @tagName(self);
    }
};

const ErrorInfo = struct {
    code: ErrorCode,
    message: []const u8,
};

const Remediation = struct {
    description: []const u8,
};

const MachineResponse = struct {
    schema_version: i64 = api_schema_version,
    request_id: ?[]const u8 = null,
    orca_version: []const u8 = build_options.version,
    daemon_protocol_version: ?i64 = daemon_protocol_version,
    decision: []const u8,
    reason: []const u8,
    severity: ?[]const u8 = null,
    pack_id: ?[]const u8 = null,
    pattern_name: ?[]const u8 = null,
    rule_id: ?[]const u8 = null,
    remediation: []const Remediation = &.{},
    daemon_status: DaemonStatus,
    daemon_compatible: bool,
    error_info: ?ErrorInfo = null,
};

pub fn command(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    return commandWithEvaluator(io, argv, stdout, stderr, shellEvalBridge);
}

fn shellEvalBridge(
    allocator: std.mem.Allocator,
    command_text: []const u8,
    cwd: ?[]const u8,
) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    return shell_eval.defaultEvaluator(allocator, .{ .command = command_text, .cwd = cwd });
}

fn commandWithEvaluator(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype, evaluator: EvaluatorFn) !u8 {
    if (argv.len > 0 and (std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h"))) {
        _ = try help.writeCommand(io, stdout, "evaluate");
        return exit_codes.success;
    }

    var saw_json = false;
    var saw_stdin = false;
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--json")) {
            saw_json = true;
        } else if (std.mem.eql(u8, arg, "--stdin")) {
            saw_stdin = true;
        } else {
            if (saw_json) {
                try writeInvalidInput(stdout, null, "unsupported option for evaluate");
            }
            try stderr.print("orca evaluate: unsupported option '{s}'. Expected --json --stdin.\n", .{arg});
            return if (saw_json) exit_invalid_input else exit_codes.usage;
        }
    }

    if (!saw_json or !saw_stdin) {
        if (saw_json) {
            try writeInvalidInput(stdout, null, "expected --json --stdin");
            return exit_invalid_input;
        }
        try stderr.writeAll("orca evaluate: expected --json --stdin. Run 'orca help evaluate' for usage.\n");
        return exit_codes.usage;
    }

    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const payload = readBoundedStdin(io, allocator, max_payload_len) catch |err| {
        const message = if (err == error.PayloadTooLarge) "JSON payload exceeds maximum size" else "failed to read stdin payload";
        try writeInvalidInput(stdout, null, message);
        return exit_invalid_input;
    };
    defer allocator.free(payload);

    return evaluatePayload(io, allocator, payload, stdout, evaluator, .process_home);
}

fn evaluatePayload(
    io: std.Io,
    allocator: std.mem.Allocator,
    payload: []const u8,
    stdout: anytype,
    evaluator: EvaluatorFn,
    feed_destination: FeedDestination,
) !u8 {
    const request = parseRequest(io, allocator, payload) catch |err| {
        const request_id = requestIdBestEffort(allocator, payload) catch null;
        defer if (request_id) |id| allocator.free(id);
        switch (err) {
            error.OutOfMemory => {
                try writeInternalError(stdout, request_id, "internal allocation failure during request parsing");
                return exit_internal_error;
            },
            else => |parse_err| {
                try writeInvalidInput(stdout, request_id, validationMessage(parse_err));
                return exit_invalid_input;
            },
        }
    };
    defer request.deinit(allocator);

    var parsed = evaluator(allocator, request.command, request.cwd) catch |err| {
        recordUnavailableEvaluationBestEffort(io, allocator, request, err, feed_destination);
        try writeDaemonError(stdout, request.request_id, err);
        return exit_evaluator_error;
    };
    defer parsed.deinit();

    recordEvaluationBestEffort(io, allocator, request, parsed.value.result, feed_destination);

    return writeEvaluationResponse(allocator, stdout, request, parsed.value.result) catch |err| switch (err) {
        error.DaemonProtocolError => {
            try writeProtocolError(stdout, request.request_id, "daemon returned an unexpected evaluation response");
            return exit_evaluator_error;
        },
        error.OutOfMemory => {
            try writeInternalError(stdout, request.request_id, "internal allocation failure during evaluation response");
            return exit_internal_error;
        },
        else => {
            try writeInternalError(stdout, request.request_id, "failed to write evaluation response");
            return exit_internal_error;
        },
    };
}

fn recordEvaluationBestEffort(
    io: std.Io,
    allocator: std.mem.Allocator,
    request: EvaluateRequest,
    result: std.json.Value,
    destination: FeedDestination,
) void {
    if (destination == .disabled) return;
    const workspace_root = core.supervisor.resolveWorkspaceRoot(io, allocator, null, request.cwd) catch
        allocator.dupe(u8, request.cwd) catch return;
    defer allocator.free(workspace_root);
    var record = rust_visibility.buildFeedRecordFromDaemon(
        allocator,
        io,
        workspace_root,
        event_source_evaluate,
        request.host,
        "healthy",
        result,
        request.session_id orelse request.request_id,
        false,
    ) catch return;
    defer record.deinit(allocator);
    persistEvaluationRecordBestEffort(io, allocator, record, destination);
}

fn recordUnavailableEvaluationBestEffort(
    io: std.Io,
    allocator: std.mem.Allocator,
    request: EvaluateRequest,
    err: daemon.DaemonError,
    destination: FeedDestination,
) void {
    if (destination == .disabled) return;
    const workspace_root = core.supervisor.resolveWorkspaceRoot(io, allocator, null, request.cwd) catch
        allocator.dupe(u8, request.cwd) catch return;
    defer allocator.free(workspace_root);
    var record = rust_visibility.buildFeedRecordFromUnavailable(
        allocator,
        io,
        workspace_root,
        event_source_evaluate,
        request.host,
        err,
        request.session_id orelse request.request_id,
        false,
    ) catch return;
    defer record.deinit(allocator);
    persistEvaluationRecordBestEffort(io, allocator, record, destination);
}

fn persistEvaluationRecordBestEffort(
    io: std.Io,
    allocator: std.mem.Allocator,
    record: rust_visibility.RustShellFeedRecord,
    destination: FeedDestination,
) void {
    feed_writer.appendRecord(io, allocator, record.workspace_root, record) catch {};
    const dashboard_root = switch (destination) {
        .disabled => return,
        .process_home => if (feed_writer.processGlobalWritesDisabled()) return else feed_writer.resolveGlobalDashboardRoot(allocator) catch return,
        .explicit => |root| allocator.dupe(u8, root) catch return,
    };
    defer allocator.free(dashboard_root);
    feed_writer.appendGlobalRecord(io, allocator, dashboard_root, record) catch {};
}

const RequestParseError = error{
    InvalidJson,
    RootNotObject,
    MissingSchemaVersion,
    UnsupportedSchemaVersion,
    MissingKind,
    UnsupportedKind,
    MissingCommand,
    EmptyCommand,
    MissingCwd,
    RelativeCwd,
    NonexistentCwd,
};

fn parseRequest(io: std.Io, allocator: std.mem.Allocator, payload: []const u8) (RequestParseError || error{OutOfMemory})!EvaluateRequest {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, payload, .{}) catch return error.InvalidJson;
    defer parsed.deinit();

    if (parsed.value != .object) return error.RootNotObject;
    const object = parsed.value.object;

    const schema_value = object.get("schema_version") orelse return error.MissingSchemaVersion;
    const schema_version = switch (schema_value) {
        .integer => |value| value,
        else => return error.MissingSchemaVersion,
    };
    if (schema_version != api_schema_version) return error.UnsupportedSchemaVersion;

    const kind = stringField(object, "kind") orelse return error.MissingKind;
    if (!std.mem.eql(u8, kind, "shell_command")) return error.UnsupportedKind;

    const command_value = object.get("command") orelse return error.MissingCommand;
    const command_text = switch (command_value) {
        .string => |value| value,
        else => return error.MissingCommand,
    };
    if (std.mem.trim(u8, command_text, " \t\r\n").len == 0) return error.EmptyCommand;

    const cwd_value = object.get("cwd") orelse return error.MissingCwd;
    const cwd_text = switch (cwd_value) {
        .string => |value| value,
        else => return error.MissingCwd,
    };
    if (!std.fs.path.isAbsolute(cwd_text)) return error.RelativeCwd;

    const canonical_cwd_z = std.Io.Dir.cwd().realPathFileAlloc(io, cwd_text, allocator) catch return error.NonexistentCwd;
    defer allocator.free(canonical_cwd_z);
    var cwd_dir = std.Io.Dir.openDirAbsolute(io, canonical_cwd_z, .{}) catch return error.NonexistentCwd;
    cwd_dir.close(io);
    const canonical_cwd = try allocator.dupe(u8, canonical_cwd_z);
    errdefer allocator.free(canonical_cwd);

    const owned_request_id = if (stringField(object, "request_id")) |id| try allocator.dupe(u8, id) else null;
    errdefer if (owned_request_id) |id| allocator.free(id);
    const owned_session_id = if (nestedStringField(object, "source", "session_id")) |id| try allocator.dupe(u8, id) else null;
    errdefer if (owned_session_id) |id| allocator.free(id);
    const owned_host = if (nestedStringField(object, "source", "host")) |host| try allocator.dupe(u8, host) else null;
    errdefer if (owned_host) |host| allocator.free(host);
    const owned_command = try allocator.dupe(u8, command_text);
    errdefer allocator.free(owned_command);

    return .{
        .schema_version = schema_version,
        .request_id = owned_request_id,
        .session_id = owned_session_id,
        .host = owned_host,
        .command = owned_command,
        .cwd = canonical_cwd,
    };
}

fn validationMessage(err: RequestParseError) []const u8 {
    return switch (err) {
        error.InvalidJson => "invalid JSON request",
        error.RootNotObject => "request must be a JSON object",
        error.MissingSchemaVersion => "schema_version is required and must be 1",
        error.UnsupportedSchemaVersion => "unsupported schema_version",
        error.MissingKind => "kind is required",
        error.UnsupportedKind => "kind must be shell_command",
        error.MissingCommand => "command is required and must be a string",
        error.EmptyCommand => "command must not be empty",
        error.MissingCwd => "cwd is required and must be an absolute existing directory",
        error.RelativeCwd => "cwd must be an absolute path",
        error.NonexistentCwd => "cwd does not exist or is not accessible",
    };
}

fn stringField(object: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = object.get(key) orelse return null;
    return switch (value) {
        .string => |s| s,
        else => null,
    };
}

fn nestedStringField(object: std.json.ObjectMap, parent: []const u8, key: []const u8) ?[]const u8 {
    const parent_value = object.get(parent) orelse return null;
    if (parent_value != .object) return null;
    return stringField(parent_value.object, key);
}

fn requestIdBestEffort(allocator: std.mem.Allocator, payload: []const u8) !?[]const u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, payload, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    if (stringField(parsed.value.object, "request_id")) |id| return try allocator.dupe(u8, id);
    return null;
}

fn writeEvaluationResponse(allocator: std.mem.Allocator, stdout: anytype, request: EvaluateRequest, result: std.json.Value) !u8 {
    return switch (daemon.responseStatus(result)) {
        .allow => {
            const reason = try safeReason(allocator, result);
            defer allocator.free(reason);
            const response = MachineResponse{
                .request_id = request.request_id,
                .decision = "allow",
                .reason = reason,
                .severity = normalizeSeverity(daemon.responseStringField(result, "severity")),
                .pack_id = daemon.responseStringField(result, "pack_id"),
                .pattern_name = daemon.responseStringField(result, "pattern_name"),
                .rule_id = null,
                .daemon_status = .healthy,
                .daemon_compatible = true,
            };
            try writeResponseJson(stdout, response);
            return exit_allowed;
        },
        .deny => {
            const reason = try safeReason(allocator, result);
            defer allocator.free(reason);
            const remediation_text = try rust_visibility.remediationFromDaemonResult(allocator, result);
            defer if (remediation_text) |text| allocator.free(text);
            const remediation_items = if (remediation_text) |text| &[_]Remediation{.{ .description = text }} else &[_]Remediation{};
            const rule = try buildRuleId(allocator, result);
            defer if (rule) |value| allocator.free(value);
            const response = MachineResponse{
                .request_id = request.request_id,
                .decision = "deny",
                .reason = reason,
                .severity = normalizeSeverity(daemon.responseStringField(result, "severity")),
                .pack_id = daemon.responseStringField(result, "pack_id"),
                .pattern_name = daemon.responseStringField(result, "pattern_name"),
                .rule_id = rule,
                .remediation = remediation_items,
                .daemon_status = .healthy,
                .daemon_compatible = true,
            };
            try writeResponseJson(stdout, response);
            return exit_denied;
        },
        .error_status => {
            try writeProtocolError(stdout, request.request_id, "daemon evaluator returned an error");
            return exit_evaluator_error;
        },
        .pong, .cli_execution, .unknown => return error.DaemonProtocolError,
    };
}

fn safeReason(allocator: std.mem.Allocator, result: std.json.Value) ![]const u8 {
    return rust_visibility.safeReasonFromDaemonResult(allocator, result);
}

fn normalizeSeverity(severity: ?[]const u8) ?[]const u8 {
    const value = severity orelse return null;
    if (std.ascii.eqlIgnoreCase(value, "critical")) return "critical";
    if (std.ascii.eqlIgnoreCase(value, "high")) return "high";
    if (std.ascii.eqlIgnoreCase(value, "medium")) return "medium";
    if (std.ascii.eqlIgnoreCase(value, "low")) return "low";
    return null;
}

fn buildRuleId(allocator: std.mem.Allocator, result: std.json.Value) !?[]const u8 {
    const pack_id = daemon.responseStringField(result, "pack_id");
    const pattern_name = daemon.responseStringField(result, "pattern_name");
    if (pack_id) |pack| {
        if (pattern_name) |pattern| return try std.fmt.allocPrint(allocator, "{s}:{s}", .{ pack, pattern });
        return try allocator.dupe(u8, pack);
    }
    if (pattern_name) |pattern| return try allocator.dupe(u8, pattern);
    return null;
}

fn writeInvalidInput(stdout: anytype, request_id: ?[]const u8, message: []const u8) !void {
    try writeErrorResponse(stdout, .{
        .request_id = request_id,
        .decision = "error",
        .reason = message,
        .daemon_protocol_version = null,
        .daemon_status = .unknown,
        .daemon_compatible = false,
        .error_info = .{ .code = .invalid_input, .message = message },
    });
}

fn writeDaemonError(stdout: anytype, request_id: ?[]const u8, err: daemon.DaemonError) !void {
    const classified = classifyDaemonError(err);
    try writeErrorResponse(stdout, .{
        .request_id = request_id,
        .decision = "error",
        .reason = classified.message,
        .daemon_protocol_version = null,
        .daemon_status = classified.status,
        .daemon_compatible = false,
        .error_info = .{ .code = classified.code, .message = classified.message },
    });
}

fn writeProtocolError(stdout: anytype, request_id: ?[]const u8, message: []const u8) !void {
    try writeErrorResponse(stdout, .{
        .request_id = request_id,
        .decision = "error",
        .reason = message,
        .daemon_protocol_version = null,
        .daemon_status = .unknown,
        .daemon_compatible = false,
        .error_info = .{ .code = .protocol_error, .message = message },
    });
}

fn writeInternalError(stdout: anytype, request_id: ?[]const u8, message: []const u8) !void {
    try writeErrorResponse(stdout, .{
        .request_id = request_id,
        .decision = "error",
        .reason = message,
        .daemon_protocol_version = null,
        .daemon_status = .unknown,
        .daemon_compatible = false,
        .error_info = .{ .code = .internal_error, .message = message },
    });
}

fn writeErrorResponse(stdout: anytype, response: MachineResponse) !void {
    try writeResponseJson(stdout, response);
}

const ClassifiedDaemonError = struct {
    code: ErrorCode,
    status: DaemonStatus,
    message: []const u8,
};

fn classifyDaemonError(err: daemon.DaemonError) ClassifiedDaemonError {
    return switch (err) {
        error.ProtocolMismatch, error.MissingHandshake, error.HandshakeMalformed => .{
            .code = .daemon_incompatible,
            .status = .incompatible,
            .message = "daemon protocol is incompatible with this Orca CLI",
        },
        error.DaemonStartTimeout => .{
            .code = .daemon_timeout,
            .status = .timeout,
            .message = "daemon evaluation timed out",
        },
        error.ResponseParseFailed, error.DaemonProtocolError => .{
            .code = .protocol_error,
            .status = .unknown,
            .message = "daemon returned an invalid protocol response",
        },
        error.RequestSerializationFailed => .{
            .code = .protocol_error,
            .status = .unknown,
            .message = "failed to serialize daemon evaluation request",
        },
        error.InvalidWorkingDirectory => .{
            .code = .invalid_input,
            .status = .unknown,
            .message = "command working directory does not exist",
        },
        error.OutOfMemory => .{
            .code = .internal_error,
            .status = .unknown,
            .message = "internal allocation failure during evaluation",
        },
        else => .{
            .code = .daemon_unavailable,
            .status = .unavailable,
            .message = "daemon is unavailable for shell-command evaluation",
        },
    };
}

fn writeResponseJson(stdout: anytype, response: MachineResponse) !void {
    try stdout.writeAll("{\n");
    try stdout.print("  \"schema_version\": {d},\n", .{response.schema_version});
    try stdout.writeAll("  \"request_id\": ");
    try writeNullableJsonString(stdout, response.request_id);
    try stdout.writeAll(",\n");
    try stdout.writeAll("  \"orca_version\": ");
    try writeJsonString(stdout, response.orca_version);
    try stdout.writeAll(",\n");
    try stdout.writeAll("  \"daemon_protocol_version\": ");
    if (response.daemon_protocol_version) |version| try stdout.print("{d}", .{version}) else try stdout.writeAll("null");
    try stdout.writeAll(",\n");
    try stdout.writeAll("  \"decision\": ");
    try writeJsonString(stdout, response.decision);
    try stdout.writeAll(",\n");
    try stdout.writeAll("  \"reason\": ");
    try writeJsonString(stdout, response.reason);
    try stdout.writeAll(",\n");
    try stdout.writeAll("  \"severity\": ");
    try writeNullableJsonString(stdout, response.severity);
    try stdout.writeAll(",\n");
    try stdout.writeAll("  \"pack_id\": ");
    try writeNullableJsonString(stdout, response.pack_id);
    try stdout.writeAll(",\n");
    try stdout.writeAll("  \"pattern_name\": ");
    try writeNullableJsonString(stdout, response.pattern_name);
    try stdout.writeAll(",\n");
    try stdout.writeAll("  \"rule_id\": ");
    try writeNullableJsonString(stdout, response.rule_id);
    try stdout.writeAll(",\n");
    try stdout.writeAll("  \"remediation\": [");
    for (response.remediation, 0..) |item, i| {
        if (i != 0) try stdout.writeAll(",");
        try stdout.writeAll("{\"description\":");
        try writeJsonString(stdout, item.description);
        try stdout.writeAll(",\"command\":null,\"platform\":null}");
    }
    try stdout.writeAll("],\n");
    // Additive machine-usable next steps for Pi / evaluate consumers.
    try stdout.writeAll("  \"remediation_commands\": [");
    if (std.mem.eql(u8, response.decision, "deny")) {
        try stdout.writeAll("\"orca explain \\\"<command>\\\"\",\"orca allow-once <code>\",\"orca allowlist list\"");
    }
    try stdout.writeAll("],\n");
    try stdout.writeAll("  \"daemon\": {\n");
    try stdout.writeAll("    \"status\": ");
    try writeJsonString(stdout, response.daemon_status.toString());
    try stdout.writeAll(",\n");
    try stdout.print("    \"compatible\": {}\n", .{response.daemon_compatible});
    try stdout.writeAll("  },\n");
    try stdout.writeAll("  \"redactions\": [],\n");
    try stdout.writeAll("  \"error\": ");
    if (response.error_info) |err| {
        try stdout.writeAll("{\n");
        try stdout.writeAll("    \"code\": ");
        try writeJsonString(stdout, err.code.toString());
        try stdout.writeAll(",\n");
        try stdout.writeAll("    \"message\": ");
        try writeJsonString(stdout, err.message);
        try stdout.writeAll("\n  }");
    } else {
        try stdout.writeAll("null");
    }
    try stdout.writeAll("\n}\n");
}

fn writeNullableJsonString(writer: anytype, value: ?[]const u8) !void {
    if (value) |text| try writeJsonString(writer, text) else try writer.writeAll("null");
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

fn mockAllow(allocator: std.mem.Allocator, command_text: []const u8, cwd: ?[]const u8) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    _ = command_text;
    _ = cwd;
    return daemon.parseResponse(allocator, "{\"id\":1,\"result\":{\"status\":\"Allow\",\"reason\":\"Command allowed by evaluator\"}}");
}

fn mockDeny(allocator: std.mem.Allocator, command_text: []const u8, cwd: ?[]const u8) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    _ = command_text;
    _ = cwd;
    return daemon.parseResponse(allocator, "{\"id\":1,\"result\":{\"status\":\"Deny\",\"reason\":\"blocked matched ghp_fake_secret_value\",\"pack_id\":\"core.filesystem\",\"pattern_name\":\"destructive-rm\",\"severity\":\"Critical\",\"matched_text_preview\":\"ghp_fake_secret_value\",\"explanation\":\"Use a safer remove target.\"}}");
}

fn mockUnavailable(allocator: std.mem.Allocator, command_text: []const u8, cwd: ?[]const u8) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    _ = allocator;
    _ = command_text;
    _ = cwd;
    return error.SocketConnectFailed;
}

fn mockProtocolMismatch(allocator: std.mem.Allocator, command_text: []const u8, cwd: ?[]const u8) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    _ = allocator;
    _ = command_text;
    _ = cwd;
    return error.ProtocolMismatch;
}

fn mockMalformed(allocator: std.mem.Allocator, command_text: []const u8, cwd: ?[]const u8) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    _ = allocator;
    _ = command_text;
    _ = cwd;
    return error.ResponseParseFailed;
}

fn mockDaemonError(allocator: std.mem.Allocator, command_text: []const u8, cwd: ?[]const u8) daemon.DaemonError!std.json.Parsed(daemon.DaemonResponse) {
    _ = command_text;
    _ = cwd;
    return daemon.parseResponse(allocator, "{\"id\":1,\"result\":{\"status\":\"Error\",\"message\":\"raw daemon failure with ghp_fake_secret_value\"}}");
}

fn testCwd(allocator: std.mem.Allocator) ![]u8 {
    const cwd_z = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, ".", allocator);
    defer allocator.free(cwd_z);
    return try allocator.dupe(u8, cwd_z);
}

fn validPayload(allocator: std.mem.Allocator, command_text: []const u8, cwd: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{{\"schema_version\":1,\"request_id\":\"req-1\",\"kind\":\"shell_command\",\"command\":\"{s}\",\"cwd\":\"{s}\",\"source\":{{\"host\":\"pi\",\"tool_name\":\"bash\",\"mode\":\"tui\",\"session_id\":\"pi-session-42\"}}}}",
        .{ command_text, cwd },
    );
}

test "evaluate parses a valid request and canonicalizes cwd" {
    const allocator = std.testing.allocator;
    const cwd = try testCwd(allocator);
    defer allocator.free(cwd);
    const payload = try validPayload(allocator, "git status", cwd);
    defer allocator.free(payload);

    const request = try parseRequest(std.testing.io, allocator, payload);
    defer request.deinit(allocator);
    try std.testing.expectEqual(api_schema_version, request.schema_version);
    try std.testing.expectEqualStrings("req-1", request.request_id.?);
    try std.testing.expectEqualStrings("pi-session-42", request.session_id.?);
    try std.testing.expectEqualStrings("pi", request.host.?);
    try std.testing.expectEqualStrings("git status", request.command);
    try std.testing.expect(std.fs.path.isAbsolute(request.cwd));
}

test "evaluate request validation errors are structured" {
    const allocator = std.testing.allocator;

    try std.testing.expectError(error.MissingSchemaVersion, parseRequest(std.testing.io, allocator, "{}"));
    try std.testing.expectError(error.UnsupportedSchemaVersion, parseRequest(std.testing.io, allocator, "{\"schema_version\":2,\"kind\":\"shell_command\",\"command\":\"git status\",\"cwd\":\"/tmp\"}"));
    try std.testing.expectError(error.UnsupportedKind, parseRequest(std.testing.io, allocator, "{\"schema_version\":1,\"kind\":\"file\",\"command\":\"git status\",\"cwd\":\"/tmp\"}"));
    try std.testing.expectError(error.MissingCommand, parseRequest(std.testing.io, allocator, "{\"schema_version\":1,\"kind\":\"shell_command\",\"cwd\":\"/tmp\"}"));
    try std.testing.expectError(error.EmptyCommand, parseRequest(std.testing.io, allocator, "{\"schema_version\":1,\"kind\":\"shell_command\",\"command\":\"   \",\"cwd\":\"/tmp\"}"));
    try std.testing.expectError(error.MissingCwd, parseRequest(std.testing.io, allocator, "{\"schema_version\":1,\"kind\":\"shell_command\",\"command\":\"git status\"}"));
    try std.testing.expectError(error.RelativeCwd, parseRequest(std.testing.io, allocator, "{\"schema_version\":1,\"kind\":\"shell_command\",\"command\":\"git status\",\"cwd\":\".\"}"));
    try std.testing.expectError(error.NonexistentCwd, parseRequest(std.testing.io, allocator, "{\"schema_version\":1,\"kind\":\"shell_command\",\"command\":\"git status\",\"cwd\":\"/definitely/not/orca/evaluate/cwd\"}"));
}

test "evaluate allow response is stable JSON and exit 0" {
    const allocator = std.testing.allocator;
    const cwd = try testCwd(allocator);
    defer allocator.free(cwd);
    const payload = try validPayload(allocator, "git status", cwd);
    defer allocator.free(payload);
    var stdout_buf: [4096]u8 = undefined;
    var stdout: std.Io.Writer = .fixed(&stdout_buf);

    const code = try evaluatePayload(std.testing.io, allocator, payload, &stdout, mockAllow, .disabled);
    try std.testing.expectEqual(exit_allowed, code);
    const output = stdout.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "\"schema_version\": 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"decision\": \"allow\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"daemon\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"error\": null") != null);
}

test "evaluate deny response is safe and exit 2" {
    const allocator = std.testing.allocator;
    const cwd = try testCwd(allocator);
    defer allocator.free(cwd);
    const payload = try validPayload(allocator, "echo ghp_fake_secret_value", cwd);
    defer allocator.free(payload);
    var stdout_buf: [8192]u8 = undefined;
    var stdout: std.Io.Writer = .fixed(&stdout_buf);

    const code = try evaluatePayload(std.testing.io, allocator, payload, &stdout, mockDeny, .disabled);
    try std.testing.expectEqual(exit_denied, code);
    const output = stdout.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "\"decision\": \"deny\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"severity\": \"critical\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"pack_id\": \"core.filesystem\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"rule_id\": \"core.filesystem:destructive-rm\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "matched_text_preview") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "ghp_fake_secret_value") == null);
}

test "evaluate records Pi decisions in workspace and global feeds" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(std.testing.io, ".git", .default_dir);
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const dashboard_root = try std.fs.path.join(std.testing.allocator, &.{ root, "home", ".orca", "dashboard" });
    defer std.testing.allocator.free(dashboard_root);
    const payload = try validPayload(std.testing.allocator, "rm -rf tmp", root);
    defer std.testing.allocator.free(payload);
    var stdout_buf: [8192]u8 = undefined;
    var stdout: std.Io.Writer = .fixed(&stdout_buf);

    const code = try evaluatePayload(std.testing.io, std.testing.allocator, payload, &stdout, mockDeny, .{ .explicit = dashboard_root });
    try std.testing.expectEqual(exit_denied, code);

    const workspace_records = try feed_writer.loadRecent(std.testing.io, std.testing.allocator, root, 4);
    defer {
        for (workspace_records) |*item| item.deinit(std.testing.allocator);
        std.testing.allocator.free(workspace_records);
    }
    try std.testing.expectEqual(@as(usize, 1), workspace_records.len);
    try std.testing.expectEqualStrings("pi", workspace_records[0].record.host.?);
    try std.testing.expectEqualStrings("pi-session-42", workspace_records[0].record.session_id.?);
    try std.testing.expectEqualStrings(root, workspace_records[0].record.workspace_root);

    const global_events = try std.fs.path.join(std.testing.allocator, &.{ dashboard_root, feed_writer.global_events_file_name });
    defer std.testing.allocator.free(global_events);
    try std.Io.Dir.cwd().access(std.testing.io, global_events, .{});
}

test "evaluate invalid input writes JSON error and exit 64" {
    var stdout_buf: [2048]u8 = undefined;
    var stdout: std.Io.Writer = .fixed(&stdout_buf);
    const code = try evaluatePayload(std.testing.io, std.testing.allocator, "{not json", &stdout, mockAllow, .disabled);
    try std.testing.expectEqual(exit_invalid_input, code);
    const output = stdout.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "\"decision\": \"error\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"code\": \"invalid_input\"") != null);
}

test "evaluate daemon failures map to JSON error exit 3" {
    const allocator = std.testing.allocator;
    const cwd = try testCwd(allocator);
    defer allocator.free(cwd);
    const payload = try validPayload(allocator, "git status", cwd);
    defer allocator.free(payload);

    const cases = [_]struct { EvaluatorFn, []const u8 }{
        .{ mockUnavailable, "daemon_unavailable" },
        .{ mockProtocolMismatch, "daemon_incompatible" },
        .{ mockMalformed, "protocol_error" },
        .{ mockDaemonError, "protocol_error" },
    };
    for (cases) |case| {
        var stdout_buf: [4096]u8 = undefined;
        var stdout: std.Io.Writer = .fixed(&stdout_buf);
        const code = try evaluatePayload(std.testing.io, allocator, payload, &stdout, case[0], .disabled);
        try std.testing.expectEqual(exit_evaluator_error, code);
        const output = stdout.buffered();
        try std.testing.expect(std.mem.indexOf(u8, output, "\"decision\": \"error\"") != null);
        try std.testing.expect(std.mem.indexOf(u8, output, case[1]) != null);
        try std.testing.expect(std.mem.indexOf(u8, output, "ghp_fake_secret_value") == null);
    }
}
