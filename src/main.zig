const std = @import("std");
const builtin = @import("builtin");
const orca = @import("orca");

pub fn main() !void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    var stdout_buffer: [4096]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);

    const shim_alias = if (builtin.os.tag == .windows) orca.intercept.commands.shimAliasFromExecutablePath(argv[0]) else null;
    const code = if (shim_alias) |alias|
        try runWindowsExecutableShim(allocator, alias, argv[1..], &stdout_writer.interface, &stderr_writer.interface)
    else
        try orca.cli.run(argv[1..], &stdout_writer.interface, &stderr_writer.interface);
    try stdout_writer.interface.flush();
    try stderr_writer.interface.flush();
    std.process.exit(code);
}

fn runWindowsExecutableShim(allocator: std.mem.Allocator, alias: []const u8, args: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var shim_argv = try allocator.alloc([]const u8, args.len + 3);
    defer allocator.free(shim_argv);
    shim_argv[0] = "exec";
    shim_argv[1] = "--";
    shim_argv[2] = alias;
    if (args.len > 0) @memcpy(shim_argv[3..], args);
    return orca.cli.shim.command(shim_argv, stdout, stderr);
}

test {
    _ = orca.cli;
}
