const std = @import("std");

const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");
const style = @import("style.zig");
const onboarding = @import("onboarding.zig");
const plugin = @import("plugin.zig");
const shell_eval = @import("shell_eval.zig");
const build_options = @import("build_options");
const tui = @import("../tui/mod.zig");

pub fn command(io: std.Io, cwd: std.Io.Dir, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            _ = try help.writeCommand(io, stdout, "start");
            return exit_codes.success;
        }
    }

    if (argv.len == 0) {
        var flags: onboarding.StartFlags = .{};
        if (!onboarding.interactiveSetupDesired(io)) {
            flags.auto = true;
        }
        return runStart(io, cwd, flags, stdout, stderr, null, null);
    }

    var flags = onboarding.parseStartFlags(argv, stderr) catch |err| switch (err) {
        error.Usage => return exit_codes.usage,
        else => return err,
    };

    if (!flags.auto and !onboarding.interactiveSetupDesired(io)) {
        flags.auto = true;
    }

    return runStart(io, cwd, flags, stdout, stderr, null, null);
}

pub fn runStart(
    io: std.Io,
    cwd: std.Io.Dir,
    flags: onboarding.StartFlags,
    stdout: anytype,
    stderr: anytype,
    daemon_check_fn: ?*const fn (std.mem.Allocator, bool) anyerror!void,
    shell_evaluator: ?shell_eval.ShellCommandEvaluatorFn,
) !u8 {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    try tui.render.banner(io, stdout, build_options.version, null);
    try stdout.writeAll(
        \\Orca will configure protection for your workspace, verify the Rust daemon when needed,
        \\install host integrations you choose, and run safe verification checks.
        \\Existing policy files are kept unless you run `orca init --force`.
        \\
        \\
    );

    const workspace_root = try onboarding.resolveWorkspaceRootFromCwd(io, allocator, cwd);
    defer allocator.free(workspace_root);

    const protection = try resolveProtectionMode(io, allocator, flags, stdout, stderr);
    try stdout.print("Protection mode: {s}\n  {s}\n\n", .{ protection.label(), protection.description() });

    var doctor_report = try plugin.collectPluginDoctorReport(io, allocator);
    defer plugin.deinitPluginDoctorReport(&doctor_report, allocator);

    const host_statuses = try onboarding.collectHostStatuses(io, allocator, doctor_report);
    defer allocator.free(host_statuses);

    const selected_hosts = try resolveSelectedHosts(io, allocator, flags, host_statuses, stdout);
    defer if (selected_hosts.owned) onboarding.deinitHostList(allocator, selected_hosts.items);

    var failures: usize = 0;
    var protection_active = false;

    const policy_existed = onboarding.policyExists(io, workspace_root);
    const policy_code = try onboarding.ensurePolicy(io, cwd, workspace_root, flags.preset, stdout, stderr, .{
        .missing = "Creating .orca/policy.yaml...\n",
        .exists = "Policy already exists — leaving it unchanged.\n",
    });
    if (policy_code != exit_codes.success) {
        try tui.render.stepLine(io, stdout, .failed, "Policy", "Policy setup failed.", 80);
        failures += 1;
    } else {
        try tui.render.stepLine(io, stdout, .done, "Policy", if (policy_existed) "Existing policy preserved." else "Policy created.", 80);
    }

    var daemon_check: onboarding.DaemonCheck = undefined;
    if (protection.needsCommandGuard()) {
        daemon_check = try onboarding.checkDaemonHealth(allocator, true, daemon_check_fn);
        const daemon_ok = daemon_check.status == .compatible;
        protection_active = protection_active or daemon_ok;
        try tui.render.stepLine(io, stdout, if (daemon_ok) .done else .failed, "Daemon", if (daemon_ok) "Ready for Command Guard" else daemon_check.remediation, 80);
        if (!daemon_ok) {
            try stdout.print("  Status: {s}\n", .{daemon_check.status.label()});
            try stdout.print("  Detail: {s}\n", .{daemon_check.detail});
            failures += 1;
        }
    } else {
        daemon_check = try onboarding.checkDaemonHealth(allocator, false, daemon_check_fn);
        try tui.render.stepLine(io, stdout, .done, "Daemon", "Not required for Firewall-only mode", 80);
        protection_active = onboarding.verifyFirewallReady(io, workspace_root);
    }

    var configured_hosts: std.ArrayList([]const u8) = .empty;
    defer {
        for (configured_hosts.items) |host| allocator.free(host);
        configured_hosts.deinit(allocator);
    }

    if (selected_hosts.items.len == 0) {
        try tui.render.stepLine(io, stdout, .done, "Hosts", "No hosts selected.", 80);
    } else if (protection.needsCommandGuard()) {
        const host_failures = try installSelectedHosts(io, allocator, selected_hosts.items, stdout, &configured_hosts);
        failures += host_failures;
        protection_active = protection_active and host_failures == 0;
        if (host_failures == 0) {
            try tui.render.stepLine(io, stdout, .done, "Hosts", "Integrations configured", 80);
        } else {
            try tui.render.stepLine(io, stdout, .failed, "Hosts", "Integration failed. Run `orca plugin doctor`", 80);
        }
    } else {
        try tui.render.stepLine(io, stdout, .done, "Hosts", "Skipped for Firewall-only mode", 80);
        protection_active = onboarding.verifyFirewallReady(io, workspace_root);
    }

    var verification: ?onboarding.VerificationOutcome = null;
    if (!flags.skip_verify and failures == 0) {
        if (protection.needsCommandGuard() and daemon_check.status != .compatible) {
            try tui.render.stepLine(io, stdout, .failed, "Verify", "Skipped shell verification because the daemon is unavailable", 80);
            failures += 1;
        } else {
            const eval_fn = shell_evaluator orelse shell_eval.defaultEvaluator;
            verification = try onboarding.runVerification(
                allocator,
                io,
                workspace_root,
                protection,
                selected_hosts.items,
                eval_fn,
            );
            const verify_ok = verification.?.passed();
            protection_active = protection_active and verify_ok;
            try tui.render.stepLine(io, stdout, if (verify_ok) .done else .failed, "Verify", verification.?.detail, 80);
            if (!verify_ok) {
                try stdout.print("  Safe command ({s}): {s}\n", .{ onboarding.safe_verification_command, if (verification.?.safe_allowed) "allowed" else "FAILED" });
                try stdout.print("  Dangerous command ({s}): {s}\n", .{ onboarding.dangerous_verification_command, if (verification.?.dangerous_denied) "denied" else "FAILED" });
                if (verification.?.hook_verified) |hook_ok| {
                    try stdout.print("  Hook path: {s}\n", .{if (hook_ok) "verified" else "FAILED"});
                }
                if (verification.?.firewall_ready) |firewall_ok| {
                    try stdout.print("  Firewall policy: {s}\n", .{if (firewall_ok) "ready" else "missing"});
                }
                failures += 1;
            }
        }
    } else if (flags.skip_verify) {
        try stdout.writeAll("\nVerification skipped (--skip-verify).\n");
    }

    try stdout.writeAll("\n");
    if (failures > 0) {
        try writeFailureSummary(io, stdout, protection, selected_hosts.items, configured_hosts.items, daemon_check, verification, protection_active);
        return exit_codes.general;
    }

    try writeSuccessEndCard(
        io,
        allocator,
        stdout,
        workspace_root,
        flags.preset,
        protection,
        selected_hosts.items,
        configured_hosts.items,
        daemon_check,
        verification,
    );
    return exit_codes.success;
}

