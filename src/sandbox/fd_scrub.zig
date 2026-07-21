//! Inherited file-descriptor scrub for agent launch (P0-I-05).
//!
//! Closes FDs above stdio so a child agent process does not inherit sockets,
//! log handles, or other parent FDs. Unit-testable via pure list/predicate
//! helpers; actual close is a thin platform loop.
//!
//! Called from the post-fork child path in `apply_posix` before exec (not in
//! the parent). Keep set defaults to stdin/stdout/stderr.
//!
//! Bound policy (FN residuals after M-3):
//! - Prefer max(usable soft, usable hard) so a soft rlimit drop still walks up
//!   to hard (FN-2).
//! - When soft/hard are unbounded (or hard cannot cap the table), scrub to
//!   `open_max_ceiling` — never a low Darwin `OPEN_MAX` platform hint (FN-1).
//! - Prefer `close_range` / `closefrom` when available so a 1M walk cannot burn
//!   the parent handshake budget (FN-3); fall back to an O(open_max) close loop.

const std = @import("std");
const builtin = @import("builtin");

/// Default keep set: stdin, stdout, stderr.
pub const default_keep_fds = [_]i32{ 0, 1, 2 };

/// Absolute ceiling for FD scrub loops when rlimit is infinite or huge.
/// Large enough for raised NOFILE limits; bounds worst-case close cost.
/// Prefer overshooting a high ceiling over under-scrubbing high inherited FDs (M-3).
pub const open_max_ceiling: i32 = 1 << 20; // 1_048_576

/// Max keep-set entries handled by pure range helpers / range-close path.
/// Production keep is `{0,1,2,status_w}` (4); tests may use a few more.
pub const max_keep_fds: usize = 64;

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

/// Pure: resolve scrub upper bound from soft/hard NOFILE limits and an optional
/// platform hint (e.g. Darwin `OPEN_MAX`, sysconf).
///
/// - Prefer `max(usable soft, usable hard)` so soft-first cannot under-scrub
///   when hard is higher (FN-2 finite-hard path).
/// - When hard is unbounded (infinity-shaped), use `open_max_ceiling` so FDs
///   that survive a soft rlimit drop above soft are still visited (FN-2).
/// - When soft and hard are both unusable/unbounded, use `open_max_ceiling` —
///   never a low Darwin `OPEN_MAX` (~10240) platform hint (FN-1).
/// - `platform_hint` is retained for API stability / diagnostics but is **not**
///   used as a low exclusive upper bound under unbounded rlimits.
///
/// Values `0` mean unavailable. Values above `maxInt(i32)` (RLIM_INFINITY and
/// peers) are treated as unbounded.
pub fn resolveOpenMax(soft: u64, hard: u64, platform_hint: i32) i32 {
    _ = platform_hint; // intentionally ignored as a low upper bound (FN-1)
    const soft_u = usableOpenMaxBound(soft);
    const hard_u = usableOpenMaxBound(hard);

    if (soft_u != null or hard_u != null) {
        var bound: i32 = 0;
        if (soft_u) |n| bound = @max(bound, n);
        if (hard_u) |n| bound = @max(bound, n);

        // Soft finite + hard unbounded: existing FDs may sit above soft after a
        // setrlimit soft drop. Hard cannot cap the table → walk to ceiling.
        if (hard_u == null and isRlimitUnbounded(hard)) {
            return open_max_ceiling;
        }
        if (bound > 0) return bound;
    }

    // Both unusable (0/0) or both unbounded (inf/inf): ceiling, not OPEN_MAX.
    return open_max_ceiling;
}

/// Map a raw rlimit value to a usable positive i32 scrub bound, or null if
/// unset/unbounded/unusable.
fn usableOpenMaxBound(limit: u64) ?i32 {
    if (limit == 0) return null;
    if (limit > std.math.maxInt(i32)) return null; // infinity / unusable
    const n: i32 = @intCast(limit);
    if (n > open_max_ceiling) return open_max_ceiling;
    return n;
}

/// True when `limit` is infinity-shaped (RLIM_INFINITY / > i32 max).
/// `0` is "unavailable", not unbounded.
fn isRlimitUnbounded(limit: u64) bool {
    return limit > std.math.maxInt(i32);
}

fn rlimAsU64(v: std.posix.rlim_t) u64 {
    const info = @typeInfo(std.posix.rlim_t);
    if (info != .int) return 0;
    if (info.int.signedness == .signed) {
        if (v < 0) return std.math.maxInt(u64); // treat negative as unbounded
        return @intCast(v);
    }
    return @intCast(v);
}

/// Best-effort platform hint when rlimit soft/hard are unbounded.
/// Retained for diagnostics / future use; `resolveOpenMax` does not treat a
/// low hint as the exclusive upper bound (FN-1).
fn platformOpenMaxHint() i32 {
    if (comptime builtin.os.tag.isDarwin()) {
        return @intCast(std.c.OPEN_MAX);
    }
    return 0;
}

