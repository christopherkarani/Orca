const std = @import("std");

const core = @import("orca_core").core;
const supervisor = core.supervisor;
const core_api = @import("orca_core").api;
const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");

const ReplayCliOptions = struct {
    session: []const u8 = "last",
    json: bool = false,
    only_denied: bool = false,
    verify: bool = false,
    list: bool = false,
    /// When true, a missing default `last` session lists sessions instead of erroring.
    fallback_to_list: bool = false,
};

pub fn command(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    const options = parseOptions(argv, stdout, stderr) catch |err| switch (err) {
        error.HelpShown => return exit_codes.success,
        error.Usage => return exit_codes.usage,
        else => return err,
    };

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const workspace_root = supervisor.resolveWorkspaceRoot(allocator, null, ".") catch |err| {
        try stderr.print("orca replay: failed to resolve workspace: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer allocator.free(workspace_root);

    if (options.list) {
        return listSessions(allocator, workspace_root, stdout);
    }

    return replaySession(allocator, workspace_root, options, stdout, stderr);
}

fn replaySession(
    allocator: std.mem.Allocator,
    workspace_root: []const u8,
    options: ReplayCliOptions,
    stdout: anytype,
    stderr: anytype,
) !u8 {
    var session = core_api.loadReplay(allocator, workspace_root, .{
        .session = options.session,
        .only_denied = options.only_denied,
        .verify = options.verify,
    }) catch |err| switch (err) {
        error.FileNotFound => {
            if (options.fallback_to_list) {
                return listSessions(allocator, workspace_root, stdout);
            }
            try stderr.writeAll("orca replay: session not found.\n");
            return exit_codes.general;
        },
        error.HashVerificationFailed => {
            const session_dir_path = sessionDirPathForError(allocator, workspace_root, options.session) catch null;
            defer if (session_dir_path) |path| allocator.free(path);
            const verify_result = if (session_dir_path) |path| core_api.verifyReplay(allocator, path) catch null else null;
            if (verify_result) |result| {
                defer result.deinit(allocator);
                if (result.reason) |reason| try stderr.print("orca replay: hash verification failed: {s}\n", .{reason}) else try stderr.writeAll("orca replay: hash verification failed.\n");
            } else {
                try stderr.writeAll("orca replay: hash verification failed.\n");
            }
            return exit_codes.general;
        },
        else => {
            try stderr.print("orca replay: failed: {s}\n", .{@errorName(err)});
            return exit_codes.general;
        },
    };
    defer session.deinit();

    if (options.json) {
        try core_api.writeReplayJson(stdout, session);
    } else {
        try core_api.writeReplayHuman(stdout, session, options.verify);
    }
    return exit_codes.success;
}

fn listSessions(allocator: std.mem.Allocator, workspace_root: []const u8, stdout: anytype) !u8 {
    const sessions_dir = try std.fs.path.join(allocator, &.{ workspace_root, ".orca", "sessions" });
    defer allocator.free(sessions_dir);

    var dir = std.fs.cwd().openDir(sessions_dir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => {
            try stdout.writeAll("No sessions found. Run `orca run -- <command>` to create one.\n");
            return exit_codes.success;
        },
        else => return err,
    };
    defer dir.close();

    try stdout.writeAll("SESSION ID\n");

    var count: usize = 0;
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .directory) continue;
        try stdout.print("{s}\n", .{entry.name});
        count += 1;
    }

    if (count == 0) {
        try stdout.writeAll("\nNo sessions found. Run `orca run -- <command>` to create one.\n");
    } else {
        try stdout.print("\n{d} session(s) found.\n", .{count});
        try stdout.writeAll("Run `orca replay --session <id>` to view a session.\n");
    }

    return exit_codes.success;
}

fn parseOptions(argv: []const []const u8, stdout: anytype, stderr: anytype) !ReplayCliOptions {
    var options: ReplayCliOptions = .{
        .fallback_to_list = argv.len == 0,
    };
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        const arg = argv[index];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            _ = try help.writeCommand(stdout, "replay");
            return error.HelpShown;
        } else if (std.mem.eql(u8, arg, "--list")) {
            options.list = true;
        } else if (std.mem.eql(u8, arg, "--session")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("orca replay: --session requires a session id or 'last'.\n");
                return error.Usage;
            }
            options.session = argv[index];
            options.fallback_to_list = false;
        } else if (std.mem.eql(u8, arg, "--json")) {
            options.json = true;
            options.fallback_to_list = false;
        } else if (std.mem.eql(u8, arg, "--verify")) {
            options.verify = true;
            options.fallback_to_list = false;
        } else if (std.mem.eql(u8, arg, "--only")) {
            index += 1;
            if (index >= argv.len or !std.mem.eql(u8, argv[index], "denied")) {
                try stderr.writeAll("orca replay: --only currently supports only 'denied'.\n");
                return error.Usage;
            }
            options.only_denied = true;
            options.fallback_to_list = false;
        } else {
            try stderr.print("orca replay: unknown option '{s}'.\n", .{arg});
            return error.Usage;
        }
    }
    return options;
}

fn sessionDirPathForError(allocator: std.mem.Allocator, workspace_root: []const u8, requested: []const u8) ![]u8 {
    const session_id = if (std.mem.eql(u8, requested, "last")) blk: {
        const last_path = try std.fs.path.join(allocator, &.{ workspace_root, ".orca", "last" });
        defer allocator.free(last_path);
        const text = try std.fs.cwd().readFileAlloc(allocator, last_path, core.limits.max_session_id_len + 2);
        defer allocator.free(text);
        break :blk try allocator.dupe(u8, std.mem.trim(u8, text, " \t\r\n"));
    } else try allocator.dupe(u8, requested);
    defer allocator.free(session_id);
    return try std.fs.path.join(allocator, &.{ workspace_root, ".orca", "sessions", session_id });
}

test "replay rejects invalid --only value" {
    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(&.{ "--only", "allowed" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "--only") != null);
}

test "replay --list prints sessions or friendly empty message" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath(".orca/sessions/session-a");
    try tmp.dir.makePath(".orca/sessions/session-b");

    const prev_cwd = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(prev_cwd);
    try std.process.chdir(tmp.dir);
    defer std.process.chdir(prev_cwd) catch {};

    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(&.{"--list"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);
    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "session-a") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "session-b") != null);
}

test "replay with no args and no sessions lists instead of erroring" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const prev_cwd = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(prev_cwd);
    try std.process.chdir(tmp.dir);
    defer std.process.chdir(prev_cwd) catch {};

    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(&.{}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);
    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "No sessions found") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}
