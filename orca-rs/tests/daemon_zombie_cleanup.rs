//! Zombie-cleanup test: after a daemon is killed with SIGKILL, a new
//! daemon must detect the stale socket/PID files, validate the old PID
//! is dead, remove the artifacts, and bind successfully.

mod common;

use std::time::Duration;

#[test]
#[cfg(unix)]
fn daemon_zombie_cleanup_removes_stale_artifacts() {
    let home_dir = tempfile::tempdir().expect("failed to create temp dir");
    let (socket_path, pid_path) = common::socket_and_pid_paths(home_dir.path());

    // 1. Spawn first daemon.
    let mut child = common::spawn_daemon(home_dir.path());
    common::wait_for_socket(&socket_path, Duration::from_secs(5));
    assert!(
        pid_path.exists(),
        "PID file should exist after daemon start"
    );

    // 2. Kill it uncleanly.
    let pid = child.id() as i32;
    unsafe {
        libc::kill(pid, libc::SIGKILL);
    }
    let _ = child.wait();

    // 3. Artifacts must still be present.
    assert!(
        socket_path.exists(),
        "socket should exist after unclean exit"
    );
    assert!(
        pid_path.exists(),
        "PID file should exist after unclean exit"
    );

    // 4. Start a new daemon — must succeed by cleaning stale artifacts.
    let child2 = common::spawn_daemon(home_dir.path());
    common::wait_for_daemon_ready(&socket_path, Duration::from_secs(5));

    // 5. Verify new daemon responds.
    let response = common::send_ping(&socket_path);
    let parsed: serde_json::Value =
        serde_json::from_str(&response).expect("response should be valid JSON");
    assert_eq!(parsed["id"], 1);
    assert!(
        parsed["result"]["status"].as_str() == Some("Pong"),
        "expected Pong, got: {response}"
    );

    // 6. Clean shutdown.
    let _ = common::send_shutdown(&socket_path);
    common::term_and_wait(child2, Duration::from_secs(5));

    // 7. Verify artifacts are removed.
    assert!(
        !socket_path.exists(),
        "socket should be removed after clean shutdown"
    );
    assert!(
        !pid_path.exists(),
        "PID file should be removed after clean shutdown"
    );
}
