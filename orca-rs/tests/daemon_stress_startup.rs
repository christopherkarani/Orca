//! Startup stress test: exercise the stale-socket cleanup path under
//! load by repeatedly killing the daemon uncleanly and starting a new
//! one in the same runtime directory.

mod common;

use std::time::Duration;

#[test]
#[cfg(unix)]
fn daemon_rapid_startup_stress_test() {
    let home_dir = tempfile::tempdir().expect("failed to create temp dir");
    let (socket_path, pid_path) = common::socket_and_pid_paths(home_dir.path());

    // 100 iterations is enough to surface races in the stale-socket
    // detection / cleanup path without making the default test suite
    // unreasonably slow in release builds.
    const ITERATIONS: usize = 100;

    for i in 0..ITERATIONS {
        // On every iteration after the first, stale artifacts (socket + PID)
        // from the previous SIGKILL should be detected and removed.
        let mut child = common::spawn_daemon(home_dir.path());
        common::wait_for_daemon_ready(&socket_path, Duration::from_secs(5));

        // Sanity check: daemon must respond to Ping.
        let response = common::send_ping(&socket_path);
        let parsed: serde_json::Value =
            serde_json::from_str(&response).expect("response should be valid JSON");
        assert_eq!(parsed["id"], 1);
        assert!(
            parsed["result"]["status"].as_str() == Some("Pong"),
            "iteration {i}: expected Pong, got: {response}"
        );

        let is_last = i == ITERATIONS - 1;
        if is_last {
            // Clean shutdown on the last iteration and verify removal.
            let _ = common::send_shutdown(&socket_path);
            common::term_and_wait(child, Duration::from_secs(5));

            assert!(
                !socket_path.exists(),
                "socket should be removed after final clean shutdown"
            );
            assert!(
                !pid_path.exists(),
                "PID file should be removed after final clean shutdown"
            );
        } else {
            // Unclean exit leaves stale artifacts behind.
            let pid = child.id() as i32;
            unsafe {
                libc::kill(pid, libc::SIGKILL);
            }
            let _ = child.wait();

            // Artifacts must be present before the next startup.
            assert!(
                socket_path.exists(),
                "iteration {i}: stale socket should exist after SIGKILL"
            );
            assert!(
                pid_path.exists(),
                "iteration {i}: stale PID file should exist after SIGKILL"
            );
        }
    }
}
