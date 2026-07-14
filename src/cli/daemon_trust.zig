//! Path trust checks for `ORCA_DAEMON` overrides.

const std = @import("std");
const builtin = @import("builtin");

pub const EnvOverrideTrust = enum {
    trusted,
    untrusted_world_writable,
    untrusted_stat_unavailable,
};

/// Assess whether an `ORCA_DAEMON` path is safe to execute.
/// Stat failures are treated as untrusted (fail-closed for env overrides).
pub fn assessEnvOverridePath(io: std.Io, path: []const u8) EnvOverrideTrust {
    if (builtin.os.tag == .windows) return .trusted;
    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch return .untrusted_stat_unavailable;
    return if ((stat.permissions.toMode() & 0o002) != 0)
        .untrusted_world_writable
    else
        .trusted;
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

test "assessEnvOverridePath treats missing path as stat-unavailable" {
    if (builtin.os.tag == .windows) return;
    const missing = "/tmp/orca-daemon-trust-missing-deadbeef";
    try std.testing.expectEqual(.untrusted_stat_unavailable, assessEnvOverridePath(std.testing.io, missing));
}