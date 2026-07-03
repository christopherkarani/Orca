const std = @import("std");

const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");
const style = @import("style.zig");
const plugin = @import("plugin.zig");
const onboarding = @import("onboarding.zig");
const spinner_pkg = @import("spinner.zig");
const build_options = @import("build_options");
const tui = @import("../tui/mod.zig");

pub fn command(io: std.Io, cwd: std.Io.Dir, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0) {
        if (onboarding.interactiveSetupDesired(io)) {
            return runGuidedSetup(io, cwd, onboarding.default_preset, stdout, stderr, null, .{});
        }
        _ = try help.writeCommand(io, stdout, "setup");
        return exit_codes.success;
    }

    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            _ = try help.writeCommand(io, stdout, "setup");
            return exit_codes.success;
        }
    }

    const embedded = hasEmbeddedFlag(argv);
    const flags = parseSetupFlags(argv, stderr) catch |err| switch (err) {
        error.Usage => return exit_codes.usage,
        else => return err,
    };

    if (!flags.auto) {
        if (onboarding.interactiveSetupDesired(io)) {
            return runGuidedSetup(io, cwd, flags.preset, stdout, stderr, null, .{ .embedded = embedded });
        }
        _ = try help.writeCommand(io, stdout, "setup");
        return exit_codes.success;
    }

    return runAutoSetup(io, cwd, flags.preset, stdout, stderr, .{ .embedded = embedded });
}

fn hasEmbeddedFlag(argv: []const []const u8) bool {
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--embedded")) return true;
    }
    return false;
}

fn parseSetupFlags(argv: []const []const u8, stderr: anytype) !onboarding.Flags {
    var filtered: [32][]const u8 = undefined;
    var count: usize = 0;
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--embedded")) continue;
        if (count >= filtered.len) return error.Usage;
        filtered[count] = arg;
        count += 1;
    }
    return onboarding.parseFlags(filtered[0..count], stderr, "orca setup", true);
}

const SetupRenderOpts = struct {
    embedded: bool = false,
};

fn runAutoSetup(io: std.Io, cwd: std.Io.Dir, preset: []const u8, stdout: anytype, stderr: anytype, render: SetupRenderOpts) !u8 {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const self_exe = try std.process.executablePathAlloc(io, allocator);
    defer allocator.free(self_exe);

    if (!render.embedded) {
        try tui.render.banner(io, stdout, build_options.version, "setup");
    }

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
                const outcome = plugin.verifyHostInstallAfterChild(io, allocator, host_name, code);
                if (outcome == .failed) {
                    try spinner.stop(false);
                    try stdout.print(" verification failed (installer exit {d})\n", .{code});
                    failure_count += 1;
                    continue;
                }
                try spinner.stop(true);
                if (outcome == .installed_after_child_failure)
                    try stdout.print(" verified (installer exited {d})\n", .{code})
                else
                    try stdout.writeAll(" verified\n");
            } else |err| {
                try spinner.stop(false);
                try stdout.print(" ({s})\n", .{@errorName(err)});
                failure_count += 1;
                continue;
            }
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

