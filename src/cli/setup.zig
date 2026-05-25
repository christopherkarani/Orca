const std = @import("std");

const supervisor = @import("../core/supervisor.zig");
const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");
const init = @import("init.zig");
const plugin = @import("plugin.zig");

pub fn command(cwd: std.fs.Dir, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var auto = false;
    var preset: []const u8 = "generic-agent";

    if (argv.len == 0) {
        _ = try help.writeCommand(stdout, "setup");
        return exit_codes.success;
    }

    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        const arg = argv[index];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            _ = try help.writeCommand(stdout, "setup");
            return exit_codes.success;
        }
        if (std.mem.eql(u8, arg, "--auto")) {
            auto = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--yes")) {
            auto = true; // alias for --auto
            continue;
        }
        if (std.mem.eql(u8, arg, "--preset")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("orca setup: --preset requires a preset name.\n");
                return exit_codes.usage;
            }
            preset = argv[index];
            continue;
        }
        try stderr.print("orca setup: unknown option '{s}'.\n", .{arg});
        return exit_codes.usage;
    }

    if (!auto) {
        _ = try help.writeCommand(stdout, "setup");
        return exit_codes.success;
    }

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const self_exe = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(self_exe);

    const workspace_root = supervisor.resolveWorkspaceRoot(allocator, null, ".") catch try allocator.dupe(u8, ".");
    defer allocator.free(workspace_root);

    // 1. Policy init if missing
    const policy_path = try std.fs.path.join(allocator, &.{ workspace_root, ".orca", "policy.yaml" });
    defer allocator.free(policy_path);

    if (!plugin.fileExistsAbsolute(policy_path)) {
        try stdout.writeAll("Policy not found. Initializing...\n");
        const init_argv = &[_][]const u8{ "--preset", preset, "--quiet" };
        const code = init.command(cwd, init_argv, stdout, stderr) catch |err| {
            try stderr.print("orca setup: policy init failed: {s}\n", .{@errorName(err)});
            return exit_codes.general;
        };
        if (code != exit_codes.success) return code;
        try stdout.writeAll("Policy initialized.\n");
    } else {
        try stdout.writeAll("Policy already exists.\n");
    }

    // 2. Detect hosts — collect doctor report once, reuse per host
    const hosts = &[_][]const u8{ "codex", "claude", "opencode", "openclaw", "hermes" };
    var doctor_report = try plugin.collectPluginDoctorReport(allocator);
    defer plugin.deinitPluginDoctorReport(&doctor_report, allocator);

    var any_detected = false;
    var failure_count: usize = 0;

    for (hosts) |host_name| {
        if (!plugin.binaryInPath(allocator, host_name)) continue;
        any_detected = true;
        try stdout.print("\nDetected host: {s}\n", .{host_name});

        const installed = plugin.hostPluginInstalledFromReport(host_name, doctor_report);

        if (installed) {
            try stdout.print("  {s}: plugin already installed\n", .{host_name});
        } else {
            try stdout.print("  {s}: plugin not installed. Installing...\n", .{host_name});
            const install_argv = &[_][]const u8{ self_exe, "plugin", "install", host_name, "--yes" };
            const install_code = runChild(allocator, install_argv);
            if (install_code) |code| {
                if (code != 0) {
                    try stdout.print("  {s}: install failed (exit code {d})\n", .{ host_name, code });
                    failure_count += 1;
                    continue;
                }
                try stdout.print("  {s}: install succeeded\n", .{host_name});
            } else |err| {
                try stdout.print("  {s}: install error ({s})\n", .{ host_name, @errorName(err) });
                failure_count += 1;
                continue;
            }

            plugin.deinitPluginDoctorReport(&doctor_report, allocator);
            doctor_report = try plugin.collectPluginDoctorReport(allocator);
        }

        // Smoke test (Hermes only for now using bundled fixtures)
        if (std.mem.eql(u8, host_name, "hermes")) {
            const safe_fixture = "tests/fixtures/hook-safe.json";
            const danger_fixture = "tests/fixtures/hook-danger.json";
            const safe_result = plugin.smokeTestHook(allocator, "hermes", "pre_tool_call", safe_fixture, "allow") catch plugin.SmokeResult{ .passed = false };
            const danger_result = plugin.smokeTestHook(allocator, "hermes", "pre_tool_call", danger_fixture, "block") catch plugin.SmokeResult{ .passed = false };
            const safe_ok = safe_result.passed;
            const danger_ok = danger_result.passed;
            if (safe_ok and danger_ok) {
                try stdout.print("  {s}: smoke test PASSED\n", .{host_name});
            } else {
                try stdout.print("  {s}: smoke test FAILED (safe={s}, danger={s})\n", .{ host_name, if (safe_ok) "pass" else "fail", if (danger_ok) "pass" else "fail" });
                failure_count += 1;
            }
        } else {
            try stdout.print("  {s}: smoke test skipped\n", .{host_name});
        }
    }

    if (!any_detected) {
        try stdout.writeAll("\nNo agent hosts detected in PATH.\n");
        try stdout.writeAll("Install a supported host and run 'orca setup --auto' again.\n");
    }

    if (failure_count > 0) {
        try stdout.print("\nSetup finished with {d} failure(s).\n", .{failure_count});
        try stdout.writeAll("Review the messages above and re-run 'orca setup --auto' after fixing blockers.\n");
        return exit_codes.general;
    }

    try stdout.writeAll("\nSetup complete.\n");
    try stdout.writeAll("Run 'orca run -- <command>' to start a protected session.\n");
    return exit_codes.success;
}

fn runChild(allocator: std.mem.Allocator, argv: []const []const u8) !u8 {
    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    const term = try child.spawnAndWait();
    return switch (term) {
        .Exited => |code| @as(u8, @intCast(@min(code, 255))),
        else => 255,
    };
}
