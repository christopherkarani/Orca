const std = @import("std");

const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");

const global_flags = [_][]const u8{ "--help", "--no-rich" };

const CommandOptions = struct {
    name: []const u8,
    flags: []const []const u8,
};

const command_options = [_]CommandOptions{
    .{ .name = "run", .flags = &.{ "--workspace", "--mode", "--policy", "--session-name", "--no-secrets", "--secretless", "--inherit-env", "--no-network", "--allow-network", "--network", "--network-backend", "--require-backend" } },
    .{ .name = "init", .flags = &.{ "--preset", "--mode", "--ci", "--force" } },
    .{ .name = "start", .flags = &.{ "--auto", "--protection", "--hosts", "--preset", "--skip-verify" } },
    .{ .name = "quickstart", .flags = &.{ "--auto", "--preset" } },
    .{ .name = "setup", .flags = &.{ "--auto", "--yes", "--preset" } },
    .{ .name = "status", .flags = &.{"--json"} },
    .{ .name = "doctor", .flags = &.{"--verbose"} },
    .{ .name = "scan", .flags = &.{ "--staged", "--paths" } },
    .{ .name = "history", .flags = &.{ "--live", "--json" } },
    .{ .name = "simulate", .flags = &.{"--file"} },
    .{ .name = "rebase-recover", .flags = &.{"--ttl"} },
    .{ .name = "packs", .flags = &.{ "--filter", "--enabled", "--installed", "--page", "--page-size" } },
    .{ .name = "report", .flags = &.{ "--session", "--format" } },
    .{ .name = "ci", .flags = &.{ "--format", "--github-summary" } },
    .{ .name = "shutdown", .flags = &.{"--daemon"} },
    .{ .name = "stop", .flags = &.{"--yes"} },
    .{ .name = "uninstall", .flags = &.{ "--plugins-only", "--keep-config", "--yes" } },
    .{ .name = "replay", .flags = &.{ "--list", "--session", "--json", "--only", "--verify", "--tui" } },
    .{ .name = "diff", .flags = &.{ "--session", "--file" } },
    .{ .name = "apply", .flags = &.{ "--session", "--file" } },
    .{ .name = "discard", .flags = &.{ "--session", "--file" } },
    .{ .name = "redteam", .flags = &.{ "--json", "--ci", "--fixture" } },
    .{ .name = "version", .flags = &.{"--json"} },
    .{ .name = "plugin", .flags = &.{ "--dry-run", "--yes", "--json", "--path" } },
    .{ .name = "decide", .flags = &.{ "--json", "--stdin", "--ci", "--human" } },
    .{ .name = "evaluate", .flags = &.{ "--json", "--stdin" } },
    .{ .name = "hook", .flags = &.{"--ci"} },
    .{ .name = "dashboard", .flags = &.{ "--machine", "--workspace", "--host", "--port", "--once" } },
};