fn runGuidedSetup(
    io: std.Io,
    cwd: std.Io.Dir,
    preset: []const u8,
    stdout: anytype,
    stderr: anytype,
    injected_reader: ?*std.Io.Reader,
    render: SetupRenderOpts,
) !u8 {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const self_exe = try std.process.executablePathAlloc(io, allocator);
    defer allocator.free(self_exe);

    if (!render.embedded) {
        try tui.render.banner(io, stdout, build_options.version, "guided setup");
    }

    const workspace_root = try onboarding.resolveWorkspaceRootFromCwd(io, allocator, cwd);
    defer allocator.free(workspace_root);

    const policy_existed = onboarding.policyExists(io, workspace_root);
    if (!render.embedded) {
        try tui.render.stepLine(io, stdout, .active, "Policy", "Checking workspace policy...", 0);
    }
    const policy_code = try onboarding.ensurePolicy(io, cwd, workspace_root, preset, stdout, stderr, .{
        .missing = "No policy found. Creating policy...\n",
        .exists = null,
    });
    if (policy_code != exit_codes.success) {
        if (!render.embedded) {
            try tui.render.stepLine(io, stdout, .failed, "Policy", "Policy setup failed.", 0);
        }
        try stderr.print("orca setup: policy init returned non-success code {d}\n", .{policy_code});
        return policy_code;
    }
    if (!render.embedded) {
        try tui.render.stepLine(io, stdout, .done, "Policy", if (policy_existed) "Existing policy preserved." else "Policy created.", 0);
    }

    var doctor_report = try plugin.collectPluginDoctorReport(io, allocator);
    defer plugin.deinitPluginDoctorReport(&doctor_report, allocator);

    if (!render.embedded) {
        try tui.render.stepLine(io, stdout, .active, "Hosts", "Detecting agent hosts...", 0);
    }

    var host_statuses: std.ArrayList(onboarding.HostStatus) = .empty;
    defer host_statuses.deinit(allocator);

    for (onboarding.supported_hosts) |host_name| {
        const detected = plugin.binaryInPath(io, allocator, host_name);
        const installed = if (detected) plugin.hostPluginInstalledFromReport(host_name, doctor_report) else false;
        try host_statuses.append(allocator, .{
            .name = host_name,
            .detected = detected,
            .installed = installed,
        });
    }

    var detected_count: usize = 0;
    for (host_statuses.items) |status| {
        if (status.detected) detected_count += 1;
    }

    if (detected_count == 0) {
        if (!render.embedded) {
            try tui.render.stepLine(io, stdout, .done, "Hosts", "No supported hosts detected in PATH.", 0);
        }
        try stdout.writeAll("\nYou can still use `orca run -- <your-command>` for protection.\n");
        return exit_codes.success;
    }

    var panel_lines: std.ArrayList([]const u8) = .empty;
    defer {
        for (panel_lines.items) |line| allocator.free(line);
        panel_lines.deinit(allocator);
    }

    for (host_statuses.items) |status| {
        if (!status.detected) continue;
        const line = try std.fmt.allocPrint(
            allocator,
            "{s}: {s}{s}",
            .{
                status.name,
                if (status.installed) "installed" else "detected",
                if (status.installed) "" else ", not integrated",
            },
        );
        try panel_lines.append(allocator, line);
    }
    try stdout.writeAll("\n");
    try tui.render.panel(io, stdout, "Detected hosts", panel_lines.items);
    try stdout.writeAll("\n");

    var options = try allocator.alloc(tui.prompt.SelectionOption, detected_count);
    defer {
        for (options) |opt| {
            allocator.free(opt.label);
            if (opt.id) |id| allocator.free(id);
        }
        allocator.free(options);
    }

    var visible_idx: usize = 0;
    for (host_statuses.items) |status| {
        if (!status.detected) continue;
        const marker = if (status.installed) " (installed)" else "";
        var label_buf: [64]u8 = undefined;
        const label = std.fmt.bufPrint(&label_buf, "{s}{s}", .{ status.name, marker }) catch status.name;
        options[visible_idx] = .{
            .label = try allocator.dupe(u8, label),
            .checked = true,
            .id = try allocator.dupe(u8, status.name),
        };
        visible_idx += 1;
    }

    const confirmed = try tui.prompt.multiSelect(io, allocator, stdout, options, "Select agent hosts to integrate", injected_reader);
    if (!confirmed) {
        try stdout.writeAll("\nHost selection cancelled.\n");
        return exit_codes.success;
    }

    if (!render.embedded) {
        try tui.render.stepLine(io, stdout, .active, "Hosts", "Installing integrations...", 0);
    }

    var installed_hosts: std.ArrayList([]const u8) = .empty;
    defer {
        for (installed_hosts.items) |host| allocator.free(host);
        installed_hosts.deinit(allocator);
    }
    var skipped_hosts: std.ArrayList([]const u8) = .empty;
    defer {
        for (skipped_hosts.items) |host| allocator.free(host);
        skipped_hosts.deinit(allocator);
    }
    var failure_count: usize = 0;

    for (options) |item| {
        const host_name = item.id orelse item.label;
        if (!item.checked) {
            try skipped_hosts.append(allocator, try allocator.dupe(u8, host_name));
            continue;
        }

        if (plugin.hostPluginInstalledFromReport(host_name, doctor_report)) {
            try installed_hosts.append(allocator, try allocator.dupe(u8, host_name));
            continue;
        }

        try stdout.print("  → {s}: ", .{host_name});
        try flushIfSupported(stdout);

        var spinner = spinner_pkg.Spinner(@TypeOf(stdout)){
            .label = host_name,
            .io = io,
            .stdout = stdout,
        };
        try spinner.start();

        const install_argv = &[_][]const u8{ self_exe, "plugin", "install", host_name, "--yes" };
        const code = runChild(io, install_argv) catch |err| {
            try spinner.stop(false);
            try stdout.print("failed ({s})\n", .{@errorName(err)});
            failure_count += 1;
            continue;
        };
        const outcome = plugin.verifyHostInstallAfterChild(io, allocator, host_name, code);
        if (outcome != .failed) {
            try spinner.stop(true);
            if (outcome == .installed_after_child_failure)
                try stdout.print("installed (verified; installer exited {d})\n", .{code})
            else
                try stdout.writeAll("installed (verified)\n");
            try installed_hosts.append(allocator, try allocator.dupe(u8, host_name));
        } else {
            try spinner.stop(false);
            try stdout.print("failed verification (installer exit {d})\n", .{code});
            failure_count += 1;
        }
    }

    if (!render.embedded) {
        if (failure_count == 0) {
            try tui.render.stepLine(io, stdout, .done, "Hosts", "Integrations configured.", 0);
        } else {
            try tui.render.stepLine(io, stdout, .failed, "Hosts", "Some integrations failed.", 0);
        }
    } else if (failure_count > 0) {
        try stdout.print("  {d} integration(s) failed.\n", .{failure_count});
    }

    var summary_lines: std.ArrayList([]const u8) = .empty;
    defer {
        for (summary_lines.items) |line| allocator.free(line);
        summary_lines.deinit(allocator);
    }

    for (installed_hosts.items) |host| {
        const line = try std.fmt.allocPrint(allocator, "✓ {s}: integrated", .{host});
        try summary_lines.append(allocator, line);
    }
    for (skipped_hosts.items) |host| {
        const line = try std.fmt.allocPrint(allocator, "○ {s}: skipped", .{host});
        try summary_lines.append(allocator, line);
    }
    if (failure_count > 0) {
        const line = try std.fmt.allocPrint(allocator, "✗ {d} integration(s) failed", .{failure_count});
        try summary_lines.append(allocator, line);
    }

    try stdout.writeAll("\n");
    try tui.render.panel(io, stdout, "Setup summary", summary_lines.items);
    try stdout.writeAll("\n");

    if (failure_count > 0) {
        try stdout.writeAll("Review the messages above and re-run `orca setup` after fixing blockers.\n");
        return exit_codes.general;
    }

    try style.maybeColor(io, stdout, style.Style.green, style.Glyph.party ++ " Guided setup complete!");
    try stdout.writeAll("\nRun 'orca doctor' or 'orca run -- <command>' to get started.\n");
    return exit_codes.success;
}

