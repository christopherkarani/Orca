//! Minimal allowlist matching for the Zig shell engine.
//! Exact-command and prefix entries; full Rust allowlist semantics deferred.

const std = @import("std");

pub const Entry = struct {
    pattern: []const u8,
    prefix: bool = false,
};

pub const Layered = struct {
    entries: []const Entry = &.{},

    pub fn allows(self: Layered, command: []const u8) bool {
        const trimmed = std.mem.trim(u8, command, " \t\r\n");
        for (self.entries) |entry| {
            if (entry.prefix) {
                if (std.mem.startsWith(u8, trimmed, entry.pattern)) return true;
            } else if (std.mem.eql(u8, trimmed, entry.pattern)) {
                return true;
            }
        }
        return false;
    }
};

test "allowlist exact and prefix" {
    const layered: Layered = .{
        .entries = &.{
            .{ .pattern = "git status" },
            .{ .pattern = "npm run ", .prefix = true },
        },
    };
    try std.testing.expect(layered.allows("git status"));
    try std.testing.expect(layered.allows("npm run test"));
    try std.testing.expect(!layered.allows("git reset --hard"));
}
