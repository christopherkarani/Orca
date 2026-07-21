//! Child process preparation for production agent launch.
//!
//! Production path:
//!   sandbox.apply.applyBeforeExec → supervisor.run → prepareChild → spawn
//!
//! When OS sandbox requires child apply (Landlock / Seatbelt), callers pass a
//! `custom` spawn hook that uses `sandbox.apply_posix` so the agent is boxed.
//! The core module must not import sandbox (module boundary: core_engine vs orca).
//!
//! prepareChild consumes the scrubbed env_map from applyBeforeExec.
//! FD scrub is child-side only (see sandbox/fd_scrub.zig / apply_posix.zig).

const std = @import("std");
const builtin = @import("builtin");

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

pub const EnvRedactionRecord = struct {
    name: []const u8,
    labels: []const []const u8,
    reason: []const u8,
};

pub const StdioBehavior = enum {
    inherit,
    ignore,
};

/// Request passed to a custom (sandboxed) spawn hook.
pub const CustomSpawnRequest = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    workspace_root: []const u8,
    env_map: ?*const std.process.Environ.Map,
    stdio: StdioBehavior,
};

/// Optional override for agent spawn (U07 OS-FS child apply lives in orca/sandbox).
pub const CustomSpawn = struct {
    context: *anyopaque,
    spawnFn: *const fn (context: *anyopaque, request: CustomSpawnRequest) anyerror!std.process.Child,
};

/// OS-FS child apply plan for agent spawn (U07).
/// `.custom` is provided by cli/run with Landlock/Seatbelt apply_posix.
pub const OsChildApply = union(enum) {
    none,
    custom: CustomSpawn,
};

pub const PrepareRequest = struct {
    io: std.Io,
    argv: []const []const u8,
    workspace_root: []const u8,
    stdio: StdioBehavior = .inherit,
    env_map: ?*const std.process.Environ.Map = null,
    /// When not `.none`, spawn uses the custom hook instead of std.process.spawn.
    os_child_apply: OsChildApply = .none,
};

pub const PreparedChild = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    workspace_root: []const u8,
    env_map: ?*const std.process.Environ.Map,
    stdio: StdioBehavior,
    os_child_apply: OsChildApply = .none,
    child: ?std.process.Child = null,
    process_group_cleanup: bool = false,
    process_group_id: ?std.posix.pid_t = null,
    spawned: bool = false,
    /// True when the custom spawn hook returned successfully.
    /// Does **not** prove OS child apply handshake — that is attach-receipt /
    /// `spawnAgent` territory (S-GLO-01). Renamed from `os_child_apply_used`
    /// which overclaimed handshake semantics (Z-8).
    custom_spawn_used: bool = false,

    pub fn spawn(self: *PreparedChild) !void {
        switch (self.os_child_apply) {
            .none => try self.spawnPlain(),
            .custom => |hook| try self.spawnCustom(hook),
        }
    }

    fn spawnPlain(self: *PreparedChild) !void {
        const child = try std.process.spawn(self.io, .{
            .argv = self.argv,
            .cwd = .{ .path = self.workspace_root },
            .environ_map = self.env_map,
            .stdin = mapStdio(self.stdio),
            .stdout = mapStdio(self.stdio),
            .stderr = mapStdio(self.stdio),
        });
        self.child = child;
        switch (builtin.os.tag) {
            .linux, .macos => {
                if (child.id) |pid| self.process_group_id = pid;
            },
            else => {},
        }
        self.spawned = true;
        self.custom_spawn_used = false;
    }

    fn spawnCustom(self: *PreparedChild, hook: CustomSpawn) !void {
        // Flag means "custom hook returned", not "handshake proven". Production
        // sandboxed hooks (spawnAgent / apply_posix) must only return after a
        // status-pipe handshake; this bool does not re-check that contract.
        const child = try hook.spawnFn(hook.context, .{
            .io = self.io,
            .allocator = self.allocator,
            .argv = self.argv,
            .workspace_root = self.workspace_root,
            .env_map = self.env_map,
            .stdio = self.stdio,
        });
        self.child = child;
        switch (builtin.os.tag) {
            .linux, .macos => {
                // Child setpgid(0,0) makes pgid == pid; kill(-pgid) cleans the group.
                if (child.id) |pid| self.process_group_id = pid;
            },
            else => {},
        }
        self.spawned = true;
        self.custom_spawn_used = true;
    }

    pub fn waitForSpawn(_: *PreparedChild) !void {}

    pub fn wait(self: *PreparedChild) !std.process.Child.Term {
        const child = &(self.child orelse return error.InvalidState);
        const term = try child.wait(self.io);
        self.spawned = false;
        self.cleanupProcessGroup();
        return term;
    }

    pub fn terminateAfterParentError(self: *PreparedChild) void {
        if (!self.spawned) return;
        const child = &(self.child orelse return);
        if (self.process_group_cleanup) {
            if (self.process_group_id) |pgid| killProcessGroup(pgid);
        }
        child.kill(self.io);
        self.spawned = false;
    }

    pub fn terminateForHealthFailure(self: *PreparedChild) void {
        if (!self.spawned) return;
        const child = &(self.child orelse return);
        if (self.process_group_cleanup) {
            if (self.process_group_id) |pgid| killProcessGroup(pgid);
        }
        child.kill(self.io);
    }

    fn cleanupProcessGroup(self: *PreparedChild) void {
        if (!self.process_group_cleanup) return;
        if (self.process_group_id) |pgid| killProcessGroup(pgid);
    }
};

