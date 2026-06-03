const std = @import("std");

const cli = @import("mod.zig");
const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");
const doctor = @import("doctor.zig");
const init = @import("init.zig");
const setup = @import("setup.zig");

pub fn command(cwd: std.fs.Dir, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var preset: ?[]const u8 = null;
    var auto = false;

    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        const arg = argv[index];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            _ = try help.writeCommand(stdout, "quickstart");
            return exit_codes.success;
        }
        if (std.mem.eql(u8, arg, "--auto")) {
            auto = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--preset")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("orca quickstart: --preset requires a preset name.\n");
                return exit_codes.usage;
            }
            preset = argv[index];
            continue;
        }
        try stderr.print("orca quickstart: unknown option '{s}'.\n", .{arg});
        return exit_codes.usage;
    }

    try stdout.writeAll("🚀 Orca Quickstart\n");
    try stdout.writeAll("==================\n\n");

    // Step 1: Doctor (always run for visibility)
    try stdout.writeAll("→ Step 1: Checking your system...\n");
    const doctor_code = try doctor.command(&.{}, stdout, stderr);
    if (doctor_code != exit_codes.success) {
        try stdout.writeAll("\n⚠️  Doctor found issues. Please fix them and re-run quickstart.\n");
        return doctor_code;
    }
    try stdout.writeAll("✓ System check complete.\n\n");

    // Step 2: Init (skip if policy already present at cwd)
    const policy_exists = blk: {
        cwd.access(".orca/policy.yaml", .{}) catch break :blk false;
        break :blk true;
    };

    if (!policy_exists) {
        try stdout.writeAll("→ Step 2: Creating your first policy...\n");
        const init_argv = if (preset) |p|
            &[_][]const u8{ "--preset", p }
        else
            &[_][]const u8{};
        const init_code = try init.command(cwd, init_argv, stdout, stderr);
        if (init_code != exit_codes.success) {
            try stdout.writeAll("\n⚠️  Policy creation failed.\n");
            return init_code;
        }
        try stdout.writeAll("✓ Policy created.\n\n");
    } else {
        try stdout.writeAll("→ Step 2: Policy already exists. Skipping init.\n\n");
    }

    // Step 3: Setup
    // We deliberately do *not* duplicate TTY detection here.
    // We pass the user's explicit --auto intent (or lack thereof) down to setup.
    // setup owns the decision: on TTY with no --auto it will enter guided mode.
    const setup_argv = if (auto)
        &[_][]const u8{"--auto"}
    else
        &[_][]const u8{};
    try stdout.writeAll("→ Step 3: Setting up agent host integrations...\n");
    const setup_code = try setup.command(cwd, setup_argv, stdout, stderr);
    if (setup_code != exit_codes.success) {
        try stdout.writeAll("\n⚠️  Setup finished with warnings. You may need to run `orca setup` manually.\n");
        // Do not fail the whole quickstart for plugin-level issues (per spec)
    } else {
        try stdout.writeAll("✓ Setup complete.\n\n");
    }

    // Celebration + concrete next steps
    try stdout.writeAll("🎉 You're all set!\n");
    try stdout.writeAll("\nStart protecting your sessions:\n");
    try stdout.writeAll("  orca run -- <your-command>\n");
    try stdout.writeAll("\nUseful next steps:\n");
    try stdout.writeAll("  orca doctor        Check system status\n");
    try stdout.writeAll("  orca replay        Review past sessions\n");
    try stdout.writeAll("  orca help run      Learn about running commands\n");

    return exit_codes.success;
}
