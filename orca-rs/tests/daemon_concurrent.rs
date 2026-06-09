//! Concurrent-client test: multiple simultaneous connections must all
//! receive valid, non-interleaved responses.

mod common;

use std::sync::{Arc, Barrier};
use std::thread;
use std::time::Duration;

#[test]
#[cfg(unix)]
fn daemon_concurrent_ping_responses() {
    let home_dir = tempfile::tempdir().expect("failed to create temp dir");
    let (socket_path, pid_path) = common::socket_and_pid_paths(home_dir.path());

    // 1. Spawn daemon.
    let child = common::spawn_daemon(home_dir.path());
    common::wait_for_socket(&socket_path, Duration::from_secs(5));

    // 2. Spawn 5 threads that all send Ping at the same time.
    let barrier = Arc::new(Barrier::new(5));
    let mut handles = Vec::with_capacity(5);

    for i in 0..5 {
        let b = Arc::clone(&barrier);
        let sock = socket_path.clone();
        handles.push(thread::spawn(move || {
            b.wait(); // synchronize start
            let req = format!(r#"{{"id":{},"method":"Ping"}}"#, i + 10);
            let response = common::send_request(&sock, &req);
            let parsed: serde_json::Value =
                serde_json::from_str(&response).expect("response should be valid JSON");
            assert_eq!(parsed["id"], i + 10, "id mismatch in response");
            assert!(
                parsed["result"]["status"].as_str() == Some("Pong"),
                "expected Pong, got: {response}"
            );
        }));
    }

    for h in handles {
        h.join().expect("thread panicked");
    }

    // 3. Clean shutdown.
    let _ = common::send_shutdown(&socket_path);
    common::term_and_wait(child, Duration::from_secs(5));

    assert!(
        !socket_path.exists(),
        "socket should be removed after shutdown"
    );
    assert!(
        !pid_path.exists(),
        "PID file should be removed after shutdown"
    );
}
