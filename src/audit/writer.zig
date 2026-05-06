const std = @import("std");

const core = @import("../core/mod.zig");
const hash_chain = @import("hash_chain.zig");

pub const SessionWriter = struct {
    allocator: std.mem.Allocator,
    workspace_root: []const u8,
    session_id: core.session.SessionId,
    session_dir_path: []u8,
    events_file: std.fs.File,
    previous_hash: ?hash_chain.HashHex = null,
    event_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator, session: core.session.Session) !SessionWriter {
        const aegis_dir = try std.fs.path.join(allocator, &.{ session.workspace_root, ".aegis" });
        defer allocator.free(aegis_dir);
        const sessions_dir = try std.fs.path.join(allocator, &.{ aegis_dir, "sessions" });
        defer allocator.free(sessions_dir);
        const session_dir_path = try std.fs.path.join(allocator, &.{ sessions_dir, session.id.slice() });
        errdefer allocator.free(session_dir_path);

        try std.fs.cwd().makePath(session_dir_path);
        const events_path = try std.fs.path.join(allocator, &.{ session_dir_path, "events.jsonl" });
        defer allocator.free(events_path);
        const events_file = try std.fs.cwd().createFile(events_path, .{ .exclusive = true });
        errdefer events_file.close();

        return .{
            .allocator = allocator,
            .workspace_root = session.workspace_root,
            .session_id = session.id,
            .session_dir_path = session_dir_path,
            .events_file = events_file,
        };
    }

    pub fn deinit(self: *SessionWriter) void {
        self.events_file.close();
        self.allocator.free(self.session_dir_path);
        self.* = undefined;
    }

    pub fn appendEvent(self: *SessionWriter, ev: core.event.Event) !void {
        var previous: ?[]const u8 = null;
        if (self.previous_hash) |*hash| previous = hash[0..];
        const canonical = try hash_chain.canonicalEventAlloc(self.allocator, ev, previous);
        defer self.allocator.free(canonical);
        const hash = hash_chain.eventHash(previous, canonical);

        var list: std.ArrayList(u8) = .empty;
        defer list.deinit(self.allocator);
        try hash_chain.writeEventJsonLine(list.writer(self.allocator), ev, previous, &hash);
        try self.events_file.writeAll(list.items);
        try self.events_file.sync();

        self.previous_hash = hash;
        self.event_count += 1;
    }

    pub fn finalHash(self: *const SessionWriter) ?[]const u8 {
        if (self.previous_hash) |*hash| return hash[0..];
        return null;
    }

    pub fn writeLastPointer(self: *const SessionWriter) !void {
        const aegis_dir = try std.fs.path.join(self.allocator, &.{ self.workspace_root, ".aegis" });
        defer self.allocator.free(aegis_dir);
        try std.fs.cwd().makePath(aegis_dir);

        const tmp_path = try std.fs.path.join(self.allocator, &.{ aegis_dir, "last.tmp" });
        defer self.allocator.free(tmp_path);
        const last_path = try std.fs.path.join(self.allocator, &.{ aegis_dir, "last" });
        defer self.allocator.free(last_path);

        {
            const file = try std.fs.cwd().createFile(tmp_path, .{});
            defer file.close();
            try file.writeAll(self.session_id.slice());
            try file.writeAll("\n");
            try file.sync();
        }
        std.fs.cwd().rename(tmp_path, last_path) catch |err| switch (err) {
            error.PathAlreadyExists => {
                std.fs.cwd().deleteFile(last_path) catch {};
                try std.fs.cwd().rename(tmp_path, last_path);
            },
            else => return err,
        };
    }
};

test "session writer creates directory and writes deterministic JSONL" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    const ts = core.time.Timestamp.fromUnixSeconds(1_777_983_130);
    const session: core.session.Session = .{
        .id = try core.session.generateSessionId(ts),
        .started_at = ts,
        .command = "echo",
        .args = &.{"hello"},
        .workspace_root = root,
        .mode = .observe,
        .platform = core.platform.detectOs(),
    };
    var event_id: core.event.EventId = .{ .value = undefined, .len = 0 };
    const event_id_text = try std.fmt.bufPrint(&event_id.value, "evt_000001", .{});
    event_id.len = event_id_text.len;
    const ev: core.event.Event = .{
        .session_id = session.id,
        .event_id = event_id,
        .timestamp = ts,
        .event_type = .session_start,
        .actor = .{ .kind = .aegis, .display = "aegis" },
        .target = .{ .kind = .session, .value = session.id.slice() },
    };

    var session_writer = try SessionWriter.init(std.testing.allocator, session);
    defer session_writer.deinit();
    try session_writer.appendEvent(ev);

    const rel_events_path = try std.fs.path.join(std.testing.allocator, &.{ ".aegis", "sessions", session.id.slice(), "events.jsonl" });
    defer std.testing.allocator.free(rel_events_path);
    const events = try tmp.dir.readFileAlloc(std.testing.allocator, rel_events_path, 4096);
    defer std.testing.allocator.free(events);

    try std.testing.expect(std.mem.indexOf(u8, events, "\"type\":\"session_start\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"event_hash\"") != null);
    try std.testing.expectEqual(@as(usize, 1), session_writer.event_count);
}
