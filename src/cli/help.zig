const std = @import("std");
const style = @import("style.zig");

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
    category: Category = .advanced,
    hidden: bool = false,
};

pub const commands = [_]CommandInfo{
    .{
        .name = "run",
        .summary = "Run a command under Orca",
        .usage = "orca run [options] -- <command> [args...]",
        .category = .core_workflow,
        .examples = &.{
            "orca run -- echo 'hello world'",
            "orca run --mode strict -- codex",
            "orca run --no-network --no-secrets -- claude",
        },
        .details = &.{
            "Starts a protected session, filters the child environment through policy, checks the command through a command safety check, writes audit artifacts, and mirrors the child exit code.",
            "Options: --workspace <path>, --mode observe|ask|strict|ci, --policy <path>, --session-name <name>, --no-secrets, --secretless, --inherit-env, --no-network, --allow-network <domain>, --network observe|ask|allowlist|open|off, --network-backend decision-only|proxy, --require-backend <capability>, --help",
            "Strict and CI modes default to environments without secret access. --secretless replaces policy-visible secret env values with credential references instead of raw values. --inherit-env is allowed only when the selected policy permits inheritance.",
            "Network flags update the run-time policy and audit network decisions. --network-backend proxy starts an explicit localhost proxy and injects HTTP_PROXY/HTTPS_PROXY/ALL_PROXY; HTTPS CONNECT is host/port only without interception.",
            "Linux uses platform feature detection where available. Optional kernel features are reported honestly and are not claimed active unless actually active.",
        },
    },
    .{
        .name = "init",
        .summary = "Create an Orca policy",
        .usage = "orca init [--preset <name>] [--mode strict|ask|observe|ci|trusted] [--ci] [--force]",
        .category = .getting_started,
        .examples = &.{
            "orca init --preset generic-agent",
            "orca init --mode strict --force",
            "orca init --preset claude-code",
        },
        .details = &.{
            "Creates .orca/policy.yaml from a practical editable preset.",
            "Presets: generic-agent, claude-code, codex, cursor-agent, opencode, cline-roo, mcp-dev, github-actions, solo-dev, strict-local, team-ci, openclaw-hermes, trusted-local.",
            "Refuses to overwrite an existing policy unless --force is provided.",
        },
    },
    .{
        .name = "quickstart",
        .summary = "One-command onboarding: doctor, init, setup",
        .usage = "orca quickstart [--auto] [--preset <name>]",
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
            "Use --preset to choose a policy preset (default: generic-agent).",
        },
    },
    .{
        .name = "setup",
        .summary = "Guided post-install setup for agent host integrations",
        .usage = "orca setup [--auto] [--preset <name>]",
        .category = .getting_started,
        .examples = &.{
            "orca setup",
            "orca setup --auto",
            "orca setup --preset strict-local",
        },
        .details = &.{
            "On interactive terminals (TTY), `orca setup` (no flags) enters guided mode with a numbered host selector.",
            "Enter space-separated numbers (e.g. 1 3), 'all', 'none', or press Enter to accept defaults.",
            "Use --auto (or --yes alias) for the fully automatic non-interactive path used by scripts/CI.",
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
        .name = "doctor",
        .summary = "Show platform capabilities",
        .usage = "orca doctor [-v|--verbose]",
        .category = .getting_started,
        .examples = &.{
            "orca doctor",
            "orca doctor --verbose",
        },
        .details = &.{
            "Default output is a one-line summary plus recommended next steps.",
            "Use --verbose for the full platform, integration, and capability report.",
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
        .summary = "Query Rust command history",
        .usage = "orca history <action> [options]",
        .category = .diagnostics,
        .examples = &.{
            "orca history stats --days 7",
            "orca history check --strict",
        },
        .details = &.{
            "Proxies to the Rust daemon so history queries use the Rust SQLite-backed history store.",
            "Use 'orca history --help' for the full Rust-backed action list.",
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
        .name = "packs",
        .summary = "List Rust safety packs",
        .usage = "orca packs [--enabled] [--format pretty|json]",
        .category = .diagnostics,
        .examples = &.{
            "orca packs",
            "orca packs --format json",
        },
        .details = &.{
            "Proxies to the Rust daemon and lists built-in and configured external safety packs.",
            "Use 'orca packs --help' for the full Rust-backed option set.",
        },
    },
    .{ .name = "policy", .summary = "Validate, explain, and apply policies", .usage = "orca policy <check|explain|packs|apply-pack> [...]", .category = .core_workflow, .examples = &.{
        "orca policy check .orca/policy.yaml",
        "orca policy explain file.read /etc/passwd",
    }, .details = &.{
        "Subcommands:",
        "  orca policy check <policy-path>",
        "  orca policy explain [--policy <path>] <file.read|file.write|env|command|network|mcp> <target> [--method <HTTP_METHOD>]",
        "  orca policy packs",
        "  orca policy apply-pack <solo-dev|strict-local|team-ci|openclaw-hermes> [--force]",
        "Explanations show the decision, reason, matched rule when available, and policy mode.",
    } },
    .{ .name = "credentials", .summary = "Verify credential brokers without exposing secrets", .usage = "orca credentials check [credential-ref]", .category = .advanced, .details = &.{
        "Checks configured credential brokers and optional credential refs without printing raw secret values.",
        "Supported broker kinds: local-dummy, env-file-dev, 1password-cli, macos-keychain, infisical-agent-vault.",
        "Infisical/Agent Vault is currently a status/config boundary until exact local API or CLI behavior is verified.",
    } },
    .{ .name = "report", .summary = "Export a safety report for a session", .usage = "orca report --session <id|last> --format markdown|json", .category = .diagnostics, .details = &.{
        "Loads a local session, verifies session integrity, and exports denied actions, redactions, plugin readiness, and a plain-language prevention summary.",
        "Report export is a Pro/Team local-license feature. Core safety commands remain available without a license.",
    } },
    .{ .name = "license", .summary = "Manage local offline licenses", .usage = "orca license <status|activate> [...]", .category = .advanced, .details = &.{
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
    .{ .name = "disable", .summary = "Disable Orca plugins from host agents", .usage = "orca disable [codex|claude|opencode|openclaw|hermes|all] [--yes]", .category = .integrations, .details = &.{
        "Removes Orca plugin registrations from host agents without removing the Orca binary or policy files.",
        "Hosts: codex, claude, opencode, openclaw, hermes. Defaults to all if no host is specified.",
        "OpenCode: removes .opencode/plugins/orca.ts and ~/.config/opencode/plugins/orca.ts",
        "OpenClaw: runs 'openclaw plugins uninstall orca-openclaw-plugin'",
        "Hermes: runs 'hermes plugins disable orca' and removes ~/.hermes/plugins/orca/",
        "Codex / Claude: removes known plugin paths (host-managed install locations).",
        "Re-enable later with: orca setup (guided) or orca plugin install <host>",
    } },
    .{ .name = "uninstall", .summary = "Uninstall Orca from this machine", .usage = "orca uninstall [--plugins-only] [--keep-config] [--yes]", .category = .integrations, .details = &.{
        "Completely removes Orca and its integrations from the machine.",
        "Steps:",
        "  1. Removes all plugins from host agents (same as 'orca disable').",
        "  2. Removes the Orca binary from known locations (~/.local/bin/orca, PATH).",
        "  3. Removes user config and data (~/.config/orca/, ~/.orca).",
        "Options:",
        "  --plugins-only   Only remove plugins; keep binary and config.",
        "  --keep-config    Remove plugins and binary but keep ~/.config/orca/.",
        "  --yes            Skip confirmation prompt.",
        "Local workspace .orca/ directories are not removed automatically;",
        "run 'find . -type d -name .orca' to locate them manually.",
    } },
    .{ .name = "replay", .summary = "Replay an audit session", .usage = "orca replay [--list] [--session <id|last>] [--json] [--only denied] [--verify]", .category = .core_workflow, .examples = &.{
        "orca replay",
        "orca replay --list",
        "orca replay --session last",
        "orca replay --session 2026-05-29-abc123",
    }, .details = &.{
        "Reads .orca session artifacts, renders a timeline, and can verify session integrity.",
        "With no args and no sessions, lists available sessions instead of erroring.",
        "Use --list to print all session IDs under .orca/sessions/.",
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
        .usage = "orca apply [--session <id|last>] [--file <path>]",
        .category = .staged_changes,
        .details = &.{
            "Applies reviewed pending file changes after original-state checks where feasible.",
            "See 'orca diff' to review changes and 'orca discard' to cancel them.",
        },
    },
    .{
        .name = "discard",
        .summary = "Reject pending file changes",
        .usage = "orca discard [--session <id|last>] [--file <path>]",
        .category = .staged_changes,
        .details = &.{
            "Removes pending file changes without changing workspace files.",
            "See 'orca diff' to review changes and 'orca apply' to commit them.",
        },
    },
    .{ .name = "mcp", .summary = "Inspect and proxy MCP servers", .usage = "orca mcp <inspect|proxy|list|trust|manifest> [options]", .category = .advanced, .details = &.{
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
    .{ .name = "redteam", .summary = "Run built-in safety tests against current policy", .usage = "orca redteam [path] [--json] [--ci] [--fixture <id>]", .category = .advanced, .details = &.{
        "Discovers deterministic local fixtures, runs them against implemented Orca controls, and reports a scorecard.",
        "When no path is provided, fixtures are discovered under ./fixtures.",
        "--json emits a machine-readable report. --ci never prompts and exits non-zero if any required fixture fails or is unsupported.",
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
    .{ .name = "plugin", .summary = "Plugin management and diagnostics", .usage = "orca plugin <doctor|manifest|install|mcp-server> [options]", .category = .integrations, .details = &.{
        "Subcommands:",
        "  orca plugin doctor [codex|claude|opencode|openclaw|hermes] [--json]",
        "  orca plugin manifest [codex|claude|opencode|openclaw|hermes|all] [--json]",
        "  orca plugin install [codex|claude|opencode|openclaw|hermes|all] [--dry-run] [--path <path>] [--yes]",
        "  orca plugin mcp-server [--help]",
        "Primary onboarding path: run `orca setup` (guided interactive selection on TTY terminals).",
        "`plugin install --yes` is retained for scripting, CI, and non-interactive use cases.",
        "Plugin commands are safe by default: install defaults to --dry-run, doctor does not print secrets,",
        "and mcp-server is currently a documented stub that does not start a real server.",
    } },
    .{ .name = "decide", .summary = "Ask Orca whether an action is allowed by policy", .usage = "orca decide <command|file|prompt|tool> --json <payload>|--stdin [--ci]", .category = .advanced, .details = &.{
        "Evaluates a policy decision for host plugins (Codex, Claude Code, OpenCode, etc.).",
        "Subcommands:",
        "  orca decide command --json '{\"command\":\"<cmd>\"}'",
        "  orca decide file    --json '{\"path\":\"<p>\",\"operation\":\"read|write\"}'",
        "  orca decide prompt  --json '{\"text\":\"<text>\"}'",
        "  orca decide tool    --json '{\"name\":\"<name>\"}'",
        "  orca decide <kind> --stdin",
        "  orca decide <kind> --json <payload> [--ci]",
        "Output is JSON to stdout; debug logs go to stderr only.",
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
    .{ .name = "dashboard", .summary = "Start the local Orca dashboard", .usage = "orca dashboard [--host 127.0.0.1] [--port 7742]", .category = .diagnostics, .details = &.{
        "Starts a localhost-only web dashboard for health, policy, integrations, sessions, and denied-action replay.",
        "The dashboard calls existing Orca CLI/Core paths and does not replace policy evaluation.",
        "Mutation routes use a per-run browser token and only expose fixed Orca actions; arbitrary shell commands are not accepted.",
        "Defaults to http://127.0.0.1:7742.",
    } },
    .{ .name = "help", .summary = "Show help", .usage = "orca help [command]", .category = .getting_started, .details = &.{"Shows top-level help or command-specific help."} },
};

pub fn write(io: std.Io, writer: anytype) !void {
    try writer.writeAll("Orca — local runtime firewall for AI agents\n" ++
        "\n" ++
        "Usage:\n" ++
        "  orca <command> [options]\n" ++
        "\n");

    const categories = comptime std.enums.values(Category);
    for (categories) |cat| {
        var any = false;
        for (commands) |cmd| {
            if (cmd.hidden or cmd.category != cat) continue;
            if (!any) {
                try style.maybeColor(io, writer, style.Style.bold, categoryTitle(cat));
                try writer.writeAll(":\n");
                any = true;
            }
            try writer.print("  {s:<13} {s}\n", .{ cmd.name, cmd.summary });
        }
        if (any) try writer.writeAll("\n");
    }

    try writer.writeAll("Use 'orca help <command>' for command-specific help.\n");
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

pub fn writeCommand(io: std.Io, writer: anytype, name: []const u8) !bool {
    _ = io;
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
