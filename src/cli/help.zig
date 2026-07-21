const std = @import("std");
const style = @import("style.zig");
const build_options = @import("build_options");
const tui = @import("../tui/mod.zig");
const host_launch = @import("host_launch.zig");

pub const Category = enum {
    getting_started,
    core_workflow,
    staged_changes,
    diagnostics,
    integrations,
    advanced,
    internal,
};

pub const CommandInfo = struct {
    name: []const u8,
    summary: []const u8,
    usage: []const u8,
    details: []const []const u8,
    examples: []const []const u8 = &.{},
    additional_completion_flags: []const []const u8 = &.{},
    category: Category = .advanced,
    /// When true, listed on default root help (Safe Launch progressive disclosure).
    public: bool = false,
    hidden: bool = false,
};

/// One help entry per allowlisted host — driven by `host_launch.host_launch_aliases`.
fn hostAliasCommand(comptime host: []const u8) CommandInfo {
    return .{
        .name = host,
        .summary = "Launch " ++ host ++ " under Orca protection",
        .usage = "orca " ++ host ++ " [agent-args...]",
        .category = .core_workflow,
        .public = true,
        .examples = &.{"orca " ++ host},
        .details = &.{
            "Thin host launch alias: equivalent to `orca run -- " ++ host ++ " [agent-args...]`.",
            "Inherits agent-primary defaults (network ask; secretless off). Orca run flags stay on `orca run` only — everything after the host name is agent argv.",
        },
    };
}

fn hostAliasCommands() [host_launch.host_launch_aliases.len]CommandInfo {
    var out: [host_launch.host_launch_aliases.len]CommandInfo = undefined;
    inline for (host_launch.host_launch_aliases, 0..) |host, i| {
        out[i] = hostAliasCommand(host);
    }
    return out;
}

