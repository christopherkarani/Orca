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
pub const shim = @import("shim.zig");

pub const version = "0.0.0-dev";

pub fn run(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    return runWithCwd(std.fs.cwd(), argv, stdout, stderr);
}

pub fn runWithCwd(cwd: std.fs.Dir, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0 or std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h")) {
        try help.write(stdout);
        return exit_codes.success;
    }

    const command = argv[0];
    if (std.mem.eql(u8, command, "help")) {
        if (argv.len == 1) {
            try help.write(stdout);
            return exit_codes.success;
        }
        if (argv.len > 2) {
            try stderr.writeAll("aegis help: expected at most one command.\n");
            return exit_codes.usage;
        }
        if (!try help.writeCommand(stdout, argv[1])) {
            try stderr.print("aegis help: unknown command '{s}'.\n", .{argv[1]});
            return exit_codes.usage;
        }
        return exit_codes.success;
    }

    if (std.mem.eql(u8, command, "version") or std.mem.eql(u8, command, "--version")) {
        if (argv.len > 1) {
            if (argv.len == 2 and (std.mem.eql(u8, argv[1], "--help") or std.mem.eql(u8, argv[1], "-h"))) {
                _ = try help.writeCommand(stdout, "version");
                return exit_codes.success;
            }
            try stderr.writeAll("aegis version: expected no arguments. Run 'aegis help version' for usage.\n");
            return exit_codes.usage;
        }
        try stdout.writeAll("aegis " ++ version ++ "\n");
        return exit_codes.success;
    }

    if (std.mem.eql(u8, command, "run")) return run_command.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "init")) return init.command(cwd, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "doctor")) return doctor.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "policy")) return policy.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "replay")) return replay.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "diff")) return diff.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "apply")) return apply.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "discard")) return discard.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "mcp")) return mcp.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "redteam")) return redteam.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "shim")) return shim.command(argv[1..], stdout, stderr);
    try stderr.writeAll("aegis: unknown command '");
    try stderr.writeAll(command);
    try stderr.writeAll("'. Run 'aegis help' for usage.\n");
    return exit_codes.usage;
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

test "command-specific help works through help command and command flag" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try run(&.{ "help", "run" }, stdout_stream.writer(), stderr_stream.writer());

    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "aegis run") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    stdout_stream.reset();
    stderr_stream.reset();
    const flag_code = try run(&.{ "run", "--help" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, flag_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "direct-child supervision") != null);
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

test "version supports help and rejects extra arguments" {
    var stdout_buf: [256]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const help_code = try run(&.{ "version", "--help" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, help_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "aegis version") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    stdout_stream.reset();
    stderr_stream.reset();
    const invalid_code = try run(&.{ "version", "typo" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, invalid_code);
    try std.testing.expectEqualStrings("", stdout_stream.getWritten());
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "expected no arguments") != null);
}

test "unknown command returns non-zero with useful message" {
    var stdout_buf: [128]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try run(&.{"not-a-command"}, stdout_stream.writer(), stderr_stream.writer());

    try std.testing.expect(code != exit_codes.success);
    try std.testing.expectEqual(exit_codes.usage, code);
    try std.testing.expectEqualStrings("", stdout_stream.getWritten());
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "unknown command") != null);
}

test "init dispatch creates policy in provided working directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try runWithCwd(tmp.dir, &.{ "init", "--mode", "strict" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const policy_text = try tmp.dir.readFileAlloc(std.testing.allocator, ".aegis/policy.yaml", 4096);
    defer std.testing.allocator.free(policy_text);
    try std.testing.expect(std.mem.indexOf(u8, policy_text, "mode: strict") != null);
}

test "doctor dispatch prints platform capabilities" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try run(&.{"doctor"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Capabilities:") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "planned") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "policy command rejects unknown subcommands" {
    var stdout_buf: [256]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try run(&.{ "policy", "--bad" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, code);
    try std.testing.expectEqualStrings("", stdout_stream.getWritten());
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "unknown subcommand") != null);
}

test "run dispatch launches child command" {
    var stdout_buf: [256]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try run_command.commandForTest(&.{ "--", "zig", "version" }, stdout_stream.writer(), stderr_stream.writer(), .ignore);
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Aegis session started") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Aegis session ended: exit code 0") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}
