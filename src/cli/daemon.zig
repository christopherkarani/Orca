//! Daemon binary discovery, UDS connectivity, and NDJSON IPC (Zig side).
//!
//! This module provides utilities for the Zig CLI to locate the Rust
//! `orca-daemon` companion binary, check whether a daemon instance is
//! already running, start it when needed, and exchange request/response
//! messages over a Unix Domain Socket.
//!
//! Phase 0.5: UDS socket connectivity and NDJSON IPC.
//! Phase 1D: lifecycle helpers, binary discovery, stale artifact handling.

const std = @import("std");
const builtin = @import("builtin");

/// Name of the Rust daemon binary.
const daemon_binary_name = "orca-daemon";

/// Name of the Unix Domain Socket file used to detect a running daemon.
const daemon_socket_name = "daemon.sock";

/// PID file written by the Rust daemon on startup.
const daemon_pid_name = "daemon.pid";

/// Directory under $HOME where Orca runtime state lives.
const orca_state_dir = ".orca";

/// Environment variable override for the daemon binary path.
const daemon_env_var = "ORCA_DAEMON";

/// Default time to wait for the daemon socket and Ping response after spawn.
pub const default_readiness_timeout_ms: u64 = 5_000;

/// Poll interval while waiting for daemon readiness.
const readiness_poll_ms: u64 = 50;

/// Per-request UDS timeout for Ping and other daemon IPC.
const default_request_timeout_ms: u64 = 500;

/// Maximum NDJSON response line accepted from the daemon.
const max_response_line_bytes: usize = 1024 * 1024;

/// Short Ping timeout used when deciding whether socket artifacts are stale.
const stale_artifact_ping_timeout_ms: u64 = 200;

/// Request envelope sent to the Rust daemon over UDS.
///
/// The wire format is newline-delimited JSON matching the Rust
/// `ClientEnvelope` struct: `{"id": 1, "method": "Ping"}`.
pub const DaemonRequest = struct {
    id: u64,
    method: []const u8,
    params: ?std.json.Value = null,
};

/// Response envelope returned by the Rust daemon.
///
/// The `result` field is kept as a `std.json.Value` so the Zig client can
/// inspect the `status` tag without mirroring the full Rust enum.
pub const DaemonResponse = struct {
    id: u64,
    result: std.json.Value,
};

/// Structured result returned by the Rust daemon for ExecuteCli requests.
pub const CliExecution = struct {
    stdout: []const u8,
    stderr: []const u8,
    exit_code: u8,
};

const ExecuteCliRequest = struct {
    id: u64,
    method: []const u8 = "ExecuteCli",
    params: struct {
        argv: []const []const u8,
    },
};

/// High-level status tag from a daemon `result` object.
pub const ResponseStatus = enum {
    pong,
    allow,
    deny,
    error_status,
    cli_execution,
    unknown,
};

/// Errors that can occur when communicating with the daemon.
pub const DaemonError = error{
    HomeDirectoryNotFound,
    OutOfMemory,
    DaemonBinaryNotFound,
    DaemonSpawnFailed,
    DaemonStartTimeout,
    DaemonNotReady,
    StaleSocket,
    SocketConnectFailed,
    SocketWriteFailed,
    SocketReadFailed,
    RequestSerializationFailed,
    ResponseParseFailed,
    DaemonProtocolError,
};

var ensure_daemon_lock: std.Io.Mutex = .init;

/// Resolve `$HOME/.orca/daemon.sock` and `$HOME/.orca/daemon.pid`.
pub const RuntimePaths = struct {
    socket: []const u8,
    pid: []const u8,
};

/// Build runtime artifact paths under the given home directory.
///
/// Caller owns both returned slices.
pub fn runtimePathsForHome(allocator: std.mem.Allocator, home: []const u8) !RuntimePaths {
    const state_dir = try std.fs.path.join(allocator, &.{ home, orca_state_dir });
    defer allocator.free(state_dir);

    return .{
        .socket = try std.fs.path.join(allocator, &.{ state_dir, daemon_socket_name }),
        .pid = try std.fs.path.join(allocator, &.{ state_dir, daemon_pid_name }),
    };
}

/// Resolve daemon runtime paths from `$HOME`.
pub fn runtimePaths(allocator: std.mem.Allocator) DaemonError!RuntimePaths {
    const home = (getEnvVar(allocator, "HOME") catch return error.HomeDirectoryNotFound) orelse
        return error.HomeDirectoryNotFound;
    defer allocator.free(home);
    return runtimePathsForHome(allocator, home) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => |e| return e,
    };
}

