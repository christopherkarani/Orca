const std = @import("std");

pub const args = @import("args.zig");
pub const exit_codes = @import("exit_codes.zig");
pub const help = @import("help.zig");
pub const run_command = @import("run.zig");
pub const init = @import("init.zig");
pub const doctor = @import("doctor.zig");
pub const policy = @import("policy.zig");
pub const replay = @import("replay.zig");
pub const diff = @import("diff.zig");
pub const apply = @import("apply.zig");
pub const discard = @import("discard.zig");
pub const mcp = @import("mcp.zig");
pub const redteam = @import("redteam.zig");
pub const completions = @import("completions.zig");

pub const version = "0.0.0-dev";

pub fn run(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0 or std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h") or std.mem.eql(u8, argv[0], "help")) {
        try help.write(stdout);
        return exit_codes.success;
    }

    const command = argv[0];
    if (std.mem.eql(u8, command, "version")) {
        try stdout.writeAll("aegis " ++ version ++ "\n");
        return exit_codes.success;
    }

    if (isKnownFutureCommand(command)) {
        try stderr.writeAll("aegis: command '");
        try stderr.writeAll(command);
        try stderr.writeAll("' is reserved for a later phase and is not implemented in Phase 02.\n");
        return exit_codes.unavailable;
    }

    try stderr.writeAll("aegis: unknown command '");
    try stderr.writeAll(command);
    try stderr.writeAll("'. Run 'aegis help' for usage.\n");
    return exit_codes.usage;
}

fn isKnownFutureCommand(command: []const u8) bool {
    const commands = [_][]const u8{
        "run",
        "init",
        "doctor",
        "policy",
        "replay",
        "diff",
        "apply",
        "discard",
        "mcp",
        "redteam",
        "completions",
    };
    for (commands) |known| {
        if (std.mem.eql(u8, command, known)) return true;
    }
    return false;
}

test "help flag prints command summary" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try run(&.{"--help"}, stdout_stream.writer(), stderr_stream.writer());

    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Aegis") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Commands:") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "version prints development version" {
    var stdout_buf: [128]u8 = undefined;
    var stderr_buf: [128]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try run(&.{"version"}, stdout_stream.writer(), stderr_stream.writer());

    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expectEqualStrings("aegis 0.0.0-dev\n", stdout_stream.getWritten());
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "unknown command returns non-zero with useful message" {
    var stdout_buf: [128]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try run(&.{"not-a-command"}, stdout_stream.writer(), stderr_stream.writer());

    try std.testing.expect(code != exit_codes.success);
    try std.testing.expectEqualStrings("", stdout_stream.getWritten());
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "unknown command") != null);
}
