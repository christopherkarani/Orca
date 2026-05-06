const std = @import("std");
const builtin = @import("builtin");

const event = @import("event.zig");
const platform = @import("platform.zig");
const session_mod = @import("session.zig");
const time = @import("time.zig");
const types = @import("types.zig");
const util = @import("util.zig");

pub const StdioBehavior = enum {
    inherit,
    ignore,
};

pub const RunConfig = struct {
    command: []const u8,
    args: []const []const u8 = &.{},
    workspace: ?[]const u8 = null,
    mode: types.Mode = .observe,
    session_name: ?[]const u8 = null,
    stdio: StdioBehavior = .inherit,
    before_spawn: ?StartHook = null,
    on_session_start: ?StartHook = null,
    on_event: ?EventHook = null,
};

pub const StartHook = struct {
    context: *anyopaque,
    callback: *const fn (context: *anyopaque, session: session_mod.Session) anyerror!void,
};

pub const EventHook = struct {
    context: *anyopaque,
    callback: *const fn (context: *anyopaque, ev: event.Event) anyerror!void,
};

pub const ChildStatus = union(enum) {
    exited: u8,
    signal: u32,
    stopped: u32,
    unknown: u32,

    pub fn exitCode(self: ChildStatus) i32 {
        return switch (self) {
            .exited => |code| code,
            .signal, .stopped, .unknown => 1,
        };
    }
};

pub const SessionResult = struct {
    session: session_mod.Session,
    status: ChildStatus,
    events: []event.Event,
    event_target_values: []const []const u8,
    allocator: std.mem.Allocator,

    pub fn exitCode(self: SessionResult) i32 {
        return self.status.exitCode();
    }

    pub fn deinit(self: *SessionResult) void {
        self.allocator.free(self.session.workspace_root);
        for (self.event_target_values) |target_value| {
            self.allocator.free(target_value);
        }
        self.allocator.free(self.event_target_values);
        self.allocator.free(self.events);
        self.* = undefined;
    }
};

pub fn run(allocator: std.mem.Allocator, config: RunConfig) !SessionResult {
    if (config.command.len == 0) return error.InvalidCommand;

    const workspace_root = try resolveWorkspaceRoot(allocator, config.workspace, ".");
    errdefer allocator.free(workspace_root);

    const started_at = time.Timestamp.now();
    var session: session_mod.Session = .{
        .id = try session_mod.generateSessionId(started_at),
        .started_at = started_at,
        .command = config.command,
        .args = config.args,
        .workspace_root = workspace_root,
        .session_name = config.session_name,
        .mode = config.mode,
        .platform = platform.detectOs(),
    };

    var events = try allocator.alloc(event.Event, 3);
    errdefer allocator.free(events);
    var event_target_values = try allocator.alloc([]const u8, 3);
    errdefer allocator.free(event_target_values);
    var owned_targets: usize = 0;
    errdefer {
        for (event_target_values[0..owned_targets]) |target_value| {
            allocator.free(target_value);
        }
    }
    events[0] = try makeOwnedTargetEvent(allocator, &event_target_values, &owned_targets, session, started_at, .session_start, .session, session.id.slice());

    const command_display = try commandDisplay(allocator, config.command, config.args);
    defer allocator.free(command_display);
    events[1] = try makeOwnedTargetEvent(allocator, &event_target_values, &owned_targets, session, started_at, .process_launch, .command, command_display);

    if (config.before_spawn) |hook| {
        try hook.callback(hook.context, session);
    }
    if (config.on_event) |hook| {
        try hook.callback(hook.context, events[0]);
        try hook.callback(hook.context, events[1]);
    }

    var argv = try allocator.alloc([]const u8, config.args.len + 1);
    defer allocator.free(argv);
    argv[0] = config.command;
    @memcpy(argv[1..], config.args);

    var child = std.process.Child.init(argv, allocator);
    child.cwd = workspace_root;
    switch (config.stdio) {
        .inherit => {
            child.stdin_behavior = .Inherit;
            child.stdout_behavior = .Inherit;
            child.stderr_behavior = .Inherit;
        },
        .ignore => {
            child.stdin_behavior = .Ignore;
            child.stdout_behavior = .Ignore;
            child.stderr_behavior = .Ignore;
        },
    }

    child.spawn() catch |err| switch (err) {
        error.FileNotFound => return error.CommandNotFound,
        else => return err,
    };
    child.waitForSpawn() catch |err| switch (err) {
        error.FileNotFound => return error.CommandNotFound,
        else => return err,
    };

    if (config.on_session_start) |hook| {
        hook.callback(hook.context, session) catch |err| {
            _ = child.kill() catch child.wait() catch {};
            return err;
        };
    }

    const term = try child.wait();

    const ended_at = time.Timestamp.now();
    session.ended_at = ended_at;
    const status = childStatusFromTerm(term);
    events[2] = try makeOwnedTargetEvent(allocator, &event_target_values, &owned_targets, session, ended_at, .session_exit, .session, session.id.slice());
    if (config.on_event) |hook| {
        try hook.callback(hook.context, events[2]);
    }

    return .{
        .session = session,
        .status = status,
        .events = events,
        .event_target_values = event_target_values,
        .allocator = allocator,
    };
}