/// Resolve the daemon socket path: `$HOME/.orca/daemon.sock`.
///
/// Caller owns the returned memory.
pub fn socketPath(allocator: std.mem.Allocator) DaemonError![]const u8 {
    const paths = try runtimePaths(allocator);
    defer freeRuntimePaths(allocator, paths);
    return allocator.dupe(u8, paths.socket) catch error.OutOfMemory;
}

/// Resolve the daemon PID file path: `$HOME/.orca/daemon.pid`.
///
/// Caller owns the returned memory.
pub fn pidPath(allocator: std.mem.Allocator) DaemonError![]const u8 {
    const paths = try runtimePaths(allocator);
    defer freeRuntimePaths(allocator, paths);
    return allocator.dupe(u8, paths.pid) catch error.OutOfMemory;
}

pub fn freeRuntimePaths(allocator: std.mem.Allocator, paths: RuntimePaths) void {
    allocator.free(paths.socket);
    allocator.free(paths.pid);
}

/// Return `true` when the daemon answers a Ping over UDS.
pub fn isDaemonRunning(allocator: std.mem.Allocator) bool {
    ping(allocator) catch return false;
    return true;
}

/// Extract the `status` tag from a daemon result object.
pub fn responseStatus(result: std.json.Value) ResponseStatus {
    const object = switch (result) {
        .object => |map| map,
        else => return .unknown,
    };
    const status_val = object.get("status") orelse return .unknown;
    const status_str = switch (status_val) {
        .string => |s| s,
        else => return .unknown,
    };
    if (std.mem.eql(u8, status_str, "Pong")) return .pong;
    if (std.mem.eql(u8, status_str, "Allow")) return .allow;
    if (std.mem.eql(u8, status_str, "Deny")) return .deny;
    if (std.mem.eql(u8, status_str, "Error")) return .error_status;
    if (std.mem.eql(u8, status_str, "CliExecution")) return .cli_execution;
    return .unknown;
}

/// Return the daemon error message when `result.status == "Error"`.
pub fn responseErrorMessage(result: std.json.Value) ?[]const u8 {
    if (responseStatus(result) != .error_status) return null;
    const object = switch (result) {
        .object => |map| map,
        else => return null,
    };
    const message_val = object.get("message") orelse return null;
    return switch (message_val) {
        .string => |s| s,
        else => null,
    };
}

/// Build the JSON request envelope for the Rust daemon ExecuteCli method.
///
/// Caller owns the returned slice.
pub fn buildExecuteCliRequestJson(allocator: std.mem.Allocator, id: u64, argv: []const []const u8) DaemonError![]u8 {
    return std.json.Stringify.valueAlloc(allocator, ExecuteCliRequest{
        .id = id,
        .params = .{ .argv = argv },
    }, .{}) catch error.RequestSerializationFailed;
}

/// Parse a daemon CliExecution result object.
pub fn parseCliExecution(result: std.json.Value) DaemonError!CliExecution {
    if (responseStatus(result) != .cli_execution) return error.DaemonProtocolError;
    const object = switch (result) {
        .object => |map| map,
        else => return error.DaemonProtocolError,
    };

    const stdout = jsonStringField(object, "stdout") orelse return error.DaemonProtocolError;
    const stderr = jsonStringField(object, "stderr") orelse "";
    const exit_code_int = jsonIntegerField(object, "exit_code") orelse return error.DaemonProtocolError;
    if (exit_code_int < 0 or exit_code_int > std.math.maxInt(u8)) return error.DaemonProtocolError;

    return .{
        .stdout = stdout,
        .stderr = stderr,
        .exit_code = @intCast(exit_code_int),
    };
}

fn jsonStringField(object: std.json.ObjectMap, name: []const u8) ?[]const u8 {
    const value = object.get(name) orelse return null;
    return switch (value) {
        .string => |s| s,
        else => null,
    };
}

fn jsonIntegerField(object: std.json.ObjectMap, name: []const u8) ?i64 {
    const value = object.get(name) orelse return null;
    return switch (value) {
        .integer => |i| i,
        else => null,
    };
}