fn resolveProtectionMode(
    io: std.Io,
    allocator: std.mem.Allocator,
    flags: onboarding.StartFlags,
    stdout: anytype,
    stderr: anytype,
) !onboarding.ProtectionMode {
    _ = stderr;
    if (flags.protection) |mode| return mode;
    if (flags.auto) return onboarding.defaultProtectionMode();

    const options = [_]tui.prompt.SelectionOption{
        .{ .label = "Command Guard", .description = "hook-based shell blocking", .id = "command_guard" },
        .{ .label = "Firewall", .description = "sandboxed `orca run` sessions", .id = "firewall" },
        .{ .label = "Maximum Protection", .description = "both (recommended)", .id = "maximum_protection" },
    };
    const idx = try tui.prompt.select(io, allocator, stdout, &options, 2, "Choose your protection mode", null);
    const selected = idx orelse 2;
    if (selected == 0) return .command_guard;
    if (selected == 1) return .firewall;
    return .maximum_protection;
}

const SelectedHosts = struct {
    items: [][]const u8,
    owned: bool,
};

fn resolveSelectedHosts(
    io: std.Io,
    allocator: std.mem.Allocator,
    flags: onboarding.StartFlags,
    host_statuses: []const onboarding.HostStatus,
    stdout: anytype,
) !SelectedHosts {
    if (flags.hosts_csv) |csv| {
        return .{ .items = try onboarding.parseHostsCsv(allocator, csv), .owned = true };
    }

    if (flags.auto) {
        var list: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (list.items) |item| allocator.free(item);
            list.deinit(allocator);
        }
        for (host_statuses) |status| {
            if (!status.detected) continue;
            try list.append(allocator, try allocator.dupe(u8, status.name));
        }
        return .{ .items = try list.toOwnedSlice(allocator), .owned = true };
    }

    var detected_count: usize = 0;
    for (host_statuses) |status| {
        if (status.detected) detected_count += 1;
    }
    if (detected_count == 0) {
        try stdout.writeAll("\nNo supported agent hosts detected in PATH.\n");
        try stdout.writeAll("You can continue without host hooks and use `orca run -- <command>`.\n\n");
        return .{ .items = &.{}, .owned = false };
    }

    var options = try allocator.alloc(tui.prompt.SelectionOption, detected_count);
    defer allocator.free(options);

    var visible_idx: usize = 0;
    for (host_statuses) |status| {
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
    defer {
        for (options) |opt| {
            allocator.free(opt.label);
            if (opt.id) |id| allocator.free(id);
        }
    }

    const confirmed = try tui.prompt.multiSelect(io, allocator, stdout, options, "Select agent hosts to integrate", null);
    if (!confirmed) {
        try stdout.writeAll("\nHost selection cancelled.\n");
        return .{ .items = &.{}, .owned = false };
    }

    var list: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (list.items) |item| allocator.free(item);
        list.deinit(allocator);
    }
    for (options) |item| {
        if (!item.checked) continue;
        const host_name = item.id orelse item.label;
        try list.append(allocator, try allocator.dupe(u8, host_name));
    }
    return .{ .items = try list.toOwnedSlice(allocator), .owned = true };
}

