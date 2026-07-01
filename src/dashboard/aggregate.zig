const std = @import("std");

const core_api = @import("orca_core").api;
const core = @import("orca_core").core;
const feed_writer = @import("../cli/feed_writer.zig");
const rust_visibility = @import("../cli/rust_visibility.zig");

pub const Workspace = struct {
    root: []u8,
    last_seen_at: []u8,
    last_host: ?[]u8,
    policy_present: bool,

    pub fn deinit(self: *Workspace, allocator: std.mem.Allocator) void {
        allocator.free(self.root);
        allocator.free(self.last_seen_at);
        if (self.last_host) |host| allocator.free(host);
        self.* = undefined;
    }
};

pub fn loadWorkspaces(io: std.Io, allocator: std.mem.Allocator, dashboard_root: []const u8) ![]Workspace {
    const registry_path = try std.fs.path.join(allocator, &.{ dashboard_root, feed_writer.workspace_registry_file_name });
    defer allocator.free(registry_path);
    const text = std.Io.Dir.cwd().readFileAlloc(io, registry_path, allocator, .limited(512 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return &[_]Workspace{},
        else => return err,
    };
    defer allocator.free(text);
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, text, .{}) catch return &[_]Workspace{};
    defer parsed.deinit();
    if (parsed.value != .object) return &[_]Workspace{};
    const workspaces_value = parsed.value.object.get("workspaces") orelse return &[_]Workspace{};
    if (workspaces_value != .array) return &[_]Workspace{};

    var workspaces: std.ArrayList(Workspace) = .empty;
    errdefer {
        for (workspaces.items) |*workspace| workspace.deinit(allocator);
        workspaces.deinit(allocator);
    }
    for (workspaces_value.array.items) |item| {
        if (workspaces.items.len >= feed_writer.max_registered_workspaces) break;
        if (item != .object) continue;
        const root = stringField(item.object, "root") orelse continue;
        const last_seen_at = stringField(item.object, "last_seen_at") orelse continue;
        const last_host = stringField(item.object, "last_host");
        const policy_present = boolField(item.object, "policy_present");
        var workspace = try dupeWorkspace(allocator, root, last_seen_at, last_host, policy_present);
        workspaces.append(allocator, workspace) catch |err| {
            workspace.deinit(allocator);
            return err;
        };
    }
    return workspaces.toOwnedSlice(allocator);
}

fn dupeWorkspace(
    allocator: std.mem.Allocator,
    root: []const u8,
    last_seen_at: []const u8,
    last_host: ?[]const u8,
    policy_present: bool,
) !Workspace {
    const owned_root = try allocator.dupe(u8, root);
    errdefer allocator.free(owned_root);
    const owned_last_seen_at = try allocator.dupe(u8, last_seen_at);
    errdefer allocator.free(owned_last_seen_at);
    const owned_last_host = if (last_host) |host| try allocator.dupe(u8, host) else null;
    errdefer if (owned_last_host) |host| allocator.free(host);
    return .{
        .root = owned_root,
        .last_seen_at = owned_last_seen_at,
        .last_host = owned_last_host,
        .policy_present = policy_present,
    };
}

pub fn deinitWorkspaces(allocator: std.mem.Allocator, workspaces: []Workspace) void {
    for (workspaces) |*workspace| workspace.deinit(allocator);
    allocator.free(workspaces);
}

pub fn writeWorkspacesJson(writer: anytype, workspaces: []const Workspace) !void {
    try writer.writeByte('[');
    for (workspaces, 0..) |workspace, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.writeAll("{\"root\":");
        try core.util.writeJsonString(writer, workspace.root);
        try writer.writeAll(",\"last_seen_at\":");
        try core.util.writeJsonString(writer, workspace.last_seen_at);
        try writer.writeAll(",\"last_host\":");
        if (workspace.last_host) |host| try core.util.writeJsonString(writer, host) else try writer.writeAll("null");
        try writer.writeAll(",\"policy_present\":");
        try writer.writeAll(if (workspace.policy_present) "true" else "false");
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
}

const SessionRef = struct {
    workspace_root: []const u8,
    id: []u8,
};

pub fn writeSessionsJson(
    io: std.Io,
    allocator: std.mem.Allocator,
    writer: anytype,
    workspaces: []const Workspace,
    max_count: usize,
) !void {
    var sessions: std.ArrayList(SessionRef) = .empty;
    defer {
        for (sessions.items) |session| allocator.free(session.id);
        sessions.deinit(allocator);
    }
    for (workspaces) |workspace| {
        const sessions_root = std.fs.path.join(allocator, &.{ workspace.root, ".orca", "sessions" }) catch continue;
        defer allocator.free(sessions_root);
        var dir = std.Io.Dir.cwd().openDir(io, sessions_root, .{ .iterate = true }) catch continue;
        defer dir.close(io);
        var iterator = dir.iterate();
        var workspace_count: usize = 0;
        while (workspace_count < max_count) {
            const entry = iterator.next(io) catch break orelse break;
            if (entry.kind != .directory) continue;
            if (core.session.validateSessionIdText(entry.name)) |_| {} else |_| continue;
            try sessions.append(allocator, .{ .workspace_root = workspace.root, .id = try allocator.dupe(u8, entry.name) });
            workspace_count += 1;
        }
    }
    std.mem.sort(SessionRef, sessions.items, {}, newestSessionFirst);

    try writer.writeByte('[');
    const count = @min(max_count, sessions.items.len);
    for (sessions.items[0..count], 0..) |session, index| {
        if (index > 0) try writer.writeByte(',');
        try writeSessionSummaryJson(io, allocator, writer, session.workspace_root, session.id);
    }
    try writer.writeByte(']');
}

