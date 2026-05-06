const std = @import("std");

const audit = @import("../audit/mod.zig");
const core = @import("../core/mod.zig");
const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");

const RunOptions = struct {
    workspace: ?[]const u8 = null,
    mode: core.types.Mode = .observe,
    session_name: ?[]const u8 = null,
    command_argv: []const []const u8 = &.{},
};

pub fn command(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    return commandWithStdio(argv, stdout, stderr, .inherit, true);
}

fn commandWithStdio(argv: []const []const u8, stdout: anytype, stderr: anytype, stdio: core.supervisor.StdioBehavior, audit_enabled: bool) !u8 {
    const options = parseOptions(argv, stdout, stderr) catch |err| switch (err) {
        error.HelpShown => return exit_codes.success,
        error.Usage => return exit_codes.usage,
        else => return err,
    };

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const StartPrinter = struct {
        writer: @TypeOf(stdout),

        pub fn print(context: *anyopaque, session: core.session.Session) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            try printSessionStart(self.writer, session);
            try flushIfSupported(self.writer);
        }
    };

    var start_printer: StartPrinter = .{ .writer = stdout };
    const AuditContext = struct {
        allocator: std.mem.Allocator,
        writer: ?audit.writer.SessionWriter = null,

        pub fn init(context: *anyopaque, session: core.session.Session) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.writer = try audit.writer.SessionWriter.init(self.allocator, session);
        }

        pub fn append(context: *anyopaque, ev: core.event.Event) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            try self.writer.?.appendEvent(ev);
        }

        pub fn deinit(self: *@This()) void {
            if (self.writer) |*writer| writer.deinit();
            self.writer = null;
        }
    };
    var audit_context: AuditContext = .{ .allocator = allocator };
    defer audit_context.deinit();

    const before_spawn = if (audit_enabled) core.supervisor.StartHook{
        .context = &audit_context,
        .callback = AuditContext.init,
    } else null;
    const on_event = if (audit_enabled) core.supervisor.EventHook{
        .context = &audit_context,
        .callback = AuditContext.append,
    } else null;

    var result = core.supervisor.run(allocator, .{
        .command = options.command_argv[0],
        .args = options.command_argv[1..],
        .workspace = options.workspace,
        .mode = options.mode,
        .session_name = options.session_name,
        .stdio = stdio,
        .before_spawn = before_spawn,
        .on_session_start = .{
            .context = &start_printer,
            .callback = StartPrinter.print,
        },
        .on_event = on_event,
    }) catch |err| switch (err) {
        error.CommandNotFound => {
            try stderr.print("aegis run: command not found: {s}\n", .{options.command_argv[0]});
            return exit_codes.general;
        },
        error.InvalidCommand => {
            try stderr.writeAll("aegis run: missing command after '--'.\n");
            return exit_codes.usage;
        },
        error.FileNotFound => {
            try stderr.print("aegis run: workspace not found: {s}\n", .{options.workspace orelse "."});
            return exit_codes.general;
        },
        else => {
            try stderr.print("aegis run: failed to launch child: {s}\n", .{@errorName(err)});
            return exit_codes.general;
        },
    };
    defer result.deinit();

    if (audit_context.writer) |*writer| {
        const final_hash = writer.finalHash() orelse "";
        try audit.summary.writeFiles(allocator, writer.session_dir_path, .{
            .session = result.session,
            .status = result.status,
            .event_count = writer.event_count,
            .final_event_hash = final_hash,
        });
        try writer.writeLastPointer();
    }

    try printSessionEnd(stdout, result);

    return switch (result.status) {
        .exited => |code| code,
        .signal => |signal| {
            try stderr.print("aegis run: child terminated by signal {d}.\n", .{signal});
            return exit_codes.child_failure;
        },
        .stopped => |signal| {
            try stderr.print("aegis run: child stopped by signal {d}.\n", .{signal});
            return exit_codes.child_failure;
        },
        .unknown => |status| {
            try stderr.print("aegis run: child ended with unknown status {d}.\n", .{status});
            return exit_codes.child_failure;
        },
    };
}

