const std = @import("std");

const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");
const doctor = @import("doctor.zig");
const setup = @import("setup.zig");
const onboarding = @import("onboarding.zig");
const readiness = @import("readiness.zig");
const build_options = @import("build_options");
const tui = @import("../tui/mod.zig");

pub fn command(io: std.Io, cwd: std.Io.Dir, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            _ = try help.writeCommand(io, stdout, "quickstart");
            return exit_codes.success;
        }
    }

    const flags = onboarding.parseFlags(argv, stderr, "orca quickstart", false) catch |err| switch (err) {
        error.Usage => return exit_codes.usage,
        else => return err,
    };

    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const workspace_root = try onboarding.resolveWorkspaceRootFromCwd(io, allocator, cwd);
    defer allocator.free(workspace_root);

    try tui.render.banner(io, stdout, build_options.version, "quickstart");
    try stdout.writeAll("\n");

    // Human doctor report (exit 0 without --check). One daemon probe after; receipts use cached assessment.
    try tui.render.stepLine(io, stdout, .active, "Step 1 — System check", null, 0);
    _ = try doctor.command(io, &.{}, stdout, stderr);

    const daemon_check = try onboarding.checkDaemonHealth(allocator, true, null);
    if (daemon_check.status != .compatible) {
        try tui.render.stepLine(io, stdout, .failed, "Step 1 — System check", "Daemon not ready.", 0);
        try stdout.writeAll("\n");
        try stdout.print("{s}\n", .{daemon_check.detail});
        try stdout.print("{s}\n", .{daemon_check.remediation});
        // Cached assessment — do not re-probe daemon/policy for the receipt.
        try writeReceipt(stdout, readiness.assess(daemon_check.status, false, false), false);
        try stdout.writeAll("Fix the daemon, then re-run `orca quickstart` (or `orca doctor --check`).\n");
        return exit_codes.general;
    }
    try tui.render.stepLine(io, stdout, .done, "Step 1 — System check", "daemon compatible", 0);
    try stdout.writeAll("\n");

    if (!onboarding.policyExists(io, workspace_root)) {
        try tui.render.stepLine(io, stdout, .active, "Step 2 — Policy", "Creating your first policy...", 0);
        const init_code = try onboarding.ensurePolicy(io, cwd, workspace_root, flags.preset, stdout, stderr, .{
            .missing = "",
            .exists = null,
        });
        if (init_code != exit_codes.success) {
            try tui.render.stepLine(io, stdout, .failed, "Step 2 — Policy", "Policy creation failed.", 0);
            try writeReceipt(stdout, readiness.assess(daemon_check.status, false, false), false);
            return init_code;
        }
        try tui.render.stepLine(io, stdout, .done, "Step 2 — Policy", "created", 0);
    } else {
        try tui.render.stepLine(io, stdout, .done, "Step 2 — Policy", "already exists — skipping init", 0);
    }

    // Single policy validity check after ensure/skip.
    var policy = try readiness.assessWorkspacePolicy(io, allocator, workspace_root);
    defer policy.deinit(allocator);
    const core = readiness.assess(daemon_check.status, policy.present, policy.valid);
    if (!core.ready) {
        try stdout.writeAll("\n");
        try writeReceipt(stdout, core, false);
        try stdout.writeAll("Policy missing or invalid. Fix with `orca init` / policy edits, then re-run `orca status --check`.\n");
        return exit_codes.general;
    }
    try stdout.writeAll("\n");

    try tui.render.stepLine(io, stdout, .active, "Step 3 — Host integrations", "running setup...", 0);
    const setup_argv = if (flags.auto or !onboarding.interactiveSetupDesired(io))
        &[_][]const u8{ "--auto", "--preset", flags.preset, "--embedded" }
    else
        &[_][]const u8{ "--preset", flags.preset, "--embedded" };
    const setup_code = try setup.command(io, cwd, setup_argv, stdout, stderr);
    if (setup_code != exit_codes.success) {
        try tui.render.stepLine(io, stdout, .failed, "Step 3 — Host integrations", "setup finished with warnings", 0);
        try stdout.writeAll("\n");
        // Core ready (cached); hosts failed — do not claim global success.
        try writeReceipt(stdout, core, true);
        try stdout.writeAll("Host integrations need attention; do not treat hosts as fully protected.\n");
        try stdout.writeAll("Re-check with: orca status --check\n");
        return setup_code;
    }
    try tui.render.stepLine(io, stdout, .done, "Step 3 — Host integrations", "complete", 0);
    try stdout.writeAll("\n");

    // Core gates already proved ready; no second assess (would be dead-code re-eval).
    try writeReceipt(stdout, core, true);
    try stdout.writeAll("Core protection is ready (daemon + policy). Host integrations reported above may still need setup.\n");
    try stdout.writeAll("\nStart protecting your sessions:\n");
    try stdout.writeAll("  orca run -- <your-command>\n");
    try stdout.writeAll("\nUseful next steps:\n");
    try stdout.writeAll("  orca status --check   Automation readiness check\n");
    try stdout.writeAll("  orca doctor --check   Deep diagnostic with exit contract\n");
    try stdout.writeAll("  orca help run         Learn about running commands\n");

    return exit_codes.success;
}

fn writeReceipt(stdout: anytype, a: readiness.Assessment, hosts_note: bool) !void {
    var buf: [192]u8 = undefined;
    const line = a.formatReceipt(&buf);
    try stdout.print("{s}", .{line});
    if (hosts_note) {
        try stdout.writeAll(" | hosts: see setup output above");
    }
    try stdout.writeAll("\n");
}

test "quickstart step labels render with brand banner" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var stdout_buf: [16384]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try command(std.testing.io, tmp.dir, &.{ "--auto" }, &stdout_writer, &stderr_writer);
    const output = stdout_writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "\u{1F6E1}  Orca") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Step 1 — System check") != null);

    if (code != exit_codes.success) {
        try std.testing.expect(std.mem.indexOf(u8, output, "Core protection is ready") == null);
        try std.testing.expect(std.mem.indexOf(u8, output, "daemon:") != null or std.mem.indexOf(u8, output, "Daemon not ready") != null);
    } else {
        try std.testing.expect(std.mem.indexOf(u8, output, "Step 2 — Policy") != null);
        try std.testing.expect(std.mem.indexOf(u8, output, "Step 3 — Host integrations") != null);
        try std.testing.expect(std.mem.indexOf(u8, output, "daemon:") != null);
    }
}

test "quickstart receipt does not claim ready when core readiness fails" {
    const a = readiness.assess(.unavailable, false, false);
    try std.testing.expect(!a.ready);
    var buf: [128]u8 = undefined;
    const line = a.formatReceipt(&buf);
    try std.testing.expect(std.mem.indexOf(u8, line, "not ready") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "Core protection is ready") == null);
}
