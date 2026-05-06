const std = @import("std");

const aegis_mcp = @import("../mcp/mod.zig");
const audit = @import("../audit/mod.zig");
const core = @import("../core/mod.zig");
const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");
const policy = @import("../policy/mod.zig");

pub fn command(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len > 0 and (std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h"))) {
        _ = try help.writeCommand(stdout, "mcp");
        return exit_codes.success;
    }
    if (argv.len == 0) {
        _ = try help.writeCommand(stderr, "mcp");
        return exit_codes.usage;
    }
    if (std.mem.eql(u8, argv[0], "inspect")) return inspect(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "proxy")) return proxy(argv[1..], stdout, stderr);
    try stderr.print("aegis mcp: unknown subcommand '{s}'.\n", .{argv[0]});
    return exit_codes.usage;
}

const Options = struct {
    command_argv: []const []const u8 = &.{},
    owns_command_argv: bool = false,
    server_name: []const u8 = "fake",
    policy_path: ?[]const u8 = null,
    mode: ?policy.schema.Mode = null,

    fn deinit(self: Options, allocator: std.mem.Allocator) void {
        if (self.owns_command_argv) allocator.free(self.command_argv);
    }
};

fn parseOptions(allocator: std.mem.Allocator, argv: []const []const u8, stderr: anytype) !Options {
    var options: Options = .{};
    var command_parts: std.ArrayList([]const u8) = .empty;
    defer command_parts.deinit(allocator);
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        const arg = argv[index];
        if (std.mem.eql(u8, arg, "--command")) {
            index += 1;
            if (index >= argv.len) return error.Usage;
            try command_parts.append(allocator, argv[index]);
        } else if (std.mem.eql(u8, arg, "--server")) {
            index += 1;
            if (index >= argv.len) return error.Usage;
            options.server_name = argv[index];
            try stderr.print("aegis mcp: --server presets are not implemented in Phase 11; use --command.\n", .{});
            return error.Unsupported;
        } else if (std.mem.eql(u8, arg, "--name")) {
            index += 1;
            if (index >= argv.len) return error.Usage;
            options.server_name = argv[index];
        } else if (std.mem.eql(u8, arg, "--policy")) {
            index += 1;
            if (index >= argv.len) return error.Usage;
            options.policy_path = argv[index];
        } else if (std.mem.eql(u8, arg, "--mode")) {
            index += 1;
            if (index >= argv.len) return error.Usage;
            options.mode = policy.schema.Mode.parse(argv[index]) orelse return error.Usage;
        } else if (std.mem.eql(u8, arg, "--")) {
            for (argv[index + 1 ..]) |command_arg| try command_parts.append(allocator, command_arg);
            break;
        } else {
            try stderr.print("aegis mcp: unknown option '{s}'.\n", .{arg});
            return error.Usage;
        }
    }
    if (command_parts.items.len == 0) return error.MissingCommand;
    options.command_argv = try command_parts.toOwnedSlice(allocator);
    options.owns_command_argv = true;
    return options;
}

