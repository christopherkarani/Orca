const std = @import("std");

const ci_check = @import("../ci_check.zig");
const supervisor = @import("../core/supervisor.zig");
const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");

const Format = enum { text, markdown, json };
const Options = struct { format: Format = .text, github_summary: ?[]const u8 = null };

pub fn command(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0 or std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h")) {
        _ = try help.writeCommand(stdout, "ci");
        return if (argv.len == 0) exit_codes.usage else exit_codes.success;
    }
    if (!std.mem.eql(u8, argv[0], "check")) {
        try stderr.print("orca ci: unknown subcommand '{s}'. Expected check.\n", .{argv[0]});
        return exit_codes.usage;
    }
    const options = parseOptions(argv[1..], stderr) catch |err| switch (err) {
        error.Usage => return exit_codes.usage,
        else => return err,
    };
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    const workspace_root = supervisor.resolveWorkspaceRoot(allocator, null, ".") catch try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(workspace_root);
    var result = try ci_check.run(allocator, workspace_root);
    defer result.deinit();
    switch (options.format) {
        .text, .markdown => try ci_check.writeMarkdown(stdout, result),
        .json => try ci_check.writeJson(stdout, result),
    }
    if (options.github_summary orelse std.process.getEnvVarOwned(allocator, "GITHUB_STEP_SUMMARY") catch null) |summary_path| {
        defer if (options.github_summary == null) allocator.free(summary_path);
        const file = try std.fs.cwd().createFile(summary_path, .{ .truncate = false });
        defer file.close();
        try file.seekFromEnd(0);
        var buf: [4096]u8 = undefined;
        var file_writer = file.writer(&buf);
        try ci_check.writeMarkdown(&file_writer.interface, result);
        try file_writer.interface.flush();
    }
    return if (result.ok()) exit_codes.success else exit_codes.general;
}

fn parseOptions(argv: []const []const u8, stderr: anytype) !Options {
    var options: Options = .{};
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        const arg = argv[index];
        if (std.mem.eql(u8, arg, "--format")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("orca ci check: --format requires markdown or json.\n");
                return error.Usage;
            }
            if (std.mem.eql(u8, argv[index], "markdown")) options.format = .markdown else if (std.mem.eql(u8, argv[index], "json")) options.format = .json else {
                try stderr.writeAll("orca ci check: --format supports markdown or json.\n");
                return error.Usage;
            }
        } else if (std.mem.eql(u8, arg, "--github-summary")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("orca ci check: --github-summary requires a path.\n");
                return error.Usage;
            }
            options.github_summary = argv[index];
        } else {
            try stderr.print("orca ci check: unknown option '{s}'.\n", .{arg});
            return error.Usage;
        }
    }
    return options;
}

test "ci command rejects unknown subcommands" {
    var stdout_buf: [256]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    const code = try command(&.{"bad"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, code);
}
