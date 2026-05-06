pub fn write(writer: anytype) !void {
    try writer.writeAll(
        \\Aegis — local runtime firewall for AI agents
        \\
        \\Usage:
        \\  aegis <command> [options]
        \\
        \\Commands:
        \\  run       Run a command under Aegis
        \\  init      Create an Aegis policy
        \\  doctor    Show platform capabilities
        \\  policy    Validate and explain policies
        \\  replay    Replay an audit session
        \\  diff      Show staged writes
        \\  apply     Apply staged writes
        \\  discard   Discard staged writes
        \\  mcp       MCP proxy and inspection commands
        \\  redteam   Run red-team fixtures
        \\  version   Print version
        \\  help      Show help
        \\
    );
}
