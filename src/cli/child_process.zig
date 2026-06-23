const std = @import("std");
const builtin = @import("builtin");
const env_util = @import("../env_util.zig");

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
    /// Reserved for API compatibility. Host-management commands discard output.
    stdout: ?[]const u8,
    /// Reserved for API compatibility. Host-management commands discard output.
    stderr: ?[]const u8,
};

pub fn deinitHostCommandResult(result: HostCommandResult, allocator: std.mem.Allocator) void {
    if (result.stdout) |s| allocator.free(s);
    if (result.stderr) |s| allocator.free(s);
}

/// Run an external command (intended for host agent CLIs like openclaw/hermes)
/// with a hard timeout. Output is discarded so an untrusted host CLI cannot block
/// Orca by filling a pipe. Current callers only need the exit status.
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
    _ = stdout_writer;
    _ = stderr_writer;

    var threaded = std.Io.Threaded.init(allocator, .{
        .environ = env_util.processEnviron(),
    });
    defer threaded.deinit();
    const io = threaded.io();

    var child = try std.process.spawn(io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
        .pgid = if (builtin.os.tag == .windows) null else 0,
    });
    const child_id = child.id.?;

    var timed_out: bool = false;
    var finished = std.atomic.Value(bool).init(false);
    var watcher: ?std.Thread = null;
    if (timeout_ms > 0) {
        watcher = std.Thread.spawn(.{}, struct {
            fn run(id: std.process.Child.Id, watch_io: std.Io, flag: *bool, fin: *std.atomic.Value(bool), ms: u64) void {
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
                if (builtin.os.tag == .windows) {
                    _ = std.os.windows.ntdll.NtTerminateProcess(id, @enumFromInt(1));
                } else {
                    std.posix.kill(-id, std.posix.SIG.TERM) catch {};
                    var grace_ms: u64 = 500;
                    while (grace_ms > 0 and !fin.load(.acquire)) {
                        std.Io.sleep(watch_io, std.Io.Duration.fromMilliseconds(50), .awake) catch {};
                        grace_ms -= 50;
                    }
                    if (!fin.load(.acquire)) std.posix.kill(-id, std.posix.SIG.KILL) catch {};
                }
                flag.* = true;
            }
        }.run, .{ child_id, io, &timed_out, &finished, timeout_ms }) catch |err| {
            child.kill(io);
            return err;
        };
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

    return HostCommandResult{
        .exit_code = exit_code,
        .timed_out = timed_out,
        .stdout = null,
        .stderr = null,
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

test "child_process: host command resolves through inherited PATH" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const argv = [_][]const u8{ "sh", "-c", "exit 0" };
    const res = try runHostCommandTimed(std.testing.allocator, &argv, 5_000, null, null);
    defer deinitHostCommandResult(res, std.testing.allocator);

    try std.testing.expect(!res.timed_out);
    try std.testing.expectEqual(@as(u8, 0), res.exit_code);
}

test "child_process: ignored high-volume output cannot fill a pipe" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const argv = [_][]const u8{ "sh", "-c", "yes x | head -c 1048576" };
    const res = try runHostCommandTimed(std.testing.allocator, &argv, 5_000, null, null);
    defer deinitHostCommandResult(res, std.testing.allocator);
    try std.testing.expect(!res.timed_out);
    try std.testing.expectEqual(@as(u8, 0), res.exit_code);
}

test "child_process: timeout escalates when child ignores TERM" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const argv = [_][]const u8{ "sh", "-c", "trap '' TERM; sleep 10" };
    const res = try runHostCommandTimed(std.testing.allocator, &argv, 50, null, null);
    defer deinitHostCommandResult(res, std.testing.allocator);
    try std.testing.expect(res.timed_out);
}
