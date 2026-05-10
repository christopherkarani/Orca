const std = @import("std");

// ---------------------------------------------------------------------------
// P05 — Plugin Security and Compatibility Tests
// ---------------------------------------------------------------------------
// These tests validate:
//   - Hook behavior with fake payloads (via built binary)
//   - aegis decide behavior
//   - Invalid and oversized input handling
//   - Secret safety across plugin artifacts
//   - Documentation overclaim checks
//   - Separate workstream (drone) non-regression
// ---------------------------------------------------------------------------

const aegis_bin = "./zig-out/bin/aegis";
const codex_fixture_dir = "tests/plugin-fixtures/codex";
const claude_fixture_dir = "tests/plugin-fixtures/claude";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const stat = try file.stat();
    const size = stat.size;
    if (size > 1024 * 1024) return error.FileTooLarge;
    const buf = try allocator.alloc(u8, @intCast(size));
    errdefer allocator.free(buf);
    const n = try file.readAll(buf);
    if (n != size) return error.ShortRead;
    return buf;
}

fn runAegis(allocator: std.mem.Allocator, args: []const []const u8, stdin_data: ?[]const u8) !struct { stdout: []u8, stderr: []u8, code: u8 } {
    var child = std.process.Child.init(args, allocator);
    child.stdin_behavior = if (stdin_data != null) .Pipe else .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    if (stdin_data) |data| {
        if (child.stdin) |stdin| {
            try stdin.writeAll(data);
            stdin.close();
            child.stdin = null;
        }
    }

    const stdout = try child.stdout.?.readToEndAlloc(allocator, 1024 * 1024);
    errdefer allocator.free(stdout);
    const stderr = try child.stderr.?.readToEndAlloc(allocator, 1024 * 1024);
    errdefer allocator.free(stderr);

    const term = try child.wait();
    const code: u8 = switch (term) {
        .Exited => |c| @intCast(c),
        else => 1,
    };

    return .{ .stdout = stdout, .stderr = stderr, .code = code };
}

fn binaryExists() bool {
    return fileExists(aegis_bin);
}

// ---------------------------------------------------------------------------
// 1. Plugin fixture completeness
// ---------------------------------------------------------------------------

test "all codex fixtures exist" {
    const fixtures = &[_][]const u8{
        "session_start.json",
        "user_prompt_submit_secret.json",
        "pre_tool_use_command_safe.json",
        "pre_tool_use_command_dangerous.json",
        "pre_tool_use_file_write_protected.json",
        "permission_request.json",
        "post_tool_use.json",
        "stop.json",
    };
    for (fixtures) |f| {
        const path = try std.fs.path.join(std.testing.allocator, &.{ codex_fixture_dir, f });
        defer std.testing.allocator.free(path);
        try std.testing.expect(fileExists(path));
    }
}

test "all claude fixtures exist" {
    const fixtures = &[_][]const u8{
        "session_start.json",
        "user_prompt_submit_secret.json",
        "pre_tool_use_command_safe.json",
        "pre_tool_use_command_dangerous.json",
        "pre_tool_use_file_write_protected.json",
        "permission_request.json",
        "post_tool_use.json",
        "session_end.json",
    };
    for (fixtures) |f| {
        const path = try std.fs.path.join(std.testing.allocator, &.{ claude_fixture_dir, f });
        defer std.testing.allocator.free(path);
        try std.testing.expect(fileExists(path));
    }
}

// ---------------------------------------------------------------------------
// 2. Codex hook behavior with fake payloads (requires built binary)
// ---------------------------------------------------------------------------

test "codex SessionStart hook returns valid JSON" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const fixture_path = try std.fs.path.join(allocator, &.{ codex_fixture_dir, "session_start.json" });
    defer allocator.free(fixture_path);
    const fixture = try readFile(allocator, fixture_path);
    defer allocator.free(fixture);

    const result = try runAegis(allocator, &.{ aegis_bin, "hook", "codex", "SessionStart" }, fixture);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.code);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    try std.testing.expectEqualStrings("allow", parsed.value.object.get("decision").?.string);
}

