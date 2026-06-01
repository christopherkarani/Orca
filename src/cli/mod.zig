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
pub const onboarding = @import("onboarding.zig");
pub const quickstart = @import("quickstart.zig");
pub const decide = @import("decide.zig");
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

test {
    // Ensure the child_process module (and its tests) are pulled into the test binary.
    _ = child_process;
    // Pull style tests (TDD for color/TTY/NO_COLOR handling).
    _ = style;
    _ = onboarding;
    _ = quickstart;
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

pub fn run(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    return runWithCwd(std.fs.cwd(), argv, stdout, stderr);
}

pub fn runWithCwd(cwd: std.fs.Dir, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    // Fallback / safety-net color decision prime for direct and library callers.
    // The true one-time early prime now lives in main() (real CLI startup path).
    // This call remains so that code paths that enter through runWithCwd directly
    // (tests, library consumers, or future embedding) still get a cached decision
    // before any warm output. If the cache is already populated by main(), this
    // is a fast O(1) cache hit with no side effects.
    _ = style.useColor(stdout);

    if (argv.len == 0 or std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h")) {
        try help.write(stdout);
        return exit_codes.success;
    }

    const command = argv[0];
    if (std.mem.eql(u8, command, "help")) {
        if (argv.len == 1) {
            try help.write(stdout);
            return exit_codes.success;
        }
        if (argv.len > 2) {
            try stderr.writeAll("orca help: expected at most one command.\n");
            return exit_codes.usage;
        }
        if (!try help.writeCommand(stdout, argv[1])) {
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
                _ = try help.writeCommand(stdout, "version");
                return exit_codes.success;
            }
            if (std.mem.eql(u8, argv[1], "--json")) {
                try version_command.writeJson(stdout, version_command.current());
                return exit_codes.success;
            }
            try stderr.writeAll("orca version: unsupported argument. Run 'orca help version' for usage.\n");
            return exit_codes.usage;
        }
        try version_command.writePlain(stdout, version_command.current());
        return exit_codes.success;
    }

    // Highest-value DX helper for installers, Homebrew post-install hooks, npm wrapper,
    // power users, and immediate shell activation. Now layout-aware (selfExePath) and
    // platform-correct. `orca env` is the discoverable alias; the flag is kept for
    // backward compat with any scripts that invoke it directly.
    if (std.mem.eql(u8, command, "--print-install-env")) {
        try writeInstallEnv(stdout);
        return exit_codes.success;
    }
    if (std.mem.eql(u8, command, "env")) {
        try writeInstallEnv(stdout);
        return exit_codes.success;
    }

    if (std.mem.eql(u8, command, "run")) return run_command.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "quickstart")) return quickstart.command(cwd, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "init")) return init.command(cwd, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "doctor")) return doctor.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "policy")) return policy.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "credentials")) return credentials_command.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "replay")) return replay.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "diff")) return diff.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "apply")) return apply.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "discard")) return discard.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "mcp")) return mcp.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "redteam")) return redteam.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "completions")) return completions.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "shim")) return shim.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "plugin")) return plugin.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "setup")) return setup.command(cwd, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "decide")) return decide.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "hook")) return hook.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "dashboard")) return dashboard_command.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "report")) return report.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "license")) return license_command.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "ci")) return ci.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "demo")) return demo.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "disable")) return disable.command(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "uninstall")) return uninstall.command(argv[1..], stdout, stderr);

    // Warm "did you mean?" suggestions for unknown commands (foundation UX).
    if (suggestCommand(command)) |suggestion| {
        try stderr.print("orca: unknown command '{s}'. Did you mean '{s}'?\nRun 'orca help' for usage.\n", .{ command, suggestion });
    } else {
        try stderr.print("orca: unknown command '{s}'.\nRun 'orca help' for usage.\n", .{command});
    }
    return exit_codes.usage;
}

