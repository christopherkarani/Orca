//! Live-daemon collision test: starting a second daemon while the first
//! is running must return a clear error and must not remove the socket
//! or PID file belonging to the live daemon.

mod common;

use std::io::{BufRead, Write};
use std::os::unix::net::UnixStream;
use std::time::Duration;

/// Send a Ping request and return the response line.
fn send_ping(socket_path: &std::path::Path) -> String {
    let mut stream = UnixStream::connect(socket_path).expect("failed to connect to daemon socket");
    stream
        .set_read_timeout(Some(Duration::from_secs(5)))
        .expect("failed to set read timeout");

    stream
        .write_all(br#"{"id":1,"method":"Ping"}"#)
        .expect("failed to write request");
    stream.write_all(b"\n").expect("failed to write newline");
    stream.flush().expect("failed to flush");

    let mut reader = std::io::BufReader::new(&stream);
    let mut line = String::new();
    reader
        .read_line(&mut line)
        .expect("failed to read response");
    line
}

#[test]
#[cfg(unix)]
fn daemon_live_collision_returns_error_without_removing_socket() {
    let home_dir = tempfile::tempdir().expect("failed to create temp dir");
    let (socket_path, pid_path) = common::socket_and_pid_paths(home_dir.path());

    // 1. Spawn first daemon and wait until it is actually accepting connections.
    let child1 = common::spawn_daemon(home_dir.path());
    common::wait_for_daemon_ready(&socket_path, Duration::from_secs(5));

    // 2. Attempt to spawn a second daemon in the same HOME directory.
    let mut child2 = common::spawn_daemon(home_dir.path());

    // 3. The second daemon must exit quickly with a non-zero status.
    let status = child2.wait().expect("failed to wait for second daemon");
    assert!(
        !status.success(),
        "second daemon should fail when socket is in use by a live daemon"
    );

    // 4. The live daemon's socket and PID file must remain intact.
    assert!(
        socket_path.exists(),
        "live daemon socket must not be removed by failed startup"
    );
    assert!(
        pid_path.exists(),
        "live daemon PID file must not be removed by failed startup"
    );

    // 5. The live daemon must still respond to requests.
    let response = send_ping(&socket_path);
    let parsed: serde_json::Value =
        serde_json::from_str(&response).expect("response should be valid JSON");
    assert_eq!(parsed["id"], 1);
    assert!(
        parsed["result"]["status"].as_str() == Some("Pong"),
        "expected Pong from live daemon, got: {response}"
    );

    // 6. Clean shutdown of the live daemon.
    let _ = common::send_shutdown(&socket_path);
    common::term_and_wait(child1, Duration::from_secs(5));

    // 7. Artifacts should be removed after clean shutdown.
    assert!(
        !socket_path.exists(),
        "socket should be removed after clean shutdown"
    );
    assert!(
        !pid_path.exists(),
        "PID file should be removed after clean shutdown"
    );
}
