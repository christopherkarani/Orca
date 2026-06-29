const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

pub const args = @import("args.zig");
pub const exit_codes = @import("exit_codes.zig");
pub const help = @import("help.zig");
pub const run_command = @import("run.zig");
pub const init = @import("init.zig");
pub const doctor = @import("doctor.zig");
pub const policy = @import("policy.zig");
pub const credentials_command = @import("credentials.zig");
pub const replay = @import("replay.zig");
pub const diff = @import("diff.zig");
pub const apply = @import("apply.zig");
pub const discard = @import("discard.zig");
pub const mcp = @import("mcp.zig");
pub const redteam = @import("redteam.zig");
pub const completions = @import("completions.zig");
pub const shim = @import("shim.zig");
pub const version_command = @import("version.zig");
pub const plugin = @import("plugin.zig");
pub const plugin_install = @import("plugin_install.zig");
pub const setup = @import("setup.zig");
pub const start = @import("start.zig");
pub const onboarding = @import("onboarding.zig");
pub const quickstart = @import("quickstart.zig");
pub const decide = @import("decide.zig");
pub const evaluate = @import("evaluate.zig");
pub const hook = @import("hook.zig");
pub const dashboard_command = @import("dashboard.zig");
pub const report = @import("report.zig");
pub const license_command = @import("license.zig");
pub const ci = @import("ci.zig");
pub const demo = @import("demo.zig");
pub const disable = @import("disable.zig");
pub const uninstall = @import("uninstall.zig");
pub const interactive = @import("interactive.zig");
pub const child_process = @import("child_process.zig");
pub const style = @import("style.zig");
pub const tui = @import("../tui/mod.zig");
pub const daemon = @import("daemon.zig");
pub const shutdown = @import("shutdown.zig");
pub const shell_eval = @import("shell_eval.zig");
pub const rust_visibility = @import("rust_visibility.zig");
pub const feed_writer = @import("feed_writer.zig");
pub const agent_hook = @import("agent_hook.zig");
pub const daemon_contracts = @import("daemon_contracts.zig");
pub const packs = @import("packs.zig");
pub const history = @import("history.zig");

test {
    // Ensure the child_process module (and its tests) are pulled into the test binary.
    _ = child_process;
    // Pull style tests (TDD for color/TTY/NO_COLOR handling).
    _ = style;
    _ = onboarding;
    _ = start;
    _ = setup;
    _ = quickstart;
    _ = @import("spinner.zig");
    // Pull daemon UDS/IPC tests into the test binary.
    _ = daemon;
    _ = shutdown;
    _ = shell_eval;
    _ = evaluate;
    _ = agent_hook;
    _ = daemon_contracts;
    _ = packs;
    _ = history;
}

pub const version = build_options.version;

/// Minimal allocation-free Levenshtein distance for short ASCII strings (command names).
fn levenshteinDistance(a: []const u8, b: []const u8) usize {
    if (a.len == 0) return b.len;
    if (b.len == 0) return a.len;

    var prev_row: [64]usize = undefined;
    var curr_row: [64]usize = undefined;

    const m = @min(a.len, 63);
    const n = @min(b.len, 63);

    for (0..n + 1) |j| prev_row[j] = j;

    for (0..m) |i| {
        curr_row[0] = i + 1;
        for (0..n) |j| {
            const cost: usize = if (a[i] == b[j]) 0 else 1;
            const del = prev_row[j + 1] + 1;
            const ins = curr_row[j] + 1;
            const sub = prev_row[j] + cost;
            curr_row[j + 1] = @min(@min(del, ins), sub);
        }
        const tmp = prev_row;
        prev_row = curr_row;
        curr_row = tmp;
    }
    return prev_row[n];
}

/// Suggests a close command name for typos / prefixes. Returns null for no good match.
fn suggestCommand(unknown: []const u8) ?[]const u8 {
    // 1. Prefix match (fast, intuitive for partial typing like "do")
    for (help.commands) |cmd| {
        if (std.mem.startsWith(u8, cmd.name, unknown)) return cmd.name;
    }

    // 2. Best edit distance <= 2
    var best: ?[]const u8 = null;
    var best_dist: usize = 3;
    for (help.commands) |cmd| {
        const dist = levenshteinDistance(unknown, cmd.name);
        if (dist < best_dist) {
            best = cmd.name;
            best_dist = dist;
        }
    }
    if (best_dist <= 2) return best;
    return null;
}

/// Commands that render their own branded header internally and so must NOT
/// receive the shared entry banner (would double-print).
const self_banner_commands = [_][]const u8{ "version", "--version", "help", "run" };

/// Commands whose output is always machine/raw (JSON, generated scripts, export
/// lines, long-running servers) — never receive the human brand banner.
const always_machine_commands = [_][]const u8{
    "evaluate", "hook", "shim", "completions", "env", "dashboard", "--print-install-env",
};

fn isAlwaysMachineCommand(command: []const u8) bool {
    for (always_machine_commands) |candidate| if (std.mem.eql(u8, command, candidate)) return true;
    return false;
}

fn isMachineArgv(argv: []const []const u8) bool {
    for (argv, 0..) |arg, index| {
        if (std.mem.eql(u8, arg, "--json") or std.mem.eql(u8, arg, "--stdin")) return true;
        if (std.mem.eql(u8, arg, "--format") and index + 1 < argv.len and std.mem.eql(u8, argv[index + 1], "json")) return true;
    }
    return false;
}

/// True when the compact brand banner should open this invocation. The banner
/// is a presentation-only header; it never appears on `--json`/machine/raw paths
/// (byte-identity invariant) nor on `--help`/`help <cmd>` reference output.
fn shouldShowBanner(command: []const u8, argv: []const []const u8) bool {
    // Self-banner commands render their own header (version key-value grid, top
    // help redesign, run session banner).
    for (self_banner_commands) |s| {
        if (std.mem.eql(u8, command, s)) return false;
    }
    // `decide` is a frozen machine API by default. Only its explicit human
    // output mode participates in shared presentation, even though JSON/stdin
    // are still the input transports.
    if (std.mem.eql(u8, command, "decide")) {
        for (argv[1..]) |arg| {
            if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) return false;
        }
        for (argv[1..]) |arg| if (std.mem.eql(u8, arg, "--human")) return true;
        return false;
    }
    // Reports are generated/export surfaces and never receive a banner, but
    // human error remediation remains presentation-capable. JSON is still
    // classified as machine output by isMachineArgv.
    if (std.mem.eql(u8, command, "report")) return false;
    // Always-machine / raw / server commands.
    if (isAlwaysMachineCommand(command)) return false;
    // `help <cmd>` is command-specific reference help (no banner); bare `help`
    // is top help and renders its own banner inside help.write.
    if (std.mem.eql(u8, command, "help")) return false;
    // Scan subcommand args (argv[1..]) for machine/help tokens.
    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const a = argv[i];
        if (std.mem.eql(u8, a, "--json") or std.mem.eql(u8, a, "--stdin")) return false;
        if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) return false;
        if (std.mem.eql(u8, a, "--format") and i + 1 < argv.len and std.mem.eql(u8, argv[i + 1], "json")) return false;
    }
    // Unknown commands get no banner (error path); the brand header belongs only
    // to recognised human commands.
    return help.findCommand(command) != null;
}

