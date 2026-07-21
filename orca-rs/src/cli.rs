//! CLI argument parsing and command handling.
//!
//! This module provides the command-line interface for Orca-rs (`orca`),
//! including subcommands for configuration management and pack information.

use chrono::Utc;
use clap::{Args, CommandFactory, Parser, Subcommand};
use inquire::{Select, Text};

use crate::agent::{DetectionMethod, detect_agent_with_details};
use crate::config::Config;
use crate::evaluator::{
    DEFAULT_WINDOW_WIDTH, EvaluationDecision, EvaluationResult, MatchSource,
    evaluate_command_with_pack_order, evaluate_command_with_pack_order_deadline_at_path,
};
use crate::exit_codes::{EXIT_DENIED, EXIT_IO_ERROR, EXIT_PARSE_ERROR, EXIT_SUCCESS, EXIT_WARNING};
use crate::highlight::{HighlightSpan, format_highlighted_command, should_use_color};
use crate::history::{
    ExportOptions, HistoryDb, HistoryStats, InteractiveAllowlistAuditEntry,
    InteractiveAllowlistOptionType, Outcome, SuggestionAction, SuggestionAuditEntry,
};
use crate::interactive::{
    AllowlistScope, InteractiveConfig, InteractiveResult, check_interactive_available,
    print_not_available_message, run_interactive_prompt,
};
use crate::load_default_allowlists;
use crate::output::robot_mode_enabled;
use crate::packs::{
    DecisionMode, ExternalPackStore, REGISTRY, Severity as PackSeverity, get_external_packs,
    load_external_packs,
};
use crate::pending_exceptions::{
    AllowOnceEntry, AllowOnceScopeKind, AllowOnceStore, PendingExceptionRecord,
    PendingExceptionStore,
};
use crate::suggest::{
    AllowlistSuggestion, CommandEntryInfo, ConfidenceTier, RiskLevel, filter_by_confidence,
    filter_by_risk, generate_enhanced_suggestions,
};
use std::io::IsTerminal;

/// Unified output format for all orca commands.
///
/// This enum provides a consistent interface for output format selection across
/// all commands. It supports the common formats needed by both human users
/// (pretty/text) and AI agents (json/jsonl).
///
/// # Robot Mode
///
/// When `--robot` mode is enabled, the format defaults to `Json` regardless
/// of the command-specific default.
///
/// # Aliases
///
/// Several aliases are provided for compatibility:
/// - `text` and `human` map to `Pretty`
/// - `sarif` and `structured` map to `Json`
///
/// # Example
///
/// ```bash
/// # Human-readable output (default)
/// orca test "rm -rf /"
///
/// # JSON output for scripting
/// orca test "rm -rf /" --format json
///
/// # Robot mode (implies JSON, suppresses stderr)
/// orca --robot test "rm -rf /"
/// ```
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, clap::ValueEnum, serde::Serialize)]
#[serde(rename_all = "lowercase")]
pub enum OutputFormat {
    /// Human-readable colored output (default for interactive use)
    #[default]
    #[value(alias = "text", alias = "human")]
    Pretty,

    /// Structured JSON output (for agents and scripting)
    #[value(alias = "sarif", alias = "structured")]
    Json,

    /// JSON Lines format (one JSON object per line, for streaming)
    #[value(name = "jsonl")]
    Jsonl,

    /// Compact single-line output (for specific commands)
    Compact,
}

impl OutputFormat {

}

/// High-performance Claude Code hook for blocking destructive commands.
///
/// orca (`orca_rs`) protects against accidental execution of
/// destructive commands by AI coding agents. It blocks dangerous git commands,
/// filesystem operations, database queries, and more.
#[derive(Parser, Debug)]
#[command(name = "orca")]
#[command(version, about, long_about = None)]
#[command(after_help = "Run 'orca --help' for available commands.")]
pub struct Cli {
    /// Increase verbosity (-v, -vv, -vvv)
    #[arg(short, long, action = clap::ArgAction::Count, global = true, env = "ORCA_VERBOSE")]
    pub verbose: u8,

    /// Suppress non-error output
    #[arg(
        short,
        long,
        action = clap::ArgAction::SetTrue,
        value_parser = clap::builder::FalseyValueParser::new(),
        global = true,
        conflicts_with = "verbose",
        env = "ORCA_QUIET"
    )]
    pub quiet: bool,

    /// Use legacy output rendering (fallback if rich output causes issues)
    #[arg(
        long,
        action = clap::ArgAction::SetTrue,
        value_parser = clap::builder::FalseyValueParser::new(),
        global = true,
        env = "ORCA_LEGACY_OUTPUT"
    )]
    pub legacy_output: bool,

    /// Disable colored output globally
    #[arg(
        long,
        action = clap::ArgAction::SetTrue,
        value_parser = clap::builder::FalseyValueParser::new(),
        global = true,
        env = "ORCA_NO_COLOR"
    )]
    pub no_color: bool,

    /// Disable suggestion output in warnings/denials
    #[arg(
        long,
        action = clap::ArgAction::SetTrue,
        value_parser = clap::builder::FalseyValueParser::new(),
        global = true,
        env = "ORCA_NO_SUGGESTIONS"
    )]
    pub no_suggestions: bool,

    /// Enable robot/machine mode for AI agent integration
    ///
    /// When enabled:
    /// - All output is JSON on stdout
    /// - stderr is completely silent (no rich output, no human messages)
    /// - Exit codes follow standardized values (see docs/adr-002-robot-mode-api.md)
    /// - Human-friendly decorations are suppressed
    ///
    /// This flag is designed for AI coding agents (Claude Code, Gemini CLI, etc.)
    /// that need to parse orca's output programmatically.
    ///
    /// Exit codes in robot mode:
    /// - 0: Success / Allow
    /// - 1: Denied / Blocked
    /// - 2: Warning (with --fail-on warn)
    /// - 3: Configuration error
    /// - 4: Parse/input error
    /// - 5: IO error
    ///
    /// Enable robot mode for machine-friendly output (also enabled by ORCA_ROBOT=1 env var).
    /// In robot mode: always outputs JSON, silent stderr, standardized exit codes.
    #[arg(long, global = true)]
    pub robot: bool,

    /// Run as a background daemon (used by the Orca monorepo IPC bridge).
    /// Hidden from help output; not intended for direct user invocation.
    #[arg(long, global = true, hide = true)]
    pub daemon_mode: bool,

    /// Override automatic agent detection for agent-specific profiles
    #[arg(long, global = true, value_name = "AGENT")]
    pub agent: Option<String>,

    /// Subcommand to run (omit to run in hook mode)
    #[command(subcommand)]
    pub command: Option<Command>,
}

/// Available subcommands
#[derive(Subcommand, Debug)]
pub enum Command {
    /// Run in hook mode with batch processing support
    ///
    /// Explicit hook mode for processing commands from stdin. When `--batch` is
    /// specified, reads JSONL (one JSON hook input per line) and outputs JSONL
    /// with decisions.
    ///
    /// Without `--batch`, behaves identically to running `orca` with no subcommand.
    #[command(name = "hook")]
    Hook(HookCommand),

    /// Manage allowlist entries (add, list, remove, validate)
    #[command(name = "allowlist")]
    Allowlist {
        #[command(subcommand)]
        action: AllowlistAction,
    },

    /// Add a rule to the allowlist (shortcut for `allowlist add`)
    #[command(name = "allow")]
    Allow {
        /// Rule ID to allowlist (e.g., "core.git:reset-hard")
        rule_id: String,

        /// Reason for allowlisting (required)
        #[arg(long, short = 'r')]
        reason: String,

        /// Add to project allowlist (default if in git repo)
        #[arg(long, conflicts_with = "user")]
        project: bool,

        /// Add to user allowlist
        #[arg(long, conflicts_with = "project")]
        user: bool,

        /// Make entry temporary with given duration (e.g., 1h, 30m, 2d)
        #[arg(short = 't', long, conflicts_with = "expires")]
        temporary: Option<String>,

        /// Expiration date (ISO 8601 / RFC 3339)
        #[arg(long, conflicts_with = "temporary")]
        expires: Option<String>,
    },

    /// Remove a rule from the allowlist (shortcut for `allowlist remove`)
    #[command(name = "unallow")]
    Unallow {
        /// Rule ID to remove (e.g., "core.git:reset-hard")
        rule_id: String,

        /// Remove from project allowlist (default if in git repo)
        #[arg(long, conflicts_with = "user")]
        project: bool,

        /// Remove from user allowlist
        #[arg(long, conflicts_with = "project")]
        user: bool,
    },

    /// Allow a blocked command once using the short code
    #[command(name = "allow-once")]
    AllowOnce(AllowOnceCommand),

    /// Issue a short-lived permit that unblocks `git checkout --` and
    /// `git restore` for the next recovery step.
    ///
    /// Use this when `git pull --rebase` has failed partway (e.g., after a
    /// stash pop left the worktree messy) and the next step really is to
    /// discard the mess. The permit is scoped to the current repository's
    /// `.orca/` state dir, expires after a short TTL (default 120s), and is
    /// consumed on the first matching allow. During an active rebase
    /// (`.git/rebase-merge/` or `.git/rebase-apply/` present) the permit is
    /// not needed — orca unblocks automatically in that state.
    #[command(name = "rebase-recover")]
    RebaseRecover {
        /// Permit time-to-live in seconds (default 120, max 600).
        #[arg(long, value_name = "SECONDS")]
        ttl: Option<u64>,
    },

    /// List all available packs and their status
    #[command(name = "packs")]
    ListPacks {
        /// Show only enabled packs
        #[arg(long)]
        enabled: bool,

        /// Show all patterns in verbose pack trees
        #[arg(long)]
        expand: bool,

        /// Maximum patterns to show per verbose section before truncating
        #[arg(long, value_name = "N", default_value_t = crate::output::DEFAULT_PACK_TREE_MAX_PATTERNS)]
        max_patterns: usize,

        // NOTE: Removed `verbose: bool` - use global `-v`/`--verbose` instead.
        // The global flag (u8 count) conflicts with local bool flags.
        /// Output format (json for structured output, pretty for human-readable)
        #[arg(
            long,
            short = 'f',
            value_enum,
            default_value = "pretty",
            env = "ORCA_FORMAT"
        )]
        format: PacksFormat,
    },

    /// Pack management commands (info, validate)
    #[command(name = "pack")]
    Pack {
        #[command(subcommand)]
        action: PackAction,
    },

    /// Test a command against enabled packs
    #[command(name = "test")]
    TestCommand {
        /// Command to test
        command: String,

        /// Use a specific config file (overrides default config discovery)
        #[arg(long, short = 'c', value_name = "PATH")]
        config: Option<std::path::PathBuf>,

        /// Additional packs to enable for this test
        #[arg(long, value_delimiter = ',')]
        with_packs: Option<Vec<String>>,

        /// Show detailed decision trace (same as `orca explain`)
        #[arg(long)]
        explain: bool,

        /// Output format (json for structured output, pretty for human-readable)
        #[arg(
            long,
            short = 'f',
            value_enum,
            default_value = "pretty",
            env = "ORCA_FORMAT"
        )]
        format: TestFormat,

        /// Disable colored output
        #[arg(long)]
        no_color: bool,

        /// Enable heredoc/inline-script scanning (overrides config)
        #[arg(long = "heredoc-scan", conflicts_with = "no_heredoc_scan")]
        heredoc_scan: bool,

        /// Disable heredoc/inline-script scanning (overrides config)
        #[arg(long = "no-heredoc-scan", conflicts_with = "heredoc_scan")]
        no_heredoc_scan: bool,

        /// Timeout budget for heredoc extraction (milliseconds)
        #[arg(long = "heredoc-timeout", value_name = "MS")]
        heredoc_timeout_ms: Option<u64>,

        /// Languages to scan (comma-separated). Example: python,bash,javascript
        #[arg(
            long = "heredoc-languages",
            value_delimiter = ',',
            value_name = "LANGS"
        )]
        heredoc_languages: Option<Vec<String>>,

        /// Bypass a soft block from the graduated response system
        #[arg(long)]
        force: bool,
    },

    /// Show current configuration
    #[command(name = "config")]
    ShowConfig,

    /// Scan files for destructive commands (CI/pre-commit integration)
    ///
    /// Extracts executable command contexts from files and evaluates them
    /// using the same pipeline as hook mode. Use `--fail-on` to control
    /// exit codes for CI integration.
    #[command(name = "scan")]
    Scan(ScanCommand),

    /// Simulate policy evaluation on command logs (replay/dry-run)
    ///
    /// Parses a file containing commands (one per line) and evaluates each
    /// against the current policy. Useful for:
    /// - Rolling out new packs in warn-only mode
    /// - Analyzing false positive patterns
    /// - Generating allowlist candidates
    ///
    /// Input formats are auto-detected per line:
    /// - Plain command strings
    /// - Hook JSON (`{"tool_name":"Bash","tool_input":{"command":"..."}}`)
    /// - Decision log entries (`ORCA_LOG_V1|...`)
    #[command(name = "simulate")]
    Simulate(SimulateCommand),

    /// Explain why a command would be blocked or allowed (decision trace)
    ///
    /// Shows the full decision pipeline: keyword gating, pack evaluation,
    /// pattern matching, and allowlist checks.
    #[command(name = "explain")]
    Explain {
        /// Command to explain
        command: String,

        /// Output format
        #[arg(
            long,
            short = 'f',
            value_enum,
            default_value = "pretty",
            env = "ORCA_FORMAT"
        )]
        format: ExplainFormat,

        /// Additional packs to enable for this evaluation
        #[arg(long, value_delimiter = ',')]
        with_packs: Option<Vec<String>>,
    },

    /// Query command history database
    #[command(name = "history")]
    History {
        #[command(subcommand)]
        action: HistoryAction,
    },

    /// Suggest allowlist patterns based on command history
    ///
    /// Analyzes denied commands from the history database and suggests
    /// patterns that could be added to the allowlist. Includes risk
    /// assessment and confidence scoring for each suggestion.
    #[command(name = "suggest-allowlist")]
    SuggestAllowlist(SuggestAllowlistCommand),

    /// Classify a command's risk level without blocking
    ///
    /// Returns structured risk classification (JSON or text) instead of a
    /// block/pass decision. Designed for Claude Code hooks to use orca
    /// bidirectionally: block dangerous commands AND auto-allow safe ones.
    ///
    /// Exit codes (consistent with orca exit code contract):
    /// - 0: allow (safe or low risk)
    /// - 2: warn (medium risk)
    /// - 1: block (high or critical risk)
    ///
    /// # Examples
    ///
    /// ```bash
    /// # JSON output (default)
    /// orca classify "git status"
    ///
    /// # Text output
    /// orca classify --format text "rm -rf /"
    ///
    /// # Use in Claude Code hook to auto-allow safe commands
    /// orca classify --format json "ls -la"
    /// ```
    #[command(name = "classify")]
    Classify {
        /// Command to classify
        command: String,

        /// Output format (json or text)
        #[arg(
            long,
            short = 'f',
            value_enum,
            default_value = "json",
            env = "ORCA_FORMAT"
        )]
        format: ClassifyFormat,

        /// Disable colored output
        #[arg(long)]
        no_color: bool,
    },

}

/// `orca hook` command arguments.
#[derive(Args, Debug)]
pub struct HookCommand {
    /// Enable batch mode: read JSONL from stdin, output JSONL results
    ///
    /// Each line should be a JSON hook input:
    /// ```jsonl
    /// {"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}
    /// {"tool_name":"Bash","tool_input":{"command":"git status"}}
    /// ```
    ///
    /// Output format:
    /// ```jsonl
    /// {"index":0,"decision":"deny","rule_id":"core.filesystem:rm-rf-root"}
    /// {"index":1,"decision":"allow"}
    /// ```
    #[arg(long)]
    pub batch: bool,

    /// Process commands in parallel (implies --batch)
    ///
    /// Uses multiple threads to evaluate commands concurrently.
    /// Output maintains input order via the `index` field.
    #[arg(long)]
    pub parallel: bool,

    /// Number of parallel workers (default: number of CPUs)
    #[arg(long, default_value = "0")]
    pub workers: usize,

    /// Continue processing on parse errors (skip invalid lines)
    #[arg(long)]
    pub continue_on_error: bool,
}

/// Output format for batch hook mode.
#[derive(Debug, Clone, serde::Serialize)]
pub struct BatchHookOutput {
    /// Index of the input line (0-based)
    pub index: usize,
    /// Decision: "allow" or "deny"
    pub decision: &'static str,
    /// Rule ID if denied (e.g., "core.git:reset-hard")
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rule_id: Option<String>,
    /// Pack ID if denied
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pack_id: Option<String>,
    /// Error message if parsing failed
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

/// Output format for test command.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, clap::ValueEnum)]
pub enum TestFormat {
    /// Human-readable colored output
    #[default]
    #[value(alias = "text")]
    Pretty,
    /// Structured JSON output
    #[value(alias = "sarif")]
    Json,
    /// TOON output for token-efficient structured data
    Toon,
}

impl TestFormat {
    #[must_use]
    pub const fn is_structured(self) -> bool {
        matches!(self, Self::Json | Self::Toon)
    }
}

/// Output format for classify command.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, clap::ValueEnum)]
pub enum ClassifyFormat {
    /// Structured JSON output (default for agent consumption)
    #[default]
    #[value(alias = "sarif")]
    Json,
    /// Human-readable text output
    #[value(alias = "human")]
    Text,
}

/// Output format for packs list command.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, clap::ValueEnum)]
pub enum PacksFormat {
    /// Human-readable grouped output
    #[default]
    #[value(alias = "text")]
    Pretty,
    /// Structured JSON output
    #[value(alias = "sarif")]
    Json,
}

/// Schema version for TestOutput JSON format
const TEST_OUTPUT_SCHEMA_VERSION: u32 = 1;

/// Schema version for ClassifyOutput JSON format
const CLASSIFY_OUTPUT_SCHEMA_VERSION: u32 = 1;

/// JSON output structure for `orca classify` command.
///
/// Provides risk classification for a command, enabling Claude Code hooks
/// to make bidirectional decisions: block dangerous commands AND auto-allow safe ones.
#[derive(Debug, Clone, serde::Serialize)]
pub struct ClassifyOutput {
    /// Schema version for forward compatibility (currently 1)
    pub schema_version: u32,
    /// Orca-rs version (e.g., "0.6.0")
    pub orca_version: String,
    /// The command that was classified
    pub command: String,
    /// The decision: "allow", "warn", or "block"
    pub decision: String,
    /// Risk level: "safe", "low", "medium", "high", "critical"
    pub risk_level: String,
    /// Risk score from 0.0 (safe) to 1.0 (critical)
    pub risk_score: f64,
    /// Reasons for the classification (empty if safe)
    pub reasons: Vec<ClassifyReason>,
    /// Suggested safer alternatives (empty if safe)
    pub suggestions: Vec<String>,
}

/// A single reason contributing to a classify decision.
#[derive(Debug, Clone, serde::Serialize)]
pub struct ClassifyReason {
    /// Rule identifier (e.g., "core.git:reset-hard")
    pub rule_id: String,
    /// Severity: "critical", "high", "medium", "low"
    pub severity: String,
    /// Human-readable explanation of why this pattern matched
    pub explanation: String,
}

/// JSON output structure for `orca test` command
#[derive(Debug, Clone, serde::Serialize)]
pub struct TestOutput {
    /// Schema version for forward compatibility (currently 1)
    pub schema_version: u32,
    /// Orca-rs version (e.g., "0.6.0")
    pub orca_version: String,
    /// Whether robot mode was enabled for this output
    pub robot_mode: bool,
    /// The command that was tested
    pub command: String,
    /// The decision: "allow" or "deny"
    pub decision: String,
    /// Rule ID if blocked (e.g., "core.git:reset-hard")
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rule_id: Option<String>,
    /// Pack ID that matched (e.g., "core.git")
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pack_id: Option<String>,
    /// Pattern name within the pack
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pattern_name: Option<String>,
    /// Reason for blocking
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
    /// Explanation for the match (if available)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub explanation: Option<String>,
    /// Match source: `config_override`, `pack`, `heredoc_ast`, etc.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
    /// Matched span (start, end) in the command
    #[serde(skip_serializing_if = "Option::is_none")]
    pub matched_span: Option<(usize, usize)>,
    /// Severity level: "critical", "high", "medium", "low"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub severity: Option<String>,
    /// Allowlist override info if allowed via allowlist
    #[serde(skip_serializing_if = "Option::is_none")]
    pub allowlist: Option<AllowlistOverrideInfo>,
    /// Detected agent information
    #[serde(skip_serializing_if = "Option::is_none")]
    pub agent: Option<AgentInfo>,
}

/// Allowlist override information in test output
#[derive(Debug, Clone, serde::Serialize)]
pub struct AllowlistOverrideInfo {
    /// Which layer: "project", "user", "system"
    pub layer: String,
    /// Reason from the allowlist entry
    pub reason: String,
}

/// Agent detection information in test output
#[derive(Debug, Clone, serde::Serialize)]
pub struct AgentInfo {
    /// The detected agent name (e.g., "claude-code", "aider", "unknown")
    pub detected: String,
    /// Trust level for this agent (e.g., "high", "medium", "low")
    pub trust_level: String,
    /// How the agent was detected (e.g., "environment_variable", "explicit", "process", "none")
    pub detection_method: String,
}

/// JSON output structure for `orca packs` command
#[derive(Debug, Clone, serde::Serialize)]
pub struct PacksOutput {
    /// List of all packs
    pub packs: Vec<PackInfo>,
    /// Count of enabled packs
    pub enabled_count: usize,
    /// Total pack count
    pub total_count: usize,
}

/// Pack information in the packs list
#[derive(Debug, Clone, serde::Serialize)]
pub struct PackInfo {
    /// Pack ID (e.g., "core.git")
    pub id: String,
    /// Human-readable name
    pub name: String,
    /// Category (e.g., "core", "database")
    pub category: String,
    /// Description
    pub description: String,
    /// Whether the pack is enabled
    pub enabled: bool,
    /// Number of safe patterns
    pub safe_pattern_count: usize,
    /// Number of destructive patterns
    pub destructive_pattern_count: usize,
}

/// `orca suggest-allowlist` command arguments.
#[derive(Args, Debug)]
pub struct SuggestAllowlistCommand {
    /// Minimum times a command was blocked to be considered (default: 3)
    #[arg(long, default_value = "3")]
    pub min_frequency: usize,

    /// Look back period (e.g., "30d", "7d", "24h")
    #[arg(long, default_value = "30d")]
    pub since: String,

    /// Filter by confidence tier (high, medium, low, all)
    #[arg(long, default_value = "all")]
    pub confidence: ConfidenceTierFilter,

    /// Filter by risk level (low, medium, high, all)
    #[arg(long, default_value = "all")]
    pub risk: RiskLevelFilter,

    /// Non-interactive mode: print suggestions without prompts
    #[arg(long)]
    pub non_interactive: bool,

    /// Output format (text, json)
    #[arg(
        long,
        short = 'f',
        value_enum,
        default_value = "text",
        env = "ORCA_FORMAT"
    )]
    pub format: SuggestFormat,

    /// Maximum number of suggestions to show
    #[arg(long, default_value = "20")]
    pub limit: usize,

    /// Undo recently added auto-suggested patterns (removes patterns added in the last N minutes)
    #[arg(long)]
    pub undo: Option<u32>,

    /// Apply suggestions by index (comma-separated, 1-based). Skips interactive prompts.
    /// Example: --apply 1,3,5
    #[arg(long, value_delimiter = ',')]
    pub apply: Option<Vec<usize>>,

    /// Permit `--apply` to write suggestions whose safety decision is
    /// `RequireConfirmation` (e.g. patterns that touch system paths). Without
    /// this flag those suggestions are skipped to preserve the safety
    /// gate normally enforced in interactive mode.
    #[arg(long)]
    pub accept_risk: bool,
}

/// Output format for suggest-allowlist command.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, clap::ValueEnum)]
pub enum SuggestFormat {
    /// Human-readable colored output
    #[default]
    #[value(alias = "pretty")]
    Text,
    /// Structured JSON output
    #[value(alias = "sarif")]
    Json,
}

/// Filter for confidence tiers.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, clap::ValueEnum)]
pub enum ConfidenceTierFilter {
    /// High confidence suggestions only
    High,
    /// Medium confidence suggestions only
    Medium,
    /// Low confidence suggestions only
    Low,
    /// All confidence levels
    #[default]
    All,
}

/// Filter for risk levels.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, clap::ValueEnum)]
pub enum RiskLevelFilter {
    /// Low risk suggestions only
    Low,
    /// Medium risk suggestions only
    Medium,
    /// High risk suggestions only
    High,
    /// All risk levels
    #[default]
    All,
}

/// Export format options for history export.
#[derive(Debug, Clone, Copy, Default, clap::ValueEnum)]
pub enum ExportFormat {
    /// JSON with metadata wrapper
    #[default]
    Json,
    /// JSON Lines (one JSON object per line)
    Jsonl,
    /// Comma-separated values
    Csv,
}

/// History subcommand actions
#[derive(Subcommand, Debug, Clone)]
pub enum HistoryAction {
    /// Show history stats and summaries
    #[command(name = "stats")]
    Stats {
        /// Time period in days (default: 30)
        #[arg(long, short = 'd', default_value = "30")]
        days: u64,

        /// Include trend comparisons against the previous period
        #[arg(long)]
        trends: bool,

        /// Output as JSON
        #[arg(long)]
        json: bool,
    },

    /// Prune history entries older than the specified age
    #[command(name = "prune")]
    Prune {
        /// Prune entries older than this many days
        #[arg(long, value_name = "DAYS")]
        older_than_days: u64,

        /// Show what would be pruned without deleting
        #[arg(long)]
        dry_run: bool,

        /// Confirm pruning (required unless --dry-run)
        #[arg(long)]
        yes: bool,
    },

    /// Export command history to a file
    #[command(name = "export")]
    Export {
        /// Output file path (stdout if not specified)
        #[arg(long, short = 'o', value_name = "PATH")]
        output: Option<String>,

        /// Export format
        #[arg(long, short = 'f', value_enum, default_value = "json")]
        format: ExportFormat,

        /// Filter by outcome (allow, deny, warn, bypass)
        #[arg(long, value_name = "OUTCOME")]
        outcome: Option<String>,

        /// Include only commands since this date/time (ISO 8601)
        #[arg(long, value_name = "DATETIME")]
        since: Option<String>,

        /// Include only commands until this date/time (ISO 8601)
        #[arg(long, value_name = "DATETIME")]
        until: Option<String>,

        /// Maximum number of records to export
        #[arg(long, value_name = "N")]
        limit: Option<usize>,

        /// Compress output with gzip
        #[arg(long)]
        compress: bool,
    },

    /// Show interactive allowlist audit entries
    #[command(name = "interactive")]
    Interactive {
        /// Maximum number of entries to show
        #[arg(long, value_name = "N", default_value = "50")]
        limit: usize,

        /// Filter by option type (exact, temporary, path_specific)
        #[arg(long, value_name = "TYPE")]
        option: Option<String>,

        /// Output as JSON
        #[arg(long)]
        json: bool,
    },

    /// Analyze pack effectiveness and generate recommendations
    #[command(name = "analyze")]
    Analyze {
        /// Time period in days (default: 30)
        #[arg(long, short = 'd', default_value = "30")]
        days: u64,

        /// Output as JSON
        #[arg(long)]
        json: bool,

        /// Show only recommendations
        #[arg(long)]
        recommendations_only: bool,

        /// Show potential false positives (bypassed commands)
        #[arg(long)]
        false_positives: bool,

        /// Show potential coverage gaps (dangerous allowed commands)
        #[arg(long)]
        gaps: bool,
    },

    /// Check database health and integrity
    #[command(name = "check")]
    Check {
        /// Output as JSON
        #[arg(long)]
        json: bool,

        /// Fail with non-zero exit code if integrity check fails
        #[arg(long)]
        strict: bool,
    },

    /// Create a backup of the history database
    #[command(name = "backup")]
    Backup {
        /// Output file path for the backup
        #[arg(value_name = "PATH")]
        output: String,

        /// Compress the backup with gzip
        #[arg(long, short = 'z')]
        compress: bool,
    },
}

/// `orca scan` command arguments and actions.
#[derive(Args, Debug)]
#[command(args_conflicts_with_subcommands = true)]
pub struct ScanCommand {
    // === File selection modes (mutually exclusive) ===
    /// Scan files staged for commit (git index)
    #[arg(long, conflicts_with_all = ["paths", "git_diff"])]
    staged: bool,

    /// Scan explicit file paths (directories are expanded recursively)
    #[arg(long, conflicts_with_all = ["staged", "git_diff"], num_args = 1..)]
    paths: Option<Vec<std::path::PathBuf>>,

    /// Scan files changed in a git diff range (e.g., "HEAD~3..HEAD", "main..feature")
    #[arg(
        long = "git-diff",
        value_name = "REV_RANGE",
        conflicts_with_all = ["staged", "paths"]
    )]
    git_diff: Option<String>,

    // === Output / policy flags ===
    /// Output format
    #[arg(long, short = 'f', value_enum, env = "ORCA_FORMAT")]
    format: Option<crate::scan::ScanFormat>,

    /// Exit non-zero when findings meet this threshold
    #[arg(long, value_enum)]
    fail_on: Option<crate::scan::ScanFailOn>,

    // === Safety / performance knobs ===
    /// Maximum file size to scan (bytes); larger files are skipped
    #[arg(
        long = "max-file-size",
        value_name = "BYTES",
        value_parser = clap::value_parser!(u64)
    )]
    max_file_size: Option<u64>,

    /// Maximum number of findings to report (stop scanning after limit)
    #[arg(long = "max-findings", value_name = "N")]
    max_findings: Option<usize>,

    /// Exclude files matching glob pattern (repeatable)
    #[arg(long, value_name = "GLOB")]
    exclude: Vec<String>,

    /// Include only files matching glob pattern (repeatable)
    #[arg(long, value_name = "GLOB")]
    include: Vec<String>,

    // === Redaction / truncation ===
    /// Redact sensitive content in output
    #[arg(long, value_enum)]
    redact: Option<crate::scan::ScanRedactMode>,

    /// Truncate long commands in output (chars; 0 = no truncation)
    #[arg(long, value_name = "N")]
    truncate: Option<usize>,

    // === UX flags ===
    // NOTE: Removed `verbose: bool` - use global `-v`/`--verbose` instead.
    // The global flag (u8 count) conflicts with local bool flags.
    /// Limit exemplars shown in pretty output
    #[arg(long, value_name = "N", default_value = "10")]
    top: usize,

    /// Optional action subcommand (pre-commit integration helpers)
    #[command(subcommand)]
    action: Option<ScanAction>,
}

/// `orca scan` subcommands.
#[derive(Subcommand, Debug)]
pub enum ScanAction {
    /// Install a `.git/hooks/pre-commit` hook that runs `orca scan --staged`.
    #[command(name = "install-pre-commit")]
    InstallPreCommit,

    /// Uninstall the `.git/hooks/pre-commit` hook installed by orca.
    #[command(name = "uninstall-pre-commit")]
    UninstallPreCommit,
}

/// `orca simulate` command arguments.
///
/// This task (git_safety_guard-1gt.8.1) implements the streaming parser.
/// The evaluation loop and aggregation will be added in git_safety_guard-1gt.8.2.
#[derive(Args, Debug)]
pub struct SimulateCommand {
    /// Input file (use "-" for stdin)
    #[arg(long, short = 'f', default_value = "-")]
    pub file: String,

    /// Maximum number of lines to process
    #[arg(long)]
    pub max_lines: Option<usize>,

    /// Maximum bytes to read from input
    #[arg(long)]
    pub max_bytes: Option<usize>,

    /// Maximum command length in bytes (longer commands are skipped)
    #[arg(long, default_value = "65536")]
    pub max_command_bytes: usize,

    /// Fail on first malformed line (default: count and continue)
    #[arg(long)]
    pub strict: bool,

    /// Output format (for parse stats, evaluation comes later)
    #[arg(
        long,
        short = 'F',
        value_enum,
        default_value = "pretty",
        env = "ORCA_FORMAT"
    )]
    pub format: SimulateFormat,

    // NOTE: Removed `verbose: bool` - use global `-v`/`--verbose` instead.
    // The global flag (u8 count) conflicts with local bool flags.
    /// Redact sensitive data in exemplar commands
    #[arg(long, value_enum, default_value = "none")]
    pub redact: crate::scan::ScanRedactMode,

    /// Maximum length for exemplar commands in output (0 = unlimited)
    #[arg(long, default_value = "120")]
    pub truncate: usize,

    /// Limit output to top N rules by count (0 = show all)
    #[arg(long, default_value = "20")]
    pub top: usize,
}

/// Output format for simulate command.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, clap::ValueEnum)]
pub enum SimulateFormat {
    /// Human-readable output
    #[default]
    #[value(alias = "text")]
    Pretty,
    /// Structured JSON output
    #[value(alias = "sarif")]
    Json,
}

/// Output format for explain command.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, clap::ValueEnum)]
pub enum ExplainFormat {
    /// Human-readable colored output
    #[default]
    #[value(alias = "text")]
    Pretty,
    /// Compact single-line output
    Compact,
    /// Structured JSON output
    #[value(alias = "sarif")]
    Json,
}

/// Allowlist subcommand actions
#[derive(Subcommand, Debug)]
pub enum AllowlistAction {
    /// Add a rule to the allowlist
    #[command(name = "add")]
    Add {
        /// Rule ID to allowlist (e.g., "core.git:reset-hard")
        rule_id: String,

        /// Reason for allowlisting (required)
        #[arg(long, short = 'r')]
        reason: String,

        /// Add to project allowlist (default if in git repo)
        #[arg(long, conflicts_with = "user")]
        project: bool,

        /// Add to user allowlist
        #[arg(long, conflicts_with = "project")]
        user: bool,

        /// Expiration date (ISO 8601 / RFC 3339)
        #[arg(long)]
        expires: Option<String>,

        /// Environment condition (e.g., CI=true)
        #[arg(long = "condition", value_name = "KEY=VAL")]
        conditions: Vec<String>,

        /// Path glob pattern where this entry applies (repeatable)
        #[arg(long = "path", value_name = "GLOB")]
        paths: Vec<String>,
    },

    /// Add an exact command to the allowlist
    #[command(name = "add-command")]
    AddCommand {
        /// Exact command to allowlist
        command: String,

        /// Reason for allowlisting (required)
        #[arg(long, short = 'r')]
        reason: String,

        /// Add to project allowlist (default if in git repo)
        #[arg(long, conflicts_with = "user")]
        project: bool,

        /// Add to user allowlist
        #[arg(long, conflicts_with = "project")]
        user: bool,

        /// Expiration date (ISO 8601 / RFC 3339)
        #[arg(long)]
        expires: Option<String>,

        /// Path glob pattern where this entry applies (repeatable)
        #[arg(long = "path", value_name = "GLOB")]
        paths: Vec<String>,
    },

    /// List allowlist entries
    #[command(name = "list")]
    List {
        /// Show project allowlist only
        #[arg(long, conflicts_with = "user")]
        project: bool,

        /// Show user allowlist only
        #[arg(long, conflicts_with = "project")]
        user: bool,

        /// Output format
        #[arg(long, value_enum, default_value = "pretty", env = "ORCA_FORMAT")]
        format: AllowlistOutputFormat,
    },

    /// Remove a rule from the allowlist
    #[command(name = "remove")]
    Remove {
        /// Rule ID to remove (e.g., "core.git:reset-hard")
        rule_id: String,

        /// Remove from project allowlist (default if in git repo)
        #[arg(long, conflicts_with = "user")]
        project: bool,

        /// Remove from user allowlist
        #[arg(long, conflicts_with = "project")]
        user: bool,
    },

    /// Validate allowlist entries
    #[command(name = "validate")]
    Validate {
        /// Validate project allowlist only
        #[arg(long, conflicts_with = "user")]
        project: bool,

        /// Validate user allowlist only
        #[arg(long, conflicts_with = "project")]
        user: bool,

        /// Treat warnings as errors
        #[arg(long)]
        strict: bool,
    },

    /// Remove expired allowlist entries
    #[command(name = "prune")]
    Prune {
        /// Prune project allowlist only
        #[arg(long, conflicts_with = "user")]
        project: bool,

        /// Prune user allowlist only
        #[arg(long, conflicts_with = "project")]
        user: bool,

        /// Show what would be removed without writing changes
        #[arg(long)]
        dry_run: bool,

        /// Output format
        #[arg(long, value_enum, default_value = "pretty", env = "ORCA_FORMAT")]
        format: AllowlistOutputFormat,
    },
}

/// Subcommands for managing allow-once entries.
#[derive(Subcommand, Debug, Clone)]
pub enum AllowOnceAction {
    /// List pending codes and active allow-once entries (redacted by default)
    #[command(name = "list")]
    List,

    /// Clear expired entries and optionally wipe stores
    #[command(name = "clear")]
    Clear(AllowOnceClearArgs),

    /// Revoke a pending code or active allow-once entry
    #[command(name = "revoke")]
    Revoke(AllowOnceRevokeArgs),
}

#[derive(Args, Debug, Clone)]
pub struct AllowOnceClearArgs {
    /// Wipe both pending codes and active allow-once entries
    #[arg(long)]
    pub all: bool,

    /// Wipe pending codes
    #[arg(long)]
    pub pending: bool,

    /// Wipe active allow-once entries
    #[arg(long = "allow-once")]
    pub allow_once: bool,
}

#[derive(Args, Debug, Clone)]
pub struct AllowOnceRevokeArgs {
    /// Short code or full hash (or prefix) to revoke
    pub target: String,
}

/// Allow-once command arguments.
///
/// - `orca allow-once <CODE>` (legacy shorthand for applying an allow-once code)
/// - `orca allow-once list|clear|revoke` (management commands)
#[derive(Args, Debug)]
#[command(subcommand_precedence_over_arg = true)]
#[allow(clippy::struct_excessive_bools)]
pub struct AllowOnceCommand {
    /// Optional management subcommand.
    #[command(subcommand)]
    pub action: Option<AllowOnceAction>,

    /// Short code printed at the top of a denial message (legacy shorthand for apply)
    #[arg(value_name = "CODE")]
    pub code: Option<String>,

    /// Automatically confirm (non-interactive)
    #[arg(long, short = 'y', global = true)]
    pub yes: bool,

    /// Show raw command text in output (default shows redacted)
    #[arg(long, global = true)]
    pub show_raw: bool,

    /// Dry-run (do not write allow-once entry) (apply-only)
    #[arg(long)]
    pub dry_run: bool,

    /// Output JSON for automation
    #[arg(long, global = true)]
    pub json: bool,

    /// Allow a single use only (consumed after first allow) (apply-only)
    #[arg(long)]
    pub single_use: bool,

    /// Override explicit config blocklist (extra confirmation required) (apply-only)
    #[arg(long)]
    pub force: bool,

    /// Select a specific entry when multiple match the code (1-based) (apply-only)
    #[arg(long, value_name = "N", conflicts_with = "hash")]
    pub pick: Option<usize>,

    /// Select by full hash when multiple match the code (apply-only)
    #[arg(long, value_name = "HASH", conflicts_with = "pick")]
    pub hash: Option<String>,
}

/// Output format for allowlist list command
#[derive(Debug, Clone, Copy, PartialEq, Eq, clap::ValueEnum)]
pub enum AllowlistOutputFormat {
    /// Human-readable output
    #[value(alias = "text")]
    Pretty,
    /// JSON output
    #[value(alias = "sarif")]
    Json,
}

/// Pack subcommand actions
#[derive(Subcommand, Debug)]
pub enum PackAction {
    /// Show information about a specific pack (built-in or external)
    #[command(name = "info")]
    Info {
        /// Pack ID (e.g., "database.postgresql", "core.git")
        pack_id: String,

        /// Hide pattern details (patterns are shown by default)
        #[arg(long)]
        no_patterns: bool,

        /// Output as JSON instead of human-readable text
        #[arg(long)]
        json: bool,
    },

    /// Validate an external pack YAML file
    ///
    /// Checks for:
    /// - Valid YAML syntax
    /// - Required fields (id, name, version)
    /// - ID format (namespace.name)
    /// - Version format (semver)
    /// - Pattern regex compilation
    /// - Duplicate pattern names
    /// - Collision with built-in packs
    #[command(name = "validate")]
    Validate {
        /// Path to pack YAML file
        file_path: String,

        /// Treat warnings as errors (exit non-zero on warnings)
        #[arg(long)]
        strict: bool,

        /// Output format
        #[arg(long, short = 'f', value_enum, default_value_t = PackValidateFormat::Pretty, env = "ORCA_FORMAT")]
        format: PackValidateFormat,
    },
}

/// Output format for pack validate command
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, clap::ValueEnum)]
pub enum PackValidateFormat {
    /// Human-readable colored output
    #[default]
    #[value(alias = "text")]
    Pretty,
    /// Structured JSON output for tooling integration
    #[value(alias = "sarif")]
    Json,
}

/// Run the CLI command.
///
/// # Errors
///
/// Returns an error when no subcommand is provided (hook mode), or when a
/// subcommand that performs I/O fails.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Verbosity {
    level: u8,
    quiet: bool,
}

impl Verbosity {
    fn from_cli(cli: &Cli) -> Self {
        Self {
            level: cli.verbose.min(3),
            quiet: cli.quiet,
        }
    }

    const fn level(self) -> u8 {
        if self.quiet { 0 } else { self.level }
    }

    const fn is_verbose(self) -> bool {
        self.level() >= 1
    }

    const fn is_debug(self) -> bool {
        self.level() >= 2
    }

    const fn is_trace(self) -> bool {
        self.level() >= 3
    }
}

/// Structured output from a CLI subcommand, allowing the caller
/// (interactive CLI or daemon request handler) to decide how to
/// render the result and whether to exit the process.
#[derive(Debug)]
pub enum CommandOutput {
    /// Success with no special exit code.
    Ok,
    /// Result from the `test` subcommand.
    TestResult { blocked: bool },
    /// Result from the `classify` subcommand.
    ClassifyResult { exit_code: i32 },
    /// Result from the `validate` subcommand.
    ValidateResult {
        exit_error: bool,
        reports: Vec<String>,
    },
    /// Result from the `scan` subcommand.
    ScanResult {
        report: crate::scan::ScanReport,
        should_fail: bool,
    },
    /// Result from the `history check --strict` subcommand.
    HistoryResult { strict_ok: bool },
}
/// Captured stdout/stderr/exit code from a daemon-safe CLI invocation.
///
/// Used by [`execute_daemon_cli`] and serialized into daemon protocol
/// `CliExecution` responses.  Handlers must never call [`std::process::exit`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CliExecutionResult {
    pub stdout: String,
    pub stderr: String,
    pub exit_code: i32,
}

/// Machine-readable version line written to stdout by `orca --version`.
#[must_use]
pub fn version_stdout_line() -> String {
    format!("{}\n", env!("CARGO_PKG_VERSION"))
}

/// Execute a whitelisted CLI operation for daemon `ExecuteCli` requests.
///
/// Routes through the same version formatting as standalone `orca --version`
/// stdout output.  Unsupported commands return structured errors instead of
/// terminating the process.
///
/// Read-only proxies (version, test, scan, history, packs, pack, precommit,
/// explain, classify, simulate, allowlist list/show, suggest-allowlist without
/// `--apply`/`--undo`, and `--help` for any proxy command) are allowed over UDS.
///
/// Mutating commands (`allow`, `unallow`, `allow-once`, `rebase-recover`,
/// `config`, allowlist writes, `suggest-allowlist --apply`/`--undo`) are refused here.
/// The Zig CLI must spawn `orca-daemon <cmd>` directly for those — same-UID
/// peers on the 0600 socket must not rewrite policy via ExecuteCli.
#[must_use]
pub fn execute_daemon_cli(argv: &[String]) -> CliExecutionResult {
    execute_daemon_cli_at(argv, None)
}

#[must_use]
pub fn execute_daemon_cli_at(argv: &[String], cwd: Option<&str>) -> CliExecutionResult {
    if argv.is_empty() {
        return CliExecutionResult {
            stdout: String::new(),
            stderr: "ExecuteCli requires at least one argument (subcommand)".to_string(),
            exit_code: EXIT_PARSE_ERROR,
        };
    }

    // R03: refuse policy mutations over UDS ExecuteCli (socket is same-UID).
    if is_mutating_daemon_cli_argv(argv) {
        return CliExecutionResult {
            stdout: String::new(),
            stderr: format!(
                "ExecuteCli refused mutating command `{}`: policy mutations are not permitted over the daemon UDS socket. Run `orca-daemon {} …` locally (Zig `orca` spawns the daemon binary for these commands).",
                argv[0], argv[0]
            ),
            exit_code: EXIT_DENIED,
        };
    }

    match argv[0].as_str() {
        "version" | "--version" | "-V" => CliExecutionResult {
            stdout: version_stdout_line(),
            stderr: String::new(),
            exit_code: EXIT_SUCCESS,
        },
        cmd if is_daemon_proxy_command(cmd) => execute_proxied_daemon_cli(argv, cwd),
        other => CliExecutionResult {
            stdout: String::new(),
            stderr: format!(
                "unsupported daemon CLI command: {other} (supported read-only: version, test, scan, history, precommit, packs, pack, explain, allowlist list/show, classify, suggest-allowlist, simulate; mutations require local orca-daemon)"
            ),
            exit_code: EXIT_PARSE_ERROR,
        },
    }
}

/// True when `argv` would mutate policy/config if executed via ExecuteCli.
///
/// `--help` / `-h` are treated as read-only for every command.
#[must_use]
pub(crate) fn is_mutating_daemon_cli_argv(argv: &[String]) -> bool {
    if argv.is_empty() {
        return false;
    }
    if argv.iter().any(|arg| arg == "--help" || arg == "-h") {
        return false;
    }
    match argv[0].as_str() {
        "allow" | "unallow" | "allow-once" | "rebase-recover" | "config" => true,
        "allowlist" => match argv.get(1).map(String::as_str) {
            None | Some("list") | Some("show") | Some("ls") => false,
            Some(_) => true,
        },
        "suggest-allowlist" => argv.iter().any(|arg| {
            arg == "--apply"
                || arg.starts_with("--apply=")
                || arg == "--undo"
                || arg.starts_with("--undo=")
        }),
        _ => false,
    }
}

fn is_daemon_proxy_command(command: &str) -> bool {
    matches!(
        command,
        "test"
            | "scan"
            | "history"
            | "packs"
            | "pack"
            | "precommit"
            | "explain"
            | "allowlist"
            | "allow"
            | "unallow"
            | "allow-once"
            | "classify"
            | "suggest-allowlist"
            | "rebase-recover"
            | "config"
            | "simulate"
    )
}

fn execute_proxied_daemon_cli(argv: &[String], cwd: Option<&str>) -> CliExecutionResult {
    let Some(mapped_argv) = map_daemon_proxy_argv(argv) else {
        return CliExecutionResult {
            stdout: String::new(),
            stderr: "ExecuteCli requires at least one argument (subcommand)".to_string(),
            exit_code: EXIT_PARSE_ERROR,
        };
    };

    if mapped_argv.iter().any(|arg| arg == "--help" || arg == "-h") {
        return render_daemon_proxy_help(mapped_argv[0].as_str());
    }

    let exe = match std::env::current_exe() {
        Ok(path) => path,
        Err(err) => {
            return CliExecutionResult {
                stdout: String::new(),
                stderr: format!("failed to resolve daemon executable: {err}"),
                exit_code: EXIT_IO_ERROR,
            };
        }
    };

    let mut command = std::process::Command::new(exe);
    command.args(&mapped_argv);
    if let Some(cwd) = cwd {
        command.current_dir(cwd);
    }
    match command.output() {
        Ok(output) => CliExecutionResult {
            stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
            exit_code: output.status.code().unwrap_or(EXIT_IO_ERROR),
        },
        Err(err) => CliExecutionResult {
            stdout: String::new(),
            stderr: format!("failed to execute daemon CLI command: {err}"),
            exit_code: EXIT_IO_ERROR,
        },
    }
}

fn map_daemon_proxy_argv(argv: &[String]) -> Option<Vec<String>> {
    let (command, rest) = argv.split_first()?;
    let mapped = if command == "precommit" {
        let mut mapped = Vec::with_capacity(rest.len() + 2);
        mapped.push("scan".to_string());
        if rest.iter().any(|arg| arg == "--help" || arg == "-h") {
        } else {
            mapped.push("--staged".to_string());
        }
        mapped.extend(rest.iter().cloned());
        mapped
    } else {
        argv.to_vec()
    };
    Some(mapped)
}

fn render_daemon_proxy_help(command_name: &str) -> CliExecutionResult {
    let mut command = Cli::command();
    let Some(subcommand) = command.find_subcommand_mut(command_name) else {
        return CliExecutionResult {
            stdout: String::new(),
            stderr: format!("unsupported daemon CLI command: {command_name}"),
            exit_code: EXIT_PARSE_ERROR,
        };
    };

    let mut help = Vec::new();
    match subcommand.write_long_help(&mut help) {
        Ok(()) => CliExecutionResult {
            stdout: String::from_utf8_lossy(&help).into_owned(),
            stderr: String::new(),
            exit_code: EXIT_SUCCESS,
        },
        Err(err) => CliExecutionResult {
            stdout: String::new(),
            stderr: format!("failed to render help: {err}"),
            exit_code: EXIT_IO_ERROR,
        },
    }
}

/// # Errors
///
/// Returns an error when no subcommand is provided (hook mode) or when a
/// subcommand that performs I/O fails.
#[allow(clippy::too_many_lines)]
pub fn run_command(cli: Cli) -> Result<CommandOutput, Box<dyn std::error::Error>> {
    let config = Config::load();
    let verbosity = Verbosity::from_cli(&cli);

    match cli.command {
        Some(Command::Hook(cmd)) => {
            run_hook_command(&config, &cmd)?;
        }
        Some(Command::ListPacks {
            enabled,
            expand,
            max_patterns,
            format,
        }) => {
            // Robot mode forces JSON output
            let robot_mode = robot_mode_enabled(cli.robot);
            let effective_format = if robot_mode {
                PacksFormat::Json
            } else {
                format
            };

            // Load external packs from custom_paths so they appear in the listing
            let external_paths = config.packs.expand_custom_paths();
            let _ = load_external_packs(&external_paths);

            list_packs(
                &config,
                enabled,
                verbosity.is_verbose(),
                effective_format,
                verbosity.quiet,
                expand,
                max_patterns,
            );
        }
        Some(Command::Pack {
            action:
                PackAction::Validate {
                    file_path,
                    strict,
                    format,
                },
        }) => {
            let exit_error = pack_validate(&file_path, strict, format)?;
            return Ok(CommandOutput::ValidateResult {
                exit_error,
                reports: vec![file_path],
            });
        }
        Some(Command::Pack { action }) => {
            handle_pack_command(&config, action)?;
        }
        Some(Command::TestCommand {
            command,
            config: config_path,
            with_packs,
            explain,
            format,
            no_color,
            heredoc_scan,
            no_heredoc_scan,
            heredoc_timeout_ms,
            heredoc_languages,
            force,
        }) => {
            // Robot mode forces JSON output
            let robot_mode = robot_mode_enabled(cli.robot);
            let effective_format = if robot_mode { TestFormat::Json } else { format };

            // Load specific config file if provided, otherwise use default
            let effective_config = if let Some(ref path) = config_path {
                Config::load_from_file(path).unwrap_or_else(|| {
                    eprintln!("Warning: Failed to load config from {}", path.display());
                    config.clone()
                })
            } else {
                config.clone()
            };

            if explain {
                // Delegate to explain handler for detailed trace output
                // Convert TestFormat to ExplainFormat for explain mode
                let explain_format = match effective_format {
                    TestFormat::Pretty => ExplainFormat::Pretty,
                    TestFormat::Json | TestFormat::Toon => ExplainFormat::Json,
                };
                handle_explain(&effective_config, &command, explain_format, with_packs);
            } else {
                let was_blocked = test_command(
                    &effective_config,
                    &command,
                    with_packs,
                    effective_format,
                    verbosity,
                    no_color || robot_mode, // Robot mode also implies no color
                    robot_mode,
                    heredoc_scan,
                    no_heredoc_scan,
                    heredoc_timeout_ms,
                    heredoc_languages,
                    force,
                );
                // Exit with code 1 if command would be blocked (for CI/robot mode scripting)
                return Ok(CommandOutput::TestResult {
                    blocked: was_blocked,
                });
            }
        }
        Some(Command::ShowConfig) => {
            if !verbosity.quiet {
                show_config(&config);
            }
        }
        Some(Command::Allowlist { action }) => {
            handle_allowlist_command(action, config.allowlist.auto_prune_expired)?;
        }
        Some(Command::Allow {
            rule_id,
            reason,
            project,
            user,
            temporary,
            expires,
        }) => {
            // Shortcut for `allowlist add`
            let layer = resolve_layer(project, user);

            // Compute the effective expiration: --temporary converts duration to absolute time
            let effective_expires = match (&temporary, &expires) {
                (Some(duration_str), None) => {
                    // Parse duration and compute absolute expiration time
                    let duration = crate::allowlist::parse_duration(duration_str)
                        .map_err(|e| format!("Invalid duration: {e}"))?;

                    // Warn if duration is longer than 30 days
                    if let Some(days) = duration.num_days().checked_abs() {
                        if days > 30 {
                            eprintln!(
                                "Warning: Temporary allowlist entry expires in {days} days. \
                                 Consider using a permanent entry with `--expires` for long durations."
                            );
                        }
                    }

                    let expires_at = Utc::now()
                        .checked_add_signed(duration)
                        .ok_or("Duration overflow: expiration time too far in the future")?;
                    Some(expires_at.to_rfc3339())
                }
                (None, Some(exp)) => Some(exp.clone()),
                (None, None) => None,
                // This case is prevented by clap's conflicts_with, but handle it for safety
                (Some(_), Some(_)) => {
                    return Err("Cannot specify both --temporary and --expires".into());
                }
            };

            allowlist_add_rule(&rule_id, &reason, layer, effective_expires.as_deref(), &[])?;
        }
        Some(Command::Unallow {
            rule_id,
            project,
            user,
        }) => {
            // Shortcut for `allowlist remove`
            let layer = resolve_layer(project, user);
            allowlist_remove(&rule_id, layer)?;
        }
        Some(Command::AllowOnce(cmd)) => {
            handle_allow_once_command(&config, &cmd)?;
        }
        Some(Command::RebaseRecover { ttl }) => {
            handle_rebase_recover(ttl, robot_mode_enabled(cli.robot))?;
        }
        Some(Command::Scan(scan)) => {
            if let Some((report, should_fail)) = handle_scan_command(&config, scan, verbosity)? {
                return Ok(CommandOutput::ScanResult {
                    report,
                    should_fail,
                });
            }
        }
        Some(Command::Simulate(sim)) => {
            handle_simulate_command(sim, &config, verbosity)?;
        }
        Some(Command::Explain {
            command,
            format,
            with_packs,
        }) => {
            // Robot mode forces JSON output
            let robot_mode = robot_mode_enabled(cli.robot);
            let effective_format = if robot_mode {
                ExplainFormat::Json
            } else {
                format
            };

            if !verbosity.quiet {
                handle_explain(&config, &command, effective_format, with_packs);
            }
        }
        Some(Command::History {
            action: HistoryAction::Check { json, strict },
        }) => {
            let db_path = config.history.expanded_database_path();
            let db = match HistoryDb::open(db_path) {
                Ok(db) => db,
                Err(err) => {
                    println!("Error opening history database: {err}");
                    return Ok(CommandOutput::Ok);
                }
            };
            let strict_ok = history_check(&db, json, strict)?;
            return Ok(CommandOutput::HistoryResult { strict_ok });
        }
        Some(Command::History { action }) => {
            handle_history_command(&config, action)?;
        }
        Some(Command::SuggestAllowlist(cmd)) => {
            let robot_mode = robot_mode_enabled(cli.robot);
            handle_suggest_allowlist_command(&config, &cmd, robot_mode)?;
        }
        Some(Command::Classify {
            command,
            format,
            no_color,
        }) => {
            let robot_mode = robot_mode_enabled(cli.robot);
            let exit_code = classify_command(&config, &command, format, no_color || robot_mode);
            return Ok(CommandOutput::ClassifyResult { exit_code });
        }
        None => {
            // No subcommand - run in hook mode (default behavior)
            // This is handled by main.rs
            return Err("No subcommand provided. Running in hook mode.".into());
        }
    }

    Ok(CommandOutput::Ok)
}

// ============================================================================
// Hook Command (orca hook --batch)
// ============================================================================

/// Run the hook command with optional batch processing.
#[allow(clippy::too_many_lines)]
fn run_hook_command(config: &Config, cmd: &HookCommand) -> Result<(), Box<dyn std::error::Error>> {
    use std::io::{self, BufRead, Write};

    // If not batch mode and not parallel, fall through to normal hook mode
    if !cmd.batch && !cmd.parallel {
        // Delegate to main.rs hook mode by returning an error
        // that main.rs will catch and handle
        return Err("Hook mode without --batch; delegating to main.rs".into());
    }

    // Parallel implies batch
    let workers = if cmd.workers == 0 {
        std::thread::available_parallelism()
            .map(std::num::NonZeroUsize::get)
            .unwrap_or(4)
    } else {
        cmd.workers
    };

    // Load configuration for evaluation
    let compiled_overrides = config.overrides.compile();
    let allowlists = crate::load_default_allowlists();
    let heredoc_settings = config.heredoc_settings();
    let mut enabled_packs = config.enabled_pack_ids();
    let mut enabled_keywords = REGISTRY.collect_enabled_keywords(&enabled_packs);

    // Load external packs from custom_paths (glob + tilde expansion).
    let external_paths = config.packs.expand_custom_paths();
    let external_store = load_external_packs(&external_paths);

    // Auto-enable external packs and merge their keywords.
    for id in external_store.pack_ids() {
        enabled_packs.insert(id.clone());
    }
    enabled_keywords.extend(external_store.keywords().iter().copied());

    // Build ordered pack list AFTER external packs are loaded so they're included.
    let mut ordered_packs = REGISTRY.expand_enabled_ordered(&enabled_packs);
    for id in external_store.pack_ids() {
        if !ordered_packs.contains(id) {
            ordered_packs.push(id.clone());
        }
    }
    // Disable keyword index when external packs are present (not covered by index).
    let keyword_index = if external_store.pack_ids().next().is_some() {
        None
    } else {
        REGISTRY.build_enabled_keyword_index(&ordered_packs)
    };

    let stdin = io::stdin();
    let stdout = io::stdout();
    let mut stdout_lock = stdout.lock();

    if cmd.parallel && workers > 1 {
        // Parallel processing: collect all lines, process in parallel, output in order
        let lines: Vec<(usize, String)> = stdin
            .lock()
            .lines()
            .enumerate()
            .filter_map(|(idx, line)| line.ok().map(|l| (idx, l)))
            .collect();

        // Process in parallel using rayon
        #[cfg(feature = "rayon")]
        {
            use rayon::prelude::*;

            let results: Vec<BatchHookOutput> = lines
                .into_par_iter()
                .map(|(index, line)| {
                    evaluate_batch_line(
                        index,
                        &line,
                        &enabled_keywords,
                        &ordered_packs,
                        keyword_index.as_ref(),
                        &compiled_overrides,
                        &allowlists,
                        &heredoc_settings,
                        cmd.continue_on_error,
                    )
                })
                .collect();

            // Sort by index and output
            let mut sorted = results;
            sorted.sort_by_key(|r| r.index);

            for result in sorted {
                let json = serde_json::to_string(&result)?;
                writeln!(stdout_lock, "{json}")?;
            }
        }

        // Fallback to sequential if rayon is not available
        #[cfg(not(feature = "rayon"))]
        {
            for (index, line) in lines {
                let result = evaluate_batch_line(
                    index,
                    &line,
                    &enabled_keywords,
                    &ordered_packs,
                    keyword_index.as_ref(),
                    &compiled_overrides,
                    &allowlists,
                    &heredoc_settings,
                    cmd.continue_on_error,
                );
                let json = serde_json::to_string(&result)?;
                writeln!(stdout_lock, "{json}")?;
            }
        }
    } else {
        // Sequential processing: stream input to output
        for (index, line) in stdin.lock().lines().enumerate() {
            let line = match line {
                Ok(l) => l,
                Err(e) => {
                    if cmd.continue_on_error {
                        let result = BatchHookOutput {
                            index,
                            decision: "error",
                            rule_id: None,
                            pack_id: None,
                            error: Some(format!("IO error: {e}")),
                        };
                        let json = serde_json::to_string(&result)?;
                        writeln!(stdout_lock, "{json}")?;
                        continue;
                    }
                    return Err(e.into());
                }
            };

            let result = evaluate_batch_line(
                index,
                &line,
                &enabled_keywords,
                &ordered_packs,
                keyword_index.as_ref(),
                &compiled_overrides,
                &allowlists,
                &heredoc_settings,
                cmd.continue_on_error,
            );
            let json = serde_json::to_string(&result)?;
            writeln!(stdout_lock, "{json}")?;
        }
    }

    Ok(())
}

/// Evaluate a single batch line and return the result.
#[allow(clippy::too_many_arguments, clippy::too_many_lines)]
fn evaluate_batch_line(
    index: usize,
    line: &str,
    enabled_keywords: &[&str],
    ordered_packs: &[String],
    keyword_index: Option<&crate::packs::EnabledKeywordIndex>,
    compiled_overrides: &crate::config::CompiledOverrides,
    allowlists: &crate::allowlist::LayeredAllowlist,
    heredoc_settings: &crate::config::HeredocSettings,
    continue_on_error: bool,
) -> BatchHookOutput {
    // Skip empty lines
    if line.trim().is_empty() {
        return BatchHookOutput {
            index,
            decision: "skip",
            rule_id: None,
            pack_id: None,
            error: Some("Empty line".to_string()),
        };
    }

    // Parse JSON input
    let hook_input: crate::hook::HookInput = match serde_json::from_str(line) {
        Ok(input) => input,
        Err(e) => {
            if continue_on_error {
                return BatchHookOutput {
                    index,
                    decision: "error",
                    rule_id: None,
                    pack_id: None,
                    error: Some(format!("JSON parse error: {e}")),
                };
            }
            return BatchHookOutput {
                index,
                decision: "error",
                rule_id: None,
                pack_id: None,
                error: Some(format!("JSON parse error: {e}")),
            };
        }
    };

    let Some((command, _protocol)) = crate::hook::extract_command_with_protocol(&hook_input) else {
        return BatchHookOutput {
            index,
            decision: "skip",
            rule_id: None,
            pack_id: None,
            error: Some("Not a supported shell tool invocation or missing command".to_string()),
        };
    };

    // Evaluate the command
    let eval_result = evaluate_command_with_pack_order_deadline_at_path(
        &command,
        enabled_keywords,
        ordered_packs,
        keyword_index,
        compiled_overrides,
        allowlists,
        heredoc_settings,
        None,
        None,
        None,
        None, // No deadline for batch mode
    );

    match eval_result.decision {
        EvaluationDecision::Allow => BatchHookOutput {
            index,
            decision: "allow",
            rule_id: None,
            pack_id: None,
            error: None,
        },
        EvaluationDecision::Deny => {
            // Extract pattern info for deny decisions
            let (rule_id, pack_id) =
                eval_result
                    .pattern_info
                    .as_ref()
                    .map_or((None, None), |info| {
                        let rule_id = match (&info.pack_id, &info.pattern_name) {
                            (Some(p), Some(pat)) => Some(format!("{p}:{pat}")),
                            (Some(p), None) => Some(p.clone()),
                            _ => None,
                        };
                        (rule_id, info.pack_id.clone())
                    });

            BatchHookOutput {
                index,
                decision: "deny",
                rule_id,
                pack_id,
                error: None,
            }
        }
    }
}

/// List all packs and their status
fn list_packs(
    config: &Config,
    enabled_only: bool,
    verbose: bool,
    format: PacksFormat,
    quiet: bool,
    expand: bool,
    max_patterns: usize,
) {
    if quiet {
        return;
    }

    let enabled_packs = config.enabled_pack_ids();
    let infos = REGISTRY.list_packs(&enabled_packs);

    // Build pack list (filtered if enabled_only)
    let mut pack_list: Vec<PackInfo> = infos
        .iter()
        .filter(|info| !enabled_only || info.enabled)
        .map(|info| {
            let category = info.id.split('.').next().unwrap_or(&info.id).to_string();
            PackInfo {
                id: info.id.clone(),
                name: info.name.to_string(),
                category,
                description: info.description.to_string(),
                enabled: info.enabled,
                safe_pattern_count: info.safe_pattern_count,
                destructive_pattern_count: info.destructive_pattern_count,
            }
        })
        .collect();

    // Include external packs from custom_paths
    // External packs are auto-enabled when loaded (same behavior as test_command_inner)
    if let Some(external_store) = get_external_packs() {
        for (id, pack) in external_store.iter_packs() {
            // External packs loaded via custom_paths are always enabled by convention
            // (if you add a pack to custom_paths, you want it active)
            let is_enabled = true;
            if enabled_only && !is_enabled {
                continue;
            }
            let category = id.split('.').next().unwrap_or(id).to_string();
            pack_list.push(PackInfo {
                id: id.clone(),
                name: pack.name.to_string(),
                category,
                description: pack.description.to_string(),
                enabled: is_enabled,
                safe_pattern_count: pack.safe_patterns.len(),
                destructive_pattern_count: pack.destructive_patterns.len(),
            });
        }
    }

    // Handle JSON output
    let total_count = infos.len() + get_external_packs().map_or(0, ExternalPackStore::len);
    if format == PacksFormat::Json {
        let enabled_count = pack_list.iter().filter(|p| p.enabled).count();
        let output = PacksOutput {
            packs: pack_list,
            enabled_count,
            total_count,
        };
        println!("{}", serde_json::to_string_pretty(&output).unwrap());
        return;
    }

    // Rich output when feature enabled and the process is attached to a
    // terminal that can render it. Non-TTY output keeps the plain stdout
    // contract used by scripts and tests.
    #[cfg(feature = "rich-output")]
    {
        if crate::output::should_use_rich_output() {
            list_packs_rich(&pack_list, verbose, expand, max_patterns);
            return;
        }
    }

    // Pretty output (default, non-rich fallback)
    println!("Available packs:");
    println!();

    // Group by category (use pack_list which includes both built-in and external packs)
    let mut by_category: std::collections::BTreeMap<&str, Vec<&PackInfo>> =
        std::collections::BTreeMap::new();
    for info in &pack_list {
        let category = info.category.as_str();
        by_category.entry(category).or_default().push(info);
    }

    for (category, packs) in by_category {
        println!("  {category}:");
        for info in packs {
            if enabled_only && !info.enabled {
                continue;
            }

            let status = if info.enabled { "✓" } else { "○" };
            if verbose {
                let description = markdown_single_line_for_cli(&info.description);
                println!(
                    "    {} {} - {} ({} safe, {} destructive)",
                    status,
                    info.id,
                    description,
                    info.safe_pattern_count,
                    info.destructive_pattern_count
                );
                print_pack_patterns_plain(info, expand, max_patterns);
            } else {
                println!("    {} {} - {}", status, info.id, info.name);
            }
        }
        println!();
    }

    println!("Legend: ✓ = enabled, ○ = disabled");
    println!();
    println!("Enable packs in ~/.config/orca/config.toml");
}

fn print_pack_patterns_plain(info: &PackInfo, expand: bool, max_patterns: usize) {
    let Some(pack) = REGISTRY.get(&info.id) else {
        return;
    };
    let use_color = crate::output::auto_theme().colors_enabled;

    let safe_patterns = pack
        .safe_patterns
        .iter()
        .map(|pattern| {
            let regex = crate::highlight::format_regex_pattern(pattern.regex.as_str(), use_color);
            format!("{}: {}", pattern.name, regex)
        })
        .collect();
    print_pack_pattern_lines("Safe patterns", safe_patterns, expand, max_patterns);

    let destructive_patterns = pack
        .destructive_patterns
        .iter()
        .map(|pattern| {
            let name = pattern.name.unwrap_or("unnamed");
            let severity_label = pattern.severity.label();
            let regex = crate::highlight::format_regex_pattern(pattern.regex.as_str(), use_color);
            format!("{name} [{severity_label}]: {regex}")
        })
        .collect();
    print_pack_pattern_lines(
        "Destructive patterns",
        destructive_patterns,
        expand,
        max_patterns,
    );
}

fn print_pack_pattern_lines(title: &str, lines: Vec<String>, expand: bool, max_patterns: usize) {
    if lines.is_empty() {
        return;
    }

    println!("      {title}:");
    let total = lines.len();
    let max_patterns = max_patterns.max(1);

    if expand || total <= max_patterns {
        for line in lines {
            println!("        - {line}");
        }
        return;
    }

    let head_count = max_patterns.div_ceil(2);
    let tail_count = max_patterns.saturating_sub(head_count);
    let hidden_count = total.saturating_sub(head_count + tail_count);

    for line in lines.iter().take(head_count) {
        println!("        - {line}");
    }
    println!("        - ... {hidden_count} more patterns (--expand to show all)");
    if tail_count > 0 {
        for line in lines.iter().skip(total - tail_count) {
            println!("        - {line}");
        }
    }
}

/// Rich terminal packs output using OrcaConsole and markup.
#[cfg(feature = "rich-output")]
fn list_packs_rich(pack_list: &[PackInfo], verbose: bool, expand: bool, max_patterns: usize) {
    let tree_items: Vec<_> = pack_list
        .iter()
        .map(|info| {
            let item = crate::output::PackTreeItem::new(
                &info.id,
                &info.name,
                &info.category,
                &info.description,
                info.enabled,
                info.safe_pattern_count,
                info.destructive_pattern_count,
            );

            if !verbose {
                return item;
            }

            let Some(pack) = REGISTRY.get(&info.id) else {
                return item;
            };

            let safe_patterns = pack
                .safe_patterns
                .iter()
                .map(|pattern| {
                    crate::output::PackTreePattern::safe(pattern.name, pattern.regex.as_str())
                })
                .collect();
            let destructive_patterns = pack
                .destructive_patterns
                .iter()
                .map(|pattern| {
                    crate::output::PackTreePattern::destructive(
                        pattern.name.unwrap_or("unnamed"),
                        pattern.regex.as_str(),
                        pattern.severity.label(),
                    )
                })
                .collect();

            item.with_patterns(safe_patterns, destructive_patterns)
        })
        .collect();

    let options = crate::output::PackTreeOptions::new(verbose)
        .expand(expand)
        .max_patterns(max_patterns);

    crate::output::pack_list_tree_with_options(&tree_items, options)
        .with_theme(&crate::output::auto_theme())
        .render();
}

fn markdown_single_line_for_cli(text: &str) -> String {
    crate::highlight::format_markdown_explanation(
        text,
        false,
        usize::from(crate::output::terminal_width()).max(40),
    )
    .split_whitespace()
    .collect::<Vec<_>>()
    .join(" ")
}

fn print_markdown_field(label: &str, text: &str, indent: &str, use_color: bool) {
    let prefix_width = indent.chars().count() + label.chars().count() + 2;
    let width = usize::from(crate::output::terminal_width())
        .saturating_sub(prefix_width)
        .max(20);
    let rendered = crate::highlight::format_markdown_explanation(text, use_color, width);
    let mut lines = rendered.lines();

    if let Some(first) = lines.next() {
        println!("{indent}{label}: {first}");
        for line in lines {
            println!("{indent}  {line}");
        }
    } else {
        println!("{indent}{label}:");
    }
}

/// Show detailed information about a pack
fn pack_info(
    pack_id: &str,
    show_patterns: bool,
    json_output: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    let pack = REGISTRY
        .get(pack_id)
        .ok_or_else(|| format!("Pack not found: {pack_id}"))?;

    if json_output {
        #[derive(serde::Serialize)]
        struct PackInfoJson {
            id: String,
            name: String,
            description: String,
            keywords: Vec<String>,
            safe_pattern_count: usize,
            destructive_pattern_count: usize,
            #[serde(skip_serializing_if = "Option::is_none")]
            safe_patterns: Option<Vec<SafePatternJson>>,
            #[serde(skip_serializing_if = "Option::is_none")]
            destructive_patterns: Option<Vec<DestructivePatternJson>>,
        }
        #[derive(serde::Serialize)]
        struct SafePatternJson {
            name: String,
            regex: String,
        }
        #[derive(serde::Serialize)]
        struct DestructivePatternJson {
            name: String,
            regex: String,
            severity: String,
            reason: String,
            #[serde(skip_serializing_if = "Option::is_none")]
            explanation: Option<String>,
            #[serde(skip_serializing_if = "Vec::is_empty")]
            suggestions: Vec<SuggestionJson>,
        }
        #[derive(serde::Serialize)]
        struct SuggestionJson {
            command: String,
            description: String,
        }

        let safe_patterns = if show_patterns {
            Some(
                pack.safe_patterns
                    .iter()
                    .map(|p| SafePatternJson {
                        name: p.name.to_string(),
                        regex: p.regex.as_str().to_string(),
                    })
                    .collect(),
            )
        } else {
            None
        };

        let destructive_patterns = if show_patterns {
            Some(
                pack.destructive_patterns
                    .iter()
                    .map(|p| DestructivePatternJson {
                        name: p.name.unwrap_or("unnamed").to_string(),
                        regex: p.regex.as_str().to_string(),
                        severity: p.severity.label().to_string(),
                        reason: p.reason.to_string(),
                        explanation: p.explanation.map(String::from),
                        suggestions: p
                            .suggestions
                            .iter()
                            .map(|s| SuggestionJson {
                                command: s.command.to_string(),
                                description: s.description.to_string(),
                            })
                            .collect(),
                    })
                    .collect(),
            )
        } else {
            None
        };

        let info = PackInfoJson {
            id: pack.id.clone(),
            name: pack.name.to_string(),
            description: pack.description.to_string(),
            keywords: pack.keywords.iter().map(|k| (*k).to_string()).collect(),
            safe_pattern_count: pack.safe_patterns.len(),
            destructive_pattern_count: pack.destructive_patterns.len(),
            safe_patterns,
            destructive_patterns,
        };

        println!("{}", serde_json::to_string_pretty(&info)?);
        return Ok(());
    }

    println!("Pack: {}", pack.name);
    println!("ID: {}", pack.id);
    let use_color = crate::output::auto_theme().colors_enabled;
    print_markdown_field("Description", pack.description, "", use_color);
    println!("Keywords: {}", pack.keywords.join(", "));
    println!();
    println!("Patterns:");
    println!("  Safe patterns: {}", pack.safe_patterns.len());
    println!(
        "  Destructive patterns: {}",
        pack.destructive_patterns.len()
    );

    if show_patterns {
        println!();
        println!("Safe patterns:");
        for pattern in &pack.safe_patterns {
            let regex = crate::highlight::format_regex_pattern(pattern.regex.as_str(), use_color);
            println!("  - {} : {}", pattern.name, regex);
        }

        println!();
        println!("Destructive patterns:");
        for pattern in &pack.destructive_patterns {
            let name = pattern.name.unwrap_or("unnamed");
            let severity_label = pattern.severity.label().to_uppercase();
            let regex = crate::highlight::format_regex_pattern(pattern.regex.as_str(), use_color);
            println!("  - {name} [{severity_label}] : {regex}");
            println!("    Reason: {}", pattern.reason);
            if let Some(explanation) = pattern.explanation {
                print_markdown_field("Explanation", explanation, "    ", use_color);
            }
            for suggestion in pattern.suggestions {
                println!(
                    "    Suggestion: {} - {}",
                    suggestion.command, suggestion.description
                );
            }
        }
    }

    Ok(())
}

// ============================================================================
// Pack Commands (orca pack info/validate)
// ============================================================================

/// Handle all `orca pack` subcommands
fn handle_pack_command(
    _config: &Config,
    action: PackAction,
) -> Result<(), Box<dyn std::error::Error>> {
    match action {
        PackAction::Info {
            pack_id,
            no_patterns,
            json,
        } => {
            pack_info(&pack_id, !no_patterns, json)?;
        }
        PackAction::Validate {
            file_path,
            strict,
            format,
        } => {
            let _ = pack_validate(&file_path, strict, format)?;
        }
    }
    Ok(())
}

/// Validate an external pack YAML file
#[allow(clippy::too_many_lines)]
fn pack_validate(
    file_path: &str,
    strict: bool,
    format: PackValidateFormat,
) -> Result<bool, Box<dyn std::error::Error>> {
    use crate::packs::external::{
        CURRENT_SCHEMA_VERSION, ExternalPack, RegexEngineType, analyze_pack_engines,
        check_builtin_collision, summarize_pack_engines,
    };
    use std::path::Path;

    let path = Path::new(file_path);

    let mut result = PackValidationOutput {
        valid: true,
        file: file_path.to_string(),
        pack_id: None,
        pack_name: None,
        pack_version: None,
        errors: Vec::new(),
        warnings: Vec::new(),
        suggestions: Vec::new(),
        patterns: None,
        engine_summary: None,
    };

    // Step 1: Check if file exists
    if !path.exists() {
        result.valid = false;
        result.errors.push(PackValidationIssue {
            code: "E001".to_string(),
            message: format!("File not found: {file_path}"),
            suggestion: None,
        });
        return output_pack_validation(&result, format, strict);
    }

    // Step 2: Read file content
    let content = match std::fs::read_to_string(path) {
        Ok(c) => c,
        Err(e) => {
            result.valid = false;
            result.errors.push(PackValidationIssue {
                code: "E002".to_string(),
                message: format!("Failed to read file: {e}"),
                suggestion: None,
            });
            return output_pack_validation(&result, format, strict);
        }
    };

    // Step 3: Parse YAML
    let pack: ExternalPack = match serde_yaml::from_str(&content) {
        Ok(p) => p,
        Err(e) => {
            result.valid = false;
            result.errors.push(PackValidationIssue {
                code: "E003".to_string(),
                message: format!("YAML parse error: {e}"),
                suggestion: Some("Check YAML syntax (indentation, colons, quotes)".to_string()),
            });
            return output_pack_validation(&result, format, strict);
        }
    };

    // Store basic pack info for output
    result.pack_id = Some(pack.id.clone());
    result.pack_name = Some(pack.name.clone());
    result.pack_version = Some(pack.version.clone());

    // Step 4: Validate schema version
    if pack.schema_version > CURRENT_SCHEMA_VERSION {
        result.valid = false;
        result.errors.push(PackValidationIssue {
            code: "E004".to_string(),
            message: format!(
                "Schema version {} is not supported (max: {})",
                pack.schema_version, CURRENT_SCHEMA_VERSION
            ),
            suggestion: Some(format!(
                "Use schema_version: {CURRENT_SCHEMA_VERSION} or lower"
            )),
        });
    }

    // Step 5: Validate ID format
    let id_regex = regex::Regex::new(r"^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$").unwrap();
    if !id_regex.is_match(&pack.id) {
        result.valid = false;
        result.errors.push(PackValidationIssue {
            code: "E005".to_string(),
            message: format!(
                "Invalid pack ID '{}': must match pattern namespace.name (e.g., 'mycompany.deploy')",
                pack.id
            ),
            suggestion: Some("Use lowercase letters, numbers, underscores. Format: namespace.name".to_string()),
        });
    }

    // Step 6: Validate version format (semver)
    let version_regex = regex::Regex::new(r"^\d+\.\d+\.\d+$").unwrap();
    if !version_regex.is_match(&pack.version) {
        result.valid = false;
        result.errors.push(PackValidationIssue {
            code: "E006".to_string(),
            message: format!(
                "Invalid version '{}': must be semantic version (e.g., '1.0.0')",
                pack.version
            ),
            suggestion: Some("Use MAJOR.MINOR.PATCH format (e.g., 1.0.0, 2.1.3)".to_string()),
        });
    }

    // Step 7: Check for empty pack
    if pack.destructive_patterns.is_empty() && pack.safe_patterns.is_empty() {
        result.valid = false;
        result.errors.push(PackValidationIssue {
            code: "E007".to_string(),
            message: "Pack has no patterns defined".to_string(),
            suggestion: Some("Add at least one destructive_pattern or safe_pattern".to_string()),
        });
    }

    // Step 8: Check for duplicate pattern names
    let mut seen_names = std::collections::HashSet::new();
    for pattern in &pack.destructive_patterns {
        if !seen_names.insert(&pattern.name) {
            result.valid = false;
            result.errors.push(PackValidationIssue {
                code: "E008".to_string(),
                message: format!("Duplicate pattern name: {}", pattern.name),
                suggestion: Some("Pattern names must be unique within a pack".to_string()),
            });
        }
    }
    for pattern in &pack.safe_patterns {
        if !seen_names.insert(&pattern.name) {
            result.valid = false;
            result.errors.push(PackValidationIssue {
                code: "E008".to_string(),
                message: format!("Duplicate pattern name: {}", pattern.name),
                suggestion: Some("Pattern names must be unique within a pack".to_string()),
            });
        }
    }

    // Step 9: Validate regex patterns
    for pattern in &pack.destructive_patterns {
        if let Err(e) = crate::packs::regex_engine::CompiledRegex::new(&pattern.pattern) {
            result.valid = false;
            result.errors.push(PackValidationIssue {
                code: "E009".to_string(),
                message: format!("Invalid regex in pattern '{}': {}", pattern.name, e),
                suggestion: Some("Check regex syntax".to_string()),
            });
        }
    }
    for pattern in &pack.safe_patterns {
        if let Err(e) = crate::packs::regex_engine::CompiledRegex::new(&pattern.pattern) {
            result.valid = false;
            result.errors.push(PackValidationIssue {
                code: "E009".to_string(),
                message: format!("Invalid regex in pattern '{}': {}", pattern.name, e),
                suggestion: Some("Check regex syntax".to_string()),
            });
        }
    }

    // Step 10: Check for collision with built-in packs
    if let Some(builtin_name) = check_builtin_collision(&pack.id) {
        result.valid = false;
        result.errors.push(PackValidationIssue {
            code: "E010".to_string(),
            message: format!(
                "Pack ID '{}' collides with built-in pack '{}'",
                pack.id, builtin_name
            ),
            suggestion: Some(
                "Use a different namespace (e.g., 'mycompany.git' instead of 'core.git')"
                    .to_string(),
            ),
        });
    }

    // === Warnings (non-fatal) ===

    // Check for broad patterns
    for pattern in &pack.destructive_patterns {
        if pattern.pattern.contains(".*") && !pattern.pattern.starts_with('^') {
            result.warnings.push(PackValidationIssue {
                code: "W001".to_string(),
                message: format!(
                    "Pattern '{}' contains '.*' without anchor - may be too broad",
                    pattern.name
                ),
                suggestion: Some("Consider anchoring with ^ at the start".to_string()),
            });
        }
    }

    // Check for missing descriptions
    for pattern in &pack.destructive_patterns {
        if pattern.description.is_none() {
            result.warnings.push(PackValidationIssue {
                code: "W002".to_string(),
                message: format!("Pattern '{}' has no description", pattern.name),
                suggestion: Some(
                    "Add a description to help users understand why this blocks".to_string(),
                ),
            });
        }
    }

    // Check for missing explanations on high/critical patterns
    for pattern in &pack.destructive_patterns {
        use crate::packs::external::ExternalSeverity;
        if matches!(
            pattern.severity,
            ExternalSeverity::High | ExternalSeverity::Critical
        ) && pattern.explanation.is_none()
        {
            result.warnings.push(PackValidationIssue {
                code: "W003".to_string(),
                message: format!(
                    "High/critical pattern '{}' has no explanation",
                    pattern.name
                ),
                suggestion: Some(
                    "Add an explanation for verbose output to help users understand the risk"
                        .to_string(),
                ),
            });
        }
    }

    // Check for keywords not used in patterns
    for keyword in &pack.keywords {
        let keyword_lower = keyword.to_lowercase();
        let found_in_pattern = pack
            .destructive_patterns
            .iter()
            .any(|p| p.pattern.to_lowercase().contains(&keyword_lower))
            || pack
                .safe_patterns
                .iter()
                .any(|p| p.pattern.to_lowercase().contains(&keyword_lower));
        if !found_in_pattern {
            result.warnings.push(PackValidationIssue {
                code: "W004".to_string(),
                message: format!("Keyword '{keyword}' not found in any pattern"),
                suggestion: Some(
                    "Keywords should match substrings in patterns for efficient filtering"
                        .to_string(),
                ),
            });
        }
    }

    // === Suggestions (informational) ===

    // Suggest adding keywords if none defined
    if pack.keywords.is_empty()
        && (!pack.destructive_patterns.is_empty() || !pack.safe_patterns.is_empty())
    {
        result.suggestions.push(PackValidationIssue {
            code: "S001".to_string(),
            message: "No keywords defined".to_string(),
            suggestion: Some(
                "Adding keywords improves performance by enabling quick-reject filtering"
                    .to_string(),
            ),
        });
    }

    // Add pattern and engine summary
    result.patterns = Some(PackPatternSummary {
        destructive: pack.destructive_patterns.len(),
        safe: pack.safe_patterns.len(),
    });

    let engine_summary = summarize_pack_engines(&pack);
    result.engine_summary = Some(PackEngineSummary {
        linear: engine_summary.linear_count,
        backtracking: engine_summary.backtracking_count,
        linear_percentage: engine_summary.linear_percentage(),
    });

    // Suggest optimizing if too many backtracking patterns
    if engine_summary.backtracking_count > 0 && engine_summary.linear_percentage() < 80.0 {
        let engine_infos = analyze_pack_engines(&pack);
        let backtrack_names: Vec<_> = engine_infos
            .iter()
            .filter(|e| e.engine == RegexEngineType::Backtracking)
            .map(|e| e.name.as_str())
            .collect();
        result.suggestions.push(PackValidationIssue {
            code: "S002".to_string(),
            message: format!(
                "{} of {} patterns use backtracking engine",
                engine_summary.backtracking_count,
                engine_summary.total()
            ),
            suggestion: Some(format!(
                "Patterns using backtracking: {}. Consider simplifying to avoid lookahead/lookbehind if possible.",
                backtrack_names.join(", ")
            )),
        });
    }

    output_pack_validation(&result, format, strict)
}

/// Output validation result in the specified format
fn output_pack_validation(
    result: &PackValidationOutput,
    format: PackValidateFormat,
    strict: bool,
) -> Result<bool, Box<dyn std::error::Error>> {
    use colored::Colorize;

    let has_warnings = !result.warnings.is_empty();
    let exit_error = !result.valid || (strict && has_warnings);

    match format {
        PackValidateFormat::Json => {
            println!("{}", serde_json::to_string_pretty(result)?);
        }
        PackValidateFormat::Pretty => {
            println!("{}", "Pack Validation Report".bold().cyan());
            println!();
            println!("File: {}", result.file);

            if let (Some(id), Some(name), Some(version)) =
                (&result.pack_id, &result.pack_name, &result.pack_version)
            {
                println!();
                println!("{} Pack ID: {}", "✓".green(), id);
                println!("{} Name: {}", "✓".green(), name);
                println!("{} Version: {}", "✓".green(), version);
            }

            if let Some(patterns) = &result.patterns {
                println!();
                println!("{}", "Patterns:".bold());
                println!(
                    "  {} destructive patterns",
                    patterns.destructive.to_string().cyan()
                );
                println!("  {} safe patterns", patterns.safe.to_string().cyan());
            }

            if let Some(engines) = &result.engine_summary {
                println!();
                println!("{}", "Engine Analysis:".bold());
                println!(
                    "  {} linear (O(n)), {} backtracking ({:.0}% linear)",
                    engines.linear.to_string().green(),
                    engines.backtracking.to_string().yellow(),
                    engines.linear_percentage
                );
            }

            if !result.errors.is_empty() {
                println!();
                println!("{}", "Errors:".bold().red());
                for err in &result.errors {
                    println!("  {} [{}] {}", "✗".red(), err.code, err.message);
                    if let Some(suggestion) = &err.suggestion {
                        println!("    {}", format!("→ {suggestion}").dimmed());
                    }
                }
            }

            if !result.warnings.is_empty() {
                println!();
                println!("{}", "Warnings:".bold().yellow());
                for warn in &result.warnings {
                    println!("  {} [{}] {}", "⚠".yellow(), warn.code, warn.message);
                    if let Some(suggestion) = &warn.suggestion {
                        println!("    {}", format!("→ {suggestion}").dimmed());
                    }
                }
            }

            if !result.suggestions.is_empty() {
                println!();
                println!("{}", "Suggestions:".bold().blue());
                for sug in &result.suggestions {
                    println!("  {} [{}] {}", "ℹ".blue(), sug.code, sug.message);
                    if let Some(suggestion) = &sug.suggestion {
                        println!("    {}", format!("→ {suggestion}").dimmed());
                    }
                }
            }

            println!();
            if result.valid && !has_warnings {
                println!("{}", "✓ Pack is valid and ready to use.".bold().green());
                if let Some(id) = &result.pack_id {
                    println!();
                    println!("Add to your config:");
                    println!(
                        "  {}",
                        format!("[packs]\ncustom_paths = [\"path/to/{id}.yaml\"]").dimmed()
                    );
                }
            } else if result.valid {
                println!("{}", "✓ Pack is valid (with warnings).".bold().yellow());
            } else {
                println!("{}", "✗ Pack validation failed.".bold().red());
            }
        }
    }

    Ok(exit_error)
}

// Type alias for validation output to avoid repeating the struct definition
#[derive(serde::Serialize)]
struct PackValidationOutput {
    valid: bool,
    file: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pack_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pack_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pack_version: Option<String>,
    errors: Vec<PackValidationIssue>,
    warnings: Vec<PackValidationIssue>,
    suggestions: Vec<PackValidationIssue>,
    #[serde(skip_serializing_if = "Option::is_none")]
    patterns: Option<PackPatternSummary>,
    #[serde(skip_serializing_if = "Option::is_none")]
    engine_summary: Option<PackEngineSummary>,
}

#[derive(serde::Serialize)]
struct PackValidationIssue {
    code: String,
    message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    suggestion: Option<String>,
}

#[derive(serde::Serialize)]
struct PackPatternSummary {
    destructive: usize,
    safe: usize,
}

#[derive(serde::Serialize)]
struct PackEngineSummary {
    linear: usize,
    backtracking: usize,
    linear_percentage: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum InteractiveDecision {
    Block,
    AllowOnce,
    AddToAllowlist,
    ShowDetails,
}

fn should_prompt_interactively(
    format: TestFormat,
    verbosity: Verbosity,
    mode: DecisionMode,
    severity: Option<PackSeverity>,
    interactive_config: &InteractiveConfig,
) -> bool {
    let non_interactive_env =
        std::env::var("ORCA_NON_INTERACTIVE").is_ok() || std::env::var("CI").is_ok();
    let interactive_available = check_interactive_available(interactive_config).is_ok();
    let stdin_is_tty = std::io::stdin().is_terminal();
    let stdout_is_tty = std::io::stdout().is_terminal();

    should_prompt_interactively_with_context(
        format,
        verbosity,
        mode,
        severity,
        non_interactive_env,
        interactive_available,
        stdin_is_tty,
        stdout_is_tty,
    )
}

fn should_prompt_interactively_with_context(
    format: TestFormat,
    verbosity: Verbosity,
    mode: DecisionMode,
    severity: Option<PackSeverity>,
    non_interactive_env: bool,
    interactive_available: bool,
    stdin_is_tty: bool,
    stdout_is_tty: bool,
) -> bool {
    if format.is_structured() || verbosity.quiet {
        return false;
    }

    if mode != DecisionMode::Deny {
        return false;
    }

    if !matches!(severity, Some(PackSeverity::Medium | PackSeverity::Low)) {
        return false;
    }

    if non_interactive_env {
        return false;
    }

    if !interactive_available {
        return false;
    }

    stdin_is_tty && stdout_is_tty
}

fn prompt_for_block_action() -> InteractiveDecision {
    let options = vec![
        "Block this command (recommended)",
        "Allow once (this time only)",
        "Add to allowlist (remember for future)",
        "Show more details",
    ];

    let selection = Select::new("What would you like to do?", options)
        .with_help_message("Use arrow keys to select, Enter to confirm")
        .prompt();

    match selection {
        Ok("Allow once (this time only)") => InteractiveDecision::AllowOnce,
        Ok("Add to allowlist (remember for future)") => InteractiveDecision::AddToAllowlist,
        Ok("Show more details") => InteractiveDecision::ShowDetails,
        _ => InteractiveDecision::Block,
    }
}

/// Security-aware interactive prompt with verification code.
///
/// This prompt requires the user to type a random verification code before
/// allowing bypass of a blocked command. This prevents automated tools
/// (like AI agents) from bypassing security controls.
///
/// Returns the allowlist scope if verification succeeds, or None if the
/// user cancels, times out, or enters an invalid code.
fn prompt_secure_bypass(
    command: &str,
    reason: &str,
    rule_id: Option<&str>,
    config: &InteractiveConfig,
) -> Option<AllowlistScope> {
    use colored::Colorize;

    // Check if interactive mode is available
    if let Err(reason) = check_interactive_available(config) {
        print_not_available_message(&reason);
        return None;
    }

    // Run the security-aware prompt
    match run_interactive_prompt(command, reason, rule_id, config) {
        InteractiveResult::AllowlistRequested(scope) => Some(scope),
        InteractiveResult::InvalidCode => {
            eprintln!(
                "{}",
                "Invalid verification code. Command remains blocked.".red()
            );
            None
        }
        InteractiveResult::Timeout => {
            eprintln!("{}", "Timeout. Command remains blocked.".yellow());
            None
        }
        InteractiveResult::Cancelled => {
            eprintln!("{}", "Cancelled. Command remains blocked.".bright_black());
            None
        }
        InteractiveResult::NotAvailable(reason) => {
            print_not_available_message(&reason);
            None
        }
    }
}

/// Check if the security-aware prompt should be used instead of the simple prompt.
///
/// The security-aware prompt is used for:
/// - Critical severity blocks (always require verification)
/// - High severity blocks (require verification)
///
/// For medium/low severity blocks, the simpler inquire-based prompt is used
/// for better UX during testing.
fn should_use_secure_prompt(severity: Option<PackSeverity>) -> bool {
    matches!(severity, Some(PackSeverity::Critical | PackSeverity::High))
}

fn prompt_allowlist_reason(default_reason: &str) -> String {
    Text::new("Reason for allowlisting?")
        .with_initial_value(default_reason)
        .prompt()
        .unwrap_or_else(|_| default_reason.to_string())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum InteractiveAllowlistTarget {
    ExactCommand,
    MatchedRule,
}

#[derive(Debug, Clone)]
struct InteractiveAllowlistApplication {
    summary: String,
    pattern_added: String,
    option_type: InteractiveAllowlistOptionType,
    option_detail: Option<String>,
    config_file: std::path::PathBuf,
}

fn prompt_allowlist_target(rule_id: Option<&str>) -> InteractiveAllowlistTarget {
    let Some(rule_id) = rule_id else {
        return InteractiveAllowlistTarget::ExactCommand;
    };

    let exact = "Exact command only (recommended)".to_string();
    let rule = format!("Matched rule `{rule_id}` (broader)");
    let options = vec![exact.clone(), rule.clone()];

    match Select::new("Allowlist target:", options)
        .with_help_message(
            "Exact command is safer; rule-based allows all future matches of this rule",
        )
        .prompt()
    {
        Ok(choice) if choice == rule => InteractiveAllowlistTarget::MatchedRule,
        _ => InteractiveAllowlistTarget::ExactCommand,
    }
}

fn prompt_allowlist_path_scope() -> Vec<String> {
    let cwd = std::env::current_dir().unwrap_or_else(|_| std::path::PathBuf::from("."));
    let scope_path = cwd.canonicalize().unwrap_or(cwd);
    let scope_path_str = scope_path.to_string_lossy().into_owned();

    let scoped = format!("Current directory only ({scope_path_str})");
    let global = "All directories (global)".to_string();
    let options = vec![scoped.clone(), global];

    match Select::new("Path scope:", options)
        .with_help_message("Directory-scoped entries are safer")
        .prompt()
    {
        Ok(choice) if choice == scoped => vec![scope_path_str],
        _ => Vec::new(),
    }
}

fn prompt_allowlist_lifetime_choice() -> Option<std::time::Duration> {
    let permanent = "Permanent allowlist entry".to_string();
    let temporary = "Temporary allowlist entry (24 hours)".to_string();
    let options = vec![permanent.clone(), temporary.clone()];

    match Select::new("Lifetime:", options)
        .with_help_message("Temporary entries auto-expire and are safer")
        .prompt()
    {
        Ok(choice) if choice == temporary => Some(std::time::Duration::from_secs(24 * 3600)),
        _ => None,
    }
}

fn duration_to_expires_at(
    duration: std::time::Duration,
) -> Result<String, Box<dyn std::error::Error>> {
    let duration = chrono::Duration::from_std(duration)
        .map_err(|e| format!("Failed to convert duration: {e}"))?;
    let expires_at = Utc::now()
        .checked_add_signed(duration)
        .ok_or("Duration overflow while computing expiration timestamp")?;
    Ok(expires_at.to_rfc3339())
}

fn interactive_option_type(
    expires: Option<&str>,
    paths: &[String],
) -> InteractiveAllowlistOptionType {
    if expires.is_some() {
        InteractiveAllowlistOptionType::Temporary
    } else if paths.is_empty() {
        InteractiveAllowlistOptionType::Exact
    } else {
        InteractiveAllowlistOptionType::PathSpecific
    }
}

fn current_username() -> Option<String> {
    ["USER", "LOGNAME", "USERNAME"]
        .iter()
        .find_map(|key| std::env::var(key).ok())
        .and_then(|value| (!value.trim().is_empty()).then_some(value))
}

fn apply_interactive_allowlist_entry(
    command: &str,
    rule_id: Option<&str>,
    reason: &str,
    layer: crate::allowlist::AllowlistLayer,
    expires: Option<&str>,
) -> Result<InteractiveAllowlistApplication, Box<dyn std::error::Error>> {
    let target = prompt_allowlist_target(rule_id);
    let paths = prompt_allowlist_path_scope();
    let option_type = interactive_option_type(expires, &paths);
    let option_detail = Some(format!(
        "target={};scope={};layer={};expires={};paths={}",
        match target {
            InteractiveAllowlistTarget::ExactCommand => "exact_command",
            InteractiveAllowlistTarget::MatchedRule => "matched_rule",
        },
        if paths.is_empty() {
            "all_directories"
        } else {
            "current_directory_only"
        },
        layer.label(),
        expires.unwrap_or("none"),
        if paths.is_empty() {
            "*".to_string()
        } else {
            paths.join("|")
        }
    ));
    let config_file = allowlist_path_for_layer(layer);

    let scope_label = if paths.is_empty() {
        "all directories"
    } else {
        "current directory only"
    };

    match (target, rule_id) {
        (InteractiveAllowlistTarget::MatchedRule, Some(rule_id)) => {
            allowlist_add_rule_with_paths(rule_id, reason, layer, expires, &[], &paths)?;
            Ok(InteractiveAllowlistApplication {
                summary: format!("rule target, {scope_label}"),
                pattern_added: rule_id.to_string(),
                option_type,
                option_detail,
                config_file,
            })
        }
        _ => {
            allowlist_add_command_with_paths(command, reason, layer, expires, &paths)?;
            Ok(InteractiveAllowlistApplication {
                summary: format!("exact command target, {scope_label}"),
                pattern_added: command.to_string(),
                option_type,
                option_detail,
                config_file,
            })
        }
    }
}

fn log_interactive_allowlist_audit_event(
    config: &Config,
    command: &str,
    applied: &InteractiveAllowlistApplication,
) -> Result<(), Box<dyn std::error::Error>> {
    if !config.history.enabled {
        return Ok(());
    }

    let db_path = config.history.expanded_database_path();
    let db = HistoryDb::open(db_path)?;

    let cwd = std::env::current_dir()
        .ok()
        .and_then(|path| path.canonicalize().ok().or(Some(path)))
        .map(|path| path.to_string_lossy().into_owned());

    let entry = InteractiveAllowlistAuditEntry {
        timestamp: Utc::now(),
        command: command.to_string(),
        pattern_added: applied.pattern_added.clone(),
        option_type: applied.option_type,
        option_detail: applied.option_detail.clone(),
        config_file: applied.config_file.to_string_lossy().into_owned(),
        cwd,
        user: current_username(),
    };

    let _ = db.log_interactive_allowlist_audit(&entry)?;
    Ok(())
}

fn resolve_mode_for_cli(
    config: &Config,
    command: &str,
    result: &EvaluationResult,
) -> Option<DecisionMode> {
    let info = result.pattern_info.as_ref()?;
    let pack = info.pack_id.as_deref();
    let pattern = info.pattern_name.as_deref();

    let mut mode = match info.source {
        MatchSource::Pack | MatchSource::HeredocAst => {
            config.policy().resolve_mode(pack, pattern, info.severity)
        }
        MatchSource::ConfigOverride | MatchSource::LegacyPattern => DecisionMode::Deny,
    };

    if matches!(info.source, MatchSource::Pack | MatchSource::HeredocAst) {
        let sanitized = crate::context::sanitize_for_pattern_matching(command);
        let normalized_command = crate::normalize::normalize_command(command);
        let normalized_sanitized = crate::normalize::normalize_command(sanitized.as_ref());

        let mut confidence_command = command;
        let mut confidence_sanitized: Option<&str> = None;

        if normalized_command.len() == normalized_sanitized.len() {
            confidence_command = normalized_command.as_ref();
            if sanitized.as_ref() != command {
                confidence_sanitized = Some(normalized_sanitized.as_ref());
            }
        }

        let confidence_result = crate::apply_confidence_scoring(
            confidence_command,
            confidence_sanitized,
            result,
            mode,
            &config.confidence,
        );
        mode = confidence_result.mode;
    }

    Some(mode)
}

/// Test a command against the configured packs using the shared evaluator.
///
/// This ensures parity with hook mode by using the same evaluation logic:
/// 1. Config allow overrides
/// 2. Config block overrides
/// 3. Quick rejection (keyword filtering)
/// 4. Command normalization
/// 5. Pack pattern matching
#[allow(clippy::needless_pass_by_value)] // Value is consumed from CLI args
#[allow(clippy::too_many_arguments, clippy::too_many_lines)]
fn test_command(
    config: &Config,
    command: &str,
    extra_packs: Option<Vec<String>>,
    format: TestFormat,
    verbosity: Verbosity,
    no_color: bool,
    robot_mode: bool,
    heredoc_scan: bool,
    no_heredoc_scan: bool,
    heredoc_timeout_ms: Option<u64>,
    heredoc_languages: Option<Vec<String>>,
    force: bool,
) -> bool {
    use std::time::Instant;

    if verbosity.quiet {
        return false; // Not blocked in quiet mode
    }

    if verbosity.is_trace() && format == TestFormat::Pretty {
        handle_explain(config, command, ExplainFormat::Pretty, extra_packs);
        return false; // Explain mode doesn't track blocked status
    }

    // Build effective config with extra packs if specified
    let mut effective_config = extra_packs.map_or_else(
        || config.clone(),
        |packs| {
            let mut modified = config.clone();
            modified.packs.enabled.extend(packs);
            modified
        },
    );

    // CLI overrides for heredoc scanning (higher priority than env/config file).
    if heredoc_scan {
        effective_config.heredoc.enabled = Some(true);
    }
    if no_heredoc_scan {
        effective_config.heredoc.enabled = Some(false);
    }
    if let Some(timeout_ms) = heredoc_timeout_ms {
        effective_config.heredoc.timeout_ms = Some(timeout_ms);
    }
    if let Some(langs) = heredoc_languages {
        effective_config.heredoc.languages = Some(langs);
    }

    // Get enabled packs and collect keywords for quick rejection
    let mut enabled_packs = effective_config.enabled_pack_ids();
    let mut enabled_keywords = REGISTRY.collect_enabled_keywords(&enabled_packs);
    let heredoc_settings = effective_config.heredoc_settings();

    // Compile overrides once (not per-command)
    let compiled_overrides = effective_config.overrides.compile();

    // Load allowlists (project/user/system) for parity with hook mode.
    // This is a small file read and only affects decisions when a rule matches.
    let allowlists = load_default_allowlists();

    // Load external packs from custom_paths (glob + tilde expansion).
    let external_paths = effective_config.packs.expand_custom_paths();
    let external_store = load_external_packs(&external_paths);

    // Auto-enable external packs and merge their keywords.
    for id in external_store.pack_ids() {
        enabled_packs.insert(id.clone());
    }
    enabled_keywords.extend(external_store.keywords().iter().copied());

    // Build ordered pack list AFTER external packs are loaded so they're included.
    let mut ordered_packs = REGISTRY.expand_enabled_ordered(&enabled_packs);
    for id in external_store.pack_ids() {
        if !ordered_packs.contains(id) {
            ordered_packs.push(id.clone());
        }
    }
    // Disable keyword index when external packs are present (not covered by index).
    let keyword_index = if external_store.pack_ids().next().is_some() {
        None
    } else {
        REGISTRY.build_enabled_keyword_index(&ordered_packs)
    };

    // Detect the current AI coding agent for agent-specific profiles
    let detection = detect_agent_with_details();
    let trust_level = effective_config.trust_level_for_agent(&detection.agent);
    let agent_info = AgentInfo {
        detected: detection.agent.config_key().to_string(),
        trust_level: format!("{:?}", trust_level).to_lowercase(),
        detection_method: match detection.method {
            DetectionMethod::Environment => "environment_variable".to_string(),
            DetectionMethod::Explicit => "explicit".to_string(),
            DetectionMethod::Process => "process".to_string(),
            DetectionMethod::None => "none".to_string(),
        },
    };

    // Use shared evaluator for consistent behavior with hook mode
    let start = Instant::now();
    let mut result = evaluate_command_with_pack_order_deadline_at_path(
        command,
        &enabled_keywords,
        &ordered_packs,
        keyword_index.as_ref(),
        &compiled_overrides,
        &allowlists,
        &heredoc_settings,
        None, // allow_once_audit
        None, // project_path
        None, // external_store
        None, // deadline
    );

    // NOTE: External packs from custom_paths are now checked in evaluate_command()
    // alongside built-in packs, so no separate fallback check is needed here.

    // Apply graduated response system
    result.record_and_graduate(command, &effective_config.response);

    // If --force and we have a SoftBlock, bypass it
    if force {
        if let Some(crate::evaluator::GraduatedResponse::SoftBlock { .. }) =
            &result.graduated_response
        {
            result.decision = EvaluationDecision::Allow;
            result.bypass_method = Some(crate::evaluator::BypassMethod::Force);
        }
    }

    let elapsed = start.elapsed();

    // Handle structured output (JSON/TOON)
    if format.is_structured() {
        let output = match result.decision {
            EvaluationDecision::Allow => {
                let allowlist =
                    result
                        .allowlist_override
                        .as_ref()
                        .map(|info| AllowlistOverrideInfo {
                            layer: info.layer.label().to_string(),
                            reason: info.reason.clone(),
                        });
                TestOutput {
                    schema_version: TEST_OUTPUT_SCHEMA_VERSION,
                    orca_version: env!("CARGO_PKG_VERSION").to_string(),
                    robot_mode,
                    command: command.to_string(),
                    decision: "allow".to_string(),
                    rule_id: None,
                    pack_id: None,
                    pattern_name: None,
                    reason: None,
                    explanation: None,
                    source: None,
                    matched_span: None,
                    severity: None,
                    allowlist,
                    agent: Some(agent_info.clone()),
                }
            }
            EvaluationDecision::Deny => {
                let (
                    pack_id,
                    pattern_name,
                    reason,
                    explanation,
                    source_str,
                    matched_span,
                    rule_id,
                    severity,
                ) = result.pattern_info.as_ref().map_or(
                    (None, None, None, None, None, None, None, None),
                    |info| {
                        let source_str = match info.source {
                            MatchSource::ConfigOverride => "config_override",
                            MatchSource::LegacyPattern => "legacy_pattern",
                            MatchSource::Pack => "pack",
                            MatchSource::HeredocAst => "heredoc_ast",
                        };
                        let rule_id = info
                            .pack_id
                            .as_ref()
                            .and_then(|p| info.pattern_name.as_ref().map(|n| format!("{p}:{n}")));
                        let severity_str = info.severity.map(|s| match s {
                            PackSeverity::Critical => "critical",
                            PackSeverity::High => "high",
                            PackSeverity::Medium => "medium",
                            PackSeverity::Low => "low",
                        });
                        (
                            info.pack_id.clone(),
                            info.pattern_name.clone(),
                            Some(info.reason.clone()),
                            info.explanation.clone(),
                            Some(source_str.to_string()),
                            info.matched_span.as_ref().map(|s| (s.start, s.end)),
                            rule_id,
                            severity_str.map(std::string::ToString::to_string),
                        )
                    },
                );
                TestOutput {
                    schema_version: TEST_OUTPUT_SCHEMA_VERSION,
                    orca_version: env!("CARGO_PKG_VERSION").to_string(),
                    robot_mode,
                    command: command.to_string(),
                    decision: "deny".to_string(),
                    rule_id,
                    pack_id,
                    pattern_name,
                    reason,
                    explanation,
                    source: source_str,
                    matched_span,
                    severity,
                    allowlist: None,
                    agent: Some(agent_info.clone()),
                }
            }
        };
        match format {
            TestFormat::Json => {
                println!("{}", serde_json::to_string_pretty(&output).unwrap());
            }
            TestFormat::Toon => {
                let json = serde_json::to_value(&output).expect("TestOutput should serialize");
                let encoded = toon::encode(json, None);
                println!("{encoded}");
            }
            TestFormat::Pretty => unreachable!("handled above"),
        }
        return result.decision == EvaluationDecision::Deny;
    }

    // Pretty output (default)
    // Use color based on terminal detection and --no-color flag
    let use_color = !no_color && should_use_color();

    // Use default window width for highlighting
    let term_width = DEFAULT_WINDOW_WIDTH;

    // Build highlight label if we have span info
    let highlight_info = result.pattern_info.as_ref().and_then(|info| {
        info.matched_span.as_ref().map(|span| {
            let label = info
                .pack_id
                .as_ref()
                .and_then(|pack| {
                    info.pattern_name
                        .as_ref()
                        .map(|pattern| format!("Matched: {pack}:{pattern}"))
                })
                .or_else(|| info.pack_id.as_ref().map(|p| format!("Matched: {p}")))
                .unwrap_or_else(|| "Matched destructive pattern".to_string());
            (span, label)
        })
    });

    // Print command with highlighting if available
    if let Some((span, label)) = &highlight_info {
        let highlight_span = HighlightSpan::with_label(span.start, span.end, label.clone());
        let highlighted =
            format_highlighted_command(command, &highlight_span, use_color, term_width);
        println!("Command: {}", highlighted.command_line);
        println!("         {}", highlighted.caret_line);
        if let Some(ref label_line) = highlighted.label_line {
            println!("         {label_line}");
        }
    } else {
        println!("Command: {command}");
    }
    println!();

    let resolved_mode = resolve_mode_for_cli(&effective_config, command, &result);

    match result.decision {
        EvaluationDecision::Allow => {
            if let Some(override_info) = &result.allowlist_override {
                println!(
                    "Result: ALLOWED (allowlisted by {})",
                    override_info.layer.label()
                );
                println!("Allowlist reason: {}", override_info.reason);
            } else {
                println!("Result: ALLOWED");
            }
        }
        EvaluationDecision::Deny => {
            let mut result_line = "Result: BLOCKED".to_string();

            if let Some(ref info) = result.pattern_info {
                if let Some(ref pack_id) = info.pack_id {
                    println!("Pack: {pack_id}");
                }
                if let Some(ref pattern_name) = info.pattern_name {
                    println!("Pattern: {pattern_name}");
                }
                println!("Reason: {}", info.reason);
                if let Some(ref explanation) = info.explanation {
                    print_markdown_field("Explanation", explanation, "", use_color);
                }
                let source = match info.source {
                    MatchSource::ConfigOverride => "config override",
                    MatchSource::LegacyPattern => "legacy pattern",
                    MatchSource::Pack => "pack",
                    MatchSource::HeredocAst => "heredoc/inline script (AST)",
                };
                println!("Source: {source}");

                let rule_id = info
                    .pack_id
                    .as_ref()
                    .zip(info.pattern_name.as_ref())
                    .map(|(pack, pattern)| format!("{pack}:{pattern}"));
                let mode = resolved_mode.unwrap_or(DecisionMode::Deny);

                match mode {
                    DecisionMode::Warn => {
                        result_line = "Result: WARN (policy allows)".to_string();
                    }
                    DecisionMode::Log => {
                        result_line = "Result: LOG (policy allows)".to_string();
                    }
                    DecisionMode::Deny => {
                        // For critical/high severity, use security-aware prompt
                        // For medium/low severity, use simpler inquire-based prompt
                        if should_use_secure_prompt(info.severity) {
                            // Security-aware prompt with verification code
                            if let Some(scope) = prompt_secure_bypass(
                                command,
                                &info.reason,
                                rule_id.as_deref(),
                                &effective_config.interactive,
                            ) {
                                match scope {
                                    AllowlistScope::Once => {
                                        result_line =
                                            "Result: ALLOWED (once, not persisted)".to_string();
                                    }
                                    AllowlistScope::Session => {
                                        result_line = "Result: ALLOWED (session only)".to_string();
                                    }
                                    AllowlistScope::Temporary(duration) => {
                                        let layer = resolve_layer(false, false);
                                        let hours = duration.as_secs() / 3600;
                                        match duration_to_expires_at(duration) {
                                            Ok(expires) => {
                                                let reason = "Verified bypass via orca test (security prompt temporary)";
                                                match apply_interactive_allowlist_entry(
                                                    command,
                                                    rule_id.as_deref(),
                                                    reason,
                                                    layer,
                                                    Some(expires.as_str()),
                                                ) {
                                                    Ok(applied) => {
                                                        if let Err(err) =
                                                            log_interactive_allowlist_audit_event(
                                                                &effective_config,
                                                                command,
                                                                &applied,
                                                            )
                                                        {
                                                            eprintln!(
                                                                "Warning: failed to write interactive allowlist audit: {err}"
                                                            );
                                                        }
                                                        result_line = format!(
                                                            "Result: ALLOWED (temporary allowlisted in {} for {} hours; {})",
                                                            layer.label(),
                                                            hours,
                                                            applied.summary
                                                        );
                                                    }
                                                    Err(err) => {
                                                        eprintln!("Allowlist update failed: {err}");
                                                        result_line = "Result: BLOCKED".to_string();
                                                    }
                                                }
                                            }
                                            Err(err) => {
                                                eprintln!(
                                                    "Failed to compute temporary expiration: {err}"
                                                );
                                                result_line = "Result: BLOCKED".to_string();
                                            }
                                        }
                                    }
                                    AllowlistScope::Permanent => {
                                        let layer = resolve_layer(false, false);
                                        let reason =
                                            "Verified bypass via orca test (security prompt)";
                                        match apply_interactive_allowlist_entry(
                                            command,
                                            rule_id.as_deref(),
                                            reason,
                                            layer,
                                            None,
                                        ) {
                                            Ok(applied) => {
                                                if let Err(err) =
                                                    log_interactive_allowlist_audit_event(
                                                        &effective_config,
                                                        command,
                                                        &applied,
                                                    )
                                                {
                                                    eprintln!(
                                                        "Warning: failed to write interactive allowlist audit: {err}"
                                                    );
                                                }
                                                result_line = format!(
                                                    "Result: ALLOWED (allowlisted in {}; {})",
                                                    layer.label(),
                                                    applied.summary
                                                );
                                            }
                                            Err(err) => {
                                                eprintln!("Allowlist update failed: {err}");
                                                result_line = "Result: BLOCKED".to_string();
                                            }
                                        }
                                    }
                                }
                            }
                            // If prompt_secure_bypass returns None, result_line stays at BLOCKED
                        } else if should_prompt_interactively(
                            format,
                            verbosity,
                            mode,
                            info.severity,
                            &effective_config.interactive,
                        ) {
                            // Simpler inquire-based prompt for medium/low severity
                            let action = loop {
                                let choice = prompt_for_block_action();
                                if choice == InteractiveDecision::ShowDetails {
                                    handle_explain(
                                        &effective_config,
                                        command,
                                        ExplainFormat::Pretty,
                                        None,
                                    );
                                    println!();
                                } else {
                                    break choice;
                                }
                            };

                            match action {
                                InteractiveDecision::AllowOnce => {
                                    result_line =
                                        "Result: ALLOWED (allow once, not persisted)".to_string();
                                }
                                InteractiveDecision::AddToAllowlist => {
                                    let layer = resolve_layer(false, false);
                                    let reason = prompt_allowlist_reason(
                                        "Interactive approval via orca test",
                                    );
                                    let lifetime = prompt_allowlist_lifetime_choice();
                                    let expires = match lifetime {
                                        Some(duration) => match duration_to_expires_at(duration) {
                                            Ok(expires) => Some(expires),
                                            Err(err) => {
                                                eprintln!(
                                                    "Failed to compute temporary expiration: {err}"
                                                );
                                                result_line = "Result: BLOCKED".to_string();
                                                None
                                            }
                                        },
                                        None => None,
                                    };

                                    if result_line != "Result: BLOCKED" {
                                        match apply_interactive_allowlist_entry(
                                            command,
                                            rule_id.as_deref(),
                                            &reason,
                                            layer,
                                            expires.as_deref(),
                                        ) {
                                            Ok(applied) => {
                                                if let Err(err) =
                                                    log_interactive_allowlist_audit_event(
                                                        &effective_config,
                                                        command,
                                                        &applied,
                                                    )
                                                {
                                                    eprintln!(
                                                        "Warning: failed to write interactive allowlist audit: {err}"
                                                    );
                                                }
                                                if let Some(duration) = lifetime {
                                                    let hours = duration.as_secs() / 3600;
                                                    result_line = format!(
                                                        "Result: ALLOWED (temporary allowlisted in {} for {} hours; {})",
                                                        layer.label(),
                                                        hours,
                                                        applied.summary
                                                    );
                                                } else {
                                                    result_line = format!(
                                                        "Result: ALLOWED (allowlisted in {}; {})",
                                                        layer.label(),
                                                        applied.summary
                                                    );
                                                }
                                            }
                                            Err(err) => {
                                                eprintln!("Allowlist update failed: {err}");
                                                result_line = "Result: BLOCKED".to_string();
                                            }
                                        }
                                    }
                                }
                                InteractiveDecision::Block | InteractiveDecision::ShowDetails => {}
                            }
                        }
                    }
                }
            }

            println!("{result_line}");
        }
    }

    if verbosity.is_verbose() {
        println!("Elapsed: {:.2}ms", elapsed.as_secs_f64() * 1000.0);
        println!("Agent: {}", detection.agent);
        println!("Trust level: {}", agent_info.trust_level);
        if let Some(ref info) = result.pattern_info {
            if let Some(severity) = info.severity {
                println!("Severity: {}", severity.label());
            }
        }
    }

    if verbosity.is_debug() {
        // Agent detection details
        println!("Agent detection:");
        println!(
            "  Detected: {} ({})",
            detection.agent,
            detection.agent.config_key()
        );
        println!("  Method: {}", agent_info.detection_method);
        if let Some(ref matched) = detection.matched_value {
            println!("  Matched: {matched}");
        }
        println!("  Profile: agents.{}", detection.agent.config_key());
        println!("  Trust level: {}", agent_info.trust_level);

        if let Some(ref info) = result.pattern_info {
            if let Some(ref pack_id) = info.pack_id {
                if let Some(ref pattern_name) = info.pattern_name {
                    println!("Rule: {pack_id}:{pattern_name}");
                }
            }
            if let Some(ref span) = info.matched_span {
                println!("Match span: {}..{}", span.start, span.end);
            }
            if let Some(ref preview) = info.matched_text_preview {
                println!("Match preview: \"{preview}\"");
            }
        }
        let normalized = crate::normalize::normalize_command(command);
        if normalized.as_ref() != command {
            println!("Normalized: {normalized}");
        }
    }

    // Return true if the command was blocked (for exit code handling)
    result.decision == EvaluationDecision::Deny
}

/// Classify a command's risk level and return an exit code.
///
/// Returns:
/// - 0 for allow (safe or low risk)
/// - `EXIT_DENIED` (1) for block (high or critical)
/// - `EXIT_WARNING` (2) for warn (medium risk)
fn classify_command(config: &Config, command: &str, format: ClassifyFormat, no_color: bool) -> i32 {
    // Build effective config (no extra packs for classify — uses current config as-is)
    let effective_config = config.clone();

    // Get enabled packs and collect keywords for quick rejection
    let mut enabled_packs = effective_config.enabled_pack_ids();
    let mut enabled_keywords = REGISTRY.collect_enabled_keywords(&enabled_packs);
    let heredoc_settings = effective_config.heredoc_settings();

    // Compile overrides once
    let compiled_overrides = effective_config.overrides.compile();

    // Load allowlists (project/user/system)
    let allowlists = load_default_allowlists();

    // Load external packs from custom_paths
    let external_paths = effective_config.packs.expand_custom_paths();
    let external_store = load_external_packs(&external_paths);

    // Auto-enable external packs and merge their keywords
    for id in external_store.pack_ids() {
        enabled_packs.insert(id.clone());
    }
    enabled_keywords.extend(external_store.keywords().iter().copied());

    // Build ordered pack list
    let mut ordered_packs = REGISTRY.expand_enabled_ordered(&enabled_packs);
    for id in external_store.pack_ids() {
        if !ordered_packs.contains(id) {
            ordered_packs.push(id.clone());
        }
    }
    let keyword_index = if external_store.pack_ids().next().is_some() {
        None
    } else {
        REGISTRY.build_enabled_keyword_index(&ordered_packs)
    };

    // Evaluate the command
    let result = evaluate_command_with_pack_order_deadline_at_path(
        command,
        &enabled_keywords,
        &ordered_packs,
        keyword_index.as_ref(),
        &compiled_overrides,
        &allowlists,
        &heredoc_settings,
        None, // allow_once_audit
        None, // project_path
        None, // external_store
        None, // deadline
    );

    // Map EvaluationResult to classification
    let (decision, risk_level, risk_score, reasons, suggestions) = match result.decision {
        EvaluationDecision::Allow => {
            // Check if this was an allowlist override (still matched a pattern)
            if result.allowlist_override.is_some() {
                // Matched a dangerous pattern but allowlisted — still "allow" but note it
                ("allow".to_string(), "low".to_string(), 0.2, vec![], vec![])
            } else {
                ("allow".to_string(), "safe".to_string(), 0.0, vec![], vec![])
            }
        }
        EvaluationDecision::Deny => {
            let severity = result.pattern_info.as_ref().and_then(|info| info.severity);
            let effective_mode = result.effective_mode.unwrap_or(DecisionMode::Deny);

            // Build reasons from pattern info
            let reasons = result
                .pattern_info
                .as_ref()
                .map(|info| {
                    let rule_id = info
                        .pack_id
                        .as_ref()
                        .and_then(|p| info.pattern_name.as_ref().map(|n| format!("{p}:{n}")))
                        .unwrap_or_else(|| "unknown".to_string());
                    let severity_str = info.severity.map_or("high", |s| s.label()).to_string();
                    let explanation = info
                        .explanation
                        .clone()
                        .unwrap_or_else(|| info.reason.clone());
                    vec![ClassifyReason {
                        rule_id,
                        severity: severity_str,
                        explanation,
                    }]
                })
                .unwrap_or_default();

            // Collect suggestions from pattern info
            let suggestions = result
                .pattern_info
                .as_ref()
                .map(|info| {
                    info.suggestions
                        .iter()
                        .filter(|s| s.platform.matches_current())
                        .map(|s| {
                            if s.description.is_empty() {
                                s.command.to_string()
                            } else {
                                format!("{} ({})", s.command, s.description)
                            }
                        })
                        .collect::<Vec<_>>()
                })
                .unwrap_or_default();

            // Determine decision and risk based on severity and effective mode
            match effective_mode {
                DecisionMode::Log => {
                    // Log-only: treat as allow with low risk
                    let risk_score = match severity {
                        Some(PackSeverity::Low) => 0.2,
                        Some(PackSeverity::Medium) => 0.3,
                        _ => 0.2,
                    };
                    (
                        "allow".to_string(),
                        severity.map_or("low", |s| s.label()).to_string(),
                        risk_score,
                        reasons,
                        suggestions,
                    )
                }
                DecisionMode::Warn => {
                    let risk_score = match severity {
                        Some(PackSeverity::Medium) => 0.5,
                        Some(PackSeverity::Low) => 0.3,
                        _ => 0.5,
                    };
                    (
                        "warn".to_string(),
                        severity.map_or("medium", |s| s.label()).to_string(),
                        risk_score,
                        reasons,
                        suggestions,
                    )
                }
                DecisionMode::Deny => {
                    let (risk_level, risk_score) = match severity {
                        Some(PackSeverity::Critical) => ("critical", 1.0),
                        Some(PackSeverity::High) => ("high", 0.8),
                        Some(PackSeverity::Medium) => ("medium", 0.5),
                        Some(PackSeverity::Low) => ("low", 0.3),
                        None => ("high", 0.8), // Default to high if severity unknown
                    };
                    (
                        "block".to_string(),
                        risk_level.to_string(),
                        risk_score,
                        reasons,
                        suggestions,
                    )
                }
            }
        }
    };

    let output = ClassifyOutput {
        schema_version: CLASSIFY_OUTPUT_SCHEMA_VERSION,
        orca_version: env!("CARGO_PKG_VERSION").to_string(),
        command: command.to_string(),
        decision: decision.clone(),
        risk_level: risk_level.clone(),
        risk_score,
        reasons,
        suggestions,
    };

    match format {
        ClassifyFormat::Json => {
            println!("{}", serde_json::to_string_pretty(&output).unwrap());
        }
        ClassifyFormat::Text => {
            let use_color = !no_color && should_use_color();
            let decision_display = if use_color {
                match decision.as_str() {
                    "allow" => "\x1b[32mALLOW\x1b[0m",
                    "warn" => "\x1b[33mWARN\x1b[0m",
                    "block" => "\x1b[31mBLOCK\x1b[0m",
                    _ => &decision,
                }
            } else {
                match decision.as_str() {
                    "allow" => "ALLOW",
                    "warn" => "WARN",
                    "block" => "BLOCK",
                    _ => &decision,
                }
            };
            println!("{decision_display} [{risk_level}] {command}");
            for reason in &output.reasons {
                println!("  rule: {} ({})", reason.rule_id, reason.severity);
                println!("  why:  {}", reason.explanation);
            }
            for suggestion in &output.suggestions {
                println!("  try:  {suggestion}");
            }
        }
    }

    // Exit code based on decision
    match output.decision.as_str() {
        "allow" => 0,
        "warn" => EXIT_WARNING,
        "block" => EXIT_DENIED,
        _ => 0,
    }
}

/// Generate a sample configuration file
/// Show the current configuration
fn show_config(config: &Config) {
    println!("Current configuration:");
    println!();
    println!("Config sources (lowest → highest priority):");
    let user_cfg = config_path();
    let system_cfg = std::path::PathBuf::from("/etc/orca").join("config.toml");
    if system_cfg.exists() {
        println!("  - system: {}", system_cfg.display());
    }
    if user_cfg.exists() {
        println!("  - user: {}", user_cfg.display());
    }
    if let Some(repo_root) = find_repo_root_from_cwd() {
        let project_cfg = repo_root.join(".orca.toml");
        if project_cfg.exists() {
            println!("  - project: {}", project_cfg.display());
        }
    }
    if let Ok(value) = std::env::var(crate::config::ENV_CONFIG_PATH) {
        if let Some(path) = crate::config::resolve_config_path_value(
            &value,
            std::env::current_dir().ok().as_deref(),
        ) {
            if path.exists() {
                println!("  - ORCA_CONFIG: {}", path.display());
            } else {
                println!("  - ORCA_CONFIG: {} (missing)", path.display());
            }
        } else {
            println!("  - ORCA_CONFIG: (set but empty)");
        }
    }
    println!();
    println!("General:");
    println!("  Color: {}", config.general.color);
    println!("  Verbose: {}", config.general.verbose);
    println!("  Log file: {:?}", config.general.log_file);
    println!();
    println!("Enabled packs:");
    for pack in config.enabled_pack_ids() {
        println!("  - {pack}");
    }
    println!();
    println!("Disabled packs:");
    for pack in &config.packs.disabled {
        println!("  - {pack}");
    }
    println!();

    let heredoc = config.heredoc_settings();
    println!("Heredoc scanning:");
    println!("  Enabled: {}", heredoc.enabled);
    println!("  Timeout (ms): {}", heredoc.limits.timeout_ms);
    println!("  Max body bytes: {}", heredoc.limits.max_body_bytes);
    println!("  Max body lines: {}", heredoc.limits.max_body_lines);
    println!("  Max heredocs: {}", heredoc.limits.max_heredocs);
    println!(
        "  Fail-open on parse error: {}",
        heredoc.fallback_on_parse_error
    );
    println!("  Fail-open on timeout: {}", heredoc.fallback_on_timeout);

    let lang_label = |lang: crate::heredoc::ScriptLanguage| -> &'static str {
        match lang {
            crate::heredoc::ScriptLanguage::Bash => "bash",
            crate::heredoc::ScriptLanguage::Go => "go",
            crate::heredoc::ScriptLanguage::Php => "php",
            crate::heredoc::ScriptLanguage::Python => "python",
            crate::heredoc::ScriptLanguage::Ruby => "ruby",
            crate::heredoc::ScriptLanguage::Perl => "perl",
            crate::heredoc::ScriptLanguage::JavaScript => "javascript",
            crate::heredoc::ScriptLanguage::TypeScript => "typescript",
            crate::heredoc::ScriptLanguage::Unknown => "unknown",
        }
    };

    if let Some(langs) = &heredoc.allowed_languages {
        let langs = langs.iter().copied().map(lang_label).collect::<Vec<_>>();
        println!("  Languages: {}", langs.join(","));
    } else {
        println!("  Languages: all");
    }
}

const ORCA_SCAN_PRE_COMMIT_SENTINEL: &str = "# orca:scan-pre-commit";

fn build_scan_pre_commit_hook_script() -> String {
    format!(
        r#"#!/usr/bin/env sh
{ORCA_SCAN_PRE_COMMIT_SENTINEL}
# Generated by: orca scan install-pre-commit
#
# This hook runs `orca scan --staged` to block commits that introduce destructive
# commands in executable contexts (CI workflows, scripts, etc.).
#
# Bypass once (unsafe): git commit --no-verify

set -u

if ! command -v orca >/dev/null 2>&1; then
  echo "orca pre-commit hook: 'orca' not found in PATH; skipping scan." >&2
  echo "Fix: install orca or remove this hook via: orca scan uninstall-pre-commit" >&2
  exit 0
fi

orca scan --staged
status=$?
if [ "$status" -ne 0 ]; then
  echo >&2
  echo "orca scan blocked this commit." >&2
  echo "Fix findings (preferred), or allowlist false positives:" >&2
  echo "  orca allow <rule_id> -r \"<reason>\" --project" >&2
  echo "  orca allowlist add-command \"<command>\" -r \"<reason>\" --project" >&2
  echo "Bypass once (unsafe): git commit --no-verify" >&2
  exit "$status"
fi
"#,
    )
}

fn git_resolve_path(
    cwd: &std::path::Path,
    git_path: &str,
) -> Result<std::path::PathBuf, Box<dyn std::error::Error>> {
    ensure_git_repo(cwd)?;

    let output = std::process::Command::new("git")
        .current_dir(cwd)
        .args(["rev-parse", "--git-path", git_path])
        .output()?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("git rev-parse --git-path {git_path} failed: {stderr}").into());
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let path_str = stdout.trim();
    if path_str.is_empty() {
        return Err(format!("git rev-parse --git-path {git_path} returned empty output").into());
    }

    let path = std::path::PathBuf::from(path_str);
    Ok(if path.is_absolute() {
        path
    } else {
        cwd.join(path)
    })
}

fn git_show_toplevel(
    cwd: &std::path::Path,
) -> Result<std::path::PathBuf, Box<dyn std::error::Error>> {
    ensure_git_repo(cwd)?;

    let output = std::process::Command::new("git")
        .current_dir(cwd)
        .args(["rev-parse", "--show-toplevel"])
        .output()?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("git rev-parse --show-toplevel failed: {stderr}").into());
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let root = stdout.trim();
    if root.is_empty() {
        return Err("git rev-parse --show-toplevel returned empty output".into());
    }

    Ok(std::path::PathBuf::from(root))
}

#[derive(Debug, Clone)]
struct LoadedHooksToml {
    path: std::path::PathBuf,
    cfg: crate::scan::HooksToml,
    warnings: Vec<String>,
}

fn maybe_load_repo_hooks_toml(
    cwd: &std::path::Path,
) -> Result<Option<LoadedHooksToml>, Box<dyn std::error::Error>> {
    let Ok(repo_root) = git_show_toplevel(cwd) else {
        return Ok(None);
    };

    let path = repo_root.join(".orca/hooks.toml");
    if !path.exists() {
        return Ok(None);
    }

    let contents = std::fs::read_to_string(&path)?;
    let (cfg, warnings) = crate::scan::parse_hooks_toml(&contents)
        .map_err(|e| format!("Failed to parse {}: {e}", path.display()))?;

    Ok(Some(LoadedHooksToml {
        path,
        cfg,
        warnings,
    }))
}

fn hook_looks_like_orca_scan_pre_commit(hook_bytes: &[u8]) -> bool {
    String::from_utf8_lossy(hook_bytes).contains(ORCA_SCAN_PRE_COMMIT_SENTINEL)
}

fn install_scan_pre_commit_hook() -> Result<(), Box<dyn std::error::Error>> {
    let cwd = std::env::current_dir()?;
    let hook_path = install_scan_pre_commit_hook_at(&cwd)?;
    eprintln!("Installed pre-commit hook: {}", hook_path.display());
    Ok(())
}

fn install_scan_pre_commit_hook_at(
    cwd: &std::path::Path,
) -> Result<std::path::PathBuf, Box<dyn std::error::Error>> {
    let hook_path = git_resolve_path(cwd, "hooks/pre-commit")?;

    if hook_path.exists() {
        let existing = std::fs::read(&hook_path)?;
        if !hook_looks_like_orca_scan_pre_commit(&existing) {
            return Err(format!(
                "Refusing to overwrite existing pre-commit hook at {}\n\n\
This hook does not appear to have been installed by orca.\n\n\
Manual integration options:\n\
  1) Add a line to your existing hook to run: orca scan --staged\n\
  2) Configure your hook manager to run: orca scan --staged\n\n\
To replace your hook with a orca-managed hook, delete it manually and re-run:\n\
  orca scan install-pre-commit",
                hook_path.display()
            )
            .into());
        }
    } else if let Some(parent) = hook_path.parent() {
        std::fs::create_dir_all(parent)?;
    }

    std::fs::write(&hook_path, build_scan_pre_commit_hook_script())?;

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;

        let mut perms = std::fs::metadata(&hook_path)?.permissions();
        perms.set_mode(0o755);
        std::fs::set_permissions(&hook_path, perms)?;
    }

    Ok(hook_path)
}

fn uninstall_scan_pre_commit_hook() -> Result<(), Box<dyn std::error::Error>> {
    let cwd = std::env::current_dir()?;
    let removed = uninstall_scan_pre_commit_hook_at(&cwd)?;
    if let Some(path) = removed {
        eprintln!("Removed pre-commit hook: {}", path.display());
    } else {
        eprintln!("No orca pre-commit hook found (nothing to remove).");
    }
    Ok(())
}

fn uninstall_scan_pre_commit_hook_at(
    cwd: &std::path::Path,
) -> Result<Option<std::path::PathBuf>, Box<dyn std::error::Error>> {
    let hook_path = git_resolve_path(cwd, "hooks/pre-commit")?;

    if !hook_path.exists() {
        return Ok(None);
    }

    let existing = std::fs::read(&hook_path)?;
    if !hook_looks_like_orca_scan_pre_commit(&existing) {
        return Err(format!(
            "Refusing to remove existing pre-commit hook at {}\n\n\
This hook does not appear to have been installed by orca.\n\n\
If you want to remove it, delete it manually.\n\
If you want to keep it, you can still add orca scanning by adding this line:\n\
  orca scan --staged",
            hook_path.display()
        )
        .into());
    }

    std::fs::remove_file(&hook_path)?;
    Ok(Some(hook_path))
}

/// Handle the `orca scan` subcommand.
///
/// Validates file selection mode, builds scan options, and delegates to
/// the scan module for execution.
#[derive(Debug, Clone)]
struct ResolvedScanSettings {
    format: crate::scan::ScanFormat,
    fail_on: crate::scan::ScanFailOn,
    max_file_size: u64,
    max_findings: usize,
    redact: crate::scan::ScanRedactMode,
    truncate: usize,
    include: Vec<String>,
    exclude: Vec<String>,
}

#[derive(Debug, Clone)]
struct ScanSettingsOverrides {
    format: Option<crate::scan::ScanFormat>,
    fail_on: Option<crate::scan::ScanFailOn>,
    max_file_size: Option<u64>,
    max_findings: Option<usize>,
    redact: Option<crate::scan::ScanRedactMode>,
    truncate: Option<usize>,
    include: Vec<String>,
    exclude: Vec<String>,
}

impl ScanSettingsOverrides {
    fn resolve(self, hooks: Option<&crate::scan::HooksToml>) -> ResolvedScanSettings {
        let mut resolved = ResolvedScanSettings {
            format: crate::scan::ScanFormat::Pretty,
            fail_on: crate::scan::ScanFailOn::Error,
            max_file_size: 1_048_576,
            max_findings: 100,
            redact: crate::scan::ScanRedactMode::None,
            truncate: 200,
            include: Vec::new(),
            exclude: Vec::new(),
        };

        if let Some(hooks) = hooks {
            if let Some(format) = hooks.scan.format {
                resolved.format = format;
            }
            if let Some(fail_on) = hooks.scan.fail_on {
                resolved.fail_on = fail_on;
            }
            if let Some(max_file_size) = hooks.scan.max_file_size {
                resolved.max_file_size = max_file_size;
            }
            if let Some(max_findings) = hooks.scan.max_findings {
                resolved.max_findings = max_findings;
            }
            if let Some(redact) = hooks.scan.redact {
                resolved.redact = redact;
            }
            if let Some(truncate) = hooks.scan.truncate {
                resolved.truncate = truncate;
            }
            resolved.include.clone_from(&hooks.scan.paths.include);
            resolved.exclude.clone_from(&hooks.scan.paths.exclude);
        }

        if let Some(format) = self.format {
            resolved.format = format;
        }
        if let Some(fail_on) = self.fail_on {
            resolved.fail_on = fail_on;
        }
        if let Some(max_file_size) = self.max_file_size {
            resolved.max_file_size = max_file_size;
        }
        if let Some(max_findings) = self.max_findings {
            resolved.max_findings = max_findings;
        }
        if let Some(redact) = self.redact {
            resolved.redact = redact;
        }
        if let Some(truncate) = self.truncate {
            resolved.truncate = truncate;
        }
        if !self.include.is_empty() {
            resolved.include = self.include;
        }
        if !self.exclude.is_empty() {
            resolved.exclude = self.exclude;
        }

        resolved
    }
}

/// Handle the `orca simulate` command.
///
/// This implements git_safety_guard-1gt.8.1 (streaming parser) and
/// git_safety_guard-1gt.8.2 (evaluation loop + aggregation).
fn handle_simulate_command(
    sim: SimulateCommand,
    config: &Config,
    verbosity: Verbosity,
) -> Result<(), Box<dyn std::error::Error>> {
    use crate::simulate::{
        SimulateLimits, SimulateOutputConfig, SimulationConfig, format_json_output,
        format_pretty_output, run_simulation_from_reader,
    };
    use std::fs::File;
    use std::io::{self, BufReader};

    let SimulateCommand {
        file,
        max_lines,
        max_bytes,
        max_command_bytes,
        strict,
        format,
        redact,
        truncate,
        top,
    } = sim;

    let limits = SimulateLimits {
        max_lines,
        max_bytes,
        max_command_bytes: Some(max_command_bytes),
    };

    // Open input (file or stdin)
    let reader: Box<dyn io::Read> = if file == "-" {
        Box::new(io::stdin())
    } else {
        Box::new(BufReader::new(File::open(&file)?))
    };

    let sim_config = SimulationConfig::default();

    if !verbosity.quiet {
        if verbosity.is_debug() {
            eprintln!(
                "Simulate settings: format={format:?}, strict={strict}, max_command_bytes={max_command_bytes}"
            );
        }
        if verbosity.is_trace() {
            eprintln!(
                "Simulate input: file={file}, max_lines={max_lines:?}, max_bytes={max_bytes:?}, top={top}, truncate={truncate}, redact={redact:?}"
            );
        }
    }

    // Run simulation with evaluation loop
    let result = run_simulation_from_reader(reader, limits, config, sim_config, strict)?;

    // Build output configuration
    let output_config = SimulateOutputConfig {
        redact,
        truncate,
        top,
        verbose: verbosity.is_verbose(),
    };

    if verbosity.quiet {
        return Ok(());
    }

    // Output results using formatting functions
    match format {
        SimulateFormat::Pretty => {
            print!("{}", format_pretty_output(&result, &output_config));
        }
        SimulateFormat::Json => {
            println!("{}", format_json_output(result, &output_config)?);
        }
    }

    Ok(())
}

fn handle_scan_command(
    config: &Config,
    scan: ScanCommand,
    verbosity: Verbosity,
) -> Result<Option<(crate::scan::ScanReport, bool)>, Box<dyn std::error::Error>> {
    let ScanCommand {
        staged,
        paths,
        git_diff,
        format,
        fail_on,
        max_file_size,
        max_findings,
        exclude,
        include,
        redact,
        truncate,
        top,
        action,
    } = scan;
    let effective_verbose = verbosity.is_verbose();
    let quiet = verbosity.quiet;
    let debug = verbosity.is_debug();
    let trace = verbosity.is_trace();

    match action {
        Some(ScanAction::InstallPreCommit) => {
            install_scan_pre_commit_hook()?;
            Ok(None)
        }
        Some(ScanAction::UninstallPreCommit) => {
            uninstall_scan_pre_commit_hook()?;
            Ok(None)
        }
        None => {
            let cwd = std::env::current_dir()?;
            let hooks = maybe_load_repo_hooks_toml(&cwd)?;
            if let Some(hooks) = &hooks {
                for warning in &hooks.warnings {
                    eprintln!("Warning: {}: {warning}", hooks.path.display());
                }
            }

            let settings = ScanSettingsOverrides {
                format,
                fail_on,
                max_file_size,
                max_findings,
                redact,
                truncate,
                include,
                exclude,
            }
            .resolve(hooks.as_ref().map(|h| &h.cfg));

            let result = handle_scan(
                config,
                staged,
                paths,
                git_diff,
                settings.format,
                settings.fail_on,
                settings.max_file_size,
                settings.max_findings,
                &settings.exclude,
                &settings.include,
                settings.redact,
                settings.truncate,
                effective_verbose,
                quiet,
                debug,
                trace,
                top,
            )?;
            Ok(Some(result))
        }
    }
}

#[allow(clippy::too_many_arguments)]
#[allow(clippy::needless_pass_by_value)] // Values consumed from CLI args
#[allow(clippy::fn_params_excessive_bools)]
fn handle_scan(
    config: &Config,
    staged: bool,
    paths: Option<Vec<std::path::PathBuf>>,
    git_diff: Option<String>,
    format: crate::scan::ScanFormat,
    fail_on: crate::scan::ScanFailOn,
    max_file_size: u64,
    max_findings: usize,
    exclude: &[String],
    include: &[String],
    redact: crate::scan::ScanRedactMode,
    truncate: usize,
    verbose: bool,
    quiet: bool,
    debug: bool,
    trace: bool,
    top: usize,
) -> Result<(crate::scan::ScanReport, bool), Box<dyn std::error::Error>> {
    use crate::output::progress::MaybeProgress;
    use crate::scan::{ScanEvalContext, ScanOptions, scan_paths_with_progress, should_fail};

    // Validate file selection mode - at least one must be specified
    let file_sources = [staged, paths.is_some(), git_diff.is_some()]
        .iter()
        .filter(|&&x| x)
        .count();

    if file_sources == 0 {
        return Err("No file selection mode specified".into());
    }

    // Build scan options
    let options = ScanOptions {
        format,
        fail_on,
        max_file_size_bytes: max_file_size,
        max_findings,
        redact,
        truncate,
    };

    // Build evaluation context from config
    let ctx = ScanEvalContext::from_config(config);

    // Determine paths to scan
    let scan_paths_list: Vec<std::path::PathBuf> = if staged {
        get_staged_files()?
    } else if let Some(ref paths) = paths {
        paths.clone()
    } else if let Some(ref rev_range) = git_diff {
        get_git_diff_files(rev_range)?
    } else {
        return Err("No file selection mode specified".into());
    };

    if !quiet {
        if verbose {
            eprintln!("Scanning {} path(s)", scan_paths_list.len());
        }
        if debug {
            eprintln!(
                "Scan settings: format={format:?}, fail_on={fail_on:?}, max_file_size={max_file_size}, max_findings={max_findings}"
            );
        }
        if trace {
            eprintln!(
                "Scan filters: include={include:?}, exclude={exclude:?}, truncate={truncate}, redact={redact:?}"
            );
        }
    }

    // Run scan with progress reporting
    let repo_root = find_repo_root_from_cwd();

    // Create progress tracker lazily when we know total file count
    // Use RefCell to allow mutation inside the closure
    use std::cell::RefCell;
    let progress: RefCell<Option<MaybeProgress>> = RefCell::new(None);

    let mut progress_callback = |current: usize, total: usize, file: &str| {
        if current == 0 {
            // First call signals total file count - initialize progress
            if !quiet {
                *progress.borrow_mut() = Some(MaybeProgress::new(total as u64));
            }
        } else if let Some(ref p) = *progress.borrow() {
            // Subsequent calls tick the progress bar
            p.tick(file);
        }
    };

    let report = scan_paths_with_progress(
        &scan_paths_list,
        &options,
        config,
        &ctx,
        include,
        exclude,
        repo_root.as_deref(),
        if quiet {
            None
        } else {
            Some(&mut progress_callback)
        },
    )?;

    // Finish progress bar if it was created
    if let Some(ref p) = *progress.borrow() {
        p.finish_and_clear();
    }

    // Output results
    if !quiet {
        match format {
            crate::scan::ScanFormat::Pretty => {
                print_scan_pretty(&report, verbose, top);
            }
            crate::scan::ScanFormat::Json => {
                let json = serde_json::to_string_pretty(&report)?;
                println!("{json}");
            }
            crate::scan::ScanFormat::Markdown => {
                print_scan_markdown(&report, top, truncate);
            }
            crate::scan::ScanFormat::Sarif => {
                let sarif = crate::sarif::SarifReport::from_scan_report(&report);
                let json = serde_json::to_string_pretty(&sarif)?;
                println!("{json}");
            }
        }
    }

    // Exit with appropriate code based on fail-on policy
    let should_fail = should_fail(&report, fail_on);

    Ok((report, should_fail))
}

/// Get list of files staged for commit (git index).
fn get_staged_files() -> Result<Vec<std::path::PathBuf>, Box<dyn std::error::Error>> {
    let cwd = std::env::current_dir()?;
    get_staged_files_at(&cwd)
}

fn get_staged_files_at(
    cwd: &std::path::Path,
) -> Result<Vec<std::path::PathBuf>, Box<dyn std::error::Error>> {
    ensure_git_repo(cwd)?;

    let output = std::process::Command::new("git")
        .current_dir(cwd)
        .args([
            "diff",
            "--cached",
            "-M",
            "--name-status",
            "-z",
            "--diff-filter=ACMR",
        ])
        .output()?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("git diff --cached failed: {stderr}").into());
    }

    Ok(parse_git_name_status_z(&output.stdout))
}

/// Get list of files changed in a git diff range.
fn get_git_diff_files(
    rev_range: &str,
) -> Result<Vec<std::path::PathBuf>, Box<dyn std::error::Error>> {
    let cwd = std::env::current_dir()?;
    get_git_diff_files_at(&cwd, rev_range)
}

fn get_git_diff_files_at(
    cwd: &std::path::Path,
    rev_range: &str,
) -> Result<Vec<std::path::PathBuf>, Box<dyn std::error::Error>> {
    ensure_git_repo(cwd)?;

    // SECURITY: `rev_range` is user-supplied (`--git-diff <rev>`). Without
    // validation it is forwarded as a positional arg to `git diff`, which
    // happily interprets values starting with `-` as flags. A value like
    // `--output=/etc/orca/allowlist.toml` redirects the diff into that
    // file (clobbering it); `--ext-diff` activates external diff drivers
    // from `.git/config` (arbitrary command execution if an attacker
    // controls the repo's gitconfig). Reject anything that looks like a
    // flag or contains shell metacharacters.
    validate_git_rev_range(rev_range)?;

    let output = std::process::Command::new("git")
        .current_dir(cwd)
        .args([
            "diff",
            "-M",
            "--name-status",
            "-z",
            "--diff-filter=ACMR",
            rev_range,
        ])
        .output()?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("git diff --name-status failed: {stderr}").into());
    }

    Ok(parse_git_name_status_z(&output.stdout))
}

/// Reject `rev_range` values that could be misinterpreted by `git diff` as
/// flags (anything starting with `-`) or that contain shell metacharacters
/// (`\0`, `\n`, `\r`, whitespace, `;`, `&`, `|`, etc.). Legitimate git
/// rev-ranges look like `HEAD~3..HEAD`, `main..feature`,
/// `release/1.0..HEAD`, `v1.2.3...v2.0`, or a single ref like `HEAD@{1}`.
///
/// We do *not* reject every character forbidden by `git check-ref-format`;
/// the goal is to block the unambiguous flag/injection cases, not to
/// reproduce git's full refname grammar in here. If git itself rejects a
/// legitimate-looking value the underlying error is surfaced normally.
fn validate_git_rev_range(rev_range: &str) -> Result<(), Box<dyn std::error::Error>> {
    if rev_range.is_empty() {
        return Err("--git-diff value is empty".into());
    }
    if rev_range.starts_with('-') {
        return Err(format!(
            "--git-diff value {rev_range:?} starts with '-' (would be parsed by git as a flag)"
        )
        .into());
    }
    for ch in rev_range.chars() {
        let bad = matches!(
            ch,
            '\0' | '\n' | '\r' | ' ' | '\t' | ';' | '&' | '|' | '`' | '$' | '<' | '>' | '(' | ')'
        );
        if bad {
            return Err(format!(
                "--git-diff value {rev_range:?} contains a disallowed character ({ch:?})"
            )
            .into());
        }
    }
    Ok(())
}

fn ensure_git_repo(cwd: &std::path::Path) -> Result<(), Box<dyn std::error::Error>> {
    let output = std::process::Command::new("git")
        .current_dir(cwd)
        .args(["rev-parse", "--is-inside-work-tree"])
        .output()?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("Not a git repository: {stderr}").into());
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    if stdout.trim() != "true" {
        return Err("Not inside a git work tree".into());
    }

    Ok(())
}

fn parse_git_name_status_z(stdout: &[u8]) -> Vec<std::path::PathBuf> {
    use std::collections::BTreeSet;

    let mut set: BTreeSet<String> = BTreeSet::new();
    let mut it = stdout.split(|b| *b == 0).filter(|s| !s.is_empty());

    while let Some(status_bytes) = it.next() {
        let status = String::from_utf8_lossy(status_bytes);
        let Some(kind) = status.chars().next() else {
            continue;
        };

        match kind {
            // Renames/copies: status, old path, new path
            'R' | 'C' => {
                let _old = it.next();
                let new = it.next();
                if let Some(new) = new {
                    set.insert(String::from_utf8_lossy(new).to_string());
                }
            }
            // Added/modified/other: status, path
            _ => {
                if let Some(path) = it.next() {
                    set.insert(String::from_utf8_lossy(path).to_string());
                }
            }
        }
    }

    set.into_iter().map(std::path::PathBuf::from).collect()
}

/// Print scan report in pretty format.
fn print_scan_pretty(report: &crate::scan::ScanReport, verbose: bool, top: usize) {
    #[cfg(feature = "rich-output")]
    {
        if crate::output::should_use_rich_output() {
            print_scan_pretty_rich(report, verbose, top);
            return;
        }
    }

    print_scan_pretty_plain(report, verbose, top);
}

fn print_scan_pretty_plain(report: &crate::scan::ScanReport, verbose: bool, top: usize) {
    use crate::output::{ScanResultRow, ScanResultsTable, TableStyle, auto_theme};
    use colored::Colorize;

    if report.findings.is_empty() {
        println!("{}", "No findings.".green());
    } else {
        let total = report.findings.len();
        let shown = if top == 0 { total } else { total.min(top) };
        println!("{} finding(s):", total.to_string().yellow().bold());
        println!();

        // Render findings as a table
        let rows: Vec<ScanResultRow> = report
            .findings
            .iter()
            .take(shown)
            .map(ScanResultRow::from_scan_finding)
            .collect();

        let theme = auto_theme();
        let table = ScanResultsTable::new(rows)
            .with_theme(&theme)
            .with_style(TableStyle::Ascii)
            .with_command_preview();

        println!("{}", table.render());

        // Show detailed info for findings with reasons/suggestions
        let findings_with_details: Vec<_> = report
            .findings
            .iter()
            .take(shown)
            .filter(|f| f.reason.is_some() || f.suggestion.is_some())
            .collect();

        if !findings_with_details.is_empty() && verbose {
            println!();
            println!("{}", "Details:".bold());
            for finding in findings_with_details {
                let location = finding.col.map_or_else(
                    || format!("{}:{}", finding.file, finding.line),
                    |col| format!("{}:{}:{col}", finding.file, finding.line),
                );
                println!("  {}", location.dimmed());
                if let Some(ref reason) = finding.reason {
                    println!("    Reason: {reason}");
                }
                if let Some(ref suggestion) = finding.suggestion {
                    println!("    Suggestion: {}", suggestion.green());
                }
            }
        }

        if shown < total {
            println!();
            println!(
                "{}",
                format!(
                    "… {remaining} more finding(s) not shown (use --top 0 to show all)",
                    remaining = total - shown
                )
                .bright_black()
            );
        }
    }

    // Summary
    println!("---");
    let considered = report.summary.files_scanned + report.summary.files_skipped;
    println!(
        "Files: {considered} considered, {} scanned, {} skipped",
        report.summary.files_scanned, report.summary.files_skipped
    );
    if !report.summary.paths_skipped.is_empty() {
        println!("{}", "Skipped input path(s):".yellow());
        for entry in &report.summary.paths_skipped {
            println!("  {} ({:?})", entry.path, entry.reason);
        }
    }
    println!("Commands extracted: {}", report.summary.commands_extracted);
    println!(
        "Findings: {} (allow={}, warn={}, deny={})",
        report.summary.findings_total,
        report.summary.decisions.allow,
        report.summary.decisions.warn,
        report.summary.decisions.deny
    );
    println!(
        "Severities: error={}, warning={}, info={}",
        report.summary.severities.error,
        report.summary.severities.warning,
        report.summary.severities.info
    );

    if let Some(elapsed_ms) = report.summary.elapsed_ms {
        println!("Elapsed: {elapsed_ms} ms");
    }

    if report.summary.max_findings_reached {
        println!(
            "{}",
            "Note: max findings limit reached, scan stopped early".yellow()
        );
    }

    if verbose {
        // Additional verbose info could go here
    }
}

/// Print scan report in pretty format with rich output.
#[cfg(feature = "rich-output")]
fn print_scan_pretty_rich(report: &crate::scan::ScanReport, verbose: bool, top: usize) {
    use crate::output::console::console;
    use crate::output::{ScanResultRow, ScanResultsTable, auto_theme};

    let con = console();

    if report.findings.is_empty() {
        con.print("[green]No findings.[/]");
    } else {
        let total = report.findings.len();
        let shown = if top == 0 { total } else { total.min(top) };

        con.rule(Some("[bold] Scan Findings [/]"));
        con.print(&format!("[yellow bold]{total}[/] finding(s)"));
        con.print("");

        // Render findings as a table using rich_rust
        let rows: Vec<ScanResultRow> = report
            .findings
            .iter()
            .take(shown)
            .map(ScanResultRow::from_scan_finding)
            .collect();

        let theme = auto_theme();
        let table = ScanResultsTable::new(rows)
            .with_theme(&theme)
            .with_command_preview();

        con.print(&table.render());

        // Show detailed info for findings with reasons/suggestions
        let findings_with_details: Vec<_> = report
            .findings
            .iter()
            .take(shown)
            .filter(|f| f.reason.is_some() || f.suggestion.is_some())
            .collect();

        if !findings_with_details.is_empty() && verbose {
            con.print("");
            con.print("[bold]Details:[/]");
            for finding in findings_with_details {
                let location = finding.col.map_or_else(
                    || format!("{}:{}", finding.file, finding.line),
                    |col| format!("{}:{}:{col}", finding.file, finding.line),
                );
                con.print(&format!("  [dim]{location}[/]"));
                if let Some(ref reason) = finding.reason {
                    con.print(&format!("    [cyan]Reason:[/] {reason}"));
                }
                if let Some(ref suggestion) = finding.suggestion {
                    con.print(&format!("    [green]Suggestion:[/] {suggestion}"));
                }
            }
        }

        if shown < total {
            con.print("");
            con.print(&format!(
                "[dim]… {} more finding(s) not shown (use --top 0 to show all)[/]",
                total - shown
            ));
        }
    }

    // Summary
    con.print("");
    con.print("[dim]───[/]");
    let considered = report.summary.files_scanned + report.summary.files_skipped;
    con.print(&format!(
        "[cyan]Files:[/] {considered} considered, {} scanned, {} skipped",
        report.summary.files_scanned, report.summary.files_skipped
    ));
    if !report.summary.paths_skipped.is_empty() {
        con.print("[yellow]Skipped input path(s):[/]");
        for entry in &report.summary.paths_skipped {
            con.print(&format!("  {} ({:?})", entry.path, entry.reason));
        }
    }
    con.print(&format!(
        "[cyan]Commands extracted:[/] {}",
        report.summary.commands_extracted
    ));
    con.print(&format!(
        "[cyan]Findings:[/] {} ([green]allow={}[/], [yellow]warn={}[/], [red]deny={}[/])",
        report.summary.findings_total,
        report.summary.decisions.allow,
        report.summary.decisions.warn,
        report.summary.decisions.deny
    ));
    con.print(&format!(
        "[cyan]Severities:[/] [red]error={}[/], [yellow]warning={}[/], [blue]info={}[/]",
        report.summary.severities.error,
        report.summary.severities.warning,
        report.summary.severities.info
    ));

    if let Some(elapsed_ms) = report.summary.elapsed_ms {
        con.print(&format!("[cyan]Elapsed:[/] {elapsed_ms} ms"));
    }

    if report.summary.max_findings_reached {
        con.print("[yellow]Note: max findings limit reached, scan stopped early[/]");
    }

    if verbose {
        // Additional verbose info could go here
    }
}

/// Print scan report as GitHub-flavored Markdown (for PR comments).
///
/// Output structure:
/// - Summary header with findings counts
/// - Findings grouped by file, each in a `<details>` block
/// - Severity badges (error/warning/info)
/// - Truncated command preview for readability
fn print_scan_markdown(report: &crate::scan::ScanReport, top: usize, truncate: usize) {
    use std::collections::BTreeMap;

    // Header
    println!("## ORCA Scan Results\n");

    if report.findings.is_empty() {
        println!(":white_check_mark: **No findings** - all commands passed safety checks.\n");
        print_scan_markdown_summary(report);
        return;
    }

    // Summary badges
    let error_count = report.summary.severities.error;
    let warning_count = report.summary.severities.warning;
    let info_count = report.summary.severities.info;

    if error_count > 0 {
        print!(":x: **{error_count} error(s)** ");
    }
    if warning_count > 0 {
        print!(":warning: **{warning_count} warning(s)** ");
    }
    if info_count > 0 {
        print!(":information_source: **{info_count} info** ");
    }
    println!("\n");

    // Group findings by file
    let mut by_file: BTreeMap<&str, Vec<&crate::scan::ScanFinding>> = BTreeMap::new();
    for finding in &report.findings {
        by_file.entry(&finding.file).or_default().push(finding);
    }

    // Limit total findings shown
    let total_findings = report.findings.len();
    let limit = if top == 0 { usize::MAX } else { top };
    let mut shown = 0;

    for (file, findings) in &by_file {
        if shown >= limit {
            break;
        }

        let file_errors = findings
            .iter()
            .filter(|f| matches!(f.severity, crate::scan::ScanSeverity::Error))
            .count();
        let file_warnings = findings
            .iter()
            .filter(|f| matches!(f.severity, crate::scan::ScanSeverity::Warning))
            .count();

        // Build summary line
        let mut summary_parts = Vec::new();
        if file_errors > 0 {
            summary_parts.push(format!("{file_errors} error(s)"));
        }
        if file_warnings > 0 {
            summary_parts.push(format!("{file_warnings} warning(s)"));
        }
        let summary_suffix = if summary_parts.is_empty() {
            String::new()
        } else {
            format!(" - {}", summary_parts.join(", "))
        };

        println!("<details>");
        println!("<summary><code>{file}</code>{summary_suffix}</summary>\n");

        for finding in findings {
            if shown >= limit {
                break;
            }

            let severity_badge = match finding.severity {
                crate::scan::ScanSeverity::Error => ":x:",
                crate::scan::ScanSeverity::Warning => ":warning:",
                crate::scan::ScanSeverity::Info => ":information_source:",
            };

            let decision_str = match finding.decision {
                crate::scan::ScanDecision::Deny => "DENY",
                crate::scan::ScanDecision::Warn => "WARN",
                crate::scan::ScanDecision::Allow => "ALLOW",
            };

            let location = finding.col.map_or_else(
                || finding.line.to_string(),
                |col| format!("{}:{col}", finding.line),
            );

            // Truncate command for readability
            let cmd_preview = truncate_for_markdown(&finding.extracted_command, truncate);

            println!("{severity_badge} **{decision_str}** at line {location}");
            println!("```");
            println!("{cmd_preview}");
            println!("```");

            if let Some(ref rule_id) = finding.rule_id {
                println!("- **Rule:** `{rule_id}`");
            }
            if let Some(ref reason) = finding.reason {
                println!("- **Reason:** {reason}");
            }
            if let Some(ref suggestion) = finding.suggestion {
                println!("- :bulb: **Suggestion:** {suggestion}");
            }
            println!();

            shown += 1;
        }

        println!("</details>\n");
    }

    if shown < total_findings {
        println!("*Showing {shown} of {total_findings} findings. Use `--top 0` to show all.*\n");
    }

    print_scan_markdown_summary(report);
}

/// Print markdown summary section.
fn print_scan_markdown_summary(report: &crate::scan::ScanReport) {
    println!("---\n");
    println!("### Summary\n");
    println!("| Metric | Value |");
    println!("|--------|-------|");
    println!("| Files scanned | {} |", report.summary.files_scanned);
    println!("| Files skipped | {} |", report.summary.files_skipped);
    println!(
        "| Input paths skipped | {} |",
        report.summary.paths_skipped.len()
    );
    println!(
        "| Commands extracted | {} |",
        report.summary.commands_extracted
    );
    println!("| Total findings | {} |", report.summary.findings_total);

    if let Some(elapsed_ms) = report.summary.elapsed_ms {
        println!("| Elapsed | {elapsed_ms} ms |");
    }

    if report.summary.max_findings_reached {
        println!("\n:warning: *Max findings limit reached, scan stopped early.*");
    }

    if !report.summary.paths_skipped.is_empty() {
        println!("\n### Skipped Input Paths\n");
        for entry in &report.summary.paths_skipped {
            println!("- `{}` ({:?})", entry.path, entry.reason);
        }
    }
}

/// Truncate a string for markdown display, respecting char boundaries.
fn truncate_for_markdown(s: &str, max_len: usize) -> String {
    if max_len == 0 || s.len() <= max_len {
        return s.to_string();
    }

    // Find a safe truncation point (char boundary)
    let mut end = max_len;
    while end > 0 && !s.is_char_boundary(end) {
        end -= 1;
    }

    if end == 0 {
        return "...".to_string();
    }

    format!("{}...", &s[..end])
}

/// Handle the `orca explain` subcommand.
///
/// Shows a detailed decision trace for why a command would be allowed or denied.
/// Currently wraps the evaluator result; full tracing integration is future work.
#[allow(clippy::needless_pass_by_value)] // Value consumed from CLI args
fn handle_explain(
    config: &Config,
    command: &str,
    format: ExplainFormat,
    extra_packs: Option<Vec<String>>,
) {
    use crate::trace::{MatchInfo, TraceCollector, TraceDetails};

    // Build effective config with extra packs if specified
    let effective_config = extra_packs.map_or_else(
        || config.clone(),
        |packs| {
            let mut modified = config.clone();
            modified.packs.enabled.extend(packs);
            modified
        },
    );

    // Get enabled packs and collect keywords
    let mut enabled_packs = effective_config.enabled_pack_ids();
    let mut enabled_keywords = REGISTRY.collect_enabled_keywords(&enabled_packs);
    let heredoc_settings = effective_config.heredoc_settings();
    let compiled_overrides = effective_config.overrides.compile();
    let allowlists = load_default_allowlists();

    // Load external packs from custom_paths (glob + tilde expansion).
    let external_paths = effective_config.packs.expand_custom_paths();
    let external_store = load_external_packs(&external_paths);

    // Auto-enable external packs and merge their keywords.
    for id in external_store.pack_ids() {
        enabled_packs.insert(id.clone());
    }
    enabled_keywords.extend(external_store.keywords().iter().copied());

    // Build ordered pack list AFTER external packs are loaded so they're included.
    let mut ordered_packs = REGISTRY.expand_enabled_ordered(&enabled_packs);
    for id in external_store.pack_ids() {
        if !ordered_packs.contains(id) {
            ordered_packs.push(id.clone());
        }
    }
    // Disable keyword index when external packs are present (not covered by index).
    let keyword_index = if external_store.pack_ids().next().is_some() {
        None
    } else {
        REGISTRY.build_enabled_keyword_index(&ordered_packs)
    };

    // Start tracing
    let mut collector = TraceCollector::new(command);

    // Evaluate with timing
    collector.begin_step();
    let result = evaluate_command_with_pack_order(
        command,
        &enabled_keywords,
        &ordered_packs,
        keyword_index.as_ref(),
        &compiled_overrides,
        &allowlists,
        &heredoc_settings,
    );
    collector.end_step(
        "full_evaluation",
        TraceDetails::KeywordGating {
            quick_rejected: result.decision == EvaluationDecision::Allow
                && result.pattern_info.is_none(),
            keywords_checked: enabled_keywords.iter().map(|s| (*s).to_string()).collect(),
            first_match: result.pattern_info.as_ref().and_then(|p| p.pack_id.clone()),
        },
    );
    collector.set_budget_skip(result.skipped_due_to_budget);

    // Add match info if present
    if let Some(ref pattern) = result.pattern_info {
        let rule_id = pattern
            .pack_id
            .as_ref()
            .zip(pattern.pattern_name.as_ref())
            .map(|(pack, name)| format!("{pack}:{name}"));
        collector.set_match(MatchInfo {
            rule_id,
            pack_id: pattern.pack_id.clone(),
            pattern_name: pattern.pattern_name.clone(),
            severity: pattern.severity,
            reason: pattern.reason.clone(),
            source: pattern.source,
            match_start: pattern.matched_span.map(|s| s.start),
            match_end: pattern.matched_span.map(|s| s.end),
            matched_text_preview: pattern.matched_text_preview.clone(),
            explanation: pattern.explanation.clone(),
        });
    }

    // Finish and get trace
    let trace = collector.finish(result.decision);

    // Format and print based on selected format
    match format {
        ExplainFormat::Pretty => {
            #[cfg(feature = "rich-output")]
            {
                if crate::output::should_use_rich_output() {
                    explain_rich(&trace);
                } else {
                    print_explain_pretty_plain(&trace);
                }
            }
            #[cfg(not(feature = "rich-output"))]
            {
                print_explain_pretty_plain(&trace);
            }
        }
        ExplainFormat::Compact => {
            println!("{}", trace.format_compact(None));
        }
        ExplainFormat::Json => {
            let json_output = trace.to_json_output();
            let json = serde_json::to_string_pretty(&json_output)
                .unwrap_or_else(|e| format!("{{\"error\": \"JSON serialization failed: {e}\"}}"));
            println!("{json}");
        }
    }
}

fn print_explain_pretty_plain(trace: &crate::trace::ExplainTrace) {
    let output = trace.format_pretty(colored::control::SHOULD_COLORIZE.should_colorize());
    println!("{output}");
    print_explain_regex_line(trace);
}

fn print_explain_regex_line(trace: &crate::trace::ExplainTrace) {
    let Some(match_info) = trace.match_info.as_ref() else {
        return;
    };
    let Some((pack_id, pattern_name)) = match_info
        .pack_id
        .as_deref()
        .zip(match_info.pattern_name.as_deref())
    else {
        return;
    };
    let Some(regex) = crate::highlight::find_pattern_regex(pack_id, pattern_name) else {
        return;
    };

    let regex =
        crate::highlight::format_regex_pattern(&regex, crate::output::auto_theme().colors_enabled);
    println!("Regex: {regex}");
}

/// Rich output for explain command with tree visualization.
#[cfg(feature = "rich-output")]
fn explain_rich(trace: &crate::trace::ExplainTrace) {
    crate::output::explain_trace_tree(trace)
        .with_theme(&crate::output::auto_theme())
        .render();
}

/// Parse a duration string like "30d", "7d", "24h", "1w" into a chrono Duration.
fn parse_duration_string(s: &str) -> Result<chrono::Duration, String> {
    let s = s.trim();
    if s.is_empty() {
        return Err("Empty duration string".to_string());
    }

    // Find where the number ends and the unit begins
    let num_end = s.find(|c: char| !c.is_ascii_digit()).unwrap_or(s.len());

    if num_end == 0 {
        return Err(format!("Invalid duration: {s} (no number found)"));
    }

    let value: i64 = s[..num_end]
        .parse()
        .map_err(|_| format!("Invalid number in duration: {s}"))?;

    let unit = &s[num_end..];

    match unit.to_lowercase().as_str() {
        "d" | "day" | "days" => Ok(chrono::Duration::days(value)),
        "h" | "hr" | "hour" | "hours" => Ok(chrono::Duration::hours(value)),
        "w" | "week" | "weeks" => Ok(chrono::Duration::weeks(value)),
        "m" | "min" | "minutes" => Ok(chrono::Duration::minutes(value)),
        "" => Err(format!("Missing unit in duration: {s} (use d, h, w, or m)")),
        _ => Err(format!("Unknown duration unit: {unit} (use d, h, w, or m)")),
    }
}

/// Handle the `orca suggest-allowlist` command.
///
/// Analyzes denied commands from history and suggests allowlist patterns.
fn handle_suggest_allowlist_command(
    config: &Config,
    cmd: &SuggestAllowlistCommand,
    robot_mode: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    // Handle --undo mode first
    if let Some(minutes) = cmd.undo {
        return handle_suggest_allowlist_undo(minutes);
    }

    // Parse the "since" duration
    let duration = parse_duration_string(&cmd.since)?;
    let since_time = Utc::now() - duration;

    let effective_format = if robot_mode {
        SuggestFormat::Json
    } else {
        cmd.format
    };

    // Open history database
    let db_path = config.history.expanded_database_path();
    let db = match HistoryDb::open(db_path) {
        Ok(db) => db,
        Err(err) => {
            if matches!(effective_format, SuggestFormat::Json) {
                // Output empty array for JSON format
                println!("[]");
                return Ok(());
            }
            if matches!(err, crate::history::HistoryError::Disabled) {
                println!("History is disabled. Enable it in config to use suggest-allowlist.");
                return Ok(());
            }
            println!("Error opening history database: {err}");
            println!();
            println!("Run 'orca history stats' to check database status.");
            return Ok(());
        }
    };

    // Query denied commands from history
    let options = ExportOptions {
        outcome_filter: Some(Outcome::Deny),
        since: Some(since_time),
        until: None,
        limit: None,
    };

    let entries = db.query_commands_for_export(&options)?;

    if entries.is_empty() {
        if matches!(effective_format, SuggestFormat::Json) {
            // Output empty array for JSON format
            println!("[]");
            return Ok(());
        }
        println!("No denied commands found in the last {}.", cmd.since);
        println!();
        println!("Suggestions:");
        println!("  - Check if history is enabled: orca history stats");
        println!("  - Try a longer time period: --since 90d");
        return Ok(());
    }

    // Also query bypassed commands to include bypass information
    let bypass_options = ExportOptions {
        outcome_filter: Some(Outcome::Bypass),
        since: Some(since_time),
        until: None,
        limit: None,
    };
    let bypass_entries = db
        .query_commands_for_export(&bypass_options)
        .unwrap_or_default();

    // Build a set of commands that were bypassed
    let bypassed_commands: std::collections::HashSet<String> =
        bypass_entries.iter().map(|e| e.command.clone()).collect();

    // Convert to CommandEntryInfo with path and bypass information
    let entry_infos: Vec<CommandEntryInfo> = entries
        .iter()
        .map(|e| CommandEntryInfo {
            command: e.command.clone(),
            working_dir: e.working_dir.clone(),
            was_bypassed: bypassed_commands.contains(&e.command),
        })
        .collect();

    // Generate enhanced suggestions with confidence and risk analysis
    let mut suggestions = generate_enhanced_suggestions(&entry_infos, cmd.min_frequency);

    if suggestions.is_empty() {
        if matches!(effective_format, SuggestFormat::Json) {
            // Output empty array for JSON format
            println!("[]");
            return Ok(());
        }
        println!(
            "No commands found that were blocked {} or more times.",
            cmd.min_frequency
        );
        println!();
        println!("Try lowering --min-frequency or increasing --since period.");
        return Ok(());
    }

    // Apply confidence filtering
    suggestions = match cmd.confidence {
        ConfidenceTierFilter::High => filter_by_confidence(suggestions, ConfidenceTier::High),
        ConfidenceTierFilter::Medium => filter_by_confidence(suggestions, ConfidenceTier::Medium),
        ConfidenceTierFilter::Low => filter_by_confidence(suggestions, ConfidenceTier::Low),
        ConfidenceTierFilter::All => suggestions,
    };

    // Apply risk filtering
    suggestions = match cmd.risk {
        RiskLevelFilter::Low => filter_by_risk(suggestions, RiskLevel::Low),
        RiskLevelFilter::Medium => filter_by_risk(suggestions, RiskLevel::Medium),
        RiskLevelFilter::High => filter_by_risk(suggestions, RiskLevel::High),
        RiskLevelFilter::All => suggestions,
    };

    // Take up to the limit
    suggestions.truncate(cmd.limit);

    if suggestions.is_empty() {
        if matches!(effective_format, SuggestFormat::Json) {
            // Output empty array for JSON format
            println!("[]");
            return Ok(());
        }
        println!("No suggestions available.");
        return Ok(());
    }

    // --apply mode: apply specific suggestions by 1-based index, non-interactively
    if let Some(ref indices) = cmd.apply {
        apply_suggestions_by_index(&suggestions, indices, &db, cmd.accept_risk);
        return Ok(());
    }

    // Output based on format
    match effective_format {
        SuggestFormat::Json => {
            output_suggestions_json(&suggestions)?;
        }
        SuggestFormat::Text => {
            let force_non_interactive = robot_mode
                || cmd.non_interactive
                || std::env::var("ORCA_NON_INTERACTIVE").is_ok()
                || std::env::var("CI").is_ok();
            if force_non_interactive {
                // Non-interactive mode: no writes to database
                output_suggestions_text(&suggestions);
            } else {
                // Interactive mode: pass db for audit logging and config for conflict detection
                output_suggestions_interactive(&suggestions, entries.len(), Some(&db), config)?;
            }
        }
    }

    Ok(())
}

/// Output suggestions as JSON.
fn output_suggestions_json(
    suggestions: &[AllowlistSuggestion],
) -> Result<(), Box<dyn std::error::Error>> {
    #[derive(serde::Serialize)]
    struct JsonSuggestion {
        pattern: String,
        frequency: usize,
        unique_variants: usize,
        confidence: String,
        risk: String,
        reason: String,
        score: f32,
        example_commands: Vec<String>,
        #[serde(skip_serializing_if = "Vec::is_empty")]
        path_patterns: Vec<String>,
        suggest_path_specific: bool,
        bypass_count: usize,
    }

    let output: Vec<JsonSuggestion> = suggestions
        .iter()
        .map(|s| JsonSuggestion {
            pattern: s.cluster.proposed_pattern.clone(),
            frequency: s.cluster.frequency,
            unique_variants: s.cluster.unique_count,
            confidence: s.confidence.as_str().to_string(),
            risk: s.risk.as_str().to_string(),
            reason: s.reason.as_str().to_string(),
            score: s.score,
            example_commands: s.cluster.commands.clone(),
            path_patterns: s.path_patterns.iter().map(|p| p.pattern.clone()).collect(),
            suggest_path_specific: s.suggest_path_specific,
            bypass_count: s.bypass_count,
        })
        .collect();

    let json = serde_json::to_string_pretty(&output)?;
    println!("{json}");
    Ok(())
}

/// Output suggestions as formatted text (non-interactive).
fn output_suggestions_text(suggestions: &[AllowlistSuggestion]) {
    println!("Allowlist Suggestions");
    println!("=====================");
    println!();

    for (i, suggestion) in suggestions.iter().enumerate() {
        println!("[{}/{}] Suggestion", i + 1, suggestions.len());
        println!("────────────────────────────────────────");
        println!("Pattern: {}", suggestion.cluster.proposed_pattern);
        println!(
            "Blocked: {} times ({} unique variants)",
            suggestion.cluster.frequency, suggestion.cluster.unique_count
        );
        println!(
            "Confidence: {} | Risk: {} | Score: {:.2}",
            suggestion.confidence, suggestion.risk, suggestion.score
        );
        println!("Reason: {}", suggestion.reason.description());
        if suggestion.bypass_count > 0 {
            println!("Bypassed: {} times", suggestion.bypass_count);
        }
        if !suggestion.path_patterns.is_empty() {
            println!("Common paths:");
            for pp in suggestion.path_patterns.iter().take(3) {
                println!(
                    "  • {} ({} occurrences{})",
                    pp.pattern,
                    pp.occurrence_count,
                    if pp.is_project_dir {
                        ", project dir"
                    } else {
                        ""
                    }
                );
            }
        }
        println!();
        println!("Example commands:");
        for cmd in suggestion.cluster.commands.iter().take(5) {
            println!("  • {cmd}");
        }
        if suggestion.cluster.commands.len() > 5 {
            println!("  ... and {} more", suggestion.cluster.commands.len() - 5);
        }
        println!();
    }

    // Day-2 policy loop: copy-pasteable next commands for high-confidence items.
    let high_conf: Vec<(usize, &AllowlistSuggestion)> = suggestions
        .iter()
        .enumerate()
        .filter(|(_, s)| matches!(s.confidence, ConfidenceTier::High))
        .map(|(i, s)| (i + 1, s))
        .collect();
    if !high_conf.is_empty() {
        println!("Next steps (high confidence)");
        println!("───────────────────────────");
        println!("Apply by index (non-interactive), or allowlist an example command:");
        for (idx, suggestion) in &high_conf {
            println!("  orca suggest-allowlist --apply {idx}");
            if let Some(example) = suggestion.cluster.commands.first() {
                let escaped = example.replace('\'', "'\\''");
                println!("  orca allowlist add-command '{escaped}' -r \"from suggest-allowlist\"");
            }
        }
        println!();
        println!("Or re-run on a TTY to accept/skip interactively:");
        println!("  orca suggest-allowlist");
    } else {
        println!("Next steps");
        println!("──────────");
        println!("  orca suggest-allowlist --confidence high   # filter high-confidence only");
        println!("  orca allowlist list                        # review current allowlist");
    }
    println!();
}

/// Output suggestions interactively (prompting user for each).
#[allow(clippy::too_many_lines)]
fn output_suggestions_interactive(
    suggestions: &[AllowlistSuggestion],
    total_denied: usize,
    db: Option<&HistoryDb>,
    config: &Config,
) -> Result<(), Box<dyn std::error::Error>> {
    use colored::Colorize;
    use std::io::{self, BufRead, Write};

    println!("Analyzing {total_denied} denied commands...");
    println!("Found {} potential allowlist patterns.", suggestions.len());
    println!();
    println!("For each suggestion, you can:");
    println!("  [A]ccept - Record pattern (to add to allowlist)");
    println!("  [S]kip   - Move to next suggestion");
    println!("  [Q]uit   - Exit without more changes");
    println!();

    let stdin = io::stdin();
    let mut stdout = io::stdout();
    let working_dir = std::env::current_dir()
        .ok()
        .map(|p| p.to_string_lossy().to_string());

    for (i, suggestion) in suggestions.iter().enumerate() {
        let cluster = &suggestion.cluster;
        // Check for potential conflicts before displaying
        let conflict_check = check_pattern_conflicts(&cluster.proposed_pattern, config);

        println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        println!(" [{}/{}] Suggestion", i + 1, suggestions.len());
        println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        println!(" Pattern: {}", cluster.proposed_pattern);
        println!(
            " Blocked: {} times ({} unique variants)",
            cluster.frequency, cluster.unique_count
        );

        // Display confidence, risk, and score
        let confidence_color = match suggestion.confidence {
            ConfidenceTier::High => "high".green(),
            ConfidenceTier::Medium => "medium".yellow(),
            ConfidenceTier::Low => "low".red(),
        };
        let risk_color = match suggestion.risk {
            RiskLevel::Low => "low".green(),
            RiskLevel::Medium => "medium".yellow(),
            RiskLevel::High => "high".red(),
        };
        println!(
            " Confidence: {} | Risk: {} | Score: {:.2}",
            confidence_color, risk_color, suggestion.score
        );
        println!(" Reason: {}", suggestion.reason.description());

        // Show bypass information if available
        if suggestion.bypass_count > 0 {
            println!(
                " {} Bypassed {} time(s) - user manually allowed this command",
                "✓".green(),
                suggestion.bypass_count
            );
        }

        // Show path patterns if suggesting path-specific allowlisting
        if !suggestion.path_patterns.is_empty() {
            println!();
            println!(" Common paths:");
            for pp in suggestion.path_patterns.iter().take(3) {
                let project_indicator = if pp.is_project_dir {
                    " (project dir)".dimmed()
                } else {
                    "".normal()
                };
                println!(
                    "   • {} ({} occurrences){}",
                    pp.pattern, pp.occurrence_count, project_indicator
                );
            }
            if suggestion.suggest_path_specific {
                println!(
                    "   {}",
                    "→ Consider path-specific allowlisting for this pattern".cyan()
                );
            }
        }

        // Display warnings if there are conflicts or the pattern is overly broad
        if conflict_check.conflicts_with_blocks || conflict_check.is_overly_broad {
            println!();
            println!(" {}", "⚠ Warnings:".yellow());
            if let Some(ref warning) = conflict_check.block_conflict_warning {
                println!("   • {}", warning.yellow());
            }
            if conflict_check.is_overly_broad {
                println!(
                    "   • {}",
                    "Pattern is overly broad (uses wildcards without anchors)".yellow()
                );
                if let Some(ref suggestion_text) = conflict_check.refinement_suggestion {
                    println!("     {}", suggestion_text.dimmed());
                }
            }
        }

        println!();
        println!(" Example commands:");
        for cmd in cluster.commands.iter().take(5) {
            println!("   • {cmd}");
        }
        if cluster.commands.len() > 5 {
            println!("   ... and {} more", cluster.commands.len() - 5);
        }
        println!();

        // Prompt for action
        print!(" [A]ccept  [S]kip  [Q]uit: ");
        stdout.flush()?;

        let mut input = String::new();
        stdin.lock().read_line(&mut input)?;

        match input.trim().to_lowercase().as_str() {
            "a" | "accept" => {
                // Log audit entry for accepted suggestion
                if let Some(db) = db {
                    let audit_entry = SuggestionAuditEntry {
                        timestamp: Utc::now(),
                        action: SuggestionAction::Accepted,
                        pattern: cluster.proposed_pattern.clone(),
                        final_pattern: None,
                        risk_level: suggestion.risk.as_str().to_string(),
                        risk_score: suggestion.risk.score(),
                        confidence_tier: suggestion.confidence.as_str().to_string(),
                        confidence_points: match suggestion.confidence {
                            ConfidenceTier::High => 3,
                            ConfidenceTier::Medium => 2,
                            ConfidenceTier::Low => 1,
                        },
                        cluster_frequency: cluster.frequency,
                        unique_variants: cluster.unique_count,
                        sample_commands: serde_json::to_string(&cluster.commands)
                            .unwrap_or_default(),
                        rule_id: None,
                        session_id: None,
                        working_dir: working_dir.clone(),
                    };
                    if let Err(e) = db.log_suggestion_audit(&audit_entry) {
                        eprintln!(" Warning: Could not log audit entry: {e}");
                    }
                }

                // Generate a descriptive reason from the suggestion
                let reason = format!(
                    "Auto-suggested ({} confidence, {} risk): {}",
                    suggestion.confidence.as_str(),
                    suggestion.risk.as_str(),
                    suggestion.reason.description()
                );

                // Write the pattern to the allowlist
                match allowlist_add_pattern(
                    &cluster.proposed_pattern,
                    &reason,
                    suggestion.confidence.as_str(),
                    suggestion.risk.as_str(),
                    cluster.frequency,
                    cluster.unique_count,
                ) {
                    Ok(path) => {
                        use colored::Colorize;
                        println!(" {} Pattern added to allowlist", "✓".green());
                        println!("   File: {}", path.display());
                        println!();
                    }
                    Err(e) => {
                        use colored::Colorize;
                        // Check if it's a duplicate error (not a real failure)
                        if e.to_string().contains("already exists") {
                            println!(" {} Pattern already in allowlist", "ℹ".cyan());
                        } else {
                            eprintln!(" {} Could not write to allowlist: {e}", "✗".red());
                            println!("   You can manually add it with:");
                            println!(
                                "   orca allowlist add-pattern --pattern '{}' --reason '{}'",
                                cluster.proposed_pattern, reason
                            );
                        }
                        println!();
                    }
                }
            }
            "q" | "quit" => {
                println!();
                println!("Exiting. No changes made to allowlist.");
                break;
            }
            _ => {
                // Skip by default - log as rejected for tracking
                if let Some(db) = db {
                    let audit_entry = SuggestionAuditEntry {
                        timestamp: Utc::now(),
                        action: SuggestionAction::Rejected,
                        pattern: cluster.proposed_pattern.clone(),
                        final_pattern: None,
                        risk_level: suggestion.risk.as_str().to_string(),
                        risk_score: suggestion.risk.score(),
                        confidence_tier: suggestion.confidence.as_str().to_string(),
                        confidence_points: match suggestion.confidence {
                            ConfidenceTier::High => 3,
                            ConfidenceTier::Medium => 2,
                            ConfidenceTier::Low => 1,
                        },
                        cluster_frequency: cluster.frequency,
                        unique_variants: cluster.unique_count,
                        sample_commands: serde_json::to_string(&cluster.commands)
                            .unwrap_or_default(),
                        rule_id: None,
                        session_id: None,
                        working_dir: working_dir.clone(),
                    };
                    // Best effort - don't warn on skip audit failures
                    let _ = db.log_suggestion_audit(&audit_entry);
                }
                println!(" → Skipped");
                println!();
            }
        }
    }

    Ok(())
}

/// Apply suggestions by 1-based index without interactive prompts.
///
/// `accept_risk` opts into writing suggestions whose `safety` decision is
/// `RequireConfirmation`. Without it, those entries are skipped — interactive
/// mode would have prompted for explicit confirmation, and `--apply` must not
/// silently bypass that gate. `NeverSuggest` entries are already removed by
/// `filter_suggestions_for_safety`, so they never reach this function.
fn apply_suggestions_by_index(
    suggestions: &[AllowlistSuggestion],
    indices: &[usize],
    db: &HistoryDb,
    accept_risk: bool,
) {
    let working_dir = std::env::current_dir()
        .ok()
        .map(|p| p.to_string_lossy().to_string());

    let mut applied = 0usize;
    let mut skipped = 0usize;

    for &idx in indices {
        if idx == 0 || idx > suggestions.len() {
            eprintln!(
                "Index {idx} out of range (1-{}), skipping",
                suggestions.len()
            );
            skipped += 1;
            continue;
        }

        let suggestion = &suggestions[idx - 1];
        let cluster = &suggestion.cluster;

        if suggestion.safety.requires_confirmation() && !accept_risk {
            let safety_reason = suggestion
                .safety
                .reason()
                .unwrap_or("requires explicit confirmation");
            eprintln!(
                "[{idx}] Skipped (safety): {} — {safety_reason}. Re-run with --accept-risk to apply.",
                cluster.proposed_pattern
            );
            let audit_entry = SuggestionAuditEntry {
                timestamp: Utc::now(),
                action: SuggestionAction::Rejected,
                pattern: cluster.proposed_pattern.clone(),
                final_pattern: None,
                risk_level: suggestion.risk.as_str().to_string(),
                risk_score: suggestion.risk.score(),
                confidence_tier: suggestion.confidence.as_str().to_string(),
                confidence_points: match suggestion.confidence {
                    ConfidenceTier::High => 3,
                    ConfidenceTier::Medium => 2,
                    ConfidenceTier::Low => 1,
                },
                cluster_frequency: cluster.frequency,
                unique_variants: cluster.unique_count,
                sample_commands: serde_json::to_string(&cluster.commands).unwrap_or_default(),
                rule_id: None,
                session_id: None,
                working_dir: working_dir.clone(),
            };
            let _ = db.log_suggestion_audit(&audit_entry);
            skipped += 1;
            continue;
        }

        let reason = format!(
            "Auto-suggested ({} confidence, {} risk): {}",
            suggestion.confidence.as_str(),
            suggestion.risk.as_str(),
            suggestion.reason.description()
        );

        match allowlist_add_pattern(
            &cluster.proposed_pattern,
            &reason,
            suggestion.risk.as_str(),
            suggestion.confidence.as_str(),
            cluster.frequency,
            cluster.unique_count,
        ) {
            Ok(path) => {
                println!(
                    "[{idx}] Applied: {} → {}",
                    cluster.proposed_pattern,
                    path.display()
                );
                applied += 1;

                let audit_entry = SuggestionAuditEntry {
                    timestamp: Utc::now(),
                    action: SuggestionAction::Accepted,
                    pattern: cluster.proposed_pattern.clone(),
                    final_pattern: None,
                    risk_level: suggestion.risk.as_str().to_string(),
                    risk_score: suggestion.risk.score(),
                    confidence_tier: suggestion.confidence.as_str().to_string(),
                    confidence_points: match suggestion.confidence {
                        ConfidenceTier::High => 3,
                        ConfidenceTier::Medium => 2,
                        ConfidenceTier::Low => 1,
                    },
                    cluster_frequency: cluster.frequency,
                    unique_variants: cluster.unique_count,
                    sample_commands: serde_json::to_string(&cluster.commands).unwrap_or_default(),
                    rule_id: None,
                    session_id: None,
                    working_dir: working_dir.clone(),
                };
                let _ = db.log_suggestion_audit(&audit_entry);
            }
            Err(e) => {
                if e.to_string().contains("already exists") {
                    println!("[{idx}] Already in allowlist: {}", cluster.proposed_pattern);
                } else {
                    eprintln!("[{idx}] Failed: {e}");
                }
                skipped += 1;
            }
        }
    }

    println!();
    println!("{applied} applied, {skipped} skipped");
}

/// Handle the `orca history` command.
fn handle_history_command(
    config: &Config,
    action: HistoryAction,
) -> Result<(), Box<dyn std::error::Error>> {
    let db_path = config.history.expanded_database_path();
    let db = match HistoryDb::open(db_path) {
        Ok(db) => db,
        Err(err) => {
            println!("Error opening history database: {err}");
            return Ok(());
        }
    };

    match action {
        HistoryAction::Stats { days, trends, json } => {
            history_stats(&db, days, trends, json)?;
        }
        HistoryAction::Prune {
            older_than_days,
            dry_run,
            yes,
        } => {
            history_prune(&db, older_than_days, dry_run, yes)?;
        }
        HistoryAction::Export {
            output,
            format,
            outcome,
            since,
            until,
            limit,
            compress,
        } => {
            history_export(&db, output, format, outcome, since, until, limit, compress)?;
        }
        HistoryAction::Interactive {
            limit,
            option,
            json,
        } => {
            history_interactive(&db, limit, option, json)?;
        }
        HistoryAction::Analyze {
            days,
            json,
            recommendations_only,
            false_positives,
            gaps,
        } => {
            history_analyze(&db, days, json, recommendations_only, false_positives, gaps)?;
        }
        HistoryAction::Check { json, strict } => {
            let _ = history_check(&db, json, strict)?;
        }
        HistoryAction::Backup { output, compress } => {
            history_backup(&db, &output, compress)?;
        }
    }

    Ok(())
}

fn history_stats(
    db: &HistoryDb,
    days: u64,
    trends: bool,
    json: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    let stats = if trends {
        db.compute_stats_with_trends(days)?
    } else {
        db.compute_stats(days)?
    };

    if json {
        let output = serde_json::to_string_pretty(&stats)?;
        println!("{output}");
    } else {
        let output = format_history_stats_pretty(&stats);
        print!("{output}");
    }

    Ok(())
}

fn history_prune(
    db: &HistoryDb,
    older_than_days: u64,
    dry_run: bool,
    yes: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    if older_than_days == 0 {
        return Err("older-than-days must be at least 1".into());
    }

    if !dry_run && !yes {
        println!("Refusing to prune without --yes or --dry-run.");
        return Ok(());
    }

    let pruned = db.prune_older_than_days(older_than_days, dry_run)?;
    if dry_run {
        println!("Would prune {pruned} entries older than {older_than_days} days");
    } else {
        println!("Pruned {pruned} entries older than {older_than_days} days");
    }

    Ok(())
}

#[allow(clippy::too_many_arguments)]
#[allow(clippy::needless_pass_by_value)]
fn history_export(
    db: &HistoryDb,
    output_path: Option<String>,
    format: ExportFormat,
    outcome: Option<String>,
    since: Option<String>,
    until: Option<String>,
    limit: Option<usize>,
    compress: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    use chrono::DateTime;
    use flate2::Compression;
    use flate2::write::GzEncoder;
    use std::fs::File;
    use std::io::{self, BufWriter, Write};

    // Parse outcome filter
    let outcome_filter = outcome
        .as_deref()
        .map(|o| Outcome::parse(o).ok_or_else(|| format!("Invalid outcome: {o}")))
        .transpose()?;

    // Parse date/time filters
    let since_dt = since
        .as_deref()
        .map(|s| {
            DateTime::parse_from_rfc3339(s)
                .map(|dt| dt.with_timezone(&chrono::Utc))
                .map_err(|_| format!("Invalid since datetime: {s} (use ISO 8601 format)"))
        })
        .transpose()?;

    let until_dt = until
        .as_deref()
        .map(|s| {
            DateTime::parse_from_rfc3339(s)
                .map(|dt| dt.with_timezone(&chrono::Utc))
                .map_err(|_| format!("Invalid until datetime: {s} (use ISO 8601 format)"))
        })
        .transpose()?;

    let options = ExportOptions {
        outcome_filter,
        since: since_dt,
        until: until_dt,
        limit,
    };

    // Create output writer
    let count: usize;
    if let Some(path) = output_path {
        let file = File::create(&path)?;
        if compress {
            let encoder = GzEncoder::new(file, Compression::default());
            let mut writer = BufWriter::new(encoder);
            count = export_to_writer(db, &mut writer, format, &options)?;
            writer.flush()?;
        } else {
            let mut writer = BufWriter::new(file);
            count = export_to_writer(db, &mut writer, format, &options)?;
            writer.flush()?;
        }
        eprintln!("Exported {count} records to {path}");
    } else {
        let stdout = io::stdout();
        let mut writer = stdout.lock();
        count = export_to_writer(db, &mut writer, format, &options)?;
        writer.flush()?;
        eprintln!("Exported {count} records");
    }

    Ok(())
}

fn export_to_writer<W: std::io::Write>(
    db: &HistoryDb,
    writer: &mut W,
    format: ExportFormat,
    options: &ExportOptions,
) -> Result<usize, Box<dyn std::error::Error>> {
    let count = match format {
        ExportFormat::Json => db.export_json(writer, options)?,
        ExportFormat::Jsonl => db.export_jsonl(writer, options)?,
        ExportFormat::Csv => db.export_csv(writer, options)?,
    };
    Ok(count)
}

fn history_interactive(
    db: &HistoryDb,
    limit: usize,
    option: Option<String>,
    json: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    if limit == 0 {
        return Err("limit must be at least 1".into());
    }

    let option_filter = option
        .as_deref()
        .map(|raw| {
            InteractiveAllowlistOptionType::parse(raw).ok_or_else(|| {
                format!("Invalid option type: {raw} (expected exact, temporary, or path_specific)")
            })
        })
        .transpose()?;

    let entries = db.query_interactive_allowlist_audits(limit, option_filter)?;

    if json {
        println!("{}", serde_json::to_string_pretty(&entries)?);
        return Ok(());
    }

    if entries.is_empty() {
        println!("No interactive allowlist audit entries found.");
        return Ok(());
    }

    println!("Interactive allowlist audit entries (most recent first):");
    for entry in entries {
        println!(
            "- {} [{}] {} -> {}",
            entry.timestamp.to_rfc3339(),
            entry.option_type,
            entry.command,
            entry.pattern_added
        );
        if let Some(detail) = entry.option_detail.as_deref() {
            println!("    detail: {detail}");
        }
        println!("    config: {}", entry.config_file);
        if let Some(cwd) = entry.cwd.as_deref() {
            println!("    cwd: {cwd}");
        }
        if let Some(user) = entry.user.as_deref() {
            println!("    user: {user}");
        }
    }

    Ok(())
}

#[allow(clippy::fn_params_excessive_bools, clippy::too_many_lines)]
fn history_analyze(
    db: &HistoryDb,
    days: u64,
    json: bool,
    recommendations_only: bool,
    false_positives: bool,
    gaps: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    use colored::Colorize;

    // Get enabled packs from config
    let config = Config::load();
    let enabled_pack_ids = config.enabled_pack_ids();
    let enabled_packs: Vec<&str> = enabled_pack_ids.iter().map(String::as_str).collect();

    let analysis = db.analyze_pack_effectiveness(days, &enabled_packs)?;

    if json {
        let output = serde_json::to_string_pretty(&analysis)?;
        println!("{output}");
        return Ok(());
    }

    // Pretty print output
    println!(
        "\n{}",
        "═══ Pack Effectiveness Analysis ═══".bright_cyan().bold()
    );
    println!(
        "Period: {} days | Commands analyzed: {}\n",
        analysis.period_days,
        analysis.total_commands.to_string().yellow()
    );

    // Show recommendations (always unless specific view requested)
    if !false_positives && !gaps || recommendations_only {
        if analysis.recommendations.is_empty() {
            println!("{}", "No recommendations at this time.".dimmed());
        } else {
            println!("{}", "📋 Recommendations:".bright_white().bold());
            for rec in &analysis.recommendations {
                let priority_indicator = match rec.priority {
                    8..=10 => "🔴".to_string(),
                    5..=7 => "🟡".to_string(),
                    _ => "🟢".to_string(),
                };
                println!("  {} {}", priority_indicator, rec.description);
                if let Some(action) = &rec.suggested_action {
                    println!("     └─ {}", action.dimmed());
                }
            }
            println!();
        }
    }

    // Show false positives (potentially aggressive patterns)
    if false_positives || (!recommendations_only && !gaps) {
        if analysis.potentially_aggressive.is_empty() {
            println!(
                "{}",
                "✓ No patterns with high bypass rates detected.".green()
            );
        } else {
            println!(
                "{}",
                "⚠️  Potentially Aggressive Patterns (high bypass rate):"
                    .yellow()
                    .bold()
            );
            for p in &analysis.potentially_aggressive {
                println!(
                    "  • {} ({}): {:.1}% bypass rate ({}/{} triggers)",
                    p.pattern.bright_white(),
                    p.pack_id.as_deref().unwrap_or("unknown").dimmed(),
                    p.bypass_rate,
                    p.bypassed_count,
                    p.total_triggers
                );
            }
            println!();
        }
    }

    // Show coverage gaps
    if gaps || (!recommendations_only && !false_positives) {
        if analysis.potential_gaps.is_empty() {
            println!("{}", "✓ No potential coverage gaps detected.".green());
        } else {
            println!(
                "{}",
                "⚠️  Potential Coverage Gaps (dangerous commands that were allowed):"
                    .yellow()
                    .bold()
            );
            for gap in analysis.potential_gaps.iter().take(10) {
                let cmd_display = if gap.command.len() > 60 {
                    format!("{}...", &gap.command[..57])
                } else {
                    gap.command.clone()
                };
                println!(
                    "  • {} ({})",
                    cmd_display.bright_white(),
                    gap.reason.dimmed()
                );
            }
            if analysis.potential_gaps.len() > 10 {
                println!("  ... and {} more", analysis.potential_gaps.len() - 10);
            }
            println!();
        }
    }

    // Show high-value patterns summary
    if !recommendations_only && !false_positives && !gaps {
        if !analysis.high_value_patterns.is_empty() {
            let total_blocked: u64 = analysis
                .high_value_patterns
                .iter()
                .map(|p| p.denied_count)
                .sum();
            println!(
                "{}",
                format!(
                    "✓ {} high-value patterns blocked {} commands with minimal false positives.",
                    analysis.high_value_patterns.len(),
                    total_blocked
                )
                .green()
            );
        }

        // Show inactive packs
        if !analysis.inactive_packs.is_empty() {
            println!(
                "\n{} Inactive packs (enabled but never triggered): {}",
                "ℹ️ ".dimmed(),
                analysis.inactive_packs.join(", ").dimmed()
            );
        }
    }

    Ok(())
}

fn history_check(
    db: &HistoryDb,
    json: bool,
    strict: bool,
) -> Result<bool, Box<dyn std::error::Error>> {
    use colored::Colorize;

    let result = db.check_health()?;

    if json {
        let output = serde_json::to_string_pretty(&result)?;
        println!("{output}");
    } else {
        println!(
            "\n{}",
            "═══ History Database Health Check ═══".bright_cyan().bold()
        );

        // Integrity status
        let integrity_status = if result.integrity_ok {
            "✓ PASSED".green()
        } else {
            "✗ FAILED".red()
        };
        println!(
            "Integrity check: {} ({})",
            integrity_status, result.integrity_check
        );

        // Foreign key check
        if result.foreign_key_violations == 0 {
            println!("Foreign keys: {} violations", "0".green());
        } else {
            println!(
                "Foreign keys: {} violations",
                result.foreign_key_violations.to_string().red()
            );
        }

        // FTS sync status
        let fts_status = if result.fts_in_sync {
            "✓ in sync".green()
        } else {
            "✗ out of sync".red()
        };
        println!(
            "FTS index: {} ({} commands, {} FTS entries)",
            fts_status, result.commands_count, result.fts_count
        );

        // Storage info
        println!("\n{}", "Storage:".bright_white());
        println!(
            "  Database: {} ({} pages)",
            format_size(result.file_size_bytes),
            result.page_count
        );
        println!("  WAL file: {}", format_size(result.wal_size_bytes));
        println!(
            "  Free pages: {} ({} bytes)",
            result.freelist_count,
            result.freelist_count * u64::from(result.page_size)
        );

        // Schema info
        println!("\n{}", "Configuration:".bright_white());
        println!("  Schema version: {}", result.schema_version);
        println!("  Journal mode: {}", result.journal_mode);
        println!("  Page size: {} bytes", result.page_size);
    }

    Ok(!strict || result.integrity_ok)
}

fn history_backup(
    db: &HistoryDb,
    output: &str,
    compress: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    use colored::Colorize;
    use std::path::Path;

    let output_path = Path::new(output);

    // Add .gz extension if compressing and not already present
    let has_gz_ext = output_path
        .extension()
        .is_some_and(|ext| ext.eq_ignore_ascii_case("gz"));
    let final_path = if compress && !has_gz_ext {
        output_path.with_extension(format!(
            "{}.gz",
            output_path
                .extension()
                .map(|e| e.to_string_lossy())
                .unwrap_or_default()
        ))
    } else {
        output_path.to_path_buf()
    };

    println!("Creating backup...");
    let result = db.backup(&final_path, compress)?;

    println!("\n{}", "═══ Backup Complete ═══".bright_cyan().bold());
    println!("Output: {}", result.backup_path.bright_white());
    println!(
        "Size: {} {}",
        format_size(result.backup_size_bytes),
        if result.compressed {
            "(compressed)"
        } else {
            ""
        }
    );
    println!("Duration: {} ms", result.duration_ms);
    if result.verified {
        println!("Verification: {}", "✓ PASSED".green());
    } else {
        println!("Verification: {}", "skipped (compressed backup)".dimmed());
    }

    Ok(())
}

/// Format a byte size in human-readable format.
#[allow(clippy::cast_precision_loss)]
fn format_size(bytes: u64) -> String {
    const KB: u64 = 1024;
    const MB: u64 = KB * 1024;
    const GB: u64 = MB * 1024;

    if bytes >= GB {
        format!("{:.2} GB", bytes as f64 / GB as f64)
    } else if bytes >= MB {
        format!("{:.2} MB", bytes as f64 / MB as f64)
    } else if bytes >= KB {
        format!("{:.2} KB", bytes as f64 / KB as f64)
    } else {
        format!("{bytes} bytes")
    }
}

fn format_history_stats_pretty(stats: &HistoryStats) -> String {
    use std::fmt::Write;

    let mut output = String::new();
    let _ = writeln!(output, "History stats (last {} days)", stats.period_days);
    let _ = writeln!(output, "Total commands: {}", stats.total_commands);
    let _ = writeln!(
        output,
        "Outcomes: allow {} | deny {} | warn {} | bypass {}",
        stats.outcomes.allowed,
        stats.outcomes.denied,
        stats.outcomes.warned,
        stats.outcomes.bypassed
    );
    let _ = writeln!(output, "Block rate: {:.2}%", stats.block_rate * 100.0);
    let _ = writeln!(
        output,
        "Performance (us): p50 {} | p95 {} | p99 {} | max {}",
        stats.performance.p50_us,
        stats.performance.p95_us,
        stats.performance.p99_us,
        stats.performance.max_us
    );

    if !stats.top_patterns.is_empty() {
        let _ = writeln!(output, "Top patterns:");
        for pattern in &stats.top_patterns {
            let _ = writeln!(
                output,
                "  - {} ({}{})",
                pattern.name,
                pattern.count,
                pattern
                    .pack_id
                    .as_ref()
                    .map_or_else(String::new, |pack| format!(", {pack}"))
            );
        }
    }

    if !stats.top_projects.is_empty() {
        let _ = writeln!(output, "Top projects:");
        for project in &stats.top_projects {
            let _ = writeln!(output, "  - {} ({})", project.path, project.command_count);
        }
    }

    if !stats.agents.is_empty() {
        let _ = writeln!(output, "Top agents:");
        for agent in &stats.agents {
            let _ = writeln!(output, "  - {} ({})", agent.name, agent.count);
        }
    }

    if let Some(trends) = &stats.trends {
        let _ = writeln!(
            output,
            "Trends: commands {:+.1}% | block rate {:+.2}pp",
            trends.commands_change, trends.block_rate_change
        );
        if !trends.top_pattern_change.is_empty() {
            let _ = writeln!(output, "Pattern shifts:");
            for (name, delta) in &trends.top_pattern_change {
                let _ = writeln!(output, "  - {name}: {delta:+}");
            }
        }
    }

    output
}

fn is_orca_command(cmd: &str) -> bool {
    cmd == "orca" || cmd.ends_with("/orca")
}

fn is_orca_hook_entry(entry: &serde_json::Value) -> bool {
    entry
        .get("matcher")
        .and_then(|m| m.as_str())
        .is_some_and(|m| m == "Bash")
        && entry
            .get("hooks")
            .and_then(|h| h.as_array())
            .is_some_and(|hooks| {
                hooks.iter().any(|hook| {
                    hook.get("command")
                        .and_then(|c| c.as_str())
                        .is_some_and(is_orca_command)
                })
            })
}

fn remove_orca_hooks_from_pre_tool_use(pre_tool_use: &mut Vec<serde_json::Value>) -> bool {
    let mut removed = false;
    let mut retained_entries = Vec::with_capacity(pre_tool_use.len());

    for mut entry in std::mem::take(pre_tool_use) {
        let is_bash_entry = entry
            .get("matcher")
            .and_then(|m| m.as_str())
            .is_some_and(|m| m == "Bash");

        if !is_bash_entry {
            retained_entries.push(entry);
            continue;
        }

        let drop_entry = if let Some(hooks) = entry.get_mut("hooks").and_then(|h| h.as_array_mut())
        {
            let before = hooks.len();
            hooks.retain(|hook| {
                !hook
                    .get("command")
                    .and_then(|c| c.as_str())
                    .is_some_and(is_orca_command)
            });
            let entry_removed = hooks.len() < before;
            removed |= entry_removed;
            entry_removed && hooks.is_empty()
        } else {
            false
        };

        if !drop_entry {
            retained_entries.push(entry);
        }
    }

    *pre_tool_use = retained_entries;
    removed
}

/// Install the orca hook entry into an in-memory Claude settings JSON value.
///
/// Returns `Ok(true)` when a new hook entry was added, `Ok(false)` when an
/// existing hook was detected and `force == false`.
///
/// # Errors
///
/// Returns an error if the settings JSON is not in the expected format:
/// - root must be an object
/// - `hooks` must be an object (if present)
/// - `hooks.PreToolUse` must be an array (if present)
fn install_orca_hook_into_settings(
    settings: &mut serde_json::Value,
    force: bool,
) -> Result<bool, Box<dyn std::error::Error>> {
    // Build the hook configuration.
    let hook_config = serde_json::json!({
        "matcher": "Bash",
        "hooks": [{
            "type": "command",
            "command": "orca"
        }]
    });

    let settings_obj = settings
        .as_object_mut()
        .ok_or("Invalid settings format (expected JSON object)")?;

    let hooks_value = settings_obj
        .entry("hooks")
        .or_insert_with(|| serde_json::json!({}));

    let hooks_obj = hooks_value
        .as_object_mut()
        .ok_or("Invalid hooks format (expected JSON object)")?;

    let pre_tool_use_value = hooks_obj
        .entry("PreToolUse")
        .or_insert_with(|| serde_json::json!([]));

    let pre_tool_use = pre_tool_use_value
        .as_array_mut()
        .ok_or("Invalid PreToolUse hooks format (expected JSON array)")?;

    let already_installed = pre_tool_use.iter().any(is_orca_hook_entry);
    if already_installed && !force {
        return Ok(false);
    }

    if force {
        remove_orca_hooks_from_pre_tool_use(pre_tool_use);
    }

    pre_tool_use.insert(0, hook_config);
    Ok(true)
}

/// Get the path to user-level Claude Code settings (`~/.claude/settings.json`).
fn claude_settings_path() -> std::path::PathBuf {
    dirs::home_dir()
        .unwrap_or_default()
        .join(".claude")
        .join("settings.json")
}

/// Get the path to orca config directory.
///
/// Prefers `$XDG_CONFIG_HOME/orca/`, then XDG-style `~/.config/orca/` if it exists,
/// otherwise falls back to the platform-native location. This ensures users can
/// use `~/.config/orca/` on all platforms, including macOS where
/// `dirs::config_dir()` returns `~/Library/Application Support`.
fn config_dir() -> std::path::PathBuf {
    // Check XDG_CONFIG_HOME first (if set)
    if let Ok(xdg_home) = std::env::var("XDG_CONFIG_HOME") {
        if let Some(xdg_home) = crate::config::resolve_config_path_value(&xdg_home, None) {
            return xdg_home.join("orca");
        }
    }

    // Check XDG-style path next (~/.config/orca/)
    if let Some(home) = dirs::home_dir() {
        let xdg_dir = home.join(".config").join("orca");
        if xdg_dir.exists() {
            return xdg_dir;
        }
    }

    // Fall back to platform-native or default to ~/.config/orca
    dirs::config_dir()
        .unwrap_or_else(|| dirs::home_dir().unwrap_or_default().join(".config"))
        .join("orca")
}

/// Get the path to orca config file
fn config_path() -> std::path::PathBuf {
    // Prefer an existing config file in the same order as config loading.
    if let Ok(xdg_home) = std::env::var("XDG_CONFIG_HOME") {
        if let Some(xdg_home) = crate::config::resolve_config_path_value(&xdg_home, None) {
            let path = xdg_home.join("orca").join("config.toml");
            if path.exists() {
                return path;
            }
        }
    }

    if let Some(home) = dirs::home_dir() {
        let path = home.join(".config").join("orca").join("config.toml");
        if path.exists() {
            return path;
        }
    }

    if let Some(config_dir) = dirs::config_dir() {
        let path = config_dir.join("orca").join("config.toml");
        if path.exists() {
            return path;
        }
    }

    config_dir().join("config.toml")
}

/// Ensure the ORCA hook is registered in `~/.claude/settings.json`.
///
/// This is the self-healing mechanism that protects against Claude Code
/// silently overwriting `settings.json` mid-session (removing the ORCA hook).
///
/// Called on every hook invocation when `general.self_heal_hook` is enabled.
/// If the hook entry is missing, it is silently re-registered and a warning
/// is emitted to stderr.
///
/// Design constraints:
/// - **Fail-open**: any error (IO, JSON parse, etc.) is swallowed — never
///   block command evaluation because of a self-heal failure.
/// - **Fast path**: if the hook is present, this is just a file read + JSON
///   parse + array scan (typically < 1ms).
/// - **Idempotent**: safe to call on every invocation.
pub fn ensure_hook_registered() {
    if let Err(e) = ensure_hook_registered_inner() {
        // Fail-open: log warning but never block the hook pipeline.
        eprintln!("[orca] Warning: self-heal check failed: {e}");
    }
}

/// Inner implementation for `ensure_hook_registered` that returns errors
/// so the outer function can swallow them for fail-open behavior.
fn ensure_hook_registered_inner() -> Result<(), Box<dyn std::error::Error>> {
    let settings_path = claude_settings_path();
    if !settings_path.exists() {
        // No settings.json at all — nothing to heal. The user hasn't run
        // `orca install` yet, or Claude Code hasn't been configured.
        return Ok(());
    }

    let content = std::fs::read_to_string(&settings_path)?;
    let mut settings: serde_json::Value = serde_json::from_str(&content)?;

    let is_registered = settings
        .get("hooks")
        .and_then(|h| h.get("PreToolUse"))
        .and_then(|arr| arr.as_array())
        .is_some_and(|a| a.iter().any(is_orca_hook_entry));

    if is_registered {
        // Fast path: hook is present, nothing to do.
        return Ok(());
    }

    // Hook was removed — re-register it.
    let changed = install_orca_hook_into_settings(&mut settings, false)?;
    if changed {
        let new_content = serde_json::to_string_pretty(&settings)?;
        std::fs::write(&settings_path, new_content)?;
        eprintln!(
            "[orca] \x1b[1;33mWarning: ORCA hook was missing from {} — re-registered automatically.\x1b[0m",
            settings_path.display()
        );
        eprintln!(
            "[orca] \x1b[1;33mThis usually means Claude Code overwrote settings.json mid-session.\x1b[0m"
        );
    }

    Ok(())
}

// Allowlist CLI implementation
// ============================================================================

use crate::allowlist::{AllowEntry, AllowSelector, AllowlistLayer, RuleId};

/// Resolve which allowlist layer to use based on CLI flags.
///
/// Default: project if in a git repo, otherwise user.
fn resolve_layer(project: bool, user: bool) -> AllowlistLayer {
    if user {
        AllowlistLayer::User
    } else if project {
        AllowlistLayer::Project
    } else {
        // Default: project if we can detect a git repo, otherwise user
        if find_repo_root_from_cwd().is_some() {
            AllowlistLayer::Project
        } else {
            AllowlistLayer::User
        }
    }
}

/// Find the repo root from the current working directory.
fn find_repo_root_from_cwd() -> Option<std::path::PathBuf> {
    let cwd = std::env::current_dir().ok()?;
    crate::config::find_repo_root(&cwd, crate::config::REPO_ROOT_SEARCH_MAX_HOPS)
}

/// Get the path to the allowlist file for a given layer.
fn allowlist_path_for_layer(layer: AllowlistLayer) -> std::path::PathBuf {
    match layer {
        AllowlistLayer::Agent => std::path::PathBuf::from("<agent-profile>"),
        AllowlistLayer::Project => {
            let repo_root = find_repo_root_from_cwd()
                .unwrap_or_else(|| std::env::current_dir().unwrap_or_default());
            repo_root.join(".orca").join("allowlist.toml")
        }
        AllowlistLayer::User => config_dir().join("allowlist.toml"),
        AllowlistLayer::System => std::path::PathBuf::from("/etc/orca/allowlist.toml"),
    }
}

/// Handle allowlist subcommand dispatch.
fn handle_allowlist_command(
    action: AllowlistAction,
    auto_prune_expired: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    if auto_prune_expired && !matches!(action, AllowlistAction::Prune { .. }) {
        prune_allowlist_layers(false, false, false)?;
    }

    match action {
        AllowlistAction::Add {
            rule_id,
            reason,
            project,
            user,
            expires,
            conditions,
            paths,
        } => {
            let layer = resolve_layer(project, user);
            allowlist_add_rule_with_paths(
                &rule_id,
                &reason,
                layer,
                expires.as_deref(),
                &conditions,
                &paths,
            )?;
        }
        AllowlistAction::AddCommand {
            command,
            reason,
            project,
            user,
            expires,
            paths,
        } => {
            let layer = resolve_layer(project, user);
            if paths.is_empty() {
                allowlist_add_command(&command, &reason, layer, expires.as_deref())?;
            } else {
                allowlist_add_command_with_paths(
                    &command,
                    &reason,
                    layer,
                    expires.as_deref(),
                    &paths,
                )?;
            }
        }
        AllowlistAction::List {
            project,
            user,
            format,
        } => {
            allowlist_list(project, user, format)?;
        }
        AllowlistAction::Remove {
            rule_id,
            project,
            user,
        } => {
            let layer = resolve_layer(project, user);
            allowlist_remove(&rule_id, layer)?;
        }
        AllowlistAction::Validate {
            project,
            user,
            strict,
        } => {
            allowlist_validate(project, user, strict)?;
        }
        AllowlistAction::Prune {
            project,
            user,
            dry_run,
            format,
        } => {
            allowlist_prune(project, user, dry_run, format)?;
        }
    }
    Ok(())
}

#[allow(clippy::too_many_lines)]
/// Handle `orca rebase-recover` — issue a short-lived permit that unblocks
/// `git checkout --` and `git restore` for the next recovery step.
///
/// The permit file lives in `.orca/rebase-recovery-permit` at the repo
/// root (anchored to the nearest `.git/`), expires after `ttl` seconds
/// (default 120, hard-capped at 600 via the rebase_recovery module), and
/// is consumed after one successful allow.
fn handle_rebase_recover(
    ttl: Option<u64>,
    robot_mode: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    use crate::rebase_recovery::{
        DEFAULT_PERMIT_TTL_SECS, MAX_PERMIT_TTL_SECS, is_rebase_in_progress, set_permit,
    };

    let cwd = std::env::current_dir().map_err(|e| format!("Cannot read current directory: {e}"))?;
    let ttl_secs = ttl.unwrap_or(DEFAULT_PERMIT_TTL_SECS);
    if ttl_secs == 0 {
        return Err("ttl must be at least 1 second".into());
    }
    let effective_ttl = ttl_secs.min(MAX_PERMIT_TTL_SECS);
    let path = set_permit(&cwd, effective_ttl)?;

    let rebase_active = is_rebase_in_progress(&cwd);

    if robot_mode {
        let status = if rebase_active {
            "rebase_in_progress"
        } else {
            "permit_issued"
        };
        println!(
            r#"{{"status":"{status}","permit_path":"{}","ttl_secs":{effective_ttl},"rebase_in_progress":{rebase_active}}}"#,
            path.display()
                .to_string()
                .replace('\\', "\\\\")
                .replace('"', "\\\"")
        );
        return Ok(());
    }

    println!(
        "orca rebase-recovery permit issued\n  \
         path:   {}\n  \
         ttl:    {effective_ttl}s\n  \
         scope:  core.git:checkout-discard, checkout-ref-discard, restore-worktree, restore-worktree-explicit\n\n\
         Next: retry `git checkout -- .` or `git restore <paths>` in this repo.\n\
         The permit is single-shot — the first matching allow consumes it.",
        path.display()
    );
    if rebase_active {
        println!(
            "\nNote: a rebase is already in progress (`.git/rebase-merge/` or `.git/rebase-apply/`).\n\
             The recovery patterns are already auto-allowed in this state, so the permit is redundant\n\
             here but harmless."
        );
    }
    if effective_ttl < ttl_secs {
        eprintln!(
            "Warning: requested ttl={ttl_secs}s exceeds max ({MAX_PERMIT_TTL_SECS}s); clamped to {effective_ttl}s."
        );
    }
    Ok(())
}

fn handle_allow_once_command(
    config: &Config,
    cmd: &AllowOnceCommand,
) -> Result<(), Box<dyn std::error::Error>> {
    use std::io::{self, Write};

    if let Some(action) = &cmd.action {
        match action {
            AllowOnceAction::List => return handle_allow_once_list(config, cmd),
            AllowOnceAction::Clear(args) => return handle_allow_once_clear(config, cmd, args),
            AllowOnceAction::Revoke(args) => return handle_allow_once_revoke(config, cmd, args),
        }
    }

    let Some(code) = cmd.code.as_deref() else {
        return Err("Missing allow-once code. Usage: orca allow-once <CODE>".into());
    };

    let now = Utc::now();
    let cwd = std::env::current_dir().unwrap_or_default();
    let pending_path = PendingExceptionStore::default_path(Some(&cwd));
    let pending_store = PendingExceptionStore::new(pending_path);

    let (matches, _maintenance) = pending_store.lookup_by_code(code, now)?;
    if matches.is_empty() {
        return Err(
            format!("No pending exception found for code '{code}'. It may be expired.").into(),
        );
    }

    let selected = select_pending_entry(&matches, cmd)?;

    let is_config_block = selected.source.as_deref() == Some("ConfigOverride");
    if is_config_block && !cmd.force {
        return Err(
            "This denial came from your config blocklist; re-run with --force to override.".into(),
        );
    }
    if cmd.json && !cmd.yes && !cmd.dry_run {
        return Err("JSON output requires --yes or --dry-run to avoid prompts.".into());
    }

    let selected_cwd = if selected.cwd == "<unknown>" || selected.cwd.is_empty() {
        cwd
    } else {
        std::path::PathBuf::from(&selected.cwd)
    };
    let repo_root =
        crate::config::find_repo_root(&selected_cwd, crate::config::REPO_ROOT_SEARCH_MAX_HOPS);
    let (scope_kind, scope_path) = repo_root.map_or_else(
        || (AllowOnceScopeKind::Cwd, selected_cwd.clone()),
        |root| (AllowOnceScopeKind::Project, root),
    );
    let scope_path_str = scope_path.to_string_lossy().to_string();

    let entry = AllowOnceEntry::from_pending(
        selected,
        now,
        scope_kind,
        &scope_path_str,
        cmd.single_use,
        cmd.force && is_config_block,
        &config.logging.redaction,
    );

    if cmd.json {
        let output = serde_json::json!({
            "status": "ok",
            "code": code,
            "dry_run": cmd.dry_run,
            "single_use": cmd.single_use,
            "force": entry.force_allow_config,
            "scope_kind": format!("{scope_kind:?}").to_lowercase(),
            "scope_path": scope_path_str,
            "command": if cmd.show_raw { selected.command_raw.clone() } else { selected.command_redacted.clone() },
            "cwd": selected.cwd.clone(),
            "expires_at": entry.expires_at,
        });
        println!("{}", serde_json::to_string_pretty(&output)?);
        if cmd.dry_run {
            return Ok(());
        }
    } else {
        let display_command = if cmd.show_raw {
            selected.command_raw.as_str()
        } else {
            selected.command_redacted.as_str()
        };
        println!("Allow-once confirmation:");
        println!("  Command: {display_command}");
        println!("  CWD: {}", selected.cwd);
        println!("  Expires: {}", entry.expires_at);
        println!("  Scope: {scope_kind:?} ({scope_path_str})");
        if cmd.single_use {
            println!("  Mode: single-use");
        } else {
            println!("  Mode: reusable until expiry");
        }

        let needs_prompt = !(cmd.yes || cmd.dry_run);
        if needs_prompt {
            if cmd.force && is_config_block {
                print!("Type 'FORCE' to confirm override: ");
                io::stdout().flush()?;
                let mut response = String::new();
                io::stdin().read_line(&mut response)?;
                if response.trim() != "FORCE" {
                    return Err("Aborted.".into());
                }
            } else {
                print!("Proceed? [y/N]: ");
                io::stdout().flush()?;
                let mut response = String::new();
                io::stdin().read_line(&mut response)?;
                let response = response.trim().to_lowercase();
                if response != "y" && response != "yes" {
                    return Err("Aborted.".into());
                }
            }
        }

        if cmd.dry_run {
            println!("Dry-run: no allow-once entry written.");
            return Ok(());
        }
    }

    let allow_once_path = AllowOnceStore::default_path(Some(&selected_cwd));
    let allow_once_store = AllowOnceStore::new(allow_once_path.clone());
    let _maintenance = allow_once_store.add_entry(&entry, now)?;

    // Remove the pending exception so it doesn't show up in lists anymore.
    // This is best-effort (if it fails, the allowed command still works).
    if let Err(e) = pending_store.remove_by_full_hash(&selected.full_hash, now) {
        eprintln!("Warning: Failed to remove pending exception: {e}");
    }

    if !cmd.json {
        println!("✓ Allow-once entry created");
        println!("  File: {}", allow_once_path.display());
    }

    Ok(())
}

fn handle_allow_once_list(
    _config: &Config,
    cmd: &AllowOnceCommand,
) -> Result<(), Box<dyn std::error::Error>> {
    let now = Utc::now();
    let cwd = std::env::current_dir().unwrap_or_default();

    let pending_store = PendingExceptionStore::new(PendingExceptionStore::default_path(Some(&cwd)));
    let allow_once_store = AllowOnceStore::new(AllowOnceStore::default_path(Some(&cwd)));

    let (pending, pending_maintenance) = pending_store.load_active(now)?;
    let (allow_once, allow_once_maintenance) = allow_once_store.load_active(now)?;

    if cmd.json {
        let output = build_allow_once_list_json(
            &pending,
            pending_maintenance,
            &allow_once,
            allow_once_maintenance,
            cmd.show_raw,
        );
        println!("{}", serde_json::to_string_pretty(&output)?);
        return Ok(());
    }

    println!("Allow-once pending codes: {}", pending.len());
    if pending.is_empty() {
        println!("  (none)");
    } else {
        for record in &pending {
            let cmd_display = if cmd.show_raw {
                record.command_raw.as_str()
            } else {
                record.command_redacted.as_str()
            };
            println!(
                "  - {} [{}] {}",
                record.short_code,
                &record.full_hash[..8.min(record.full_hash.len())],
                cmd_display
            );
        }
    }

    println!();
    println!("Allow-once active entries: {}", allow_once.len());
    if allow_once.is_empty() {
        println!("  (none)");
    } else {
        for entry in &allow_once {
            let cmd_display = if cmd.show_raw {
                entry.command_raw.as_str()
            } else {
                entry.command_redacted.as_str()
            };
            println!(
                "  - {} [{}] {}",
                entry.source_short_code,
                &entry.source_full_hash[..8.min(entry.source_full_hash.len())],
                cmd_display
            );
        }
    }

    if !pending_maintenance.is_empty() || !allow_once_maintenance.is_empty() {
        println!();
        println!(
            "Maintenance: pending(pruned_expired={}, pruned_consumed={}, parse_errors={}), allow_once(pruned_expired={}, pruned_consumed={}, parse_errors={})",
            pending_maintenance.pruned_expired,
            pending_maintenance.pruned_consumed,
            pending_maintenance.parse_errors,
            allow_once_maintenance.pruned_expired,
            allow_once_maintenance.pruned_consumed,
            allow_once_maintenance.parse_errors
        );
    }

    Ok(())
}

fn build_allow_once_list_json(
    pending: &[PendingExceptionRecord],
    pending_maintenance: crate::pending_exceptions::PendingMaintenance,
    allow_once: &[AllowOnceEntry],
    allow_once_maintenance: crate::pending_exceptions::PendingMaintenance,
    show_raw: bool,
) -> serde_json::Value {
    let pending_json: Vec<serde_json::Value> = pending
        .iter()
        .map(|record| {
            serde_json::json!({
                "short_code": &record.short_code,
                "full_hash": &record.full_hash,
                "created_at": &record.created_at,
                "expires_at": &record.expires_at,
                "cwd": &record.cwd,
                "reason": &record.reason,
                "single_use": record.single_use,
                "source": record.source.as_deref(),
                "command": if show_raw { &record.command_raw } else { &record.command_redacted },
            })
        })
        .collect();

    let allow_once_json: Vec<serde_json::Value> = allow_once
        .iter()
        .map(|entry| {
            serde_json::json!({
                "source_short_code": &entry.source_short_code,
                "source_full_hash": &entry.source_full_hash,
                "created_at": &entry.created_at,
                "expires_at": &entry.expires_at,
                "scope_kind": format!("{:?}", entry.scope_kind).to_lowercase(),
                "scope_path": &entry.scope_path,
                "reason": &entry.reason,
                "single_use": entry.single_use,
                "force_allow_config": entry.force_allow_config,
                "command": if show_raw { &entry.command_raw } else { &entry.command_redacted },
            })
        })
        .collect();

    serde_json::json!({
        "status": "ok",
        "pending": {
            "count": pending_json.len(),
            "maintenance": pending_maintenance,
            "entries": pending_json,
        },
        "allow_once": {
            "count": allow_once_json.len(),
            "maintenance": allow_once_maintenance,
            "entries": allow_once_json,
        },
    })
}

fn handle_allow_once_clear(
    config: &Config,
    cmd: &AllowOnceCommand,
    args: &AllowOnceClearArgs,
) -> Result<(), Box<dyn std::error::Error>> {
    use std::io::{self, Write};

    if cmd.json && !cmd.yes {
        return Err("JSON output requires --yes to avoid interactive prompts.".into());
    }

    let now = Utc::now();
    let cwd = std::env::current_dir().unwrap_or_default();

    let pending_store = PendingExceptionStore::new(PendingExceptionStore::default_path(Some(&cwd)));
    let allow_once_store = AllowOnceStore::new(AllowOnceStore::default_path(Some(&cwd)));

    let wipe_pending = args.all || args.pending;
    let wipe_allow_once = args.all || args.allow_once;

    let (pending_preview, pending_preview_maintenance) = pending_store.preview_active(now)?;
    let (allow_once_preview, allow_once_preview_maintenance) =
        allow_once_store.preview_active(now)?;

    let pending_wipe_count = if wipe_pending {
        pending_preview.len()
    } else {
        0
    };
    let allow_once_wipe_count = if wipe_allow_once {
        allow_once_preview.len()
    } else {
        0
    };

    if !cmd.json && !cmd.yes && (wipe_pending || wipe_allow_once) {
        println!("Allow-once clear confirmation:");
        println!("  pending_wipe_active={pending_wipe_count}");
        println!("  allow_once_wipe_active={allow_once_wipe_count}");
        print!("Proceed? [y/N]: ");
        io::stdout().flush()?;
        let mut response = String::new();
        io::stdin().read_line(&mut response)?;
        let response = response.trim().to_lowercase();
        if response != "y" && response != "yes" {
            return Err("Aborted.".into());
        }
    }

    let (pending_wiped, pending_maintenance) = if wipe_pending {
        pending_store.clear_all(now)?
    } else {
        let (_active, maintenance) = pending_store.load_active(now)?;
        (0, maintenance)
    };
    let (allow_once_wiped, allow_once_maintenance) = if wipe_allow_once {
        allow_once_store.clear_all(now)?
    } else {
        let (_active, maintenance) = allow_once_store.load_active(now)?;
        (0, maintenance)
    };

    if let Some(log_file) = config.general.log_file.as_deref() {
        let _ = crate::pending_exceptions::log_allow_once_action(
            log_file,
            "clear",
            &format!(
                "pending_wiped={pending_wiped}, allow_once_wiped={allow_once_wiped}, flags=all:{} pending:{} allow_once:{}",
                args.all, args.pending, args.allow_once
            ),
        );
    }

    if cmd.json {
        let output = serde_json::json!({
            "status": "ok",
            "pending": {
                "wiped": pending_wiped,
                "preview_maintenance": pending_preview_maintenance,
                "maintenance": pending_maintenance,
            },
            "allow_once": {
                "wiped": allow_once_wiped,
                "preview_maintenance": allow_once_preview_maintenance,
                "maintenance": allow_once_maintenance,
            },
        });
        println!("{}", serde_json::to_string_pretty(&output)?);
        return Ok(());
    }

    println!("✓ Cleared allow-once stores");
    println!("  Pending wiped: {pending_wiped}");
    println!("  Allow-once wiped: {allow_once_wiped}");
    Ok(())
}

fn handle_allow_once_revoke(
    config: &Config,
    cmd: &AllowOnceCommand,
    args: &AllowOnceRevokeArgs,
) -> Result<(), Box<dyn std::error::Error>> {
    use std::io::{self, Write};

    if cmd.json && !cmd.yes {
        return Err("JSON output requires --yes to avoid interactive prompts.".into());
    }

    let now = Utc::now();
    let cwd = std::env::current_dir().unwrap_or_default();

    let pending_store = PendingExceptionStore::new(PendingExceptionStore::default_path(Some(&cwd)));
    let allow_once_store = AllowOnceStore::new(AllowOnceStore::default_path(Some(&cwd)));

    let (pending_preview, _) = pending_store.preview_active(now)?;
    let (allow_once_preview, _) = allow_once_store.preview_active(now)?;
    let full_hash =
        resolve_allow_once_revoke_target(&args.target, &pending_preview, &allow_once_preview)?;

    if !cmd.json && !cmd.yes {
        println!("Allow-once revoke confirmation:");
        println!("  target: {}", args.target);
        println!("  resolved_full_hash: {full_hash}");
        print!("Proceed? [y/N]: ");
        io::stdout().flush()?;
        let mut response = String::new();
        io::stdin().read_line(&mut response)?;
        let response = response.trim().to_lowercase();
        if response != "y" && response != "yes" {
            return Err("Aborted.".into());
        }
    }

    let (pending_removed, pending_maintenance) =
        pending_store.remove_by_full_hash(&full_hash, now)?;
    let (allow_once_removed, allow_once_maintenance) =
        allow_once_store.remove_by_source_full_hash(&full_hash, now)?;

    if let Some(log_file) = config.general.log_file.as_deref() {
        let _ = crate::pending_exceptions::log_allow_once_action(
            log_file,
            "revoke",
            &format!(
                "target={}, full_hash={}, pending_removed={}, allow_once_removed={}",
                args.target, full_hash, pending_removed, allow_once_removed
            ),
        );
    }

    if cmd.json {
        let output = serde_json::json!({
            "status": "ok",
            "target": &args.target,
            "full_hash": full_hash,
            "pending": { "removed": pending_removed, "maintenance": pending_maintenance },
            "allow_once": { "removed": allow_once_removed, "maintenance": allow_once_maintenance },
        });
        println!("{}", serde_json::to_string_pretty(&output)?);
        return Ok(());
    }

    println!("✓ Revoked allow-once exception");
    println!("  Pending removed: {pending_removed}");
    println!("  Allow-once removed: {allow_once_removed}");
    Ok(())
}

fn resolve_allow_once_revoke_target(
    target: &str,
    pending: &[PendingExceptionRecord],
    allow_once: &[AllowOnceEntry],
) -> Result<String, Box<dyn std::error::Error>> {
    let mut matches: Vec<String> = Vec::new();

    // Short codes are 6-digit numeric strings (formerly 5; legacy codes still
    // accepted). Anything else is a hash prefix.
    let is_short_code = target.len() <= 6 && target.chars().all(|c| c.is_ascii_digit());

    if is_short_code {
        matches.extend(
            pending
                .iter()
                .filter(|record| record.short_code == target)
                .map(|record| record.full_hash.clone()),
        );
        matches.extend(
            allow_once
                .iter()
                .filter(|entry| entry.source_short_code == target)
                .map(|entry| entry.source_full_hash.clone()),
        );
    } else {
        matches.extend(
            pending
                .iter()
                .filter(|record| record.full_hash.starts_with(target))
                .map(|record| record.full_hash.clone()),
        );
        matches.extend(
            allow_once
                .iter()
                .filter(|entry| entry.source_full_hash.starts_with(target))
                .map(|entry| entry.source_full_hash.clone()),
        );
    }

    matches.sort();
    matches.dedup();

    match matches.as_slice() {
        [] => Err(format!("No allow-once exception found matching '{target}'.").into()),
        [one] => Ok(one.clone()),
        many => Err(format!(
            "Ambiguous allow-once revoke target '{target}'. Matches: {}",
            many.join(", ")
        )
        .into()),
    }
}

fn select_pending_entry<'a>(
    matches: &'a [PendingExceptionRecord],
    cmd: &AllowOnceCommand,
) -> Result<&'a PendingExceptionRecord, Box<dyn std::error::Error>> {
    if matches.len() == 1 {
        return Ok(&matches[0]);
    }

    if let Some(hash) = cmd.hash.as_deref() {
        let record = matches
            .iter()
            .find(|record| record.full_hash == hash)
            .ok_or_else(|| format!("No pending entry with hash '{hash}'"))?;
        return Ok(record);
    }

    if let Some(pick) = cmd.pick {
        if pick == 0 || pick > matches.len() {
            return Err(format!("Pick must be between 1 and {}", matches.len()).into());
        }
        return Ok(&matches[pick - 1]);
    }

    print_pending_choices(matches, cmd.show_raw);
    Err("Multiple pending entries share this code; use --pick or --hash.".into())
}

fn print_pending_choices(matches: &[PendingExceptionRecord], show_raw: bool) {
    println!("Multiple pending entries match this code:");
    for (idx, record) in matches.iter().enumerate() {
        let display_command = if show_raw {
            record.command_raw.as_str()
        } else {
            record.command_redacted.as_str()
        };
        println!(
            "  {}. [{}] {} (cwd: {}, created: {})",
            idx + 1,
            &record.full_hash[..8.min(record.full_hash.len())],
            display_command,
            record.cwd,
            record.created_at
        );
    }
}

/// Add a rule to the allowlist.
fn allowlist_add_rule(
    rule_id: &str,
    reason: &str,
    layer: AllowlistLayer,
    expires: Option<&str>,
    conditions: &[String],
) -> Result<(), Box<dyn std::error::Error>> {
    allowlist_add_rule_with_paths(rule_id, reason, layer, expires, conditions, &[])
}

/// Add a rule to the allowlist with optional path scoping.
fn allowlist_add_rule_with_paths(
    rule_id: &str,
    reason: &str,
    layer: AllowlistLayer,
    expires: Option<&str>,
    conditions: &[String],
    paths: &[String],
) -> Result<(), Box<dyn std::error::Error>> {
    use colored::Colorize;

    // Validate rule ID format
    let parsed_rule = RuleId::parse(rule_id)
        .ok_or_else(|| format!("Invalid rule ID: {rule_id} (expected pack_id:pattern_name)"))?;

    // Validate expiration date format if provided
    if let Some(exp) = expires {
        crate::allowlist::validate_expiration_date(exp)?;
    }

    // Validate condition formats
    for cond in conditions {
        crate::allowlist::validate_condition(cond)?;
    }

    // Validate path glob patterns
    for path in paths {
        crate::allowlist::validate_glob_pattern(path)?;
    }

    let path = allowlist_path_for_layer(layer);
    let mut doc = load_or_create_allowlist_doc(&path)?;

    // Check for duplicate
    if has_rule_entry(&doc, &parsed_rule) {
        println!(
            "{} Rule {} already exists in {} allowlist",
            "Warning:".yellow(),
            rule_id,
            layer.label()
        );
        return Ok(());
    }

    // Build entry
    let entry = if paths.is_empty() {
        build_rule_entry(&parsed_rule, reason, expires, conditions)
    } else {
        build_rule_entry_with_paths(&parsed_rule, reason, expires, conditions, paths)
    };
    append_entry(&mut doc, entry);

    // Write back
    write_allowlist(&path, &doc)?;

    println!(
        "{} Added {} to {} allowlist",
        "✓".green(),
        rule_id.cyan(),
        layer.label()
    );
    println!("  File: {}", path.display());

    Ok(())
}

/// Add an exact command to the allowlist.
fn allowlist_add_command(
    command: &str,
    reason: &str,
    layer: AllowlistLayer,
    expires: Option<&str>,
) -> Result<(), Box<dyn std::error::Error>> {
    allowlist_add_command_with_paths(command, reason, layer, expires, &[])
}

/// Add an exact command to the allowlist with optional path scoping.
fn allowlist_add_command_with_paths(
    command: &str,
    reason: &str,
    layer: AllowlistLayer,
    expires: Option<&str>,
    paths: &[String],
) -> Result<(), Box<dyn std::error::Error>> {
    use colored::Colorize;

    // Validate expiration date format if provided
    if let Some(exp) = expires {
        crate::allowlist::validate_expiration_date(exp)?;
    }

    // Validate path glob patterns
    for path in paths {
        crate::allowlist::validate_glob_pattern(path)?;
    }

    let path = allowlist_path_for_layer(layer);
    let mut doc = load_or_create_allowlist_doc(&path)?;

    // Check for duplicate
    if has_command_entry(&doc, command) {
        println!(
            "{} Command already exists in {} allowlist",
            "Warning:".yellow(),
            layer.label()
        );
        return Ok(());
    }

    // Build entry
    let entry = if paths.is_empty() {
        build_command_entry(command, reason, expires)
    } else {
        build_command_entry_with_paths(command, reason, expires, paths)
    };
    append_entry(&mut doc, entry);

    // Write back
    write_allowlist(&path, &doc)?;

    println!(
        "{} Added exact command to {} allowlist",
        "✓".green(),
        layer.label()
    );
    println!("  File: {}", path.display());

    Ok(())
}

/// List allowlist entries.
fn allowlist_list(
    project_only: bool,
    user_only: bool,
    format: AllowlistOutputFormat,
) -> Result<(), Box<dyn std::error::Error>> {
    use colored::Colorize;

    let layers: Vec<AllowlistLayer> = if project_only {
        vec![AllowlistLayer::Project]
    } else if user_only {
        vec![AllowlistLayer::User]
    } else {
        vec![AllowlistLayer::Project, AllowlistLayer::User]
    };

    let mut all_entries: Vec<(AllowlistLayer, std::path::PathBuf, AllowEntry)> = Vec::new();

    // Load all allowlists once (more efficient than loading per-layer)
    let allowlist = crate::allowlist::load_default_allowlists();

    for layer in layers {
        let path = allowlist_path_for_layer(layer);
        if !path.exists() {
            continue;
        }

        for loaded in &allowlist.layers {
            if loaded.layer == layer {
                for entry in &loaded.file.entries {
                    all_entries.push((layer, path.clone(), entry.clone()));
                }
            }
        }
    }

    match format {
        AllowlistOutputFormat::Pretty => {
            if all_entries.is_empty() {
                println!("{}", "No allowlist entries found.".yellow());
                return Ok(());
            }

            println!("{}", "Allowlist entries:".bold());
            println!();

            for (layer, path, entry) in &all_entries {
                let selector_str = match &entry.selector {
                    AllowSelector::Rule(rule_id) => {
                        serde_json::json!({"type": "rule", "value": rule_id.to_string()})
                    }
                    AllowSelector::ExactCommand(cmd) => {
                        serde_json::json!({"type": "exact_command", "value": cmd})
                    }
                    AllowSelector::CommandPrefix(prefix) => {
                        serde_json::json!({"type": "command_prefix", "value": prefix})
                    }
                    AllowSelector::RegexPattern(re) => {
                        serde_json::json!({"type": "pattern", "value": re})
                    }
                };

                println!("  {} [{}]", selector_str, layer.label());
                println!("    Reason: {}", entry.reason);
                if let Some(added_by) = &entry.added_by {
                    println!("    Added by: {added_by}");
                }
                if let Some(added_at) = &entry.added_at {
                    println!("    Added at: {added_at}");
                }
                if let Some(expires_at) = &entry.expires_at {
                    let expired = is_expired(expires_at);
                    let status = if expired {
                        "EXPIRED".red().to_string()
                    } else {
                        expires_at.clone()
                    };
                    println!("    Expires: {status}");
                }
                println!("    File: {}", path.display());
                println!();
            }
        }
        AllowlistOutputFormat::Json => {
            let json_entries: Vec<serde_json::Value> = all_entries
                .iter()
                .map(|(layer, path, entry)| {
                    let selector = match &entry.selector {
                        AllowSelector::Rule(rule_id) => {
                            serde_json::json!({"type": "rule", "value": rule_id.to_string()})
                        }
                        AllowSelector::ExactCommand(cmd) => {
                            serde_json::json!({"type": "exact_command", "value": cmd})
                        }
                        AllowSelector::CommandPrefix(prefix) => {
                            serde_json::json!({"type": "command_prefix", "value": prefix})
                        }
                        AllowSelector::RegexPattern(re) => {
                            serde_json::json!({"type": "pattern", "value": re})
                        }
                    };
                    serde_json::json!({
                        "layer": layer.label(),
                        "path": path.display().to_string(),
                        "selector": selector,
                        "reason": entry.reason,
                        "added_by": entry.added_by,
                        "added_at": entry.added_at,
                        "expires_at": entry.expires_at,
                    })
                })
                .collect();

            println!("{}", serde_json::to_string_pretty(&json_entries)?);
        }
    }

    Ok(())
}

/// Remove a rule from the allowlist.
fn allowlist_remove(
    rule_id: &str,
    layer: AllowlistLayer,
) -> Result<(), Box<dyn std::error::Error>> {
    use colored::Colorize;

    let parsed_rule = RuleId::parse(rule_id)
        .ok_or_else(|| format!("Invalid rule ID: {rule_id} (expected pack_id:pattern_name)"))?;

    let path = allowlist_path_for_layer(layer);
    if !path.exists() {
        println!(
            "{} No {} allowlist file found at {}",
            "Warning:".yellow(),
            layer.label(),
            path.display()
        );
        return Ok(());
    }

    let mut doc = load_or_create_allowlist_doc(&path)?;

    let removed = remove_rule_entry(&mut doc, &parsed_rule);
    if !removed {
        println!(
            "{} Rule {} not found in {} allowlist",
            "Warning:".yellow(),
            rule_id,
            layer.label()
        );
        return Ok(());
    }

    write_allowlist(&path, &doc)?;

    println!(
        "{} Removed {} from {} allowlist",
        "✓".green(),
        rule_id.cyan(),
        layer.label()
    );

    Ok(())
}

/// Validate allowlist entries.
fn allowlist_validate(
    project_only: bool,
    user_only: bool,
    strict: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    use colored::Colorize;

    let layers: Vec<AllowlistLayer> = if project_only {
        vec![AllowlistLayer::Project]
    } else if user_only {
        vec![AllowlistLayer::User]
    } else {
        vec![AllowlistLayer::Project, AllowlistLayer::User]
    };

    let mut errors = 0;
    let mut warnings = 0;

    // Load all allowlists once (more efficient than loading per-layer)
    let allowlist = crate::allowlist::load_default_allowlists();

    for layer in layers {
        let path = allowlist_path_for_layer(layer);
        if !path.exists() {
            continue;
        }

        println!("{} allowlist: {}", layer.label().bold(), path.display());

        for loaded in &allowlist.layers {
            if loaded.layer != layer {
                continue;
            }

            // Report parse errors
            for err in &loaded.file.errors {
                println!("  {} {}", "ERROR:".red(), err.message);
                errors += 1;
            }

            // Check entries
            for (idx, entry) in loaded.file.entries.iter().enumerate() {
                // Check for expired entries
                if let Some(expires_at) = &entry.expires_at {
                    if is_expired(expires_at) {
                        println!(
                            "  {} Entry {} is expired ({})",
                            "WARNING:".yellow(),
                            idx + 1,
                            expires_at
                        );
                        warnings += 1;
                    }
                }

                // Check for risky regex patterns without acknowledgement
                if matches!(entry.selector, AllowSelector::RegexPattern(_))
                    && !entry.risk_acknowledged
                {
                    println!(
                        "  {} Entry {} uses regex pattern without risk_acknowledged=true",
                        "WARNING:".yellow(),
                        idx + 1
                    );
                    warnings += 1;
                }

                // Check for overly broad wildcards
                if let AllowSelector::Rule(rule_id) = &entry.selector {
                    if rule_id.pack_id == "*" {
                        println!(
                            "  {} Entry {} uses global wildcard pack (dangerous)",
                            "ERROR:".red(),
                            idx + 1
                        );
                        errors += 1;
                    } else if rule_id.pattern_name == "*" {
                        println!(
                            "  {} Entry {} uses pack wildcard ({}:*)",
                            "WARNING:".yellow(),
                            idx + 1,
                            rule_id.pack_id
                        );
                        warnings += 1;
                    }
                }
            }
        }

        println!();
    }

    let total_issues = if strict { errors + warnings } else { errors };

    if total_issues == 0 {
        println!("{}", "All allowlist entries are valid.".green());
        Ok(())
    } else {
        let msg = format!(
            "{} error(s), {} warning(s)",
            errors.to_string().red(),
            warnings.to_string().yellow()
        );
        println!("{msg}");
        Err(format!("Validation failed: {errors} error(s), {warnings} warning(s)").into())
    }
}

/// Remove expired entries from selected allowlist files.
fn allowlist_prune(
    project_only: bool,
    user_only: bool,
    dry_run: bool,
    format: AllowlistOutputFormat,
) -> Result<(), Box<dyn std::error::Error>> {
    use colored::Colorize;

    let pruned = prune_allowlist_layers(project_only, user_only, dry_run)?;

    match format {
        AllowlistOutputFormat::Pretty => {
            if pruned.is_empty() {
                println!("{}", "No expired allowlist entries found.".green());
                return Ok(());
            }

            let action = if dry_run { "Would prune" } else { "Pruned" };
            println!(
                "{} {} expired allowlist entr{}",
                "✓".green(),
                action,
                if pruned.len() == 1 { "y" } else { "ies" }
            );
            println!();

            for entry in &pruned {
                println!(
                    "  {} {} [{}]",
                    entry.selector_kind,
                    entry.selector_value,
                    entry.layer.label()
                );
                if let Some(reason) = &entry.reason {
                    println!("    Reason: {reason}");
                }
                if let Some(expires_at) = &entry.expires_at {
                    println!("    Expires: {expires_at}");
                }
                if let Some(ttl) = &entry.ttl {
                    println!("    TTL: {ttl}");
                }
                println!("    File: {}", entry.path.display());
            }
        }
        AllowlistOutputFormat::Json => {
            let entries: Vec<serde_json::Value> = pruned
                .iter()
                .map(|entry| {
                    serde_json::json!({
                        "layer": entry.layer.label(),
                        "path": entry.path.display().to_string(),
                        "index": entry.index,
                        "selector": {
                            "type": &entry.selector_kind,
                            "value": &entry.selector_value,
                        },
                        "reason": &entry.reason,
                        "expires_at": &entry.expires_at,
                        "ttl": &entry.ttl,
                        "added_at": &entry.added_at,
                    })
                })
                .collect();

            let output = serde_json::json!({
                "dry_run": dry_run,
                "pruned": entries.len(),
                "entries": entries,
            });
            println!("{}", serde_json::to_string_pretty(&output)?);
        }
    }

    Ok(())
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct PrunedAllowlistEntry {
    index: usize,
    layer: AllowlistLayer,
    path: std::path::PathBuf,
    selector_kind: String,
    selector_value: String,
    reason: Option<String>,
    expires_at: Option<String>,
    ttl: Option<String>,
    added_at: Option<String>,
}

fn prune_allowlist_layers(
    project_only: bool,
    user_only: bool,
    dry_run: bool,
) -> Result<Vec<PrunedAllowlistEntry>, Box<dyn std::error::Error>> {
    let layers: Vec<AllowlistLayer> = if project_only {
        vec![AllowlistLayer::Project]
    } else if user_only {
        vec![AllowlistLayer::User]
    } else {
        vec![AllowlistLayer::Project, AllowlistLayer::User]
    };

    let mut pruned = Vec::new();

    for layer in layers {
        let path = allowlist_path_for_layer(layer);
        if !path.exists() {
            continue;
        }

        let mut doc = load_or_create_allowlist_doc(&path)?;
        let layer_pruned = prune_expired_allowlist_doc(&mut doc, layer, &path, dry_run);
        if !dry_run && !layer_pruned.is_empty() {
            write_allowlist(&path, &doc)?;
        }
        pruned.extend(layer_pruned);
    }

    Ok(pruned)
}

fn prune_expired_allowlist_doc(
    doc: &mut toml_edit::DocumentMut,
    layer: AllowlistLayer,
    path: &std::path::Path,
    dry_run: bool,
) -> Vec<PrunedAllowlistEntry> {
    let pruned = collect_expired_allowlist_entries(doc, layer, path);
    if dry_run || pruned.is_empty() {
        return pruned;
    }

    if let Some(arr) = doc
        .get_mut("allow")
        .and_then(toml_edit::Item::as_array_of_tables_mut)
    {
        for idx in pruned.iter().map(|entry| entry.index).rev() {
            arr.remove(idx);
        }
    }

    pruned
}

fn collect_expired_allowlist_entries(
    doc: &toml_edit::DocumentMut,
    layer: AllowlistLayer,
    path: &std::path::Path,
) -> Vec<PrunedAllowlistEntry> {
    let Some(arr) = doc
        .get("allow")
        .and_then(toml_edit::Item::as_array_of_tables)
    else {
        return Vec::new();
    };

    arr.iter()
        .enumerate()
        .filter_map(|(index, tbl)| {
            let expires_at = toml_item_string(tbl.get("expires_at"));
            let ttl = toml_item_string(tbl.get("ttl"));
            let added_at = toml_item_string(tbl.get("added_at"));

            if !crate::allowlist::is_expiration_expired(
                expires_at.as_deref(),
                ttl.as_deref(),
                added_at.as_deref(),
            ) {
                return None;
            }

            let (selector_kind, selector_value) = allowlist_table_selector(tbl);
            Some(PrunedAllowlistEntry {
                index,
                layer,
                path: path.to_path_buf(),
                selector_kind,
                selector_value,
                reason: toml_item_string(tbl.get("reason")),
                expires_at,
                ttl,
                added_at,
            })
        })
        .collect()
}

fn toml_item_string(item: Option<&toml_edit::Item>) -> Option<String> {
    let item = item?;
    if let Some(s) = item.as_str() {
        return Some(s.to_string());
    }
    item.as_datetime().map(ToString::to_string)
}

fn allowlist_table_selector(tbl: &toml_edit::Table) -> (String, String) {
    for (key, label) in [
        ("rule", "rule"),
        ("exact_command", "exact_command"),
        ("command_prefix", "command_prefix"),
        ("pattern", "pattern"),
    ] {
        if let Some(value) = toml_item_string(tbl.get(key)) {
            return (label.to_string(), value);
        }
    }

    ("unknown".to_string(), "<unknown>".to_string())
}

// ============================================================================
// TOML manipulation helpers (using toml_edit for stable formatting)
// ============================================================================

/// Load an existing allowlist file or create an empty document.
fn load_or_create_allowlist_doc(
    path: &std::path::Path,
) -> Result<toml_edit::DocumentMut, Box<dyn std::error::Error>> {
    if path.exists() {
        let content = std::fs::read_to_string(path)?;
        let doc: toml_edit::DocumentMut = content.parse()?;
        Ok(doc)
    } else {
        // Create new document with header comment
        let mut doc = toml_edit::DocumentMut::new();
        doc.as_table_mut().set_implicit(true);
        Ok(doc)
    }
}

/// Write the allowlist document back to disk atomically.
///
/// Uses a temp file + rename strategy to prevent corruption:
/// 1. Write content to a temp file in the same directory
/// 2. Validate the temp file parses correctly as TOML
/// 3. Atomically rename temp file to target path
///
/// This ensures that power loss or crash during write won't leave a
/// corrupted allowlist file.
fn write_allowlist(
    path: &std::path::Path,
    doc: &toml_edit::DocumentMut,
) -> Result<(), Box<dyn std::error::Error>> {
    use std::io::Write;

    // Create parent directory if needed
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }

    let content = doc.to_string();

    // Create temp file in same directory (required for atomic rename on same filesystem)
    let parent = path.parent().unwrap_or_else(|| std::path::Path::new("."));
    let temp_name = format!(".orca-allowlist-{}.tmp", std::process::id());
    let temp_path = parent.join(&temp_name);

    // Write to temp file
    {
        let mut temp_file = std::fs::File::create(&temp_path)?;
        temp_file.write_all(content.as_bytes())?;
        temp_file.sync_all()?; // Ensure data is flushed to disk
    }

    // Validate the temp file parses correctly before committing
    let verification = std::fs::read_to_string(&temp_path)?;
    if let Err(parse_err) = verification.parse::<toml_edit::DocumentMut>() {
        // Remove temp file on parse failure
        let _ = std::fs::remove_file(&temp_path);
        return Err(
            format!("Generated TOML failed validation (this is a bug): {parse_err}").into(),
        );
    }

    // Create a backup before replacing the file so we can recover from write failures.
    let backup_path = backup_allowlist_file(path)?;

    // Atomic rename (on Unix, this is atomic; on Windows, it replaces atomically)
    std::fs::rename(&temp_path, path)?;

    // Validate final file and roll back if needed.
    let final_content = std::fs::read_to_string(path)?;
    if let Err(parse_err) = final_content.parse::<toml_edit::DocumentMut>() {
        if let Some(ref backup_path) = backup_path {
            std::fs::copy(backup_path, path)?;
        }
        return Err(format!(
            "Final allowlist verification failed after write (rolled back): {parse_err}"
        )
        .into());
    }

    Ok(())
}

fn backup_allowlist_file(
    path: &std::path::Path,
) -> Result<Option<std::path::PathBuf>, Box<dyn std::error::Error>> {
    if !path.exists() {
        return Ok(None);
    }

    let filename = path
        .file_name()
        .and_then(std::ffi::OsStr::to_str)
        .unwrap_or("allowlist.toml");
    let backup_name = format!(
        "{}.bak.{}",
        filename,
        Utc::now().format("%Y%m%dT%H%M%S%.6fZ")
    );
    let backup_path = path.with_file_name(backup_name);
    std::fs::copy(path, &backup_path)?;
    Ok(Some(backup_path))
}

/// Check if a rule entry already exists in the document.
fn has_rule_entry(doc: &toml_edit::DocumentMut, rule_id: &RuleId) -> bool {
    let Some(allow) = doc.get("allow") else {
        return false;
    };
    let Some(arr) = allow.as_array_of_tables() else {
        return false;
    };

    let rule_str = rule_id.to_string();
    arr.iter().any(|tbl| {
        tbl.get("rule")
            .and_then(|v| v.as_str())
            .is_some_and(|s| s == rule_str)
    })
}

/// Check if an exact command entry already exists.
fn has_command_entry(doc: &toml_edit::DocumentMut, command: &str) -> bool {
    let Some(allow) = doc.get("allow") else {
        return false;
    };
    let Some(arr) = allow.as_array_of_tables() else {
        return false;
    };

    arr.iter().any(|tbl| {
        tbl.get("exact_command")
            .and_then(|v| v.as_str())
            .is_some_and(|s| s == command)
    })
}

/// Build a new rule entry as an inline table.
fn build_rule_entry(
    rule_id: &RuleId,
    reason: &str,
    expires: Option<&str>,
    conditions: &[String],
) -> toml_edit::Table {
    build_rule_entry_with_paths(rule_id, reason, expires, conditions, &[])
}

/// Build a new rule entry with optional path scoping.
fn build_rule_entry_with_paths(
    rule_id: &RuleId,
    reason: &str,
    expires: Option<&str>,
    conditions: &[String],
    paths: &[String],
) -> toml_edit::Table {
    let mut tbl = toml_edit::Table::new();

    tbl.insert("rule", toml_edit::value(rule_id.to_string()));
    tbl.insert("reason", toml_edit::value(reason));

    // Add audit metadata
    if let Some(user) = get_current_user() {
        tbl.insert("added_by", toml_edit::value(user));
    }
    tbl.insert("added_at", toml_edit::value(current_timestamp()));

    if let Some(exp) = expires {
        tbl.insert("expires_at", toml_edit::value(exp));
    }

    if !conditions.is_empty() {
        let mut cond_tbl = toml_edit::InlineTable::new();
        for cond in conditions {
            if let Some((k, v)) = cond.split_once('=') {
                cond_tbl.insert(k.trim(), v.trim().into());
            }
        }
        tbl.insert("conditions", toml_edit::Item::Value(cond_tbl.into()));
    }

    if !paths.is_empty() {
        let mut path_array = toml_edit::Array::new();
        for path in paths {
            path_array.push(path.as_str());
        }
        tbl.insert("paths", toml_edit::Item::Value(path_array.into()));
    }

    tbl
}

/// Build a new exact command entry.
fn build_command_entry(command: &str, reason: &str, expires: Option<&str>) -> toml_edit::Table {
    build_command_entry_with_paths(command, reason, expires, &[])
}

/// Build a new exact command entry with optional path scoping.
fn build_command_entry_with_paths(
    command: &str,
    reason: &str,
    expires: Option<&str>,
    paths: &[String],
) -> toml_edit::Table {
    let mut tbl = toml_edit::Table::new();

    tbl.insert("exact_command", toml_edit::value(command));
    tbl.insert("reason", toml_edit::value(reason));

    // Add audit metadata
    if let Some(user) = get_current_user() {
        tbl.insert("added_by", toml_edit::value(user));
    }
    tbl.insert("added_at", toml_edit::value(current_timestamp()));

    if let Some(exp) = expires {
        tbl.insert("expires_at", toml_edit::value(exp));
    }

    if !paths.is_empty() {
        let mut path_array = toml_edit::Array::new();
        for path in paths {
            path_array.push(path.as_str());
        }
        tbl.insert("paths", toml_edit::Item::Value(path_array.into()));
    }

    tbl
}

/// Build a new pattern entry for a regex-based allowlist (from suggest-allowlist).
///
/// Pattern entries require `risk_acknowledged = true` because they use regex matching.
fn build_pattern_entry(
    pattern: &str,
    reason: &str,
    risk_level: &str,
    confidence_tier: &str,
    frequency: usize,
    unique_variants: usize,
) -> toml_edit::Table {
    let mut tbl = toml_edit::Table::new();

    tbl.insert("pattern", toml_edit::value(pattern));

    // Build a descriptive reason with metadata
    let full_reason = format!(
        "{reason} (auto-suggested: {confidence_tier} confidence, {risk_level} risk, {frequency} occurrences, {unique_variants} variants)"
    );
    tbl.insert("reason", toml_edit::value(full_reason));

    // Add audit metadata
    if let Some(user) = get_current_user() {
        tbl.insert("added_by", toml_edit::value(user));
    }
    tbl.insert("added_at", toml_edit::value(current_timestamp()));

    // Pattern-based allowlist entries MUST acknowledge risk
    tbl.insert("risk_acknowledged", toml_edit::value(true));

    tbl
}

/// Check if a pattern entry already exists in the document.
fn has_pattern_entry(doc: &toml_edit::DocumentMut, pattern: &str) -> bool {
    let Some(allow) = doc.get("allow") else {
        return false;
    };
    let Some(arr) = allow.as_array_of_tables() else {
        return false;
    };

    arr.iter().any(|tbl| {
        tbl.get("pattern")
            .and_then(|v| v.as_str())
            .is_some_and(|s| s == pattern)
    })
}

/// Add a regex pattern to the allowlist (from suggest-allowlist).
///
/// Returns Ok(path) on success, or Err on failure.
fn allowlist_add_pattern(
    pattern: &str,
    reason: &str,
    risk_level: &str,
    confidence_tier: &str,
    frequency: usize,
    unique_variants: usize,
) -> Result<std::path::PathBuf, Box<dyn std::error::Error>> {
    // Determine layer: prefer project if in a git repo, else user
    let layer = if find_repo_root_from_cwd().is_some() {
        AllowlistLayer::Project
    } else {
        AllowlistLayer::User
    };

    let path = allowlist_path_for_layer(layer);
    let mut doc = load_or_create_allowlist_doc(&path)?;

    // Check for duplicate
    if has_pattern_entry(&doc, pattern) {
        return Err(format!(
            "Pattern '{}' already exists in {} allowlist",
            pattern,
            layer.label()
        )
        .into());
    }

    // Build and append entry
    let entry = build_pattern_entry(
        pattern,
        reason,
        risk_level,
        confidence_tier,
        frequency,
        unique_variants,
    );
    append_entry(&mut doc, entry);

    // Write atomically (temp file + rename to prevent corruption)
    write_allowlist(&path, &doc)?;

    Ok(path)
}

/// Result of pattern conflict detection.
#[derive(Debug, Default)]
pub struct PatternConflictCheck {
    /// True if the pattern may conflict with existing block overrides.
    pub conflicts_with_blocks: bool,
    /// Human-readable warning message if conflicts exist.
    pub block_conflict_warning: Option<String>,
    /// True if the pattern is overly broad (contains unconstrained wildcards).
    pub is_overly_broad: bool,
    /// Human-readable suggestion for refinement if too broad.
    pub refinement_suggestion: Option<String>,
}

/// Check if a suggested pattern has potential conflicts or issues.
///
/// This function performs two checks:
/// 1. Does this pattern potentially overlap with any configured block overrides?
/// 2. Is this pattern overly broad (contains .* or .+ without anchoring)?
///
/// These are informational warnings - they don't prevent adding the pattern.
fn check_pattern_conflicts(pattern: &str, config: &Config) -> PatternConflictCheck {
    let mut result = PatternConflictCheck::default();

    // Check for overly broad patterns
    // A pattern is "overly broad" if it uses .* or .+ without anchors
    let has_unanchored_wildcard = (pattern.contains(".*") || pattern.contains(".+"))
        && !pattern.starts_with('^')
        && !pattern.ends_with('$');

    if has_unanchored_wildcard {
        result.is_overly_broad = true;
        result.refinement_suggestion = Some(
            "Consider adding anchors (^ and $) or more specific token patterns \
             to avoid matching unintended commands."
                .to_string(),
        );
    }

    // Check for conflicts with block overrides
    // We compile the pattern and see if any of the block patterns would match
    // the same space. This is a heuristic check.
    let compiled_overrides = config.overrides.compile();
    if compiled_overrides.block.is_empty() {
        return result;
    }

    // For each block pattern, check if there's textual overlap
    // This is a simple heuristic: we look for common substrings
    let pattern_lower = pattern.to_lowercase();
    for block in &compiled_overrides.block {
        let block_pattern_lower = block.pattern.to_lowercase();

        // Check for substring overlap in the pattern text
        // This is imperfect but catches obvious cases
        let overlap = find_pattern_overlap(&pattern_lower, &block_pattern_lower);
        if overlap {
            result.conflicts_with_blocks = true;
            result.block_conflict_warning = Some(format!(
                "This pattern may conflict with block override: '{}' ({})",
                block.pattern, block.reason
            ));
            break;
        }
    }

    result
}

/// Check for textual overlap between two regex patterns.
///
/// This is a heuristic check that looks for common literal substrings
/// that might indicate the patterns could match overlapping commands.
fn find_pattern_overlap(pattern1: &str, pattern2: &str) -> bool {
    // Extract literal tokens from patterns (words, commands)
    let tokens1: Vec<&str> = pattern1
        .split(|c: char| !c.is_alphanumeric() && c != '-' && c != '_')
        .filter(|s| s.len() >= 3) // Only consider meaningful tokens
        .collect();

    let tokens2: Vec<&str> = pattern2
        .split(|c: char| !c.is_alphanumeric() && c != '-' && c != '_')
        .filter(|s| s.len() >= 3)
        .collect();

    // Check for any common tokens
    for t1 in &tokens1 {
        for t2 in &tokens2 {
            if t1 == t2 {
                return true;
            }
        }
    }

    false
}

/// Handle the --undo flag for suggest-allowlist.
///
/// Removes auto-suggested pattern entries that were added within the last N minutes.
/// This allows users to undo patterns they accepted by mistake.
fn handle_suggest_allowlist_undo(minutes: u32) -> Result<(), Box<dyn std::error::Error>> {
    use colored::Colorize;

    let cutoff = Utc::now() - chrono::Duration::minutes(i64::from(minutes));

    // Check both project and user allowlists
    let layers_to_check = [
        (
            AllowlistLayer::Project,
            find_repo_root_from_cwd().map(|r| r.join(".orca").join("allowlist.toml")),
        ),
        (
            AllowlistLayer::User,
            dirs::config_dir().map(|d| d.join("orca").join("allowlist.toml")),
        ),
    ];

    let mut total_removed = 0;

    for (layer, path_opt) in layers_to_check {
        let Some(path) = path_opt else {
            continue;
        };

        if !path.exists() {
            continue;
        }

        let Ok(mut doc) = load_or_create_allowlist_doc(&path) else {
            continue;
        };

        let removed = remove_auto_suggested_entries(&mut doc, cutoff);
        if removed > 0 {
            write_allowlist(&path, &doc)?;
            println!(
                "{} Removed {} auto-suggested pattern(s) from {} allowlist ({})",
                "✓".green(),
                removed,
                layer.label(),
                path.display()
            );
            total_removed += removed;
        }
    }

    if total_removed == 0 {
        println!("No auto-suggested patterns found added in the last {minutes} minutes.");
        println!();
        println!("Patterns are identified by:");
        println!("  - Having 'auto-suggested' in the reason field");
        println!("  - Having an added_at timestamp within the time window");
    } else {
        println!();
        println!("Total: {total_removed} pattern(s) removed.");
    }

    Ok(())
}

/// Remove auto-suggested entries added after the cutoff time.
///
/// Returns the number of entries removed.
fn remove_auto_suggested_entries(
    doc: &mut toml_edit::DocumentMut,
    cutoff: chrono::DateTime<Utc>,
) -> usize {
    let Some(allow) = doc.get_mut("allow") else {
        return 0;
    };
    let Some(arr) = allow.as_array_of_tables_mut() else {
        return 0;
    };

    let initial_len = arr.len();

    // Find indices to remove (reverse order to avoid index shifting)
    let mut remove_indices: Vec<usize> = Vec::new();
    for (idx, tbl) in arr.iter().enumerate() {
        // Check if it's an auto-suggested pattern entry
        let is_pattern = tbl.get("pattern").is_some();
        let is_auto_suggested = tbl
            .get("reason")
            .and_then(|v| v.as_str())
            .is_some_and(|r| r.contains("auto-suggested"));

        if !is_pattern || !is_auto_suggested {
            continue;
        }

        // Check the added_at timestamp
        let added_at = tbl.get("added_at").and_then(|v| v.as_str());
        if let Some(timestamp) = added_at {
            if let Ok(dt) = chrono::DateTime::parse_from_rfc3339(timestamp) {
                if dt >= cutoff {
                    remove_indices.push(idx);
                }
            }
        }
    }

    // Remove in reverse order to maintain correct indices
    for idx in remove_indices.into_iter().rev() {
        arr.remove(idx);
    }

    initial_len - arr.len()
}

/// Append an entry to the [[allow]] array.
fn append_entry(doc: &mut toml_edit::DocumentMut, entry: toml_edit::Table) {
    // Get or create the [[allow]] array of tables
    let allow = doc
        .entry("allow")
        .or_insert_with(|| toml_edit::Item::ArrayOfTables(toml_edit::ArrayOfTables::new()));

    if let Some(arr) = allow.as_array_of_tables_mut() {
        arr.push(entry);
    }
}

/// Remove a rule entry from the document. Returns true if removed.
fn remove_rule_entry(doc: &mut toml_edit::DocumentMut, rule_id: &RuleId) -> bool {
    let Some(allow) = doc.get_mut("allow") else {
        return false;
    };
    let Some(arr) = allow.as_array_of_tables_mut() else {
        return false;
    };

    let rule_str = rule_id.to_string();
    let initial_len = arr.len();

    // Find the index to remove
    let mut remove_idx = None;
    for (idx, tbl) in arr.iter().enumerate() {
        if tbl
            .get("rule")
            .and_then(|v| v.as_str())
            .is_some_and(|s| s == rule_str)
        {
            remove_idx = Some(idx);
            break;
        }
    }

    if let Some(idx) = remove_idx {
        arr.remove(idx);
    }

    arr.len() < initial_len
}

/// Get the current user (from environment or whoami).
fn get_current_user() -> Option<String> {
    std::env::var("USER")
        .or_else(|_| std::env::var("USERNAME"))
        .ok()
}

/// Get current timestamp in RFC 3339 format.
fn current_timestamp() -> String {
    chrono::Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string()
}

/// Check if a timestamp string is expired.
fn is_expired(timestamp: &str) -> bool {
    // Try to parse as RFC 3339
    if let Ok(dt) = chrono::DateTime::parse_from_rfc3339(timestamp) {
        return dt < chrono::Utc::now();
    }
    // Try simpler formats
    if let Ok(dt) = chrono::NaiveDateTime::parse_from_str(timestamp, "%Y-%m-%dT%H:%M:%S") {
        let utc = dt.and_utc();
        return utc < chrono::Utc::now();
    }
    // Fail-closed: treat unparseable timestamps as expired for security.
    // This prevents entries with corrupted/invalid timestamps from persisting indefinitely.
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    struct BatchEvalContext {
        enabled_keywords: Vec<&'static str>,
        ordered_packs: Vec<String>,
        keyword_index: Option<crate::packs::EnabledKeywordIndex>,
        compiled_overrides: crate::config::CompiledOverrides,
        allowlists: crate::allowlist::LayeredAllowlist,
        heredoc_settings: crate::config::HeredocSettings,
    }

    fn build_batch_eval_context() -> BatchEvalContext {
        let config = Config::default();
        let compiled_overrides = config.overrides.compile();
        let allowlists = crate::allowlist::LayeredAllowlist::default();
        let heredoc_settings = config.heredoc_settings();
        let enabled_packs = config.enabled_pack_ids();
        let enabled_keywords = REGISTRY.collect_enabled_keywords(&enabled_packs);
        let ordered_packs = REGISTRY.expand_enabled_ordered(&enabled_packs);
        let keyword_index = REGISTRY.build_enabled_keyword_index(&ordered_packs);

        BatchEvalContext {
            enabled_keywords,
            ordered_packs,
            keyword_index,
            compiled_overrides,
            allowlists,
            heredoc_settings,
        }
    }

    fn process_batch_lines(lines: &[&str]) -> Vec<BatchHookOutput> {
        let ctx = build_batch_eval_context();
        lines
            .iter()
            .enumerate()
            .map(|(index, line)| {
                evaluate_batch_line(
                    index,
                    line,
                    &ctx.enabled_keywords,
                    &ctx.ordered_packs,
                    ctx.keyword_index.as_ref(),
                    &ctx.compiled_overrides,
                    &ctx.allowlists,
                    &ctx.heredoc_settings,
                    true,
                )
            })
            .collect()
    }

    fn make_orca_entry() -> serde_json::Value {
        serde_json::json!({
            "matcher": "Bash",
            "hooks": [{
                "type": "command",
                "command": "orca"
            }]
        })
    }

    fn entry_has_hook_command(entry: &serde_json::Value, command: &str) -> bool {
        entry
            .get("hooks")
            .and_then(|h| h.as_array())
            .is_some_and(|hooks| {
                hooks.iter().any(|hook| {
                    hook.get("command")
                        .and_then(|c| c.as_str())
                        .is_some_and(|c| c == command)
                })
            })
    }

    #[test]
    fn install_into_settings_creates_structure() {
        let mut settings = serde_json::json!({});
        let changed = install_orca_hook_into_settings(&mut settings, false).expect("install ok");
        assert!(changed);

        let pre = settings
            .get("hooks")
            .and_then(|h| h.get("PreToolUse"))
            .and_then(|arr| arr.as_array())
            .expect("PreToolUse array exists");
        assert_eq!(pre.len(), 1);
        assert!(is_orca_hook_entry(&pre[0]));
    }

    #[test]
    fn install_into_settings_does_not_duplicate_without_force() {
        let mut settings = serde_json::json!({
            "hooks": { "PreToolUse": [ make_orca_entry() ] }
        });

        let changed = install_orca_hook_into_settings(&mut settings, false).expect("install ok");
        assert!(!changed, "should detect existing hook");

        let pre = settings
            .get("hooks")
            .and_then(|h| h.get("PreToolUse"))
            .and_then(|arr| arr.as_array())
            .unwrap();
        assert_eq!(pre.iter().filter(|e| is_orca_hook_entry(e)).count(), 1);
    }

    #[test]
    fn install_into_settings_inserts_orca_before_existing_hooks() {
        let other = serde_json::json!({
            "matcher": "Bash",
            "hooks": [{ "type": "command", "command": "other-hook" }]
        });
        let mut settings = serde_json::json!({
            "hooks": { "PreToolUse": [ other ] }
        });

        let changed = install_orca_hook_into_settings(&mut settings, false).expect("install ok");
        assert!(changed);

        let pre = settings["hooks"]["PreToolUse"].as_array().unwrap();
        assert!(is_orca_hook_entry(&pre[0]), "orca hook should run first");
        assert!(entry_has_hook_command(&pre[1], "other-hook"));
    }

    #[test]
    fn install_into_settings_force_reinstalls_single_entry() {
        let other = serde_json::json!({
            "matcher": "Bash",
            "hooks": [{ "type": "command", "command": "other-hook" }]
        });
        let mut settings = serde_json::json!({
            "hooks": { "PreToolUse": [ make_orca_entry(), other ] }
        });

        let changed = install_orca_hook_into_settings(&mut settings, true).expect("install ok");
        assert!(changed);

        let pre = settings["hooks"]["PreToolUse"].as_array().unwrap();
        assert_eq!(pre.iter().filter(|e| is_orca_hook_entry(e)).count(), 1);
        assert!(is_orca_hook_entry(&pre[0]), "orca hook should run first");
        assert!(
            pre.iter().any(|e| entry_has_hook_command(e, "other-hook")),
            "should retain other hook entry"
        );
    }

    #[test]
    fn install_into_settings_force_preserves_coexisting_hook_in_same_entry() {
        let mut settings = serde_json::json!({
            "hooks": {
                "PreToolUse": [{
                    "matcher": "Bash",
                    "hooks": [
                        { "type": "command", "command": "orca" },
                        { "type": "command", "command": "other-hook" }
                    ]
                }]
            }
        });

        let changed = install_orca_hook_into_settings(&mut settings, true).expect("install ok");
        assert!(changed);

        let pre = settings["hooks"]["PreToolUse"].as_array().unwrap();
        assert_eq!(pre.iter().filter(|e| is_orca_hook_entry(e)).count(), 1);
        assert!(is_orca_hook_entry(&pre[0]), "orca hook should run first");
        assert!(
            pre.iter().any(|e| entry_has_hook_command(e, "other-hook")),
            "force reinstall should retain non-orca hooks from mixed hook entries"
        );
    }

    #[test]
    fn install_into_settings_errors_on_invalid_pre_tool_use_type() {
        let mut settings = serde_json::json!({
            "hooks": { "PreToolUse": { "not": "an array" } }
        });
        let err = install_orca_hook_into_settings(&mut settings, false).expect_err("should error");
        assert!(err.to_string().contains("PreToolUse"));
    }

    #[test]
    fn test_cli_parse_no_args() {
        let cli = Cli::parse_from(["orca"]);
        assert!(cli.command.is_none());
    }

    #[test]
    fn test_cli_parse_packs() {
        let cli = Cli::parse_from(["orca", "packs"]);
        assert!(matches!(cli.command, Some(Command::ListPacks { .. })));
    }

    #[test]
    fn test_cli_parse_packs_verbose() {
        // Tests that `--verbose` with packs command uses the global verbose flag
        let cli = Cli::parse_from(["orca", "packs", "--verbose"]);
        assert!(matches!(cli.command, Some(Command::ListPacks { .. })));
        assert_eq!(cli.verbose, 1); // Global verbose flag should be set
    }

    #[test]
    fn test_cli_parse_packs_pattern_tree_controls() {
        let cli = Cli::parse_from(["orca", "packs", "--expand", "--max-patterns", "6"]);
        if let Some(Command::ListPacks {
            expand,
            max_patterns,
            ..
        }) = cli.command
        {
            assert!(expand);
            assert_eq!(max_patterns, 6);
        } else {
            unreachable!("Expected ListPacks");
        }
    }

    #[test]
    fn test_cli_parse_pack_info() {
        let cli = Cli::parse_from(["orca", "pack", "info", "core.git"]);
        if let Some(Command::Pack {
            action: PackAction::Info { pack_id, .. },
        }) = cli.command
        {
            assert_eq!(pack_id, "core.git");
        } else {
            unreachable!("Expected Pack Info command");
        }
    }

    #[test]
    fn test_cli_parse_test() {
        let cli = Cli::parse_from(["orca", "test", "git reset --hard"]);
        if let Some(Command::TestCommand { command, .. }) = cli.command {
            assert_eq!(command, "git reset --hard");
        } else {
            unreachable!("Expected TestCommand command");
        }
    }

    // ========================================================================
    // Batch hook mode tests
    // ========================================================================

    #[test]
    fn test_batch_processes_multiple_commands() {
        let lines = [
            r#"{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}"#,
            r#"{"tool_name":"Bash","tool_input":{"command":"git status"}}"#,
        ];
        let results = process_batch_lines(&lines);

        assert_eq!(results.len(), 2);
        assert_eq!(results[0].index, 0);
        assert_eq!(results[1].index, 1);
        assert_eq!(results[0].decision, "deny");
        assert_eq!(results[1].decision, "allow");
    }

    #[test]
    fn test_batch_maintains_order() {
        let lines = [
            r#"{"tool_name":"Bash","tool_input":{"command":"git status"}}"#,
            r#"{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}"#,
            r#"{"tool_name":"Bash","tool_input":{"command":"git log"}}"#,
        ];
        let results = process_batch_lines(&lines);

        let indices: Vec<usize> = results.iter().map(|r| r.index).collect();
        assert_eq!(indices, vec![0, 1, 2]);
        assert_eq!(results[0].decision, "allow");
        assert_eq!(results[1].decision, "deny");
        assert_eq!(results[2].decision, "allow");
    }

    #[test]
    fn test_batch_handles_malformed_line() {
        let lines = [
            "not json",
            r#"{"tool_name":"Bash","tool_input":{"command":"git status"}}"#,
        ];
        let results = process_batch_lines(&lines);

        assert_eq!(results.len(), 2);
        assert_eq!(results[0].decision, "error");
        assert!(
            results[0]
                .error
                .as_deref()
                .unwrap_or("")
                .contains("JSON parse error")
        );
        assert_eq!(results[1].decision, "allow");
    }

    #[test]
    fn test_batch_skips_non_bash() {
        let lines = [r#"{"tool_name":"Read","tool_input":{"command":"git status"}}"#];
        let results = process_batch_lines(&lines);

        assert_eq!(results.len(), 1);
        assert_eq!(results[0].decision, "skip");
        assert!(
            results[0]
                .error
                .as_deref()
                .unwrap_or("")
                .contains("supported shell tool")
        );
    }

    #[test]
    fn test_batch_accepts_copilot_hook_input() {
        let lines = [
            r#"{"event":"pre-tool-use","toolName":"run_shell_command","toolInput":{"command":"rm -rf /"}}"#,
        ];
        let results = process_batch_lines(&lines);

        assert_eq!(results.len(), 1);
        assert_eq!(results[0].decision, "deny");
    }

    #[test]
    fn test_batch_handles_large_input() {
        let line = r#"{"tool_name":"Bash","tool_input":{"command":"git status"}}"#;
        let lines: Vec<&str> = std::iter::repeat_n(line, 1000).collect();
        let results = process_batch_lines(&lines);

        assert_eq!(results.len(), 1000);
        assert!(results.iter().all(|r| r.decision == "allow"));
    }

    // ========================================================================
    // Allowlist CLI tests
    // ========================================================================

    #[test]
    fn test_cli_parse_allowlist_add() {
        let cli = Cli::parse_from([
            "orca",
            "allowlist",
            "add",
            "core.git:reset-hard",
            "-r",
            "Testing reset workflow",
        ]);
        if let Some(Command::Allowlist {
            action: AllowlistAction::Add {
                rule_id, reason, ..
            },
        }) = cli.command
        {
            assert_eq!(rule_id, "core.git:reset-hard");
            assert_eq!(reason, "Testing reset workflow");
        } else {
            unreachable!("Expected Allowlist Add command");
        }
    }

    #[test]
    fn test_cli_parse_allowlist_add_with_paths() {
        let cli = Cli::parse_from([
            "orca",
            "allowlist",
            "add",
            "core.git:reset-hard",
            "-r",
            "Scoped override",
            "--path",
            "/workspace/project",
            "--path",
            "/workspace/project/subdir/**",
        ]);
        if let Some(Command::Allowlist {
            action: AllowlistAction::Add { paths, .. },
        }) = cli.command
        {
            assert_eq!(
                paths,
                vec![
                    "/workspace/project".to_string(),
                    "/workspace/project/subdir/**".to_string()
                ]
            );
        } else {
            unreachable!("Expected Allowlist Add command with paths");
        }
    }

    #[test]
    fn test_cli_parse_allow_shortcut() {
        let cli = Cli::parse_from([
            "orca",
            "allow",
            "core.git:push-force",
            "-r",
            "CI force push",
            "--user",
        ]);
        if let Some(Command::Allow {
            rule_id,
            reason,
            user,
            project,
            ..
        }) = cli.command
        {
            assert_eq!(rule_id, "core.git:push-force");
            assert_eq!(reason, "CI force push");
            assert!(user);
            assert!(!project);
        } else {
            unreachable!("Expected Allow command");
        }
    }

    #[test]
    fn test_cli_parse_unallow_shortcut() {
        let cli = Cli::parse_from(["orca", "unallow", "core.git:reset-hard", "--project"]);
        if let Some(Command::Unallow {
            rule_id,
            project,
            user,
        }) = cli.command
        {
            assert_eq!(rule_id, "core.git:reset-hard");
            assert!(project);
            assert!(!user);
        } else {
            unreachable!("Expected Unallow command");
        }
    }

    #[test]
    fn test_cli_parse_allowlist_list() {
        let cli = Cli::parse_from(["orca", "allowlist", "list", "--format", "json"]);
        if let Some(Command::Allowlist {
            action: AllowlistAction::List { format, .. },
        }) = cli.command
        {
            assert_eq!(format, AllowlistOutputFormat::Json);
        } else {
            unreachable!("Expected Allowlist List command");
        }
    }

    #[test]
    fn test_cli_parse_allowlist_validate() {
        let cli = Cli::parse_from(["orca", "allowlist", "validate", "--strict"]);
        if let Some(Command::Allowlist {
            action: AllowlistAction::Validate { strict, .. },
        }) = cli.command
        {
            assert!(strict);
        } else {
            unreachable!("Expected Allowlist Validate command");
        }
    }

    #[test]
    fn test_cli_parse_allowlist_prune() {
        let cli = Cli::parse_from([
            "orca",
            "allowlist",
            "prune",
            "--dry-run",
            "--user",
            "--format",
            "json",
        ]);
        if let Some(Command::Allowlist {
            action:
                AllowlistAction::Prune {
                    dry_run,
                    user,
                    format,
                    ..
                },
        }) = cli.command
        {
            assert!(dry_run);
            assert!(user);
            assert_eq!(format, AllowlistOutputFormat::Json);
        } else {
            unreachable!("Expected Allowlist Prune command");
        }
    }

    #[test]
    fn test_cli_parse_allowlist_add_command() {
        let cli = Cli::parse_from([
            "orca",
            "allowlist",
            "add-command",
            "git push --force origin main",
            "-r",
            "Release workflow",
        ]);
        if let Some(Command::Allowlist {
            action: AllowlistAction::AddCommand {
                command, reason, ..
            },
        }) = cli.command
        {
            assert_eq!(command, "git push --force origin main");
            assert_eq!(reason, "Release workflow");
        } else {
            unreachable!("Expected Allowlist AddCommand command");
        }
    }

    #[test]
    fn test_cli_parse_allowlist_add_command_with_paths() {
        let cli = Cli::parse_from([
            "orca",
            "allowlist",
            "add-command",
            "git push --force origin main",
            "-r",
            "Release workflow",
            "--path",
            "/workspace/project",
        ]);
        if let Some(Command::Allowlist {
            action: AllowlistAction::AddCommand { paths, .. },
        }) = cli.command
        {
            assert_eq!(paths, vec!["/workspace/project".to_string()]);
        } else {
            unreachable!("Expected Allowlist AddCommand command with paths");
        }
    }

    #[test]
    fn test_cli_parse_allow_once() {
        let cli = Cli::parse_from([
            "orca",
            "allow-once",
            "ab12",
            "--single-use",
            "--dry-run",
            "--yes",
            "--pick",
            "2",
        ]);
        if let Some(Command::AllowOnce(cmd)) = cli.command {
            assert_eq!(cmd.code.as_deref(), Some("ab12"));
            assert!(cmd.action.is_none());
            assert!(cmd.single_use);
            assert!(cmd.dry_run);
            assert!(cmd.yes);
            assert_eq!(cmd.pick, Some(2));
        } else {
            unreachable!("Expected AllowOnce command");
        }
    }

    #[test]
    fn test_cli_parse_allow_once_list() {
        let cli = Cli::parse_from(["orca", "allow-once", "list"]);
        if let Some(Command::AllowOnce(cmd)) = cli.command {
            assert!(matches!(cmd.action, Some(AllowOnceAction::List)));
        } else {
            unreachable!("Expected AllowOnce list command");
        }
    }

    #[test]
    fn test_cli_parse_allow_once_revoke_with_global_flags_after_subcommand() {
        let cli = Cli::parse_from([
            "orca",
            "allow-once",
            "revoke",
            "deadbeef",
            "--yes",
            "--json",
        ]);
        if let Some(Command::AllowOnce(cmd)) = cli.command {
            assert!(cmd.yes);
            assert!(cmd.json);
            assert!(matches!(cmd.action, Some(AllowOnceAction::Revoke(_))));
        } else {
            unreachable!("Expected AllowOnce revoke command");
        }
    }

    #[test]
    fn test_allowlist_toml_helpers() {
        // Test building a rule entry
        let rule_id = RuleId::parse("core.git:reset-hard").unwrap();
        let entry = build_rule_entry(&rule_id, "test", None, &[]);
        assert!(entry.get("rule").is_some());
        assert!(entry.get("reason").is_some());
        assert!(entry.get("added_at").is_some());

        // Test building entry with expiration
        let entry_with_exp = build_rule_entry(&rule_id, "test", Some("2030-01-01T00:00:00Z"), &[]);
        assert!(entry_with_exp.get("expires_at").is_some());

        // Test building entry with conditions
        let entry_with_cond = build_rule_entry(&rule_id, "test", None, &["CI=true".to_string()]);
        assert!(entry_with_cond.get("conditions").is_some());
    }

    #[test]
    fn test_allowlist_toml_helpers_with_paths() {
        let rule_id = RuleId::parse("core.git:reset-hard").unwrap();
        let path_scoped_rule = build_rule_entry_with_paths(
            &rule_id,
            "path scoped",
            None,
            &[],
            &["/workspace/project".to_string()],
        );
        assert!(path_scoped_rule.get("paths").is_some());

        let path_scoped_command = build_command_entry_with_paths(
            "git reset --hard HEAD~1",
            "path scoped command",
            None,
            &["/workspace/project/subdir/**".to_string()],
        );
        assert!(path_scoped_command.get("paths").is_some());
    }

    #[test]
    fn test_is_expired() {
        // Past date should be expired
        assert!(is_expired("2020-01-01T00:00:00Z"));
        // Future date should not be expired
        assert!(!is_expired("2099-12-31T23:59:59Z"));
        // Invalid date IS considered expired (fail-closed for security)
        // This prevents entries with corrupted timestamps from persisting indefinitely
        assert!(is_expired("not-a-date"));
    }

    // ========================================================================
    // Allowlist E2E / Idempotence tests (git_safety_guard-1gt.2.5)
    // ========================================================================

    #[test]
    fn allowlist_add_creates_file_and_entry() {
        use tempfile::TempDir;
        let temp = TempDir::new().unwrap();
        let path = temp.path().join("allowlist.toml");

        // File should not exist yet
        assert!(!path.exists());

        // Load or create, add entry, write
        let mut doc = load_or_create_allowlist_doc(&path).unwrap();
        let rule = RuleId::parse("core.git:reset-hard").unwrap();
        let entry = build_rule_entry(&rule, "test", None, &[]);
        append_entry(&mut doc, entry);
        write_allowlist(&path, &doc).unwrap();

        // File should now exist with content
        assert!(path.exists());
        let content = std::fs::read_to_string(&path).unwrap();
        assert!(content.contains("core.git:reset-hard"));
        assert!(content.contains("reason = \"test\""));
    }

    #[test]
    fn write_allowlist_creates_backup_when_overwriting() {
        use tempfile::TempDir;

        let temp = TempDir::new().unwrap();
        let path = temp.path().join("allowlist.toml");
        std::fs::write(
            &path,
            "[[allow]]\nrule = \"core.git:reset-hard\"\nreason = \"old\"\n",
        )
        .unwrap();

        let mut doc = load_or_create_allowlist_doc(&path).unwrap();
        let rule = RuleId::parse("core.git:clean-force").unwrap();
        let entry = build_rule_entry(&rule, "new", None, &[]);
        append_entry(&mut doc, entry);
        write_allowlist(&path, &doc).unwrap();

        let backup_count = std::fs::read_dir(temp.path())
            .unwrap()
            .filter_map(Result::ok)
            .map(|entry| entry.file_name().to_string_lossy().into_owned())
            .filter(|name| name.starts_with("allowlist.toml.bak."))
            .count();
        assert_eq!(backup_count, 1, "exactly one backup should be created");
    }

    #[test]
    fn allowlist_add_is_idempotent_via_duplicate_check() {
        use tempfile::TempDir;
        let temp = TempDir::new().unwrap();
        let path = temp.path().join("allowlist.toml");

        let rule = RuleId::parse("core.git:push-force").unwrap();

        // Add first entry
        let mut doc = load_or_create_allowlist_doc(&path).unwrap();
        let entry = build_rule_entry(&rule, "first", None, &[]);
        append_entry(&mut doc, entry);
        write_allowlist(&path, &doc).unwrap();

        // has_rule_entry should detect duplicate
        let doc2 = load_or_create_allowlist_doc(&path).unwrap();
        assert!(has_rule_entry(&doc2, &rule), "should detect existing rule");

        // Count entries - should only have 1
        let allow_array = doc2.get("allow").and_then(|v| v.as_array_of_tables());
        assert_eq!(allow_array.map_or(0, toml_edit::ArrayOfTables::len), 1);
    }

    #[test]
    fn allowlist_remove_deletes_matching_entry() {
        use tempfile::TempDir;
        let temp = TempDir::new().unwrap();
        let path = temp.path().join("allowlist.toml");

        let rule = RuleId::parse("core.git:clean-force").unwrap();

        // Add entry
        let mut doc = load_or_create_allowlist_doc(&path).unwrap();
        let entry = build_rule_entry(&rule, "to be removed", None, &[]);
        append_entry(&mut doc, entry);
        write_allowlist(&path, &doc).unwrap();

        // Verify it exists
        let doc_before = load_or_create_allowlist_doc(&path).unwrap();
        assert!(
            has_rule_entry(&doc_before, &rule),
            "should have existing rule"
        );

        // Remove it
        let mut doc_to_modify = load_or_create_allowlist_doc(&path).unwrap();
        let removed = remove_rule_entry(&mut doc_to_modify, &rule);
        assert!(removed, "should have removed entry");
        write_allowlist(&path, &doc_to_modify).unwrap();

        // Verify it's gone
        let doc_after = load_or_create_allowlist_doc(&path).unwrap();
        assert!(
            !has_rule_entry(&doc_after, &rule),
            "should not have existing rule"
        );
    }

    #[test]
    fn allowlist_remove_nonexistent_returns_false() {
        use tempfile::TempDir;
        let temp = TempDir::new().unwrap();
        let path = temp.path().join("allowlist.toml");

        let rule = RuleId::parse("core.git:nonexistent").unwrap();

        // Create empty allowlist
        let mut doc = load_or_create_allowlist_doc(&path).unwrap();
        write_allowlist(&path, &doc).unwrap();

        // Try to remove non-existent entry
        let removed = remove_rule_entry(&mut doc, &rule);
        assert!(!removed, "should return false for non-existent entry");
    }

    #[test]
    fn allowlist_prune_removes_only_expired_entries() {
        use tempfile::TempDir;
        let temp = TempDir::new().unwrap();
        let path = temp.path().join("allowlist.toml");

        let expired_rule = RuleId::parse("core.git:reset-hard").unwrap();
        let active_rule = RuleId::parse("core.git:clean-force").unwrap();
        let mut doc = load_or_create_allowlist_doc(&path).unwrap();
        append_entry(
            &mut doc,
            build_rule_entry(&expired_rule, "expired", Some("2020-01-01T00:00:00Z"), &[]),
        );
        append_entry(
            &mut doc,
            build_rule_entry(&active_rule, "active", Some("2099-01-01T00:00:00Z"), &[]),
        );

        let pruned = prune_expired_allowlist_doc(&mut doc, AllowlistLayer::Project, &path, false);
        assert_eq!(pruned.len(), 1);
        assert_eq!(pruned[0].selector_value, "core.git:reset-hard");
        assert!(!has_rule_entry(&doc, &expired_rule));
        assert!(has_rule_entry(&doc, &active_rule));
    }

    #[test]
    fn allowlist_prune_dry_run_preserves_document() {
        use tempfile::TempDir;
        let temp = TempDir::new().unwrap();
        let path = temp.path().join("allowlist.toml");

        let expired_rule = RuleId::parse("core.git:reset-hard").unwrap();
        let mut doc = load_or_create_allowlist_doc(&path).unwrap();
        append_entry(
            &mut doc,
            build_rule_entry(&expired_rule, "expired", Some("2020-01-01T00:00:00Z"), &[]),
        );

        let pruned = prune_expired_allowlist_doc(&mut doc, AllowlistLayer::Project, &path, true);
        assert_eq!(pruned.len(), 1);
        assert!(has_rule_entry(&doc, &expired_rule));
    }

    #[test]
    fn allowlist_expired_entries_are_skipped_in_matching() {
        use crate::allowlist::{AllowlistLayer, is_expired, parse_allowlist_toml};
        use std::path::Path;

        let toml = r#"
            [[allow]]
            rule = "core.git:reset-hard"
            reason = "expired entry"
            expires_at = "2020-01-01T00:00:00Z"
        "#;

        // Parsing creates the entry (doesn't filter it out)
        let file = parse_allowlist_toml(AllowlistLayer::Project, Path::new("test"), toml);
        assert_eq!(file.entries.len(), 1, "parser should create the entry");
        assert!(
            file.errors.is_empty(),
            "parser should not report error for expired entry"
        );

        // But the entry should be marked as expired (skipped during matching)
        assert!(
            is_expired(&file.entries[0]),
            "entry should be detected as expired"
        );
    }

    #[test]
    fn allowlist_regex_without_ack_is_invalid_for_matching() {
        use crate::allowlist::{AllowlistLayer, has_required_risk_ack, parse_allowlist_toml};
        use std::path::Path;

        let toml = r#"
            [[allow]]
            pattern = "rm.*-rf"
            reason = "risky pattern"
        "#;

        // Parsing creates the entry (doesn't add error)
        let file = parse_allowlist_toml(AllowlistLayer::Project, Path::new("test"), toml);
        assert_eq!(file.entries.len(), 1, "parser should create the entry");

        // But the entry should fail the risk acknowledgement check (skipped during matching)
        assert!(
            !has_required_risk_ack(&file.entries[0]),
            "regex without ack should fail risk check"
        );
    }

    #[test]
    fn allowlist_pattern_entry_creates_valid_toml() {
        use tempfile::TempDir;
        let temp = TempDir::new().unwrap();
        let path = temp.path().join("allowlist.toml");

        // File should not exist yet
        assert!(!path.exists());

        // Create a pattern entry (as would be done by suggest-allowlist)
        let mut doc = load_or_create_allowlist_doc(&path).unwrap();
        let entry = build_pattern_entry(
            "npm run (build|test|lint)",
            "NPM scripts",
            "low",
            "high",
            42,
            3,
        );
        append_entry(&mut doc, entry);
        write_allowlist(&path, &doc).unwrap();

        // File should now exist with correct content
        assert!(path.exists());
        let content = std::fs::read_to_string(&path).unwrap();
        assert!(
            content.contains("pattern = \"npm run (build|test|lint)\""),
            "pattern should be in TOML"
        );
        assert!(
            content.contains("risk_acknowledged = true"),
            "risk_acknowledged should be true for patterns"
        );
        assert!(
            content.contains("auto-suggested"),
            "reason should mention auto-suggested"
        );
        assert!(
            content.contains("42 occurrences"),
            "reason should include frequency"
        );
    }

    #[test]
    fn allowlist_pattern_duplicate_detection() {
        use tempfile::TempDir;
        let temp = TempDir::new().unwrap();
        let path = temp.path().join("allowlist.toml");

        let pattern = "npm run (build|test)";

        // Add first pattern entry
        let mut doc = load_or_create_allowlist_doc(&path).unwrap();
        let entry = build_pattern_entry(pattern, "test", "low", "high", 10, 2);
        append_entry(&mut doc, entry);
        write_allowlist(&path, &doc).unwrap();

        // has_pattern_entry should detect duplicate
        let doc2 = load_or_create_allowlist_doc(&path).unwrap();
        assert!(
            has_pattern_entry(&doc2, pattern),
            "should detect existing pattern"
        );
        assert!(
            !has_pattern_entry(&doc2, "different pattern"),
            "should not detect different pattern"
        );
    }

    #[test]
    fn allowlist_command_entry_duplicate_detection() {
        use tempfile::TempDir;
        let temp = TempDir::new().unwrap();
        let path = temp.path().join("allowlist.toml");

        let command = "git push --force origin main";

        // Add first entry
        let mut doc = load_or_create_allowlist_doc(&path).unwrap();
        let entry = build_command_entry(command, "first", None);
        append_entry(&mut doc, entry);
        write_allowlist(&path, &doc).unwrap();

        // has_command_entry should detect duplicate
        let doc2 = load_or_create_allowlist_doc(&path).unwrap();
        assert!(
            has_command_entry(&doc2, command),
            "should detect existing command"
        );
    }

    // ========================================================================
    // Allowlist write safety tests (5apz.5)
    // ========================================================================

    #[test]
    fn allowlist_pattern_write_includes_risk_acknowledged() {
        // Pattern entries must always include risk_acknowledged = true
        let entry = build_pattern_entry(
            "rm -rf /tmp/cache.*",
            "Temporary cache cleanup",
            "medium",
            "high",
            15,
            3,
        );

        // Verify risk_acknowledged is present and true
        let risk_ack = entry.get("risk_acknowledged");
        assert!(
            risk_ack.is_some(),
            "risk_acknowledged field must be present"
        );
        assert_eq!(
            risk_ack.unwrap().as_bool(),
            Some(true),
            "risk_acknowledged must be true for pattern entries"
        );
    }

    #[test]
    fn allowlist_pattern_write_prevents_duplicates() {
        use tempfile::TempDir;
        let temp = TempDir::new().unwrap();
        let path = temp.path().join("allowlist.toml");

        let pattern = "npm run (dev|start|test)";

        // Write pattern once
        let mut doc = load_or_create_allowlist_doc(&path).unwrap();
        let entry = build_pattern_entry(pattern, "NPM scripts", "low", "high", 50, 3);
        append_entry(&mut doc, entry);
        write_allowlist(&path, &doc).unwrap();

        // Verify the pattern exists
        let doc2 = load_or_create_allowlist_doc(&path).unwrap();
        assert!(
            has_pattern_entry(&doc2, pattern),
            "pattern should exist after write"
        );

        // Attempting to add again should be detected as duplicate
        assert!(
            has_pattern_entry(&doc2, pattern),
            "duplicate detection should work before write attempt"
        );
    }

    #[test]
    fn allowlist_pattern_entry_format_matches_spec() {
        // Verify all required fields are present in pattern entries
        let entry = build_pattern_entry(
            "git (fetch|pull|push) origin",
            "Git remote operations",
            "low",
            "high",
            100,
            3,
        );

        // Required fields for pattern entries
        assert!(entry.get("pattern").is_some(), "pattern field is required");
        assert!(entry.get("reason").is_some(), "reason field is required");
        assert!(
            entry.get("risk_acknowledged").is_some(),
            "risk_acknowledged is required"
        );
        assert!(
            entry.get("added_at").is_some(),
            "added_at timestamp is required"
        );

        // Verify pattern value
        assert_eq!(
            entry.get("pattern").unwrap().as_str(),
            Some("git (fetch|pull|push) origin")
        );

        // Verify reason includes auto-suggested metadata
        let reason = entry.get("reason").unwrap().as_str().unwrap();
        assert!(
            reason.contains("auto-suggested"),
            "reason should mention auto-suggested"
        );
        assert!(
            reason.contains("high confidence"),
            "reason should include confidence tier"
        );
        assert!(
            reason.contains("low risk"),
            "reason should include risk level"
        );
        assert!(
            reason.contains("100 occurrences"),
            "reason should include frequency"
        );
        assert!(
            reason.contains("3 variants"),
            "reason should include variant count"
        );
    }

    #[test]
    fn suggestion_audit_entry_includes_required_metadata() {
        // Verify that SuggestionAuditEntry can be constructed with all required fields
        use crate::history::{SuggestionAction, SuggestionAuditEntry};

        let entry = SuggestionAuditEntry {
            timestamp: Utc::now(),
            action: SuggestionAction::Accepted,
            pattern: "npm run (build|test)".to_string(),
            final_pattern: None,
            risk_level: "low".to_string(),
            risk_score: 0.15,
            confidence_tier: "high".to_string(),
            confidence_points: 85,
            cluster_frequency: 42,
            unique_variants: 3,
            sample_commands: r#"["npm run build","npm run test"]"#.to_string(),
            rule_id: None,
            session_id: Some("test-session-123".to_string()),
            working_dir: Some("/home/user/project".to_string()),
        };

        // Verify all fields are accessible and correct
        assert_eq!(entry.pattern, "npm run (build|test)");
        assert_eq!(entry.action, SuggestionAction::Accepted);
        assert_eq!(entry.risk_level, "low");
        assert!(entry.risk_score > 0.0);
        assert_eq!(entry.confidence_tier, "high");
        assert_eq!(entry.confidence_points, 85);
        assert_eq!(entry.cluster_frequency, 42);
        assert_eq!(entry.unique_variants, 3);
        assert!(entry.sample_commands.contains("npm run build"));
    }

    #[test]
    fn suggestion_audit_entry_can_be_stored_and_retrieved() {
        use crate::history::{HistoryDb, SuggestionAction, SuggestionAuditEntry};

        let db = HistoryDb::open_in_memory().unwrap();

        let entry = SuggestionAuditEntry {
            timestamp: Utc::now(),
            action: SuggestionAction::Accepted,
            pattern: "cargo (build|test|run)".to_string(),
            final_pattern: None,
            risk_level: "low".to_string(),
            risk_score: 0.1,
            confidence_tier: "high".to_string(),
            confidence_points: 90,
            cluster_frequency: 100,
            unique_variants: 3,
            sample_commands: r#"["cargo build","cargo test"]"#.to_string(),
            rule_id: None,
            session_id: Some("cli-test-session".to_string()),
            working_dir: Some("/test/project".to_string()),
        };

        // Store the entry
        let id = db.log_suggestion_audit(&entry).unwrap();
        assert!(id > 0, "should return positive row ID");

        // Retrieve and verify
        let results = db.query_suggestion_audits(1, None).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].pattern, "cargo (build|test|run)");
        assert_eq!(results[0].action, SuggestionAction::Accepted);
        assert_eq!(results[0].session_id, Some("cli-test-session".to_string()));
    }

    #[test]
    fn test_interactive_option_type_resolution() {
        let no_paths: Vec<String> = Vec::new();
        assert_eq!(
            interactive_option_type(None, &no_paths),
            InteractiveAllowlistOptionType::Exact
        );

        let paths = vec!["/tmp/workspace".to_string()];
        assert_eq!(
            interactive_option_type(None, &paths),
            InteractiveAllowlistOptionType::PathSpecific
        );

        assert_eq!(
            interactive_option_type(Some("2030-01-01T00:00:00Z"), &no_paths),
            InteractiveAllowlistOptionType::Temporary
        );
    }

    #[test]
    fn test_log_interactive_allowlist_audit_event_skips_when_history_disabled() {
        let temp_dir = tempfile::tempdir().expect("temp dir");
        let db_path = temp_dir.path().join("history.sqlite3");

        let mut config = Config::default();
        config.history.enabled = false;
        config.history.database_path = Some(db_path.to_string_lossy().into_owned());

        let applied = InteractiveAllowlistApplication {
            summary: "exact command target, all directories".to_string(),
            pattern_added: "git reset --hard".to_string(),
            option_type: InteractiveAllowlistOptionType::Exact,
            option_detail: Some("target=exact_command".to_string()),
            config_file: temp_dir.path().join(".orca/allowlist.toml"),
        };

        log_interactive_allowlist_audit_event(&config, "git reset --hard", &applied)
            .expect("history disabled should be a no-op");

        assert!(
            !db_path.exists(),
            "history db should not be created when history is disabled"
        );
    }

    #[test]
    fn test_log_interactive_allowlist_audit_event_persists_entry() {
        use crate::history::HistoryDb;

        let temp_dir = tempfile::tempdir().expect("temp dir");
        let db_path = temp_dir.path().join("history.sqlite3");

        let mut config = Config::default();
        config.history.enabled = true;
        config.history.database_path = Some(db_path.to_string_lossy().into_owned());

        let applied = InteractiveAllowlistApplication {
            summary: "rule target, current directory only".to_string(),
            pattern_added: "core.git:reset-hard".to_string(),
            option_type: InteractiveAllowlistOptionType::PathSpecific,
            option_detail: Some("target=matched_rule;scope=current_directory_only".to_string()),
            config_file: temp_dir.path().join(".orca/allowlist.toml"),
        };

        log_interactive_allowlist_audit_event(&config, "git reset --hard", &applied)
            .expect("audit entry should be logged");

        let db = HistoryDb::open(Some(db_path)).expect("history db opens");
        assert_eq!(
            db.count_interactive_allowlist_audits()
                .expect("count audit entries"),
            1
        );

        let rows = db
            .query_interactive_allowlist_audits(10, None)
            .expect("query audit entries");
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].command, "git reset --hard");
        assert_eq!(rows[0].pattern_added, "core.git:reset-hard");
        assert_eq!(
            rows[0].option_type,
            InteractiveAllowlistOptionType::PathSpecific
        );
    }

    // ========================================================================
    // Scan CLI tests
    // ========================================================================

    #[test]
    fn test_cli_parse_scan_staged() {
        let cli = Cli::try_parse_from(["orca", "scan", "--staged"]).expect("parse");
        if let Some(Command::Scan(scan)) = cli.command {
            assert!(scan.staged);
            assert!(scan.paths.is_none());
            assert!(scan.git_diff.is_none());
            assert!(scan.action.is_none());
        } else {
            unreachable!("Expected Scan command");
        }
    }

    #[test]
    fn test_cli_parse_scan_paths() {
        let cli = Cli::try_parse_from(["orca", "scan", "--paths", "src/main.rs", "src/lib.rs"])
            .expect("parse");
        if let Some(Command::Scan(scan)) = cli.command {
            assert!(!scan.staged);
            assert_eq!(
                scan.paths,
                Some(vec![
                    std::path::PathBuf::from("src/main.rs"),
                    std::path::PathBuf::from("src/lib.rs"),
                ])
            );
            assert!(scan.git_diff.is_none());
            assert!(scan.action.is_none());
        } else {
            unreachable!("Expected Scan command");
        }
    }

    #[test]
    fn test_cli_parse_scan_git_diff() {
        let cli = Cli::try_parse_from(["orca", "scan", "--git-diff", "main..HEAD"]).expect("parse");
        if let Some(Command::Scan(scan)) = cli.command {
            assert!(!scan.staged);
            assert!(scan.paths.is_none());
            assert_eq!(scan.git_diff, Some("main..HEAD".to_string()));
            assert!(scan.action.is_none());
        } else {
            unreachable!("Expected Scan command");
        }
    }

    #[test]
    fn test_cli_parse_scan_format_json() {
        let cli =
            Cli::try_parse_from(["orca", "scan", "--staged", "--format", "json"]).expect("parse");
        if let Some(Command::Scan(scan)) = cli.command {
            assert_eq!(scan.format, Some(crate::scan::ScanFormat::Json));
        } else {
            unreachable!("Expected Scan command");
        }
    }

    #[test]
    fn test_cli_parse_scan_fail_on() {
        let cli = Cli::try_parse_from(["orca", "scan", "--staged", "--fail-on", "warning"])
            .expect("parse");
        if let Some(Command::Scan(scan)) = cli.command {
            assert_eq!(scan.fail_on, Some(crate::scan::ScanFailOn::Warning));
        } else {
            unreachable!("Expected Scan command");
        }
    }

    #[test]
    fn test_cli_parse_scan_max_file_size() {
        let cli = Cli::try_parse_from(["orca", "scan", "--staged", "--max-file-size", "2048"])
            .expect("parse");
        if let Some(Command::Scan(scan)) = cli.command {
            assert_eq!(scan.max_file_size, Some(2048));
        } else {
            unreachable!("Expected Scan command");
        }
    }

    #[test]
    fn test_cli_parse_scan_exclude_include() {
        let cli = Cli::try_parse_from([
            "orca",
            "scan",
            "--staged",
            "--exclude",
            "*.log",
            "--exclude",
            "target/**",
            "--include",
            "src/**",
        ])
        .expect("parse");
        if let Some(Command::Scan(scan)) = cli.command {
            assert_eq!(scan.exclude, vec!["*.log", "target/**"]);
            assert_eq!(scan.include, vec!["src/**"]);
        } else {
            unreachable!("Expected Scan command");
        }
    }

    #[test]
    fn test_cli_parse_scan_conflicts() {
        // --staged and --paths should conflict
        let result = Cli::try_parse_from(["orca", "scan", "--staged", "--paths", "file.txt"]);
        assert!(result.is_err());

        // --staged and --git-diff should conflict
        let result = Cli::try_parse_from(["orca", "scan", "--staged", "--git-diff", "main..HEAD"]);
        assert!(result.is_err());

        // --paths and --git-diff should conflict
        let result = Cli::try_parse_from([
            "orca",
            "scan",
            "--paths",
            "file.txt",
            "--git-diff",
            "main..HEAD",
        ]);
        assert!(result.is_err());
    }

    #[test]
    fn test_cli_parse_scan_install_pre_commit() {
        let cli = Cli::try_parse_from(["orca", "scan", "install-pre-commit"]).expect("parse");
        if let Some(Command::Scan(scan)) = cli.command {
            assert!(matches!(scan.action, Some(ScanAction::InstallPreCommit)));
        } else {
            unreachable!("Expected Scan command");
        }
    }

    #[test]
    fn test_cli_parse_scan_uninstall_pre_commit() {
        let cli = Cli::try_parse_from(["orca", "scan", "uninstall-pre-commit"]).expect("parse");
        if let Some(Command::Scan(scan)) = cli.command {
            assert!(matches!(scan.action, Some(ScanAction::UninstallPreCommit)));
        } else {
            unreachable!("Expected Scan command");
        }
    }

    #[test]
    fn test_cli_parse_scan_subcommand_conflicts_with_args() {
        let result = Cli::try_parse_from(["orca", "scan", "--staged", "install-pre-commit"]);
        assert!(
            result.is_err(),
            "args should conflict with scan subcommands"
        );
    }

    // ========================================================================
    // .orca/hooks.toml merge tests
    // ========================================================================

    #[test]
    fn scan_settings_merge_uses_hooks_defaults_when_cli_unset() {
        let (hooks, _warnings) = crate::scan::parse_hooks_toml(
            r#"
[scan]
format = "json"
fail_on = "warning"
max_file_size = 123
max_findings = 5
redact = "quoted"
truncate = 9

[scan.paths]
include = ["src/**"]
exclude = ["target/**"]
"#,
        )
        .expect("parse");

        let settings = ScanSettingsOverrides {
            format: None,
            fail_on: None,
            max_file_size: None,
            max_findings: None,
            redact: None,
            truncate: None,
            include: Vec::new(),
            exclude: Vec::new(),
        }
        .resolve(Some(&hooks));

        assert_eq!(settings.format, crate::scan::ScanFormat::Json);
        assert_eq!(settings.fail_on, crate::scan::ScanFailOn::Warning);
        assert_eq!(settings.max_file_size, 123);
        assert_eq!(settings.max_findings, 5);
        assert_eq!(settings.redact, crate::scan::ScanRedactMode::Quoted);
        assert_eq!(settings.truncate, 9);
        assert_eq!(settings.include, vec!["src/**"]);
        assert_eq!(settings.exclude, vec!["target/**"]);
    }

    #[test]
    fn scan_settings_merge_cli_overrides_hooks() {
        let (hooks, _warnings) =
            crate::scan::parse_hooks_toml("[scan]\nformat = \"json\"\n").expect("parse");

        let settings = ScanSettingsOverrides {
            format: Some(crate::scan::ScanFormat::Pretty),
            fail_on: Some(crate::scan::ScanFailOn::Error),
            max_file_size: Some(777),
            max_findings: Some(42),
            redact: Some(crate::scan::ScanRedactMode::Aggressive),
            truncate: Some(0),
            include: vec!["cli/**".to_string()],
            exclude: vec!["cli/tmp/**".to_string()],
        }
        .resolve(Some(&hooks));

        assert_eq!(settings.format, crate::scan::ScanFormat::Pretty);
        assert_eq!(settings.fail_on, crate::scan::ScanFailOn::Error);
        assert_eq!(settings.max_file_size, 777);
        assert_eq!(settings.max_findings, 42);
        assert_eq!(settings.redact, crate::scan::ScanRedactMode::Aggressive);
        assert_eq!(settings.truncate, 0);
        assert_eq!(settings.include, vec!["cli/**"]);
        assert_eq!(settings.exclude, vec!["cli/tmp/**"]);
    }

    #[test]
    fn scan_settings_defaults_are_stable_without_hooks_or_cli() {
        let settings = ScanSettingsOverrides {
            format: None,
            fail_on: None,
            max_file_size: None,
            max_findings: None,
            redact: None,
            truncate: None,
            include: Vec::new(),
            exclude: Vec::new(),
        }
        .resolve(None);

        assert_eq!(settings.format, crate::scan::ScanFormat::Pretty);
        assert_eq!(settings.fail_on, crate::scan::ScanFailOn::Error);
        assert_eq!(settings.max_file_size, 1_048_576);
        assert_eq!(settings.max_findings, 100);
        assert_eq!(settings.redact, crate::scan::ScanRedactMode::None);
        assert_eq!(settings.truncate, 200);
        assert!(settings.include.is_empty());
        assert!(settings.exclude.is_empty());
    }

    // ========================================================================
    // Pre-commit install/uninstall tests
    // ========================================================================

    fn init_temp_git_repo(dir: &std::path::Path) {
        let output = std::process::Command::new("git")
            .current_dir(dir)
            .args(["init", "-q"])
            .output()
            .expect("git init");
        assert!(
            output.status.success(),
            "git init failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    #[test]
    fn scan_pre_commit_install_uninstall_roundtrip() {
        let tmp = tempfile::tempdir().expect("tempdir");
        init_temp_git_repo(tmp.path());

        let hook_path = install_scan_pre_commit_hook_at(tmp.path()).expect("install");
        assert!(hook_path.exists(), "hook should exist after install");

        let contents_1 = std::fs::read_to_string(&hook_path).expect("read hook");
        assert!(
            contents_1.contains(ORCA_SCAN_PRE_COMMIT_SENTINEL),
            "hook should contain sentinel"
        );
        assert!(
            contents_1.contains("orca scan --staged"),
            "hook should run orca scan --staged"
        );

        let hook_path_2 = install_scan_pre_commit_hook_at(tmp.path()).expect("install again");
        assert_eq!(hook_path, hook_path_2);

        let contents_2 = std::fs::read_to_string(&hook_path).expect("read hook");
        assert_eq!(contents_1, contents_2, "install should be idempotent");

        let removed = uninstall_scan_pre_commit_hook_at(tmp.path()).expect("uninstall");
        assert!(removed.is_some(), "hook should be removed");

        let removed_again = uninstall_scan_pre_commit_hook_at(tmp.path()).expect("uninstall again");
        assert!(removed_again.is_none(), "should be a no-op when missing");
    }

    #[test]
    fn scan_pre_commit_install_refuses_to_overwrite_unknown_hook() {
        let tmp = tempfile::tempdir().expect("tempdir");
        init_temp_git_repo(tmp.path());

        let hook_path = git_resolve_path(tmp.path(), "hooks/pre-commit").expect("hook path");
        let existing = "#!/usr/bin/env bash\necho hi\n";
        std::fs::write(&hook_path, existing).expect("write existing hook");

        let err = install_scan_pre_commit_hook_at(tmp.path()).expect_err("should refuse");
        assert!(err.to_string().contains("Refusing to overwrite"));

        let after = std::fs::read_to_string(&hook_path).expect("read hook after");
        assert_eq!(after, existing, "should not modify unknown hook");
    }

    #[test]
    fn scan_pre_commit_uninstall_refuses_to_remove_unknown_hook() {
        let tmp = tempfile::tempdir().expect("tempdir");
        init_temp_git_repo(tmp.path());

        let hook_path = git_resolve_path(tmp.path(), "hooks/pre-commit").expect("hook path");
        let existing = "#!/usr/bin/env bash\necho hi\n";
        std::fs::write(&hook_path, existing).expect("write existing hook");

        let err = uninstall_scan_pre_commit_hook_at(tmp.path()).expect_err("should refuse");
        assert!(err.to_string().contains("Refusing to remove"));

        let after = std::fs::read_to_string(&hook_path).expect("read hook after");
        assert_eq!(after, existing, "should not modify unknown hook");
    }

    #[test]
    fn test_cli_parse_history_stats() {
        let cli = Cli::try_parse_from([
            "orca", "history", "stats", "--days", "7", "--json", "--trends",
        ])
        .expect("parse");
        if let Some(Command::History { action }) = cli.command {
            if let HistoryAction::Stats { days, trends, json } = action {
                assert_eq!(days, 7);
                assert!(trends);
                assert!(json);
            } else {
                unreachable!("Expected History stats action");
            }
        } else {
            unreachable!("Expected History command");
        }
    }

    #[test]
    fn test_cli_parse_history_interactive() {
        let cli = Cli::try_parse_from([
            "orca",
            "history",
            "interactive",
            "--limit",
            "25",
            "--option",
            "temporary",
            "--json",
        ])
        .expect("parse");

        if let Some(Command::History { action }) = cli.command {
            if let HistoryAction::Interactive {
                limit,
                option,
                json,
            } = action
            {
                assert_eq!(limit, 25);
                assert_eq!(option.as_deref(), Some("temporary"));
                assert!(json);
            } else {
                unreachable!("Expected History interactive action");
            }
        } else {
            unreachable!("Expected History command");
        }
    }

    #[test]
    fn test_cli_parse_explain() {
        let cli = Cli::try_parse_from(["orca", "explain", "git reset --hard"]).expect("parse");
        if let Some(Command::Explain {
            command,
            format,
            with_packs,
        }) = cli.command
        {
            assert_eq!(command, "git reset --hard");
            assert_eq!(format, ExplainFormat::Pretty);
            assert!(with_packs.is_none());
        } else {
            unreachable!("Expected Explain command");
        }
    }

    #[test]
    fn test_cli_parse_explain_with_format() {
        let cli =
            Cli::try_parse_from(["orca", "explain", "--format", "json", "docker system prune"])
                .expect("parse");
        if let Some(Command::Explain {
            command, format, ..
        }) = cli.command
        {
            assert_eq!(command, "docker system prune");
            assert_eq!(format, ExplainFormat::Json);
        } else {
            unreachable!("Expected Explain command");
        }
    }

    #[test]
    fn test_cli_parse_test_with_explain_flag() {
        let cli =
            Cli::try_parse_from(["orca", "test", "--explain", "git reset --hard"]).expect("parse");
        if let Some(Command::TestCommand {
            command,
            explain,
            format,
            ..
        }) = cli.command
        {
            assert_eq!(command, "git reset --hard");
            assert!(explain);
            assert_eq!(format, TestFormat::Pretty); // default format
        } else {
            unreachable!("Expected TestCommand");
        }
    }

    #[test]
    fn test_cli_parse_test_with_format_json() {
        let cli = Cli::try_parse_from(["orca", "test", "--format", "json", "rm -rf /tmp"])
            .expect("parse");
        if let Some(Command::TestCommand {
            command, format, ..
        }) = cli.command
        {
            assert_eq!(command, "rm -rf /tmp");
            assert_eq!(format, TestFormat::Json);
        } else {
            unreachable!("Expected TestCommand");
        }
    }

    #[test]
    fn test_cli_parse_test_with_format_toon() {
        let cli = Cli::try_parse_from(["orca", "test", "--format", "toon", "rm -rf /tmp"])
            .expect("parse");
        if let Some(Command::TestCommand {
            command, format, ..
        }) = cli.command
        {
            assert_eq!(command, "rm -rf /tmp");
            assert_eq!(format, TestFormat::Toon);
        } else {
            unreachable!("Expected TestCommand");
        }
    }

    #[test]
    fn test_cli_parse_test_with_force_flag() {
        let cli =
            Cli::try_parse_from(["orca", "test", "--force", "git reset --hard"]).expect("parse");
        if let Some(Command::TestCommand { command, force, .. }) = cli.command {
            assert_eq!(command, "git reset --hard");
            assert!(force);
        } else {
            unreachable!("Expected TestCommand");
        }
    }

    #[test]
    fn test_cli_parse_test_without_force_flag() {
        let cli = Cli::try_parse_from(["orca", "test", "git status"]).expect("parse");
        if let Some(Command::TestCommand { force, .. }) = cli.command {
            assert!(!force);
        } else {
            unreachable!("Expected TestCommand");
        }
    }

    #[test]
    fn test_cli_parse_test_without_explain_flag() {
        let cli = Cli::try_parse_from(["orca", "test", "git status"]).expect("parse");
        if let Some(Command::TestCommand {
            command,
            explain,
            format,
            ..
        }) = cli.command
        {
            assert_eq!(command, "git status");
            assert!(!explain);
            assert_eq!(format, TestFormat::Pretty); // default
        } else {
            unreachable!("Expected TestCommand");
        }
    }

    #[test]
    fn test_toon_roundtrip_for_test_output_payload() {
        let payload = TestOutput {
            schema_version: TEST_OUTPUT_SCHEMA_VERSION,
            orca_version: "v0.0.0-test".to_string(),
            robot_mode: false,
            command: "rm -rf /".to_string(),
            decision: "deny".to_string(),
            rule_id: Some("core.filesystem:rm-rf-root".to_string()),
            pack_id: Some("core.filesystem".to_string()),
            pattern_name: Some("rm-rf-root".to_string()),
            reason: Some("Refusing to remove root directory".to_string()),
            explanation: Some("Root path deletion is always destructive".to_string()),
            source: Some("pack".to_string()),
            matched_span: Some((0, 8)),
            severity: Some("critical".to_string()),
            allowlist: None,
            agent: Some(AgentInfo {
                detected: "unknown".to_string(),
                trust_level: "medium".to_string(),
                detection_method: "none".to_string(),
            }),
        };

        let json = serde_json::to_value(&payload).expect("serialize payload to json");
        let toon_encoded = toon::encode(json.clone(), None);
        let decoded: serde_json::Value = toon::try_decode(&toon_encoded, None)
            .expect("decode TOON payload")
            .into();
        // tru normalizes integers to f64 in roundtrip; compare canonically.
        fn canon(v: &serde_json::Value) -> serde_json::Value {
            match v {
                serde_json::Value::Number(n) => n
                    .as_f64()
                    .and_then(serde_json::Number::from_f64)
                    .map_or(serde_json::Value::Null, serde_json::Value::Number),
                serde_json::Value::Array(a) => {
                    serde_json::Value::Array(a.iter().map(canon).collect())
                }
                serde_json::Value::Object(o) => serde_json::Value::Object(
                    o.iter().map(|(k, v)| (k.clone(), canon(v))).collect(),
                ),
                other => other.clone(),
            }
        }
        assert_eq!(canon(&decoded), canon(&json));
    }

    // ========================================================================
    // Classify command tests
    // ========================================================================

    #[test]
    fn test_cli_parse_classify_basic() {
        let cli = Cli::try_parse_from(["orca", "classify", "git status"]).expect("parse");
        if let Some(Command::Classify {
            command,
            format,
            no_color,
        }) = cli.command
        {
            assert_eq!(command, "git status");
            assert_eq!(format, ClassifyFormat::Json); // default is json
            assert!(!no_color);
        } else {
            unreachable!("Expected Classify");
        }
    }

    #[test]
    fn test_cli_parse_classify_with_format_text() {
        let cli = Cli::try_parse_from(["orca", "classify", "--format", "text", "rm -rf /"])
            .expect("parse");
        if let Some(Command::Classify {
            command, format, ..
        }) = cli.command
        {
            assert_eq!(command, "rm -rf /");
            assert_eq!(format, ClassifyFormat::Text);
        } else {
            unreachable!("Expected Classify");
        }
    }

    #[test]
    fn test_cli_parse_classify_with_no_color() {
        let cli = Cli::try_parse_from(["orca", "classify", "--no-color", "git push --force"])
            .expect("parse");
        if let Some(Command::Classify { no_color, .. }) = cli.command {
            assert!(no_color);
        } else {
            unreachable!("Expected Classify");
        }
    }

    #[test]
    fn test_classify_output_serialization() {
        let output = ClassifyOutput {
            schema_version: CLASSIFY_OUTPUT_SCHEMA_VERSION,
            orca_version: "v0.0.0-test".to_string(),
            command: "rm -rf /".to_string(),
            decision: "block".to_string(),
            risk_level: "critical".to_string(),
            risk_score: 1.0,
            reasons: vec![ClassifyReason {
                rule_id: "core.filesystem:rm-rf-root".to_string(),
                severity: "critical".to_string(),
                explanation: "Removes the root filesystem".to_string(),
            }],
            suggestions: vec!["rm -ri / (interactive mode)".to_string()],
        };

        let json = serde_json::to_string_pretty(&output).expect("serialize");
        let parsed: serde_json::Value = serde_json::from_str(&json).expect("parse");
        assert_eq!(parsed["schema_version"], 1);
        assert_eq!(parsed["decision"], "block");
        assert_eq!(parsed["risk_level"], "critical");
        assert_eq!(parsed["risk_score"], 1.0);
        assert_eq!(parsed["reasons"].as_array().unwrap().len(), 1);
        assert_eq!(
            parsed["reasons"][0]["rule_id"],
            "core.filesystem:rm-rf-root"
        );
        assert_eq!(parsed["suggestions"].as_array().unwrap().len(), 1);
    }

    #[test]
    fn test_classify_output_safe_command_serialization() {
        let output = ClassifyOutput {
            schema_version: CLASSIFY_OUTPUT_SCHEMA_VERSION,
            orca_version: "v0.0.0-test".to_string(),
            command: "git status".to_string(),
            decision: "allow".to_string(),
            risk_level: "safe".to_string(),
            risk_score: 0.0,
            reasons: vec![],
            suggestions: vec![],
        };

        let json = serde_json::to_string_pretty(&output).expect("serialize");
        let parsed: serde_json::Value = serde_json::from_str(&json).expect("parse");
        assert_eq!(parsed["decision"], "allow");
        assert_eq!(parsed["risk_level"], "safe");
        assert_eq!(parsed["risk_score"], 0.0);
        assert!(parsed["reasons"].as_array().unwrap().is_empty());
        assert!(parsed["suggestions"].as_array().unwrap().is_empty());
    }

    // ========================================================================
    // Scan git integration tests
    // ========================================================================

    fn run_git(cwd: &std::path::Path, args: &[&str]) {
        let output = std::process::Command::new("git")
            .current_dir(cwd)
            .args(args)
            .output()
            .expect("run git");

        assert!(
            output.status.success(),
            "git {args:?} failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    fn init_fixture_repo() -> tempfile::TempDir {
        let dir = tempfile::tempdir().expect("tempdir");
        run_git(dir.path(), &["init"]);
        run_git(dir.path(), &["config", "user.email", "test@example.com"]);
        run_git(dir.path(), &["config", "user.name", "Test User"]);

        std::fs::write(dir.path().join("base.txt"), "base").expect("write base");
        run_git(dir.path(), &["add", "base.txt"]);
        run_git(dir.path(), &["commit", "-m", "init"]);

        dir
    }

    #[test]
    fn get_staged_files_errors_when_not_git_repo() {
        let dir = tempfile::tempdir().expect("tempdir");
        let err = get_staged_files_at(dir.path()).expect_err("should error");
        assert!(err.to_string().contains("Not a git repository"));
    }

    #[test]
    fn get_staged_files_handles_spaces_and_newlines() {
        let repo = init_fixture_repo();

        std::fs::write(repo.path().join("hello world.rs"), "x").expect("write");
        std::fs::write(repo.path().join("weird\nname.rs"), "y").expect("write");
        run_git(repo.path(), &["add", "hello world.rs", "weird\nname.rs"]);

        let paths = get_staged_files_at(repo.path()).expect("staged files");
        let rendered: Vec<String> = paths
            .iter()
            .map(|p| p.to_string_lossy().to_string())
            .collect();

        assert!(rendered.contains(&"hello world.rs".to_string()));
        assert!(rendered.contains(&"weird\nname.rs".to_string()));
    }

    #[test]
    fn get_staged_files_rename_returns_new_path() {
        let repo = init_fixture_repo();

        std::fs::write(repo.path().join("old.rs"), "x").expect("write");
        run_git(repo.path(), &["add", "old.rs"]);
        run_git(repo.path(), &["commit", "-m", "add old"]);

        run_git(repo.path(), &["mv", "old.rs", "new.rs"]);

        let paths = get_staged_files_at(repo.path()).expect("staged files");
        let rendered: Vec<String> = paths
            .iter()
            .map(|p| p.to_string_lossy().to_string())
            .collect();

        assert!(rendered.contains(&"new.rs".to_string()));
        assert!(!rendered.contains(&"old.rs".to_string()));
    }

    #[test]
    fn get_staged_files_delete_is_skipped() {
        let repo = init_fixture_repo();

        std::fs::write(repo.path().join("delete.rs"), "x").expect("write");
        run_git(repo.path(), &["add", "delete.rs"]);
        run_git(repo.path(), &["commit", "-m", "add delete"]);

        run_git(repo.path(), &["rm", "delete.rs"]);

        let paths = get_staged_files_at(repo.path()).expect("staged files");
        let contains_deleted = paths.iter().any(|p| p.to_string_lossy() == "delete.rs");

        assert!(!contains_deleted);
    }

    #[test]
    fn get_git_diff_files_returns_changed_paths() {
        let repo = init_fixture_repo();

        std::fs::write(repo.path().join("diff.rs"), "v1").expect("write");
        run_git(repo.path(), &["add", "diff.rs"]);
        run_git(repo.path(), &["commit", "-m", "add diff"]);

        std::fs::write(repo.path().join("diff.rs"), "v2").expect("write");
        run_git(repo.path(), &["add", "diff.rs"]);
        run_git(repo.path(), &["commit", "-m", "mod diff"]);

        let paths = get_git_diff_files_at(repo.path(), "HEAD~1..HEAD").expect("diff files");
        let contains_diff = paths.iter().any(|p| p.to_string_lossy() == "diff.rs");

        assert!(contains_diff);
    }

    #[test]
    fn git_diff_rejects_flag_like_rev_range() {
        // Regression: --git-diff used to forward its argument to `git diff`
        // with no validation. Values starting with `-` were interpreted
        // as flags, including dangerous ones like `--output=/etc/...`
        // (overwrites the file with diff content) and `--ext-diff`
        // (activates external diff drivers from .git/config).
        let bad_inputs = [
            "--output=/etc/passwd",
            "--ext-diff",
            "--upload-pack=evil",
            "-",
            "--no-renames",
        ];
        for bad in bad_inputs {
            let err = validate_git_rev_range(bad).expect_err(&format!(
                "validate_git_rev_range({bad:?}) should reject flag-like input"
            ));
            let msg = err.to_string();
            assert!(
                msg.contains("'-'") || msg.contains("disallowed"),
                "expected flag rejection message, got: {msg}"
            );
        }
    }

    #[test]
    fn git_diff_rejects_shell_metacharacters() {
        // Defense in depth: even if downstream callers ever interpolate
        // rev_range into a shell string, we reject the chars that would
        // matter.
        let bad_inputs = [
            "main; rm -rf /",
            "HEAD && echo pwned",
            "HEAD | curl evil",
            "HEAD\nrm -rf /",
            "$(echo evil)",
            "`evil`",
            "main\0HEAD",
        ];
        for bad in bad_inputs {
            assert!(
                validate_git_rev_range(bad).is_err(),
                "validate_git_rev_range({bad:?}) should reject shell metacharacter"
            );
        }
    }

    #[test]
    fn git_diff_accepts_legitimate_rev_ranges() {
        // Real git rev-ranges that should pass through unchanged.
        let good_inputs = [
            "HEAD",
            "HEAD~3..HEAD",
            "main..feature",
            "release/1.0..HEAD",
            "v1.2.3...v2.0",
            "HEAD@{1}",
            "abc1234",
            "abc1234..def5678",
        ];
        for good in good_inputs {
            assert!(
                validate_git_rev_range(good).is_ok(),
                "validate_git_rev_range({good:?}) should accept legitimate input"
            );
        }
    }

    #[test]
    fn git_diff_rejects_empty() {
        assert!(validate_git_rev_range("").is_err());
    }

    // ========================================================================
    // Git-diff integration tests (git_safety_guard-scan.5.3)
    // ========================================================================

    #[test]
    fn git_diff_empty_returns_empty() {
        let repo = init_fixture_repo();
        std::fs::write(repo.path().join("stable.rs"), "content").expect("write");
        run_git(repo.path(), &["add", "stable.rs"]);
        run_git(repo.path(), &["commit", "-m", "add stable"]);
        let paths = get_git_diff_files_at(repo.path(), "HEAD..HEAD").expect("diff");
        assert!(
            paths.is_empty(),
            "Empty diff should return empty list: {paths:?}"
        );
    }

    #[test]
    fn git_diff_renamed_file() {
        let repo = init_fixture_repo();
        std::fs::write(repo.path().join("old.rs"), "x").expect("write");
        run_git(repo.path(), &["add", "old.rs"]);
        run_git(repo.path(), &["commit", "-m", "add"]);
        run_git(repo.path(), &["mv", "old.rs", "new.rs"]);
        run_git(repo.path(), &["commit", "-m", "rename"]);
        let paths = get_git_diff_files_at(repo.path(), "HEAD~1..HEAD").expect("diff");
        let strs: Vec<String> = paths
            .iter()
            .map(|p| p.to_string_lossy().to_string())
            .collect();
        assert!(
            strs.contains(&"new.rs".to_string()),
            "Should have new: {strs:?}"
        );
        assert!(
            !strs.contains(&"old.rs".to_string()),
            "Should not have old: {strs:?}"
        );
    }

    #[test]
    fn git_diff_deleted_skipped() {
        let repo = init_fixture_repo();
        std::fs::write(repo.path().join("del.rs"), "x").expect("write");
        run_git(repo.path(), &["add", "del.rs"]);
        run_git(repo.path(), &["commit", "-m", "add"]);
        run_git(repo.path(), &["rm", "del.rs"]);
        run_git(repo.path(), &["commit", "-m", "del"]);
        let paths = get_git_diff_files_at(repo.path(), "HEAD~1..HEAD").expect("diff");
        assert!(
            !paths.iter().any(|p| p.to_string_lossy() == "del.rs"),
            "Deleted skipped: {paths:?}"
        );
    }

    #[test]
    fn git_diff_deterministic() {
        let repo = init_fixture_repo();
        std::fs::write(repo.path().join("z.rs"), "z").expect("write");
        std::fs::write(repo.path().join("a.rs"), "a").expect("write");
        run_git(repo.path(), &["add", "."]);
        run_git(repo.path(), &["commit", "-m", "add"]);
        let p1 = get_git_diff_files_at(repo.path(), "HEAD~1..HEAD").expect("diff1");
        let p2 = get_git_diff_files_at(repo.path(), "HEAD~1..HEAD").expect("diff2");
        let s1: Vec<String> = p1.iter().map(|p| p.to_string_lossy().to_string()).collect();
        let s2: Vec<String> = p2.iter().map(|p| p.to_string_lossy().to_string()).collect();
        assert_eq!(s1, s2, "Deterministic order");
    }

    #[test]
    fn git_diff_mixed_ops() {
        let repo = init_fixture_repo();
        std::fs::write(repo.path().join("mod.rs"), "v1").expect("write");
        std::fs::write(repo.path().join("del.rs"), "x").expect("write");
        std::fs::write(repo.path().join("ren.rs"), "x").expect("write");
        run_git(repo.path(), &["add", "."]);
        run_git(repo.path(), &["commit", "-m", "init"]);
        std::fs::write(repo.path().join("new.rs"), "x").expect("write");
        std::fs::write(repo.path().join("mod.rs"), "v2").expect("write");
        run_git(repo.path(), &["rm", "del.rs"]);
        run_git(repo.path(), &["mv", "ren.rs", "renamed.rs"]);
        run_git(repo.path(), &["add", "."]);
        run_git(repo.path(), &["commit", "-m", "mix"]);
        let paths = get_git_diff_files_at(repo.path(), "HEAD~1..HEAD").expect("diff");
        let s: Vec<String> = paths
            .iter()
            .map(|p| p.to_string_lossy().to_string())
            .collect();
        assert!(s.contains(&"new.rs".to_string()), "Has new");
        assert!(s.contains(&"mod.rs".to_string()), "Has mod");
        assert!(s.contains(&"renamed.rs".to_string()), "Has renamed");
        assert!(!s.contains(&"ren.rs".to_string()), "No old rename");
        assert!(!s.contains(&"del.rs".to_string()), "No deleted");
    }

    // ========================================================================
    // Markdown output tests (scan.5.2)
    // ========================================================================

    #[test]
    fn truncate_for_markdown_short_strings_unchanged() {
        assert_eq!(truncate_for_markdown("hello", 10), "hello");
        assert_eq!(truncate_for_markdown("", 10), "");
        assert_eq!(truncate_for_markdown("abc", 3), "abc");
    }

    #[test]
    fn truncate_for_markdown_long_strings_truncated() {
        assert_eq!(truncate_for_markdown("hello world", 5), "hello...");
        assert_eq!(truncate_for_markdown("abcdefghij", 7), "abcdefg...");
    }

    #[test]
    fn truncate_for_markdown_zero_max_no_truncation() {
        // max_len=0 means unlimited
        assert_eq!(truncate_for_markdown("hello world", 0), "hello world");
    }

    #[test]
    fn truncate_for_markdown_unicode_boundary() {
        // "café" = 5 bytes: c(1) + a(1) + f(1) + é(2)
        // Truncating at byte 4 lands mid-character (é spans bytes 3-4)
        // Should back up to byte 3 (char boundary after 'f')
        assert_eq!(truncate_for_markdown("café", 4), "caf...");

        // Truncating at byte 3 lands at char boundary
        assert_eq!(truncate_for_markdown("café", 3), "caf...");

        // Truncating at byte 5 keeps entire string (no truncation needed)
        assert_eq!(truncate_for_markdown("café", 5), "café");

        // Emoji test: "hi👋" = 6 bytes: h(1) + i(1) + 👋(4)
        // Truncating at byte 3 lands mid-emoji, should back up to byte 2
        assert_eq!(truncate_for_markdown("hi👋", 3), "hi...");

        // Truncating at byte 2 lands at char boundary
        assert_eq!(truncate_for_markdown("hi👋", 2), "hi...");

        // Truncating at byte 5 keeps entire string (no truncation needed)
        // Wait, byte 5 is inside the emoji. It should truncate to "hi..." because it can't fit the emoji.
        assert_eq!(truncate_for_markdown("hi👋", 5), "hi...");
    }

    #[test]
    fn scan_format_markdown_variant_exists() {
        // Verify the Markdown variant is available and can be compared
        assert_eq!(
            crate::scan::ScanFormat::Markdown,
            crate::scan::ScanFormat::Markdown
        );
    }

    #[test]
    fn cli_parse_scan_format_markdown() {
        let cli = Cli::try_parse_from(["orca", "scan", "--staged", "--format", "markdown"])
            .expect("parse");
        if let Some(Command::Scan(scan)) = cli.command {
            assert_eq!(scan.format, Some(crate::scan::ScanFormat::Markdown));
        } else {
            unreachable!("Expected Scan command");
        }
    }

    #[test]
    fn allow_once_disambiguation_selects_by_pick_or_hash() {
        use crate::logging::{RedactionConfig, RedactionMode};

        let ts = chrono::DateTime::parse_from_rfc3339("2099-01-01T00:00:00Z")
            .unwrap()
            .with_timezone(&Utc);
        let redaction = RedactionConfig {
            enabled: true,
            mode: RedactionMode::Arguments,
            max_argument_len: 8,
        };

        let a =
            PendingExceptionRecord::new(ts, "/repo", "git status", "ok", &redaction, false, None);
        let mut b = PendingExceptionRecord::new(
            ts,
            "/repo",
            "git reset --hard",
            "blocked",
            &redaction,
            false,
            None,
        );
        // Force a short-code collision to exercise disambiguation.
        b.short_code = a.short_code.clone();

        let cmd_pick = AllowOnceCommand {
            action: None,
            code: Some(a.short_code.clone()),
            yes: true,
            show_raw: false,
            dry_run: true,
            json: true,
            single_use: false,
            force: false,
            pick: Some(2),
            hash: None,
        };
        let records = [a.clone(), b.clone()];
        let selected = select_pending_entry(&records, &cmd_pick).unwrap();
        assert_eq!(selected.command_raw, b.command_raw);

        let cmd_hash = AllowOnceCommand {
            action: None,
            code: Some(a.short_code.clone()),
            yes: true,
            show_raw: false,
            dry_run: true,
            json: true,
            single_use: false,
            force: false,
            pick: None,
            hash: Some(b.full_hash.clone()),
        };
        let records = [a, b.clone()];
        let selected = select_pending_entry(&records, &cmd_hash).unwrap();
        assert_eq!(selected.full_hash, b.full_hash);
    }

    #[test]
    fn allow_once_disambiguation_rejects_invalid_pick() {
        use crate::logging::{RedactionConfig, RedactionMode};

        let ts = chrono::DateTime::parse_from_rfc3339("2099-01-01T00:00:00Z")
            .unwrap()
            .with_timezone(&Utc);
        let redaction = RedactionConfig {
            enabled: true,
            mode: RedactionMode::Arguments,
            max_argument_len: 8,
        };

        let a =
            PendingExceptionRecord::new(ts, "/repo", "git status", "ok", &redaction, false, None);
        let mut b = PendingExceptionRecord::new(
            ts,
            "/repo",
            "git reset --hard",
            "blocked",
            &redaction,
            false,
            None,
        );
        b.short_code = a.short_code.clone();

        let cmd_pick = AllowOnceCommand {
            action: None,
            code: Some(a.short_code.clone()),
            yes: true,
            show_raw: false,
            dry_run: true,
            json: true,
            single_use: false,
            force: false,
            pick: Some(3),
            hash: None,
        };

        let records = [a, b];
        let err = select_pending_entry(&records, &cmd_pick).expect_err("invalid pick should error");
        assert!(err.to_string().contains("Pick must be between 1 and 2"));
    }

    #[test]
    fn prompt_disabled_for_json_format() {
        let verbosity = Verbosity {
            level: 1,
            quiet: false,
        };
        assert!(!should_prompt_interactively(
            TestFormat::Json,
            verbosity,
            DecisionMode::Deny,
            Some(PackSeverity::Medium),
            &InteractiveConfig::default(),
        ));
    }

    #[test]
    fn prompt_disabled_for_toon_format() {
        let verbosity = Verbosity {
            level: 1,
            quiet: false,
        };
        assert!(!should_prompt_interactively(
            TestFormat::Toon,
            verbosity,
            DecisionMode::Deny,
            Some(PackSeverity::Medium),
            &InteractiveConfig::default(),
        ));
    }

    #[test]
    fn prompt_disabled_for_non_blocking_mode() {
        let verbosity = Verbosity {
            level: 1,
            quiet: false,
        };
        assert!(!should_prompt_interactively(
            TestFormat::Pretty,
            verbosity,
            DecisionMode::Warn,
            Some(PackSeverity::Medium),
            &InteractiveConfig::default(),
        ));
    }

    #[test]
    fn prompt_disabled_for_non_interactive_env_context() {
        let verbosity = Verbosity {
            level: 1,
            quiet: false,
        };
        assert!(!should_prompt_interactively_with_context(
            TestFormat::Pretty,
            verbosity,
            DecisionMode::Deny,
            Some(PackSeverity::Medium),
            true,
            true,
            true,
            true,
        ));
    }

    #[test]
    fn prompt_disabled_when_interactive_not_available_context() {
        let verbosity = Verbosity {
            level: 1,
            quiet: false,
        };
        assert!(!should_prompt_interactively_with_context(
            TestFormat::Pretty,
            verbosity,
            DecisionMode::Deny,
            Some(PackSeverity::Medium),
            false,
            false,
            true,
            true,
        ));
    }

    #[test]
    fn prompt_disabled_for_non_tty_context() {
        let verbosity = Verbosity {
            level: 1,
            quiet: false,
        };
        assert!(!should_prompt_interactively_with_context(
            TestFormat::Pretty,
            verbosity,
            DecisionMode::Deny,
            Some(PackSeverity::Medium),
            false,
            true,
            false,
            true,
        ));
    }

    #[test]
    fn prompt_enabled_when_all_requirements_met_context() {
        let verbosity = Verbosity {
            level: 1,
            quiet: false,
        };
        assert!(should_prompt_interactively_with_context(
            TestFormat::Pretty,
            verbosity,
            DecisionMode::Deny,
            Some(PackSeverity::Medium),
            false,
            true,
            true,
            true,
        ));
    }

    // ========================================================================
    // Self-heal hook registration tests
    // ========================================================================

    #[test]
    fn self_heal_reregisters_missing_hook() {
        // Create a temporary settings.json WITHOUT the orca hook
        let dir = tempfile::tempdir().unwrap();
        let settings_path = dir.path().join("settings.json");
        let settings = serde_json::json!({
            "hooks": {
                "PreToolUse": []
            }
        });
        std::fs::write(
            &settings_path,
            serde_json::to_string_pretty(&settings).unwrap(),
        )
        .unwrap();

        // Read it back, install the hook, and write
        let content = std::fs::read_to_string(&settings_path).unwrap();
        let mut settings: serde_json::Value = serde_json::from_str(&content).unwrap();

        let is_registered = settings
            .get("hooks")
            .and_then(|h| h.get("PreToolUse"))
            .and_then(|arr| arr.as_array())
            .is_some_and(|a| a.iter().any(is_orca_hook_entry));
        assert!(!is_registered, "hook should not be registered yet");

        let changed = install_orca_hook_into_settings(&mut settings, false).unwrap();
        assert!(changed, "should have installed the hook");

        let is_registered = settings
            .get("hooks")
            .and_then(|h| h.get("PreToolUse"))
            .and_then(|arr| arr.as_array())
            .is_some_and(|a| a.iter().any(is_orca_hook_entry));
        assert!(is_registered, "hook should be registered after install");
    }

    #[test]
    fn self_heal_noop_when_hook_present() {
        let mut settings = serde_json::json!({
            "hooks": {
                "PreToolUse": [{
                    "matcher": "Bash",
                    "hooks": [{"type": "command", "command": "orca"}]
                }]
            }
        });

        let changed = install_orca_hook_into_settings(&mut settings, false).unwrap();
        assert!(!changed, "should not modify when hook is already present");
    }

    #[test]
    fn self_heal_handles_overwritten_settings() {
        // Simulate Claude Code overwriting settings.json with no hooks at all
        let mut settings = serde_json::json!({
            "permissions": {
                "allow": ["Bash(*)"]
            }
        });

        let changed = install_orca_hook_into_settings(&mut settings, false).unwrap();
        assert!(
            changed,
            "should install hook into settings with no hooks key"
        );

        // Verify the structure was created correctly
        let is_registered = settings
            .get("hooks")
            .and_then(|h| h.get("PreToolUse"))
            .and_then(|arr| arr.as_array())
            .is_some_and(|a| a.iter().any(is_orca_hook_entry));
        assert!(is_registered, "hook should be registered after self-heal");

        // Verify existing keys were preserved
        assert!(
            settings.get("permissions").is_some(),
            "existing keys should be preserved"
        );
    }

}
