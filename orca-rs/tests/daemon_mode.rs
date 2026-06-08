//! Integration test for the --daemon-mode daemon.
//!
//! Note: daemon mode keeps the process alive until signalled.
//! Manual verification: run `./target/debug/orca-daemon --daemon-mode`
//! and press Ctrl-C; it should exit 0.

use assert_cmd::Command;
use std::time::Duration;

#[test]
fn daemon_mode_rejects_unknown_flags() {
    let mut cmd = Command::cargo_bin("orca-daemon").expect("orca-daemon binary should exist");
    cmd.arg("--daemon-mode");
    cmd.arg("--this-flag-does-not-exist");
    cmd.timeout(Duration::from_secs(5));
    // Parse errors in daemon mode must NOT return success.
    cmd.assert().failure();
}