fn parseOptions(argv: []const []const u8, stdout: anytype, stderr: anytype) !RunOptions {
    var options: RunOptions = .{};
    var index: usize = 0;

    while (index < argv.len) : (index += 1) {
        const arg = argv[index];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            _ = try help.writeCommand(stdout, "run");
            return error.HelpShown;
        } else if (std.mem.eql(u8, arg, "--")) {
            options.command_argv = argv[index + 1 ..];
            break;
        } else if (std.mem.eql(u8, arg, "--workspace")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("aegis run: --workspace requires a path.\n");
                return error.Usage;
            }
            options.workspace = argv[index];
        } else if (std.mem.eql(u8, arg, "--mode")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("aegis run: --mode requires observe, ask, strict, or ci.\n");
                return error.Usage;
            }
            options.mode = parseMode(argv[index]) orelse {
                try stderr.print("aegis run: unsupported mode '{s}'. Expected observe, ask, strict, or ci.\n", .{argv[index]});
                return error.Usage;
            };
        } else if (std.mem.eql(u8, arg, "--session-name")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("aegis run: --session-name requires a name.\n");
                return error.Usage;
            }
            options.session_name = argv[index];
        } else if (std.mem.startsWith(u8, arg, "-")) {
            try stderr.print("aegis run: unknown option '{s}'.\n", .{arg});
            return error.Usage;
        } else {
            try stderr.writeAll("aegis run: expected '--' before child command.\n");
            return error.Usage;
        }
    }

    if (options.command_argv.len == 0) {
        try stderr.writeAll("aegis run: missing command after '--'.\n");
        return error.Usage;
    }

    return options;
}

fn parseMode(value: []const u8) ?core.types.Mode {
    if (std.mem.eql(u8, value, "observe")) return .observe;
    if (std.mem.eql(u8, value, "ask")) return .ask;
    if (std.mem.eql(u8, value, "strict")) return .strict;
    if (std.mem.eql(u8, value, "ci")) return .ci;
    return null;
}

fn printSessionStart(stdout: anytype, session: core.session.Session) !void {
    try stdout.print(
        \\Aegis session started: {s}
        \\Workspace: {s}
        \\Mode: {s}
        \\
    , .{
        session.id.slice(),
        session.workspace_root,
        session.mode.toString(),
    });
    if (session.session_name) |name| {
        try stdout.print("Session: {s}\n", .{name});
    }
    try stdout.writeAll("\n");
}

fn printSessionEnd(stdout: anytype, result: core.supervisor.SessionResult) !void {
    try stdout.print("\nAegis session ended: exit code {d}\n", .{result.exitCode()});
}

fn flushIfSupported(writer: anytype) !void {
    const Writer = @TypeOf(writer);
    switch (@typeInfo(Writer)) {
        .pointer => |pointer| {
            if (@hasDecl(pointer.child, "flush")) {
                try writer.flush();
            }
        },
        else => {
            if (@hasDecl(Writer, "flush")) {
                try writer.flush();
            }
        },
    }
}

test "run rejects missing child command" {
    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(&.{"--"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "missing command") != null);
}

test "run rejects child command without separator" {
    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(&.{"echo"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "expected '--'") != null);
}

test "run reports missing command usefully" {
    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try commandForTest(&.{ "--", "aegis-definitely-missing-command" }, stdout_stream.writer(), stderr_stream.writer(), .ignore);
    try std.testing.expectEqual(exit_codes.general, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "command not found") != null);
}

pub fn commandForTest(argv: []const []const u8, stdout: anytype, stderr: anytype, stdio: core.supervisor.StdioBehavior) !u8 {
    return commandWithStdio(argv, stdout, stderr, stdio, false);
}
