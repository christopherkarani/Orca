//! Inherited file-descriptor scrub for agent launch (P0-I-05).
//!
//! Closes FDs above stdio so a child agent process does not inherit sockets,
//! log handles, or other parent FDs. Unit-testable via pure list/predicate
//! helpers; actual close is a thin platform loop.
//!
//! Not wired into process.prepareChild here — handoff for U04-apply-seam
//! (apply after fork / before exec, or via posix_spawn file actions).

const std = @import("std");
const builtin = @import("builtin");

/// Default keep set: stdin, stdout, stderr.
pub const default_keep_fds = [_]i32{ 0, 1, 2 };

/// Fallback upper bound when rlimit is unavailable.
const fallback_open_max: i32 = 1024;

/// True when `fd` is listed in `keep` (should not be closed).
pub fn isKeptFd(fd: i32, keep: []const i32) bool {
    for (keep) |k| {
        if (k == fd) return true;
    }
    return false;
}

/// True when `fd` should be closed given the keep list.
pub fn shouldCloseFd(fd: i32, keep: []const i32) bool {
    if (fd < 0) return false;
    return !isKeptFd(fd, keep);
}

/// Pure: list every FD in `[0, open_max)` that should be closed.
/// Caller frees the returned slice with `allocator.free`.
pub fn listFdsToClose(allocator: std.mem.Allocator, open_max: i32, keep: []const i32) ![]i32 {
    var list: std.ArrayList(i32) = .empty;
    errdefer list.deinit(allocator);

    if (open_max <= 0) return try list.toOwnedSlice(allocator);

    var fd: i32 = 0;
    while (fd < open_max) : (fd += 1) {
        if (shouldCloseFd(fd, keep)) {
            try list.append(allocator, fd);
        }
    }
    return try list.toOwnedSlice(allocator);
}

/// Close callback type for injectable close (unit tests mock this).
pub const CloseFn = *const fn (fd: i32) void;

/// Iterate FDs in `[0, open_max)` and invoke `close_fn` for each that should close.
/// Returns number of close attempts. Pure control flow; no syscalls when mocked.
pub fn closeFdsWith(open_max: i32, keep: []const i32, close_fn: CloseFn) usize {
    if (open_max <= 0) return 0;
    var closed: usize = 0;
    var fd: i32 = 0;
    while (fd < open_max) : (fd += 1) {
        if (shouldCloseFd(fd, keep)) {
            close_fn(fd);
            closed += 1;
        }
    }
    return closed;
}

fn platformOpenMax() i32 {
    switch (builtin.os.tag) {
        .windows, .wasi => return 0,
        else => {
            const limits = std.posix.getrlimit(.NOFILE) catch return fallback_open_max;
            const soft = limits.cur;
            if (soft == 0 or soft > std.math.maxInt(i32)) return fallback_open_max;
            return @intCast(soft);
        },
    }
}

fn bestEffortClose(fd: i32) void {
    switch (builtin.os.tag) {
        .windows, .wasi => {},
        else => {
            // libc close: ignore EBADF and other errors (empty slots are normal).
            _ = std.c.close(fd);
        },
    }
}

/// Close inherited FDs above the keep set (default: keep 0/1/2).
/// Best-effort: ignores close errors (EBADF for already-closed slots).
/// Prefer calling from a post-fork child path (U04) or via posix_spawn file actions.
pub fn closeInheritedFds(keep: []const i32) void {
    const open_max = platformOpenMax();
    if (open_max <= 0) return;
    _ = closeFdsWith(open_max, keep, bestEffortClose);
}

/// Like `closeInheritedFds` but uses `default_keep_fds` (0, 1, 2).
pub fn closeInheritedFdsDefault() void {
    closeInheritedFds(&default_keep_fds);
}

// ── tests ──────────────────────────────────────────────────────────────────