pub fn run(io: std.Io, environ_map: *const std.process.Environ.Map, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    return runWithCwd(io, environ_map, std.Io.Dir.cwd(), argv, stdout, stderr);
}

const GlobalArgs = struct { command_index: usize, no_rich: bool };

fn parseGlobalArgs(argv: []const []const u8) GlobalArgs {
    var index: usize = 0;
    var no_rich = false;
    while (index < argv.len and std.mem.eql(u8, argv[index], "--no-rich")) : (index += 1) no_rich = true;
    return .{ .command_index = index, .no_rich = no_rich };
}

pub fn runWithCwd(io: std.Io, environ_map: *const std.process.Environ.Map, cwd: std.Io.Dir, argv_input: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    const global_args = parseGlobalArgs(argv_input);
    const argv = argv_input[global_args.command_index..];
    const no_rich_env = tui.output_policy.envDisablesRich(environ_map.get("ORCA_NO_RICH"));
    const machine_output = if (argv.len == 0) false else !shouldShowBanner(argv[0], argv) and
        (isMachineArgv(argv) or isAlwaysMachineCommand(argv[0]));
    const output = tui.output_policy.resolve(no_rich_env, global_args.no_rich, machine_output);
    tui.theme.setRichEnabled(output.rich);
    style.setRichEnabled(output.rich);
    defer {
        tui.theme.setRichEnabled(true);
        style.setRichEnabled(null);
    }
    // Fallback / safety-net color decision prime for direct and library callers.
    // The true one-time early prime now lives in main() (real CLI startup path).
    // This call remains so that code paths that enter through runWithCwd directly
    // (tests, library consumers, or future embedding) still get a cached decision
    // before any warm output. If the cache is already populated by main(), this
    // is a fast O(1) cache hit with no side effects.
    _ = style.useColor(io, stdout);

    if (argv.len == 0) {
        if (agent_hook.shouldEnter(io)) {
            return agent_hook.command(io, stdout, stderr) catch |err| switch (err) {
                error.NotAgentHookInput => {
                    try help.write(io, stdout);
                    return exit_codes.success;
                },
                else => return err,
            };
        }
        try help.write(io, stdout);
        return exit_codes.success;
    }
    if (std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h")) {
        try help.write(io, stdout);
        return exit_codes.success;
    }

    const command = argv[0];
    // Compact brand header at the entry of every HUMAN command (Phase 2 brand
    // cohesion). Suppressed for self-banner commands (version/help/run render
    // their own header), always-machine/raw commands, --json/--stdin/--format
    // json machine paths, --help reference output, and unknown commands.
    if (shouldShowBanner(command, argv)) {
        try tui.render.banner(io, stdout, version, null);
    }
    if (std.mem.eql(u8, command, "help")) {
        if (argv.len == 1) {
            try help.write(io, stdout);
            return exit_codes.success;
        }
        if (argv.len > 2) {
            try stderr.writeAll("orca help: expected at most one command.\n");
            return exit_codes.usage;
        }
        if (!try help.writeCommand(io, stdout, argv[1])) {
            try stderr.print("orca help: unknown command '{s}'.\n", .{argv[1]});
            return exit_codes.usage;
        }
        return exit_codes.success;
    }

    if (std.mem.eql(u8, command, "version") or std.mem.eql(u8, command, "--version")) {
        if (argv.len > 2) {
            try stderr.writeAll("orca version: expected at most one argument. Run 'orca help version' for usage.\n");
            return exit_codes.usage;
        }
        if (argv.len == 2) {
            if (std.mem.eql(u8, argv[1], "--help") or std.mem.eql(u8, argv[1], "-h")) {
                _ = try help.writeCommand(io, stdout, "version");
                return exit_codes.success;
            }
            if (std.mem.eql(u8, argv[1], "--json")) {
                try version_command.writeJsonWithDaemon(std.heap.smp_allocator, stdout);
                return exit_codes.success;
            }
            try stderr.writeAll("orca version: unsupported argument. Run 'orca help version' for usage.\n");
            return exit_codes.usage;
        }
        // Human path: compact brand banner + key-value grid (Phase 2).
        try version_command.writeHumanBanner(std.heap.smp_allocator, io, stdout);
        return exit_codes.success;
    }

    if (std.mem.eql(u8, command, "packs")) {
        return packs.command(io, argv[1..], stdout, stderr) catch |err| {
            try stderr.print("orca packs: {s}: {s}\n", .{ daemonErrorLabel(err), @errorName(err) });
            return exit_codes.general;
        };
    }

    if (std.mem.eql(u8, command, "history")) {
        return history.command(io, argv[1..], stdout, stderr) catch |err| {
            try stderr.print("orca history: {s}: {s}\n", .{ daemonErrorLabel(err), @errorName(err) });
            return exit_codes.general;
        };
    }

    if (isPhase1ProxyCommand(command)) {
        return proxyPhase1Command(realDaemonExecuteCli, command, argv[1..], io, stdout, stderr);
    }

    // Highest-value DX helper for installers, Homebrew post-install hooks, npm wrapper,
    // power users, and immediate shell activation. Now layout-aware (selfExePath) and
    // platform-correct. `orca env` is the discoverable alias; the flag is kept for
    // backward compat with any scripts that invoke it directly.
    if (std.mem.eql(u8, command, "--print-install-env")) {
        try writeInstallEnv(io, stdout);
        return exit_codes.success;
    }
    if (std.mem.eql(u8, command, "env")) {
        try writeInstallEnv(io, stdout);
        return exit_codes.success;
    }

    if (std.mem.eql(u8, command, "run")) return run_command.command(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "start")) return start.command(io, cwd, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "quickstart")) return quickstart.command(io, cwd, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "init")) return init.command(io, cwd, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "doctor")) return doctor.command(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "policy")) return policy.command(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "credentials")) return credentials_command.command(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "replay")) return replay.command(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "diff")) return diff.command(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "apply")) return apply.command(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "discard")) return discard.command(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "mcp")) return mcp.command(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "redteam")) return redteam.command(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "completions")) return completions.command(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "shim")) return shim.command(io, environ_map, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "plugin")) return plugin.command(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "setup")) return setup.command(io, cwd, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "decide")) return decide.command(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "evaluate")) return evaluate.command(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "hook")) return hook.command(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "dashboard")) return dashboard_command.command(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "report")) return report.command(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "license")) return license_command.command(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "ci")) return ci.command(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "demo")) return demo.command(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "stop")) return disable.command(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "disable")) return disable.command(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "uninstall")) return uninstall.command(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "shutdown")) return shutdown.command(io, argv[1..], stdout, stderr);

    // Warm "did you mean?" suggestions for unknown commands (foundation UX).
    if (suggestCommand(command)) |suggestion| {
        try stderr.print("orca: unknown command '{s}'. Did you mean '{s}'?\nRun 'orca help' for usage.\n", .{ command, suggestion });
    } else {
        try stderr.print("orca: unknown command '{s}'.\nRun 'orca help' for usage.\n", .{command});
    }
    return exit_codes.usage;
}