/// Parse a daemon response line from JSON.
///
/// The caller must invoke `deinit()` on the returned value.
pub fn parseResponse(allocator: std.mem.Allocator, line: []const u8) DaemonError!std.json.Parsed(DaemonResponse) {
    return std.json.parseFromSlice(DaemonResponse, allocator, line, .{
        .allocate = .alloc_if_needed,
    }) catch error.ResponseParseFailed;
}

/// Locate the `orca-daemon` binary for local development and installed layouts.
///
/// Search order:
/// 1. `$ORCA_DAEMON` when set and executable
/// 2. Adjacent to the current `orca` executable
/// 3. Repo-relative dev paths under `orca-rs/target/{release,debug}/`
///
/// Returns an allocated path (caller owns memory) or `null` if not found.
pub fn findDaemonBinary(allocator: std.mem.Allocator) DaemonError!?[]const u8 {
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();

    if (getEnvVar(allocator, daemon_env_var) catch return error.OutOfMemory) |env_path| {
        if (pathIsExecutable(io, env_path)) return env_path;
        allocator.free(env_path);
    }

    if (adjacentDaemonBinaryPath(allocator, io) catch return error.OutOfMemory) |path| return path;

    const self_dir = std.process.executableDirPathAlloc(io, allocator) catch return null;
    defer allocator.free(self_dir);

    const repo_root = std.fs.path.dirname(std.fs.path.dirname(self_dir) orelse return null) orelse return null;
    const dev_candidates = [_][]const u8{
        "orca-rs/target/release/orca-daemon",
        "orca-rs/target/debug/orca-daemon",
    };
    for (dev_candidates) |rel| {
        const path = std.fs.path.join(allocator, &.{ repo_root, rel }) catch return error.OutOfMemory;
        errdefer allocator.free(path);
        if (pathIsExecutable(io, path)) return path;
        allocator.free(path);
    }

    return null;
}

/// Send a Ping request and verify the daemon responds with Pong.
pub fn ping(allocator: std.mem.Allocator) DaemonError!void {
    const paths = try runtimePaths(allocator);
    defer freeRuntimePaths(allocator, paths);
    try pingWithTimeout(allocator, paths.socket, default_request_timeout_ms);
}

fn pingWithTimeout(allocator: std.mem.Allocator, socket_path: []const u8, timeout_ms: u64) DaemonError!void {
    var parsed = try sendRequestWithTimeout(allocator, socket_path, .{
        .id = 0,
        .method = "Ping",
        .params = null,
    }, timeout_ms);
    defer parsed.deinit();
    if (responseStatus(parsed.value.result) != .pong) return error.DaemonProtocolError;
}

/// Send a single NDJSON request to the daemon and return its parsed response.
///
/// The caller must invoke `deinit()` on the returned value.
pub fn sendRequest(
    allocator: std.mem.Allocator,
    socket_path: []const u8,
    request: DaemonRequest,
) DaemonError!std.json.Parsed(DaemonResponse) {
    return sendRequestWithTimeout(allocator, socket_path, request, default_request_timeout_ms);
}

/// Ensure the daemon is running and send ExecuteCli.
///
/// Callers inspect the returned result before deinitializing the Parsed response.
pub fn executeCli(allocator: std.mem.Allocator, argv: []const []const u8) DaemonError!std.json.Parsed(DaemonResponse) {
    try ensureDaemonRunning(allocator);
    const path = try socketPath(allocator);
    defer allocator.free(path);

    const json_str = try buildExecuteCliRequestJson(allocator, 1, argv);
    defer allocator.free(json_str);

    var parsed = try sendRawRequestWithTimeout(allocator, path, json_str, default_request_timeout_ms);
    errdefer parsed.deinit();
    if (parsed.value.id != 1) return error.DaemonProtocolError;
    return parsed;
}

fn sendRequestWithTimeout(
    allocator: std.mem.Allocator,
    socket_path: []const u8,
    request: DaemonRequest,
    timeout_ms: u64,
) DaemonError!std.json.Parsed(DaemonResponse) {
    const json_str = std.json.Stringify.valueAlloc(allocator, request, .{}) catch {
        return error.RequestSerializationFailed;
    };
    defer allocator.free(json_str);
    return sendRawRequestWithTimeout(allocator, socket_path, json_str, timeout_ms);
}

