const std = @import("std");

const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");
const plugin = @import("plugin.zig");

// ---------------------------------------------------------------------------
// Top-level dispatch
// ---------------------------------------------------------------------------

const DisableTarget = enum { codex, claude, opencode, openclaw, hermes, all };

pub fn command(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var target: DisableTarget = .all;
    var yes = false;

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        const arg = argv[index];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            _ = try help.writeCommand(stdout, "disable");
            return exit_codes.success;
        }
        if (std.mem.eql(u8, arg, "--yes")) {
            yes = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "codex")) {
            target = .codex;
            continue;
        }
        if (std.mem.eql(u8, arg, "claude")) {
            target = .claude;
            continue;
        }
        if (std.mem.eql(u8, arg, "opencode")) {
            target = .opencode;
            continue;
        }
        if (std.mem.eql(u8, arg, "openclaw")) {
            target = .openclaw;
            continue;
        }
        if (std.mem.eql(u8, arg, "hermes") or std.mem.eql(u8, arg, "hermess")) {
            target = .hermes;
            continue;
        }
        if (std.mem.eql(u8, arg, "all")) {
            target = .all;
            continue;
        }
        try stderr.print("orca disable: unknown option '{s}'.\n", .{arg});
        return exit_codes.usage;
    }

    if (!yes) {
        const stdin = std.fs.File.stdin();
        if (stdin.isTty()) {
            const host_label = if (target == .all) "all" else @tagName(target);
            try stdout.print("Disable Orca for {s}? This removes plugin registrations from host agents. [Y/n] ", .{host_label});
            var buf: [8]u8 = undefined;
            const n = try stdin.read(&buf);
            const answer = if (n > 0) std.mem.trimRight(u8, buf[0..n], "\r\n") else "";
            if (answer.len > 0 and (answer[0] == 'n' or answer[0] == 'N')) {
                try stdout.writeAll("canceled\n");
                return exit_codes.success;
            }
        } else {
            try stderr.writeAll("orca disable: requires --yes or run interactively.\n");
            return exit_codes.usage;
        }
    }

    try stdout.writeAll("Orca Disable\n\n");

    const targets = switch (target) {
        .codex => &[_]DisableTarget{.codex},
        .claude => &[_]DisableTarget{.claude},
        .opencode => &[_]DisableTarget{.opencode},
        .openclaw => &[_]DisableTarget{.openclaw},
        .hermes => &[_]DisableTarget{.hermes},
        .all => &[_]DisableTarget{ .codex, .claude, .opencode, .openclaw, .hermes },
    };

    var any_action = false;
    for (targets) |t| {
        try stdout.print("Host: {s}\n", .{@tagName(t)});
        const did_disable = switch (t) {
            .opencode => try disableOpenCode(allocator, stdout),
            .openclaw => try disableOpenClaw(allocator, stdout),
            .hermes => try disableHermes(allocator, stdout),
            .codex => try disableCodex(allocator, stdout),
            .claude => try disableClaude(allocator, stdout),
            .all => unreachable,
        };
        if (did_disable) {
            any_action = true;
        } else if (t != .openclaw) {
            // openclaw already prints its own status
            try stdout.print("  status: no {s} Orca plugin found\n", .{@tagName(t)});
        }
    }

    try stdout.writeAll("\n");
    if (any_action) {
        try stdout.writeAll("Orca plugins have been disabled.\n");
        try stdout.writeAll("Orca binary and policy files remain in place.\n");
        try stdout.writeAll("Re-enable with: orca setup (guided) or orca plugin install <host>\n");
    } else {
        try stdout.writeAll("No Orca plugins were found to disable.\n");
    }
    return exit_codes.success;
}

// ---------------------------------------------------------------------------
// Per-host disable functions (pub so uninstall.zig can delegate)
// ---------------------------------------------------------------------------

pub fn disableOpenCode(allocator: std.mem.Allocator, stdout: anytype) !bool {
    var removed = false;
    const project_path = try std.fs.path.join(allocator, &.{ ".opencode", "plugins", "orca.ts" });
    defer allocator.free(project_path);
    const global_path = blk: {
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch break :blk null;
        defer allocator.free(home);
        break :blk try std.fs.path.join(allocator, &.{ home, ".config", "opencode", "plugins", "orca.ts" });
    };
    defer if (global_path) |p| allocator.free(p);

    if (plugin.fileExistsAbsolute(project_path)) {
        blk: {
            std.fs.cwd().deleteFile(project_path) catch |err| {
                try stdout.print("  project plugin: failed to remove ({s})\n", .{@errorName(err)});
                break :blk;
            };
            try stdout.writeAll("  project plugin: removed (.opencode/plugins/orca.ts)\n");
            removed = true;
        }
    }
    if (global_path) |gp| {
        if (plugin.fileExistsAbsolute(gp)) {
            blk: {
                std.fs.cwd().deleteFile(gp) catch |err| {
                    try stdout.print("  global plugin: failed to remove ({s})\n", .{@errorName(err)});
                    break :blk;
                };
                try stdout.writeAll("  global plugin: removed (~/.config/opencode/plugins/orca.ts)\n");
                removed = true;
            }
        }
    }
    return removed;
}