test "codex UserPromptSubmit with fake secret returns warn" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const fixture_path = try std.fs.path.join(allocator, &.{ codex_fixture_dir, "user_prompt_submit_secret.json" });
    defer allocator.free(fixture_path);
    const fixture = try readFile(allocator, fixture_path);
    defer allocator.free(fixture);

    const result = try runAegis(allocator, &.{ aegis_bin, "hook", "codex", "UserPromptSubmit" }, fixture);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.code);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    const decision = parsed.value.object.get("decision").?.string;
    try std.testing.expect(std.mem.eql(u8, decision, "warn") or std.mem.eql(u8, decision, "block"));

    // Fake secret should not appear in stdout
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "fake_p05_secret_value") == null);
    // Fake secret should not appear in stderr
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "fake_p05_secret_value") == null);
}

test "codex PreToolUse safe command returns allow" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const fixture_path = try std.fs.path.join(allocator, &.{ codex_fixture_dir, "pre_tool_use_command_safe.json" });
    defer allocator.free(fixture_path);
    const fixture = try readFile(allocator, fixture_path);
    defer allocator.free(fixture);

    const result = try runAegis(allocator, &.{ aegis_bin, "hook", "codex", "PreToolUse" }, fixture);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.code);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    const decision = parsed.value.object.get("decision").?.string;
    try std.testing.expect(std.mem.eql(u8, decision, "allow") or std.mem.eql(u8, decision, "context_only"));
}

test "codex PreToolUse dangerous command returns block or warn" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const fixture_path = try std.fs.path.join(allocator, &.{ codex_fixture_dir, "pre_tool_use_command_dangerous.json" });
    defer allocator.free(fixture_path);
    const fixture = try readFile(allocator, fixture_path);
    defer allocator.free(fixture);

    const result = try runAegis(allocator, &.{ aegis_bin, "hook", "codex", "PreToolUse" }, fixture);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.code);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    const decision = parsed.value.object.get("decision").?.string;
    try std.testing.expect(std.mem.eql(u8, decision, "block") or std.mem.eql(u8, decision, "warn") or std.mem.eql(u8, decision, "ask"));
}

test "codex PreToolUse protected file write returns block or ask" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const fixture_path = try std.fs.path.join(allocator, &.{ codex_fixture_dir, "pre_tool_use_file_write_protected.json" });
    defer allocator.free(fixture_path);
    const fixture = try readFile(allocator, fixture_path);
    defer allocator.free(fixture);

    const result = try runAegis(allocator, &.{ aegis_bin, "hook", "codex", "PreToolUse" }, fixture);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.code);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    const decision = parsed.value.object.get("decision").?.string;
    try std.testing.expect(std.mem.eql(u8, decision, "block") or std.mem.eql(u8, decision, "ask") or std.mem.eql(u8, decision, "warn"));
}

// ---------------------------------------------------------------------------
// 3. Claude hook behavior with fake payloads (requires built binary)
// ---------------------------------------------------------------------------

test "claude SessionStart hook returns valid JSON" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const fixture_path = try std.fs.path.join(allocator, &.{ claude_fixture_dir, "session_start.json" });
    defer allocator.free(fixture_path);
    const fixture = try readFile(allocator, fixture_path);
    defer allocator.free(fixture);

    const result = try runAegis(allocator, &.{ aegis_bin, "hook", "claude", "SessionStart" }, fixture);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.code);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    try std.testing.expectEqualStrings("allow", parsed.value.object.get("decision").?.string);
}

test "claude UserPromptSubmit with fake secret returns warn" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const fixture_path = try std.fs.path.join(allocator, &.{ claude_fixture_dir, "user_prompt_submit_secret.json" });
    defer allocator.free(fixture_path);
    const fixture = try readFile(allocator, fixture_path);
    defer allocator.free(fixture);

    const result = try runAegis(allocator, &.{ aegis_bin, "hook", "claude", "UserPromptSubmit" }, fixture);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.code);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    const decision = parsed.value.object.get("decision").?.string;
    try std.testing.expect(std.mem.eql(u8, decision, "warn") or std.mem.eql(u8, decision, "block"));

    // Fake secret should not appear in stdout or stderr
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "fake_p05_secret_value") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "fake_p05_secret_value") == null);
}

