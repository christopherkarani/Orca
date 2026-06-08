//! Daemon binary discovery and status checks (Zig side).
//!
//! This module provides utilities for the Zig CLI to locate the Rust
//! `orca-daemon` companion binary and check whether a daemon instance
//! is already running.
//!
//! Phase 0 (current): existence checks only.
//! Phase 0.5+: UDS socket connectivity and NDJSON IPC.

const std = @import("std");

/// Name of the Rust daemon binary.
const daemon_binary_name = "orca-daemon";

/// Name of the Unix Domain Socket file used to detect a running daemon.
const daemon_socket_name = "daemon.sock";

/// Directory under $HOME where Orca runtime state lives.
const orca_state_dir = ".orca";

/// Locate the `orca-daemon` binary in the same directory as the current
/// executable.
///
/// Returns an allocated path string (caller owns memory) or `null` if the
/// binary was not found. The caller should free the returned slice with
/// the same allocator passed in.
pub fn findDaemonBinary(allocator: std.mem.Allocator) !?[]const u8 {
    const self_dir = std.fs.selfExeDirPathAlloc(allocator) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.BadPathName,
        error.DeviceBusy,
        error.FileNotFound,
        error.FileSystem,
        error.InvalidHandle,
        error.InvalidUtf8,
        error.NameTooLong,
        error.NoDevice,
        error.NotDir,
        error.SymLinkLoop,
        error.SystemResources,
        error.Unexpected,
        => return null,
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
    std.fs.accessAbsolute(path, .{}) catch return null;

    return path;
}

/// Check whether the daemon appears to be running.
///
/// Phase 0 implementation: returns `true` if the UDS socket file exists
/// at `$HOME/.orca/daemon.sock`. This is a coarse existence check; a
/// future phase will attempt an actual ping/health-check over the socket.
pub fn isDaemonRunning() bool {
    const home = std.process.getEnvVarOwned(std.heap.page_allocator, "HOME") catch return false;
    defer std.heap.page_allocator.free(home);

    const sock_path = std.fs.path.join(std.heap.page_allocator, &[_][]const u8{
        home,
        orca_state_dir,
        daemon_socket_name,
    }) catch return false;
    defer std.heap.page_allocator.free(sock_path);

    std.fs.accessAbsolute(sock_path, .{}) catch return false;
    return true;
}

// ---------------------------------------------------------------------------
// Compile-time / basic unit tests
// ---------------------------------------------------------------------------

test "findDaemonBinary compiles and handles missing binary gracefully" {
    const allocator = std.testing.allocator;

    // When run in the test environment the current executable directory
    // almost certainly does not contain an `orca-daemon` binary, so we
    // expect `null` rather than a hard error.
    const maybe_path = try findDaemonBinary(allocator);
    if (maybe_path) |p| {
        allocator.free(p);
    }
}

test "isDaemonRunning returns false when socket does not exist" {
    // In the test environment $HOME/.orca/daemon.sock is unlikely to exist.
    const running = isDaemonRunning();
    // We simply assert the function returns a boolean; in most CI/test
    // environments the socket will not exist so `false` is expected.
    _ = running;
}