fn installSelectedHosts(
    io: std.Io,
    allocator: std.mem.Allocator,
    hosts: []const []const u8,
    stdout: anytype,
    configured_out: *std.ArrayList([]const u8),
) !usize {
    const self_exe = try std.process.executablePathAlloc(io, allocator);
    defer allocator.free(self_exe);

    var failures: usize = 0;
    for (hosts) |host_name| {
        try stdout.print("  → {s}: ", .{host_name});
        const install_argv = &[_][]const u8{ self_exe, "plugin", "install", host_name, "--yes" };
        const code = runChild(io, install_argv) catch |err| {
            try stdout.print("failed ({s})\n", .{@errorName(err)});
            failures += 1;
            continue;
        };
        const outcome = plugin.verifyHostInstallAfterChild(io, allocator, host_name, code);
        if (outcome != .failed) {
            if (outcome == .installed_after_child_failure)
                try stdout.print("installed (verified; installer exited {d})\n", .{code})
            else
                try stdout.writeAll("installed (verified)\n");
            try configured_out.append(allocator, try allocator.dupe(u8, host_name));
        } else {
            try stdout.print("failed verification (installer exit {d})\n", .{code});
            failures += 1;
        }
    }
    return failures;
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

/// Stable first-run end-card after successful `orca start`.
/// Works on non-TTY (plain text, no broken ANSI via tui theme degrade).
fn writeSuccessEndCard(
    io: std.Io,
    allocator: std.mem.Allocator,
    stdout: anytype,
    workspace_root: []const u8,
    preset: []const u8,
    protection: onboarding.ProtectionMode,
    selected_hosts: []const []const u8,
    configured_hosts: []const []const u8,
    daemon_check: onboarding.DaemonCheck,
    verification: ?onboarding.VerificationOutcome,
) !void {
    try tui.render.callout(io, stdout, .success, "You are protected", "Orca is configured for this workspace.");
    try stdout.writeAll("\n");

    const policy_path = try std.fs.path.join(allocator, &.{ workspace_root, ".orca", "policy.yaml" });
    defer allocator.free(policy_path);
    const policy_line = try std.fmt.allocPrint(allocator, "{s}  (preset {s})", .{ policy_path, preset });
    defer allocator.free(policy_line);
    const daemon_line = try std.fmt.allocPrint(allocator, "{s}", .{daemon_check.status.label()});
    defer allocator.free(daemon_line);
    const protection_line = try std.fmt.allocPrint(allocator, "{s}", .{protection.label()});
    defer allocator.free(protection_line);
    const verify_line: []const u8 = if (verification) |v|
        if (v.passed()) "passed" else "failed"
    else
        "skipped";

    const daemon_status_line = try std.fmt.allocPrint(allocator, "Daemon       {s}", .{daemon_line});
    defer allocator.free(daemon_status_line);
    const policy_status_line = try std.fmt.allocPrint(allocator, "Policy       {s}", .{policy_line});
    defer allocator.free(policy_status_line);
    const protection_status_line = try std.fmt.allocPrint(allocator, "Protection   {s}", .{protection_line});
    defer allocator.free(protection_status_line);
    const verify_status_line = try std.fmt.allocPrint(allocator, "Verify       {s}", .{verify_line});
    defer allocator.free(verify_status_line);
    const status_lines = [_][]const u8{ daemon_status_line, policy_status_line, protection_status_line, verify_status_line };
    try tui.render.panel(io, stdout, "Status", &status_lines);
    try stdout.writeAll("\n");

    // Host install results: selected hosts get ✓ / failed; unselected shown as skipped when CG.
    var host_lines: std.ArrayList([]const u8) = .empty;
    defer {
        for (host_lines.items) |line| allocator.free(line);
        host_lines.deinit(allocator);
    }
    if (!protection.needsCommandGuard()) {
        try host_lines.append(allocator, try allocator.dupe(u8, "hooks skipped (Firewall-only mode)"));
        for (selected_hosts) |host| {
            try host_lines.append(allocator, try std.fmt.allocPrint(allocator, "  {s}  skipped", .{host}));
        }
    } else if (selected_hosts.len == 0) {
        try host_lines.append(allocator, try allocator.dupe(u8, "none selected"));
    } else {
        for (selected_hosts) |host| {
            const ok = hostInList(host, configured_hosts);
            const mark: []const u8 = if (ok) "✓" else "failed";
            try host_lines.append(allocator, try std.fmt.allocPrint(allocator, "  {s}  {s}", .{ host, mark }));
        }
    }
    try tui.render.panel(io, stdout, "Hosts", host_lines.items);
    try stdout.writeAll("\n");

    try tui.theme.paintBold(io, stdout, .brand, "Try next");
    try stdout.writeAll("\n");
    try stdout.writeAll("  orca demo blocked-action\n");
    try stdout.writeAll("  orca test \"git reset --hard\"\n");
    if (protection.needsFirewall()) {
        try stdout.writeAll("  orca run -- echo hello\n");
    } else {
        try stdout.writeAll("  orca doctor\n");
    }
    try stdout.writeAll("\n");
    try tui.theme.paint(io, stdout, .muted, "Diagnostics: orca doctor · orca dashboard · orca start (re-run safely)");
    try stdout.writeAll("\n");
}

fn hostInList(name: []const u8, list: []const []const u8) bool {
    for (list) |item| {
        if (std.mem.eql(u8, item, name)) return true;
    }
    return false;
}

fn writeFailureSummary(
    io: std.Io,
    stdout: anytype,
    protection: onboarding.ProtectionMode,
    selected_hosts: []const []const u8,
    configured_hosts: []const []const u8,
    daemon_check: onboarding.DaemonCheck,
    verification: ?onboarding.VerificationOutcome,
    protection_active: bool,
) !void {
    try style.maybeColor(io, stdout, style.Style.red, "Setup incomplete");
    try stdout.writeAll("\n\n");
    try stdout.print("Protection mode selected: {s}\n", .{protection.label()});
    try stdout.print("Protection active now: {s}\n", .{if (protection_active) "partially or fully" else "no"});
    try stdout.print("Daemon: {s} — {s}\n", .{ daemon_check.status.label(), daemon_check.detail });
    if (verification) |v| try stdout.print("Verification: {s}\n", .{v.detail});
    if (configured_hosts.len > 0) {
        try stdout.writeAll("Configured hosts: ");
        for (configured_hosts, 0..) |host, i| {
            if (i > 0) try stdout.writeAll(", ");
            try stdout.writeAll(host);
        }
        try stdout.writeAll("\n");
    } else if (selected_hosts.len > 0) {
        try stdout.writeAll("Selected hosts: ");
        for (selected_hosts, 0..) |host, i| {
            if (i > 0) try stdout.writeAll(", ");
            try stdout.writeAll(host);
        }
        try stdout.writeAll("\n");
    }
    try stdout.writeAll("\nRecommended repair steps:\n");
    try stdout.print("  {s}\n", .{daemon_check.remediation});
    try stdout.writeAll("  orca plugin doctor\n");
    try stdout.writeAll("  orca doctor --verbose\n");
    try stdout.writeAll("  orca start --auto\n");
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

test "start auto mode with mock daemon completes in temp workspace" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var stdout_buf: [16384]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const flags = onboarding.StartFlags{
        .auto = true,
        .protection = .firewall,
        .skip_verify = true,
    };

    const mock_checker = struct {
        fn check(_: std.mem.Allocator, _: bool) !void {}
    }.check;

    const code = try runStart(
        std.testing.io,
        tmp.dir,
        flags,
        &stdout_writer,
        &stderr_writer,
        mock_checker,
        onboarding.mockOnboardingEvaluator,
    );
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "\u{1F6E1}  Orca") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Firewall") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "You are protected") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Daemon") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Policy") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Hosts") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "orca demo blocked-action") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "orca test \"git reset --hard\"") != null);
}

