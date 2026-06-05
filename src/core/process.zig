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
    io: std.Io,
    argv: []const []const u8,
    workspace_root: []const u8,
    stdio: StdioBehavior = .inherit,
    env_map: ?*const std.process.Environ.Map = null,
};

pub const PreparedChild = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    workspace_root: []const u8,
    env_map: ?*const std.process.Environ.Map,
    stdio: StdioBehavior,
    child: ?std.process.Child = null,
    process_group_cleanup: bool = false,
    process_group_id: ?std.posix.pid_t = null,
    spawned: bool = false,

    pub fn spawn(self: *PreparedChild) !void {
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

test "child status exit code mapping" {
    try std.testing.expectEqual(@as(i32, 0), (ChildStatus{ .exited = 0 }).exitCode());
    try std.testing.expectEqual(@as(i32, 7), (ChildStatus{ .exited = 7 }).exitCode());
    try std.testing.expectEqual(@as(i32, 1), (ChildStatus{ .signal = 9 }).exitCode());
}
