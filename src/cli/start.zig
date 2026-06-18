const std = @import("std");

const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");
const style = @import("style.zig");
const onboarding = @import("onboarding.zig");
const plugin = @import("plugin.zig");
const interactive = @import("interactive.zig");
const shell_eval = @import("shell_eval.zig");

pub fn command(io: std.Io, cwd: std.Io.Dir, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            _ = try help.writeCommand(io, stdout, "start");
            return exit_codes.success;
        }
    }

    if (argv.len == 0) {
        if (onboarding.interactiveSetupDesired(io)) {
            return runStart(io, cwd, .{}, stdout, stderr, null, null);
        }
        try stderr.writeAll("orca start: non-interactive terminal requires --auto.\n");
        try stderr.writeAll("Use: orca start --auto [--protection maximum] [--hosts codex,claude]\n");
        return exit_codes.usage;
    }

    const flags = onboarding.parseStartFlags(argv, stderr) catch |err| switch (err) {
        error.Usage => return exit_codes.usage,
        else => return err,
    };

    if (!flags.auto and !onboarding.interactiveSetupDesired(io)) {
        try stderr.writeAll("orca start: non-interactive terminal requires --auto.\n");
        try stderr.writeAll("Use: orca start --auto [--protection maximum] [--hosts codex,claude]\n");
        return exit_codes.usage;
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

    try stdout.writeAll("Orca Start\n");
    try stdout.writeAll("==========\n\n");
    try stdout.writeAll(
        \\Orca will configure protection for your workspace, verify the Rust daemon when needed,
        \\install host integrations you choose, and run safe verification checks.
        \\Existing policy files are kept unless you run `orca init --force`.
        \\
        \\
    );

    const workspace_root = try onboarding.resolveWorkspaceRootFromCwd(io, allocator, cwd);
    defer allocator.free(workspace_root);

    const protection = try resolveProtectionMode(io, flags, stdout, stderr);
    try stdout.print("Protection mode: {s}\n  {s}\n\n", .{ protection.label(), protection.description() });

    var doctor_report = try plugin.collectPluginDoctorReport(io, allocator);
    defer plugin.deinitPluginDoctorReport(&doctor_report, allocator);

    const host_statuses = try onboarding.collectHostStatuses(io, allocator, doctor_report);
    defer allocator.free(host_statuses);

    const selected_hosts = try resolveSelectedHosts(io, allocator, flags, host_statuses, stdout, stderr);
    defer if (selected_hosts.owned) onboarding.deinitHostList(allocator, selected_hosts.items);

    var failures: usize = 0;
    var protection_active = false;

    try printStepHeader(stdout, "Policy");
    const policy_existed = onboarding.policyExists(io, workspace_root);
    const policy_code = try onboarding.ensurePolicy(io, cwd, workspace_root, flags.preset, stdout, stderr, .{
        .missing = "  Creating .orca/policy.yaml...\n",
        .exists = "  Policy already exists — leaving it unchanged.\n",
    });
    if (policy_code != exit_codes.success) {
        try printStepResult(stdout, false, "Policy setup failed.");
        failures += 1;
    } else {
        try printStepResult(stdout, true, if (policy_existed) "Existing policy preserved." else "Policy created.");
    }

    try printStepHeader(stdout, "Daemon");
    var daemon_check: onboarding.DaemonCheck = undefined;
    if (protection.needsCommandGuard()) {
        daemon_check = try onboarding.checkDaemonHealth(allocator, true, daemon_check_fn);
        const daemon_ok = daemon_check.status == .compatible;
        protection_active = protection_active or daemon_ok;
        try stdout.print("  Status: {s}\n", .{daemon_check.status.label()});
        try stdout.print("  Detail: {s}\n", .{daemon_check.detail});
        try printStepResult(stdout, daemon_ok, if (daemon_ok) "Daemon ready for Command Guard." else daemon_check.remediation);
        if (!daemon_ok) failures += 1;
    } else {
        daemon_check = try onboarding.checkDaemonHealth(allocator, false, daemon_check_fn);
        try stdout.print("  Status: {s} (optional for Firewall-only)\n", .{daemon_check.status.label()});
        try stdout.print("  Detail: {s}\n", .{daemon_check.detail});
        try printStepResult(stdout, true, "Firewall mode does not require daemon for basic `orca run` sessions.");
        protection_active = onboarding.verifyFirewallReady(io, workspace_root);
    }

    var configured_hosts: std.ArrayList([]const u8) = .empty;
    defer {
        for (configured_hosts.items) |host| allocator.free(host);
        configured_hosts.deinit(allocator);
    }

    try printStepHeader(stdout, "Host integrations");
    if (selected_hosts.items.len == 0) {
        try printStepResult(stdout, true, "No hosts selected. You can run `orca setup` later.");
    } else if (protection.needsCommandGuard()) {
        const host_failures = try installSelectedHosts(io, allocator, selected_hosts.items, stdout, &configured_hosts);
        failures += host_failures;
        protection_active = protection_active and host_failures == 0;
        if (host_failures == 0) {
            try printStepResult(stdout, true, "Selected host integrations configured.");
        } else {
            try printStepResult(stdout, false, "One or more host integrations failed. Run `orca plugin doctor`.");
        }
    } else {
        try stdout.writeAll("  Skipping hook installs for Firewall-only mode.\n");
        try stdout.writeAll("  Use `orca run -- <agent>` to launch protected sessions.\n");
        try printStepResult(stdout, true, "Firewall path ready.");
        protection_active = onboarding.verifyFirewallReady(io, workspace_root);
    }

    var verification: ?onboarding.VerificationOutcome = null;
    if (!flags.skip_verify and failures == 0) {
        try printStepHeader(stdout, "Verification");
        if (protection.needsCommandGuard() and daemon_check.status != .compatible) {
            try printStepResult(stdout, false, "Skipped shell verification because the daemon is unavailable.");
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
            try stdout.print("  Safe command ({s}): {s}\n", .{ onboarding.safe_verification_command, if (verification.?.safe_allowed) "allowed" else "FAILED" });
            try stdout.print("  Dangerous command ({s}): {s}\n", .{ onboarding.dangerous_verification_command, if (verification.?.dangerous_denied) "denied" else "FAILED" });
            if (verification.?.hook_verified) |hook_ok| {
                try stdout.print("  Hook path: {s}\n", .{if (hook_ok) "verified" else "FAILED"});
            }
            if (verification.?.firewall_ready) |firewall_ok| {
                try stdout.print("  Firewall policy: {s}\n", .{if (firewall_ok) "ready" else "missing"});
            }
            const verify_ok = verification.?.passed();
            protection_active = protection_active and verify_ok;
            try printStepResult(stdout, verify_ok, verification.?.detail);
            if (!verify_ok) failures += 1;
        }
    } else if (flags.skip_verify) {
        try stdout.writeAll("\nVerification skipped (--skip-verify).\n");
    }

    try stdout.writeAll("\n");
    if (failures > 0) {
        try writeFailureSummary(io, stdout, protection, selected_hosts.items, configured_hosts.items, daemon_check, verification, protection_active);
        return exit_codes.general;
    }

    try writeSuccessSummary(io, stdout, protection, selected_hosts.items, configured_hosts.items, daemon_check, verification);
    return exit_codes.success;
}