pub const commands =
    [_]CommandInfo{
        .{
            .name = "run",
            .summary = "Run a command under Orca (agent-primary defaults)",
            .usage = "orca run [options] -- <command> [args...]",
            .category = .core_workflow,
            .examples = &.{
                "orca claude",
                "orca pi",
                "orca run -- claude",
                "orca run --network allowlist -- pi",
                "orca run --no-network --no-secrets -- echo 'offline'",
                "orca run --secretless --network-backend proxy -- <command>",
                "orca run --os-sandbox on -- <command>",
            },
            .additional_completion_flags = &.{ "--workspace", "--policy", "--session-name", "--secretless", "--inherit-env", "--allow-network", "--network", "--network-backend", "--os-sandbox", "--require-backend" },
            .details = &.{
                "Starts a protected session, filters the child environment through policy, checks the command through a command safety check, writes audit artifacts, and mirrors the child exit code.",
                "Agent-primary defaults: network mode is ask when --network/--no-network are omitted (overrides policy network.mode for this run). Secretless stays off unless --secretless. Opt-outs: --network open|allowlist|observe|off|ask, --no-network.",
                "Host launch aliases (orca claude, orca pi, …) rewrite to this command with no extra flags — same defaults. Pass Orca run flags only on `orca run`, not after a host alias name.",
                "Options: --workspace <path>, --mode observe|ask|strict|ci, --policy <path>, --session-name <name>, --no-secrets, --secretless, --inherit-env, --no-network, --allow-network <domain>, --network observe|ask|allowlist|open|off, --network-backend decision-only|proxy, --os-sandbox auto|on|off, --require-backend <capability>, --help",
                "Strict and CI modes default to environments without secret access. --secretless replaces policy-visible secret env values with non-resolving orca-secret:// local-dummy references (not usable as raw model API keys; opt-in strip/demo only — not day-1 model auth). --inherit-env is allowed only when the selected policy permits inheritance.",
                "Network flags update the run-time policy and audit network decisions. --network-backend proxy starts an explicit localhost proxy and injects HTTP_PROXY/HTTPS_PROXY/ALL_PROXY; HTTPS CONNECT is host/port only without interception.",
                "--os-sandbox auto|on|off controls the OS filesystem sandbox (default auto). on fails closed when the platform backend cannot attach. auto: degrades loudly when no backend plan exists; fails closed on incomplete env scrub/allowlist; fails closed if attach fails after materials are prepared. off disables OS apply.",
                "Linux (Landlock): when active, the session banner reports workspace child RW with workspace-root RO — create/write at the workspace root is denied; write works under pre-existing non-control children. macOS (Seatbelt): full workspace subpath RW minus control-root carve-outs (create-at-root allowed). Neither path is network-sandboxed.",
                "Linux uses platform feature detection where available. Optional kernel features are reported honestly and are not claimed active unless actually active.",
            },
        },
    } ++ hostAliasCommands() ++ [_]CommandInfo{
    .{
        .name = "init",
        .summary = "Create an Orca policy",
        .usage = "orca init [--preset <name>] [--mode strict|ask|observe|ci|trusted] [--ci] [--force] [--quiet]",
        .category = .getting_started,
        .examples = &.{
            "orca init --preset generic-agent",
            "orca init --mode strict --force",
            "orca init --preset claude-code",
        },
        .details = &.{
            "Creates .orca/policy.yaml from a practical editable preset.",
            "Also enables preset-mapped safety packs in project `.orca.toml` (git repo) or user config (additive; never wipes customizations).",
            "Presets: generic-agent, claude-code, codex, cursor-agent, opencode, cline-roo, mcp-dev, github-actions, solo-dev, strict-local, team-ci, openclaw-hermes, trusted-local.",
            "Pack map: generic-agent/solo-dev/trusted-local/mcp-dev = baseline only; claude-code/codex/… = package_managers; team-ci/github-actions/openclaw-hermes = containers + k8s + terraform (+ GHA for CI); strict-local = strict_git.",
            "Refuses to overwrite an existing policy unless --force is provided.",
            "Use --quiet to suppress informational output in scripts.",
        },
    },
    .{
        .name = "start",
        .summary = "Get protected: wire hosts, policy, and Ask posture",
        .usage = "orca start [--auto|--yes|--no-interact] [--hosts <list>] [--preset <name>] [--skip-verify]",
        .category = .getting_started,
        .public = true,
        .examples = &.{
            "orca start",
            "orca start --auto",
            "orca start --auto --hosts codex,claude",
        },
        .details = &.{
            "Primary first-run onboarding — the only Safe Launch door.",
            "Creates a policy if missing (Ask on risk by default via generic-agent preset).",
            "Wires detected host integrations and verifies daemon/hook paths when available.",
            "Auto-selects the best available Ask posture — no protection-grade menu.",
            "On interactive terminals, prompts only for host selection when hosts are detected.",
            "On non-TTY terminals, auto-selects safe defaults (no --auto required).",
            "Use --auto to force non-interactive mode on a TTY; optional --hosts and --preset.",
            "Compatibility flags --yes and --no-interact also select non-interactive mode.",
            "Next steps after start: orca <agent> · orca status · orca replay.",
            "Re-run safely to repair or update an existing setup.",
        },
    },
    .{
        .name = "quickstart",
        .summary = "One-command onboarding: doctor, init, setup",
        .usage = "orca quickstart [--auto|--no-interact] [--preset <name>]",
        .category = .getting_started,
        .examples = &.{
            "orca quickstart",
            "orca quickstart --auto",
            "orca quickstart --preset strict-local",
        },
        .details = &.{
            "Runs doctor -> init (if needed) -> setup in one command.",
            "On interactive terminals, setup runs in guided mode.",
            "Use --auto for non-interactive environments (CI, scripts).",
            "The compatibility flag --no-interact also selects non-interactive mode.",
            "Use --preset to choose a policy preset (default: generic-agent).",
        },
    },
    .{
        .name = "setup",
        .summary = "Guided post-install setup for agent host integrations",
        .usage = "orca setup [--auto|--yes|--no-interact] [--preset <name>]",
        .category = .getting_started,
        .examples = &.{
            "orca setup",
            "orca setup --auto",
            "orca setup --preset strict-local",
        },
        .details = &.{
            "On interactive terminals (TTY), `orca setup` (no flags) enters guided mode with arrow-key host selection.",
            "Use ↑↓ to navigate, Space to toggle hosts, Enter to confirm.",
            "Use --auto (or --yes alias) for the fully automatic non-interactive path used by scripts/CI.",
            "The compatibility flag --no-interact also selects the non-interactive path.",
            "Use --preset to choose a policy preset (default: generic-agent).",
            "After setup, run 'orca run -- <your-command>' for immediate protection.",
        },
    },
    .{
        .name = "env",
        .summary = "Print shell environment for Orca",
        .usage = "orca env",
        .category = .getting_started,
        .details = &.{
            "Prints export statements for PATH and ORCA_RESOURCE_ROOT.",
            "Use with eval: eval \"$(orca env)\"",
        },
    },
    .{
        .name = "status",
        .summary = "One-glance protection snapshot",
        .usage = "orca status [--json] [--check]",
        .category = .getting_started,
        .public = true,
        .examples = &.{
            "orca status",
            "orca status --json",
            "orca status --check",
            "orca status --check --json",
        },
        .additional_completion_flags = &.{ "--json", "--check" },
        .details = &.{
            "Shows daemon health, policy path/mode/valid, hosts summary, enabled packs, and one next step.",
            "Status is the glance; `orca doctor` is the deep diagnostic.",
            "Packs summary uses the daemon registry (fail-closed note when the daemon is unavailable).",
            "Pack enablement is written to project `.orca.toml` when in a git repo, else user config (`$XDG_CONFIG_HOME/orca/config.toml` or `~/.config/orca/config.toml`).",
            "Use --json for scripting (includes schema_version, ready, state, policy.valid).",
            "Use --check for automation: exit non-zero when core readiness fails (daemon not compatible, or policy missing/invalid). Default without --check still prints the full report and exits 0.",
        },
    },
    .{
        .name = "doctor",
        .summary = "Show platform capabilities",
        .usage = "orca doctor [-v|--verbose] [--check] [--json]",
        .category = .getting_started,
        .examples = &.{
            "orca doctor",
            "orca doctor --verbose",
            "orca doctor --check",
            "orca doctor --json",
        },
        .additional_completion_flags = &.{ "--verbose", "-v", "--check", "--json" },
        .details = &.{
            "Default output is a one-line summary plus recommended next steps.",
            "Includes a Packs section (baseline always-on + opt-in enabled) when the daemon is reachable.",
            "Use --verbose for the full platform, integration, and capability report.",
            "Use --check for automation: exit non-zero when core readiness fails (daemon not compatible, or policy missing/invalid).",
            "Use --json for a minimal readiness report (ready, state, policy.valid).",
            "For a one-glance snapshot, prefer `orca status`.",
        },
    },
    .{
        .name = "test",
        .summary = "Test a shell command with Rust safety packs",
        .usage = "orca test <command> [options]",
        .category = .core_workflow,
        .examples = &.{
            "orca test \"git status\"",
            "orca test \"rm -rf /\" --format json",
        },
        .details = &.{
            "Proxies to the Rust daemon and evaluates the command with the Rust pack engine.",
            "The daemon response preserves the Rust CLI stdout, stderr, and exit code.",
        },
    },
    .{
        .name = "scan",
        .summary = "Scan files for destructive commands",
        .usage = "orca scan [--staged|--paths <path>...] [options]",
        .category = .core_workflow,
        .examples = &.{
            "orca scan --staged",
            "orca scan --paths scripts/deploy.sh --format json",
        },
        .details = &.{
            "Proxies to the Rust daemon for CI and pre-commit scanning.",
            "Use 'orca scan --help' for the full Rust-backed option set.",
        },
    },
    .{
        .name = "history",
        .summary = "Review protected command history",
        .usage = "orca history [stats|check|analyze|interactive|export|prune|backup] [options] [--days N] [--strict] [--live] [--json|--robot|--format <value>]",
        .category = .diagnostics,
        .examples = &.{
            "orca history stats --days 7",
            "orca history check --strict",
            "orca history --live",
        },
        .details = &.{
            "Human stats are rendered by Orca from structured history data.",
            "Use 'orca history --help' for actions and examples.",
            "--live opens a scrollable alt-screen view of the current stats snapshot (TTY only; not with --json).",
            "Use --json, --robot, or --format for machine-readable daemon output.",
        },
    },
    .{
        .name = "precommit",
        .summary = "Run the Rust pre-commit safety scan",
        .usage = "orca precommit [options]",
        .category = .core_workflow,
        .examples = &.{
            "orca precommit",
            "orca precommit --format json",
        },
        .details = &.{
            "Proxies to the Rust daemon and runs the staged-file pre-commit scan path.",
            "This is the Phase 1 user-facing alias for the Rust scan pre-commit workflow.",
        },
    },
    .{
        .name = "explain",
        .summary = "Explain why a shell command is blocked or allowed (Rust packs)",
        .usage = "orca explain <command> [options]",
        .category = .core_workflow,
        .public = true,
        .examples = &.{
            "orca explain \"git reset --hard\"",
            "orca explain \"rm -rf /tmp/x\" --format json",
        },
        .details = &.{
            "Proxies to the Rust daemon pack decision trace for shell commands.",
            "This is different from 'orca policy explain', which explains Zig .orca/policy.yaml rules for files/network/commands.",
            "Use 'orca explain --help' for the full Rust-backed option set.",
        },
    },
    .{
        .name = "classify",
        .summary = "Classify a shell command's risk without blocking",
        .usage = "orca classify <command> [options]",
        .category = .diagnostics,
        .examples = &.{
            "orca classify \"git status\"",
            "orca classify \"rm -rf /\" --format json",
        },
        .details = &.{
            "Proxies to the Rust daemon risk classifier (read-only; does not block).",
            "Use 'orca classify --help' for the full Rust-backed option set.",
        },
    },
    .{
        .name = "allowlist",
        .summary = "Manage allowlist entries for pack rules",
        .usage = "orca allowlist <add|list|remove|validate|prune|...> [options]",
        .category = .core_workflow,
        .examples = &.{
            "orca allowlist list",
            "orca allowlist add core.git:reset-hard -r \"intentional reset\"",
            "orca allow \"core.git:reset-hard\" -r \"intentional reset\"",
        },
        .details = &.{
            "Proxies to the Rust daemon allowlist manager.",
            "Shortcuts: 'orca allow <rule>' and 'orca unallow <rule>' also proxy.",
            "Use 'orca allowlist --help' for actions and options.",
        },
    },
    .{
        .name = "allow",
        .summary = "Add a rule to the allowlist (shortcut)",
        .usage = "orca allow <rule-id> -r <reason> [options]",
        .category = .core_workflow,
        .examples = &.{
            "orca allow core.git:reset-hard -r \"recovering local branch\"",
        },
        .details = &.{
            "Shortcut for 'orca allowlist add'. Proxies to the Rust daemon.",
        },
    },
    .{
        .name = "unallow",
        .summary = "Remove a rule from the allowlist (shortcut)",
        .usage = "orca unallow <rule-id> [options]",
        .category = .core_workflow,
        .examples = &.{
            "orca unallow core.git:reset-hard",
        },
        .details = &.{
            "Shortcut for 'orca allowlist remove'. Proxies to the Rust daemon.",
        },
    },
    .{
        .name = "allow-once",
        .summary = "Allow a blocked command once via short code",
        .usage = "orca allow-once <code|list|clear|revoke> [options]",
        .category = .core_workflow,
        .examples = &.{
            "orca allow-once list",
            "orca allow-once ABC123",
        },
        .details = &.{
            "Proxies to the Rust daemon pending-exception / allow-once store.",
            "Use 'orca allow-once --help' for apply and management subcommands.",
        },
    },
    .{
        .name = "suggest-allowlist",
        .summary = "Suggest allowlist entries from protected history",
        .usage = "orca suggest-allowlist [options]",
        .category = .diagnostics,
        .examples = &.{
            "orca suggest-allowlist",
            "orca suggest-allowlist --confidence high",
            "orca suggest-allowlist --format json",
            "orca history suggest",
        },
        .additional_completion_flags = &.{"--apply"},
        .details = &.{
            "Day-2 policy loop: denials → suggestions → allowlist.",
            "Proxies to the Rust daemon; requires history to be enabled.",
            "Human output includes copy-pasteable next commands (`suggest-allowlist --apply N` / `allowlist add-command`) for high-confidence items.",
            "Alias: `orca history suggest` (same as suggest-allowlist).",
            "Use 'orca suggest-allowlist --help' for filters and confidence options.",
        },
    },
    .{
        .name = "simulate",
        .summary = "Dry-run policy / packs against a command file or history dump",
        .usage = "orca simulate [--file <path>] [options]",
        .category = .diagnostics,
        .examples = &.{
            "orca simulate --file commands.txt",
            "orca simulate -f denials.jsonl --format pretty",
            "orca simulate --help",
        },
        .details = &.{
            "What-if dry-run for pack rollout and false-positive review before tightening modes.",
            "Proxies to the Rust daemon simulate engine (does not execute shell commands).",
            "Input is a file of commands or hook JSONL (use -f / --file; default stdin).",
            "Prints allow/deny counts and top denials. Use before enabling packs or switching to strict/ci.",
        },
    },
    .{
        .name = "rebase-recover",
        .summary = "Issue a short-lived permit for git rebase recovery",
        .usage = "orca rebase-recover [--ttl <seconds>]",
        .category = .core_workflow,
        .examples = &.{
            "orca rebase-recover",
            "orca rebase-recover --ttl 120",
        },
        .details = &.{
            "Proxies to the Rust daemon. Unblocks the next git checkout -- / restore",
            "step after a messy rebase recovery within a short TTL.",
        },
    },
    .{
        .name = "config",
        .summary = "Show Orca daemon configuration",
        .usage = "orca config",
        .category = .diagnostics,
        .examples = &.{
            "orca config",
        },
        .details = &.{
            "Proxies to the Rust daemon config show path (read-only).",
            "Use 'orca config --help' for daemon-backed details.",
        },
    },
    .{
        .name = "packs",
        .summary = "Browse, inspect, and enable safety packs",
        .usage =
        \\orca packs [--filter <term>] [--enabled|--installed] [--page N] [--page-size N]
        \\  orca packs show <id> [--no-patterns] [--verbose] [--format json]
        \\  orca packs enable <id> [id…]
        \\  orca packs disable <id> [id…]
        ,
        .category = .diagnostics,
        .examples = &.{
            "orca packs",
            "orca packs --enabled",
            "orca packs show core.git",
            "orca packs enable containers.docker database.postgresql",
            "orca packs disable containers.docker",
            "orca packs --filter database --page-size 10",
            "orca packs --format json",
        },
        .additional_completion_flags = &.{ "--robot", "--no-patterns", "--verbose" },
        .details = &.{
            "Safety packs are Rust shell-rule sets evaluated by the daemon (not policy presets).",
            "Policy presets use `orca policy packs` / `orca policy apply-pack` instead.",
            "List is sorted and paginated locally; --installed is an alias for --enabled.",
            "Baseline packs (core.*, system.disk) are always on; opt-in packs are enabled via config or `orca packs enable`.",
            "Enable/disable writes project `.orca.toml` in a git repo, otherwise user config (`$XDG_CONFIG_HOME/orca/config.toml` or `~/.config/orca/config.toml`).",
            "`orca packs show <id>` prefers daemon `pack info --json` (human view hides raw regex unless --verbose).",
            "Use --format json or --robot on the list path for byte-stable daemon output.",
        },
    },
    .{ .name = "policy", .summary = "Validate, explain, and apply policies", .usage = "orca policy <check|explain|packs|apply-pack> [...]", .category = .core_workflow, .additional_completion_flags = &.{ "--policy", "--method", "--force", "--preset" }, .examples = &.{
        "orca policy check",
        "orca policy check .orca/policy.yaml",
        "orca policy check --preset strict",
        "orca policy explain file.read /etc/passwd",
    }, .details = &.{
        "Subcommands:",
        "  orca policy check [policy-path]   # default: workspace .orca/policy.yaml (not builtin)",
        "  orca policy check --preset <observe|ask|strict|ci|redteam|trusted>",
        "  orca policy check builtin:<preset>",
        "  orca policy explain [--policy <path>] <file.read|file.write|env|command|network|mcp|tool> <target> [--method <HTTP_METHOD>]",
        "  orca policy packs",
        "  orca policy apply-pack <solo-dev|strict-local|team-ci|openclaw-hermes> [--force]",
        "policy check with no path validates the workspace policy only; missing policy fails (run orca init).",
        "Built-in presets require --preset or an explicit builtin:<name> path.",
        "policy explain covers Zig policy.yaml rules (file/env/network/mcp).",
        "For shell pack traces use 'orca explain \"<command>\"' instead.",
        "For effect-class tool classification use 'orca tools classify <name>'.",
    } },
    .{
        .name = "tools",
        .summary = "Classify tools into effect hits and list effect packs",
        .usage = "orca tools <classify|packs> [...]",
        .category = .diagnostics,
        .additional_completion_flags = &.{ "--args", "--policy" },
        .examples = &.{
            "orca tools classify send_email",
            "orca tools classify notify --args '{\"to\":\"a@b.com\",\"body\":\"hi\"}'",
            "orca tools classify send_email --policy .orca/policy.yaml",
            "orca tools packs",
        },
        .details = &.{
            "Discovery helpers for effect-class policy (not shell `orca classify`).",
            "  orca tools classify <name> [--args '<json-object>'] [--policy <path>]",
            "  orca tools packs",
            "Prints effect ids, confidence, and matcher labels only (never raw arg values).",
            "User effect packs load from ~/.config/orca/effect-packs and .orca/effect-packs.",
            "Packs extend classification only; allow/deny still requires policy effects:.",
        },
    },
    .{ .name = "credentials", .summary = "Verify credential brokers without exposing secrets", .usage = "orca credentials check [credential-ref]", .category = .advanced, .details = &.{
        "Checks configured credential brokers and optional credential refs without printing raw secret values.",
        "Supported broker kinds: local-dummy, env-file-dev, 1password-cli, macos-keychain, infisical-agent-vault.",
        "Infisical/Agent Vault is currently a status/config boundary until exact local API or CLI behavior is verified.",
    } },
    .{ .name = "report", .summary = "Export a safety report for a session", .usage = "orca report --session <id|last> --format markdown|json", .category = .diagnostics, .details = &.{
        "Loads a local session, verifies session integrity, and exports denied actions, redactions, plugin readiness, and a plain-language prevention summary.",
        "Report export is a Pro/Team local-license feature. Core safety commands remain available without a license.",
    } },
    .{ .name = "license", .summary = "Manage local offline licenses", .usage = "orca license <status|activate> [...]", .category = .advanced, .additional_completion_flags = &.{"--json"}, .details = &.{
        "Subcommands:",
        "  orca license status [--json]",
        "  orca license activate <key-or-file>",
        "Development keys: dev-free, dev-pro, dev-team.",
        "Licenses are verified offline and stored under the user config directory.",
    } },
    .{ .name = "ci", .summary = "Run local CI readiness checks", .usage = "orca ci check [--format markdown|json] [--github-summary <path>]", .category = .advanced, .details = &.{
        "Validates .orca/policy.yaml, rejects dangerous obvious defaults, runs a focused CI-safe redteam fixture, and emits GitHub Actions-friendly output.",
    } },
    .{ .name = "demo", .summary = "Create safe local demo evidence", .usage = "orca demo blocked-action", .category = .getting_started, .details = &.{
        "Creates a harmless local session showing a destructive command denied by Orca.",
        "The demo writes replay/report artifacts but does not execute the destructive command.",
    } },
    .{ .name = "shutdown", .summary = "Stop the background Orca daemon", .usage = "orca shutdown [--daemon]", .category = .advanced, .examples = &.{
        "orca shutdown",
        "orca shutdown --daemon",
    }, .details = &.{
        "Sends a graceful Shutdown request to the Rust daemon over UDS.",
        "Removes $HOME/.orca/daemon.sock and daemon.pid when shutdown succeeds.",
        "When the daemon is not running, stale artifacts are cleaned when safe.",
    } },
    .{ .name = "stop", .summary = "Stop Orca protection for host agents", .usage = "orca stop [codex|claude|cursor|opencode|openclaw|hermes|all] [--yes]", .category = .integrations, .public = true, .examples = &.{
        "orca stop",
        "orca stop codex",
        "orca stop cursor",
    }, .details = &.{
        "Removes Orca plugin registrations from host agents without removing the Orca binary or policy files.",
        "Hosts: codex, claude, cursor, opencode, openclaw, hermes. Defaults to all if no host is specified.",
        "Cursor: removes the Orca shell hook wrapper and disables simple Orca-only hooks.json files.",
        "OpenCode: removes .opencode/plugins/orca.ts and ~/.config/opencode/plugins/orca.ts",
        "OpenClaw: runs 'openclaw plugins uninstall orca-openclaw-plugin'",
        "Hermes: runs 'hermes plugins disable orca' and removes ~/.hermes/plugins/orca/",
        "Codex / Claude: removes known plugin paths (host-managed install locations).",
        "Restart protection later with: orca setup (guided) or orca plugin install <host>",
    } },
    .{ .name = "uninstall", .summary = "Uninstall Orca from this machine", .usage = "orca uninstall [--plugins-only] [--keep-config] [--yes]", .category = .integrations, .details = &.{
        "Completely removes Orca and its integrations from the machine.",
        "Steps:",
        "  1. Removes all plugins from host agents (same as 'orca stop').",
        "  2. Removes the Orca binary from known locations (~/.local/bin/orca, PATH).",
        "  3. Removes user config and data (~/.config/orca/, ~/.orca).",
        "Options:",
        "  --plugins-only   Only remove plugins; keep binary and config.",
        "  --keep-config    Remove plugins and binary but keep ~/.config/orca/.",
        "  --yes            Skip confirmation prompt.",
        "Local workspace .orca/ directories are not removed automatically;",
        "run 'find . -type d -name .orca' to locate them manually.",
    } },
    .{ .name = "replay", .summary = "Replay an audit session", .usage = "orca replay [--list] [--session <id|last>] [--json] [--only denied] [--verify] [--tui]", .category = .core_workflow, .public = true, .examples = &.{
        "orca replay",
        "orca replay --list",
        "orca replay --session last",
        "orca replay --session 2026-05-29-abc123",
        "orca replay --session last --tui",
    }, .details = &.{
        "Reads .orca session artifacts, renders a timeline, and can verify session integrity.",
        "With no args and no sessions, lists available sessions instead of erroring.",
        "Use --list to print all session IDs under .orca/sessions/.",
        "--tui opens a scrollable alt-screen timeline view (TTY only; not with --json).",
    } },
    .{
        .name = "diff",
        .summary = "Show pending file changes",
        .usage = "orca diff [--session <id|last>] [--file <path>]",
        .category = .staged_changes,
        .details = &.{
            "Shows unified diffs for Orca-mediated pending file changes.",
            "Use 'orca apply' to commit changes or 'orca discard' to cancel them.",
        },
    },
    .{
        .name = "apply",
        .summary = "Commit pending file changes",
        .usage = "orca apply [--session <id|last>] [--file <path>] [--dry-run] [--yes]",
        .category = .staged_changes,
        .additional_completion_flags = &.{ "--dry-run", "--yes" },
        .details = &.{
            "Applies reviewed pending file changes after original-state checks where feasible.",
            "--dry-run prints a summary without mutating; non-interactive mutation requires --yes.",
            "Interactive confirm defaults to No (empty Enter cancels).",
            "See 'orca diff' to review changes and 'orca discard' to cancel them.",
        },
    },
    .{
        .name = "discard",
        .summary = "Reject pending file changes",
        .usage = "orca discard [--session <id|last>] [--file <path>] [--dry-run] [--yes]",
        .category = .staged_changes,
        .additional_completion_flags = &.{ "--dry-run", "--yes" },
        .details = &.{
            "Destroys proposed staged changes without changing workspace files.",
            "--dry-run prints a summary without mutating; non-interactive mutation requires --yes.",
            "Interactive confirm defaults to No and warns that discard destroys proposed staged changes.",
            "See 'orca diff' to review changes and 'orca apply' to commit them.",
        },
    },
    .{ .name = "mcp", .summary = "Inspect and proxy MCP servers", .usage = "orca mcp <inspect|proxy|list|trust|manifest> [options]", .category = .advanced, .additional_completion_flags = &.{ "--command", "--name", "--policy", "--manifest", "--mode", "--tool", "--server" }, .details = &.{
        "Subcommands:",
        "  orca mcp inspect --command <server> [--name <server-name>] [--policy <path>]",
        "  orca mcp proxy --command <server> [--name <server-name>] [--policy <path>] [--manifest <path>] [--mode observe|ask|strict|ci]",
        "  orca mcp list",
        "  orca mcp trust <server> --tool <tool>",
        "  orca mcp manifest check <manifest.yaml>",
        "  orca mcp manifest generate --command <server-command> | --server <name>",
        "The proxy handles MCP server communication over stdio and forwards messages transparently.",
        "Remote HTTP MCP, OAuth, and hosted gateway behavior are limited/deferred in Phase 17.",
    } },
    .{ .name = "redteam", .summary = "Run built-in fixture engine self-tests (not your workspace policy)", .usage = "orca redteam [path] [--json] [--ci] [--fixture <id>]", .category = .advanced, .details = &.{
        "Runs deterministic local fixtures against the internal builtin:redteam preset with synthetic in-process (Zig) evaluation.",
        "This is an engine self-test: it does not load .orca/policy.yaml, does not exercise the Rust daemon shell path, and does not prove wrapper/host/proxy/OS enforcement.",
        "Reports include provenance (suite_kind, policy, evaluator, real_action_attempted=false). A 100% score is not workspace-policy assurance.",
        "When no path is provided, fixtures are discovered under ./fixtures (or installed resource fixtures).",
        "--json emits a machine-readable report with a provenance object. --ci never prompts and exits non-zero if any required fixture fails or is unsupported.",
    } },
    .{ .name = "completions", .summary = "Generate shell completions", .usage = "orca completions <bash|zsh|fish|powershell>", .category = .getting_started, .details = &.{
        "Prints a completion script to stdout for the requested shell.",
        "The generated completions include top-level commands and common flags.",
    } },
    .{ .name = "shim", .summary = "Internal callback for session-local PATH shims", .usage = "orca shim exec -- <command> [args...]", .category = .internal, .hidden = true, .details = &.{
        "Internal callback used by session-local PATH shims under .orca/sessions/<id>/shims/.",
        "The shim removes the session shim directory from PATH before resolving the real binary to avoid recursive invocation.",
        "This is wrapper-level coverage only and does not claim transparent OS-level interception.",
    } },
    .{ .name = "version", .summary = "Print version", .usage = "orca version [--json] [--help]", .category = .diagnostics, .details = &.{
        "Prints the current Orca version.",
        "--json emits version, commit, target, and build_date fields for release automation.",
    } },
    .{ .name = "plugin", .summary = "Plugin management and diagnostics", .usage = "orca plugin <list|host|doctor|manifest|install> [options]", .category = .integrations, .additional_completion_flags = &.{ "--dry-run", "--yes", "--json", "--path" }, .details = &.{
        "Subcommands:",
        "  orca plugin list",
        "  orca plugin <codex|claude|opencode|openclaw|hermes> [--dry-run|--yes]",
        "  orca plugin doctor [codex|claude|opencode|openclaw|hermes] [--json]",
        "  orca plugin manifest [codex|claude|opencode|openclaw|hermes|all] [--json]",
        "  orca plugin install                                 # dry-run preview of all hosts (no mutation)",
        "  orca plugin install <codex|claude|opencode|openclaw|hermes|all> [--dry-run|--yes] [--path <path>]",
        "Primary onboarding path: run `orca setup` (guided interactive selection on TTY terminals).",
        "Bare install never mutates; mutation requires an explicit host or `all` plus --yes (confirm default No on TTY).",
        "Plugin doctor does not print secrets.",
    } },
    .{ .name = "decide", .summary = "Ask Orca whether an action is allowed by policy", .usage = "orca decide <command|file|prompt|tool> (--json <payload>|--stdin) [--ci] [--human]", .category = .advanced, .details = &.{
        "Evaluates a policy decision for host plugins (Codex, Claude Code, OpenCode, etc.).",
        "Subcommands:",
        "  orca decide command --json '{\"command\":\"<cmd>\"}'",
        "  orca decide file    --json '{\"path\":\"<p>\",\"operation\":\"read|write\"}'",
        "  orca decide prompt  --json '{\"text\":\"<text>\"}'",
        "  orca decide tool    --json '{\"name\":\"<name>\"}'",
        "  orca decide <kind> --stdin",
        "  orca decide <kind> --json <payload> [--ci]",
        "Default output is stable JSON; add --human for a decision badge, details, and risk meter.",
        "Debug logs go to stderr only.",
    } },
    .{ .name = "evaluate", .summary = "Stable machine API for shell-command evaluation", .usage = "orca evaluate --json --stdin", .category = .integrations, .details = &.{
        "Reads a versioned JSON request from stdin and evaluates shell_command events through the Rust daemon Evaluate path.",
        "Requires schema_version=1, kind=shell_command, command string, and an absolute existing cwd.",
        "Always writes the stable integration JSON response to stdout for invalid input and expected daemon outcomes.",
        "Exit codes: 0 allow, 2 deny, 3 daemon/protocol failure, 64 invalid input, 1 unexpected internal error.",
        "Designed for external integrations such as Pi bash tool-call evaluation; non-shell evaluation is intentionally unsupported.",
    } },
    .{ .name = "hook", .summary = "Receive events from AI agent hosts", .usage = "orca hook <codex|claude|opencode|openclaw|hermes> <event> [--ci]", .category = .advanced, .details = &.{
        "Reads a JSON payload from stdin, normalizes host-specific events to Orca decisions,",
        "and emits a host-valid JSON response to stdout. Debug logs go to stderr only.",
        "Events:",
        "  orca hook codex SessionStart",
        "  orca hook codex UserPromptSubmit",
        "  orca hook codex PreToolUse",
        "  orca hook codex PermissionRequest",
        "  orca hook codex PostToolUse",
        "  orca hook codex Stop",
        "  orca hook claude SessionStart",
        "  orca hook claude UserPromptSubmit",
        "  orca hook claude PreToolUse",
        "  orca hook claude PermissionRequest",
        "  orca hook claude PostToolUse",
        "  orca hook claude SessionEnd",
        "  orca hook opencode session.created",
        "  orca hook opencode tool.execute.before",
        "  orca hook opencode tool.execute.after",
        "  orca hook opencode permission.asked",
        "  orca hook opencode permission.replied",
        "  orca hook opencode file.edited",
        "  orca hook opencode command.executed",
        "  orca hook opencode session.updated",
        "  orca hook opencode session.idle",
        "  orca hook opencode session.error",
        "  orca hook opencode shell.env",
        "  orca hook openclaw session.start",
        "  orca hook openclaw tool.before",
        "  orca hook openclaw tool.after",
        "  orca hook openclaw permission.before",
        "  orca hook openclaw permission.after",
        "  orca hook openclaw session.end",
        "  orca hook hermes on_session_start",
        "  orca hook hermes pre_tool_call",
        "  orca hook hermes post_tool_call",
        "  orca hook hermes pre_llm_call",
        "  orca hook hermes post_llm_call",
        "  orca hook hermes subagent_stop",
        "  orca hook hermes on_session_end",
        "Hook responses include host_limitations to honestly report enforcement limits.",
    } },
    .{ .name = "dashboard", .summary = "Start the local Orca dashboard", .usage = "orca dashboard [--machine | --workspace PATH] [--host 127.0.0.1] [--port 7742] [--once]", .category = .diagnostics, .details = &.{
        "Starts a localhost-only machine-wide dashboard by default; the view is not tied to shell cwd.",
        "Use --workspace PATH or ORCA_DASHBOARD_WORKSPACE for policy, integrations, and workspace-scoped actions.",
        "The dashboard calls existing Orca CLI/Core paths and does not replace policy evaluation.",
        "Mutation routes use a per-run browser token and only expose fixed Orca actions; arbitrary shell commands are not accepted.",
        "Defaults to http://127.0.0.1:7742.",
        "LAN and non-loopback binds (for example 0.0.0.0) are rejected; the dashboard is intentionally localhost-only.",
        "Use --once to serve one request for smoke tests and automation.",
    } },
    .{ .name = "help", .summary = "Show help", .usage = "orca help [command|--all]", .category = .getting_started, .details = &.{
        "Shows Safe Launch help by default (public verbs only).",
        "Use `orca help --all` for the full command surface.",
        "Use `orca help <command>` for command-specific help.",
    } },
};