fn platformOpenMax() i32 {
    switch (builtin.os.tag) {
        .windows, .wasi => return 0,
        else => {
            var soft: u64 = 0;
            var hard: u64 = 0;
            if (std.posix.getrlimit(.NOFILE)) |limits| {
                soft = rlimAsU64(limits.cur);
                hard = rlimAsU64(limits.max);
            } else |_| {}
            return resolveOpenMax(soft, hard, platformOpenMaxHint());
        },
    }
}

/// Pure: copy keep FDs in `[0, open_max)` into `out`, unique and ascending.
/// Returns count written (capped by `out.len` and `max_keep_fds`).
pub fn sortedUniqueKeep(open_max: i32, keep: []const i32, out: []i32) usize {
    var n: usize = 0;
    for (keep) |k| {
        if (k < 0) continue;
        if (open_max > 0 and k >= open_max) continue;
        // Insert sorted unique.
        var i: usize = 0;
        while (i < n) : (i += 1) {
            if (out[i] == k) break;
            if (out[i] > k) {
                if (n >= out.len) break;
                var j: usize = n;
                while (j > i) : (j -= 1) {
                    out[j] = out[j - 1];
                }
                out[i] = k;
                n += 1;
                break;
            }
        } else {
            if (n < out.len) {
                out[n] = k;
                n += 1;
            }
        }
    }
    return n;
}

