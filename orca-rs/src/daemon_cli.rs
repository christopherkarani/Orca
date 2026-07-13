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
    fn phase1_test_command_is_supported() {
        let result = execute_cli(&["test".to_string(), "--help".to_string()]);
        assert_eq!(result.exit_code, EXIT_SUCCESS);
        assert!(result.stderr.is_empty());
        assert!(
            result
                .stdout
                .contains("Test a command against enabled packs")
        );
    }

    #[test]
    fn phase1_scan_command_is_supported() {
        let result = execute_cli(&["scan".to_string(), "--help".to_string()]);
        assert_eq!(result.exit_code, EXIT_SUCCESS);
        assert!(result.stderr.is_empty());
        assert!(
            result
                .stdout
                .contains("Scan files for destructive commands")
        );
    }

    #[test]
    fn phase1_history_command_is_supported() {
        let result = execute_cli(&["history".to_string(), "--help".to_string()]);
        assert_eq!(result.exit_code, EXIT_SUCCESS);
        assert!(result.stderr.is_empty());
        assert!(result.stdout.contains("Query command history database"));
    }

    #[test]
    fn phase1_packs_command_is_supported() {
        let result = execute_cli(&["packs".to_string(), "--help".to_string()]);
        assert_eq!(result.exit_code, EXIT_SUCCESS);
        assert!(result.stderr.is_empty());
        assert!(result.stdout.contains("List all available packs"));
    }

    #[test]
    fn phase1_precommit_alias_is_supported() {
        let result = execute_cli(&["precommit".to_string(), "--help".to_string()]);
        assert_eq!(result.exit_code, EXIT_SUCCESS);
        assert!(result.stderr.is_empty());
        assert!(result.stdout.contains("pre-commit"));
    }

    #[test]
    fn phase_a_explain_command_is_supported() {
        let result = execute_cli(&["explain".to_string(), "--help".to_string()]);
        assert_eq!(result.exit_code, EXIT_SUCCESS);
        assert!(result.stderr.is_empty());
        assert!(result.stdout.to_lowercase().contains("explain"));
    }

    #[test]
    fn phase_a_allowlist_command_is_supported() {
        let result = execute_cli(&["allowlist".to_string(), "--help".to_string()]);
        assert_eq!(result.exit_code, EXIT_SUCCESS);
        assert!(result.stderr.is_empty());
        assert!(result.stdout.to_lowercase().contains("allowlist"));
    }

    #[test]
    fn phase_a_allow_once_command_is_supported() {
        let result = execute_cli(&["allow-once".to_string(), "--help".to_string()]);
        assert_eq!(result.exit_code, EXIT_SUCCESS);
        assert!(result.stderr.is_empty());
        assert!(result.stdout.to_lowercase().contains("allow"));
    }

    #[test]
    fn phase_a_classify_command_is_supported() {
        let result = execute_cli(&["classify".to_string(), "--help".to_string()]);
        assert_eq!(result.exit_code, EXIT_SUCCESS);
        assert!(result.stderr.is_empty());
        assert!(result.stdout.to_lowercase().contains("classify"));
    }

    #[test]
    fn phase_a_suggest_allowlist_command_is_supported() {
        let result = execute_cli(&["suggest-allowlist".to_string(), "--help".to_string()]);
        assert_eq!(result.exit_code, EXIT_SUCCESS);
        assert!(result.stderr.is_empty());
        assert!(result.stdout.to_lowercase().contains("allowlist"));
    }

    #[test]
    fn phase_a_rebase_recover_command_is_supported() {
        let result = execute_cli(&["rebase-recover".to_string(), "--help".to_string()]);
        assert_eq!(result.exit_code, EXIT_SUCCESS);
        assert!(result.stderr.is_empty());
        assert!(result.stdout.to_lowercase().contains("rebase"));
    }

    #[test]
    fn phase_a_config_command_is_supported() {
        let result = execute_cli(&["config".to_string(), "--help".to_string()]);
        assert_eq!(result.exit_code, EXIT_SUCCESS);
        assert!(result.stderr.is_empty());
        assert!(result.stdout.to_lowercase().contains("config"));
    }

    #[test]
    fn phase4_command_is_still_deferred() {
        let result = execute_cli(&["stats".to_string()]);
        assert_eq!(result.exit_code, EXIT_PARSE_ERROR);
        assert!(result.stdout.is_empty());
        assert!(
            result
                .stderr
                .contains("unsupported daemon CLI command: stats")
        );
    }

    #[test]
    fn daemon_cli_matches_cli_version_stdout_line() {
        use crate::cli::version_stdout_line;
        let result = execute_cli(&["version".to_string()]);
        assert_eq!(result.stdout, version_stdout_line());
    }
}