test "start reports failure when daemon required but unavailable" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var stdout_buf: [16384]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const flags = onboarding.StartFlags{
        .auto = true,
        .protection = .command_guard,
        .skip_verify = true,
    };

    const failing_checker = struct {
        fn check(_: std.mem.Allocator, _: bool) !void {
            return error.DaemonBinaryNotFound;
        }
    }.check;

    const code = try runStart(
        std.testing.io,
        tmp.dir,
        flags,
        &stdout_writer,
        &stderr_writer,
        failing_checker,
        null,
    );
    try std.testing.expectEqual(exit_codes.general, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "Setup incomplete") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "Protection active now: no") != null);
}

test "start firewall mode verifies without daemon or shell evaluator" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(std.testing.io, ".git", .default_dir);

    var stdout_buf: [16384]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const flags = onboarding.StartFlags{
        .auto = true,
        .protection = .firewall,
        .skip_verify = false,
    };

    const mock_checker = struct {
        fn check(_: std.mem.Allocator, _: bool) !void {
            return error.DaemonBinaryNotFound;
        }
    }.check;

    const code = try runStart(
        std.testing.io,
        tmp.dir,
        flags,
        &stdout_writer,
        &stderr_writer,
        mock_checker,
        null,
    );
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "Firewall-only mode") != null);
}

test "start verification failure detected by allow-only mock evaluator" {
    const outcome = try onboarding.verifyShellEvaluation(
        std.testing.allocator,
        null,
        shell_eval.mockDaemonAllowEvaluator,
    );
    try std.testing.expect(!outcome.passed());
}

test "start protection mode prompt selects default via injected reader" {
    tui.theme.resetCache();
    var buf: [4096]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    var in = std.Io.Reader.fixed("enter\n");

    const options = [_]tui.prompt.SelectionOption{
        .{ .label = "Command Guard", .description = "hook-based shell blocking", .id = "command_guard" },
        .{ .label = "Firewall", .description = "sandboxed `orca run` sessions", .id = "firewall" },
        .{ .label = "Maximum Protection", .description = "both (recommended)", .id = "maximum_protection" },
    };

    const idx = try tui.prompt.select(std.testing.io, std.testing.allocator, &w, &options, 2, "Choose your protection mode", &in);
    try std.testing.expectEqual(@as(?usize, 2), idx);
}
