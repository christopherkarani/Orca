const std = @import("std");
const builtin = @import("builtin");

const core = @import("orca_core").core;
const env_util = @import("../env_util.zig");
const rust_visibility = @import("rust_visibility.zig");

pub const feed_dir_name = "feed";
pub const feed_file_name = "rust_shell_decisions.jsonl";
pub const global_events_file_name = "events.jsonl";
pub const workspace_registry_file_name = "workspaces.json";
pub const max_registered_workspaces: usize = 200;

pub fn feedPath(allocator: std.mem.Allocator, workspace_root: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ workspace_root, ".orca", feed_dir_name, feed_file_name });
}

pub fn appendRecord(io: std.Io, allocator: std.mem.Allocator, workspace_root: []const u8, record: rust_visibility.RustShellFeedRecord) !void {
    const feed_dir = try std.fs.path.join(allocator, &.{ workspace_root, ".orca", feed_dir_name });
    defer allocator.free(feed_dir);
    try std.Io.Dir.cwd().createDirPath(io, feed_dir);

    const feed_path = try feedPath(allocator, workspace_root);
    defer allocator.free(feed_path);

    try appendRecordAtPath(io, allocator, feed_path, record);
}

fn appendRecordAtPath(io: std.Io, allocator: std.mem.Allocator, path: []const u8, record: rust_visibility.RustShellFeedRecord) !void {
    var file = try std.Io.Dir.cwd().createFile(io, path, .{ .read = true, .truncate = false, .lock = .exclusive });
    defer file.close(io);
    const end_offset = (try file.stat(io)).size;
    var file_buf: [4096]u8 = undefined;
    var file_writer = file.writer(io, &file_buf);
    try file_writer.seekToUnbuffered(end_offset);

    var line: std.Io.Writer.Allocating = .init(allocator);
    defer line.deinit();
    try rust_visibility.writeFeedRecordJson(&line.writer, record);
    try line.writer.writeByte('\n');
    const bytes = try line.toOwnedSlice();
    defer allocator.free(bytes);
    try file_writer.interface.writeAll(bytes);
    try file_writer.interface.flush();
    try file.sync(io);
}

pub fn appendGlobalRecord(
    io: std.Io,
    allocator: std.mem.Allocator,
    dashboard_root: []const u8,
    record: rust_visibility.RustShellFeedRecord,
) !void {
    try std.Io.Dir.cwd().createDirPath(io, dashboard_root);

    const lock_path = try std.fs.path.join(allocator, &.{ dashboard_root, ".write.lock" });
    defer allocator.free(lock_path);
    const lock_file = try std.Io.Dir.cwd().createFile(io, lock_path, .{ .read = true });
    defer lock_file.close(io);
    try lock_file.lock(io, .exclusive);
    defer lock_file.unlock(io);

    const events_path = try std.fs.path.join(allocator, &.{ dashboard_root, global_events_file_name });
    defer allocator.free(events_path);
    try appendRecordAtPath(io, allocator, events_path, record);
    try updateWorkspaceRegistry(io, allocator, dashboard_root, record);
}

/// Best-effort GUI feed write. Feed persistence must not affect hook/run fail-closed behavior.
pub fn appendRecordBestEffort(io: std.Io, allocator: std.mem.Allocator, workspace_root: []const u8, record: rust_visibility.RustShellFeedRecord) void {
    appendRecord(io, allocator, workspace_root, record) catch {};
    if (processGlobalWritesDisabled()) return;
    const dashboard_root = resolveGlobalDashboardRoot(allocator) catch return;
    defer allocator.free(dashboard_root);
    appendGlobalRecord(io, allocator, dashboard_root, record) catch {};
}

pub fn processGlobalWritesDisabled() bool {
    if (builtin.is_test) return true;
    const value = std.c.getenv("ORCA_DISABLE_GLOBAL_DASHBOARD_FEED") orelse return false;
    return std.mem.eql(u8, std.mem.span(value), "1");
}