fn commandDisplay(allocator: std.mem.Allocator, command: []const u8, args: []const []const u8) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try list.appendSlice(allocator, command);
    for (args) |arg| {
        try list.append(allocator, ' ');
        try list.appendSlice(allocator, arg);
    }
    return try list.toOwnedSlice(allocator);
}

pub fn resolveWorkspaceRoot(
    allocator: std.mem.Allocator,
    explicit_workspace: ?[]const u8,
    start_path: []const u8,
) ![]u8 {
    if (explicit_workspace) |workspace| {
        return try std.fs.cwd().realpathAlloc(allocator, workspace);
    }

    const fallback = try std.fs.cwd().realpathAlloc(allocator, start_path);
    errdefer allocator.free(fallback);
    var current = try allocator.dupe(u8, fallback);
    errdefer allocator.free(current);

    while (true) {
        const git_path = try std.fs.path.join(allocator, &.{ current, ".git" });
        defer allocator.free(git_path);

        if (hasGitMarker(git_path)) {
            allocator.free(fallback);
            return current;
        }

        const parent = std.fs.path.dirname(current) orelse {
            allocator.free(current);
            return fallback;
        };
        if (std.mem.eql(u8, parent, current)) {
            allocator.free(current);
            return fallback;
        }

        const next = try allocator.dupe(u8, parent);
        allocator.free(current);
        current = next;
    }
}

fn hasGitMarker(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn childStatusFromTerm(term: std.process.Child.Term) ChildStatus {
    return switch (term) {
        .Exited => |code| .{ .exited = code },
        .Signal => |signal| .{ .signal = signal },
        .Stopped => |signal| .{ .stopped = signal },
        .Unknown => |status| .{ .unknown = status },
    };
}

fn makeEvent(
    session: session_mod.Session,
    timestamp: time.Timestamp,
    event_type: event.EventType,
    target_kind: types.TargetKind,
    target_value: []const u8,
) !event.Event {
    return .{
        .session_id = session.id,
        .event_id = try event.generateEventId(timestamp),
        .timestamp = timestamp,
        .event_type = event_type,
        .actor = .{ .kind = .aegis, .display = "aegis" },
        .target = .{ .kind = target_kind, .value = target_value },
    };
}

fn makeOwnedTargetEvent(
    allocator: std.mem.Allocator,
    event_target_values: *[][]const u8,
    owned_targets: *usize,
    session: session_mod.Session,
    timestamp: time.Timestamp,
    event_type: event.EventType,
    target_kind: types.TargetKind,
    target_value: []const u8,
) !event.Event {
    const owned_target = try allocator.dupe(u8, target_value);
    errdefer allocator.free(owned_target);
    event_target_values.*[owned_targets.*] = owned_target;
    owned_targets.* += 1;
    return makeEvent(session, timestamp, event_type, target_kind, owned_target);
}

const FailingHookContext = struct {
    calls: usize = 0,

    fn fail(context: *anyopaque, _: session_mod.Session) !void {
        const self: *FailingHookContext = @ptrCast(@alignCast(context));
        self.calls += 1;
        return error.IntentionalHookFailure;
    }
};

test "run config construction captures phase 05 inputs" {
    const config: RunConfig = .{
        .command = "zig",
        .args = &.{ "version" },
        .workspace = ".",
        .mode = .observe,
        .session_name = "smoke",
        .stdio = .ignore,
    };

    try std.testing.expectEqualStrings("zig", config.command);
    try std.testing.expectEqualStrings("version", config.args[0]);
    try std.testing.expectEqualStrings(".", config.workspace.?);
    try std.testing.expectEqual(types.Mode.observe, config.mode);
    try std.testing.expectEqualStrings("smoke", config.session_name.?);
}

test "workspace detection honors explicit workspace" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const explicit = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(explicit);

    const resolved = try resolveWorkspaceRoot(std.testing.allocator, explicit, "/");
    defer std.testing.allocator.free(resolved);

    try std.testing.expectEqualStrings(explicit, resolved);
}

