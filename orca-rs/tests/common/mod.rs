//! Common test utilities for ORCA history E2E tests.
//!
//! This module provides shared infrastructure for testing history functionality:
//! - Isolated test databases via `TestDb`
//! - Test fixtures for realistic command data
//! - Logging utilities for debugging test failures
//!
//! # Usage
//!
//! ```ignore
//! mod common;
//! use common::db::TestDb;
//!
//! #[test]
//! fn my_test() {
//!     let test_db = TestDb::new();
//!     // Use test_db.db for testing...
//! }
//! ```

pub mod db;
pub mod fixtures;
pub mod logging;

// ------------------------------------------------------------------
// Daemon lifecycle helpers (added for Phase 5 socket micro-tests)
// ------------------------------------------------------------------

use std::io::{BufRead, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, Stdio};
use std::time::Duration;
use std::{io, thread};

/// Spawn `orca-daemon --daemon-mode` with `HOME` set to `home_dir`.
pub fn spawn_daemon(home_dir: &Path) -> Child {
    let bin = assert_cmd::cargo::cargo_bin("orca-daemon");
    std::process::Command::new(bin)
        .arg("--daemon-mode")
        .env("HOME", home_dir)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("failed to spawn daemon")
}

/// Poll until the socket file exists, panicking after `timeout`.
pub fn wait_for_socket(socket_path: &Path, timeout: Duration) {
    let start = std::time::Instant::now();
    while !socket_path.exists() {
        if start.elapsed() > timeout {
            panic!("timed out waiting for socket at {}", socket_path.display());
        }
        thread::sleep(Duration::from_millis(50));
    }
}

/// Poll until the daemon is actually accepting connections.
///
/// Unlike `wait_for_socket` this verifies the socket is bound and
/// writable, which is necessary when a previous daemon may have left
/// a stale socket file behind.
pub fn wait_for_daemon_ready(socket_path: &Path, timeout: Duration) {
    let start = std::time::Instant::now();
    loop {
        if start.elapsed() > timeout {
            panic!(
                "timed out waiting for daemon to accept connections at {}",
                socket_path.display()
            );
        }
        if let Ok(mut stream) = std::os::unix::net::UnixStream::connect(socket_path) {
            stream.set_write_timeout(Some(Duration::from_secs(1))).ok();
            let req = r#"{"id":0,"method":"Ping"}"#;
            if stream.write_all(req.as_bytes()).is_ok()
                && stream.write_all(b"\n").is_ok()
                && stream.flush().is_ok()
            {
                return;
            }
        }
        thread::sleep(Duration::from_millis(50));
    }
}

/// Send an NDJSON request to the daemon and return the response line.
pub fn send_request(socket_path: &Path, request: &str) -> String {
    let mut stream = std::os::unix::net::UnixStream::connect(socket_path)
        .expect("failed to connect to daemon socket");
    stream
        .set_read_timeout(Some(Duration::from_secs(5)))
        .expect("failed to set read timeout");

    stream
        .write_all(request.as_bytes())
        .expect("failed to write request");
    stream.write_all(b"\n").expect("failed to write newline");
    stream.flush().expect("failed to flush");

    let mut reader = io::BufReader::new(&stream);
    let mut line = String::new();
    reader
        .read_line(&mut line)
        .expect("failed to read response");
    line
}

/// Send a Ping request and return the response line.
pub fn send_ping(socket_path: &Path) -> String {
    send_request(socket_path, r#"{"id":1,"method":"Ping"}"#)
}

/// Send a Shutdown request and return the response line.
pub fn send_shutdown(socket_path: &Path) -> String {
    send_request(socket_path, r#"{"id":2,"method":"Shutdown"}"#)
}

/// Compute the expected socket and PID file paths for a given `HOME`.
pub fn socket_and_pid_paths(home_dir: &Path) -> (PathBuf, PathBuf) {
    let runtime_dir = home_dir.join(".orca");
    let socket_path = runtime_dir.join("daemon.sock");
    let pid_path = runtime_dir.join("daemon.pid");
    (socket_path, pid_path)
}

/// Send SIGTERM to the child and wait for it to exit, falling back to
/// SIGKILL after `timeout`.
pub fn term_and_wait(mut child: Child, timeout: Duration) {
    let pid = child.id() as i32;
    unsafe {
        libc::kill(pid, libc::SIGTERM);
    }
    let start = std::time::Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) => {
                if start.elapsed() > timeout {
                    let _ = child.kill();
                    child.wait().expect("failed to wait for child after kill");
                    break;
                }
                thread::sleep(Duration::from_millis(50));
            }
            Err(e) => panic!("error waiting for child: {e}"),
        }
    }
}
