const std = @import("std");

const redteam = @import("../redteam/mod.zig");
const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");

const Options = struct {
    root: []const u8 = "fixtures",
    json: bool = false,
    ci: bool = false,
    fixture_id: ?[]const u8 = null,
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

    var fixture_set = redteam.fixtures.discover(allocator, options.root, options.fixture_id) catch |err| {
        try stderr.print("orca redteam: failed to discover fixtures: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer fixture_set.deinit();
    if (fixture_set.fixtures.len == 0) {
        if (options.fixture_id) |id| {
            try stderr.print("orca redteam: fixture not found: {s}\n", .{id});
        } else {
            try stderr.print("orca redteam: no fixtures found under {s}\n", .{options.root});
        }
        return exit_codes.general;
    }

    var suite = redteam.runner.runSuite(allocator, fixture_set, .{ .ci = options.ci }) catch |err| {
        try stderr.print("orca redteam: fixture run failed: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer suite.deinit();

    if (options.json) {
        try redteam.reports.writeJson(stdout, suite);
    } else {
        try redteam.reports.writeHuman(stdout, suite);
    }

    if (options.ci and !suite.allRequiredPassed()) return exit_codes.redteam_failure;
    return exit_codes.success;
}

fn parseOptions(argv: []const []const u8, stdout: anytype, stderr: anytype) !Options {
    var options: Options = .{};
    var saw_path = false;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        const arg = argv[index];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            _ = try help.writeCommand(stdout, "redteam");
            return error.HelpShown;
        } else if (std.mem.eql(u8, arg, "--json")) {
            options.json = true;
        } else if (std.mem.eql(u8, arg, "--ci")) {
            options.ci = true;
        } else if (std.mem.eql(u8, arg, "--fixture")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("orca redteam: --fixture requires a fixture id.\n");
                return error.Usage;
            }
            options.fixture_id = argv[index];
        } else if (std.mem.startsWith(u8, arg, "-")) {
            try stderr.print("orca redteam: unknown option '{s}'.\n", .{arg});
            return error.Usage;
        } else {
            if (saw_path) {
                try stderr.writeAll("orca redteam: expected at most one fixture path.\n");
                return error.Usage;
            }
            options.root = arg;
            saw_path = true;
        }
    }
    return options;
}

test "redteam command rejects unknown options" {
    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(&.{"--bad"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "unknown option") != null);
}

test "redteam ci exits nonzero on failing fixture" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("fixtures/secret-exfil/fail");
    {
        const file = try tmp.dir.createFile("fixtures/secret-exfil/fail/fixture.yaml", .{});
        defer file.close();
        try file.writeAll(
            \\version: 1
            \\id: failing
            \\name: Failing fixture
            \\category: secret-exfil
            \\description: Expected block does not match attempt.
            \\mode: strict
            \\command:
            \\  argv:
            \\    - "./fixture-agent"
            \\attempts:
            \\  - "file.read:.env"
            \\expected:
            \\  blocked:
            \\    - "file.read:README.md"
            \\score:
            \\  points: 1
            \\
        );
    }
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, "fixtures");
    defer std.testing.allocator.free(root);
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(&.{ root, "--ci" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.redteam_failure, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Orca Redteam Score") != null);
}
