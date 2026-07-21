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
    /// Sticky POSIX pid captured at spawn. Survives `Child.kill`/`wait` nulling
    /// `child.id` so parent error cleanup can still SIGKILL+waitpid (M-4).
    posix_pid: ?std.posix.pid_t = null,
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

    fn recordSpawnedPid(self: *PreparedChild, child: std.process.Child) void {
        switch (builtin.os.tag) {
            .linux, .macos, .freebsd, .netbsd, .openbsd, .dragonfly => {
                if (child.id) |pid| {
                    self.posix_pid = pid;
                    // Child setpgid(0,0) makes pgid == pid; kill(-pgid) cleans the group.
                    self.process_group_id = pid;
                }
            },
            else => {},
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
        self.recordSpawnedPid(child);
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
        self.recordSpawnedPid(child);
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

    /// Kill the spawned agent (and process group when enabled), then **reap**.
    ///
    /// Must wait/reap before any parent free of fork-shared argv/env (COW
    /// free-before-reap). `std.process.Child.kill` already waits, but we use a
    /// sticky spawn-time pid and an EINTR-retry waitpid so a partial Io kill
    /// path (or a nulled `child.id`) cannot leave the child unreaped (M-4).
    ///
    /// Main-thread only. Must not run concurrently with `wait` (see
    /// `terminateForHealthFailure`).
    pub fn terminateAfterParentError(self: *PreparedChild) void {
        if (!self.spawned) return;
        const sticky = self.stickyPosixPid();
        if (self.process_group_cleanup) {
            if (self.process_group_id) |pgid| killProcessGroup(pgid);
        }
        if (self.child) |*child| {
            // Child.kill waits and nulls id when id is still set. If id is
            // already null (failed partial wait), fall through to sticky waitpid.
            if (child.id != null) {
                child.kill(self.io);
            } else {
                signalKillPid(sticky);
            }
        } else {
            signalKillPid(sticky);
        }
        if (sticky) |pid| waitpidEintr(pid);
        self.spawned = false;
        self.process_group_id = null;
    }

    /// Health-monitor path: **signal only**, never wait/reap.
    ///
    /// Concurrent waitpid on the same Child is double-free under Zig 0.16
    /// (ECHILD). The main `wait()` path is the sole reaper (M-6). Prefer
    /// process-group SIGKILL so the blocked main waiter unblocks promptly.
    pub fn terminateForHealthFailure(self: *PreparedChild) void {
        if (!self.spawned) return;
        if (self.process_group_cleanup) {
            if (self.process_group_id) |pgid| {
                killProcessGroup(pgid);
                return;
            }
        }
        // No process group: SIGKILL sticky pid without waitpid / without
        // touching child.id so the main waiter remains the only reaper.
        signalKillPid(self.stickyPosixPid());
    }

    fn stickyPosixPid(self: *const PreparedChild) ?std.posix.pid_t {
        if (self.posix_pid) |pid| return pid;
        switch (builtin.os.tag) {
            .linux, .macos, .freebsd, .netbsd, .openbsd, .dragonfly => {
                if (self.child) |child| return child.id;
            },
            else => {},
        }
        return null;
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

fn signalKillPid(pid: ?std.posix.pid_t) void {
    const p = pid orelse return;
    if (p <= 0) return;
    switch (builtin.os.tag) {
        .windows, .wasi => return,
        else => std.posix.kill(p, std.posix.SIG.KILL) catch {},
    }
}

/// Best-effort waitpid with EINTR retry. Idempotent when the child was already
/// reaped (`ECHILD`). Core-side only — must not import sandbox `killAndReapChild`.
fn waitpidEintr(pid: std.posix.pid_t) void {
    if (pid <= 0) return;
    switch (builtin.os.tag) {
        .windows, .wasi => return,
        else => {
            var status: c_int = 0;
            while (true) {
                const rc = std.c.waitpid(pid, &status, 0);
                if (rc >= 0) break;
                if (std.posix.errno(@as(isize, rc)) == .INTR) continue;
                break;
            }
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

test "terminateAfterParentError reaps child so free-after is not free-before-reap" {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return error.SkipZigTest;

    // Sleep long enough that kill is required; terminate must reap (not leave a zombie).
    const child = try std.process.spawn(std.testing.io, .{
        .argv = &[_][]const u8{ "/bin/sleep", "30" },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
    const pid = child.id orelse return error.SkipZigTest;

    var prepared = prepareChild(std.testing.io, std.testing.allocator, .{
        .io = std.testing.io,
        .argv = &[_][]const u8{ "/bin/sleep", "30" },
        .workspace_root = ".",
        .stdio = .ignore,
    });
    prepared.child = child;
    prepared.spawned = true;
    prepared.posix_pid = pid;
    prepared.process_group_id = pid;
    prepared.process_group_cleanup = true;

    prepared.terminateAfterParentError();
    try std.testing.expect(!prepared.spawned);
    try std.testing.expect(prepared.child.?.id == null);

    // Child must not still be running: NOHANG waitpid returns 0 only if alive.
    var status: c_int = 0;
    const rc = std.c.waitpid(pid, &status, 1); // WNOHANG == 1 on Linux/macOS
    if (rc == 0) {
        _ = std.posix.kill(pid, std.posix.SIG.KILL) catch {};
        waitpidEintr(pid);
        return error.TestUnexpectedResult;
    }
    // rc < 0 (ECHILD) or rc == pid both mean reaped / not running.
}

test "terminateAfterParentError uses sticky posix_pid when child.id already null" {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return error.SkipZigTest;

    const child = try std.process.spawn(std.testing.io, .{
        .argv = &[_][]const u8{ "/bin/sleep", "30" },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
    const pid = child.id orelse return error.SkipZigTest;

    var prepared = prepareChild(std.testing.io, std.testing.allocator, .{
        .io = std.testing.io,
        .argv = &[_][]const u8{ "/bin/sleep", "30" },
        .workspace_root = ".",
        .stdio = .ignore,
    });
    // Simulate a failed partial wait that nulled Child.id while the process lives.
    var zombie_handle = child;
    zombie_handle.id = null;
    prepared.child = zombie_handle;
    prepared.spawned = true;
    prepared.posix_pid = pid;
    prepared.process_group_id = pid;
    prepared.process_group_cleanup = true;

    prepared.terminateAfterParentError();
    try std.testing.expect(!prepared.spawned);

    var status: c_int = 0;
    const rc = std.c.waitpid(pid, &status, 1);
    if (rc == 0) {
        _ = std.posix.kill(pid, std.posix.SIG.KILL) catch {};
        waitpidEintr(pid);
        return error.TestUnexpectedResult;
    }
}

test "terminateForHealthFailure signals without reaping so main wait is sole reaper" {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return error.SkipZigTest;

    const child = try std.process.spawn(std.testing.io, .{
        .argv = &[_][]const u8{ "/bin/sleep", "30" },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
    const pid = child.id orelse return error.SkipZigTest;

    var prepared = prepareChild(std.testing.io, std.testing.allocator, .{
        .io = std.testing.io,
        .argv = &[_][]const u8{ "/bin/sleep", "30" },
        .workspace_root = ".",
        .stdio = .ignore,
    });
    prepared.child = child;
    prepared.spawned = true;
    prepared.posix_pid = pid;
    prepared.process_group_id = pid;
    prepared.process_group_cleanup = true;

    prepared.terminateForHealthFailure();
    // Must remain spawned with a live Child handle for the main waiter.
    try std.testing.expect(prepared.spawned);
    try std.testing.expect(prepared.child.?.id != null);

    // Sole reaper path (mirrors supervisor after health signal).
    const term = try prepared.wait();
    try std.testing.expect(term == .signal or term == .exited);
    try std.testing.expect(!prepared.spawned);
}