fn proxyVersionCommand(comptime execute_cli: anytype, io: std.Io, stdout: anytype, stderr: anytype) !u8 {
    return execute_cli(io, &.{"version"}, stdout, stderr) catch |err| {
        try stderr.print("orca version: {s}: {s}\n", .{ daemonErrorLabel(err), @errorName(err) });
        return exit_codes.general;
    };
}

fn isPhase1ProxyCommand(command: []const u8) bool {
    return std.mem.eql(u8, command, "test") or
        std.mem.eql(u8, command, "scan") or
        std.mem.eql(u8, command, "precommit");
}

fn proxyPhase1Command(comptime execute_cli: anytype, command: []const u8, command_args: []const []const u8, io: std.Io, stdout: anytype, stderr: anytype) !u8 {
    const allocator = std.heap.smp_allocator;
    const daemon_argv = try allocator.alloc([]const u8, command_args.len + 1);
    defer allocator.free(daemon_argv);

    daemon_argv[0] = command;
    if (command_args.len > 0) @memcpy(daemon_argv[1..], command_args);

    return execute_cli(io, daemon_argv, stdout, stderr) catch |err| {
        try stderr.print("orca {s}: {s}: {s}\n", .{ command, daemonErrorLabel(err), @errorName(err) });
        return exit_codes.general;
    };
}

fn daemonErrorLabel(err: anyerror) []const u8 {
    return switch (err) {
        error.HomeDirectoryNotFound,
        error.DaemonBinaryNotFound,
        error.DaemonBinaryNotExecutable,
        error.DaemonSpawnFailed,
        error.DaemonStartTimeout,
        error.DaemonNotReady,
        error.StaleSocket,
        error.SocketConnectFailed,
        => "daemon unavailable",
        error.SocketReadFailed,
        error.SocketWriteFailed,
        => "daemon communication failed",
        error.RequestSerializationFailed,
        error.ResponseParseFailed,
        error.DaemonProtocolError,
        error.MissingHandshake,
        error.HandshakeMalformed,
        error.ProtocolMismatch,
        => "daemon protocol error",
        error.OutOfMemory => "out of memory",
        else => "daemon proxy failed",
    };
}

fn realDaemonExecuteCli(_: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) daemon.DaemonError!u8 {
    var parsed = try daemon.executeCli(std.heap.smp_allocator, argv);
    defer parsed.deinit();

    if (daemon.responseStatus(parsed.value.result) == .error_status) {
        if (daemon.responseErrorMessage(parsed.value.result)) |message| {
            stderr.print("orca daemon: {s}\n", .{message}) catch return error.SocketWriteFailed;
        } else {
            stderr.writeAll("orca daemon: protocol error\n") catch return error.SocketWriteFailed;
        }
        return exit_codes.general;
    }

    const execution = try daemon.parseCliExecution(parsed.value.result);
    stdout.writeAll(execution.stdout) catch return error.SocketWriteFailed;
    if (execution.stderr.len > 0) stderr.writeAll(execution.stderr) catch return error.SocketWriteFailed;
    return execution.exit_code;
}

pub fn executeDaemonCli(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    return realDaemonExecuteCli(io, argv, stdout, stderr);
}

fn testRun(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var env_map = try std.process.Environ.createMap(std.process.Environ.empty, std.testing.allocator);
    defer env_map.deinit();
    return run(std.testing.io, &env_map, argv, stdout, stderr);
}

fn testRunWithCwd(cwd: std.Io.Dir, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var env_map = try std.process.Environ.createMap(std.process.Environ.empty, std.testing.allocator);
    defer env_map.deinit();
    return runWithCwd(std.testing.io, &env_map, cwd, argv, stdout, stderr);
}

test "help output is grouped, complete, and excludes hidden commands" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try testRun(&.{"--help"}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_writer.buffered();
    // Title and category headers present
    try std.testing.expect(std.mem.indexOf(u8, output, "Orca") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Getting Started") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Core Workflow") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Diagnostics & Reporting") != null);
    // Visible commands present
    try std.testing.expect(std.mem.indexOf(u8, output, "run") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "env") != null);
    // Hidden internal command absent
    try std.testing.expect(std.mem.indexOf(u8, output, "shim") == null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "help output uses human-friendly summaries" {
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var empty_buf: [0]u8 = undefined;
    var stderr_writer: std.Io.Writer = .fixed(&empty_buf);

    _ = try testRun(&.{"--help"}, &stdout_writer, &stderr_writer);
    const output = stdout_writer.buffered();

    // Old jargon should be gone from summaries
    try std.testing.expect(std.mem.indexOf(u8, output, "Secretless") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "hook adapter") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "red-team fixtures") == null);

    // New friendly text should be present
    try std.testing.expect(std.mem.indexOf(u8, output, "Verify credential brokers") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Receive events from AI agent hosts") != null);
}

test "env command appears in help and dispatches correctly" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    // env appears in grouped help
    const help_code = try testRun(&.{"--help"}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, help_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "env") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "Print shell environment") != null);

    // env command dispatches
    stdout_writer = .fixed(&stdout_buf);
    stderr_writer = .fixed(&stderr_buf);
    const env_code = try testRun(&.{"env"}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, env_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "PATH") != null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "command-specific help works through help command and command flag" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try testRun(&.{ "help", "run" }, &stdout_writer, &stderr_writer);

    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "orca run") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "Examples:") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "orca run -- echo") != null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());

    stdout_writer = .fixed(&stdout_buf);
    stderr_writer = .fixed(&stderr_buf);
    const flag_code = try testRun(&.{ "run", "--help" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, flag_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "protected session") != null);
}

