const std = @import("std");
const build_options = @import("build_options");

pub const args = @import("args.zig");
pub const exit_codes = @import("exit_codes.zig");
pub const help = @import("help.zig");
pub const run_command = @import("run.zig");
pub const init = @import("init.zig");
pub const doctor = @import("doctor.zig");
pub const policy = @import("policy.zig");
pub const credentials_command = @import("credentials.zig");
pub const replay = @import("replay.zig");
pub const diff = @import("diff.zig");
pub const apply = @import("apply.zig");
pub const discard = @import("discard.zig");
pub const mcp = @import("mcp.zig");
pub const redteam = @import("redteam.zig");
pub const completions = @import("completions.zig");
pub const shim = @import("shim.zig");
pub const version_command = @import("version.zig");
pub const plugin = @import("plugin.zig");
pub const plugin_install = @import("plugin_install.zig");
pub const setup = @import("setup.zig");
pub const decide = @import("decide.zig");
pub const hook = @import("hook.zig");
pub const dashboard_command = @import("dashboard.zig");
pub const report = @import("report.zig");
pub const license_command = @import("license.zig");
pub const ci = @import("ci.zig");
pub const demo = @import("demo.zig");
pub const disable = @import("disable.zig");
pub const uninstall = @import("uninstall.zig");
pub const interactive = @import("interactive.zig");

pub const version = build_options.version;

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
            try stderr.writeAll("orca help: expected at most one command.\n");
            return exit_codes.usage;
        }
        if (!try help.writeCommand(stdout, argv[1])) {
            try stderr.print("orca help: unknown command '{s}'.\n", .{argv[1]});
            return exit_codes.usage;
        }
        return exit_codes.success;
    }

    if (std.mem.eql(u8, command, "version") or std.mem.eql(u8, command, "--version")) {
        if (argv.len > 2) {
            try stderr.writeAll("orca version: expected at most one argument. Run 'orca help version' for usage.\n");
            return exit_codes.usage;
        }
        if (argv.len == 2) {
            if (std.mem.eql(u8, argv[1], "--help") or std.mem.eql(u8, argv[1], "-h")) {
                _ = try help.writeCommand(stdout, "version");
                return exit_codes.success;
            }
            if (std.mem.eql(u8, argv[1], "--json")) {
                try version_command.writeJson(stdout, version_command.current());
                return exit_codes.success;
            }
            try stderr.writeAll("orca version: unsupported argument. Run 'orca help version' for usage.\n");
            return exit_codes.usage;
        }
        try version_command.writePlain(stdout, version_command.current());
        return exit_codes.success;
    }

    // Highest-value DX helper for installers, Homebrew post-install hooks, npm wrapper,
    // and users who want a reliable way to get the activation exports (see install.sh + doctor).
    if (std.mem.eql(u8, command, "--print-install-env")) {
        try stdout.writeAll("export PATH=\"$HOME/.local/bin:$PATH\"\n");
        try stdout.writeAll("export ORCA_RESOURCE_ROOT=\"$HOME/.local/share/orca/current\"\n");
        return exit_codes.success;
    }

    if (std.mem.eql(u8, command, "run")) return run_command.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "init")) return init.command(cwd, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "doctor")) return doctor.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "policy")) return policy.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "credentials")) return credentials_command.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "replay")) return replay.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "diff")) return diff.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "apply")) return apply.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "discard")) return discard.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "mcp")) return mcp.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "redteam")) return redteam.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "completions")) return completions.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "shim")) return shim.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "plugin")) return plugin.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "setup")) return setup.command(cwd, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "decide")) return decide.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "hook")) return hook.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "dashboard")) return dashboard_command.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "report")) return report.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "license")) return license_command.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "ci")) return ci.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "demo")) return demo.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "disable")) return disable.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "uninstall")) return uninstall.command(argv[1..], stdout, stderr);
    try stderr.writeAll("orca: unknown command '");
    try stderr.writeAll(command);
    try stderr.writeAll(". Run 'orca help' for usage.\n");
    return exit_codes.usage;
}

test "help flag prints command summary" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try run(&.{"--help"}, stdout_stream.writer(), stderr_stream.writer());

    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Orca") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Commands:") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Commands:\n  run") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "command-specific help works through help command and command flag" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try run(&.{ "help", "run" }, stdout_stream.writer(), stderr_stream.writer());

    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "orca run") != null);
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
    try std.testing.expect(std.mem.startsWith(u8, stdout_stream.getWritten(), "orca "));
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), version) != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "version supports json, help, and rejects extra arguments" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const help_code = try run(&.{ "version", "--help" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, help_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "orca version") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    stdout_stream.reset();
    stderr_stream.reset();
    const json_code = try run(&.{ "version", "--json" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, json_code);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, stdout_stream.getWritten(), .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings(version, parsed.value.object.get("version").?.string);
    try std.testing.expect(parsed.value.object.get("commit") != null);
    try std.testing.expect(parsed.value.object.get("target") != null);
    try std.testing.expect(parsed.value.object.get("build_date") != null);

    stdout_stream.reset();
    stderr_stream.reset();
    const invalid_code = try run(&.{ "version", "typo" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, invalid_code);
    try std.testing.expectEqualStrings("", stdout_stream.getWritten());
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "unsupported argument") != null);
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

    const policy_text = try tmp.dir.readFileAlloc(std.testing.allocator, ".orca/policy.yaml", 4096);
    defer std.testing.allocator.free(policy_text);
    try std.testing.expect(std.mem.indexOf(u8, policy_text, "mode: strict") != null);
}

test "doctor dispatch prints platform capabilities" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try run(&.{"doctor"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Capabilities:") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "network policy engine: active") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "completions dispatch prints shell script" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try run(&.{ "completions", "bash" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "complete -F") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Orca session started") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Orca session ended: exit code 0") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

// ---------------------------------------------------------------------------
// Phase 3 TDD tests: messaging and help text updates for guided onboarding
// These tests are written FIRST (RED). They will fail until help text is updated
// to describe the new default guided behavior and de-emphasize --yes.
// ---------------------------------------------------------------------------

test "setup help describes guided interactive default on TTY and de-emphasizes --auto for primary path" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try run(&.{ "help", "setup" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    // New Phase 3 messaging: guided is default on interactive terminals
    try std.testing.expect(std.mem.indexOf(u8, output, "guided") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "interactive") != null or std.mem.indexOf(u8, output, "TTY") != null or std.mem.indexOf(u8, output, "terminal") != null);
    // Still documents the non-interactive escape hatch
    try std.testing.expect(std.mem.indexOf(u8, output, "--auto") != null or std.mem.indexOf(u8, output, "non-interactive") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin help and disable re-enable messaging de-emphasize --yes in favor of setup" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try run(&.{ "help", "plugin" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    // Phase 3: primary onboarding path is `orca setup`; --yes remains for scripts
    try std.testing.expect(std.mem.indexOf(u8, output, "setup") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "guided") != null or std.mem.indexOf(u8, output, "interactive") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}