pub fn writeGlobalFeedJson(
    io: std.Io,
    allocator: std.mem.Allocator,
    writer: anytype,
    dashboard_root: []const u8,
    max_count: usize,
    denied_only: bool,
) !void {
    const loaded = feed_writer.loadGlobalRecent(io, allocator, dashboard_root, max_count) catch {
        try writer.writeAll("[]");
        return;
    };
    defer {
        for (loaded) |*item| item.deinit(allocator);
        allocator.free(loaded);
    }
    std.mem.sort(feed_writer.LoadedFeedRecord, loaded, {}, newestFeedFirst);
    try writer.writeByte('[');
    var written: usize = 0;
    for (loaded) |item| {
        if (denied_only and !std.mem.eql(u8, item.record.decision, "deny")) continue;
        if (written > 0) try writer.writeByte(',');
        try writeFeedRecordJson(writer, item.record);
        written += 1;
    }
    try writer.writeByte(']');
}

fn writeSessionSummaryJson(
    io: std.Io,
    allocator: std.mem.Allocator,
    writer: anytype,
    workspace_root: []const u8,
    session_id: []const u8,
) !void {
    try writer.writeAll("{\"id\":");
    try core.util.writeJsonString(writer, session_id);
    try writer.writeAll(",\"timestamp\":");
    try core.util.writeJsonString(writer, session_id);
    try writer.writeAll(",\"workspace_root\":");
    try core.util.writeJsonString(writer, workspace_root);
    try writer.writeAll(",\"host\":null");
    if (core_api.loadReplay(io, allocator, workspace_root, .{ .session = session_id, .only_denied = true, .verify = false })) |loaded| {
        var replay = loaded;
        defer replay.deinit();
        try writer.writeAll(",\"command\":");
        try core.util.writeJsonString(writer, replay.command_display);
        try writer.writeAll(",\"policy\":");
        try core.util.writeJsonString(writer, replay.policy);
        try writer.writeAll(",\"status\":");
        try core.util.writeJsonString(writer, replay.status_display);
        try writer.print(",\"denied_count\":{d},\"verified\":{}", .{ replay.events.len, replay.verified });
    } else |err| {
        if (err == error.OutOfMemory) return err;
        try writer.writeAll(",\"command\":null,\"policy\":null,\"status\":\"unreadable\",\"denied_count\":0,\"verified\":false");
    }
    try writer.writeByte('}');
}

fn writeFeedRecordJson(writer: anytype, record: rust_visibility.RustShellFeedRecord) !void {
    try writer.writeAll("{\"timestamp\":");
    try core.util.writeJsonString(writer, record.timestamp);
    try writer.writeAll(",\"workspace_root\":");
    try core.util.writeJsonString(writer, record.workspace_root);
    try writer.writeAll(",\"event_type\":");
    try core.util.writeJsonString(writer, record.event_type);
    try writer.writeAll(",\"decision\":");
    try core.util.writeJsonString(writer, record.decision);
    try writer.writeAll(",\"decision_source\":");
    try core.util.writeJsonString(writer, record.decision_source);
    try writer.writeAll(",\"event_source\":");
    try core.util.writeJsonString(writer, record.event_source);
    try writer.writeAll(",\"host\":");
    if (record.host) |host| try core.util.writeJsonString(writer, host) else try writer.writeAll("null");
    try writer.writeAll(",\"daemon_status\":");
    try core.util.writeJsonString(writer, record.daemon_status);
    try writer.writeAll(",\"pack_id\":");
    if (record.pack_id) |pack| try core.util.writeJsonString(writer, pack) else try writer.writeAll("null");
    try writer.writeAll(",\"severity\":");
    if (record.severity) |severity| try core.util.writeJsonString(writer, severity) else try writer.writeAll("null");
    try writer.writeAll(",\"reason\":");
    try core.util.writeJsonString(writer, record.reason);
    try writer.writeAll(",\"remediation\":");
    if (record.remediation) |remediation| try core.util.writeJsonString(writer, remediation) else try writer.writeAll("null");
    try writer.writeAll(",\"target\":");
    try core.util.writeJsonString(writer, record.target_summary);
    try writer.writeAll(",\"session_id\":");
    if (record.session_id) |session_id| try core.util.writeJsonString(writer, session_id) else try writer.writeAll("null");
    try writer.writeAll(",\"verified\":");
    try writer.writeAll(if (record.verified) "true" else "false");
    try writer.writeByte('}');
}

fn newestSessionFirst(_: void, lhs: SessionRef, rhs: SessionRef) bool {
    return std.mem.order(u8, lhs.id, rhs.id) == .gt;
}

fn newestFeedFirst(_: void, lhs: feed_writer.LoadedFeedRecord, rhs: feed_writer.LoadedFeedRecord) bool {
    return std.mem.order(u8, lhs.record.timestamp, rhs.record.timestamp) == .gt;
}

fn stringField(object: std.json.ObjectMap, name: []const u8) ?[]const u8 {
    const value = object.get(name) orelse return null;
    if (value != .string) return null;
    return value.string;
}

fn boolField(object: std.json.ObjectMap, name: []const u8) bool {
    const value = object.get(name) orelse return false;
    return value == .bool and value.bool;
}
