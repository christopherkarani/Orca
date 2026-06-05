const std = @import("std");

const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");
const doctor = @import("doctor.zig");
const setup = @import("setup.zig");
const onboarding = @import("onboarding.zig");

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

    try stdout.writeAll("Orca Quickstart\n");
    try stdout.writeAll("==================\n\n");

    try stdout.writeAll("-> Step 1: Checking your system...\n");
    const doctor_code = try doctor.command(io, &.{}, stdout, stderr);
    if (doctor_code != exit_codes.success) {
        try stdout.writeAll("\nDoctor found issues. Please fix them and re-run quickstart.\n");
        return doctor_code;
    }
    try stdout.writeAll("System check complete.\n\n");

    if (!onboarding.policyExists(io, workspace_root)) {
        try stdout.writeAll("-> Step 2: Creating your first policy...\n");
        const init_code = try onboarding.ensurePolicy(io, cwd, workspace_root, flags.preset, stdout, stderr, .{
            .missing = "",
            .exists = null,
        });
        if (init_code != exit_codes.success) {
            try stdout.writeAll("\nPolicy creation failed.\n");
            return init_code;
        }
        try stdout.writeAll("Policy created.\n\n");
    } else {
        try stdout.writeAll("-> Step 2: Policy already exists. Skipping init.\n\n");
    }

    try stdout.writeAll("-> Step 3: Setting up agent host integrations...\n");
    const setup_argv = if (flags.auto or !onboarding.interactiveSetupDesired(io))
        &[_][]const u8{ "--auto", "--preset", flags.preset }
    else
        &[_][]const u8{ "--preset", flags.preset };
    const setup_code = try setup.command(io, cwd, setup_argv, stdout, stderr);
    if (setup_code != exit_codes.success) {
        try stdout.writeAll("\nSetup finished with warnings. You may need to run `orca setup` manually.\n");
    } else {
        try stdout.writeAll("Setup complete.\n\n");
    }

    try stdout.writeAll("You're all set!\n");
    try stdout.writeAll("\nStart protecting your sessions:\n");
    try stdout.writeAll("  orca run -- <your-command>\n");
    try stdout.writeAll("\nUseful next steps:\n");
    try stdout.writeAll("  orca doctor        Check system status\n");
    try stdout.writeAll("  orca replay        Review past sessions\n");
    try stdout.writeAll("  orca help run      Learn about running commands\n");

    return exit_codes.success;
}
