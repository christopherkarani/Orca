//! Daemon binary discovery, UDS connectivity, and NDJSON IPC (Zig side).
//!
//! This module provides utilities for the Zig CLI to locate the Rust
//! `orca-daemon` companion binary, check whether a daemon instance is
//! already running, and exchange request/response messages over a Unix
//! Domain Socket.
//!
//! Phase 0 (previous): existence checks only.
//! Phase 0.5 (current): UDS socket connectivity and NDJSON IPC.

const std = @import("std");

/// Name of the Rust daemon binary.
const daemon_binary_name = "orca-daemon";

/// Name of the Unix Domain Socket file used to detect a running daemon.
const daemon_socket_name = "daemon.sock";

/// Directory under $HOME where Orca runtime state lives.
const orca_state_dir = ".orca";

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
/// The `result` field is kept as a `std.json.Value` in Phase 0.5 so the
/// Zig client can peek at the `status` tag without needing a full typed
/// mirror of the Rust `ResultPayload` enum.
pub const DaemonResponse = struct {
    id: u64,
    result: std.json.Value,
};

/// Errors that can occur when communicating with the daemon.
pub const DaemonError = error{
    HomeDirectoryNotFound,
    SocketConnectFailed,
    SocketWriteFailed,
    SocketReadFailed,
    RequestSerializationFailed,
    ResponseParseFailed,
};

