const std = @import("std");

const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");

const InitOptions = struct {
    mode: []const u8 = "ask",
    force: bool = false,
};

pub fn command(cwd: std.fs.Dir, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    const options = parseOptions(argv, stdout, stderr) catch |err| switch (err) {
        error.HelpShown => return exit_codes.success,
        error.Usage => return exit_codes.usage,
        else => return err,
    };

    cwd.makePath(".aegis") catch |err| {
        try stderr.print("aegis init: failed to create .aegis: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };

    const flags: std.fs.File.CreateFlags = if (options.force) .{} else .{ .exclusive = true };
    const file = cwd.createFile(".aegis/policy.yaml", flags) catch |err| switch (err) {
        error.PathAlreadyExists => {
            try stderr.writeAll("aegis init: .aegis/policy.yaml already exists; use --force to overwrite.\n");
            return exit_codes.general;
        },
        else => {
            try stderr.print("aegis init: failed to write .aegis/policy.yaml: {s}\n", .{@errorName(err)});
            return exit_codes.general;
        },
    };
    defer file.close();

    try writePolicy(file, options.mode);
    try stdout.print("Created .aegis/policy.yaml with mode '{s}'.\n", .{options.mode});
    return exit_codes.success;
}

fn parseOptions(argv: []const []const u8, stdout: anytype, stderr: anytype) !InitOptions {
    var options: InitOptions = .{};
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        const arg = argv[index];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            _ = try help.writeCommand(stdout, "init");
            return error.HelpShown;
        } else if (std.mem.eql(u8, arg, "--force")) {
            options.force = true;
        } else if (std.mem.eql(u8, arg, "--ci")) {
            options.mode = "ci";
        } else if (std.mem.eql(u8, arg, "--mode")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("aegis init: --mode requires strict, ask, or observe.\n");
                return error.Usage;
            }
            const mode = argv[index];
            if (!isValidMode(mode)) {
                try stderr.print("aegis init: unsupported mode '{s}'. Expected strict, ask, or observe.\n", .{mode});
                return error.Usage;
            }
            options.mode = mode;
        } else {
            try stderr.print("aegis init: unknown option '{s}'.\n", .{arg});
            return error.Usage;
        }
    }
    return options;
}

fn isValidMode(mode: []const u8) bool {
    return std.mem.eql(u8, mode, "strict") or
        std.mem.eql(u8, mode, "ask") or
        std.mem.eql(u8, mode, "observe");
}

fn writePolicy(file: std.fs.File, mode: []const u8) !void {
    var buffer: [1024]u8 = undefined;
    const policy = try std.fmt.bufPrint(&buffer,
        \\version: 1
        \\mode: {s}
        \\
        \\env:
        \\  default: redact
        \\files:
        \\  default: ask
        \\commands:
        \\  default: ask
        \\network:
        \\  default: ask
        \\mcp:
        \\  default: ask
        \\audit:
        \\  enabled: true
        \\
    , .{mode});
    try file.writeAll(policy);
}

test "init creates policy and refuses overwrite without force" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(tmp.dir, &.{"--mode", "strict"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const policy = try tmp.dir.readFileAlloc(std.testing.allocator, ".aegis/policy.yaml", 4096);
    defer std.testing.allocator.free(policy);
    try std.testing.expect(std.mem.indexOf(u8, policy, "version: 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, policy, "mode: strict") != null);

    stdout_stream.reset();
    stderr_stream.reset();
    const second_code = try command(tmp.dir, &.{}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.general, second_code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "already exists") != null);
}

test "init force overwrites existing policy" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath(".aegis");
    {
        const existing = try tmp.dir.createFile(".aegis/policy.yaml", .{});
        defer existing.close();
        try existing.writeAll("old\n");
    }

    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(tmp.dir, &.{ "--mode", "observe", "--force" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    const policy = try tmp.dir.readFileAlloc(std.testing.allocator, ".aegis/policy.yaml", 4096);
    defer std.testing.allocator.free(policy);
    try std.testing.expect(std.mem.indexOf(u8, policy, "mode: observe") != null);
}
