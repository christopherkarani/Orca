//! Crash-recovery test: a daemon killed with SIGKILL leaves stale artifacts
//! behind, and a subsequent daemon startup must detect them as stale and
//! clean them up.

mod common;

use std::time::Duration;

#[test]
#[cfg(unix)]
fn daemon_crash_recovery_cleans_stale_socket() {
    let home_dir = tempfile::tempdir().expect("failed to create temp dir");
    let (socket_path, pid_path) = common::socket_and_pid_paths(home_dir.path());

    // 1. Spawn first daemon.
    let mut child = common::spawn_daemon(home_dir.path());
    common::wait_for_socket(&socket_path, Duration::from_secs(5));
    assert!(
        pid_path.exists(),
        "PID file should exist after daemon start"
    );

    // 2. Crash it with SIGKILL.
    let pid = child.id() as i32;
    unsafe {
        libc::kill(pid, libc::SIGKILL);
    }
    let _ = child.wait();

    // 3. Socket and PID file should still be present (unclean exit).
    assert!(
        socket_path.exists(),
        "socket should still exist after SIGKILL"
    );
    assert!(
        pid_path.exists(),
        "PID file should still exist after SIGKILL"
    );

    // 4. Connecting to the stale socket should fail.
    let connect_result = std::os::unix::net::UnixStream::connect(&socket_path);
    assert!(
        connect_result.is_err(),
        "connecting to stale socket should fail"
    );

    // 5. Start a new daemon in the same HOME.
    let child2 = common::spawn_daemon(home_dir.path());
    common::wait_for_daemon_ready(&socket_path, Duration::from_secs(5));

    // 6. Ping → Pong.
    let response = common::send_ping(&socket_path);
    let parsed: serde_json::Value =
        serde_json::from_str(&response).expect("response should be valid JSON");
    assert_eq!(parsed["id"], 1);
    assert!(
        parsed["result"]["status"].as_str() == Some("Pong"),
        "expected Pong, got: {response}"
    );

    // 7. Clean shutdown.
    let _ = common::send_shutdown(&socket_path);
    common::shutdown_and_wait(child2, &socket_path, Duration::from_secs(5));

    // 8. Artifacts should be gone.
    assert!(
        !socket_path.exists(),
        "socket should be removed after clean shutdown"
    );
    assert!(
        !pid_path.exists(),
        "PID file should be removed after clean shutdown"
    );
}