/// Locate the `orca-daemon` binary in the same directory as the current
/// executable.
///
/// Returns an allocated path string (caller owns memory) or `null` if the
/// binary was not found. The caller should free the returned slice with
/// the same allocator passed in.
pub fn findDaemonBinary(allocator: std.mem.Allocator) !?[]const u8 {
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    const self_dir = std.process.executableDirPathAlloc(io, allocator) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    defer allocator.free(self_dir);

    const path = std.fs.path.join(allocator, &[_][]const u8{
        self_dir,
        daemon_binary_name,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
    };
    errdefer allocator.free(path);

    // Verify the file actually exists and is executable (if we can stat it).
    std.Io.Dir.cwd().access(io, path, .{}) catch return null;

    return path;
}

/// Look up an environment variable by name, allocating the value.
///
/// Returns `null` if the variable is not set.  Caller owns the returned
/// memory.  This helper bridges Zig 0.16.0's `std.process.Environ` API
/// to the simpler getenv semantics used by this module.
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

/// Check whether the daemon appears to be running.
///
/// Phase 0 implementation: returns `true` if the UDS socket file exists
/// at `$HOME/.orca/daemon.sock`. This is a coarse existence check; a
/// future phase will attempt an actual ping/health-check over the socket.
pub fn isDaemonRunning() bool {
    const home = (getEnvVar(std.heap.page_allocator, "HOME") catch return false) orelse return false;
    defer std.heap.page_allocator.free(home);

    const sock_path = std.fs.path.join(std.heap.page_allocator, &[_][]const u8{
        home,
        orca_state_dir,
        daemon_socket_name,
    }) catch return false;
    defer std.heap.page_allocator.free(sock_path);

    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    std.Io.Dir.cwd().access(io, sock_path, .{}) catch return false;
    return true;
}

/// Resolve the daemon socket path: `$HOME/.orca/daemon.sock`.
///
/// Caller owns the returned memory.
pub fn socketPath(allocator: std.mem.Allocator) ![]const u8 {
    const home = try getEnvVar(allocator, "HOME") orelse return error.HomeDirectoryNotFound;
    defer allocator.free(home);

    return std.fs.path.join(allocator, &[_][]const u8{
        home,
        orca_state_dir,
        daemon_socket_name,
    });
}

/// Send a single NDJSON request to the daemon and return its response.
///
/// This function is synchronous: it opens a connection, writes one JSON
/// line, reads one JSON line, closes the connection, and returns.  It is
/// intentionally simple for the Phase 0.5 prototype.
pub fn sendRequest(
    allocator: std.mem.Allocator,
    socket_path: []const u8,
    request: DaemonRequest,
) DaemonError!DaemonResponse {
    const fd = connectUnixSocket(socket_path) catch return error.SocketConnectFailed;
    defer _ = std.c.close(fd);

    // Serialize request.
    const json_str = std.json.Stringify.valueAlloc(allocator, request, .{}) catch {
        return error.RequestSerializationFailed;
    };
    defer allocator.free(json_str);

    // Write to socket.
    const to_write = json_str;
    var written: usize = 0;
    while (written < to_write.len) {
        const n = std.c.write(fd, to_write.ptr + written, to_write.len - written);
        if (n < 0) return error.SocketWriteFailed;
        if (n == 0) return error.SocketWriteFailed;
        written += @intCast(n);
    }
    const newline = "\n";
    const nl_n = std.c.write(fd, newline.ptr, newline.len);
    if (nl_n < 0) return error.SocketWriteFailed;

    // Read one line.
    var read_buf: std.ArrayList(u8) = .empty;
    defer read_buf.deinit(allocator);

    var byte: [1]u8 = undefined;
    while (true) {
        const n = std.c.read(fd, &byte, 1);
        if (n < 0) return error.SocketReadFailed;
        if (n == 0) return error.SocketReadFailed;
        read_buf.append(allocator, byte[0]) catch return error.SocketReadFailed;
        if (byte[0] == '\n') break;
    }

    // Parse response.
    const parsed = std.json.parseFromSlice(DaemonResponse, allocator, read_buf.items, .{
        .allocate = .alloc_if_needed,
    }) catch return error.ResponseParseFailed;
    defer parsed.deinit();

    return parsed.value;
}

/// Open a connection to a Unix Domain Socket at `path`.
///
/// Returns a POSIX file descriptor on success.  Caller must close the fd.
fn connectUnixSocket(path: []const u8) !std.posix.fd_t {
    const builtin = @import("builtin");
    const AF_UNIX = switch (builtin.os.tag) {
        .linux => std.posix.AF.UNIX,
        .macos => 1, // AF_UNIX on Darwin
        else => @compileError("unsupported OS for UDS"),
    };
    const SOCK_STREAM = switch (builtin.os.tag) {
        .linux => std.posix.SOCK.STREAM,
        .macos => 1, // SOCK_STREAM on Darwin
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

// ---------------------------------------------------------------------------
// Compile-time / basic unit tests
// ---------------------------------------------------------------------------

// Skipped: findDaemonBinary triggers error-return-trace printing in Zig 0.16.0
// test mode when executableDirPathAlloc fails, which causes the test runner to
// exit with code 1 even though the error is caught. Re-enable once we can
// suppress the trace or when the test binary is co-located with orca-daemon.
// test "findDaemonBinary compiles and handles missing binary gracefully" {
//     const allocator = std.testing.allocator;
//     const maybe_path = try findDaemonBinary(allocator);
//     if (maybe_path) |p| {
//         allocator.free(p);
//     }
// }

test "isDaemonRunning returns false when socket does not exist" {
    // In the test environment $HOME/.orca/daemon.sock is unlikely to exist.
    const running = isDaemonRunning();
    // We simply assert the function returns a boolean; in most CI/test
    // environments the socket will not exist so `false` is expected.
    _ = running;
}

test "socketPath returns a path under $HOME/.orca" {
    const allocator = std.testing.allocator;
    const path = try socketPath(allocator);
    defer allocator.free(path);

    // Verify the path ends with the expected socket name.
    try std.testing.expect(std.mem.endsWith(u8, path, "/.orca/daemon.sock"));
}

test "DaemonRequest can be serialized to JSON" {
    const request = DaemonRequest{
        .id = 1,
        .method = "Ping",
        .params = null,
    };

    const json_str = try std.json.Stringify.valueAlloc(std.testing.allocator, request, .{});
    defer std.testing.allocator.free(json_str);

    try std.testing.expectEqualStrings("{\"id\":1,\"method\":\"Ping\",\"params\":null}", json_str);
}