/// Prefix of Safe Launch teaching order (host aliases inserted after stop).
const public_help_prefix = [_][]const u8{ "start", "stop" };
/// Suffix of Safe Launch teaching order (after host aliases).
const public_help_suffix = [_][]const u8{ "status", "replay", "explain" };

pub const WriteMode = enum {
    /// Safe Launch surface only (default `orca` / `orca help`).
    public,
    /// Full command surface (`orca help --all`).
    all,
};

/// Default root help: public Safe Launch verbs only.
pub fn write(io: std.Io, writer: anytype) !void {
    try writeWithMode(io, writer, .public);
}

/// Full root help including advanced / power commands.
pub fn writeAll(io: std.Io, writer: anytype) !void {
    try writeWithMode(io, writer, .all);
}

pub fn writeWithMode(io: std.Io, writer: anytype, mode: WriteMode) !void {
    // Compact brand header (Phase 2 brand cohesion).
    try tui.render.banner(io, writer, build_options.version, null);
    try tui.theme.paint(io, writer, .muted, "Graded policy mediation for AI agent actions");
    try writer.writeAll("\n\n");
    try writer.writeAll("Usage:\n  orca <command> [options]\n\n");

    // Task-oriented primary paths — Safe Launch loop on default; richer on --all.
    try writer.writeAll("  ");
    try tui.theme.paintBold(io, writer, .brand, "Common tasks");
    try writer.writeAll("\n");
    const Task = struct { label: []const u8, cmd: []const u8 };
    const public_tasks = [_]Task{
        .{ .label = "Get protected", .cmd = "orca start" },
        .{ .label = "Run an agent", .cmd = "orca claude  (or: codex | pi | opencode | openclaw | hermes)" },
        .{ .label = "See status", .cmd = "orca status" },
        .{ .label = "Review session", .cmd = "orca replay" },
        .{ .label = "Why blocked?", .cmd = "orca explain \"…\"" },
        .{ .label = "Stop protection", .cmd = "orca stop" },
    };
    const all_tasks = [_]Task{
        .{ .label = "Get protected", .cmd = "orca start" },
        .{ .label = "See status", .cmd = "orca status" },
        .{ .label = "Deep diagnose", .cmd = "orca doctor" },
        .{ .label = "Why blocked?", .cmd = "orca explain \"…\"" },
        .{ .label = "Run an agent", .cmd = "orca claude  (or: orca pi | orca run -- <agent>)" },
        .{ .label = "Wire a host", .cmd = "orca plugin install" },
        .{ .label = "Review session", .cmd = "orca replay" },
        .{ .label = "Stop protection", .cmd = "orca stop" },
    };
    const tasks: []const Task = switch (mode) {
        .public => &public_tasks,
        .all => &all_tasks,
    };
    var task_label_width: usize = 0;
    for (tasks) |task| {
        const w = tui.render.displayWidth(task.label);
        if (w > task_label_width) task_label_width = w;
    }
    for (tasks) |task| {
        try writer.writeAll("    ");
        try tui.theme.paint(io, writer, .text_bright, task.label);
        try tui.render.writePadded(writer, "", task_label_width - tui.render.displayWidth(task.label) + 2);
        try writer.writeAll(task.cmd);
        try writer.writeAll("\n");
    }
    try writer.writeAll("\n");
    if (mode == .all) {
        try writer.writeAll("  ");
        try tui.theme.paint(io, writer, .muted, "Shell deny remediation: orca explain / allow-once / allowlist (daemon). Policy files: orca policy explain.");
        try writer.writeAll("\n\n");
    }

    // Compute a uniform command-name column width across listed commands.
    var name_width: usize = 0;
    for (commands) |cmd| {
        if (cmd.hidden) continue;
        if (mode == .public and !cmd.public) continue;
        const w = tui.render.displayWidth(cmd.name);
        if (w > name_width) name_width = w;
    }

    switch (mode) {
        .public => {
            try writer.writeAll("  ");
            try tui.theme.paintBold(io, writer, .brand, "Commands");
            try writer.writeAll("\n");
            // Teaching order: start → stop → host aliases → status → replay → explain
            for (public_help_prefix) |name| {
                try writeCommandRow(io, writer, name, name_width);
            }
            for (host_launch.host_launch_aliases) |host| {
                try writeCommandRow(io, writer, host, name_width);
            }
            for (public_help_suffix) |name| {
                try writeCommandRow(io, writer, name, name_width);
            }
            try writer.writeAll("\n");
            try writer.writeAll("  ");
            try tui.theme.paint(io, writer, .muted, "Power features:");
            try writer.writeAll(" ");
            try tui.theme.paint(io, writer, .text_bright, "orca help --all");
            try writer.writeAll("\n\n");
        },
        .all => {
            const categories = comptime std.enums.values(Category);
            for (categories) |cat| {
                if (cat == .internal) continue; // hide internal group entirely
                var any = false;
                for (commands) |cmd| {
                    if (cmd.hidden or cmd.category != cat) continue;
                    if (!any) {
                        try writer.writeAll("  ");
                        try tui.theme.paintBold(io, writer, .brand, categoryTitle(cat));
                        try writer.writeAll("\n");
                        any = true;
                    }
                    try writer.writeAll("    ");
                    try tui.theme.paint(io, writer, .text_bright, cmd.name);
                    try tui.render.writePadded(writer, "", name_width - tui.render.displayWidth(cmd.name) + 2);
                    try writer.writeAll(cmd.summary);
                    try writer.writeAll("\n");
                }
                if (any) try writer.writeAll("\n");
            }
        },
    }

    // Global options (Phase 7 discoverability): surface the --no-rich /
    // ORCA_NO_RICH escape hatch at the top level so users can find it without
    // reading the source. --json/--robot are per-command machine flags.
    try writer.writeAll("  ");
    try tui.theme.paintBold(io, writer, .brand, "Global options");
    try writer.writeAll("\n");
    try writer.writeAll("    --no-rich   Plain text output (no colour, no animation). ");
    try tui.theme.paint(io, writer, .muted, "Also ORCA_NO_RICH=1.");
    try writer.writeAll("\n");
    try writer.writeAll("                 Use this for piping, scripting, or terminals that mis-render colour.\n");
    try writer.writeAll("    --json      Per-command machine output (byte-stable). See `orca help <command>`.\n");
    try writer.writeAll("\n");

    // Try-next hint.
    try writer.writeAll("  ");
    try tui.theme.paint(io, writer, .muted, "Next:");
    try writer.writeAll(" run ");
    try tui.theme.paint(io, writer, .text_bright, "orca start");
    try writer.writeAll(" to get protected, or ");
    if (mode == .public) {
        try tui.theme.paint(io, writer, .text_bright, "orca help --all");
        try writer.writeAll(" for the full surface.\n");
    } else {
        try tui.theme.paint(io, writer, .text_bright, "orca help <command>");
        try writer.writeAll(" for details.\n");
    }
}

