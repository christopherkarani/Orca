const std = @import("std");
const core = @import("orca_core").core;
const supervisor = core.supervisor;
const core_api = @import("orca_core").api;
const intercept = @import("../intercept/mod.zig");
const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");
const suggestions = @import("suggestions.zig");

pub fn command(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    const options = parseOptions(io, argv, stdout, stderr) catch |err| switch (err) {
        error.HelpShown => return exit_codes.success,
        error.Usage => return exit_codes.usage,
        else => return err,
    };

    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const workspace_root = try supervisor.resolveWorkspaceRoot(io, allocator, null, ".");
    defer allocator.free(workspace_root);
    const session_id = intercept.files.resolveSessionId(io, allocator, workspace_root, options.session) catch |err| {
        try stderr.print("orca discard: failed to resolve session '{s}': {s}\n", .{ options.session, @errorName(err) });
        return exit_codes.general;
    };
    defer allocator.free(session_id);
    const audit_session = commandAuditSession(io, session_id, workspace_root, "orca discard");
    var session_writer = core_api.openAuditWriter(io, allocator, workspace_root, session_id) catch |err| {
        try stderr.print("orca discard: failed to open session audit log: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer session_writer.deinit();
    const audit_context: intercept.files.AuditContext = .{ .writer = &session_writer, .session = audit_session };

    const result = intercept.files.discardStaged(io, allocator, workspace_root, session_id, options.file, audit_context) catch |err| {
        try stderr.print("orca discard: failed to discard staged files: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    if (session_writer.finalHash()) |hash| {
        try core_api.updateAuditSummaryFinalHash(allocator, session_writer.session_dir_path, session_writer.event_count, hash);
    }
    try stdout.print("Discarded {d} staged file(s) from session {s}.\n", .{ result.count, session_id });
    return exit_codes.success;
}

const Options = struct {
    session: []const u8 = "last",
    file: ?[]const u8 = null,
};

fn parseOptions(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !Options {
    var options: Options = .{};
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        const arg = argv[index];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            _ = try help.writeCommand(io, stdout, "discard");
            return error.HelpShown;
        } else if (std.mem.eql(u8, arg, "--session")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("orca discard: --session requires an id or 'last'.\n");
                return error.Usage;
            }
            options.session = argv[index];
        } else if (std.mem.eql(u8, arg, "--file")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("orca discard: --file requires a workspace path.\n");
                return error.Usage;
            }
            options.file = argv[index];
        } else {
            try suggestions.writeUnknownOption(stderr, "orca discard", arg, &.{ "--session", "--file", "--help", "-h" }, "discard");
            return error.Usage;
        }
    }
    return options;
}

fn commandAuditSession(io: std.Io, session_id_text: []const u8, workspace_root: []const u8, command_name: []const u8) core.session.Session {
    var session_id: core.session.SessionId = .{ .value = undefined, .len = 0 };
    const len = @min(session_id_text.len, session_id.value.len);
    @memcpy(session_id.value[0..len], session_id_text[0..len]);
    session_id.len = len;
    return .{
        .id = session_id,
        .started_at = core.time.Timestamp.now(io),
        .command = command_name,
        .args = &.{},
        .workspace_root = workspace_root,
        .mode = .strict,
        .platform = core.platform.detectOs(),
    };
}