fn resolveProtectionMode(io: std.Io, flags: onboarding.StartFlags, stdout: anytype, stderr: anytype) !onboarding.ProtectionMode {
    if (flags.protection) |mode| return mode;
    if (flags.auto) return onboarding.defaultProtectionMode();

    try stdout.writeAll("Choose your protection mode:\n");
    try stdout.writeAll("  1) Command Guard — hook-based shell blocking\n");
    try stdout.writeAll("  2) Firewall — sandboxed `orca run` sessions\n");
    try stdout.writeAll("  3) Maximum Protection — both (recommended)\n\n");
    try stdout.writeAll("Enter 1, 2, or 3 [default 3]: ");
    try flushIfSupported(stdout);

    const stdin_file = std.Io.File.stdin();
    var stdin_reader_buf: [64]u8 = undefined;
    var stdin_reader = stdin_file.reader(io, &stdin_reader_buf);
    const raw = stdin_reader.interface.takeDelimiterExclusive('\n') catch |err| switch (err) {
        error.EndOfStream => "",
        else => return err,
    };
    const input = std.mem.trim(u8, raw, " \t\r");
    if (input.len == 0 or std.mem.eql(u8, input, "3")) return onboarding.defaultProtectionMode();
    if (std.mem.eql(u8, input, "1")) return .command_guard;
    if (std.mem.eql(u8, input, "2")) return .firewall;
    if (std.mem.eql(u8, input, "3")) return .maximum_protection;
    try stderr.writeAll("orca start: invalid selection; using Maximum Protection.\n");
    return onboarding.defaultProtectionMode();
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
    stderr: anytype,
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

    try stdout.writeAll("\nDetected agent hosts:\n");
    var selection_items = try allocator.alloc(interactive.SelectionItem, host_statuses.len);
    defer allocator.free(selection_items);

    var visible: usize = 0;
    for (host_statuses) |status| {
        if (!status.detected) continue;
        const marker = if (status.installed) " (installed)" else "";
        var label_buf: [64]u8 = undefined;
        const label = std.fmt.bufPrint(&label_buf, "{s}{s}", .{ status.name, marker }) catch status.name;
        selection_items[visible] = .{
            .label = label,
            .checked = true,
            .id = status.name,
        };
        visible += 1;
    }

    const stdin_file = std.Io.File.stdin();
    var stdin_reader_buf: [256]u8 = undefined;
    var stdin_reader = stdin_file.reader(io, &stdin_reader_buf);
    var result = try interactive.runMultiSelect(allocator, selection_items[0..visible], stdout, &stdin_reader.interface);
    defer interactive.deinitMultiSelectResult(&result, allocator);

    var list: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (list.items) |item| allocator.free(item);
        list.deinit(allocator);
    }
    for (result.items) |item| {
        if (!item.checked) continue;
        const host_name = item.id orelse item.label;
        try list.append(allocator, try allocator.dupe(u8, host_name));
    }
    _ = stderr;
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
        if (code == 0) {
            try stdout.writeAll("installed\n");
            try configured_out.append(allocator, try allocator.dupe(u8, host_name));
        } else {
            try stdout.print("failed (exit {d})\n", .{code});
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

fn printStepHeader(stdout: anytype, title: []const u8) !void {
    try stdout.print("\n[{s}]\n", .{title});
}

fn printStepResult(stdout: anytype, ok: bool, detail: []const u8) !void {
    const glyph = if (ok) "✓" else "✗";
    try stdout.print("  {s} {s}\n", .{ glyph, detail });
}

fn writeSuccessSummary(
    io: std.Io,
    stdout: anytype,
    protection: onboarding.ProtectionMode,
    selected_hosts: []const []const u8,
    configured_hosts: []const []const u8,
    daemon_check: onboarding.DaemonCheck,
    verification: ?onboarding.VerificationOutcome,
) !void {
    try style.maybeColor(io, stdout, style.Style.green, style.Glyph.party ++ " Orca is configured!");
    try stdout.writeAll("\n\nSummary\n-------\n");
    try stdout.print("Protection: {s}\n", .{protection.label()});
    if (protection.needsCommandGuard()) {
        if (configured_hosts.len == 0) {
            try stdout.writeAll("Configured hosts: none\n");
        } else {
            try stdout.writeAll("Configured hosts: ");
            for (configured_hosts, 0..) |host, i| {
                if (i > 0) try stdout.writeAll(", ");
                try stdout.writeAll(host);
            }
            try stdout.writeAll("\n");
        }
    } else {
        try stdout.writeAll("Configured hosts: hooks skipped (Firewall-only mode)\n");
        if (selected_hosts.len > 0) {
            try stdout.writeAll("Detected hosts: ");
            for (selected_hosts, 0..) |host, i| {
                if (i > 0) try stdout.writeAll(", ");
                try stdout.writeAll(host);
            }
            try stdout.writeAll("\n");
        }
    }
    try stdout.print("Daemon: {s}\n", .{daemon_check.status.label()});
    if (verification) |v| {
        try stdout.print("Verification: {s}\n", .{if (v.passed()) "passed" else "failed"});
    }
    try stdout.writeAll("\nTry it manually:\n");
    if (protection.needsCommandGuard()) {
        try stdout.writeAll("  orca hook hermes pre_tool_call < tests/fixtures/hook-danger.json\n");
    }
    if (protection.needsFirewall()) {
        try stdout.writeAll("  orca run -- echo hello\n");
    }
    try stdout.writeAll("\nDiagnostics:\n");
    try stdout.writeAll("  orca doctor\n");
    try stdout.writeAll("  orca version\n");
    try stdout.writeAll("\nAudit feed / GUI:\n");
    try stdout.writeAll("  orca dashboard\n");
    try stdout.writeAll("  orca replay\n");
    try stdout.writeAll("\nRe-run onboarding safely:\n");
    try stdout.writeAll("  orca start\n");
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
    try std.testing.expect(std.mem.indexOf(u8, output, "Orca Start") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Firewall") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Orca is configured") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "Firewall policy: ready") != null);
}

test "start verification failure detected by allow-only mock evaluator" {
    const outcome = try onboarding.verifyShellEvaluation(
        std.testing.allocator,
        null,
        shell_eval.mockDaemonAllowEvaluator,
    );
    try std.testing.expect(!outcome.passed());
}