fn categoryTitle(cat: Category) []const u8 {
    return switch (cat) {
        .getting_started => "Getting Started",
        .core_workflow => "Core Workflow",
        .staged_changes => "Staged Changes",
        .diagnostics => "Diagnostics & Reporting",
        .integrations => "Integrations",
        .advanced => "Advanced",
        .internal => "Internal",
    };
}

fn writeCommandRow(io: std.Io, writer: anytype, name: []const u8, name_width: usize) !void {
    const cmd = findCommand(name) orelse return;
    if (cmd.hidden or !cmd.public) return;
    try writer.writeAll("    ");
    try tui.theme.paint(io, writer, .text_bright, cmd.name);
    try tui.render.writePadded(writer, "", name_width - tui.render.displayWidth(cmd.name) + 2);
    try writer.writeAll(cmd.summary);
    try writer.writeAll("\n");
}

pub fn writeCommand(io: std.Io, writer: anytype, name: []const u8) !bool {
    // Progressive disclosure: `orca help --all` reuses the existing single-arg
    // help dispatch path without changing top-level argv parsing.
    if (std.mem.eql(u8, name, "--all") or std.mem.eql(u8, name, "all")) {
        try writeAll(io, writer);
        return true;
    }
    const command = findCommand(name) orelse return false;
    try writer.print("{s}\n\nUsage:\n  {s}\n\n", .{ command.summary, command.usage });

    if (command.examples.len > 0) {
        try writer.writeAll("Examples:\n");
        for (command.examples) |example| {
            try writer.print("  {s}\n", .{example});
        }
        try writer.writeAll("\n");
    }

    for (command.details) |line| {
        try writer.print("{s}\n", .{line});
    }
    return true;
}

