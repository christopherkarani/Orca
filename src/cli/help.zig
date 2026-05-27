const std = @import("std");

pub const CommandInfo = struct {
    name: []const u8,
    summary: []const u8,
    usage: []const u8,
    details: []const []const u8,
};

pub const commands = [_]CommandInfo{
    .{
        .name = "run",
        .summary = "Run a command under Orca",
        .usage = "orca run [options] -- <command> [args...]",
        .details = &.{
            "Starts a direct-child supervision session, filters the child environment through policy, checks the direct command through Command Guard, writes audit artifacts, and mirrors the child exit code.",
            "Options: --workspace <path>, --mode observe|ask|strict|ci, --policy <path>, --session-name <name>, --no-secrets, --secretless, --inherit-env, --no-network, --allow-network <domain>, --network observe|ask|allowlist|open|off, --network-backend decision-only|proxy, --require-backend <capability>, --help",
            "Strict and CI modes default to no-secrets child environments. --secretless replaces policy-visible secret env values with broker references instead of raw values. --inherit-env is allowed only when the selected policy permits inheritance.",
            "Network flags update the run-time policy and audit network decisions. --network-backend proxy starts an explicit localhost proxy and injects HTTP_PROXY/HTTPS_PROXY/ALL_PROXY; HTTPS CONNECT enforcement is host/port only without MITM.",
            "Linux uses backend capability detection and process-group cleanup where available. Optional kernel features are reported honestly and are not claimed active unless actually active.",
        },
    },
    .{
        .name = "init",
        .summary = "Create an Orca policy",
        .usage = "orca init [--preset <name>] [--mode strict|ask|observe|ci|trusted] [--ci] [--force]",
        .details = &.{
            "Creates .orca/policy.yaml from a practical editable preset.",
            "Presets: generic-agent, claude-code, codex, cursor-agent, opencode, cline-roo, mcp-dev, github-actions, solo-dev, strict-local, team-ci, openclaw-hermes, trusted-local.",
            "Refuses to overwrite an existing policy unless --force is provided.",
        },
    },
    .{
        .name = "setup",
        .summary = "Unified bootstrap: detect hosts, init policy, install plugins",
        .usage = "orca setup [--auto] [--preset <name>]",
        .details = &.{
            "Detects installed agent hosts, initializes a policy if missing, installs missing plugins, and runs smoke tests.",
            "Use --auto for non-interactive mode. Use --preset to choose a policy preset (default: generic-agent).",
        },
    },
    .{
        .name = "doctor",
        .summary = "Show platform capabilities",
        .usage = "orca doctor [--help]",
        .details = &.{
            "Reports platform and planned capability status honestly.",
        },
    },
    .{ .name = "policy", .summary = "Validate, explain, and apply policies", .usage = "orca policy <check|explain|packs|apply-pack> [...]", .details = &.{
        "Subcommands:",
        "  orca policy check <policy-path>",
        "  orca policy explain [--policy <path>] <file.read|file.write|env|command|network|mcp> <target> [--method <HTTP_METHOD>]",
        "  orca policy packs",
        "  orca policy apply-pack <solo-dev|strict-local|team-ci|openclaw-hermes> [--force]",
        "Explanations show the decision, reason, matched rule when available, and policy mode.",
    } },
    .{ .name = "credentials", .summary = "Check Secretless credential brokers", .usage = "orca credentials check [credential-ref]", .details = &.{
        "Checks configured Secretless brokers and optional credential refs without printing raw secret values.",
        "Supported broker kinds: local-dummy, env-file-dev, 1password-cli, macos-keychain, infisical-agent-vault.",
        "Infisical/Agent Vault is currently a status/config boundary until exact local API or CLI behavior is verified.",
    } },
    .{ .name = "report", .summary = "Export a local safety report", .usage = "orca report --session <id|last> --format markdown|json", .details = &.{
        "Loads a local session, verifies the hash chain, and exports denied actions, redactions, plugin readiness, and a plain-language prevention summary.",
        "Report export is a Pro/Team local-license feature. Core safety commands remain available without a license.",
    } },
    .{ .name = "license", .summary = "Manage local offline licenses", .usage = "orca license <status|activate> [...]", .details = &.{
        "Subcommands:",
        "  orca license status [--json]",
        "  orca license activate <key-or-file>",
        "Development keys: dev-free, dev-pro, dev-team.",
        "Licenses are verified offline and stored under the user config directory.",
    } },
    .{ .name = "ci", .summary = "Run local CI readiness checks", .usage = "orca ci check [--format markdown|json] [--github-summary <path>]", .details = &.{
        "Validates .orca/policy.yaml, rejects dangerous obvious defaults, runs a focused CI-safe redteam fixture, and emits GitHub Actions-friendly output.",
    } },
    .{ .name = "demo", .summary = "Create safe local demo evidence", .usage = "orca demo blocked-action", .details = &.{
        "Creates a harmless local session showing a destructive command denied by Orca.",
        "The demo writes replay/report artifacts but does not execute the destructive command.",
    } },
    .{ .name = "disable", .summary = "Disable Orca plugins from host agents", .usage = "orca disable [codex|claude|opencode|openclaw|hermes|all] [--yes]", .details = &.{
        "Removes Orca plugin registrations from host agents without removing the Orca binary or policy files.",
        "Hosts: codex, claude, opencode, openclaw, hermes. Defaults to all if no host is specified.",
        "OpenCode: removes .opencode/plugins/orca.ts and ~/.config/opencode/plugins/orca.ts",
        "OpenClaw: runs 'openclaw plugins uninstall orca-openclaw-plugin'",
        "Hermes: runs 'hermes plugins disable orca' and removes ~/.hermes/plugins/orca/",
        "Codex / Claude: removes known plugin paths (host-managed install locations).",
        "Re-enable later with: orca plugin install <host> --yes",
    } },
    .{ .name = "uninstall", .summary = "Uninstall Orca from this machine", .usage = "orca uninstall [--plugins-only] [--keep-config] [--yes]", .details = &.{
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
    .{ .name = "replay", .summary = "Replay an audit session", .usage = "orca replay [--session <id|last>] [--json] [--only denied] [--verify]", .details = &.{"Reads .orca session artifacts, renders a timeline, and can verify the event hash chain."} },
    .{ .name = "diff", .summary = "Show staged writes", .usage = "orca diff [--session <id|last>] [--file <path>]", .details = &.{"Shows unified diffs for Orca-mediated staged writes. This does not claim transparent interception of arbitrary child-process file IO."} },
    .{ .name = "apply", .summary = "Apply staged writes", .usage = "orca apply [--session <id|last>] [--file <path>]", .details = &.{"Applies reviewed staged writes after original-state checks where feasible."} },
    .{ .name = "discard", .summary = "Discard staged writes", .usage = "orca discard [--session <id|last>] [--file <path>]", .details = &.{"Removes staged writes without changing workspace files."} },
    .{ .name = "mcp", .summary = "MCP proxy and inspection commands", .usage = "orca mcp <inspect|proxy|list|trust|manifest> [options]", .details = &.{
        "Subcommands:",
        "  orca mcp inspect --command <server> [--name <server-name>] [--policy <path>]",
        "  orca mcp proxy --command <server> [--name <server-name>] [--policy <path>] [--manifest <path>] [--mode observe|ask|strict|ci]",
        "  orca mcp list",
        "  orca mcp trust <server> --tool <tool>",
        "  orca mcp manifest check <manifest.yaml>",
        "  orca mcp manifest generate --command <server-command> | --server <name>",
        "The proxy speaks newline-delimited stdio JSON-RPC and writes only MCP protocol messages to stdout while proxying.",
        "Remote HTTP MCP, OAuth, and hosted gateway behavior are limited/deferred in Phase 17.",
    } },
    .{ .name = "redteam", .summary = "Run red-team fixtures", .usage = "orca redteam [path] [--json] [--ci] [--fixture <id>]", .details = &.{
        "Discovers deterministic local fixtures, runs them against implemented Orca controls, and reports a scorecard.",
        "When no path is provided, fixtures are discovered under ./fixtures.",
        "--json emits a machine-readable report. --ci never prompts and exits non-zero if any required fixture fails or is unsupported.",
    } },
    .{ .name = "completions", .summary = "Generate shell completions", .usage = "orca completions <bash|zsh|fish|powershell>", .details = &.{
        "Prints a completion script to stdout for the requested shell.",
        "The generated completions include top-level commands and common flags.",
    } },
    .{ .name = "shim", .summary = "Internal PATH shim callback", .usage = "orca shim exec -- <command> [args...]", .details = &.{
        "Internal callback used by session-local PATH shims under .orca/sessions/<id>/shims/.",
        "The shim removes the session shim directory from PATH before resolving the real binary to avoid recursive invocation.",
        "This is wrapper-level coverage only and does not claim transparent OS-level interception.",
    } },
    .{ .name = "version", .summary = "Print version", .usage = "orca version [--json] [--help]", .details = &.{
        "Prints the current Orca version.",
        "--json emits version, commit, target, and build_date fields for release automation.",
    } },
    .{ .name = "plugin", .summary = "Plugin management and diagnostics", .usage = "orca plugin <doctor|manifest|install|mcp-server> [options]", .details = &.{
        "Subcommands:",
        "  orca plugin doctor [codex|claude|opencode|openclaw|hermes] [--json]",
        "  orca plugin manifest [codex|claude|opencode|openclaw|hermes|all] [--json]",
        "  orca plugin install [codex|claude|opencode|openclaw|hermes|all] [--dry-run] [--path <path>] [--yes]",
        "  orca plugin mcp-server [--help]",
        "Plugin commands are safe by default: install defaults to --dry-run, doctor does not print secrets,",
        "and mcp-server is currently a documented stub that does not start a real server.",
    } },
    .{ .name = "decide", .summary = "Evaluate a policy decision for host plugins", .usage = "orca decide <command|file|prompt|tool> --json <payload>|--stdin [--ci]", .details = &.{
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
    .{ .name = "hook", .summary = "Host-specific hook adapter for Codex, Claude Code, OpenCode, OpenClaw, and Hermes", .usage = "orca hook <codex|claude|opencode|openclaw|hermes> <event> [--ci]", .details = &.{
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
    .{ .name = "dashboard", .summary = "Start the local Orca dashboard", .usage = "orca dashboard [--host 127.0.0.1] [--port 7742]", .details = &.{
        "Starts a localhost-only web dashboard for health, policy, integrations, sessions, and denied-action replay.",
        "The dashboard calls existing Orca CLI/Core paths and does not replace policy evaluation.",
        "Mutation routes use a per-run browser token and only expose fixed Orca actions; arbitrary shell commands are not accepted.",
        "Defaults to http://127.0.0.1:7742.",
    } },
    .{ .name = "help", .summary = "Show help", .usage = "orca help [command]", .details = &.{"Shows top-level help or command-specific help."} },
};

pub fn write(writer: anytype) !void {
    try writer.writeAll(
        \\Orca — local runtime firewall for AI agents
        \\
        \\Usage:
        \\  orca <command> [options]
        \\
        \\Commands:
        \\
    );
    for (commands) |command| {
        try writer.print("  {s:<9} {s}\n", .{ command.name, command.summary });
    }
    try writer.writeAll(
        \\
        \\Use 'orca help <command>' for command-specific help.
        \\
    );
}

pub fn writeCommand(writer: anytype, name: []const u8) !bool {
    const command = findCommand(name) orelse return false;
    try writer.print("{s}\n\nUsage:\n  {s}\n\n", .{ command.summary, command.usage });
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
