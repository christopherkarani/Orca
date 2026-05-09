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
            "Options: --workspace <path>, --mode observe|ask|strict|ci, --policy <path>, --session-name <name>, --no-secrets, --inherit-env, --no-network, --allow-network <domain>, --network observe|ask|allowlist|open|off, --require-backend <capability>, --help",
            "Strict and CI modes default to no-secrets child environments. --inherit-env is allowed only when the selected policy permits inheritance.",
            "Network flags update the run-time policy and audit network decisions. Phase 12 provides decision logic plus child environment metadata hooks, not active proxy or transparent network enforcement.",
            "Linux uses backend capability detection and process-group cleanup where available. Optional kernel features are reported honestly and are not claimed active unless actually active.",
        },
    },
    .{
        .name = "init",
        .summary = "Create an Orca policy",
        .usage = "orca init [--preset <name>] [--mode strict|ask|observe|ci|trusted] [--ci] [--force]",
        .details = &.{
            "Creates .aegis/policy.yaml from a practical editable preset.",
            "Presets: generic-agent, claude-code, codex, cursor-agent, opencode, cline-roo, mcp-dev, github-actions, strict-local, trusted-local.",
            "Refuses to overwrite an existing policy unless --force is provided.",
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
    .{ .name = "policy", .summary = "Validate and explain policies", .usage = "orca policy <check|explain> [...]", .details = &.{
        "Subcommands:",
        "  orca policy check <policy-path>",
        "  orca policy explain <file.read|file.write|env|command|network|mcp> <target>",
        "Explanations show the decision, reason, matched rule when available, and policy mode.",
    } },
    .{ .name = "replay", .summary = "Replay an audit session", .usage = "orca replay [--session <id|last>] [--json] [--only denied] [--verify]", .details = &.{"Reads .aegis session artifacts, renders a timeline, and can verify the event hash chain."} },
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
        "Discovers deterministic local fixtures, runs them against implemented Aegis controls, and reports a scorecard.",
        "When no path is provided, fixtures are discovered under ./fixtures.",
        "--json emits a machine-readable report. --ci never prompts and exits non-zero if any required fixture fails or is unsupported.",
    } },
    .{ .name = "completions", .summary = "Generate shell completions", .usage = "orca completions <bash|zsh|fish|powershell>", .details = &.{
        "Prints a completion script to stdout for the requested shell.",
        "The generated completions include top-level commands and common flags.",
    } },
    .{ .name = "shim", .summary = "Internal PATH shim callback", .usage = "orca shim exec -- <command> [args...]", .details = &.{
        "Internal callback used by session-local PATH shims under .aegis/sessions/<id>/shims/.",
        "The shim removes the session shim directory from PATH before resolving the real binary to avoid recursive invocation.",
        "This is wrapper-level coverage only and does not claim transparent OS-level interception.",
    } },
    .{ .name = "version", .summary = "Print version", .usage = "orca version [--json] [--help]", .details = &.{
        "Prints the current Orca version.",
        "--json emits version, commit, target, and build_date fields for release automation.",
    } },
    .{ .name = "plugin", .summary = "Plugin management and diagnostics", .usage = "orca plugin <doctor|manifest|install|mcp-server> [options]", .details = &.{
        "Subcommands:",
        "  orca plugin doctor [codex|claude] [--json]",
        "  orca plugin manifest [codex|claude|all] [--json]",
        "  orca plugin install [codex|claude|all] [--dry-run] [--path <path>] [--yes]",
        "  orca plugin mcp-server [--help]",
        "Plugin commands are safe by default: install defaults to --dry-run, doctor does not print secrets,",
        "and mcp-server is currently a documented stub that does not start a real server.",
    } },
    .{ .name = "decide", .summary = "Evaluate a policy decision for host plugins", .usage = "orca decide <command|file|prompt|tool> --json <payload>|--stdin [--ci]", .details = &.{
        "Evaluates a policy decision for host plugins (Codex, Claude Code, etc.).",
        "Subcommands:",
        "  orca decide command --json '{\"command\":\"<cmd>\"}'",
        "  orca decide file    --json '{\"path\":\"<p>\",\"operation\":\"read|write\"}'",
        "  orca decide prompt  --json '{\"text\":\"<text>\"}'",
        "  orca decide tool    --json '{\"name\":\"<name>\"}'",
        "  orca decide <kind> --stdin",
        "  orca decide <kind> --json <payload> [--ci]",
        "Output is JSON to stdout; debug logs go to stderr only.",
    } },
    .{ .name = "hook", .summary = "Host-specific hook adapter for Codex and Claude Code", .usage = "orca hook <codex|claude> <event> [--ci]", .details = &.{
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
        "Hook responses include host_limitations to honestly report enforcement limits.",
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