pub fn findCommand(name: []const u8) ?CommandInfo {
    for (commands) |command| {
        if (std.mem.eql(u8, command.name, name)) return command;
    }
    return null;
}

test "run help documents --os-sandbox auto degrade and fail-closed paths" {
    const info = findCommand("run") orelse return error.TestUnexpectedResult;
    var joined: [4096]u8 = undefined;
    var w: std.Io.Writer = .fixed(&joined);
    for (info.details) |line| {
        try w.writeAll(line);
        try w.writeAll("\n");
    }
    const text = w.buffered();
    try std.testing.expect(std.mem.indexOf(u8, text, "--os-sandbox auto|on|off") != null);
    // Three auto outcomes (Z-6): degrade when no backend plan; scrub fail-closed; attach fail-closed.
    try std.testing.expect(std.mem.indexOf(u8, text, "degrades loudly when no backend plan exists") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "fails closed on incomplete env scrub/allowlist") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "fails closed if attach fails after materials are prepared") != null);
}

test "host launch allowlist is the single source for help alias entries" {
    for (host_launch.host_launch_aliases) |host| {
        const info = findCommand(host) orelse {
            std.debug.print("missing help entry for host launch alias: {s}\n", .{host});
            try std.testing.expect(false);
            return;
        };
        try std.testing.expectEqualStrings(host, info.name);
        try std.testing.expect(std.mem.indexOf(u8, info.summary, host) != null);
        try std.testing.expect(std.mem.indexOf(u8, info.usage, host) != null);
        try std.testing.expect(std.mem.indexOf(u8, info.details[0], "orca run -- ") != null);
        try std.testing.expect(std.mem.indexOf(u8, info.details[1], "secretless off") != null);
    }
    try std.testing.expect(findCommand("notanagent") == null);
    try std.testing.expect(!host_launch.isHostLaunchAlias("notanagent"));
}