pub fn resolveGlobalDashboardRoot(allocator: std.mem.Allocator) ![]u8 {
    var env_map = try env_util.createProcessMap(allocator);
    defer env_map.deinit();
    const home = (try env_util.getOwned(&env_map, allocator, "HOME")) orelse return error.HomeDirectoryNotFound;
    defer allocator.free(home);
    return std.fs.path.join(allocator, &.{ home, ".orca", "dashboard" });
}

fn updateWorkspaceRegistry(
    io: std.Io,
    allocator: std.mem.Allocator,
    dashboard_root: []const u8,
    record: rust_visibility.RustShellFeedRecord,
) !void {
    const registry_path = try std.fs.path.join(allocator, &.{ dashboard_root, workspace_registry_file_name });
    defer allocator.free(registry_path);
    const existing = std.Io.Dir.cwd().readFileAlloc(io, registry_path, allocator, .limited(512 * 1024)) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    defer if (existing) |text| allocator.free(text);
    var parsed = if (existing) |text| std.json.parseFromSlice(std.json.Value, allocator, text, .{}) catch null else null;
    defer if (parsed) |*value| value.deinit();

    const policy_path = try std.fs.path.join(allocator, &.{ record.workspace_root, ".orca", "policy.yaml" });
    defer allocator.free(policy_path);
    const policy_present = blk: {
        std.Io.Dir.cwd().access(io, policy_path, .{}) catch break :blk false;
        break :blk true;
    };

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    try output.writer.writeAll("{\"workspaces\":[");
    try writeWorkspaceRegistration(&output.writer, record.workspace_root, record.timestamp, record.host, policy_present);
    var count: usize = 1;
    if (parsed) |value| {
        if (workspaceArray(value.value)) |items| {
            for (items) |item| {
                if (count >= max_registered_workspaces) break;
                const entry = readWorkspaceRegistration(item) orelse continue;
                if (std.mem.eql(u8, entry.root, record.workspace_root)) continue;
                try output.writer.writeByte(',');
                try writeWorkspaceRegistration(&output.writer, entry.root, entry.last_seen_at, entry.last_host, entry.policy_present);
                count += 1;
            }
        }
    }
    try output.writer.writeAll("]}\n");
    const bytes = try output.toOwnedSlice();
    defer allocator.free(bytes);

    const temp_path = try std.fs.path.join(allocator, &.{ dashboard_root, "workspaces.json.tmp" });
    defer allocator.free(temp_path);
    {
        const file = try std.Io.Dir.cwd().createFile(io, temp_path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, bytes);
        try file.sync(io);
    }
    try std.Io.Dir.renameAbsolute(temp_path, registry_path, io);
}

const WorkspaceRegistrationView = struct {
    root: []const u8,
    last_seen_at: []const u8,
    last_host: ?[]const u8,
    policy_present: bool,
};

fn workspaceArray(value: std.json.Value) ?[]std.json.Value {
    if (value != .object) return null;
    const workspaces = value.object.get("workspaces") orelse return null;
    if (workspaces != .array) return null;
    return workspaces.array.items;
}

fn readWorkspaceRegistration(value: std.json.Value) ?WorkspaceRegistrationView {
    if (value != .object) return null;
    const root = value.object.get("root") orelse return null;
    const last_seen_at = value.object.get("last_seen_at") orelse return null;
    if (root != .string or last_seen_at != .string) return null;
    const last_host_value = value.object.get("last_host");
    const last_host = if (last_host_value) |host| if (host == .string) host.string else null else null;
    const policy_value = value.object.get("policy_present");
    const policy_present = if (policy_value) |present| present == .bool and present.bool else false;
    return .{ .root = root.string, .last_seen_at = last_seen_at.string, .last_host = last_host, .policy_present = policy_present };
}

fn writeWorkspaceRegistration(
    writer: anytype,
    root: []const u8,
    last_seen_at: []const u8,
    last_host: ?[]const u8,
    policy_present: bool,
) !void {
    try writer.writeAll("{\"root\":");
    try core.util.writeJsonString(writer, root);
    try writer.writeAll(",\"last_seen_at\":");
    try core.util.writeJsonString(writer, last_seen_at);
    try writer.writeAll(",\"last_host\":");
    if (last_host) |host| try core.util.writeJsonString(writer, host) else try writer.writeAll("null");
    try writer.writeAll(",\"policy_present\":");
    try writer.writeAll(if (policy_present) "true" else "false");
    try writer.writeByte('}');
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

    return loadRecentFromPath(io, allocator, feed_path, workspace_root, max_count);
}