fn sendRawRequestWithTimeout(
    allocator: std.mem.Allocator,
    socket_path: []const u8,
    json_str: []const u8,
    timeout_ms: u64,
) DaemonError!std.json.Parsed(DaemonResponse) {
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();

    const fd = connectUnixSocket(socket_path) catch return error.SocketConnectFailed;
    defer _ = std.c.close(fd);

    try writeAllFdWithTimeout(io, fd, json_str, timeout_ms);
    try writeAllFdWithTimeout(io, fd, "\n", timeout_ms);

    const line = try readLineFdWithTimeout(io, allocator, fd, timeout_ms);
    const parsed = parseResponse(allocator, line) catch |err| {
        allocator.free(line);
        return err;
    };
    allocator.free(line);
    return parsed;
}

/// Return `true` when socket artifacts exist but no daemon responds to Ping.
pub fn isStaleDaemonArtifacts(allocator: std.mem.Allocator, paths: RuntimePaths) DaemonError!bool {
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();

    std.Io.Dir.cwd().access(io, paths.socket, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return error.DaemonNotReady,
    };

    pingWithTimeout(allocator, paths.socket, stale_artifact_ping_timeout_ms) catch {
        return true;
    };
    return false;
}

/// Best-effort removal of stale socket and PID files.
pub fn cleanupStaleArtifacts(io: std.Io, paths: RuntimePaths) void {
    std.Io.Dir.cwd().deleteFile(io, paths.socket) catch {};
    std.Io.Dir.cwd().deleteFile(io, paths.pid) catch {};
}