test "help run includes examples section" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try testRun(&.{ "help", "run" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "Examples:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "orca run -- echo") != null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

fn fakeVersionSuccess(_: std.Io, argv: []const []const u8, stdout: anytype, _: anytype) !u8 {
    try std.testing.expectEqual(@as(usize, 1), argv.len);
    try std.testing.expectEqualStrings("version", argv[0]);
    try stdout.writeAll("orca-rs 1.2.3\n");
    return exit_codes.success;
}

fn fakeVersionError(_: std.Io, argv: []const []const u8, _: anytype, stderr: anytype) !u8 {
    try std.testing.expectEqual(@as(usize, 1), argv.len);
    try std.testing.expectEqualStrings("version", argv[0]);
    try stderr.writeAll("unsupported command\n");
    return exit_codes.general;
}

fn fakeVersionUnavailable(_: std.Io, argv: []const []const u8, _: anytype, _: anytype) !u8 {
    try std.testing.expectEqual(@as(usize, 1), argv.len);
    try std.testing.expectEqualStrings("version", argv[0]);
    return error.DaemonBinaryNotFound;
}

fn fakeTestProxySuccess(_: std.Io, argv: []const []const u8, stdout: anytype, _: anytype) !u8 {
    try std.testing.expectEqual(@as(usize, 2), argv.len);
    try std.testing.expectEqualStrings("test", argv[0]);
    try std.testing.expectEqualStrings("git status", argv[1]);
    try stdout.writeAll("test ok\n");
    return exit_codes.success;
}

fn fakeScanProxySuccess(_: std.Io, argv: []const []const u8, stdout: anytype, _: anytype) !u8 {
    try std.testing.expectEqual(@as(usize, 2), argv.len);
    try std.testing.expectEqualStrings("scan", argv[0]);
    try std.testing.expectEqualStrings("--help", argv[1]);
    try stdout.writeAll("scan ok\n");
    return exit_codes.success;
}

fn fakeHistoryProxySuccess(_: std.Io, argv: []const []const u8, stdout: anytype, _: anytype) !u8 {
    try std.testing.expectEqual(@as(usize, 2), argv.len);
    try std.testing.expectEqualStrings("history", argv[0]);
    try std.testing.expectEqualStrings("--help", argv[1]);
    try stdout.writeAll("history ok\n");
    return exit_codes.success;
}

fn fakeHistoryMachineContract(_: std.Io, argv: []const []const u8, stdout: anytype, _: anytype) !u8 {
    try std.testing.expectEqualStrings("history", argv[0]);
    try std.testing.expectEqualStrings("--format", argv[1]);
    try std.testing.expectEqualStrings("json", argv[2]);
    try stdout.writeAll(@embedFile("test-fixtures/proxy-history.json"));
    return exit_codes.success;
}

fn fakePrecommitProxySuccess(_: std.Io, argv: []const []const u8, stdout: anytype, _: anytype) !u8 {
    try std.testing.expectEqual(@as(usize, 1), argv.len);
    try std.testing.expectEqualStrings("precommit", argv[0]);
    try stdout.writeAll("precommit ok\n");
    return exit_codes.success;
}

fn fakePacksProxySuccess(_: std.Io, argv: []const []const u8, stdout: anytype, _: anytype) !u8 {
    try std.testing.expectEqual(@as(usize, 3), argv.len);
    try std.testing.expectEqualStrings("packs", argv[0]);
    try std.testing.expectEqualStrings("--format", argv[1]);
    try std.testing.expectEqualStrings("json", argv[2]);
    try stdout.writeAll("packs ok\n");
    return exit_codes.success;
}

fn fakePhase1ProxyUnavailable(_: std.Io, argv: []const []const u8, _: anytype, _: anytype) !u8 {
    try std.testing.expectEqual(@as(usize, 1), argv.len);
    try std.testing.expectEqualStrings("packs", argv[0]);
    return error.DaemonBinaryNotFound;
}

test "version proxy routes version argv and renders success" {
    var stdout_buf: [128]u8 = undefined;
    var stderr_buf: [128]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try proxyVersionCommand(fakeVersionSuccess, std.testing.io, &stdout_writer, &stderr_writer);

    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expectEqualStrings("orca-rs 1.2.3\n", stdout_writer.buffered());
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "version proxy propagates daemon error output and exit code" {
    var stdout_buf: [128]u8 = undefined;
    var stderr_buf: [128]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try proxyVersionCommand(fakeVersionError, std.testing.io, &stdout_writer, &stderr_writer);

    try std.testing.expectEqual(exit_codes.general, code);
    try std.testing.expectEqualStrings("", stdout_writer.buffered());
    try std.testing.expectEqualStrings("unsupported command\n", stderr_writer.buffered());
}

test "version proxy reports daemon unavailable explicitly" {
    var stdout_buf: [128]u8 = undefined;
    var stderr_buf: [128]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try proxyVersionCommand(fakeVersionUnavailable, std.testing.io, &stdout_writer, &stderr_writer);

    try std.testing.expectEqual(exit_codes.general, code);
    try std.testing.expectEqualStrings("", stdout_writer.buffered());
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "daemon unavailable") != null);
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "DaemonBinaryNotFound") != null);
}

test "phase 1 proxy commands construct daemon argv and render success" {
    var stdout_buf: [128]u8 = undefined;
    var stderr_buf: [128]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const test_code = try proxyPhase1Command(fakeTestProxySuccess, "test", &.{"git status"}, std.testing.io, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, test_code);
    try std.testing.expectEqualStrings("test ok\n", stdout_writer.buffered());
    try std.testing.expectEqualStrings("", stderr_writer.buffered());

    stdout_writer = .fixed(&stdout_buf);
    stderr_writer = .fixed(&stderr_buf);
    const scan_code = try proxyPhase1Command(fakeScanProxySuccess, "scan", &.{"--help"}, std.testing.io, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, scan_code);
    try std.testing.expectEqualStrings("scan ok\n", stdout_writer.buffered());
    try std.testing.expectEqualStrings("", stderr_writer.buffered());

    stdout_writer = .fixed(&stdout_buf);
    stderr_writer = .fixed(&stderr_buf);
    const history_code = try proxyPhase1Command(fakeHistoryProxySuccess, "history", &.{"--help"}, std.testing.io, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, history_code);
    try std.testing.expectEqualStrings("history ok\n", stdout_writer.buffered());
    try std.testing.expectEqualStrings("", stderr_writer.buffered());

    stdout_writer = .fixed(&stdout_buf);
    stderr_writer = .fixed(&stderr_buf);
    const precommit_code = try proxyPhase1Command(fakePrecommitProxySuccess, "precommit", &.{}, std.testing.io, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, precommit_code);
    try std.testing.expectEqualStrings("precommit ok\n", stdout_writer.buffered());
    try std.testing.expectEqualStrings("", stderr_writer.buffered());

    stdout_writer = .fixed(&stdout_buf);
    stderr_writer = .fixed(&stderr_buf);
    const packs_code = try proxyPhase1Command(fakePacksProxySuccess, "packs", &.{ "--format", "json" }, std.testing.io, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, packs_code);
    try std.testing.expectEqualStrings("packs ok\n", stdout_writer.buffered());
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "phase 1 proxy reports daemon unavailable explicitly" {
    var stdout_buf: [128]u8 = undefined;
    var stderr_buf: [128]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try proxyPhase1Command(fakePhase1ProxyUnavailable, "packs", &.{}, std.testing.io, &stdout_writer, &stderr_writer);

    try std.testing.expectEqual(exit_codes.general, code);
    try std.testing.expectEqualStrings("", stdout_writer.buffered());
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "orca packs: daemon unavailable") != null);
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "DaemonBinaryNotFound") != null);
}