test "default keep is 0 1 2" {
    try std.testing.expectEqual(@as(usize, 3), default_keep_fds.len);
    try std.testing.expectEqual(@as(i32, 0), default_keep_fds[0]);
    try std.testing.expectEqual(@as(i32, 1), default_keep_fds[1]);
    try std.testing.expectEqual(@as(i32, 2), default_keep_fds[2]);
}

test "isKeptFd and shouldCloseFd respect keep list" {
    const keep = default_keep_fds[0..];
    try std.testing.expect(isKeptFd(0, keep));
    try std.testing.expect(isKeptFd(1, keep));
    try std.testing.expect(isKeptFd(2, keep));
    try std.testing.expect(!isKeptFd(3, keep));
    try std.testing.expect(!isKeptFd(42, keep));

    try std.testing.expect(!shouldCloseFd(0, keep));
    try std.testing.expect(!shouldCloseFd(1, keep));
    try std.testing.expect(!shouldCloseFd(2, keep));
    try std.testing.expect(shouldCloseFd(3, keep));
    try std.testing.expect(shouldCloseFd(99, keep));
}

test "shouldCloseFd with custom keep" {
    const keep = [_]i32{ 0, 1, 2, 7 };
    try std.testing.expect(!shouldCloseFd(7, &keep));
    try std.testing.expect(shouldCloseFd(8, &keep));
    try std.testing.expect(shouldCloseFd(3, &keep));
}

test "listFdsToClose returns non-kept fds in range" {
    const keep = default_keep_fds[0..];
    const list = try listFdsToClose(std.testing.allocator, 8, keep);
    defer std.testing.allocator.free(list);

    try std.testing.expectEqual(@as(usize, 5), list.len); // 3,4,5,6,7
    try std.testing.expectEqual(@as(i32, 3), list[0]);
    try std.testing.expectEqual(@as(i32, 4), list[1]);
    try std.testing.expectEqual(@as(i32, 5), list[2]);
    try std.testing.expectEqual(@as(i32, 6), list[3]);
    try std.testing.expectEqual(@as(i32, 7), list[4]);
}

test "listFdsToClose empty when open_max is 0" {
    const list = try listFdsToClose(std.testing.allocator, 0, &default_keep_fds);
    defer std.testing.allocator.free(list);
    try std.testing.expectEqual(@as(usize, 0), list.len);
}

test "listFdsToClose keeps only stdio when open_max is 3" {
    const list = try listFdsToClose(std.testing.allocator, 3, &default_keep_fds);
    defer std.testing.allocator.free(list);
    try std.testing.expectEqual(@as(usize, 0), list.len);
}

test "closeFdsWith invokes close only for non-kept fds" {
    // Use module-level-style static for mock (CloseFn has no context pointer).
    const Mock = struct {
        var buf: [32]i32 = undefined;
        var len: usize = 0;
        fn reset() void {
            len = 0;
        }
        fn close(fd: i32) void {
            if (len < buf.len) {
                buf[len] = fd;
                len += 1;
            }
        }
    };
    Mock.reset();
    const n = closeFdsWith(6, &default_keep_fds, Mock.close);
    try std.testing.expectEqual(@as(usize, 3), n); // 3,4,5
    try std.testing.expectEqual(@as(usize, 3), Mock.len);
    try std.testing.expectEqual(@as(i32, 3), Mock.buf[0]);
    try std.testing.expectEqual(@as(i32, 4), Mock.buf[1]);
    try std.testing.expectEqual(@as(i32, 5), Mock.buf[2]);
}

test "closeInheritedFds is callable without panic on posix" {
    // Smoke only: do not close real process FDs in unit tests.
    // Real close is exercised via closeFdsWith mock above.
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return error.SkipZigTest;
    // Ensure symbol links; keep a wide set so we do not close live FDs.
    var keep_all: [256]i32 = undefined;
    for (&keep_all, 0..) |*slot, i| slot.* = @intCast(i);
    closeInheritedFds(keep_all[0..]);
}
