//! Integration test for the --daemon-mode stub.
//!
//! Verifies that the binary exits 0 when invoked with --daemon-mode.

use assert_cmd::Command;

#[test]
fn daemon_mode_exits_zero() {
    let mut cmd = Command::cargo_bin("orca-daemon").expect("orca-daemon binary should exist");
    cmd.arg("--daemon-mode");
    cmd.assert().success().code(0);
}