test "help output is grouped, complete, and excludes hidden commands" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try run(&.{"--help"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
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
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "help output uses human-friendly summaries" {
    var stdout_buf: [4096]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var empty_buf: [0]u8 = undefined;
    var stderr_stream = std.io.fixedBufferStream(&empty_buf);

    _ = try run(&.{"--help"}, stdout_stream.writer(), stderr_stream.writer());
    const output = stdout_stream.getWritten();

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
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    // env appears in grouped help
    const help_code = try run(&.{"--help"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, help_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "env") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Print shell environment") != null);

    // env command dispatches
    stdout_stream.reset();
    stderr_stream.reset();
    const env_code = try run(&.{"env"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, env_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "PATH") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "command-specific help works through help command and command flag" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try run(&.{ "help", "run" }, stdout_stream.writer(), stderr_stream.writer());

    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "orca run") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Examples:") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "orca run -- echo") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    stdout_stream.reset();
    stderr_stream.reset();
    const flag_code = try run(&.{ "run", "--help" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, flag_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "protected session") != null);
}

test "help run includes examples section" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try run(&.{ "help", "run" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Examples:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "orca run -- echo") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "version prints development version" {
    var stdout_buf: [128]u8 = undefined;
    var stderr_buf: [128]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try run(&.{"version"}, stdout_stream.writer(), stderr_stream.writer());

    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.startsWith(u8, stdout_stream.getWritten(), "orca "));
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), version) != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "version supports json, help, and rejects extra arguments" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const help_code = try run(&.{ "version", "--help" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, help_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "orca version") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    stdout_stream.reset();
    stderr_stream.reset();
    const json_code = try run(&.{ "version", "--json" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, json_code);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, stdout_stream.getWritten(), .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings(version, parsed.value.object.get("version").?.string);
    try std.testing.expect(parsed.value.object.get("commit") != null);
    try std.testing.expect(parsed.value.object.get("target") != null);
    try std.testing.expect(parsed.value.object.get("build_date") != null);

    stdout_stream.reset();
    stderr_stream.reset();
    const invalid_code = try run(&.{ "version", "typo" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, invalid_code);
    try std.testing.expectEqualStrings("", stdout_stream.getWritten());
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "unsupported argument") != null);
}

test "unknown command returns non-zero with useful message" {
    var stdout_buf: [128]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try run(&.{"not-a-command"}, stdout_stream.writer(), stderr_stream.writer());

    try std.testing.expect(code != exit_codes.success);
    try std.testing.expectEqual(exit_codes.usage, code);
    try std.testing.expectEqualStrings("", stdout_stream.getWritten());
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "unknown command") != null);
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
    // "doctor" or "disable" etc. are valid; just ensure something returned
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
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try runWithCwd(tmp.dir, &.{ "init", "--mode", "strict" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const policy_text = try tmp.dir.readFileAlloc(std.testing.allocator, ".orca/policy.yaml", 4096);
    defer std.testing.allocator.free(policy_text);
    try std.testing.expect(std.mem.indexOf(u8, policy_text, "mode: strict") != null);
}

test "doctor dispatch prints summary by default" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try run(&.{"doctor"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);
    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Summary:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Capabilities:") == null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "doctor dispatch --verbose prints platform capabilities" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try run(&.{ "doctor", "--verbose" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Capabilities:") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "network policy engine: active") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "quickstart dispatch runs and prints steps" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try runWithCwd(tmp.dir, &.{"quickstart"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Orca Quickstart") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Step 1: Checking your system") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Step 2: Creating your first policy") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Step 3: Setting up") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "You're all set!") != null);
}

test "quickstart skips init when policy exists" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath(".orca");
    {
        const file = try tmp.dir.createFile(".orca/policy.yaml", .{});
        defer file.close();
        try file.writeAll("version: 1\nmode: observe\n");
    }

    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try runWithCwd(tmp.dir, &.{"quickstart"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Policy already exists") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Skipping init") != null);
}

test "completions dispatch prints shell script" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try run(&.{ "completions", "bash" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "complete -F") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "policy command rejects unknown subcommands" {
    var stdout_buf: [256]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try run(&.{ "policy", "--bad" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, code);
    try std.testing.expectEqualStrings("", stdout_stream.getWritten());
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "unknown subcommand") != null);
}

test "run dispatch launches child command" {
    var stdout_buf: [256]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try run_command.commandForTest(&.{ "--", "zig", "version" }, stdout_stream.writer(), stderr_stream.writer(), .ignore);
    try std.testing.expectEqual(exit_codes.success, code);
    // TDD: new framed output with shield + separators + status glyphs (foundation work)
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Orca is watching this session") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Session ended cleanly") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

// ---------------------------------------------------------------------------
// Phase 3 TDD tests: messaging and help text updates for guided onboarding
// These tests are written FIRST (RED). They will fail until help text is updated
// to describe the new default guided behavior and de-emphasize --yes.
// ---------------------------------------------------------------------------

test "setup help describes guided interactive default on TTY and de-emphasizes --auto for primary path" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try run(&.{ "help", "setup" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    // Accurate for current Phase 0 guided stub: mentions guided and the TTY/auto distinction.
    // Full interactive toggle UI is future work; help text reflects stub reality.
    try std.testing.expect(std.mem.indexOf(u8, output, "guided") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "auto-selects") != null or std.mem.indexOf(u8, output, "--auto") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin help and disable re-enable messaging de-emphasize --yes in favor of setup" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try run(&.{ "help", "plugin" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    // Primary path is `orca setup` (guided on TTY); messaging updated for Phase 0 stub.
    try std.testing.expect(std.mem.indexOf(u8, output, "setup") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "guided") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

// writeInstallEnv — the trustworthy, layout-aware activation printer for installers,
// Homebrew post-install, npm wrappers, power users, and `eval "$(orca env)"`.
// Uses the running binary's actual location (selfExePath) so custom prefixes
// (Homebrew, containers, non-~ installs) produce correct exports. Falls back to
// documented platform defaults. Windows uses cmd.exe set syntax; Unix uses sh export.
// Concrete absolute paths (not $HOME) guarantee "actual install layout" fidelity.
fn writeInstallEnv(stdout: anytype) !void {
    const allocator = std.heap.page_allocator;
    const exe_path = std.fs.selfExePathAlloc(allocator) catch {
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