test "top help and per-host help surface claude and pi aliases" {
    var buf: [24576]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    try write(std.testing.io, &writer);
    const top = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, top, "claude") != null);
    try std.testing.expect(std.mem.indexOf(u8, top, "pi") != null);
    try std.testing.expect(std.mem.indexOf(u8, top, "orca claude") != null);

    writer = .fixed(&buf);
    try std.testing.expect(try writeCommand(std.testing.io, &writer, "claude"));
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "orca run -- claude") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "secretless off") != null);

    writer = .fixed(&buf);
    try std.testing.expect(try writeCommand(std.testing.io, &writer, "pi"));
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "orca run -- pi") != null);
}

/// True when root help lists `name` as a left-column peer command (not Common tasks / prose).
fn helpListsPeerCommand(text: []const u8, name: []const u8) bool {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "    ")) continue;
        if (std.mem.startsWith(u8, line, "    --")) continue;
        const rest = line[4..];
        if (rest.len <= name.len) continue;
        if (std.mem.startsWith(u8, rest, name) and rest[name.len] == ' ') return true;
    }
    return false;
}

test "default root help shows only public Safe Launch verbs" {
    var buf: [24576]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    try write(std.testing.io, &writer);
    const top = writer.buffered();

    // Public Safe Launch verbs as command peers
    try std.testing.expect(helpListsPeerCommand(top, "start"));
    try std.testing.expect(helpListsPeerCommand(top, "stop"));
    try std.testing.expect(helpListsPeerCommand(top, "status"));
    try std.testing.expect(helpListsPeerCommand(top, "replay"));
    try std.testing.expect(helpListsPeerCommand(top, "explain"));
    for (host_launch.host_launch_aliases) |host| {
        try std.testing.expect(helpListsPeerCommand(top, host));
    }

    // Common tasks teach start → agent → status → replay
    try std.testing.expect(std.mem.indexOf(u8, top, "orca start") != null);
    try std.testing.expect(std.mem.indexOf(u8, top, "orca status") != null);
    try std.testing.expect(std.mem.indexOf(u8, top, "orca replay") != null);
    try std.testing.expect(std.mem.indexOf(u8, top, "orca claude") != null);

    // Progressive disclosure escape hatch
    try std.testing.expect(std.mem.indexOf(u8, top, "help --all") != null);

    // Not Getting Started / public peers
    try std.testing.expect(!helpListsPeerCommand(top, "quickstart"));
    try std.testing.expect(!helpListsPeerCommand(top, "setup"));
    try std.testing.expect(!helpListsPeerCommand(top, "init"));
    try std.testing.expect(!helpListsPeerCommand(top, "run"));
    try std.testing.expect(!helpListsPeerCommand(top, "doctor"));
    try std.testing.expect(!helpListsPeerCommand(top, "history"));
    try std.testing.expect(!helpListsPeerCommand(top, "policy"));
    try std.testing.expect(!helpListsPeerCommand(top, "mcp"));
}

test "help --all lists full advanced command surface" {
    var buf: [32768]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    try std.testing.expect(try writeCommand(std.testing.io, &writer, "--all"));
    const all = writer.buffered();

    try std.testing.expect(helpListsPeerCommand(all, "start"));
    try std.testing.expect(helpListsPeerCommand(all, "run"));
    try std.testing.expect(helpListsPeerCommand(all, "doctor"));
    try std.testing.expect(helpListsPeerCommand(all, "policy"));
    try std.testing.expect(helpListsPeerCommand(all, "history"));
    try std.testing.expect(helpListsPeerCommand(all, "init"));
    try std.testing.expect(helpListsPeerCommand(all, "mcp"));
    try std.testing.expect(helpListsPeerCommand(all, "env"));
    // Still present on full surface until hard-delete units remove them
    try std.testing.expect(helpListsPeerCommand(all, "quickstart"));
    try std.testing.expect(helpListsPeerCommand(all, "setup"));
}