test "guided setup host panel formats detected hosts" {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const statuses = [_]onboarding.HostStatus{
        .{ .name = "codex", .detected = true, .installed = false },
        .{ .name = "claude", .detected = true, .installed = true },
        .{ .name = "hermes", .detected = false, .installed = false },
    };

    var panel_lines: std.ArrayList([]const u8) = .empty;
    defer {
        for (panel_lines.items) |line| allocator.free(line);
        panel_lines.deinit(allocator);
    }

    for (statuses) |status| {
        if (!status.detected) continue;
        const line = try std.fmt.allocPrint(
            allocator,
            "{s}: {s}{s}",
            .{
                status.name,
                if (status.installed) "installed" else "detected",
                if (status.installed) "" else ", not integrated",
            },
        );
        try panel_lines.append(allocator, line);
    }

    try std.testing.expectEqual(@as(usize, 2), panel_lines.items.len);
    try std.testing.expect(std.mem.indexOf(u8, panel_lines.items[0], "codex") != null);
    try std.testing.expect(std.mem.indexOf(u8, panel_lines.items[1], "claude") != null);
}

test "guided setup multiSelect with injected reader accepts defaults" {
    tui.theme.resetCache();
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var in = std.Io.Reader.fixed("enter\n");

    var options = [_]tui.prompt.SelectionOption{
        .{ .label = "codex", .checked = true, .id = "codex" },
        .{ .label = "claude", .checked = false, .id = "claude" },
    };

    const confirmed = try tui.prompt.multiSelect(std.testing.io, std.testing.allocator, &stdout_writer, &options, "Select hosts", &in);
    try std.testing.expect(confirmed);
    try std.testing.expect(options[0].checked);
    try std.testing.expect(!options[1].checked);
}
