//! Product identity constants for Orca-rs.
//!
//! Centralizes CLI name, config paths, environment variable prefix, and GitHub
//! coordinates so renames stay consistent across the codebase.

/// Installed CLI binary name (`orca`).
pub const CLI_NAME: &str = "orca";

/// User-facing product name.
pub const PRODUCT_NAME: &str = "Orca-rs";

/// Config and data directory name under XDG paths (`~/.config/orca`, etc.).
pub const CONFIG_DIR: &str = "orca";

/// Project-level config filename in repository root.
pub const PROJECT_CONFIG_FILE: &str = ".orca.toml";

/// Project-local data directory name (allowlists, packs, state).
pub const PROJECT_DATA_DIR: &str = ".orca";

/// Prefix for environment variables (`ORCA_BYPASS`, `ORCA_CONFIG`, …).
pub const ENV_PREFIX: &str = "ORCA";

/// GitHub repository owner.
pub const GITHUB_OWNER: &str = "christopherkarani";

/// GitHub repository name.
pub const GITHUB_REPO: &str = "Orca";

/// Full GitHub repository URL.
pub const GITHUB_REPO_URL: &str = "https://github.com/christopherkarani/Orca";
