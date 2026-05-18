const std = @import("std");

const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");

const commands = [_][]const u8{
    "run",
    "init",
    "doctor",
    "policy",
    "credentials",
    "replay",
    "diff",
    "apply",
    "discard",
    "mcp",
    "redteam",
    "completions",
    "plugin",
    "decide",
    "hook",
    "dashboard",
    "report",
    "license",
    "ci",
    "demo",
    "version",
    "help",
};

const common_flags = [_][]const u8{
    "--help",
    "--workspace",
    "--mode",
    "--policy",
    "--preset",
    "--force",
    "--ci",
    "--json",
    "--format",
    "--session",
    "--secretless",
    "--network-backend",
    "--github-summary",
};

pub fn command(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 1 and (std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h"))) {
        _ = try help.writeCommand(stdout, "completions");
        return exit_codes.success;
    }
    if (argv.len != 1) {
        try stderr.writeAll("orca completions: expected one shell: bash, zsh, fish, or powershell.\n");
        return exit_codes.usage;
    }

    const shell = argv[0];
    if (std.mem.eql(u8, shell, "bash")) {
        try writeBash(stdout);
    } else if (std.mem.eql(u8, shell, "zsh")) {
        try writeZsh(stdout);
    } else if (std.mem.eql(u8, shell, "fish")) {
        try writeFish(stdout);
    } else if (std.mem.eql(u8, shell, "powershell")) {
        try writePowerShell(stdout);
    } else {
        try stderr.print("orca completions: unsupported shell '{s}'. Expected bash, zsh, fish, or powershell.\n", .{shell});
        return exit_codes.usage;
    }
    return exit_codes.success;
}

fn writeWords(writer: anytype, words: []const []const u8) !void {
    for (words, 0..) |word, index| {
        if (index > 0) try writer.writeByte(' ');
        try writer.writeAll(word);
    }
}

fn writeBash(writer: anytype) !void {
    try writer.writeAll(
        \\_orca_completions() {
        \\  local cur prev commands flags
        \\  COMPREPLY=()
        \\  cur="${COMP_WORDS[COMP_CWORD]}"
        \\  prev="${COMP_WORDS[COMP_CWORD-1]}"
        \\  commands="
    );
    try writeWords(writer, &commands);
    try writer.writeAll(
        \\"
        \\  flags="
    );
    try writeWords(writer, &common_flags);
    try writer.writeAll(
        \\"
        \\  if [[ ${COMP_CWORD} -eq 1 ]]; then
        \\    COMPREPLY=( $(compgen -W "${commands}" -- "${cur}") )
        \\  else
        \\    COMPREPLY=( $(compgen -W "${flags}" -- "${cur}") )
        \\  fi
        \\}
        \\complete -F _orca_completions orca
        \\
    );
}

fn writeZsh(writer: anytype) !void {
    try writer.writeAll(
        \\#compdef orca
        \\_orca() {
        \\  local -a commands flags
        \\  commands=(
    );
    for (commands) |cmd| try writer.print("    '{s}'\n", .{cmd});
    try writer.writeAll(
        \\  )
        \\  flags=(
    );
    for (common_flags) |flag| try writer.print("    '{s}'\n", .{flag});
    try writer.writeAll(
        \\  )
        \\  if (( CURRENT == 2 )); then
        \\    _describe 'command' commands
        \\  else
        \\    _describe 'flag' flags
        \\  fi
        \\}
        \\_orca "$@"
        \\
    );
}

fn writeFish(writer: anytype) !void {
    for (commands) |cmd| {
        try writer.print("complete -c orca -f -n '__fish_use_subcommand' -a '{s}'\n", .{cmd});
    }
    for (common_flags) |flag| {
        try writer.print("complete -c orca -f -l {s}\n", .{flag[2..]});
    }
}

fn writePowerShell(writer: anytype) !void {
    try writer.writeAll(
        \\Register-ArgumentCompleter -Native -CommandName orca -ScriptBlock {
        \\  param($wordToComplete, $commandAst, $cursorPosition)
        \\  $commands = @(
    );
    for (commands) |cmd| try writer.print("    '{s}'\n", .{cmd});
    try writer.writeAll(
        \\  )
        \\  $flags = @(
    );
    for (common_flags) |flag| try writer.print("    '{s}'\n", .{flag});
    try writer.writeAll(
        \\  )
        \\  ($commands + $flags) | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        \\    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        \\  }
        \\}
        \\
    );
}

test "completions output is non-empty for supported shells" {
    const shells = [_][]const u8{ "bash", "zsh", "fish", "powershell" };
    for (shells) |shell| {
        var stdout_buf: [8192]u8 = undefined;
        var stderr_buf: [512]u8 = undefined;
        var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
        var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

        const code = try command(&.{shell}, stdout_stream.writer(), stderr_stream.writer());
        try std.testing.expectEqual(exit_codes.success, code);
        try std.testing.expect(stdout_stream.getWritten().len > 0);
        try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "run") != null);
        try std.testing.expectEqualStrings("", stderr_stream.getWritten());
    }
}

test "GitHub Actions documentation includes Orca run and redteam commands" {
    const doc = try std.fs.cwd().readFileAlloc(std.testing.allocator, "docs/ci/github-actions.md", 32 * 1024);
    defer std.testing.allocator.free(doc);
    try std.testing.expect(std.mem.indexOf(u8, doc, "orca run --mode ci -- ./scripts/agent-task.sh") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "orca redteam --ci") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "actions/upload-artifact@v4") != null);
}