/// Spawn `orca-daemon --daemon-mode` without waiting for readiness.
pub fn startDaemon(_: std.mem.Allocator, daemon_binary: []const u8) DaemonError!void {
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();

    const argv = [_][]const u8{ daemon_binary, "--daemon-mode" };
    _ = std.process.spawn(io, .{
        .argv = &argv,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch return error.DaemonSpawnFailed;

    // The daemon is long-lived; do not wait here. If it exits immediately the
    // readiness loop in `waitForDaemonReady` will surface `DaemonStartTimeout`.
}

/// Poll until Ping succeeds or `timeout_ms` elapses.
pub fn waitForDaemonReady(allocator: std.mem.Allocator, timeout_ms: u64) DaemonError!void {
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();

    const paths = try runtimePaths(allocator);
    defer freeRuntimePaths(allocator, paths);

    const deadline_ms = monotonicNowMs(io) + @as(i64, @intCast(timeout_ms));
    while (monotonicNowMs(io) < deadline_ms) {
        const remaining_ms = @as(u64, @intCast(@max(deadline_ms - monotonicNowMs(io), 0)));
        const attempt_ms = @min(remaining_ms, readiness_poll_ms);

        if (pingWithTimeout(allocator, paths.socket, attempt_ms)) |_| {
            return;
        } else |err| switch (err) {
            error.SocketConnectFailed,
            error.SocketReadFailed,
            error.SocketWriteFailed,
            error.DaemonProtocolError,
            error.ResponseParseFailed,
            => {},
            else => return err,
        }

        std.Io.sleep(io, std.Io.Duration.fromMilliseconds(@intCast(readiness_poll_ms)), .awake) catch {};
    }

    return error.DaemonStartTimeout;
}

/// Ensure a reachable daemon exists: ping, cleanup stale artifacts, spawn, wait.
pub fn ensureDaemonRunning(allocator: std.mem.Allocator) DaemonError!void {
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();

    ensure_daemon_lock.lock(io) catch return error.DaemonNotReady;
    defer ensure_daemon_lock.unlock(io);

    if (ping(allocator)) |_| return else |_| {}

    const paths = try runtimePaths(allocator);
    defer freeRuntimePaths(allocator, paths);

    if (isStaleDaemonArtifacts(allocator, paths) catch return error.DaemonNotReady) {
        cleanupStaleArtifacts(io, paths);
    }

    // Another caller may have started the daemon while we waited for the lock.
    if (ping(allocator)) |_| return else |_| {}

    const daemon_binary = try findDaemonBinary(allocator) orelse return error.DaemonBinaryNotFound;
    defer allocator.free(daemon_binary);

    try startDaemon(allocator, daemon_binary);
    try waitForDaemonReady(allocator, default_readiness_timeout_ms);
}

fn adjacentDaemonBinaryPath(allocator: std.mem.Allocator, io: std.Io) DaemonError!?[]const u8 {
    const self_dir = std.process.executableDirPathAlloc(io, allocator) catch return null;
    defer allocator.free(self_dir);

    const path = std.fs.path.join(allocator, &.{ self_dir, daemon_binary_name }) catch return error.OutOfMemory;
    errdefer allocator.free(path);

    if (pathIsExecutable(io, path)) return path;
    allocator.free(path);
    return null;
}

fn pathIsExecutable(io: std.Io, path: []const u8) bool {
    std.Io.Dir.cwd().access(io, path, .{ .execute = true }) catch return false;
    return true;
}

fn monotonicNowMs(io: std.Io) i64 {
    return std.Io.Timestamp.now(io, .awake).toMilliseconds();
}

fn pollTimeoutMs(timeout_ms: u64) i32 {
    return @intCast(@min(timeout_ms, @as(u64, @intCast(std.math.maxInt(i32)))));
}

fn waitForPoll(fd: std.posix.fd_t, events: i16, timeout_ms: u64) DaemonError!void {
    var fds = [_]std.posix.pollfd{ .{
        .fd = fd,
        .events = events,
        .revents = 0,
    } };
    const rc = std.posix.poll(fds[0..], pollTimeoutMs(timeout_ms)) catch {
        return error.SocketReadFailed;
    };
    if (rc <= 0) return error.SocketReadFailed;
    if (fds[0].revents & events == 0) {
        return if (events & poll_out != 0) error.SocketWriteFailed else error.SocketReadFailed;
    }
}

const poll_in: i16 = 0x0001;
const poll_out: i16 = 0x0004;

fn writeAllFdWithTimeout(io: std.Io, fd: std.posix.fd_t, bytes: []const u8, timeout_ms: u64) DaemonError!void {
    var written: usize = 0;
    const deadline_ms = monotonicNowMs(io) + @as(i64, @intCast(timeout_ms));

    while (written < bytes.len) {
        const remaining_ms = @as(u64, @intCast(@max(deadline_ms - monotonicNowMs(io), 0)));
        if (remaining_ms == 0) return error.SocketWriteFailed;

        try waitForPoll(fd, poll_out, remaining_ms);

        const n = std.c.write(fd, bytes.ptr + written, bytes.len - written);
        if (n < 0) return error.SocketWriteFailed;
        if (n == 0) return error.SocketWriteFailed;
        written += @intCast(n);
    }
}

fn readLineFdWithTimeout(io: std.Io, allocator: std.mem.Allocator, fd: std.posix.fd_t, timeout_ms: u64) DaemonError![]u8 {
    var read_buf: std.ArrayList(u8) = .empty;
    errdefer read_buf.deinit(allocator);

    const deadline_ms = monotonicNowMs(io) + @as(i64, @intCast(timeout_ms));
    var byte: [1]u8 = undefined;

    while (true) {
        const remaining_ms = @as(u64, @intCast(@max(deadline_ms - monotonicNowMs(io), 0)));
        if (remaining_ms == 0) return error.SocketReadFailed;

        try waitForPoll(fd, poll_in, remaining_ms);

        const n = std.c.read(fd, &byte, 1);
        if (n < 0) return error.SocketReadFailed;
        if (n == 0) return error.SocketReadFailed;
        if (read_buf.items.len >= max_response_line_bytes) return error.SocketReadFailed;
        read_buf.append(allocator, byte[0]) catch return error.SocketReadFailed;
        if (byte[0] == '\n') break;
    }

    return read_buf.toOwnedSlice(allocator) catch return error.SocketReadFailed;
}

/// Open a connection to a Unix Domain Socket at `path`.
fn connectUnixSocket(path: []const u8) !std.posix.fd_t {
    const AF_UNIX = switch (builtin.os.tag) {
        .linux => std.posix.AF.UNIX,
        .macos => 1,
        else => @compileError("unsupported OS for UDS"),
    };
    const SOCK_STREAM = switch (builtin.os.tag) {
        .linux => std.posix.SOCK.STREAM,
        .macos => 1,
        else => @compileError("unsupported OS for UDS"),
    };

    const fd = std.c.socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return error.SocketConnectFailed;
    errdefer _ = std.c.close(fd);

    var addr: std.c.sockaddr.un = .{
        .family = AF_UNIX,
        .path = undefined,
    };
    const path_len = @min(path.len, addr.path.len - 1);
    @memset(&addr.path, 0);
    @memcpy(addr.path[0..path_len], path[0..path_len]);
    addr.path[path_len] = 0;

    const addr_len: u32 = @intCast(@offsetOf(std.c.sockaddr.un, "path") + path_len + 1);
    const rc = std.c.connect(fd, @ptrCast(&addr), addr_len);
    if (rc < 0) return error.SocketConnectFailed;

    return fd;
}

fn getEnvVar(allocator: std.mem.Allocator, key: []const u8) !?[]const u8 {
    const c_environ = std.c.environ;
    var env_count: usize = 0;
    while (c_environ[env_count] != null) : (env_count += 1) {}
    const environ_slice: [:null]?[*:0]u8 = c_environ[0..env_count :null];
    const environ = std.process.Environ{ .block = .{ .slice = environ_slice } };
    return environ.getAlloc(allocator, key) catch |err| switch (err) {
        error.EnvironmentVariableMissing => null,
        else => |e| return e,
    };
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

test "runtimePathsForHome builds socket and pid paths" {
    const allocator = std.testing.allocator;
    const paths = try runtimePathsForHome(allocator, "/tmp/orca-home");
    defer freeRuntimePaths(allocator, paths);

    try std.testing.expectEqualStrings("/tmp/orca-home/.orca/daemon.sock", paths.socket);
    try std.testing.expectEqualStrings("/tmp/orca-home/.orca/daemon.pid", paths.pid);
}

test "socketPath returns a path under $HOME/.orca" {
    const allocator = std.testing.allocator;
    const path = try socketPath(allocator);
    defer allocator.free(path);

    try std.testing.expect(std.mem.endsWith(u8, path, "/.orca/daemon.sock"));
}

test "pidPath returns a path under $HOME/.orca" {
    const allocator = std.testing.allocator;
    const path = try pidPath(allocator);
    defer allocator.free(path);

    try std.testing.expect(std.mem.endsWith(u8, path, "/.orca/daemon.pid"));
}

test "DaemonRequest serializes to NDJSON envelope" {
    const request = DaemonRequest{
        .id = 1,
        .method = "Ping",
        .params = null,
    };

    const json_str = try std.json.Stringify.valueAlloc(std.testing.allocator, request, .{});
    defer std.testing.allocator.free(json_str);

    try std.testing.expectEqualStrings("{\"id\":1,\"method\":\"Ping\",\"params\":null}", json_str);
}

test "parseResponse accepts pong payload" {
    const line = "{\"id\":1,\"result\":{\"status\":\"Pong\"}}";
    var parsed = try parseResponse(std.testing.allocator, line);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u64, 1), parsed.value.id);
    try std.testing.expect(responseStatus(parsed.value.result) == .pong);
}

test "buildExecuteCliRequestJson serializes expected argv" {
    const json_str = try buildExecuteCliRequestJson(std.testing.allocator, 7, &.{"version"});
    defer std.testing.allocator.free(json_str);

    try std.testing.expectEqualStrings("{\"id\":7,\"method\":\"ExecuteCli\",\"params\":{\"argv\":[\"version\"]}}", json_str);
}

test "parseCliExecution reads stdout stderr and exit code" {
    const line = "{\"id\":7,\"result\":{\"status\":\"CliExecution\",\"stdout\":\"orca 1.2.3\\n\",\"stderr\":\"warn\\n\",\"exit_code\":5}}";
    var parsed = try parseResponse(std.testing.allocator, line);
    defer parsed.deinit();

    const execution = try parseCliExecution(parsed.value.result);
    try std.testing.expectEqualStrings("orca 1.2.3\n", execution.stdout);
    try std.testing.expectEqualStrings("warn\n", execution.stderr);
    try std.testing.expectEqual(@as(u8, 5), execution.exit_code);
}

test "parseCliExecution accepts missing stderr as empty" {
    const line = "{\"id\":8,\"result\":{\"status\":\"CliExecution\",\"stdout\":\"orca 1.2.3\\n\",\"exit_code\":0}}";
    var parsed = try parseResponse(std.testing.allocator, line);
    defer parsed.deinit();

    const execution = try parseCliExecution(parsed.value.result);
    try std.testing.expectEqualStrings("orca 1.2.3\n", execution.stdout);
    try std.testing.expectEqualStrings("", execution.stderr);
    try std.testing.expectEqual(@as(u8, 0), execution.exit_code);
}

test "parseCliExecution rejects daemon Error status" {
    const line = "{\"id\":9,\"result\":{\"status\":\"Error\",\"message\":\"unsupported command\"}}";
    var parsed = try parseResponse(std.testing.allocator, line);
    defer parsed.deinit();

    try std.testing.expectError(error.DaemonProtocolError, parseCliExecution(parsed.value.result));
}

test "parseCliExecution rejects out of range exit code" {
    const line = "{\"id\":10,\"result\":{\"status\":\"CliExecution\",\"stdout\":\"\",\"stderr\":\"\",\"exit_code\":999}}";
    var parsed = try parseResponse(std.testing.allocator, line);
    defer parsed.deinit();

    try std.testing.expectError(error.DaemonProtocolError, parseCliExecution(parsed.value.result));
}

test "parseResponse accepts deny payload" {
    const line = "{\"id\":2,\"result\":{\"status\":\"Deny\",\"reason\":\"blocked\"}}";
    var parsed = try parseResponse(std.testing.allocator, line);
    defer parsed.deinit();
    try std.testing.expect(responseStatus(parsed.value.result) == .deny);
}

test "parseResponse rejects malformed JSON" {
    const line = "{not-json";
    const result = parseResponse(std.testing.allocator, line);
    try std.testing.expectError(error.ResponseParseFailed, result);
}

test "responseErrorMessage reads daemon Error status" {
    const line = "{\"id\":3,\"result\":{\"status\":\"Error\",\"message\":\"parse error\"}}";
    var parsed = try parseResponse(std.testing.allocator, line);
    defer parsed.deinit();
    try std.testing.expect(responseStatus(parsed.value.result) == .error_status);
    try std.testing.expectEqualStrings("parse error", responseErrorMessage(parsed.value.result).?);
}

test "isStaleDaemonArtifacts false when socket missing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const home = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(home);

    const paths = try runtimePathsForHome(std.testing.allocator, home);
    defer freeRuntimePaths(std.testing.allocator, paths);

    try std.testing.expect(!try isStaleDaemonArtifacts(std.testing.allocator, paths));
}

