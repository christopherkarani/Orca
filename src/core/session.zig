const std = @import("std");
const errors = @import("errors.zig");
const limits = @import("limits.zig");
const platform = @import("platform.zig");
const time = @import("time.zig");
const types = @import("types.zig");
const util = @import("util.zig");

pub const SessionId = struct {
    value: [limits.max_session_id_len]u8,
    len: usize,

    pub fn slice(self: *const SessionId) []const u8 {
        return self.value[0..self.len];
    }
};

pub const Session = struct {
    id: SessionId,
    started_at: time.Timestamp,
    ended_at: ?time.Timestamp = null,
    command: []const u8,
    args: []const []const u8,
    workspace_root: []const u8,
    policy_hash: ?[]const u8 = null,
    mode: types.Mode,
    platform: platform.Os,
};

pub fn generateSessionId(now: time.Timestamp) errors.AegisError!SessionId {
    var id: SessionId = .{
        .value = undefined,
        .len = 0,
    };
    var timestamp_buf: [32]u8 = undefined;
    const timestamp = now.formatFilenameSafe(&timestamp_buf) catch return errors.AegisError.SessionCreateFailed;
    var suffix_buf: [4]u8 = undefined;
    const suffix = util.randomHexSuffix(&suffix_buf) catch return errors.AegisError.SessionCreateFailed;
    const written = std.fmt.bufPrint(&id.value, "{s}_{s}", .{ timestamp, suffix }) catch return errors.AegisError.SessionCreateFailed;
    id.len = written.len;
    return id;
}

test "session id generation produces readable unique-ish ids" {
    const ts = time.Timestamp.fromUnixSeconds(1_777_983_130);
    const first = try generateSessionId(ts);
    const second = try generateSessionId(ts);

    try std.testing.expect(first.len > 0);
    try std.testing.expect(first.len <= first.value.len);
    try std.testing.expect(std.mem.startsWith(u8, first.slice(), "2026-05-05T12-12-10Z_"));
    try std.testing.expect(!std.mem.eql(u8, first.slice(), second.slice()));
}

test "session model can be constructed from core types" {
    const id = try generateSessionId(time.Timestamp.fromUnixSeconds(1_777_983_130));
    const session: Session = .{
        .id = id,
        .started_at = time.Timestamp.fromUnixSeconds(1_777_983_130),
        .command = "aegis",
        .args = &.{"run"},
        .workspace_root = "/tmp/aegis",
        .mode = .observe,
        .platform = platform.detectOs(),
    };
    try std.testing.expectEqualStrings("aegis", session.command);
    try std.testing.expectEqual(types.Mode.observe, session.mode);
}
