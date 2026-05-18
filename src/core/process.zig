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

pub const PrepareRequest = struct {
    argv: []const []const u8,
    workspace_root: []const u8,
    stdio: StdioBehavior = .inherit,
    env_map: ?*const std.process.EnvMap = null,
};

pub const PreparedChild = struct {
    child: std.process.Child,
    process_group_cleanup: bool = false,
    process_group_id: ?std.posix.pid_t = null,
    spawned: bool = false,

    pub fn spawn(self: *PreparedChild) !void {
        try self.child.spawn();
        switch (builtin.os.tag) {
            .windows, .wasi => {},
            else => if (self.process_group_cleanup) {
                self.process_group_id = @intCast(self.child.id);
            },
        }
        self.spawned = true;
    }

    pub fn waitForSpawn(self: *PreparedChild) !void {
        try self.child.waitForSpawn();
    }

    pub fn wait(self: *PreparedChild) !std.process.Child.Term {
        const term = try self.child.wait();
        self.spawned = false;
        self.cleanupProcessGroup();
        return term;
    }

    pub fn terminateAfterParentError(self: *PreparedChild) void {
        if (!self.spawned) return;
        if (self.process_group_cleanup) {
            if (self.process_group_id) |pgid| killProcessGroup(pgid);
        }
        _ = self.child.kill() catch self.child.wait() catch {};
        self.spawned = false;
    }

    pub fn terminateForHealthFailure(self: *PreparedChild) void {
        if (!self.spawned) return;
        if (self.process_group_cleanup) {
            if (self.process_group_id) |pgid| killProcessGroup(pgid);
        }
        _ = self.child.kill() catch {};
    }

    fn cleanupProcessGroup(self: *PreparedChild) void {
        if (!self.process_group_cleanup) return;
        if (self.process_group_id) |pgid| killProcessGroup(pgid);
    }
};

pub fn prepareChild(allocator: std.mem.Allocator, request: PrepareRequest) PreparedChild {
    var child = std.process.Child.init(request.argv, allocator);
    child.cwd = request.workspace_root;
    child.env_map = request.env_map;
    configureStdio(&child, request.stdio);
    var prepared: PreparedChild = .{ .child = child };
    switch (builtin.os.tag) {
        .linux, .macos => {
            prepared.child.pgid = 0;
            prepared.process_group_cleanup = true;
        },
        else => {},
    }
    return prepared;
}

fn configureStdio(child: *std.process.Child, stdio: StdioBehavior) void {
    switch (stdio) {
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
}

fn killProcessGroup(pgid: std.posix.pid_t) void {
    switch (builtin.os.tag) {
        .windows, .wasi => return,
        else => {
            if (pgid <= 0) return;
            std.posix.kill(-pgid, std.posix.SIG.TERM) catch {};
            std.Thread.sleep(50 * std.time.ns_per_ms);
            std.posix.kill(-pgid, std.posix.SIG.KILL) catch {};
        },
    }
}

test "child status maps non-exit outcomes to failure" {
    try std.testing.expectEqual(@as(i32, 0), (ChildStatus{ .exited = 0 }).exitCode());
    try std.testing.expectEqual(@as(i32, 7), (ChildStatus{ .exited = 7 }).exitCode());
    try std.testing.expectEqual(@as(i32, 1), (ChildStatus{ .signal = 9 }).exitCode());
}
