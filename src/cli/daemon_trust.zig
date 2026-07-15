//! Path trust checks for `ORCA_DAEMON` overrides.

const std = @import("std");
const builtin = @import("builtin");

pub const EnvOverrideTrust = enum {
    trusted,
    untrusted_world_writable,
    untrusted_symlink,
    untrusted_stat_unavailable,
};

/// Assess whether an `ORCA_DAEMON` path is safe to execute.
/// Stat failures are treated as untrusted (fail-closed for env overrides).
pub fn assessEnvOverridePath(io: std.Io, path: []const u8) EnvOverrideTrust {
    if (builtin.os.tag == .windows) return .trusted;
    const link_stat = std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false }) catch return .untrusted_stat_unavailable;
    if (link_stat.kind == .sym_link) return .untrusted_symlink;
    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch return .untrusted_stat_unavailable;
    if (isWorldWritable(stat.permissions.toMode())) return .untrusted_world_writable;
    return if (hasWorldWritableAncestor(io, path)) .untrusted_world_writable else .trusted;
}

fn isWorldWritable(mode: std.posix.mode_t) bool {
    return (mode & 0o002) != 0;
}

fn hasWorldWritableAncestor(io: std.Io, path: []const u8) bool {
    var ancestor = std.fs.path.dirname(path);
    while (ancestor) |directory| {
        const stat = std.Io.Dir.cwd().statFile(io, directory, .{}) catch return true;
        if (isWorldWritable(stat.permissions.toMode())) return true;
        const parent = std.fs.path.dirname(directory);
        // Guard against root self-parent edge cases (dirname("/") may be null or "/").
        if (parent) |p| {
            if (std.mem.eql(u8, p, directory)) break;
        }
        ancestor = parent;
    }
    if (std.fs.path.isAbsolute(path)) return false;
    const cwd_stat = std.Io.Dir.cwd().statFile(io, ".", .{}) catch return true;
    return isWorldWritable(cwd_stat.permissions.toMode());
}

pub fn isEnvOverrideUntrusted(io: std.Io, path: []const u8) bool {
    return assessEnvOverridePath(io, path) != .trusted;
}

test "assessEnvOverridePath detects world-writable binary path" {
    if (builtin.os.tag == .windows) return;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const file = try tmp.dir.createFile(std.testing.io, "orca-daemon", .{});
    defer file.close(std.testing.io);
    try file.writeStreamingAll(std.testing.io, "#!/bin/sh\nexit 0\n");

    const path = try tmp.dir.realPathFileAlloc(std.testing.io, "orca-daemon", std.testing.allocator);
    defer std.testing.allocator.free(path);

    try tmp.dir.setFilePermissions(std.testing.io, "orca-daemon", std.Io.File.Permissions.fromMode(0o755), .{});
    try std.testing.expectEqual(.trusted, assessEnvOverridePath(std.testing.io, path));

    try tmp.dir.setFilePermissions(std.testing.io, "orca-daemon", std.Io.File.Permissions.fromMode(0o777), .{});
    try std.testing.expectEqual(.untrusted_world_writable, assessEnvOverridePath(std.testing.io, path));
}

test "assessEnvOverridePath rejects a binary beneath a world-writable directory" {
    if (builtin.os.tag == .windows) return;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "unsafe");
    try tmp.dir.setFilePermissions(std.testing.io, "unsafe", std.Io.File.Permissions.fromMode(0o777), .{});

    const file = try tmp.dir.createFile(std.testing.io, "unsafe/orca-daemon", .{});
    defer file.close(std.testing.io);
    try file.writeStreamingAll(std.testing.io, "#!/bin/sh\nexit 0\n");
    try tmp.dir.setFilePermissions(std.testing.io, "unsafe/orca-daemon", std.Io.File.Permissions.fromMode(0o755), .{});

    const path = try tmp.dir.realPathFileAlloc(std.testing.io, "unsafe/orca-daemon", std.testing.allocator);
    defer std.testing.allocator.free(path);
    try std.testing.expectEqual(.untrusted_world_writable, assessEnvOverridePath(std.testing.io, path));
}

test "assessEnvOverridePath rejects a safe-path symlink to an unsafe target" {
    if (builtin.os.tag == .windows) return;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "safe");
    try tmp.dir.createDirPath(std.testing.io, "unsafe");
    try tmp.dir.setFilePermissions(std.testing.io, "unsafe", std.Io.File.Permissions.fromMode(0o777), .{});

    const target = try tmp.dir.createFile(std.testing.io, "unsafe/orca-daemon", .{});
    defer target.close(std.testing.io);
    try target.writeStreamingAll(std.testing.io, "#!/bin/sh\nexit 0\n");
    try tmp.dir.setFilePermissions(std.testing.io, "unsafe/orca-daemon", std.Io.File.Permissions.fromMode(0o755), .{});

    const unsafe_target = try tmp.dir.realPathFileAlloc(std.testing.io, "unsafe/orca-daemon", std.testing.allocator);
    defer std.testing.allocator.free(unsafe_target);
    const safe_link = try tmp.dir.realPathFileAlloc(std.testing.io, "safe", std.testing.allocator);
    defer std.testing.allocator.free(safe_link);
    const link_path = try std.fs.path.join(std.testing.allocator, &.{ safe_link, "orca-daemon" });
    defer std.testing.allocator.free(link_path);
    try std.Io.Dir.cwd().symLink(std.testing.io, unsafe_target, link_path, .{});

    try std.testing.expectEqual(.untrusted_symlink, assessEnvOverridePath(std.testing.io, link_path));
}

test "assessEnvOverridePath treats missing path as stat-unavailable" {
    if (builtin.os.tag == .windows) return;
    const missing = "/tmp/orca-daemon-trust-missing-deadbeef";
    try std.testing.expectEqual(.untrusted_stat_unavailable, assessEnvOverridePath(std.testing.io, missing));
}