test "proxied machine output remains byte-identical to daemon contract fixture" {
    var stdout_buf: [256]u8 = undefined;
    var stderr_buf: [128]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);
    const code = try proxyPhase1Command(fakeHistoryMachineContract, "history", &.{ "--format", "json" }, std.testing.io, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expectEqualStrings(@embedFile("test-fixtures/proxy-history.json"), stdout_writer.buffered());
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "daemonErrorLabel distinguishes protocol compatibility failures" {
    try std.testing.expectEqualStrings("daemon protocol error", daemonErrorLabel(error.ProtocolMismatch));
    try std.testing.expectEqualStrings("daemon protocol error", daemonErrorLabel(error.MissingHandshake));
    try std.testing.expectEqualStrings("daemon protocol error", daemonErrorLabel(error.HandshakeMalformed));
}

test "version supports json, help, and rejects extra arguments" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const plain_code = try testRun(&.{"version"}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, plain_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), version) != null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());

    stdout_writer = .fixed(&stdout_buf);
    stderr_writer = .fixed(&stderr_buf);
    const help_code = try testRun(&.{ "version", "--help" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, help_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "orca version") != null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());

    stdout_writer = .fixed(&stdout_buf);
    stderr_writer = .fixed(&stderr_buf);
    const json_code = try testRun(&.{ "version", "--json" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, json_code);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, stdout_writer.buffered(), .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings(version, parsed.value.object.get("version").?.string);
    try std.testing.expect(parsed.value.object.get("commit") != null);
    try std.testing.expect(parsed.value.object.get("target") != null);
    try std.testing.expect(parsed.value.object.get("build_date") != null);

    stdout_writer = .fixed(&stdout_buf);
    stderr_writer = .fixed(&stderr_buf);
    const invalid_code = try testRun(&.{ "version", "typo" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.usage, invalid_code);
    try std.testing.expectEqualStrings("", stdout_writer.buffered());
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "unsupported argument") != null);
}

test "unknown command returns non-zero with useful message" {
    var stdout_buf: [128]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try testRun(&.{"not-a-command"}, &stdout_writer, &stderr_writer);

    try std.testing.expect(code != exit_codes.success);
    try std.testing.expectEqual(exit_codes.usage, code);
    try std.testing.expectEqualStrings("", stdout_writer.buffered());
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "unknown command") != null);
}

// ---------------------------------------------------------------------------
// Phase 2 TDD: brand cohesion banner system (written FIRST — RED).
// The compact `🛡  Orca · v<version>` header must open every HUMAN command,
// be suppressed for --json / raw / machine / help-reference paths, and stay
// byte-identical on --json. Banner marker in the plain-text degrade path is
// the literal `🛡  Orca` glyph run (colour is suppressed under builtin.is_test).
// ---------------------------------------------------------------------------

test "version human path renders brand banner and key-value grid" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try testRun(&.{"version"}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);
    const out = stdout_writer.buffered();
    // Compact brand header.
    try std.testing.expect(std.mem.indexOf(u8, out, "\u{1F6E1}  Orca") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, version) != null);
    // Key-value grid labels.
    try std.testing.expect(std.mem.indexOf(u8, out, "Version") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Channel") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Target") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Daemon") != null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "version --json suppresses the brand banner (machine contract)" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try testRun(&.{ "version", "--json" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);
    const out = stdout_writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, out, "\u{1F6E1}  Orca") == null);
    try std.testing.expect(out.len > 0 and out[0] == '{');
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, out, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings(version, parsed.value.object.get("version").?.string);
}

test "top help renders brand banner, accent categories, and try-next hint" {
    var stdout_buf: [16384]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try testRun(&.{"--help"}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);
    const out = stdout_writer.buffered();
    // Brand banner opens the help.
    try std.testing.expect(std.mem.indexOf(u8, out, "\u{1F6E1}  Orca") != null);
    // Accent category headers retained.
    try std.testing.expect(std.mem.indexOf(u8, out, "Getting Started") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Core Workflow") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Diagnostics & Reporting") != null);
    // Two-column command + summary retained.
    try std.testing.expect(std.mem.indexOf(u8, out, "Print shell environment") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Receive events from AI agent hosts") != null);
    // Try-next hint present.
    try std.testing.expect(std.mem.indexOf(u8, out, "orca quickstart") != null);
    // Hidden internal command still absent.
    try std.testing.expect(std.mem.indexOf(u8, out, "shim") == null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "banner renders on a human command (doctor)" {
    var stdout_buf: [16384]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try testRun(&.{"doctor"}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);
    const out = stdout_writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, out, "\u{1F6E1}  Orca") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Summary:") != null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "banner suppressed for raw env output" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try testRun(&.{"env"}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);
    const out = stdout_writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, out, "PATH") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\u{1F6E1}  Orca") == null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "banner suppressed for completions raw output" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try testRun(&.{ "completions", "bash" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);
    const out = stdout_writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, out, "complete -F") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\u{1F6E1}  Orca") == null);
}

test "report generated exports are classified as raw at top level" {
    try std.testing.expect(!shouldShowBanner("report", &.{"report"}));
    try std.testing.expect(!shouldShowBanner("report", &.{ "report", "--format", "markdown" }));
    try std.testing.expect(!shouldShowBanner("report", &.{ "report", "--format", "json" }));
}

extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;

