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
            "Starts a direct-child supervision session, writes audit artifacts, validates the selected policy, and mirrors the child exit code.",
            "Options: --workspace <path>, --mode observe|ask|strict|ci, --policy <path>, --session-name <name>, --help",
            "Policy is evaluated and audited in Phase 07, but this command does not claim policy enforcement yet.",
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
    .{ .name = "diff", .summary = "Show staged writes", .usage = "aegis diff [--help]", .details = &.{"Placeholder in Phase 04; staged writes start in Phase 09."} },
    .{ .name = "apply", .summary = "Apply staged writes", .usage = "aegis apply [--help]", .details = &.{"Placeholder in Phase 04; staged writes start in Phase 09."} },
    .{ .name = "discard", .summary = "Discard staged writes", .usage = "aegis discard [--help]", .details = &.{"Placeholder in Phase 04; staged writes start in Phase 09."} },
    .{ .name = "mcp", .summary = "MCP proxy and inspection commands", .usage = "aegis mcp [--help]", .details = &.{"Placeholder in Phase 04; MCP proxying starts in Phase 11."} },
    .{ .name = "redteam", .summary = "Run red-team fixtures", .usage = "aegis redteam [--help]", .details = &.{"Placeholder in Phase 04; red-team execution starts in Phase 13."} },
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