test "workspace detection finds nearest git parent" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath(".git");
    try tmp.dir.makePath("child/grandchild");

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    const child = try tmp.dir.realpathAlloc(std.testing.allocator, "child/grandchild");
    defer std.testing.allocator.free(child);

    const resolved = try resolveWorkspaceRoot(std.testing.allocator, null, child);
    defer std.testing.allocator.free(resolved);

    try std.testing.expectEqualStrings(root, resolved);
}

test "workspace detection falls back to start directory outside git" {
    const tmp_parent = if (std.process.getEnvVarOwned(std.testing.allocator, "TMPDIR")) |value| value else |_| try std.testing.allocator.dupe(u8, "/tmp");
    defer std.testing.allocator.free(tmp_parent);

    var suffix_buf: [8]u8 = undefined;
    const suffix = try util.randomHexSuffix(&suffix_buf);
    const relative_name = try std.fmt.allocPrint(std.testing.allocator, "aegis-non-git-{s}", .{suffix});
    defer std.testing.allocator.free(relative_name);
    const tmp_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_parent, relative_name });
    defer std.testing.allocator.free(tmp_path);

    try std.fs.cwd().makePath(tmp_path);
    defer std.fs.cwd().deleteTree(tmp_path) catch {};

    const root = try std.fs.cwd().realpathAlloc(std.testing.allocator, tmp_path);
    defer std.testing.allocator.free(root);

    const resolved = try resolveWorkspaceRoot(std.testing.allocator, null, root);
    defer std.testing.allocator.free(resolved);

    try std.testing.expectEqualStrings(root, resolved);
}

test "running a simple child populates session metadata and events" {
    var result = try run(std.testing.allocator, .{
        .command = "zig",
        .args = &.{"version"},
        .workspace = ".",
        .mode = .observe,
        .session_name = "unit",
        .stdio = .ignore,
    });
    defer result.deinit();

    try std.testing.expectEqual(@as(i32, 0), result.exitCode());
    try std.testing.expect(result.session.id.len > 0);
    try std.testing.expect(result.session.ended_at != null);
    try std.testing.expectEqualStrings("zig", result.session.command);
    try std.testing.expectEqualStrings("unit", result.session.session_name.?);
    try std.testing.expectEqual(types.Mode.observe, result.session.mode);
    try std.testing.expectEqual(@as(usize, 3), result.events.len);
    try std.testing.expectEqual(event.EventType.session_start, result.events[0].event_type);
    try std.testing.expectEqual(event.EventType.process_launch, result.events[1].event_type);
    try std.testing.expectEqual(event.EventType.session_exit, result.events[2].event_type);
    try std.testing.expectEqualStrings(result.session.id.slice(), result.events[0].target.value);
    try std.testing.expectEqualStrings(result.session.id.slice(), result.events[2].target.value);
    try std.testing.expect(result.events[0].target.value.ptr != result.session.id.slice().ptr);
    try std.testing.expect(result.events[2].target.value.ptr != result.session.id.slice().ptr);
}

test "child non-zero exit code is propagated" {
    var result = try run(std.testing.allocator, .{
        .command = "zig",
        .args = &.{"definitely-not-a-zig-command"},
        .workspace = ".",
        .stdio = .ignore,
    });
    defer result.deinit();

    try std.testing.expect(result.exitCode() != 0);
}

test "missing child command returns useful typed error" {
    try std.testing.expectError(error.CommandNotFound, run(std.testing.allocator, .{
        .command = "aegis-definitely-missing-command",
        .workspace = ".",
        .stdio = .ignore,
    }));
}

test "session start hook failure cleans up spawned child and returns hook error" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var context: FailingHookContext = .{};
    const started = std.time.milliTimestamp();
    try std.testing.expectError(error.IntentionalHookFailure, run(std.testing.allocator, .{
        .command = "/bin/sh",
        .args = &.{ "-c", "sleep 2" },
        .workspace = ".",
        .stdio = .ignore,
        .on_session_start = .{
            .context = &context,
            .callback = FailingHookContext.fail,
        },
    }));
    const elapsed_ms = std.time.milliTimestamp() - started;

    try std.testing.expectEqual(@as(usize, 1), context.calls);
    try std.testing.expect(elapsed_ms < 1_500);
}
