const std = @import("std");
const core = @import("../core/mod.zig");
const intercept = @import("../intercept/mod.zig");
const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");

pub fn command(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    const options = parseOptions(argv, stdout, stderr) catch |err| switch (err) {
        error.HelpShown => return exit_codes.success,
        error.Usage => return exit_codes.usage,
        else => return err,
    };

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const workspace_root = try core.supervisor.resolveWorkspaceRoot(allocator, null, ".");
    defer allocator.free(workspace_root);
    const session_id = intercept.files.resolveSessionId(allocator, workspace_root, options.session) catch |err| {
        try stderr.print("aegis diff: failed to resolve session '{s}': {s}\n", .{ options.session, @errorName(err) });
        return exit_codes.general;
    };
    defer allocator.free(session_id);
    const diff = intercept.files.diffStaged(allocator, workspace_root, session_id, options.file) catch |err| {
        try stderr.print("aegis diff: failed to diff staged files: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer allocator.free(diff);
    try stdout.writeAll(diff);
    return exit_codes.success;
}

const Options = struct {
    session: []const u8 = "last",
    file: ?[]const u8 = null,
};

fn parseOptions(argv: []const []const u8, stdout: anytype, stderr: anytype) !Options {
    var options: Options = .{};
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        const arg = argv[index];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            _ = try help.writeCommand(stdout, "diff");
            return error.HelpShown;
        } else if (std.mem.eql(u8, arg, "--session")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("aegis diff: --session requires an id or 'last'.\n");
                return error.Usage;
            }
            options.session = argv[index];
        } else if (std.mem.eql(u8, arg, "--file")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("aegis diff: --file requires a workspace path.\n");
                return error.Usage;
            }
            options.file = argv[index];
        } else {
            try stderr.print("aegis diff: unknown option '{s}'.\n", .{arg});
            return error.Usage;
        }
    }
    return options;
}
