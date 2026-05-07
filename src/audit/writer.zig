const std = @import("std");

const core = @import("../core/mod.zig");
const hash_chain = @import("hash_chain.zig");
const replay = @import("replay.zig");

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

    pub fn openExisting(allocator: std.mem.Allocator, workspace_root: []const u8, session_id_text: []const u8) !SessionWriter {
        const aegis_dir = try std.fs.path.join(allocator, &.{ workspace_root, ".aegis" });
        defer allocator.free(aegis_dir);
        const sessions_dir = try std.fs.path.join(allocator, &.{ aegis_dir, "sessions" });
        defer allocator.free(sessions_dir);
        const session_dir_path = try std.fs.path.join(allocator, &.{ sessions_dir, session_id_text });
        errdefer allocator.free(session_dir_path);

        const events_path = try std.fs.path.join(allocator, &.{ session_dir_path, "events.jsonl" });
        defer allocator.free(events_path);
        const state = try readExistingState(allocator, events_path);

        var events_file = try std.fs.cwd().openFile(events_path, .{ .mode = .read_write });
        errdefer events_file.close();
        try events_file.seekFromEnd(0);

        var session_id: core.session.SessionId = .{ .value = undefined, .len = 0 };
        if (session_id_text.len > session_id.value.len) return error.InvalidSessionId;
        @memcpy(session_id.value[0..session_id_text.len], session_id_text);
        session_id.len = session_id_text.len;

        return .{
            .allocator = allocator,
            .workspace_root = workspace_root,
            .session_id = session_id,
            .session_dir_path = session_dir_path,
            .events_file = events_file,
            .previous_hash = state.previous_hash,
            .event_count = state.event_count,
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

    pub fn sessionDirPath(self: *const SessionWriter) []const u8 {
        return self.session_dir_path;
    }

    pub fn writeLastPointer(self: *const SessionWriter) !void {
        const aegis_dir = try std.fs.path.join(self.allocator, &.{ self.workspace_root, ".aegis" });
        defer self.allocator.free(aegis_dir);
        try std.fs.cwd().makePath(aegis_dir);

        const tmp_name = try std.fmt.allocPrint(self.allocator, "last.tmp.{s}", .{self.session_id.slice()});
        defer self.allocator.free(tmp_name);
        const tmp_path = try std.fs.path.join(self.allocator, &.{ aegis_dir, tmp_name });
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

const ExistingState = struct {
    previous_hash: ?hash_chain.HashHex,
    event_count: usize,
};

fn readExistingState(allocator: std.mem.Allocator, events_path: []const u8) !ExistingState {
    const text = try std.fs.cwd().readFileAlloc(allocator, events_path, core.limits.max_mcp_message_len);
    defer allocator.free(text);
    var previous_hash: ?hash_chain.HashHex = null;
    var event_count: usize = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, line, .{});
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidEventSchema;
        const object = parsed.value.object;
        const previous_value = object.get("previous_hash") orelse return error.InvalidEventSchema;
        var expected_previous: ?[]const u8 = null;
        if (previous_hash) |*hash| expected_previous = hash[0..];
        if (!jsonNullableStringEquals(previous_value, expected_previous)) return error.InvalidEventSchema;

        const canonical = try replay.canonicalFromJsonValue(allocator, parsed.value);
        defer allocator.free(canonical);
        const computed = hash_chain.eventHash(expected_previous, canonical);
        const hash_value = object.get("event_hash") orelse return error.InvalidEventSchema;
        if (hash_value != .string or !std.mem.eql(u8, hash_value.string, &computed)) return error.InvalidEventSchema;
        var hash: hash_chain.HashHex = undefined;
        @memcpy(hash[0..], &computed);
        previous_hash = hash;
        event_count += 1;
    }
    return .{ .previous_hash = previous_hash, .event_count = event_count };
}

fn jsonNullableStringEquals(value: std.json.Value, expected: ?[]const u8) bool {
    if (expected) |string| return value == .string and std.mem.eql(u8, value.string, string);
    return value == .null;
}

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

test "session writer persists redacted synthetic secrets before JSONL write" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    const ts = core.time.Timestamp.fromUnixSeconds(1_777_983_130);
    const session: core.session.Session = .{
        .id = try core.session.generateSessionId(ts),
        .started_at = ts,
        .command = "echo",
        .args = &.{"fake_secret_value"},
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
        .event_type = .process_launch,
        .actor = .{ .kind = .aegis, .display = "aegis" },
        .target = .{ .kind = .command, .value = "echo fake_secret_value" },
    };

    var session_writer = try SessionWriter.init(std.testing.allocator, session);
    defer session_writer.deinit();
    try session_writer.appendEvent(ev);

    const rel_events_path = try std.fs.path.join(std.testing.allocator, &.{ ".aegis", "sessions", session.id.slice(), "events.jsonl" });
    defer std.testing.allocator.free(rel_events_path);
    const events = try tmp.dir.readFileAlloc(std.testing.allocator, rel_events_path, 4096);
    defer std.testing.allocator.free(events);

    try std.testing.expect(std.mem.indexOf(u8, events, "fake_secret_value") == null);
    try std.testing.expect(std.mem.indexOf(u8, events, "[REDACTED:secret:synthetic_secret:sha256:") != null);
}

test "session writer redacts embedded secret assignments in command targets" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    const ts = core.time.Timestamp.fromUnixSeconds(1_777_983_130);
    const session: core.session.Session = .{
        .id = try core.session.generateSessionId(ts),
        .started_at = ts,
        .command = "/bin/echo",
        .args = &.{"OPENAI_API_KEY=sk-fakeSyntheticOpenAIKey1234567890"},
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
        .event_type = .process_launch,
        .actor = .{ .kind = .aegis, .display = "aegis" },
        .target = .{ .kind = .command, .value = "/bin/echo OPENAI_API_KEY=sk-fakeSyntheticOpenAIKey1234567890" },
    };

    var session_writer = try SessionWriter.init(std.testing.allocator, session);
    defer session_writer.deinit();
    try session_writer.appendEvent(ev);

    const rel_events_path = try std.fs.path.join(std.testing.allocator, &.{ ".aegis", "sessions", session.id.slice(), "events.jsonl" });
    defer std.testing.allocator.free(rel_events_path);
    const events = try tmp.dir.readFileAlloc(std.testing.allocator, rel_events_path, 4096);
    defer std.testing.allocator.free(events);

    try std.testing.expect(std.mem.indexOf(u8, events, "sk-fakeSyntheticOpenAIKey") == null);
    try std.testing.expect(std.mem.indexOf(u8, events, "[REDACTED:env:OPENAI_API_KEY:sha256:") != null);
}

test "openExisting fails closed on tampered existing event chain" {
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

    {
        var session_writer = try SessionWriter.init(std.testing.allocator, session);
        defer session_writer.deinit();
        try session_writer.appendEvent(ev);
    }

    const rel_events_path = try std.fs.path.join(std.testing.allocator, &.{ ".aegis", "sessions", session.id.slice(), "events.jsonl" });
    defer std.testing.allocator.free(rel_events_path);
    var events = try tmp.dir.readFileAlloc(std.testing.allocator, rel_events_path, 4096);
    defer std.testing.allocator.free(events);
    const pos = std.mem.indexOf(u8, events, "\"kind\":\"session\"").? + "\"kind\":\"".len;
    @memcpy(events[pos .. pos + "session".len], "command");
    {
        const file = try tmp.dir.createFile(rel_events_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(events);
    }

    try std.testing.expectError(error.InvalidEventSchema, SessionWriter.openExisting(std.testing.allocator, root, session.id.slice()));
}