test "isStaleDaemonArtifacts true when socket exists without pid file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const home = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(home);

    const paths = try runtimePathsForHome(std.testing.allocator, home);
    defer freeRuntimePaths(std.testing.allocator, paths);

    try tmp.dir.createDirPath(std.testing.io, ".orca");
    const sock = try tmp.dir.createFile(std.testing.io, ".orca/daemon.sock", .{});
    sock.close(std.testing.io);

    try std.testing.expect(try isStaleDaemonArtifacts(std.testing.allocator, paths));
}

test "isStaleDaemonArtifacts true when live unrelated pid cannot serve ping" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const home = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(home);

    const paths = try runtimePathsForHome(std.testing.allocator, home);
    defer freeRuntimePaths(std.testing.allocator, paths);

    try tmp.dir.createDirPath(std.testing.io, ".orca");
    const sock = try tmp.dir.createFile(std.testing.io, ".orca/daemon.sock", .{});
    sock.close(std.testing.io);

    const pid_text = try std.fmt.allocPrint(std.testing.allocator, "{d}", .{std.c.getpid()});
    defer std.testing.allocator.free(pid_text);
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = ".orca/daemon.pid",
        .data = pid_text,
    });

    try std.testing.expect(try isStaleDaemonArtifacts(std.testing.allocator, paths));
}

