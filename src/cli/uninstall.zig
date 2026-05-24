const std = @import("std");

const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");
const plugin = @import("plugin.zig");
const disable = @import("disable.zig");

// ---------------------------------------------------------------------------
// Top-level dispatch
// ---------------------------------------------------------------------------

pub fn command(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var yes = false;
    var plugins_only = false;
    var keep_config = false;

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        const arg = argv[index];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            _ = try help.writeCommand(stdout, "uninstall");
            return exit_codes.success;
        }
        if (std.mem.eql(u8, arg, "--yes")) {
            yes = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--plugins-only")) {
            plugins_only = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--keep-config")) {
            keep_config = true;
            continue;
        }
        try stderr.print("orca uninstall: unknown option '{s}'.\n", .{arg});
        return exit_codes.usage;
    }

    if (!yes) {
        const stdin = std.fs.File.stdin();
        if (stdin.isTty()) {
            if (plugins_only) {
                try stdout.writeAll("Remove all Orca plugins from host agents? [Y/n] ");
            } else if (keep_config) {
                try stdout.writeAll("Uninstall Orca (keep config files)? This removes plugins and the binary. [Y/n] ");
            } else {
                try stdout.writeAll("Fully uninstall Orca (plugins, binary, and config)? [Y/n] ");
            }
            var buf: [8]u8 = undefined;
            const n = try stdin.read(&buf);
            const answer = if (n > 0) std.mem.trimRight(u8, buf[0..n], "\r\n") else "";
            if (answer.len > 0 and (answer[0] == 'n' or answer[0] == 'N')) {
                try stdout.writeAll("canceled\n");
                return exit_codes.success;
            }
        } else {
            try stderr.writeAll("orca uninstall: requires --yes or run interactively.\n");
            return exit_codes.usage;
        }
    }

    try stdout.writeAll("Orca Uninstall\n\n");

    // 1. Disable / remove all plugins
    try stdout.writeAll("Step 1: Removing plugins\n");
    const all_disabled = try disablePlugins(allocator, stdout);

    if (plugins_only) {
        try stdout.writeAll("\nPlugins removed. Orca binary and config remain in place.\n");
        try stdout.writeAll("To fully uninstall later, run: orca uninstall --yes\n");
        return exit_codes.success;
    }

    // 2. Remove binary
    try stdout.writeAll("\nStep 2: Removing Orca binary\n");
    const binary_removed = try removeBinary(allocator, stdout);

    // 3. Remove config and data directories
    if (!keep_config) {
        try stdout.writeAll("\nStep 3: Removing config and data\n");
        try removeConfigAndData(allocator, stdout);
    } else {
        try stdout.writeAll("\nStep 3: Skipping config removal (--keep-config)\n");
    }

    try stdout.writeAll("\nUninstall complete.\n");
    if (!keep_config) {
        try stdout.writeAll("User config removed: ~/.config/orca/\n");
    }

    if (!all_disabled and !binary_removed) {
        try stdout.writeAll("\nNote: no Orca plugins or binary were found.\n");
    }

    try stdout.writeAll(
        \\
        \\Manual cleanup may still be needed:
        \\  - Remove ~/.local/bin/orca from your PATH if it was added by the installer.
        \\  - Review and remove any local .orca/ directories in project workspaces.
        \\
    );
    return exit_codes.success;
}

// ---------------------------------------------------------------------------
// Plugin removal (delegates to disable.zig)
// ---------------------------------------------------------------------------

fn disablePlugins(allocator: std.mem.Allocator, stdout: anytype) !bool {
    var any_action = false;

    any_action = try disable.disableOpenCode(allocator, stdout) or any_action;
    any_action = try disable.disableOpenClaw(allocator, stdout) or any_action;
    any_action = try disable.disableHermes(allocator, stdout) or any_action;
    any_action = try disable.disableCodex(allocator, stdout) or any_action;
    any_action = try disable.disableClaude(allocator, stdout) or any_action;

    return any_action;
}

// ---------------------------------------------------------------------------
// Binary removal — only known safe locations, no PATH traversal
// ---------------------------------------------------------------------------