fn writeTopLevelReportFixture(io: std.Io, allocator: std.mem.Allocator, workspace_root: []const u8) ![]u8 {
    const core = @import("orca_core").core;
    const core_api = @import("orca_core").api;
    const now = core.time.Timestamp.fromUnixSeconds(1_777_983_130);
    var session_id: core.session.SessionId = .{ .value = undefined, .len = 0 };
    const session_id_text = try std.fmt.bufPrint(&session_id.value, "report-output-fixture", .{});
    session_id.len = session_id_text.len;
    const session = core.session.Session{
        .id = session_id,
        .started_at = now,
        .ended_at = now,
        .command = "orca",
        .args = &.{ "run", "--", "rm", "-rf", "./fixture" },
        .workspace_root = workspace_root,
        .session_name = "report-output-test",
        .mode = .strict,
        .platform = core.platform.detectOs(),
    };
    var audit_writer = try core_api.createAuditWriter(io, allocator, session);
    defer audit_writer.deinit();
    var event_id: core.event.EventId = .{ .value = undefined, .len = 0 };
    const event_id_text = try std.fmt.bufPrint(&event_id.value, "denied", .{});
    event_id.len = event_id_text.len;
    const event = try core_api.createAuditEvent(.{
        .session_id = session.id,
        .event_id = event_id,
        .timestamp = now,
        .event_type = .command_denied,
        .actor = .{ .kind = .orca, .display = "orca" },
        .target = .{ .kind = .command, .value = "rm -rf ./fixture" },
        .decision = core_api.makeDecision(.{ .result = .deny, .reason = "blocked by fixture policy", .rule_id = "commands.deny" }),
        .redactions = .{ .count = 1, .labels = &.{"fixture-label"} },
    });
    try core_api.appendAuditEvent(&audit_writer, event);
    try audit_writer.writeLastPointer();
    try core_api.writeAuditSummary(allocator, audit_writer.sessionDirPath(), .{
        .session = session,
        .status = .{ .exited = 1 },
        .event_count = audit_writer.event_count,
        .final_event_hash = audit_writer.finalHash() orelse "",
        .policy = ".orca/policy.yaml",
        .product_label = "Orca",
    });
    return allocator.dupe(u8, audit_writer.session_id.slice());
}

test "top-level report exports preserve exact generated bytes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const previous_xdg: ?[:0]u8 = if (std.c.getenv("XDG_CONFIG_HOME")) |value|
        try std.testing.allocator.dupeZ(u8, std.mem.sliceTo(value, 0))
    else
        null;
    defer {
        if (previous_xdg) |value| {
            _ = setenv("XDG_CONFIG_HOME", value, 1);
            std.testing.allocator.free(value);
        } else _ = unsetenv("XDG_CONFIG_HOME");
    }
    const previous_path: ?[:0]u8 = if (std.c.getenv("PATH")) |value|
        try std.testing.allocator.dupeZ(u8, std.mem.sliceTo(value, 0))
    else
        null;
    defer {
        if (previous_path) |value| {
            _ = setenv("PATH", value, 1);
            std.testing.allocator.free(value);
        } else _ = unsetenv("PATH");
    }
    try std.testing.expectEqual(@as(c_int, 0), setenv("XDG_CONFIG_HOME", root, 1));
    try std.testing.expectEqual(@as(c_int, 0), setenv("PATH", "", 1));
    const license_path = try std.fs.path.join(std.testing.allocator, &.{ root, "orca", "license.json" });
    defer std.testing.allocator.free(license_path);
    var activated = try @import("../license.zig").activateToPath(std.testing.io, std.testing.allocator, "dev-pro", license_path);
    activated.deinit();
    try tmp.dir.createDirPath(std.testing.io, ".orca");
    {
        const policy_file = try tmp.dir.createFile(std.testing.io, ".orca/policy.yaml", .{});
        defer policy_file.close(std.testing.io);
        try policy_file.writeStreamingAll(std.testing.io, "version: 1\nmode: strict\n");
    }
    const session_id = try writeTopLevelReportFixture(std.testing.io, std.testing.allocator, root);
    defer std.testing.allocator.free(session_id);
    const previous_cwd = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(previous_cwd);
    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer std.process.setCurrentPath(std.testing.io, previous_cwd) catch {};

    const expected_markdown =
        \\# Orca Safety Report: report-output-fixture
        \\
        \\- Session id: `report-output-fixture`
        \\- Command: `orca run -- rm -rf ./fixture`
        \\- Status: exit 1
        \\- Policy path: .orca/policy.yaml
        \\- Hash-chain verification: verified
        \\- Denied/prevented actions: 1
        \\- Redactions: 1 (fixture-label)
        \\
        \\## What Orca Prevented
        \\
        \\Orca prevented 1 action from continuing because the active local policy denied them.
        \\
        \\- `rm -rf ./fixture` was blocked. Reason: blocked by fixture policy
        \\
        \\## Plugin Readiness
        \\
        \\- OpenClaw: host not detected, integration missing
        \\- Hermes: host not detected, integration missing
        \\
    ;
    const expected_json =
        \\{"session_id":"report-output-fixture","command":"orca run -- rm -rf ./fixture","status":"exit 1","policy_path":".orca/policy.yaml","hash_chain_verified":true,"denied_count":1,"redactions":{"count":1,"labels":["fixture-label"]},"denied_actions":[{"event_type":"command_denied","target":"rm -rf ./fixture","reason":"blocked by fixture policy"}],"plugins":[{"id":"openclaw","host_detected":false,"integration_present":false},{"id":"hermes","host_detected":false,"integration_present":false}]}
        \\
    ;

    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout: std.Io.Writer = .fixed(&stdout_buf);
    var stderr: std.Io.Writer = .fixed(&stderr_buf);
    try std.testing.expectEqual(exit_codes.success, try testRun(&.{ "report", "--session", session_id }, &stdout, &stderr));
    try std.testing.expectEqualStrings(expected_markdown, stdout.buffered());
    try std.testing.expectEqualStrings("", stderr.buffered());

    inline for (.{
        .{ .argv = &.{ "report", "--session", session_id, "--format", "markdown" }, .expected = expected_markdown },
        .{ .argv = &.{ "report", "--session", session_id, "--format", "json" }, .expected = expected_json },
    }) |case| {
        stdout = .fixed(&stdout_buf);
        stderr = .fixed(&stderr_buf);
        try std.testing.expectEqual(exit_codes.success, try testRunWithCwd(tmp.dir, case.argv, &stdout, &stderr));
        try std.testing.expectEqualStrings(case.expected, stdout.buffered());
        try std.testing.expectEqualStrings("", stderr.buffered());
    }
    stdout = .fixed(&stdout_buf);
    stderr = .fixed(&stderr_buf);
    try std.testing.expectEqual(exit_codes.success, try testRun(&.{ "report", "--session", session_id, "--format", "json" }, &stdout, &stderr));
    try std.testing.expectEqualStrings(expected_json, stdout.buffered());
    try std.testing.expectEqualStrings("", stderr.buffered());
}

