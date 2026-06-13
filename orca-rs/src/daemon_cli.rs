//! Daemon-safe dispatch for a narrow whitelist of Rust CLI operations.
//!
//! Commands routed here must never call [`std::process::exit`]. Later phases
//! can extend the whitelist or add stdout/stderr capture for richer commands.

use crate::exit_codes::{EXIT_PARSE_ERROR, EXIT_SUCCESS};
use crate::update::current_version;

/// Captured output from a daemon-side CLI invocation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CliExecutionResult {
    pub stdout: String,
    pub stderr: String,
    pub exit_code: i32,
}

/// Execute a whitelisted CLI operation for daemon `ExecuteCli` requests.
///
/// # Errors
///
/// Does not return `Result`; unsupported commands are reported via
/// [`CliExecutionResult::exit_code`] and [`CliExecutionResult::stderr`].
#[must_use]
pub fn execute_cli(argv: &[String]) -> CliExecutionResult {
    if argv.is_empty() {
        return CliExecutionResult {
            stdout: String::new(),
            stderr: "ExecuteCli requires at least one argument (subcommand)".to_string(),
            exit_code: EXIT_PARSE_ERROR,
        };
    }

    match argv[0].as_str() {
        "version" | "--version" | "-V" => CliExecutionResult {
            stdout: format!("{}\n", current_version()),
            stderr: String::new(),
            exit_code: EXIT_SUCCESS,
        },
        other => CliExecutionResult {
            stdout: String::new(),
            stderr: format!(
                "unsupported daemon CLI command: {other} (Phase 1B supports: version)"
            ),
            exit_code: EXIT_PARSE_ERROR,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_subcommand_returns_pkg_version_on_stdout() {
        let result = execute_cli(&["version".to_string()]);
        assert_eq!(result.exit_code, EXIT_SUCCESS);
        assert!(result.stderr.is_empty());
        assert_eq!(result.stdout.trim(), current_version());
    }

    #[test]
    fn version_flag_alias_is_supported() {
        let result = execute_cli(&["--version".to_string()]);
        assert_eq!(result.exit_code, EXIT_SUCCESS);
        assert_eq!(result.stdout.trim(), current_version());
    }

    #[test]
    fn empty_argv_is_parse_error() {
        let result = execute_cli(&[]);
        assert_eq!(result.exit_code, EXIT_PARSE_ERROR);
        assert!(result.stdout.is_empty());
        assert!(result.stderr.contains("at least one argument"));
    }

    #[test]
    fn unsupported_command_is_structured_error() {
        let result = execute_cli(&["scan".to_string()]);
        assert_eq!(result.exit_code, EXIT_PARSE_ERROR);
        assert!(result.stdout.is_empty());
        assert!(result.stderr.contains("unsupported daemon CLI command: scan"));
    }
}
