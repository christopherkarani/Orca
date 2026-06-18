const std = @import("std");

const core = @import("orca_core").core;
const rust_visibility = @import("rust_visibility.zig");

pub const feed_dir_name = "feed";
pub const feed_file_name = "rust_shell_decisions.jsonl";

pub fn feedPath(allocator: std.mem.Allocator, workspace_root: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ workspace_root, ".orca", feed_dir_name, feed_file_name });
}

pub fn appendRecord(io: std.Io, allocator: std.mem.Allocator, workspace_root: []const u8, record: rust_visibility.RustShellFeedRecord) !void {
    const feed_dir = try std.fs.path.join(allocator, &.{ workspace_root, ".orca", feed_dir_name });
    defer allocator.free(feed_dir);
    try std.Io.Dir.cwd().createDirPath(io, feed_dir);

    const feed_path = try feedPath(allocator, workspace_root);
    defer allocator.free(feed_path);

    var file = try std.Io.Dir.cwd().createFile(io, feed_path, .{ .read = true });
    defer file.close(io);
    const end_offset = (try file.stat(io)).size;
    var seek_buf: [1]u8 = undefined;
    var end_writer = file.writer(io, &seek_buf);
    try end_writer.seekToUnbuffered(end_offset);

    var line: std.Io.Writer.Allocating = .init(allocator);
    defer line.deinit();
    try rust_visibility.writeFeedRecordJson(&line.writer, record);
    try line.writer.writeByte('\n');
    const bytes = try line.toOwnedSlice();
    defer allocator.free(bytes);
    try file.writeStreamingAll(io, bytes);
    try file.sync(io);
}

/// Best-effort GUI feed write. Feed persistence must not affect hook/run fail-closed behavior.
pub fn appendRecordBestEffort(io: std.Io, allocator: std.mem.Allocator, workspace_root: []const u8, record: rust_visibility.RustShellFeedRecord) void {
    appendRecord(io, allocator, workspace_root, record) catch {};
}

pub const LoadedFeedRecord = struct {
    raw: []u8,
    record: rust_visibility.RustShellFeedRecord,

    pub fn deinit(self: *LoadedFeedRecord, allocator: std.mem.Allocator) void {
        allocator.free(self.raw);
        self.record.deinit(allocator);
        self.* = undefined;
    }
};

pub fn loadRecent(
    io: std.Io,
    allocator: std.mem.Allocator,
    workspace_root: []const u8,
    max_count: usize,
) ![]LoadedFeedRecord {
    const feed_path = feedPath(allocator, workspace_root) catch return &[_]LoadedFeedRecord{};
    defer allocator.free(feed_path);

    const text = std.Io.Dir.cwd().readFileAlloc(io, feed_path, allocator, .limited(core.limits.max_audit_log_len)) catch |err| switch (err) {
        error.FileNotFound => return &[_]LoadedFeedRecord{},
        else => return err,
    };
    defer allocator.free(text);

    var lines = std.mem.splitScalar(u8, text, '\n');
    var stack: std.ArrayList(LoadedFeedRecord) = .empty;
    errdefer {
        for (stack.items) |*item| item.deinit(allocator);
        stack.deinit(allocator);
    }

    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const owned_line = try allocator.dupe(u8, line);
        errdefer allocator.free(owned_line);
        const record = try parseFeedRecord(allocator, owned_line);
        try stack.append(allocator, .{ .raw = owned_line, .record = record });
    }

    if (stack.items.len <= max_count) return try stack.toOwnedSlice(allocator);

    const start = stack.items.len - max_count;
    const out = try allocator.alloc(LoadedFeedRecord, max_count);
    for (stack.items[start..], 0..) |item, index| {
        out[index] = item;
    }
    for (stack.items[0..start]) |*item| item.deinit(allocator);
    allocator.free(stack.items);
    return out;
}

fn parseFeedRecord(allocator: std.mem.Allocator, line: []const u8) !rust_visibility.RustShellFeedRecord {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, line, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidFeedRecord;

    const object = parsed.value.object;
    return .{
        .timestamp = try dupRequiredString(allocator, object, "timestamp"),
        .event_type = try dupRequiredString(allocator, object, "event_type"),
        .decision = try dupRequiredString(allocator, object, "decision"),
        .decision_source = try dupRequiredString(allocator, object, "decision_source"),
        .event_source = try dupRequiredString(allocator, object, "event_source"),
        .host = try dupOptionalString(allocator, object, "host"),
        .daemon_status = try dupRequiredString(allocator, object, "daemon_status"),
        .pack_id = try dupOptionalString(allocator, object, "pack_id"),
        .severity = try dupOptionalString(allocator, object, "severity"),
        .reason = try dupRequiredString(allocator, object, "reason"),
        .remediation = try dupOptionalString(allocator, object, "remediation"),
        .target_summary = try dupRequiredString(allocator, object, "target_summary"),
        .session_id = try dupOptionalString(allocator, object, "session_id"),
        .verified = readBoolField(object, "verified"),
    };
}

fn dupRequiredString(allocator: std.mem.Allocator, object: std.json.ObjectMap, field: []const u8) ![]u8 {
    const value = object.get(field) orelse return error.InvalidFeedRecord;
    if (value != .string) return error.InvalidFeedRecord;
    return try allocator.dupe(u8, value.string);
}

fn dupOptionalString(allocator: std.mem.Allocator, object: std.json.ObjectMap, field: []const u8) !?[]u8 {
    const value = object.get(field) orelse return null;
    if (value == .null) return null;
    if (value != .string) return error.InvalidFeedRecord;
    return try allocator.dupe(u8, value.string);
}

fn readBoolField(object: std.json.ObjectMap, field: []const u8) bool {
    const value = object.get(field) orelse return false;
    return value == .bool and value.bool;
}

test "feed writer round-trips rust shell decision without raw command" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var record = try rust_visibility.buildFeedRecordFromHookDecision(
        std.testing.allocator,
        std.testing.io,
        "claude",
        "healthy",
        "deny",
        "blocked by Orca policy rule: destructive_rm",
        "destructive_rm",
        "Critical",
        "Use a safer workflow.",
        "git",
        null,
    );
    defer record.deinit(std.testing.allocator);

    try appendRecord(std.testing.io, std.testing.allocator, root, record);

    const loaded = try loadRecent(std.testing.io, std.testing.allocator, root, 8);
    defer {
        for (loaded) |*item| item.deinit(std.testing.allocator);
        std.testing.allocator.free(loaded);
    }
    try std.testing.expectEqual(@as(usize, 1), loaded.len);
    try std.testing.expectEqualStrings("rust-daemon", loaded[0].record.decision_source);
    try std.testing.expectEqualStrings("hook", loaded[0].record.event_source);
    try std.testing.expectEqualStrings("git", loaded[0].record.pack_id.?);
    try std.testing.expectEqualStrings("shell command (redacted)", loaded[0].record.target_summary);
    try std.testing.expect(std.mem.indexOf(u8, loaded[0].raw, "matched_text_preview") == null);
}