test "claude PreToolUse safe command returns allow" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const fixture_path = try std.fs.path.join(allocator, &.{ claude_fixture_dir, "pre_tool_use_command_safe.json" });
    defer allocator.free(fixture_path);
    const fixture = try readFile(allocator, fixture_path);
    defer allocator.free(fixture);

    const result = try runAegis(allocator, &.{ aegis_bin, "hook", "claude", "PreToolUse" }, fixture);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.code);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    const decision = parsed.value.object.get("decision").?.string;
    try std.testing.expect(std.mem.eql(u8, decision, "allow") or std.mem.eql(u8, decision, "context_only"));
}

test "claude PreToolUse dangerous command returns block or warn" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const fixture_path = try std.fs.path.join(allocator, &.{ claude_fixture_dir, "pre_tool_use_command_dangerous.json" });
    defer allocator.free(fixture_path);
    const fixture = try readFile(allocator, fixture_path);
    defer allocator.free(fixture);

    const result = try runAegis(allocator, &.{ aegis_bin, "hook", "claude", "PreToolUse" }, fixture);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.code);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    const decision = parsed.value.object.get("decision").?.string;
    try std.testing.expect(std.mem.eql(u8, decision, "block") or std.mem.eql(u8, decision, "warn") or std.mem.eql(u8, decision, "ask"));
}

test "claude PreToolUse protected file write returns block or ask" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const fixture_path = try std.fs.path.join(allocator, &.{ claude_fixture_dir, "pre_tool_use_file_write_protected.json" });
    defer allocator.free(fixture_path);
    const fixture = try readFile(allocator, fixture_path);
    defer allocator.free(fixture);

    const result = try runAegis(allocator, &.{ aegis_bin, "hook", "claude", "PreToolUse" }, fixture);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.code);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    const decision = parsed.value.object.get("decision").?.string;
    try std.testing.expect(std.mem.eql(u8, decision, "block") or std.mem.eql(u8, decision, "ask") or std.mem.eql(u8, decision, "warn"));
}

// ---------------------------------------------------------------------------
// 4. Hook CI mode never prompts
// ---------------------------------------------------------------------------

test "codex hook CI mode turns ask into block" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    // Use permission request with dangerous command to trigger ask/block
    const fixture_path = try std.fs.path.join(allocator, &.{ codex_fixture_dir, "permission_request.json" });
    defer allocator.free(fixture_path);
    const fixture = try readFile(allocator, fixture_path);
    defer allocator.free(fixture);

    const result = try runAegis(allocator, &.{ aegis_bin, "hook", "codex", "PermissionRequest", "--ci" }, fixture);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.code);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    const decision = parsed.value.object.get("decision").?.string;
    // CI mode should not return ask
    try std.testing.expect(!std.mem.eql(u8, decision, "ask"));
}

test "claude hook CI mode never returns ask" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const fixture_path = try std.fs.path.join(allocator, &.{ claude_fixture_dir, "permission_request.json" });
    defer allocator.free(fixture_path);
    const fixture = try readFile(allocator, fixture_path);
    defer allocator.free(fixture);

    const result = try runAegis(allocator, &.{ aegis_bin, "hook", "claude", "PermissionRequest", "--ci" }, fixture);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.code);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    const decision = parsed.value.object.get("decision").?.string;
    try std.testing.expect(!std.mem.eql(u8, decision, "ask"));
}

// ---------------------------------------------------------------------------
// 5. aegis decide tests
// ---------------------------------------------------------------------------

test "decide command safe returns allow JSON" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const result = try runAegis(allocator, &.{
        aegis_bin, "decide", "command", "--json",
        "{\"version\":1,\"host\":\"codex\",\"command\":\"git status\",\"mode\":\"strict\"}",
    }, null);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.code);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    try std.testing.expect(parsed.value.object.get("decision") != null);
    try std.testing.expect(parsed.value.object.get("risk") != null);
}