fn removeBinary(allocator: std.mem.Allocator, stdout: anytype) !bool {
    const self_exe = std.fs.selfExePathAlloc(allocator) catch |err| {
        try stdout.print("  could not determine self path: {s}\n", .{@errorName(err)});
        return false;
    };
    defer allocator.free(self_exe);

    var removed_any = false;

    if (plugin.fileExistsAbsolute(self_exe)) {
        blk: {
            std.fs.cwd().deleteFile(self_exe) catch |err| {
                try stdout.print("  binary: failed to remove {s}: {s}\n", .{ self_exe, @errorName(err) });
                break :blk;
            };
            try stdout.print("  removed: {s}\n", .{self_exe});
            removed_any = true;
        }
    }

    const home = std.process.getEnvVarOwned(allocator, "HOME") catch null;
    if (home) |h| {
        defer allocator.free(h);
        const local_bin = try std.fs.path.join(allocator, &.{ h, ".local", "bin", "orca" });
        defer allocator.free(local_bin);
        if (!std.mem.eql(u8, self_exe, local_bin) and plugin.fileExistsAbsolute(local_bin)) {
            blk: {
                std.fs.cwd().deleteFile(local_bin) catch |err| {
                    try stdout.print("  binary: failed to remove {s}: {s}\n", .{ local_bin, @errorName(err) });
                    break :blk;
                };
                try stdout.print("  removed: {s}\n", .{local_bin});
                removed_any = true;
            }
        }
    }

    if (!removed_any) {
        try stdout.writeAll("  no Orca binary found in known locations\n");
    }
    return removed_any;
}

// ---------------------------------------------------------------------------
// Config and data removal
// ---------------------------------------------------------------------------

fn removeConfigAndData(allocator: std.mem.Allocator, stdout: anytype) !void {
    // User config dir: ~/.config/orca/ or $XDG_CONFIG_HOME/orca/
    const config_dir = blk: {
        if (std.process.getEnvVarOwned(allocator, "XDG_CONFIG_HOME")) |xdg| {
            defer allocator.free(xdg);
            break :blk std.fs.path.join(allocator, &.{ xdg, "orca" }) catch null;
        } else |_| {}
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch break :blk null;
        defer allocator.free(home);
        break :blk std.fs.path.join(allocator, &.{ home, ".config", "orca" }) catch null;
    };
    defer if (config_dir) |p| allocator.free(p);

    if (config_dir) |cd| {
        if (plugin.dirExists(cd)) {
            blk: {
                std.fs.cwd().deleteTree(cd) catch |err| {
                    try stdout.print("  failed to remove config dir {s}: {s}\n", .{ cd, @errorName(err) });
                    break :blk;
                };
                try stdout.print("  removed: {s}\n", .{cd});
            }
        }
    }

    // Legacy user data dir ~/.orca
    const legacy_dir = blk: {
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch break :blk null;
        defer allocator.free(home);
        break :blk std.fs.path.join(allocator, &.{ home, ".orca" }) catch null;
    };
    defer if (legacy_dir) |p| allocator.free(p);

    if (legacy_dir) |ld| {
        if (plugin.dirExists(ld)) {
            blk: {
                std.fs.cwd().deleteTree(ld) catch |err| {
                    try stdout.print("  failed to remove legacy dir {s}: {s}\n", .{ ld, @errorName(err) });
                    break :blk;
                };
                try stdout.print("  removed: {s}\n", .{ld});
            }
        }
    }

    try stdout.writeAll("\nNote: local workspace .orca/ directories were not removed.\n");
    try stdout.writeAll("      Run 'find . -type d -name .orca' to locate and remove them manually.\n");
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "uninstall command help and invalid args" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const help_code = try command(&.{"--help"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, help_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "uninstall") != null);

    stdout_stream.reset();
    stderr_stream.reset();
    const bad_code = try command(&.{"--unknown"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, bad_code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "unknown option") != null);
}

test "uninstall without --yes in non-TTY returns usage" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(&.{}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "--yes") != null);
}

test "uninstall --plugins-only requires --yes in non-TTY" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(&.{"--plugins-only"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "--yes") != null);
}
