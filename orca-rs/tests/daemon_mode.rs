//! Integration test for the --daemon-mode daemon.
//!
//! Note: daemon mode keeps the process alive until signalled.
//! Manual verification: run `./target/debug/orca-daemon --daemon-mode`
//! and press Ctrl-C; it should exit 0.