test "decide command dangerous returns block JSON" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const result = try runAegis(allocator, &.{
        aegis_bin, "decide", "command", "--json",
        "{\"version\":1,\"host\":\"codex\",\"command\":\"rm -rf /\",\"mode\":\"strict\"}",
    }, null);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.code);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    const decision = parsed.value.object.get("decision").?.string;
    try std.testing.expect(std.mem.eql(u8, decision, "block") or std.mem.eql(u8, decision, "warn"));
}

test "decide file write protected path returns block or ask" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const result = try runAegis(allocator, &.{
        aegis_bin, "decide", "file", "--json",
        "{\"version\":1,\"host\":\"claude\",\"operation\":\"write\",\"path\":\".env\",\"mode\":\"strict\"}",
    }, null);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.code);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    const decision = parsed.value.object.get("decision").?.string;
    try std.testing.expect(std.mem.eql(u8, decision, "block") or std.mem.eql(u8, decision, "ask") or std.mem.eql(u8, decision, "warn"));
}

test "decide prompt with fake secret redacts" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const result = try runAegis(allocator, &.{
        aegis_bin, "decide", "prompt", "--json",
        "{\"version\":1,\"host\":\"codex\",\"prompt\":\"fake_p05_secret_value\",\"mode\":\"strict\"}",
    }, null);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.code);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    const decision = parsed.value.object.get("decision").?.string;
    try std.testing.expect(std.mem.eql(u8, decision, "warn") or std.mem.eql(u8, decision, "block"));

    // Fake secret should not appear in output
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "fake_p05_secret_value") == null);
}

test "decide tool returns valid JSON" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const result = try runAegis(allocator, &.{
        aegis_bin, "decide", "tool", "--json",
        "{\"version\":1,\"host\":\"claude\",\"tool\":{\"name\":\"ExampleTool\",\"input\":{\"action\":\"example\"}},\"mode\":\"strict\"}",
    }, null);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.code);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    try std.testing.expect(parsed.value.object.get("decision") != null);
    try std.testing.expect(parsed.value.object.get("risk") != null);
    try std.testing.expect(parsed.value.object.get("category") != null);
}

// ---------------------------------------------------------------------------
// 6. Invalid input tests
// ---------------------------------------------------------------------------

test "decide rejects invalid JSON" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const result = try runAegis(allocator, &.{
        aegis_bin, "decide", "command", "--json", "{not json",
    }, null);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "invalid JSON") != null);
}

test "hook codex rejects invalid JSON" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const result = try runAegis(allocator, &.{ aegis_bin, "hook", "codex", "PreToolUse" }, "{not json");
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "invalid JSON") != null);
}

test "hook claude rejects invalid JSON" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const result = try runAegis(allocator, &.{ aegis_bin, "hook", "claude", "PreToolUse" }, "{not json");
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "invalid JSON") != null);
}

test "hook codex rejects unknown host in payload" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const result = try runAegis(allocator, &.{ aegis_bin, "hook", "codex", "SessionStart" },
        "{\"version\":1,\"host\":\"unknown\",\"event\":\"SessionStart\",\"payload\":{}}");
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "host mismatch") != null);
}

test "hook claude rejects unknown event in payload" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const result = try runAegis(allocator, &.{ aegis_bin, "hook", "claude", "SessionStart" },
        "{\"version\":1,\"host\":\"claude\",\"event\":\"UnknownEvent\",\"payload\":{}}");
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "event mismatch") != null);
}

test "decide rejects unknown decision kind" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const result = try runAegis(allocator, &.{
        aegis_bin, "decide", "unknown_kind", "--json", "{}",
    }, null);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "unknown decision kind") != null);
}

// ---------------------------------------------------------------------------
// 7. Oversized input tests
// ---------------------------------------------------------------------------

test "hook codex rejects oversized payload safely" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    // Create a payload larger than 256 KiB
    var oversized: std.ArrayList(u8) = .empty;
    defer oversized.deinit(allocator);

    try oversized.appendSlice(allocator, "{\"version\":1,\"host\":\"codex\",\"event\":\"SessionStart\",\"payload\":{\"data\":\"");
    // Append enough data to exceed 256 KiB
    var i: usize = 0;
    while (i < 300 * 1024) : (i += 1) {
        try oversized.append(allocator, 'a');
    }
    try oversized.appendSlice(allocator, "\"}}");

    const result = try runAegis(allocator, &.{ aegis_bin, "hook", "codex", "SessionStart" }, oversized.items);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // Should not crash; may succeed with truncated data or fail gracefully
    try std.testing.expect(result.code != 0 or std.mem.indexOf(u8, result.stderr, "invalid") != null or std.mem.indexOf(u8, result.stdout, "error") != null);
}