pub fn disableOpenClaw(allocator: std.mem.Allocator, stdout: anytype) !bool {
    if (plugin.binaryInPath(allocator, "openclaw")) {
        const status = runOpenClawUninstall(allocator) catch |err| blk: {
            try stdout.print("  host uninstall: failed ({s})\n", .{@errorName(err)});
            break :blk 1;
        };
        if (status == 0) {
            try stdout.writeAll("  host uninstall: removed via openclaw plugins uninstall\n");
            return true;
        } else {
            try stdout.print("  host uninstall: openclaw exited with code {d}\n", .{status});
            return false;
        }
    }
    try stdout.writeAll("  status: openclaw binary not found in PATH\n");
    return false;
}

pub fn disableHermes(allocator: std.mem.Allocator, stdout: anytype) !bool {
    var disabled = false;
    if (plugin.binaryInPath(allocator, "hermes")) {
        const status = runHermesDisable(allocator) catch |err| blk: {
            try stdout.print("  host disable: failed ({s})\n", .{@errorName(err)});
            break :blk 1;
        };
        if (status == 0) {
            try stdout.writeAll("  host disable: hermes plugins disable orca\n");
            disabled = true;
        } else {
            try stdout.print("  host disable: hermes exited with code {d}\n", .{status});
        }
    }
    const user_root = try plugin.hermesUserPluginRoot(allocator);
    defer allocator.free(user_root);
    if (plugin.dirExists(user_root)) {
        blk: {
            std.fs.cwd().deleteTree(user_root) catch |err| {
                try stdout.print("  plugin files: failed to remove ({s})\n", .{@errorName(err)});
                break :blk;
            };
            try stdout.print("  plugin files: removed {s}\n", .{user_root});
            disabled = true;
        }
    }
    return disabled;
}

pub fn disableCodex(allocator: std.mem.Allocator, stdout: anytype) !bool {
    return try removeKnownPluginPaths(allocator, stdout, "codex", &[_][]const u8{
        ".agents/plugins/orca",
        ".codex/plugins/orca",
    });
}

pub fn disableClaude(allocator: std.mem.Allocator, stdout: anytype) !bool {
    return try removeKnownPluginPaths(allocator, stdout, "claude", &[_][]const u8{
        ".claude/plugins/orca",
    });
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

pub fn runOpenClawUninstall(allocator: std.mem.Allocator) !u8 {
    const argv = [_][]const u8{ "openclaw", "plugins", "uninstall", "orca-openclaw-plugin" };
    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    const term = try child.spawnAndWait();
    return switch (term) {
        .Exited => |code| @as(u8, @intCast(@min(code, 255))),
        else => 255,
    };
}

pub fn runHermesDisable(allocator: std.mem.Allocator) !u8 {
    const argv = [_][]const u8{ "hermes", "plugins", "disable", "orca" };
    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    const term = try child.spawnAndWait();
    return switch (term) {
        .Exited => |code| @as(u8, @intCast(@min(code, 255))),
        else => 255,
    };
}

pub fn removeKnownPluginPaths(allocator: std.mem.Allocator, stdout: anytype, host_name: []const u8, paths: []const []const u8) !bool {
    var removed_any = false;
    for (paths) |rel_path| {
        if (plugin.fileExistsAbsolute(rel_path)) {
            std.fs.cwd().deleteFile(rel_path) catch |err| {
                try stdout.print("  {s} plugin: failed to remove {s} ({s})\n", .{ host_name, rel_path, @errorName(err) });
                continue;
            };
            try stdout.print("  {s} plugin: removed {s}\n", .{ host_name, rel_path });
            removed_any = true;
        }
        if (plugin.dirExists(rel_path)) {
            std.fs.cwd().deleteTree(rel_path) catch |err| {
                try stdout.print("  {s} plugin: failed to remove {s} ({s})\n", .{ host_name, rel_path, @errorName(err) });
                continue;
            };
            try stdout.print("  {s} plugin: removed {s}\n", .{ host_name, rel_path });
            removed_any = true;
        }
    }
    _ = allocator;
    return removed_any;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "disable command help and invalid args" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const help_code = try command(&.{"--help"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, help_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "disable") != null);

    stdout_stream.reset();
    stderr_stream.reset();
    const bad_code = try command(&.{"--unknown"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, bad_code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "unknown option") != null);
}

test "disable without --yes in non-TTY returns usage" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(&.{"all"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "--yes") != null);
}
