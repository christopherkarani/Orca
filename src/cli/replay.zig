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

    var session = core_api.loadReplay(allocator, workspace_root, .{
        .session = options.session,
        .only_denied = options.only_denied,
        .verify = options.verify,
    }) catch |err| switch (err) {
        error.FileNotFound => {
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

fn parseOptions(argv: []const []const u8, stdout: anytype, stderr: anytype) !ReplayCliOptions {
    var options: ReplayCliOptions = .{};
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        const arg = argv[index];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            _ = try help.writeCommand(stdout, "replay");
            return error.HelpShown;
        } else if (std.mem.eql(u8, arg, "--session")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("orca replay: --session requires a session id or 'last'.\n");
                return error.Usage;
            }
            options.session = argv[index];
        } else if (std.mem.eql(u8, arg, "--json")) {
            options.json = true;
        } else if (std.mem.eql(u8, arg, "--verify")) {
            options.verify = true;
        } else if (std.mem.eql(u8, arg, "--only")) {
            index += 1;
            if (index >= argv.len or !std.mem.eql(u8, argv[index], "denied")) {
                try stderr.writeAll("orca replay: --only currently supports only 'denied'.\n");
                return error.Usage;
            }
            options.only_denied = true;
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