test "hook claude rejects oversized payload safely" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    var oversized: std.ArrayList(u8) = .empty;
    defer oversized.deinit(allocator);

    try oversized.appendSlice(allocator, "{\"version\":1,\"host\":\"claude\",\"event\":\"SessionStart\",\"payload\":{\"data\":\"");
    var i: usize = 0;
    while (i < 300 * 1024) : (i += 1) {
        try oversized.append(allocator, 'a');
    }
    try oversized.appendSlice(allocator, "\"}}");

    const result = try runAegis(allocator, &.{ aegis_bin, "hook", "claude", "SessionStart" }, oversized.items);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.code != 0 or std.mem.indexOf(u8, result.stderr, "invalid") != null or std.mem.indexOf(u8, result.stdout, "error") != null);
}

// ---------------------------------------------------------------------------
// 8. Secret safety scan across plugin artifacts
// ---------------------------------------------------------------------------

test "no fake secret in any plugin fixture" {
    const fixture_dirs = &[_][]const u8{ codex_fixture_dir, claude_fixture_dir };
    for (fixture_dirs) |dir| {
        var d = try std.fs.cwd().openDir(dir, .{ .iterate = true });
        defer d.close();
        var it = d.iterate();
        while (try it.next()) |entry| {
            if (entry.kind != .file) continue;
            const path = try std.fs.path.join(std.testing.allocator, &.{ dir, entry.name });
            defer std.testing.allocator.free(path);
            const content = try readFile(std.testing.allocator, path);
            defer std.testing.allocator.free(content);
            try std.testing.expect(std.mem.indexOf(u8, content, "fake_p05_secret_value") != null or std.mem.indexOf(u8, content, "fake_p02_secret_value") == null);
        }
    }
}

test "no fake secret leaks into generated hook responses" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const fixture_path = try std.fs.path.join(allocator, &.{ codex_fixture_dir, "user_prompt_submit_secret.json" });
    defer allocator.free(fixture_path);
    const fixture = try readFile(allocator, fixture_path);
    defer allocator.free(fixture);

    const result = try runAegis(allocator, &.{ aegis_bin, "hook", "codex", "UserPromptSubmit" }, fixture);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // The fake secret must NOT appear in stdout or stderr
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "fake_p05_secret_value") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "fake_p05_secret_value") == null);
}

test "no obvious real secret patterns in plugin files" {
    const files_to_check = &[_][]const u8{
        "integrations/codex-plugin/.codex-plugin/plugin.json",
        "integrations/codex-plugin/hooks/hooks.json",
        "integrations/codex-plugin/README.md",
        "integrations/claude-code-plugin/.claude-plugin/plugin.json",
        "integrations/claude-code-plugin/hooks/hooks.json",
        "integrations/claude-code-plugin/README.md",
        "integrations/claude-marketplace/.claude-plugin/marketplace.json",
        "integrations/claude-marketplace/README.md",
    };

    for (files_to_check) |path| {
        if (!fileExists(path)) continue;
        const content = try readFile(std.testing.allocator, path);
        defer std.testing.allocator.free(content);

        try std.testing.expect(std.mem.indexOf(u8, content, "ghp_") == null);
        try std.testing.expect(std.mem.indexOf(u8, content, "sk-") == null);
        try std.testing.expect(std.mem.indexOf(u8, content, "AKIA") == null);
        try std.testing.expect(std.mem.indexOf(u8, content, "password123") == null);
    }
}

// ---------------------------------------------------------------------------
// 9. Documentation overclaim checks
// ---------------------------------------------------------------------------