pub fn prepareChild(io: std.Io, allocator: std.mem.Allocator, request: PrepareRequest) PreparedChild {
    var prepared: PreparedChild = .{
        .io = io,
        .allocator = allocator,
        .argv = request.argv,
        .workspace_root = request.workspace_root,
        .env_map = request.env_map,
        .stdio = request.stdio,
        .os_child_apply = request.os_child_apply,
    };
    switch (builtin.os.tag) {
        .linux, .macos => prepared.process_group_cleanup = true,
        else => {},
    }
    return prepared;
}

fn mapStdio(behavior: StdioBehavior) std.process.SpawnOptions.StdIo {
    return switch (behavior) {
        .inherit => .inherit,
        .ignore => .ignore,
    };
}

fn killProcessGroup(pgid: std.posix.pid_t) void {
    switch (builtin.os.tag) {
        .windows, .wasi => return,
        else => {
            std.posix.kill(-pgid, std.posix.SIG.KILL) catch {};
        },
    }
}

/// Build a `std.process.Child` from a raw POSIX pid (apply_posix fork path).
pub fn childFromPid(pid: i32) std.process.Child {
    return .{
        .id = pid,
        .thread_handle = {},
        .stdin = null,
        .stdout = null,
        .stderr = null,
        .request_resource_usage_statistics = false,
    };
}

test "child status exit code mapping" {
    try std.testing.expectEqual(@as(i32, 0), (ChildStatus{ .exited = 0 }).exitCode());
    try std.testing.expectEqual(@as(i32, 7), (ChildStatus{ .exited = 7 }).exitCode());
    try std.testing.expectEqual(@as(i32, 1), (ChildStatus{ .signal = 9 }).exitCode());
}

test "prepareChild defaults to no OS child apply" {
    const prepared = prepareChild(std.testing.io, std.testing.allocator, .{
        .io = std.testing.io,
        .argv = &[_][]const u8{"true"},
        .workspace_root = ".",
    });
    try std.testing.expect(prepared.os_child_apply == .none);
    try std.testing.expect(!prepared.custom_spawn_used);
}

test "custom spawn hook sets custom_spawn_used without claiming handshake" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const Ctx = struct {
        called: bool = false,
        fn spawn(context: *anyopaque, request: CustomSpawnRequest) anyerror!std.process.Child {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.called = true;
            // Resolve true and fork/exec without sandbox for the unit test.
            // This deliberately has no OS apply handshake — custom_spawn_used
            // must still become true (flag = hook returned, not attach proven).
            const child = try std.process.spawn(request.io, .{
                .argv = &[_][]const u8{"/usr/bin/true"},
                .cwd = .{ .path = request.workspace_root },
                .environ_map = request.env_map,
                .stdin = .ignore,
                .stdout = .ignore,
                .stderr = .ignore,
            });
            return child;
        }
    };
    var ctx: Ctx = .{};
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var prepared = prepareChild(std.testing.io, std.testing.allocator, .{
        .io = std.testing.io,
        .argv = &[_][]const u8{"true"},
        .workspace_root = root,
        .stdio = .ignore,
        .os_child_apply = .{ .custom = .{
            .context = &ctx,
            .spawnFn = Ctx.spawn,
        } },
    });
    try prepared.spawn();
    try std.testing.expect(ctx.called);
    try std.testing.expect(prepared.custom_spawn_used);
    const term = try prepared.wait();
    try std.testing.expect(term == .exited);
    try std.testing.expectEqual(@as(u8, 0), term.exited);
}