test "banner suppressed on machine proxy path (packs --format json)" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    _ = try testRun(&.{ "packs", "--format", "json" }, &stdout_writer, &stderr_writer);
    // Machine path must not emit a brand banner to stdout (byte-identity).
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "\u{1F6E1}  Orca") == null);
}

test "decide human mode gets a banner while default JSON remains machine output" {
    try std.testing.expect(shouldShowBanner("decide", &.{ "decide", "command", "--human", "--json", "{}" }));
    try std.testing.expect(!shouldShowBanner("decide", &.{ "decide", "command", "--json", "{}" }));
    try std.testing.expect(!shouldShowBanner("decide", &.{ "decide", "command", "--human", "--stdin", "--help" }));
}

test "decide human mode honors no-rich without changing default machine JSON" {
    var machine_buf: [4096]u8 = undefined;
    var human_buf: [4096]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var machine: std.Io.Writer = .fixed(&machine_buf);
    var human: std.Io.Writer = .fixed(&human_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);
    const payload = "{\"command\":\"echo hello\"}";

    try std.testing.expectEqual(exit_codes.success, try testRun(&.{ "--no-rich", "decide", "command", "--json", payload }, &machine, &stderr_writer));
    try std.testing.expectEqualStrings(@embedFile("test-fixtures/decide-command-allow.json"), machine.buffered());

    stderr_writer = .fixed(&stderr_buf);
    try std.testing.expectEqual(exit_codes.success, try testRun(&.{ "--no-rich", "decide", "command", "--human", "--json", payload }, &human, &stderr_writer));
    try std.testing.expect(std.mem.indexOf(u8, human.buffered(), "[ALLOW]") != null);
    try std.testing.expect(std.mem.indexOfScalar(u8, human.buffered(), 0x1b) == null);
}

test "global --no-rich is consumed without changing version JSON contract" {
    var baseline_buf: [4096]u8 = undefined;
    var escaped_buf: [4096]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var baseline: std.Io.Writer = .fixed(&baseline_buf);
    var escaped: std.Io.Writer = .fixed(&escaped_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    try std.testing.expectEqual(exit_codes.success, try testRun(&.{ "version", "--json" }, &baseline, &stderr_writer));
    stderr_writer = .fixed(&stderr_buf);
    try std.testing.expectEqual(exit_codes.success, try testRun(&.{ "--no-rich", "version", "--json" }, &escaped, &stderr_writer));
    try std.testing.expectEqualStrings(baseline.buffered(), escaped.buffered());
}

test "global flag parser only consumes no-rich before the command" {
    const prefix = parseGlobalArgs(&.{ "--no-rich", "version", "--json" });
    try std.testing.expect(prefix.no_rich);
    try std.testing.expectEqual(@as(usize, 1), prefix.command_index);
    const literal = parseGlobalArgs(&.{ "run", "--", "echo", "--no-rich" });
    try std.testing.expect(!literal.no_rich);
    try std.testing.expectEqual(@as(usize, 0), literal.command_index);
    const value = parseGlobalArgs(&.{ "decide", "command", "--json", "{\"value\":\"--no-rich\"}" });
    try std.testing.expect(!value.no_rich);
}

test "ORCA_NO_RICH truthy variants suppress presentation without changing machine JSON" {
    const variants = [_][]const u8{ "1", "true", "yes" };
    for (variants) |variant| {
        var env_map = try std.process.Environ.createMap(std.process.Environ.empty, std.testing.allocator);
        defer env_map.deinit();
        try env_map.put("ORCA_NO_RICH", variant);
        var stdout_buf: [4096]u8 = undefined;
        var stderr_buf: [256]u8 = undefined;
        var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
        var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);
        try std.testing.expectEqual(exit_codes.success, try run(std.testing.io, &env_map, &.{ "version", "--json" }, &stdout_writer, &stderr_writer));
        try std.testing.expect(stdout_writer.buffered().len > 0 and stdout_writer.buffered()[0] == '{');
        try std.testing.expect(std.mem.indexOfScalar(u8, stdout_writer.buffered(), 0x1b) == null);
        try std.testing.expectEqualStrings("", stderr_writer.buffered());
    }
}

test "banner suppressed on command-specific help (help run)" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try testRun(&.{ "help", "run" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);
    const out = stdout_writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, out, "orca run") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\u{1F6E1}  Orca") == null);
}

test "banner suppressed on subcommand --help (doctor --help)" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try testRun(&.{ "doctor", "--help" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);
    const out = stdout_writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, out, "orca doctor") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\u{1F6E1}  Orca") == null);
}

// ---------------------------------------------------------------------------
// TDD tests for "Did you mean?" suggestions (written FIRST — RED, foundation work)
// ---------------------------------------------------------------------------

test "unknown command suggests typo correction" {
    // "docter" should suggest "doctor" via Levenshtein distance
    const suggestion = suggestCommand("docter");
    try std.testing.expect(suggestion != null);
    try std.testing.expectEqualStrings("doctor", suggestion.?);
}

test "unknown command suggests prefix match" {
    // Prefix match takes priority
    const suggestion = suggestCommand("do");
    try std.testing.expect(suggestion != null);
    // "doctor" or "stop" etc. are valid; just ensure something returned
    try std.testing.expect(suggestion.?.len > 0);
}

test "completely unknown command has no suggestion" {
    const suggestion = suggestCommand("xyz123neveracmd");
    try std.testing.expect(suggestion == null);
}

test "init dispatch creates policy in provided working directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try testRunWithCwd(tmp.dir, &.{ "init", "--mode", "strict" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);

    const policy_text = try tmp.dir.readFileAlloc(std.testing.io, ".orca/policy.yaml", std.testing.allocator, .limited(4096));
    defer std.testing.allocator.free(policy_text);
    try std.testing.expect(std.mem.indexOf(u8, policy_text, "mode: strict") != null);
}

test "doctor dispatch prints summary by default" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try testRun(&.{"doctor"}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);
    const output = stdout_writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "Summary:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Capabilities:") == null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "doctor dispatch --verbose prints platform capabilities" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try testRun(&.{ "doctor", "--verbose" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "Capabilities:") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "network policy engine: active") != null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "start dispatch appears in help and runs with --auto in temp workspace" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const help_code = try testRun(&.{"--help"}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, help_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "start") != null);

    stdout_writer = .fixed(&stdout_buf);
    stderr_writer = .fixed(&stderr_buf);
    const code = try testRunWithCwd(tmp.dir, &.{ "start", "--auto", "--protection", "firewall", "--skip-verify" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "\u{1F6E1}  Orca") != null);
}