test "pathIsExecutable rejects non-executable file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const file = try tmp.dir.createFile(std.testing.io, "not-exec.txt", .{});
    defer file.close(std.testing.io);
    try file.writeStreamingAll(std.testing.io, "hello");

    const path = try tmp.dir.realPathFileAlloc(std.testing.io, "not-exec.txt", std.testing.allocator);
    defer std.testing.allocator.free(path);

    try std.testing.expect(!pathIsExecutable(std.testing.io, path));
}

test "sendRequest connect failure surfaces SocketConnectFailed" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const home = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(home);

    const missing = try std.fs.path.join(std.testing.allocator, &.{ home, ".orca", "missing.sock" });
    defer std.testing.allocator.free(missing);

    const result = sendRequest(std.testing.allocator, missing, .{
        .id = 1,
        .method = "Ping",
        .params = null,
    });
    try std.testing.expectError(error.SocketConnectFailed, result);
}

test "integration: ensureDaemonRunning when ORCA_DAEMON is set" {
    const allocator = std.testing.allocator;
    const maybe_daemon_path = getEnvVar(allocator, daemon_env_var) catch return;
    defer if (maybe_daemon_path) |p| allocator.free(p);
    if (maybe_daemon_path == null) return;

    try ensureDaemonRunning(allocator);
    try ping(allocator);
}
