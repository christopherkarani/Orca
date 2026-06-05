const std = @import("std");

const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");
const style = @import("style.zig");
const plugin = @import("plugin.zig");
const interactive = @import("interactive.zig");
const onboarding = @import("onboarding.zig");
const spinner_pkg = @import("spinner.zig");

pub fn command(io: std.Io, cwd: std.Io.Dir, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0) {
        _ = try help.writeCommand(io, stdout, "setup");
        return exit_codes.success;
    }

    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            _ = try help.writeCommand(io, stdout, "setup");
            return exit_codes.success;
        }
    }

    const flags = onboarding.parseFlags(argv, stderr, "orca setup", true) catch |err| switch (err) {
        error.Usage => return exit_codes.usage,
        else => return err,
    };

    if (!flags.auto) {
        if (onboarding.interactiveSetupDesired(io)) {
            return runGuidedSetup(io, cwd, flags.preset, stdout, stderr);
        }
        _ = try help.writeCommand(io, stdout, "setup");
        return exit_codes.success;
    }

    return runAutoSetup(io, cwd, flags.preset, stdout, stderr);
}

fn runAutoSetup(io: std.Io, cwd: std.Io.Dir, preset: []const u8, stdout: anytype, stderr: anytype) !u8 {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const self_exe = try std.process.executablePathAlloc(io, allocator);
    defer allocator.free(self_exe);

    const workspace_root = try onboarding.resolveWorkspaceRootFromCwd(io, allocator, cwd);
    defer allocator.free(workspace_root);

    const policy_code = try onboarding.ensurePolicy(io, cwd, workspace_root, preset, stdout, stderr, .{
        .missing = "Policy not found. Initializing...\n",
        .exists = "Policy already exists.\n",
    });
    if (policy_code != exit_codes.success) return policy_code;

    var doctor_report = try plugin.collectPluginDoctorReport(io, allocator);
    defer plugin.deinitPluginDoctorReport(&doctor_report, allocator);

    var any_detected = false;
    var failure_count: usize = 0;

    for (onboarding.supported_hosts) |host_name| {
        if (!plugin.binaryInPath(io, allocator, host_name)) continue;
        any_detected = true;
        try stdout.print("\nDetected host: {s}\n", .{host_name});

        const installed = plugin.hostPluginInstalledFromReport(host_name, doctor_report);

        if (installed) {
            try stdout.print("  ✓ {s}: already installed\n", .{host_name});
        } else {
            try stdout.print("  → {s}: Installing...", .{host_name});
            try flushIfSupported(stdout);

            var spinner = spinner_pkg.Spinner(@TypeOf(stdout)){
                .label = host_name,
                .io = io,
                .stdout = stdout,
            };
            try spinner.start();

            const install_argv = &[_][]const u8{ self_exe, "plugin", "install", host_name, "--yes" };
            const install_code = runChild(io, install_argv);
            if (install_code) |code| {
                if (code != 0) {
                    try spinner.stop(false);
                    try stdout.print(" (exit code {d})\n", .{code});
                    failure_count += 1;
                    continue;
                }
                try spinner.stop(true);
                try stdout.writeAll("\n");
            } else |err| {
                try spinner.stop(false);
                try stdout.print(" ({s})\n", .{@errorName(err)});
                failure_count += 1;
                continue;
            }

            const refreshed_report = try plugin.collectPluginDoctorReport(io, allocator);
            plugin.deinitPluginDoctorReport(&doctor_report, allocator);
            doctor_report = refreshed_report;
        }

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
        try stdout.writeAll("Install a supported host and run 'orca setup --auto' (non-interactive) again.\n");
    }

    if (failure_count > 0) {
        try stdout.print("\nSetup finished with {d} failure(s).\n", .{failure_count});
        try stdout.writeAll("Review the messages above and re-run 'orca setup --auto' (non-interactive) after fixing blockers.\n");
        return exit_codes.general;
    }

    try stdout.writeAll("\n");
    try style.maybeColor(io, stdout, style.Style.green, style.Glyph.party ++ " Setup complete!");
    try stdout.writeAll("\nRun 'orca run -- <command>' to start a protected session.\n");
    return exit_codes.success;
}

