const std = @import("std");

const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");
const doctor = @import("doctor.zig");
const setup = @import("setup.zig");
const onboarding = @import("onboarding.zig");
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

    try tui.render.stepLine(io, stdout, .active, "Step 1 — System check", null, 0);
    const doctor_code = try doctor.command(io, &.{}, stdout, stderr);
    if (doctor_code != exit_codes.success) {
        try tui.render.stepLine(io, stdout, .failed, "Step 1 — System check", "Doctor found issues.", 0);
        try stdout.writeAll("\nFix the issues above and re-run `orca quickstart`.\n");
        return doctor_code;
    }
    try tui.render.stepLine(io, stdout, .done, "Step 1 — System check", "passed", 0);
    try stdout.writeAll("\n");

    if (!onboarding.policyExists(io, workspace_root)) {
        try tui.render.stepLine(io, stdout, .active, "Step 2 — Policy", "Creating your first policy...", 0);
        const init_code = try onboarding.ensurePolicy(io, cwd, workspace_root, flags.preset, stdout, stderr, .{
            .missing = "",
            .exists = null,
        });
        if (init_code != exit_codes.success) {
            try tui.render.stepLine(io, stdout, .failed, "Step 2 — Policy", "Policy creation failed.", 0);
            return init_code;
        }
        try tui.render.stepLine(io, stdout, .done, "Step 2 — Policy", "created", 0);
    } else {
        try tui.render.stepLine(io, stdout, .done, "Step 2 — Policy", "already exists — skipping init", 0);
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
    } else {
        try tui.render.stepLine(io, stdout, .done, "Step 3 — Host integrations", "complete", 0);
    }
    try stdout.writeAll("\n");

    try stdout.writeAll("Core protection is ready. Host integrations reported above may still need setup.\n");
    try stdout.writeAll("\nStart protecting your sessions:\n");
    try stdout.writeAll("  orca run -- <your-command>\n");
    try stdout.writeAll("\nUseful next steps:\n");
    try stdout.writeAll("  orca doctor        Check system status\n");
    try stdout.writeAll("  orca replay        Review past sessions\n");
    try stdout.writeAll("  orca help run      Learn about running commands\n");

    return exit_codes.success;
}

test "quickstart step labels render with brand banner" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try command(std.testing.io, tmp.dir, &.{ "--auto" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "\u{1F6E1}  Orca") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Step 1 — System check") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Step 2 — Policy") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Step 3 — Host integrations") != null);
}
