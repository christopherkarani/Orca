# Daemon-Mode Exit-Call Inventory

This document inventories every `std::process::exit()` call in `orca-rs/src/` and `orca-rs/tests/` and assesses whether it can remain as-is when running in daemon mode, or whether it must be refactored into a `DaemonResponse`.

## Inventory

| File | Line | Exit Code | Context | Daemon-Safe | Refactor Note |
|------|------|-----------|---------|-------------|---------------|
| `src/exit_codes.rs` | 125 | `code` (`i32`) | Utility wrapper `exit_with(code: i32) -> !` used by callers that want a process-level exit with an Orca exit-code constant. | MAYBE | The wrapper can stay, but **no daemon request handler may call it**. Audit all call sites to ensure it is only invoked from CLI-only code paths (e.g., pre-daemon argument validation). |
| `src/main.rs` | 187 | `130` | `ctrlc::set_handler` callback flushes shutdown actions then exits 130 (`128 + SIGINT`). Installed during CLI startup in `install_signal_shutdown_handler()`. | NO | Signal handling in daemon mode must **not** terminate the process. Replace with a graceful-shutdown channel that drains the UDS listener and in-flight requests before returning from `main()`. |
| `src/main.rs` | 375 | `exit_code` | Clap argument-parsing error path. If `Cli::try_parse()` fails, prints the error and exits with clap's suggested exit code. | NO | In daemon mode there is no interactive CLI to mis-parse. This path should be unreachable; if reached, return a parse-error `DaemonResponse` or log and exit cleanly before binding the UDS socket. |
| `src/main.rs` | 405 | `1` | Generic subcommand error path. If `cli::run_command(cli)` returns `Err(e)`, prints the error and exits 1. | NO | `run_command()` must return a structured `Result<CommandOutput, DaemonError>` so the daemon can serialize it as a `DaemonResponse` instead of killing the process. |
| `src/main.rs` | 830 | `2` | Codex-protocol hook deny path. After writing the deny reason to stderr, flushes history synchronously and exits 2 so Codex treats the command as blocked. | NO | This is hook-mode-only behavior. In daemon mode the same semantic must be encoded as a `DaemonResponse::Deny { reason, protocol: Codex }` and returned to the Zig client over UDS; the exit must be skipped entirely. |
| `src/cli.rs` | 2085 | `EXIT_DENIED` (`1`) | `test` subcommand: if `test_command()` reports the command would be blocked, exits `EXIT_DENIED` for CI/robot scripting. | NO | `run_command()` should return a `TestResult` containing `was_blocked`; the caller (CLI or daemon request handler) decides whether to map it to an exit code or to a JSON response. |
| `src/cli.rs` | 2227 | `exit_code` | `classify` subcommand: maps classification severity to an exit code and exits if non-zero. | NO | `handle_classify_command()` (or `run_command()`) should return a `ClassifyResult` with the computed exit code; the caller applies the exit only in CLI mode. |
| `src/cli.rs` | 3384 | `1` | `validate` subcommand: if any pack failed validation (`exit_error == true`), exits 1 after printing results. | NO | Validation should return a `ValidateResult { reports, exit_error }`; the caller decides whether to emit exit code 1 or to serialize the report as a JSON `DaemonResponse`. |
| `src/cli.rs` | 5756 | `1` | `scan` subcommand input-error path: no `--staged`, `--paths`, or `--git-diff` specified; prints usage hint and exits 1. | NO | Return `Err("No file selection mode specified".into())` from `handle_scan_command()` and let the caller render the error as either a CLI exit or a `DaemonResponse::Error`. |
| `src/cli.rs` | 5862 | `1` | `scan` subcommand result path: if `should_fail()` is true (findings exceed `--fail-on` threshold), exits 1. | NO | `handle_scan_command()` should return a `ScanResult { report, should_fail }`; the caller maps it to an exit code in CLI mode or to a JSON response in daemon mode. |
| `src/cli.rs` | 8727 | `1` | `history info` subcommand with `--strict`: if SQLite integrity check fails, exits 1. | NO | `handle_history_command()` should propagate an `Err(HistoryError::IntegrityFailed)` or return a structured `HistoryInfoResult` so the daemon can reply with an error response instead of terminating. |

## Summary

- **Total exit calls found:** 11
- **Daemon-safe (YES):** 0
- **Daemon-safe (NO):** 10
- **Daemon-safe (MAYBE):** 1

### Three Highest-Risk Refactors

1. **`src/main.rs` (4 calls, lines 187, 375, 405, 830)**
   - This is the entry point; daemon-mode branching must be introduced before any of these exits are reached. The signal handler is especially risky because it is global and will kill long-running UDS connections.
2. **`src/cli.rs::run_command()` and subcommand handlers (6 calls)**
   - `run_command()` currently returns `Result<(), Box<dyn Error>>` and relies on `process::exit()` inside individual subcommands. Refactoring this requires touching test, classify, validate, scan, and history subcommands and deciding on a common `CommandOutput` union type.
3. **Hook deny path at `src/main.rs:830`**
   - Codex's exit-code contract (exit 2 = blocked) is baked into a protocol-specific path. The daemon replacement must preserve this contract in the `DaemonResponse` payload without calling `process::exit()`.

### Recommended Refactor Order

1. **`src/main.rs` signal handler (line 187)**
   - Replace the `ctrlc` exit-130 handler with a graceful-shutdown channel before any daemon work begins. This prevents accidental daemon termination during development.
2. **`src/main.rs` CLI parse error (line 375) and generic subcommand error (line 405)**
   - Introduce a `run_cli_or_daemon(cli: Cli) -> Result<CommandOutput, DaemonError>` dispatcher. Keep the CLI branch exiting, but route the daemon branch around all `process::exit()` calls.
3. **`src/cli.rs::run_command()` refactor**
   - Change return type from `Result<(), Box<dyn Error>>` to `Result<CommandOutput, Box<dyn Error>>` where `CommandOutput` is an enum (`Test(...)`, `Classify(...)`, `Validate(...)`, `Scan(...)`, `History(...)`, `PlainOk`). This collapses the subcommand exit calls into structured returns.
4. **Subcommand exits (lines 2085, 2227, 3384, 5756, 5862, 8727)**
   - Convert each one to populate the new `CommandOutput` variant or return an `Err` with a typed error.
5. **Hook deny exit (line 830)**
   - Move the Codex deny logic into a helper that returns `EvaluationResult::Deny` or `DaemonResponse::Deny`; call it from both the CLI hook path and the daemon request handler. Remove the `process::exit(2)` call.
6. **Audit `exit_with()` usage**
   - Verify the utility in `src/exit_codes.rs:125` is never called from daemon code paths. If it is, replace those calls with typed errors or response values.
