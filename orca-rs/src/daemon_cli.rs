//! Daemon-safe dispatch for a narrow whitelist of Rust CLI operations.
//!
//! Delegates to [`crate::cli::execute_daemon_cli`], which returns structured
//! results instead of calling [`std::process::exit`].

pub use crate::cli::{CliExecutionResult, execute_daemon_cli};

/// Daemon-side entry point for `ExecuteCli` requests.
///
/// Alias kept for call sites (`daemon.rs`, tests) that predate the
/// `execute_daemon_cli` name.
pub use execute_daemon_cli as execute_cli;

#[cfg(test)]
mod tests {
    use super::*;
    use crate::exit_codes::{EXIT_PARSE_ERROR, EXIT_SUCCESS};
    use crate::update::current_version;

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

    #[test]
    fn daemon_cli_matches_cli_version_stdout_line() {
        use crate::cli::version_stdout_line;
        let result = execute_cli(&["version".to_string()]);
        assert_eq!(result.stdout, version_stdout_line());
    }
}
