const std = @import("std");

/// Result of running a host command (e.g. `openclaw plugins uninstall ...` or `hermes ...`)
/// with a timeout guard.
///
/// This is the core primitive to prevent `orca uninstall` / `disable` from hanging
/// forever when a host CLI misbehaves, prompts unexpectedly, or is slow.
pub const HostCommandResult = struct {
    /// Exit code reported by the child (0-255). On timeout this is typically 255.
    exit_code: u8,
    /// True if we killed the child because it exceeded the deadline.
    timed_out: bool,
    /// Captured stdout (owned slice, caller must free). May be null if not captured.
    stdout: ?[]const u8,
    /// Captured stderr (owned slice, caller must free). May be null if not captured.
    stderr: ?[]const u8,
};

pub fn deinitHostCommandResult(result: HostCommandResult, allocator: std.mem.Allocator) void {
    if (result.stdout) |s| allocator.free(s);
    if (result.stderr) |s| allocator.free(s);
}

fn readPipeToAlloc(io: std.Io, allocator: std.mem.Allocator, file: std.Io.File, limit: usize) !?[]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    var buf: [4096]u8 = undefined;
    var reader = file.reader(io, &buf);
    while (list.items.len < limit) {
        const n = reader.interface.readSliceShort(buf[0..@min(buf.len, limit - list.items.len)]) catch break;
        if (n == 0) break;
        try list.appendSlice(allocator, buf[0..n]);
    }
    if (list.items.len == 0) return null;
    return try list.toOwnedSlice(allocator);
}

/// Run an external command (intended for host agent CLIs like openclaw/hermes)
/// with a hard timeout. Output is captured (and optionally streamed live for UX).
///
/// On Unix we use a monitoring thread + timer + kill for reliable timeout.
/// On Windows we use a best-effort wait loop + TerminateProcess (weaker guarantees).
///
/// This is deliberately *not* a general-purpose child runner — it is tuned for the
/// "call a potentially flaky host plugin manager and never hang the parent CLI" use case.
///
/// `timeout_ms` of 0 means "no timeout" (use only for tests or very special cases).
pub fn runHostCommandTimed(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    timeout_ms: u64,
    stdout_writer: anytype,
    stderr_writer: anytype,
) !HostCommandResult {
    if (argv.len == 0) return error.InvalidArgv;

    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var child = try std.process.spawn(io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
    });

    var timed_out: bool = false;
    var finished = std.atomic.Value(bool).init(false);
    var watcher: ?std.Thread = null;
    if (timeout_ms > 0) {
        watcher = std.Thread.spawn(.{}, struct {
            fn run(c: *std.process.Child, watch_io: std.Io, flag: *bool, fin: *std.atomic.Value(bool), ms: u64) void {
                var remaining: u64 = ms;
                const chunk: u64 = 50;
                while (remaining > 0) {
                    if (fin.load(.acquire)) return;
                    const sl = @min(chunk, remaining);
                    const duration = std.Io.Duration.fromMilliseconds(@intCast(sl));
                    std.Io.sleep(watch_io, duration, .awake) catch {};
                    remaining -= sl;
                }
                if (fin.load(.acquire)) return;
                if (@import("builtin").os.tag == .windows) {
                    c.kill(watch_io);
                } else if (c.id) |pid| {
                    std.posix.kill(pid, std.posix.SIG.TERM) catch {};
                }
                flag.* = true;
            }
        }.run, .{ &child, io, &timed_out, &finished, timeout_ms }) catch null;
    }

    const term = child.wait(io) catch {
        finished.store(true, .release);
        if (watcher) |w| w.join();
        return HostCommandResult{
            .exit_code = 255,
            .timed_out = timed_out,
            .stdout = null,
            .stderr = null,
        };
    };
    finished.store(true, .release);
    if (watcher) |w| w.join();

    const exit_code: u8 = switch (term) {
        .exited => |code| @as(u8, @intCast(@min(code, 255))),
        .signal, .stopped, .unknown => 255,
    };

    const stdout_data = if (child.stdout) |out| blk: {
        const data = readPipeToAlloc(io, allocator, out, 1 * 1024 * 1024) catch null;
        if (stdout_writer) |w| {
            if (data) |d| {
                _ = w.writeAll(d) catch {};
            }
        }
        break :blk data;
    } else null;

    const stderr_data = if (child.stderr) |err_pipe| blk: {
        const data = readPipeToAlloc(io, allocator, err_pipe, 1 * 1024 * 1024) catch null;
        if (stderr_writer) |w| {
            if (data) |d| {
                _ = w.writeAll(d) catch {};
            }
        }
        break :blk data;
    } else null;

    return HostCommandResult{
        .exit_code = exit_code,
        .timed_out = timed_out,
        .stdout = stdout_data,
        .stderr = stderr_data,
    };
}

// ---------------------------------------------------------------------------
// Test doubles / helpers for testing the runner itself without real hangs
// ---------------------------------------------------------------------------

/// Thin wrapper for tests that want to emphasize the timeout path.
/// In practice you can just call runHostCommandTimed with a tiny timeout.
pub fn runHostCommandTimedForTest(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    timeout_ms: u64,
    simulate_timeout_after_ms: ?u64,
) !HostCommandResult {
    _ = simulate_timeout_after_ms;
    return runHostCommandTimed(allocator, argv, timeout_ms, null, null);
}

test "child_process: API surface compiles and deinit is safe on zeroed result" {
    const result: HostCommandResult = .{
        .exit_code = 0,
        .timed_out = false,
        .stdout = null,
        .stderr = null,
    };
    deinitHostCommandResult(result, std.testing.allocator);
}

test "child_process: fast successful command returns reasonable result without hanging (self exe smoke)" {
    const self_exe = std.process.executablePathAlloc(std.testing.io, std.testing.allocator) catch return error.SkipZigTest;
    defer std.testing.allocator.free(self_exe);

    const argv = [_][]const u8{ self_exe, "--help" };
    const res = try runHostCommandTimed(
        std.testing.allocator,
        &argv,
        5_000,
        null,
        null,
    );
    defer deinitHostCommandResult(res, std.testing.allocator);
    try std.testing.expect(!res.timed_out);
}
