const std = @import("std");

const aegis_policy = @import("../policy/mod.zig");
const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");

const InitOptions = struct {
    mode: ?[]const u8 = null,
    preset: aegis_policy.presets.AgentPreset = .generic_agent,
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

    const preset_text = aegis_policy.presets.agentPresetText(options.preset);
    try writePolicy(file, preset_text, options.mode);
    const info = aegis_policy.presets.agentPresetInfo(options.preset);
    try stdout.print("Created .aegis/policy.yaml from preset '{s}'.\n", .{info.name});
    if (info.experimental) try stdout.print("Warning: {s}\n", .{info.warning});
    try stdout.writeAll(
        \\Next steps:
        \\  aegis policy check .aegis/policy.yaml
        \\  aegis doctor
        \\  aegis run -- <command>
        \\
    );
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
        } else if (std.mem.eql(u8, arg, "--preset")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("aegis init: --preset requires a preset name.\n");
                return error.Usage;
            }
            const preset = aegis_policy.presets.AgentPreset.parse(argv[index]) orelse {
                try stderr.print("aegis init: unsupported preset '{s}'. Run 'aegis help init' for supported presets.\n", .{argv[index]});
                return error.Usage;
            };
            options.preset = preset;
        } else if (std.mem.eql(u8, arg, "--mode")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("aegis init: --mode requires strict, ask, observe, ci, or trusted.\n");
                return error.Usage;
            }
            const mode = argv[index];
            if (!isValidMode(mode)) {
                try stderr.print("aegis init: unsupported mode '{s}'. Expected strict, ask, observe, ci, or trusted.\n", .{mode});
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
        std.mem.eql(u8, mode, "observe") or
        std.mem.eql(u8, mode, "ci") or
        std.mem.eql(u8, mode, "trusted");
}

fn writePolicy(file: std.fs.File, preset_text: []const u8, mode_override: ?[]const u8) !void {
    var buffer: [1024]u8 = undefined;
    var writer = file.writer(&buffer);
    if (mode_override) |mode| {
        var lines = std.mem.splitScalar(u8, preset_text, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trimLeft(u8, line, " \t");
            if (std.mem.startsWith(u8, trimmed, "mode:")) {
                try writer.interface.print("mode: {s}\n", .{mode});
            } else {
                try writer.interface.writeAll(line);
                try writer.interface.writeByte('\n');
            }
        }
        try writer.interface.flush();
        return;
    }
    try writer.interface.writeAll(preset_text);
    try writer.interface.flush();
}

test "init creates policy and refuses overwrite without force" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(tmp.dir, &.{ "--mode", "strict" }, stdout_stream.writer(), stderr_stream.writer());
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

test "init accepts generic-agent preset alias" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(tmp.dir, &.{ "--preset", "generic-agent", "--force" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "generic-agent") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    const policy = try tmp.dir.readFileAlloc(std.testing.allocator, ".aegis/policy.yaml", 4096);
    defer std.testing.allocator.free(policy);
    try std.testing.expect(std.mem.indexOf(u8, policy, "version: 1") != null);
}

test "init writes requested phase 18 presets as valid policies" {
    const sample_presets = [_][]const u8{ "generic-agent", "github-actions", "strict-local", "trusted-local" };
    for (sample_presets) |preset_name| {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();

        var stdout_buf: [2048]u8 = undefined;
        var stderr_buf: [512]u8 = undefined;
        var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
        var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

        const code = try command(tmp.dir, &.{ "--preset", preset_name, "--force" }, stdout_stream.writer(), stderr_stream.writer());
        try std.testing.expectEqual(exit_codes.success, code);
        try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Next steps:") != null);
        try std.testing.expectEqualStrings("", stderr_stream.getWritten());

        const policy = try tmp.dir.readFileAlloc(std.testing.allocator, ".aegis/policy.yaml", 16 * 1024);
        defer std.testing.allocator.free(policy);
        var loaded = try aegis_policy.load.parseFromSlice(std.testing.allocator, policy, ".aegis/policy.yaml");
        defer loaded.deinit();
        try aegis_policy.validate.policy(&loaded);
    }
}

test "init rejects invalid preset names clearly" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(tmp.dir, &.{ "--preset", "not-real" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "unsupported preset 'not-real'") != null);
}