fn flushIfSupported(writer: anytype) !void {
    const Writer = @TypeOf(writer);
    switch (@typeInfo(Writer)) {
        .pointer => |pointer| {
            if (@hasDecl(pointer.child, "flush")) try writer.flush();
        },
        else => {
            if (@hasDecl(Writer, "flush")) try writer.flush();
        },
    }
}

fn runChild(io: std.Io, argv: []const []const u8) !u8 {
    var child = try std.process.spawn(io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
    const term = try child.wait(io);
    return switch (term) {
        .exited => |code| @as(u8, @intCast(@min(code, 255))),
        else => 255,
    };
}

fn runGuidedSetup(io: std.Io, cwd: std.Io.Dir, preset: []const u8, stdout: anytype, stderr: anytype) !u8 {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    try stdout.writeAll("Orca Guided Setup\n\n");
    try stdout.writeAll("Detecting installed agent hosts...\n");

    const workspace_root = try onboarding.resolveWorkspaceRootFromCwd(io, allocator, cwd);
    defer allocator.free(workspace_root);

    const policy_code = try onboarding.ensurePolicy(io, cwd, workspace_root, preset, stdout, stderr, .{
        .missing = "No policy found. Creating policy...\n",
    });
    if (policy_code != exit_codes.success) {
        try stderr.print("orca setup: policy init returned non-success code {d}\n", .{policy_code});
        return policy_code;
    }

    var doctor_report = try plugin.collectPluginDoctorReport(io, allocator);
    defer plugin.deinitPluginDoctorReport(&doctor_report, allocator);

    var detected_list: std.ArrayList([]const u8) = .empty;
    defer detected_list.deinit(allocator);

    for (onboarding.supported_hosts) |h| {
        if (plugin.binaryInPath(io, allocator, h)) {
            try detected_list.append(allocator, h);
        }
    }

    if (detected_list.items.len == 0) {
        try stdout.writeAll("\nNo supported agent hosts detected in PATH.\n");
        try stdout.writeAll("You can still use `orca run -- <your-command>` for protection.\n");
        return exit_codes.success;
    }

    var selection_items = try allocator.alloc(interactive.SelectionItem, detected_list.items.len);
    defer allocator.free(selection_items);

    for (detected_list.items, 0..) |h, i| {
        selection_items[i] = .{
            .label = h,
            .checked = true,
            .id = h,
        };
    }

    const stdin_file = std.Io.File.stdin();
    var stdin_reader_buf: [256]u8 = undefined;
    var stdin_reader = stdin_file.reader(io, &stdin_reader_buf);

    var result = try interactive.runMultiSelect(allocator, selection_items, stdout, &stdin_reader.interface);
    defer interactive.deinitMultiSelectResult(&result, allocator);

    var any_installed = false;
    for (result.items) |item| {
        if (!item.checked) continue;

        try stdout.print("\nIntegrating with {s}...", .{item.label});
        try flushIfSupported(stdout);

        var spinner = spinner_pkg.Spinner(@TypeOf(stdout)){
            .label = item.label,
            .io = io,
            .stdout = stdout,
        };
        try spinner.start();

        const install_argv = &[_][]const u8{ "plugin", "install", item.label, "--yes" };
        const code = runChild(io, install_argv) catch |err| {
            try spinner.stop(false);
            try stdout.print(" ({s})\n", .{@errorName(err)});
            continue;
        };
        if (code == 0) {
            try spinner.stop(true);
            try stdout.writeAll("\n");
            any_installed = true;
        } else {
            try spinner.stop(false);
            try stdout.print(" (exit code {d})\n", .{code});
        }
    }

    if (any_installed) {
        try stdout.writeAll("\n");
        try style.maybeColor(io, stdout, style.Style.green, style.Glyph.party ++ " Guided setup complete!");
        try stdout.writeAll("\n");
    } else {
        try stdout.writeAll("\nNo new integrations were added.\n");
    }

    try stdout.writeAll("Run 'orca doctor' or 'orca run -- <command>' to get started.\n");
    return exit_codes.success;
}