fn inspect(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len > 0 and (std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h"))) {
        try stdout.writeAll("Usage: aegis mcp inspect --command <server> [--name <server-name>] [--policy <path>]\n");
        return exit_codes.success;
    }
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const options = parseOptions(allocator, argv, stderr) catch |err| return usageCode(err, stderr);
    defer options.deinit(allocator);
    var server = aegis_mcp.transport.ProcessServer.spawn(allocator, options.command_argv) catch |err| {
        try stderr.print("aegis mcp inspect: failed to start server: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer server.deinit();

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-03-26\",\"capabilities\":{},\"clientInfo\":{\"name\":\"aegis\",\"version\":\"0.0.0-dev\"}}}";
    const initialized = "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\",\"params\":{}}";
    const list_tools = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\",\"params\":{}}";
    const init_response = aegis_mcp.transport.ProcessServer.request(&server, allocator, initialize) catch |err| {
        try stderr.print("aegis mcp inspect: initialize failed: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    allocator.free(init_response);
    aegis_mcp.transport.ProcessServer.notify(&server, initialized) catch |err| {
        try stderr.print("aegis mcp inspect: initialized notification failed: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    const tools_response = aegis_mcp.transport.ProcessServer.request(&server, allocator, list_tools) catch |err| {
        try stderr.print("aegis mcp inspect: tools/list failed: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer allocator.free(tools_response);
    var parsed = aegis_mcp.jsonrpc.parseLine(allocator, tools_response) catch |err| {
        try stderr.print("aegis mcp inspect: invalid tools/list response: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer parsed.deinit();
    var inventory = aegis_mcp.tools.inspectToolsListResponse(allocator, options.server_name, parsed.value()) catch |err| {
        try stderr.print("aegis mcp inspect: could not inspect tools: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer inventory.deinit(allocator);

    try stdout.print("MCP Server: {s}\nTransport: stdio\nTools:\n", .{options.server_name});
    for (inventory.tools) |tool| {
        try stdout.print("  {s:<24} risk: {s:<8} default: {s}\n", .{ tool.name, tool.risk.toString(), aegis_mcp.tools.defaultDecisionForRisk(tool.risk) });
    }
    try stdout.writeAll("\nFindings:\n");
    var finding_count: usize = 0;
    for (inventory.tools) |tool| {
        for (tool.findings) |finding| {
            finding_count += 1;
            try stdout.print("  {s}: {s} ({s})\n", .{ tool.name, finding.reason, finding.risk.toString() });
        }
    }
    if (finding_count == 0) try stdout.writeAll("  none\n");
    return exit_codes.success;
}

fn proxy(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len > 0 and (std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h"))) {
        try stdout.writeAll("Usage: aegis mcp proxy --command <server> [--name <server-name>] [--policy <path>] [--mode observe|ask|strict|ci]\n");
        return exit_codes.success;
    }
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const options = parseOptions(allocator, argv, stderr) catch |err| return usageCode(err, stderr);
    defer options.deinit(allocator);
    const workspace = try core.supervisor.resolveWorkspaceRoot(allocator, null, ".");
    defer allocator.free(workspace);
    var loaded = try policy.load.discover(allocator, options.policy_path, workspace);
    defer loaded.deinit();
    const mode = options.mode orelse loaded.policy.mode;

    const session = try makeSession(options.command_argv, workspace, mode);
    var session_writer = audit.writer.SessionWriter.init(allocator, session) catch |err| {
        try stderr.print("aegis mcp proxy: audit unavailable: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer session_writer.deinit();
    try session_writer.writeLastPointer();

    var server = aegis_mcp.transport.ProcessServer.spawn(allocator, options.command_argv) catch |err| {
        try stderr.print("aegis mcp proxy: failed to start server: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer server.deinit();

    const stdin_buffer = try allocator.alloc(u8, core.limits.max_mcp_message_len + 1);
    defer allocator.free(stdin_buffer);
    var stdin_reader = std.fs.File.stdin().reader(stdin_buffer);
    var tty_file: ?std.fs.File = null;
    var approval_reader_storage: ?std.fs.File.Reader = null;
    var approval_writer_storage: ?std.fs.File.Writer = null;
    var approval_read_buffer: [1024]u8 = undefined;
    var approval_write_buffer: [4096]u8 = undefined;
    if (mode != .ci) {
        if (std.fs.openFileAbsolute("/dev/tty", .{ .mode = .read_write })) |file| {
            tty_file = file;
            approval_reader_storage = file.reader(&approval_read_buffer);
            approval_writer_storage = file.writer(&approval_write_buffer);
        } else |_| {}
    }
    defer if (tty_file) |file| file.close();

    try aegis_mcp.proxy.runWithServer(allocator, .{
        .server_name = options.server_name,
        .server_command_display = options.command_argv[0],
        .policy = &loaded.policy,
        .mode = mode,
        .audit_writer = &session_writer,
        .approval_reader = if (approval_reader_storage) |*reader| &reader.interface else null,
        .approval_writer = if (approval_writer_storage) |*writer| &writer.interface else null,
    }, &stdin_reader.interface, stdout, .{
        .context = &server,
        .request = aegis_mcp.transport.ProcessServer.request,
        .notify = aegis_mcp.transport.ProcessServer.notify,
    });
    if (approval_writer_storage) |*writer| writer.interface.flush() catch {};
    var completed_session = session;
    completed_session.ended_at = core.time.Timestamp.now();
    try audit.summary.writeFiles(allocator, session_writer.session_dir_path, .{
        .session = completed_session,
        .status = .{ .exited = 0 },
        .event_count = session_writer.event_count,
        .final_event_hash = session_writer.finalHash() orelse "",
        .policy = loaded.path,
    });
    return exit_codes.success;
}

fn usageCode(err: anyerror, stderr: anytype) !u8 {
    switch (err) {
        error.MissingCommand => try stderr.writeAll("aegis mcp: expected --command <server>.\n"),
        error.Unsupported => {},
        else => try stderr.writeAll("aegis mcp: invalid arguments.\n"),
    }
    return if (err == error.Unsupported) exit_codes.unsupported else exit_codes.usage;
}

fn makeSession(command_argv: []const []const u8, workspace: []const u8, mode: policy.schema.Mode) !core.session.Session {
    const now = core.time.Timestamp.now();
    return .{
        .id = try core.session.generateSessionId(now),
        .started_at = now,
        .command = "aegis mcp proxy",
        .args = command_argv,
        .workspace_root = workspace,
        .mode = mode.toCoreMode(),
        .platform = core.platform.detectOs(),
    };
}

test "mcp command help and invalid subcommands are stable" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const help_code = try command(&.{"--help"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, help_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "MCP proxy") != null);

    stdout_stream.reset();
    stderr_stream.reset();
    const bad_code = try command(&.{"unknown"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, bad_code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "unknown subcommand") != null);
}

test "mcp command parsing preserves server argv after --command" {
    var stderr_buf: [256]u8 = undefined;
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const options = try parseOptions(std.testing.allocator, &.{ "--command", "node", "--", "server.js", "--flag" }, stderr_stream.writer());
    defer options.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), options.command_argv.len);
    try std.testing.expectEqualStrings("node", options.command_argv[0]);
    try std.testing.expectEqualStrings("server.js", options.command_argv[1]);
    try std.testing.expectEqualStrings("--flag", options.command_argv[2]);
}