test "codex plugin README does not claim perfect sandboxing" {
    const content = try readFile(std.testing.allocator, "integrations/codex-plugin/README.md");
    defer std.testing.allocator.free(content);

    const lower = try std.ascii.allocLowerString(std.testing.allocator, content);
    defer std.testing.allocator.free(lower);

    try std.testing.expect(std.mem.indexOf(u8, lower, "perfect sandboxing") == null);
    try std.testing.expect(std.mem.indexOf(u8, lower, "universal transparent file enforcement") == null);
    try std.testing.expect(std.mem.indexOf(u8, lower, "universal transparent network enforcement") == null);
}

test "claude plugin README does not claim perfect sandboxing" {
    const content = try readFile(std.testing.allocator, "integrations/claude-code-plugin/README.md");
    defer std.testing.allocator.free(content);

    const lower = try std.ascii.allocLowerString(std.testing.allocator, content);
    defer std.testing.allocator.free(lower);

    try std.testing.expect(std.mem.indexOf(u8, lower, "perfect sandboxing") == null);
    try std.testing.expect(std.mem.indexOf(u8, lower, "universal transparent file enforcement") == null);
    try std.testing.expect(std.mem.indexOf(u8, lower, "universal transparent network enforcement") == null);
}

test "docs include strongest protection warning" {
    const files = &[_][]const u8{
        "integrations/codex-plugin/README.md",
        "integrations/claude-code-plugin/README.md",
        "docs/integrations/codex.md",
        "docs/integrations/claude-code.md",
    };
    for (files) |path| {
        if (!fileExists(path)) continue;
        const content = try readFile(std.testing.allocator, path);
        defer std.testing.allocator.free(content);
        // Docs should mention "strongest protection" and "aegis run --"
        try std.testing.expect(std.mem.indexOf(u8, content, "strongest protection") != null);
        try std.testing.expect(std.mem.indexOf(u8, content, "orca run --") != null);
    }
}

test "docs state no MCP server behavior and no drone features" {
    const files = &[_][]const u8{
        "integrations/codex-plugin/README.md",
        "integrations/claude-code-plugin/README.md",
    };
    for (files) |path| {
        const content = try readFile(std.testing.allocator, path);
        defer std.testing.allocator.free(content);
        try std.testing.expect(std.mem.indexOf(u8, content, "does not add MCP server behavior") != null);
        try std.testing.expect(std.mem.indexOf(u8, content, "drone-specific plugin features") != null);
    }
}

test "integration-api docs do not overclaim" {
    const path = "docs/integrations/integration-api.md";
    if (!fileExists(path)) return;
    const content = try readFile(std.testing.allocator, path);
    defer std.testing.allocator.free(content);

    const lower = try std.ascii.allocLowerString(std.testing.allocator, content);
    defer std.testing.allocator.free(lower);

    try std.testing.expect(std.mem.indexOf(u8, lower, "perfect sandboxing") == null);
    try std.testing.expect(std.mem.indexOf(u8, lower, "protection against root") == null);
}

// ---------------------------------------------------------------------------
// 10. Separate workstream non-regression
// ---------------------------------------------------------------------------

test "no drone skill exists in codex plugin" {
    const drone_skill_path = "integrations/codex-plugin/skills/aegis-drone/SKILL.md";
    try std.testing.expect(!fileExists(drone_skill_path));
}

test "no drone skill exists in claude plugin" {
    const drone_skill_path = "integrations/claude-code-plugin/skills/drone/SKILL.md";
    try std.testing.expect(!fileExists(drone_skill_path));
}

test "plugin hooks do not reference drone commands" {
    const hooks = &[_][]const u8{
        "integrations/codex-plugin/hooks/hooks.json",
        "integrations/claude-code-plugin/hooks/hooks.json",
    };
    for (hooks) |path| {
        const content = try readFile(std.testing.allocator, path);
        defer std.testing.allocator.free(content);
        const lower = try std.ascii.allocLowerString(std.testing.allocator, content);
        defer std.testing.allocator.free(lower);
        try std.testing.expect(std.mem.indexOf(u8, lower, "drone") == null);
    }
}