/// Pure: fill inclusive `[lo, hi]` ranges of FDs to close in `[0, open_max)`
/// excluding keep. Returns number of ranges written.
/// `out` should hold at least `keep.len + 1` slots (capped by keep handling).
pub fn fillCloseRanges(open_max: i32, keep: []const i32, out: [][2]i32) usize {
    if (open_max <= 0 or out.len == 0) return 0;

    var kept_buf: [max_keep_fds]i32 = undefined;
    const n_kept = sortedUniqueKeep(open_max, keep, kept_buf[0..]);

    var n_out: usize = 0;
    var cursor: i32 = 0;
    for (kept_buf[0..n_kept]) |k| {
        if (cursor < k) {
            if (n_out >= out.len) return n_out;
            out[n_out] = .{ cursor, k - 1 };
            n_out += 1;
        }
        if (k >= cursor) cursor = k + 1;
    }
    if (cursor < open_max) {
        if (n_out < out.len) {
            out[n_out] = .{ cursor, open_max - 1 };
            n_out += 1;
        }
    }
    return n_out;
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

/// Linux `close_range` inclusive `[first, last]`. `last == -1` means "through end"
/// (kernel treats the arg as unsigned ~0). Returns false on ENOSYS/other failure
/// so callers can fall back to the walk loop.
fn linuxCloseRange(first: i32, last: i32) bool {
    if (builtin.os.tag != .linux) return false;
    const linux = std.os.linux;
    const rc = linux.close_range(first, last, .{});
    return linux.errno(rc) == .SUCCESS;
}

/// Best-effort range close: Linux `close_range` over keep-set gaps, then from
/// past the highest keep through the end of the FD table. Returns true when
/// the range path fully handled scrub (caller should skip the walk).
fn tryPlatformRangeClose(keep: []const i32) bool {
    if (builtin.os.tag != .linux) return false;

    var kept_buf: [max_keep_fds]i32 = undefined;
    // open_max = 0 → no upper filter; keep all non-negative keep FDs.
    const n_kept = sortedUniqueKeep(0, keep, kept_buf[0..]);

    var cursor: i32 = 0;
    for (kept_buf[0..n_kept]) |k| {
        if (k < 0) continue;
        if (cursor < k) {
            if (!linuxCloseRange(cursor, k - 1)) return false;
        }
        if (k >= cursor) cursor = k + 1;
    }
    // Close everything above the last keep (or from 0 if keep empty).
    // last=-1 → kernel UINT_MAX = all remaining FDs (no open_max ceiling hole).
    if (!linuxCloseRange(cursor, -1)) return false;
    return true;
}

/// Best-effort `closefrom` via dlsym when present (BSD; not on current Darwin).
/// Closes non-kept FDs in `[0, max_keep]` then `closefrom(max_keep+1)`.
fn tryPlatformClosefrom(keep: []const i32) bool {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return false;
    if (builtin.os.tag == .linux) return false; // prefer close_range on Linux

    const ClosefromFn = *const fn (fd: c_int) callconv(.c) void;
    const sym = resolveClosefromSymbol() orelse return false;
    const closefrom_fn: ClosefromFn = @ptrCast(@alignCast(sym));

    var kept_buf: [max_keep_fds]i32 = undefined;
    const n_kept = sortedUniqueKeep(0, keep, kept_buf[0..]);

    var max_keep: i32 = -1;
    for (kept_buf[0..n_kept]) |k| {
        if (k > max_keep) max_keep = k;
    }

    // Close holes below/at max keep with individual close (small).
    if (max_keep >= 0) {
        var fd: i32 = 0;
        while (fd <= max_keep) : (fd += 1) {
            if (shouldCloseFd(fd, keep)) bestEffortClose(fd);
        }
        closefrom_fn(@intCast(max_keep + 1));
    } else {
        closefrom_fn(0);
    }
    return true;
}

fn resolveClosefromSymbol() ?*anyopaque {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return null;
    // Darwin: dlsym(null) is wrong; RTLD_DEFAULT required (see macos_seatbelt).
    const handle: ?*anyopaque = if (comptime builtin.os.tag.isDarwin())
        @ptrFromInt(@as(usize, @bitCast(@as(isize, -2)))) // RTLD_DEFAULT
    else
        null;
    return std.c.dlsym(handle, "closefrom");
}

/// Close inherited FDs above the keep set (default: keep 0/1/2).
/// Best-effort: ignores close errors (EBADF for already-closed slots).
/// Call from the post-fork child before exec (see `apply_posix`).
///
/// Prefers platform range-close (`close_range` / `closefrom`) when available
/// so scrub cost stays well under the parent handshake budget; falls back to
/// an O(open_max) walk bounded by `resolveOpenMax`.
pub fn closeInheritedFds(keep: []const i32) void {
    if (tryPlatformRangeClose(keep)) return;
    if (tryPlatformClosefrom(keep)) return;
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
    // Smoke only: do not mass-close real process FDs (open_max may be ceiling).
    // Real close is exercised via closeFdsWith mock; platform path is linked here
    // by resolving the bound and calling with a keep set that covers [0, open_max).
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return error.SkipZigTest;
    const n = platformOpenMax();
    try std.testing.expect(n > 3);
    // Keep every FD in a small prefix so the walk/range path runs without
    // tearing down the test process. Range-close still sees the keep set.
    var keep_prefix: [64]i32 = undefined;
    for (&keep_prefix, 0..) |*slot, i| slot.* = @intCast(i);
    // Only exercise the public entry when the bound is tiny; otherwise pure
    // helpers + mocks cover behavior (full walk would close live high FDs).
    if (n <= keep_prefix.len) {
        closeInheritedFds(keep_prefix[0..@intCast(n)]);
    }
}

test "resolveOpenMax uses max of finite soft and hard (FN-2)" {
    // Soft-first would return 1024 and miss FDs opened under a higher soft before drop.
    try std.testing.expectEqual(@as(i32, 65536), resolveOpenMax(1024, 65536, 0));
    try std.testing.expectEqual(@as(i32, 8192), resolveOpenMax(8192, 4096, 0));
    try std.testing.expectEqual(@as(i32, 256), resolveOpenMax(256, 256, 0));
    // Soft alone when hard unavailable (0), both finite path:
    try std.testing.expectEqual(@as(i32, 8192), resolveOpenMax(8192, 0, 0));
}

test "resolveOpenMax prefers hard when soft is infinity or zero" {
    const inf = std.math.maxInt(u64);
    try std.testing.expectEqual(@as(i32, 4096), resolveOpenMax(inf, 4096, 0));
    try std.testing.expectEqual(@as(i32, 512), resolveOpenMax(0, 512, 0));
}

test "resolveOpenMax soft+hard unbounded prefers ceiling over Darwin OPEN_MAX (FN-1)" {
    const inf = std.math.maxInt(u64);
    // Platform hint 10240 must NOT win — that was the Darwin residual under-scrub.
    try std.testing.expectEqual(open_max_ceiling, resolveOpenMax(inf, inf, 10240));
    try std.testing.expectEqual(open_max_ceiling, resolveOpenMax(0, inf, 10240));
    try std.testing.expectEqual(open_max_ceiling, resolveOpenMax(inf, 0, 10240));
    try std.testing.expect(resolveOpenMax(inf, inf, 10240) > 10240);
}

test "resolveOpenMax soft finite hard unbounded uses ceiling (FN-2 soft-drop)" {
    // After soft drop, live FDs above soft remain; hard inf cannot cap → ceiling.
    const inf = std.math.maxInt(u64);
    try std.testing.expectEqual(open_max_ceiling, resolveOpenMax(1024, inf, 10240));
    try std.testing.expectEqual(open_max_ceiling, resolveOpenMax(8192, inf, 0));
}

test "resolveOpenMax infinity/large soft does not fall back to 1024" {
    // M-3: RLIM_INFINITY / >i32-max must not silently under-scrub at 1024.
    const inf = std.math.maxInt(u64);
    const darwin_inf: u64 = (1 << 63) - 1; // Darwin RLIM_INFINITY shape
    try std.testing.expectEqual(open_max_ceiling, resolveOpenMax(inf, inf, 0));
    try std.testing.expectEqual(open_max_ceiling, resolveOpenMax(darwin_inf, darwin_inf, 0));
    try std.testing.expect(resolveOpenMax(inf, inf, 0) > 1024);
    // Soft above i32 max with finite hard still picks hard.
    try std.testing.expectEqual(@as(i32, 65536), resolveOpenMax(inf, 65536, 1024));
}

test "resolveOpenMax clamps huge finite soft to ceiling" {
    const huge: u64 = @as(u64, @intCast(open_max_ceiling)) + 100;
    try std.testing.expectEqual(open_max_ceiling, resolveOpenMax(huge, 0, 0));
    // Both huge finite → ceiling clamp via usableOpenMaxBound
    try std.testing.expectEqual(open_max_ceiling, resolveOpenMax(huge, huge, 0));
}

test "platformOpenMax is positive and above stdio on posix" {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return error.SkipZigTest;
    const n = platformOpenMax();
    try std.testing.expect(n > 3);
    try std.testing.expect(n <= open_max_ceiling);
}

test "sortedUniqueKeep sorts dedupes and filters" {
    var out: [8]i32 = undefined;
    const keep = [_]i32{ 5, 0, 2, 5, -1, 100, 1 };
    const n = sortedUniqueKeep(10, &keep, out[0..]);
    try std.testing.expectEqual(@as(usize, 4), n); // 0,1,2,5 (100 filtered)
    try std.testing.expectEqual(@as(i32, 0), out[0]);
    try std.testing.expectEqual(@as(i32, 1), out[1]);
    try std.testing.expectEqual(@as(i32, 2), out[2]);
    try std.testing.expectEqual(@as(i32, 5), out[3]);
}

test "fillCloseRanges covers gaps around keep set" {
    var ranges: [8][2]i32 = undefined;
    const keep = [_]i32{ 0, 1, 2, 5 };
    const n = fillCloseRanges(10, &keep, ranges[0..]);
    // [3,4] and [6,9]
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqual(@as(i32, 3), ranges[0][0]);
    try std.testing.expectEqual(@as(i32, 4), ranges[0][1]);
    try std.testing.expectEqual(@as(i32, 6), ranges[1][0]);
    try std.testing.expectEqual(@as(i32, 9), ranges[1][1]);
}

test "fillCloseRanges default keep yields single range from 3" {
    var ranges: [4][2]i32 = undefined;
    const n = fillCloseRanges(8, &default_keep_fds, ranges[0..]);
    try std.testing.expectEqual(@as(usize, 1), n);
    try std.testing.expectEqual(@as(i32, 3), ranges[0][0]);
    try std.testing.expectEqual(@as(i32, 7), ranges[0][1]);
}

test "fillCloseRanges empty when open_max is 0" {
    var ranges: [2][2]i32 = undefined;
    const n = fillCloseRanges(0, &default_keep_fds, ranges[0..]);
    try std.testing.expectEqual(@as(usize, 0), n);
}

test "closeFdsWith high open_max reaches FDs above Darwin OPEN_MAX (FN-1 plant)" {
    // Pure mock: bound from resolveOpenMax(inf,inf,10240) must include FD 12000.
    const inf = std.math.maxInt(u64);
    const open_max = resolveOpenMax(inf, inf, 10240);
    try std.testing.expect(open_max > 12000);

    const Mock = struct {
        var saw_high: bool = false;
        var saw_keep: bool = false;
        fn reset() void {
            saw_high = false;
            saw_keep = false;
        }
        fn close(fd: i32) void {
            if (fd == 12000) saw_high = true;
            if (fd == 0 or fd == 1 or fd == 2) saw_keep = true;
        }
    };
    Mock.reset();
    // Walk only a slice around the planted high FD to keep the unit test cheap.
    // Production walk uses full open_max; this asserts the bound policy + keep.
    _ = closeFdsWith(12001, &default_keep_fds, Mock.close);
    try std.testing.expect(Mock.saw_high);
    try std.testing.expect(!Mock.saw_keep);
}

test "closeFdsWith after soft-drop bound still visits high hard FD (FN-2 plant)" {
    // soft=1024, hard=20000 → bound 20000; planted FD 15000 must be closed.
    const open_max = resolveOpenMax(1024, 20000, 0);
    try std.testing.expectEqual(@as(i32, 20000), open_max);

    const Mock = struct {
        var saw: bool = false;
        fn reset() void {
            saw = false;
        }
        fn close(fd: i32) void {
            if (fd == 15000) saw = true;
        }
    };
    Mock.reset();
    _ = closeFdsWith(open_max, &default_keep_fds, Mock.close);
    try std.testing.expect(Mock.saw);
}
