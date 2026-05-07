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
        .summary = "Run a command under Aegis",
        .usage = "aegis run [options] -- <command> [args...]",
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
        .summary = "Create an Aegis policy",
        .usage = "aegis init [--mode strict|ask|observe] [--ci] [--force]",
        .details = &.{
            "Creates .aegis/policy.yaml from a minimal local template.",
            "Refuses to overwrite an existing policy unless --force is provided.",
        },
    },
    .{
        .name = "doctor",
        .summary = "Show platform capabilities",
        .usage = "aegis doctor [--help]",
        .details = &.{
            "Reports platform and planned capability status honestly.",
        },
    },
    .{ .name = "policy", .summary = "Validate and explain policies", .usage = "aegis policy <check|explain> [...]", .details = &.{
        "Subcommands:",
        "  aegis policy check <policy-path>",
        "  aegis policy explain <file.read|file.write|env|command|network|mcp> <target>",
        "Explanations show the decision, reason, matched rule when available, and policy mode.",
    } },
    .{ .name = "replay", .summary = "Replay an audit session", .usage = "aegis replay [--session <id|last>] [--json] [--only denied] [--verify]", .details = &.{"Reads .aegis session artifacts, renders a timeline, and can verify the event hash chain."} },
    .{ .name = "diff", .summary = "Show staged writes", .usage = "aegis diff [--session <id|last>] [--file <path>]", .details = &.{"Shows unified diffs for Aegis-mediated staged writes. This does not claim transparent interception of arbitrary child-process file IO."} },
    .{ .name = "apply", .summary = "Apply staged writes", .usage = "aegis apply [--session <id|last>] [--file <path>]", .details = &.{"Applies reviewed staged writes after original-state checks where feasible."} },
    .{ .name = "discard", .summary = "Discard staged writes", .usage = "aegis discard [--session <id|last>] [--file <path>]", .details = &.{"Removes staged writes without changing workspace files."} },
    .{ .name = "mcp", .summary = "MCP proxy and inspection commands", .usage = "aegis mcp <inspect|proxy> --command <server> [options]", .details = &.{
        "Subcommands:",
        "  aegis mcp inspect --command <server> [--name <server-name>] [--policy <path>]",
        "  aegis mcp proxy --command <server> [--name <server-name>] [--policy <path>] [--mode observe|ask|strict|ci]",
        "The proxy speaks newline-delimited stdio JSON-RPC and writes only MCP protocol messages to stdout while proxying.",
        "Remote HTTP MCP, OAuth, and hosted gateway behavior are not implemented in Phase 11.",
    } },
    .{ .name = "redteam", .summary = "Run red-team fixtures", .usage = "aegis redteam [path] [--json] [--ci] [--fixture <id>]", .details = &.{
        "Discovers deterministic local fixtures, runs them against implemented Aegis controls, and reports a scorecard.",
        "When no path is provided, fixtures are discovered under ./fixtures.",
        "--json emits a machine-readable report. --ci never prompts and exits non-zero if any required fixture fails or is unsupported.",
    } },
    .{ .name = "shim", .summary = "Internal PATH shim callback", .usage = "aegis shim exec -- <command> [args...]", .details = &.{
        "Internal callback used by session-local PATH shims under .aegis/sessions/<id>/shims/.",
        "The shim removes the session shim directory from PATH before resolving the real binary to avoid recursive invocation.",
        "This is wrapper-level coverage only and does not claim transparent OS-level interception.",
    } },
    .{ .name = "version", .summary = "Print version", .usage = "aegis version [--help]", .details = &.{"Prints the current Aegis version."} },
    .{ .name = "help", .summary = "Show help", .usage = "aegis help [command]", .details = &.{"Shows top-level help or command-specific help."} },
};

pub fn write(writer: anytype) !void {
    try writer.writeAll(
        \\Aegis — local runtime firewall for AI agents
        \\
        \\Usage:
        \\  aegis <command> [options]
        \\
        \\Commands:
    );
    for (commands) |command| {
        try writer.print("  {s:<9} {s}\n", .{ command.name, command.summary });
    }
    try writer.writeAll(
        \\
        \\Use 'aegis help <command>' for command-specific help.
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
