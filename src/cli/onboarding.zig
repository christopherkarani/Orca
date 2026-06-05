const std = @import("std");

const core = @import("orca_core").core;
const supervisor = core.supervisor;

const exit_codes = @import("exit_codes.zig");
const init = @import("init.zig");
const plugin = @import("plugin.zig");

pub const default_preset = "generic-agent";

/// Agent hosts wired during setup / quickstart integration.
pub const supported_hosts = [_][]const u8{ "codex", "claude", "opencode", "openclaw", "hermes" };

pub const Flags = struct {
    auto: bool = false,
    preset: []const u8 = default_preset,
};

pub const EnsurePolicyMessages = struct {
    missing: []const u8,
    exists: ?[]const u8 = null,
};

pub fn resolveWorkspaceRoot(io: std.Io, allocator: std.mem.Allocator) ![]u8 {
    return resolveWorkspaceRootFromCwd(io, allocator, std.Io.Dir.cwd());
}

/// Resolves the Orca workspace root starting from a caller-provided working directory.
pub fn resolveWorkspaceRootFromCwd(io: std.Io, allocator: std.mem.Allocator, cwd: std.Io.Dir) ![]u8 {
    const cwd_path = try cwd.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(cwd_path);
    return supervisor.resolveWorkspaceRoot(io, allocator, null, cwd_path) catch try allocator.dupe(u8, cwd_path);
}

pub fn policyPath(allocator: std.mem.Allocator, workspace_root: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ workspace_root, ".orca", "policy.yaml" });
}

pub fn policyExists(io: std.Io, workspace_root: []const u8) bool {
    const page_alloc = std.heap.page_allocator;
    const path = policyPath(page_alloc, workspace_root) catch return false;
    defer page_alloc.free(path);
    return plugin.fileExistsAbsolute(io, path);
}

/// Creates `.orca/policy.yaml` when missing. Never passes `--quiet` so init prints next steps.
pub fn ensurePolicy(
    io: std.Io,
    cwd: std.Io.Dir,
    workspace_root: []const u8,
    preset: []const u8,
    stdout: anytype,
    stderr: anytype,
    messages: EnsurePolicyMessages,
) !u8 {
    if (policyExists(io, workspace_root)) {
        if (messages.exists) |text| try stdout.writeAll(text);
        return exit_codes.success;
    }

    try stdout.writeAll(messages.missing);
    const init_argv = &[_][]const u8{ "--preset", preset };
    return init.command(io, cwd, init_argv, stdout, stderr);
}

/// Guided setup when both stdin and stdout are TTYs (matches quickstart auto-setup gate).
pub fn interactiveSetupDesired(io: std.Io) bool {
    return (std.Io.File.stdin().isTty(io) catch false) and (std.Io.File.stdout().isTty(io) catch false);
}

/// Parses `--auto`, `--yes` (optional alias), and `--preset` for setup-like commands.
pub fn parseFlags(argv: []const []const u8, stderr: anytype, command_label: []const u8, yes_is_auto: bool) !Flags {
    var flags: Flags = .{};
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        const arg = argv[index];
        if (std.mem.eql(u8, arg, "--auto")) {
            flags.auto = true;
            continue;
        }
        if (yes_is_auto and std.mem.eql(u8, arg, "--yes")) {
            flags.auto = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--preset")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.print("{s}: --preset requires a preset name.\n", .{command_label});
                return error.Usage;
            }
            flags.preset = argv[index];
            continue;
        }
        try stderr.print("{s}: unknown option '{s}'.\n", .{ command_label, arg });
        return error.Usage;
    }
    return flags;
}

test "onboarding policyPath and policyExists" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    try std.testing.expect(!policyExists(std.testing.io, root));

    const path = try policyPath(std.testing.allocator, root);
    defer std.testing.allocator.free(path);
    try std.testing.expect(std.mem.endsWith(u8, path, ".orca/policy.yaml"));

    try tmp.dir.createDirPath(std.testing.io, ".orca");
    {
        const file = try tmp.dir.createFile(std.testing.io, ".orca/policy.yaml", .{});
        defer file.close(std.testing.io);
        try file.writeStreamingAll(std.testing.io, "version: 1\nmode: observe\n");
    }

    try std.testing.expect(policyExists(std.testing.io, root));
}

test "onboarding parseFlags accepts preset and auto" {
    var stderr_buf: [256]u8 = undefined;
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const flags = try parseFlags(
        &.{ "--auto", "--preset", "strict-local" },
        &stderr_writer,
        "orca setup",
        true,
    );
    try std.testing.expect(flags.auto);
    try std.testing.expectEqualStrings("strict-local", flags.preset);
}