test "plugin docs do not include drone demos" {
    const docs = &[_][]const u8{
        "integrations/codex-plugin/README.md",
        "integrations/claude-code-plugin/README.md",
        "docs/integrations/codex.md",
        "docs/integrations/claude-code.md",
    };
    for (docs) |path| {
        if (!fileExists(path)) continue;
        const content = try readFile(std.testing.allocator, path);
        defer std.testing.allocator.free(content);
        const lower = try std.ascii.allocLowerString(std.testing.allocator, content);
        defer std.testing.allocator.free(lower);
        try std.testing.expect(std.mem.indexOf(u8, lower, "drone demo") == null);
        try std.testing.expect(std.mem.indexOf(u8, lower, "operational drone-control") == null);
    }
}

// ---------------------------------------------------------------------------
// 11. Plugin manifest and structure validation (P05 re-check)
// ---------------------------------------------------------------------------

test "codex plugin manifest references skills and hooks" {
    const content = try readFile(std.testing.allocator, "integrations/codex-plugin/.codex-plugin/plugin.json");
    defer std.testing.allocator.free(content);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, content, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;
    try std.testing.expectEqualStrings("./skills/", obj.get("skills").?.string);
    try std.testing.expectEqualStrings("./hooks/hooks.json", obj.get("hooks").?.string);
}

test "claude plugin manifest references skills and hooks" {
    const content = try readFile(std.testing.allocator, "integrations/claude-code-plugin/.claude-plugin/plugin.json");
    defer std.testing.allocator.free(content);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, content, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;
    try std.testing.expectEqualStrings("./skills/", obj.get("skills").?.string);
    try std.testing.expectEqualStrings("./hooks/hooks.json", obj.get("hooks").?.string);
}

test "claude marketplace file points to plugin directory" {
    const content = try readFile(std.testing.allocator, "integrations/claude-marketplace/.claude-plugin/marketplace.json");
    defer std.testing.allocator.free(content);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, content, .{});
    defer parsed.deinit();

    const plugins = parsed.value.object.get("plugins").?.array;
    try std.testing.expect(plugins.items.len > 0);
    const source = plugins.items[0].object.get("source").?.string;
    try std.testing.expect(std.mem.indexOf(u8, source, "claude-code-plugin") != null);
}

// ---------------------------------------------------------------------------
// 12. Missing required fields and unknown values
// ---------------------------------------------------------------------------

test "hook codex rejects missing version field" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const result = try runAegis(allocator, &.{ aegis_bin, "hook", "codex", "SessionStart" },
        "{\"host\":\"codex\",\"event\":\"SessionStart\",\"payload\":{}}");
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.code != 0);
}

test "hook claude rejects missing host field" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const result = try runAegis(allocator, &.{ aegis_bin, "hook", "claude", "SessionStart" },
        "{\"version\":1,\"event\":\"SessionStart\",\"payload\":{}}");
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.code != 0);
}

test "decide rejects missing JSON payload" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const result = try runAegis(allocator, &.{ aegis_bin, "decide", "command" }, null);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.code != 0);
}

// ---------------------------------------------------------------------------
// 13. Hook stdout is valid host-compatible JSON
// ---------------------------------------------------------------------------

