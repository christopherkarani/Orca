const std = @import("std");

const core_api = @import("aegis_core").api;
const credentials = @import("../intercept/credentials.zig");
const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");
const supervisor = @import("../core/supervisor.zig");

pub fn command(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0 or std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h")) {
        _ = try help.writeCommand(stdout, "credentials");
        return exit_codes.success;
    }
    if (!std.mem.eql(u8, argv[0], "check")) {
        try stderr.print("orca credentials: unknown subcommand '{s}'.\n", .{argv[0]});
        return exit_codes.usage;
    }
    if (argv.len > 2) {
        try stderr.writeAll("orca credentials check: expected at most one credential ref.\n");
        return exit_codes.usage;
    }
    return checkCommand(argv[1..], stdout, stderr);
}

fn checkCommand(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const workspace_root = supervisor.resolveWorkspaceRoot(allocator, null, ".") catch try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(workspace_root);
    var loaded_policy = core_api.discoverPolicy(allocator, null, workspace_root) catch |err| {
        try stderr.print("orca credentials check: invalid policy: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer loaded_policy.deinit();

    const ref_name = if (argv.len == 1) argv[0] else null;
    var report = credentials.check(allocator, &loaded_policy.policy, workspace_root, ref_name) catch |err| switch (err) {
        error.UnknownCredentialRef => {
            try stderr.writeAll("orca credentials check: unknown credential ref.\n");
            return exit_codes.general;
        },
        else => {
            try stderr.print("orca credentials check: failed: {s}\n", .{@errorName(err)});
            return exit_codes.general;
        },
    };
    defer report.deinit(allocator);

    if (report.ref_name) |name| {
        try stdout.print("Credential ref: {s}\n", .{name});
    } else {
        try stdout.writeAll("Credential brokers:\n");
    }
    for (report.statuses) |status| {
        try stdout.print("- {s} ({s}): {s} - {s}\n", .{ status.name, status.kind.toString(), status.state.toString(), status.message });
    }
    return if (report.ok()) exit_codes.success else exit_codes.general;
}

test "credentials command rejects unknown subcommand" {
    var stdout_buf: [256]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(&.{"list"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "unknown subcommand") != null);
}