pub fn command(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 1 and (std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h"))) {
        _ = try help.writeCommand(io, stdout, "completions");
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

fn writePublicCommands(writer: anytype) !void {
    var first = true;
    for (help.commands) |cmd| {
        if (cmd.hidden) continue;
        if (!first) try writer.writeByte(' ');
        try writer.writeAll(cmd.name);
        first = false;
    }
}

fn writeBashCases(writer: anytype) !void {
    for (command_options) |options| {
        try writer.print("    {s}) flags=\"${{flags}} ", .{options.name});
        try writeWords(writer, options.flags);
        try writer.writeAll("\" ;;\n");
    }
}

fn writeZshCases(writer: anytype) !void {
    for (command_options) |options| {
        try writer.print("    {s}) flags+=(", .{options.name});
        for (options.flags) |flag| try writer.print(" '{s}'", .{flag});
        try writer.writeAll(" ) ;;\n");
    }
}

fn writeBash(writer: anytype) !void {
    try writer.writeAll(
        \\_orca_completions() {
        \\  local cur commands command flags
        \\  COMPREPLY=()
        \\  cur="${COMP_WORDS[COMP_CWORD]}"
        \\  command="${COMP_WORDS[1]}"
        \\  commands="
    );
    try writePublicCommands(writer);
    try writer.writeAll(
        \\"
        \\  flags="
    );
    try writeWords(writer, &global_flags);
    try writer.writeAll(
        \\"
        \\  case "${command}" in
    );
    try writeBashCases(writer);
    try writer.writeAll(
        \\  esac
        \\  if [[ ${COMP_CWORD} -eq 1 ]]; then
        \\    COMPREPLY=( $(compgen -W "${commands} ${flags}" -- "${cur}") )
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
    for (help.commands) |cmd| {
        if (!cmd.hidden) try writer.print("    '{s}'\n", .{cmd.name});
    }
    try writer.writeAll(
        \\  )
        \\  flags=(
    );
    for (global_flags) |flag| try writer.print("    '{s}'\n", .{flag});
    try writer.writeAll(
        \\  )
        \\  case "${words[2]}" in
    );
    try writeZshCases(writer);
    try writer.writeAll(
        \\  esac
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
    for (help.commands) |cmd| {
        if (!cmd.hidden) try writer.print("complete -c orca -f -n '__fish_use_subcommand' -a '{s}'\n", .{cmd.name});
    }
    for (global_flags) |flag| {
        try writer.print("complete -c orca -f -l {s}\n", .{flag[2..]});
    }
    for (command_options) |options| {
        for (options.flags) |flag| {
            try writer.print("complete -c orca -f -n '__fish_seen_subcommand_from {s}' -l {s}\n", .{ options.name, flag[2..] });
        }
    }
}

fn writePowerShell(writer: anytype) !void {
    try writer.writeAll(
        \\Register-ArgumentCompleter -Native -CommandName orca -ScriptBlock {
        \\  param($wordToComplete, $commandAst, $cursorPosition)
        \\  $commands = @(
    );
    for (help.commands) |cmd| {
        if (!cmd.hidden) try writer.print("    '{s}'\n", .{cmd.name});
    }
    try writer.writeAll(
        \\  )
        \\  $globalFlags = @(
    );
    for (global_flags) |flag| try writer.print("    '{s}'\n", .{flag});
    try writer.writeAll(
        \\  )
        \\  $elements = @($commandAst.CommandElements)
        \\  $flags = @($globalFlags)
        \\  if ($elements.Count -gt 1) {
        \\    switch ($elements[1].Extent.Text) {
    );
    for (command_options) |options| {
        try writer.print("      '{s}' {{ $flags += @(", .{options.name});
        for (options.flags, 0..) |flag, index| {
            if (index > 0) try writer.writeAll(", ");
            try writer.print("'{s}'", .{flag});
        }
        try writer.writeAll(") }\n");
    }
    try writer.writeAll(
        \\    }
        \\  }
        \\  $candidates = if ($elements.Count -le 2) { $commands + $globalFlags } else { $flags }
        \\  $candidates | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        \\    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        \\  }
        \\}
        \\
    );
}

test "completions output is non-empty for supported shells" {
    const shells = [_][]const u8{ "bash", "zsh", "fish", "powershell" };
    for (shells) |shell| {
        var stdout_buf: [32 * 1024]u8 = undefined;
        var stderr_buf: [512]u8 = undefined;
        var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
        var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

        const code = try command(std.testing.io, &.{shell}, &stdout_writer, &stderr_writer);
        try std.testing.expectEqual(exit_codes.success, code);
        try std.testing.expect(stdout_writer.buffered().len > 0);
        try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "run") != null);
        try std.testing.expectEqualStrings("", stderr_writer.buffered());
    }
}

test "completions hide internal commands and expose global no-rich flag" {
    const shells = [_][]const u8{ "bash", "zsh", "fish", "powershell" };
    for (shells) |shell| {
        var stdout_buf: [32 * 1024]u8 = undefined;
        var stderr_buf: [512]u8 = undefined;
        var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
        var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

        const code = try command(std.testing.io, &.{shell}, &stdout_writer, &stderr_writer);
        const output = stdout_writer.buffered();

        try std.testing.expectEqual(exit_codes.success, code);
        try std.testing.expect(std.mem.indexOf(u8, output, "shim") == null);
        const no_rich = if (std.mem.eql(u8, shell, "fish")) "-l no-rich" else "--no-rich";
        try std.testing.expect(std.mem.indexOf(u8, output, no_rich) != null);
        try std.testing.expectEqualStrings("", stderr_writer.buffered());
    }
}

test "completions include command-specific dashboard and packs flags" {
    const shells = [_][]const u8{ "bash", "zsh", "fish", "powershell" };
    const required_flags = [_][]const u8{
        "--machine",   "--workspace", "--host",   "--port", "--once",
        "--installed", "--enabled",   "--filter", "--page", "--page-size",
    };
    for (shells) |shell| {
        var stdout_buf: [32 * 1024]u8 = undefined;
        var stderr_buf: [512]u8 = undefined;
        var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
        var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

        const code = try command(std.testing.io, &.{shell}, &stdout_writer, &stderr_writer);
        const output = stdout_writer.buffered();

        try std.testing.expectEqual(exit_codes.success, code);
        for (required_flags) |flag| {
            if (std.mem.eql(u8, shell, "fish")) {
                var needle_buf: [64]u8 = undefined;
                const needle = try std.fmt.bufPrint(&needle_buf, "-l {s}", .{flag[2..]});
                try std.testing.expect(std.mem.indexOf(u8, output, needle) != null);
            } else {
                try std.testing.expect(std.mem.indexOf(u8, output, flag) != null);
            }
        }
        try std.testing.expectEqualStrings("", stderr_writer.buffered());
    }
}

test "completions scope flags to their owning command" {
    const cases = [_]struct {
        shell: []const u8,
        dashboard_scope: []const u8,
        packs_scope: []const u8,
    }{
        .{ .shell = "bash", .dashboard_scope = "dashboard) flags=", .packs_scope = "packs) flags=" },
        .{ .shell = "zsh", .dashboard_scope = "dashboard) flags+=(", .packs_scope = "packs) flags+=(" },
        .{ .shell = "fish", .dashboard_scope = "__fish_seen_subcommand_from dashboard", .packs_scope = "__fish_seen_subcommand_from packs" },
        .{ .shell = "powershell", .dashboard_scope = "'dashboard' { $flags +=", .packs_scope = "'packs' { $flags +=" },
    };
    for (cases) |case| {
        var stdout_buf: [32 * 1024]u8 = undefined;
        var stderr_buf: [512]u8 = undefined;
        var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
        var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

        const code = try command(std.testing.io, &.{case.shell}, &stdout_writer, &stderr_writer);
        const output = stdout_writer.buffered();

        try std.testing.expectEqual(exit_codes.success, code);
        try std.testing.expect(std.mem.indexOf(u8, output, case.dashboard_scope) != null);
        try std.testing.expect(std.mem.indexOf(u8, output, case.packs_scope) != null);
        try std.testing.expectEqualStrings("", stderr_writer.buffered());
    }
}

// ---------------------------------------------------------------------------
// Phase 1 TDD: completions must stay in sync with help.commands (written FIRST)
// ---------------------------------------------------------------------------

test "completions include every public help command" {
    const shells = [_][]const u8{ "bash", "zsh", "fish", "powershell" };
    for (shells) |shell| {
        var stdout_buf: [32 * 1024]u8 = undefined;
        var stderr_buf: [512]u8 = undefined;
        var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
        var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

        const code = try command(std.testing.io, &.{shell}, &stdout_writer, &stderr_writer);
        try std.testing.expectEqual(exit_codes.success, code);

        for (help.commands) |cmd| {
            if (cmd.hidden) continue;
            try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), cmd.name) != null);
        }
    }
}

test "GitHub Actions documentation includes Orca run and redteam commands" {
    const doc = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "docs/ci/github-actions.md", std.testing.allocator, .limited(32 * 1024));
    defer std.testing.allocator.free(doc);
    try std.testing.expect(std.mem.indexOf(u8, doc, "orca run --mode ci -- ./scripts/agent-task.sh") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "orca redteam --ci") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "actions/upload-artifact@v4") != null);
}