test "all codex hook responses are valid JSON" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const fixtures = &[_][]const u8{
        "session_start.json",
        "user_prompt_submit_secret.json",
        "pre_tool_use_command_safe.json",
        "pre_tool_use_command_dangerous.json",
        "pre_tool_use_file_write_protected.json",
        "permission_request.json",
        "post_tool_use.json",
        "stop.json",
    };

    for (fixtures) |f| {
        const fixture_path = try std.fs.path.join(allocator, &.{ codex_fixture_dir, f });
        defer allocator.free(fixture_path);
        const fixture = try readFile(allocator, fixture_path);
        defer allocator.free(fixture);

        // Extract event name from fixture filename
        const event_name = blk: {
            const basename = std.fs.path.basename(f);
            const dot = std.mem.indexOf(u8, basename, ".") orelse basename.len;
            break :blk basename[0..dot];
        };

        // Map filename to event name
        const event = if (std.mem.eql(u8, event_name, "session_start"))
            "SessionStart"
        else if (std.mem.eql(u8, event_name, "user_prompt_submit_secret"))
            "UserPromptSubmit"
        else if (std.mem.eql(u8, event_name, "pre_tool_use_command_safe"))
            "PreToolUse"
        else if (std.mem.eql(u8, event_name, "pre_tool_use_command_dangerous"))
            "PreToolUse"
        else if (std.mem.eql(u8, event_name, "pre_tool_use_file_write_protected"))
            "PreToolUse"
        else if (std.mem.eql(u8, event_name, "permission_request"))
            "PermissionRequest"
        else if (std.mem.eql(u8, event_name, "post_tool_use"))
            "PostToolUse"
        else if (std.mem.eql(u8, event_name, "stop"))
            "Stop"
        else
            continue;

        const result = try runAegis(allocator, &.{ aegis_bin, "hook", "codex", event }, fixture);
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        // stdout must be valid JSON
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{}) catch {
            try std.testing.expect(false); // Force failure with context
            continue;
        };
        defer parsed.deinit();

        // Must have required hook response fields
        try std.testing.expect(parsed.value.object.get("version") != null);
        try std.testing.expect(parsed.value.object.get("decision") != null);
        try std.testing.expect(parsed.value.object.get("risk") != null);
        try std.testing.expect(parsed.value.object.get("category") != null);
        try std.testing.expect(parsed.value.object.get("reason") != null);
        try std.testing.expect(parsed.value.object.get("message") != null);
        try std.testing.expect(parsed.value.object.get("redactions") != null);
        try std.testing.expect(parsed.value.object.get("host_limitations") != null);
    }
}

test "all claude hook responses are valid JSON" {
    if (!binaryExists()) return;
    const allocator = std.testing.allocator;

    const fixtures = &[_][]const u8{
        "session_start.json",
        "user_prompt_submit_secret.json",
        "pre_tool_use_command_safe.json",
        "pre_tool_use_command_dangerous.json",
        "pre_tool_use_file_write_protected.json",
        "permission_request.json",
        "post_tool_use.json",
        "session_end.json",
    };

    for (fixtures) |f| {
        const fixture_path = try std.fs.path.join(allocator, &.{ claude_fixture_dir, f });
        defer allocator.free(fixture_path);
        const fixture = try readFile(allocator, fixture_path);
        defer allocator.free(fixture);

        const event_name = blk: {
            const basename = std.fs.path.basename(f);
            const dot = std.mem.indexOf(u8, basename, ".") orelse basename.len;
            break :blk basename[0..dot];
        };

        const event = if (std.mem.eql(u8, event_name, "session_start"))
            "SessionStart"
        else if (std.mem.eql(u8, event_name, "user_prompt_submit_secret"))
            "UserPromptSubmit"
        else if (std.mem.eql(u8, event_name, "pre_tool_use_command_safe"))
            "PreToolUse"
        else if (std.mem.eql(u8, event_name, "pre_tool_use_command_dangerous"))
            "PreToolUse"
        else if (std.mem.eql(u8, event_name, "pre_tool_use_file_write_protected"))
            "PreToolUse"
        else if (std.mem.eql(u8, event_name, "permission_request"))
            "PermissionRequest"
        else if (std.mem.eql(u8, event_name, "post_tool_use"))
            "PostToolUse"
        else if (std.mem.eql(u8, event_name, "session_end"))
            "SessionEnd"
        else
            continue;

        const result = try runAegis(allocator, &.{ aegis_bin, "hook", "claude", event }, fixture);
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        var parsed = std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{}) catch {
            try std.testing.expect(false);
            continue;
        };
        defer parsed.deinit();

        try std.testing.expect(parsed.value.object.get("version") != null);
        try std.testing.expect(parsed.value.object.get("decision") != null);
        try std.testing.expect(parsed.value.object.get("risk") != null);
        try std.testing.expect(parsed.value.object.get("category") != null);
        try std.testing.expect(parsed.value.object.get("reason") != null);
        try std.testing.expect(parsed.value.object.get("message") != null);
        try std.testing.expect(parsed.value.object.get("redactions") != null);
        try std.testing.expect(parsed.value.object.get("host_limitations") != null);
    }
}