test "start auto-runs on non-TTY without --auto" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try testRunWithCwd(tmp.dir, &.{ "start", "--protection", "firewall", "--skip-verify" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "\u{1F6E1}  Orca") != null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "quickstart dispatch runs and prints steps" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try testRunWithCwd(tmp.dir, &.{"quickstart"}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "\u{1F6E1}  Orca") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Step 1 — System check") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Step 2 — Policy") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Step 3 — Host integrations") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Core protection is ready") != null);
}

test "quickstart skips init when policy exists" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, ".orca");
    {
        const file = try tmp.dir.createFile(std.testing.io, ".orca/policy.yaml", .{});
        defer file.close(std.testing.io);
        try file.writeStreamingAll(std.testing.io, "version: 1\nmode: observe\n");
    }

    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try testRunWithCwd(tmp.dir, &.{"quickstart"}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "already exists — skipping init") != null);
}

test "stop dispatch is the public disable command" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const help_code = try testRun(&.{ "help", "stop" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, help_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "orca stop") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "cursor") != null);

    stdout_writer = .fixed(&stdout_buf);
    stderr_writer = .fixed(&stderr_buf);
    const code = try testRun(&.{ "stop", "-all" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.usage, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "orca stop") != null);
}

test "completions dispatch prints shell script" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try testRun(&.{ "completions", "bash" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "complete -F") != null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "policy command rejects unknown subcommands" {
    var stdout_buf: [256]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try testRun(&.{ "policy", "--bad" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.usage, code);
    // The brand banner opens the command (presentation only); the usage error
    // still goes to stderr.
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "\u{1F6E1}  Orca") != null);
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "unknown subcommand") != null);
}

test "run dispatch launches child command" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try run_command.commandForTest(&.{ "--", "zig", "version" }, &stdout_writer, &stderr_writer, .ignore);
    try std.testing.expectEqual(exit_codes.success, code);
    // Phase 2: printSessionStart now renders the shared brand banner + key-value
    // grid (the hand-rolled shield line is retired). The session shield +
    // first-run celebration remain in printSessionEnd.
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "\u{1F6E1}  Orca") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "watching this session") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "Session ended cleanly") != null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

// ---------------------------------------------------------------------------
// Phase 3 TDD tests: messaging and help text updates for guided onboarding
// These tests are written FIRST (RED). They will fail until help text is updated
// to describe the new default guided behavior and de-emphasize --yes.
// ---------------------------------------------------------------------------

test "setup help describes guided interactive default on TTY and de-emphasizes --auto for primary path" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try testRun(&.{ "help", "setup" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_writer.buffered();
    // Accurate for Phase 3 guided flow: mentions guided mode and arrow-key selection.
    try std.testing.expect(std.mem.indexOf(u8, output, "guided") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "arrow") != null or std.mem.indexOf(u8, output, "--auto") != null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "plugin help and disable re-enable messaging de-emphasize --yes in favor of setup" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try testRun(&.{ "help", "plugin" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_writer.buffered();
    // Primary path is `orca setup` (guided on TTY); messaging updated for Phase 0 stub.
    try std.testing.expect(std.mem.indexOf(u8, output, "setup") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "guided") != null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

// writeInstallEnv — the trustworthy, layout-aware activation printer for installers,
// Homebrew post-install, npm wrappers, power users, and `eval "$(orca env)"`.
// Uses the running binary's actual location (selfExePath) so custom prefixes
// (Homebrew, containers, non-~ installs) produce correct exports. Falls back to
// documented platform defaults. Windows uses cmd.exe set syntax; Unix uses sh export.
// Concrete absolute paths (not $HOME) guarantee "actual install layout" fidelity.
fn writeInstallEnv(io: std.Io, stdout: anytype) !void {
    const allocator = std.heap.page_allocator;
    const exe_path = std.process.executablePathAlloc(io, allocator) catch {
        // Fallback (static or exotic exe path): documented defaults per platform.
        if (builtin.os.tag == .windows) {
            try stdout.writeAll("set \"PATH=%USERPROFILE%\\.orca\\bin;%PATH%\"\n");
            try stdout.writeAll("set \"ORCA_RESOURCE_ROOT=%USERPROFILE%\\.orca\\share\\current\"\n");
        } else {
            try stdout.writeAll("export PATH=\"$HOME/.local/bin:$PATH\"\n");
            try stdout.writeAll("export ORCA_RESOURCE_ROOT=\"$HOME/.local/share/orca/current\"\n");
        }
        return;
    };
    defer allocator.free(exe_path);

    const bin_dir = std.fs.path.dirname(exe_path) orelse {
        // Same fallback as above.
        if (builtin.os.tag == .windows) {
            try stdout.writeAll("set \"PATH=%USERPROFILE%\\.orca\\bin;%PATH%\"\n");
            try stdout.writeAll("set \"ORCA_RESOURCE_ROOT=%USERPROFILE%\\.orca\\share\\current\"\n");
        } else {
            try stdout.writeAll("export PATH=\"$HOME/.local/bin:$PATH\"\n");
            try stdout.writeAll("export ORCA_RESOURCE_ROOT=\"$HOME/.local/share/orca/current\"\n");
        }
        return;
    };

    const prefix_dir = std.fs.path.dirname(bin_dir) orelse bin_dir;

    const is_win = builtin.os.tag == .windows;
    const resource_root = if (is_win)
        std.fs.path.join(allocator, &.{ prefix_dir, "share", "current" }) catch {
            // Fallback on join failure (extremely rare).
            try stdout.writeAll("set \"PATH=%USERPROFILE%\\.orca\\bin;%PATH%\"\n");
            try stdout.writeAll("set \"ORCA_RESOURCE_ROOT=%USERPROFILE%\\.orca\\share\\current\"\n");
            return;
        }
    else
        std.fs.path.join(allocator, &.{ prefix_dir, "share", "orca", "current" }) catch {
            try stdout.writeAll("export PATH=\"$HOME/.local/bin:$PATH\"\n");
            try stdout.writeAll("export ORCA_RESOURCE_ROOT=\"$HOME/.local/share/orca/current\"\n");
            return;
        };
    defer allocator.free(resource_root);

    if (is_win) {
        try stdout.print("set \"PATH={s};%PATH%\"\n", .{bin_dir});
        try stdout.print("set \"ORCA_RESOURCE_ROOT={s}\"\n", .{resource_root});
    } else {
        try stdout.print("export PATH=\"{s}:$PATH\"\n", .{bin_dir});
        try stdout.print("export ORCA_RESOURCE_ROOT=\"{s}\"\n", .{resource_root});
    }
}