pub fn loadGlobalRecent(
    io: std.Io,
    allocator: std.mem.Allocator,
    dashboard_root: []const u8,
    max_count: usize,
) ![]LoadedFeedRecord {
    const events_path = try std.fs.path.join(allocator, &.{ dashboard_root, global_events_file_name });
    defer allocator.free(events_path);
    return loadRecentFromPath(io, allocator, events_path, null, max_count);
}

fn loadRecentFromPath(
    io: std.Io,
    allocator: std.mem.Allocator,
    path: []const u8,
    fallback_workspace_root: ?[]const u8,
    max_count: usize,
) ![]LoadedFeedRecord {
    const text = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(core.limits.max_audit_log_len)) catch |err| switch (err) {
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
        const record = try parseFeedRecord(allocator, owned_line, fallback_workspace_root);
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

fn parseFeedRecord(allocator: std.mem.Allocator, line: []const u8, fallback_workspace_root: ?[]const u8) !rust_visibility.RustShellFeedRecord {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, line, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidFeedRecord;

    const object = parsed.value.object;
    return .{
        .timestamp = try dupRequiredString(allocator, object, "timestamp"),
        .workspace_root = try dupWorkspaceRoot(allocator, object, fallback_workspace_root),
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

fn dupWorkspaceRoot(allocator: std.mem.Allocator, object: std.json.ObjectMap, fallback: ?[]const u8) ![]u8 {
    if (try dupOptionalString(allocator, object, "workspace_root")) |root| return root;
    if (fallback) |root| return allocator.dupe(u8, root);
    return error.InvalidFeedRecord;
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
        root,
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
    try std.testing.expectEqualStrings(root, loaded[0].record.workspace_root);
    try std.testing.expectEqualStrings("claude", loaded[0].record.host.?);
    try std.testing.expectEqualStrings("git", loaded[0].record.pack_id.?);
    try std.testing.expectEqualStrings("shell command (redacted)", loaded[0].record.target_summary);
    try std.testing.expect(std.mem.indexOf(u8, loaded[0].raw, "matched_text_preview") == null);
}

test "global feed append records workspace and updates registry" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const dashboard_root = try std.fs.path.join(std.testing.allocator, &.{ root, "home", ".orca", "dashboard" });
    defer std.testing.allocator.free(dashboard_root);

    var record = try rust_visibility.buildFeedRecordFromHookDecision(
        std.testing.allocator,
        std.testing.io,
        root,
        "codex",
        "healthy",
        "deny",
        "blocked by Orca policy",
        null,
        null,
        null,
        null,
        "request-1",
    );
    defer record.deinit(std.testing.allocator);

    try appendGlobalRecord(std.testing.io, std.testing.allocator, dashboard_root, record);
    try appendGlobalRecord(std.testing.io, std.testing.allocator, dashboard_root, record);

    const events_path = try std.fs.path.join(std.testing.allocator, &.{ dashboard_root, global_events_file_name });
    defer std.testing.allocator.free(events_path);
    const events = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, events_path, std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"workspace_root\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, root) != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"host\":\"codex\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "agent_host") == null);
    const loaded = try loadGlobalRecent(std.testing.io, std.testing.allocator, dashboard_root, 4);
    defer {
        for (loaded) |*item| item.deinit(std.testing.allocator);
        std.testing.allocator.free(loaded);
    }
    try std.testing.expectEqual(@as(usize, 2), loaded.len);

    const registry_path = try std.fs.path.join(std.testing.allocator, &.{ dashboard_root, workspace_registry_file_name });
    defer std.testing.allocator.free(registry_path);
    const registry = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, registry_path, std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(registry);
    try std.testing.expect(std.mem.indexOf(u8, registry, root) != null);
    try std.testing.expect(std.mem.indexOf(u8, registry, "\"last_host\":\"codex\"") != null);
}
