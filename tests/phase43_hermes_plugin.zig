const std = @import("std");

const plugin_dir = "integrations/hermes-plugin";
const manifest_path = plugin_dir ++ "/plugin.yaml";
const source_path = plugin_dir ++ "/__init__.py";
const readme_path = plugin_dir ++ "/README.md";
const fixture_dir = "tests/plugin-fixtures/hermes";

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const stat = try file.stat();
    if (stat.size > 1024 * 1024) return error.FileTooLarge;
    const buf = try allocator.alloc(u8, @intCast(stat.size));
    errdefer allocator.free(buf);
    const n = try file.readAll(buf);
    if (n != stat.size) return error.ShortRead;
    return buf;
}

test "hermes plugin manifest exists and names orca" {
    try std.testing.expect(fileExists(manifest_path));
    const content = try readFile(std.testing.allocator, manifest_path);
    defer std.testing.allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "name: orca") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "entrypoint: __init__.py") != null);
}

test "hermes plugin source exists and calls orca hook hermes" {
    try std.testing.expect(fileExists(source_path));
    const content = try readFile(std.testing.allocator, source_path);
    defer std.testing.allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "\"hook\", \"hermes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "ctx.register_hook") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pre_tool_call") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pre_llm_call") != null);
}

test "hermes plugin source does not duplicate policy logic or store secrets" {
    const content = try readFile(std.testing.allocator, source_path);
    defer std.testing.allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "rm -rf") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "allowlist") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "denylist") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "YOUR_API_KEY") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "password123") == null);
}

test "hermes plugin readme documents install and limits" {
    try std.testing.expect(fileExists(readme_path));
    const content = try readFile(std.testing.allocator, readme_path);
    defer std.testing.allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "install-orca-plugin.sh hermes") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pre_gateway_dispatch") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "orca run -- hermes") != null);
}

test "all hermes fixtures exist" {
    const fixtures = &[_][]const u8{
        "on_session_start.json",
        "pre_tool_call_command_safe.json",
        "pre_tool_call_command_dangerous.json",
        "pre_tool_call_file_write_protected.json",
        "pre_llm_call.json",
        "post_llm_call.json",
        "on_session_end.json",
        "subagent_stop.json",
    };

    for (fixtures) |fixture| {
        const path = try std.fs.path.join(std.testing.allocator, &.{ fixture_dir, fixture });
        defer std.testing.allocator.free(path);
        try std.testing.expect(fileExists(path));
    }
}

test "hermes fixtures are valid JSON with hermes host" {
    const fixtures = &[_][]const u8{
        "on_session_start.json",
        "pre_tool_call_command_safe.json",
        "pre_tool_call_command_dangerous.json",
        "pre_tool_call_file_write_protected.json",
        "pre_llm_call.json",
        "post_llm_call.json",
        "on_session_end.json",
        "subagent_stop.json",
    };

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    for (fixtures) |fixture| {
        const path = try std.fs.path.join(allocator, &.{ fixture_dir, fixture });
        defer allocator.free(path);

        const content = try readFile(allocator, path);
        defer allocator.free(content);

        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
        defer parsed.deinit();

        try std.testing.expectEqual(@as(i64, 1), parsed.value.object.get("version").?.integer);
        try std.testing.expectEqualStrings("hermes", parsed.value.object.get("host").?.string);
    }
}

test "hermes fixtures do not contain real secrets" {
    const fixtures = &[_][]const u8{
        "on_session_start.json",
        "pre_tool_call_command_safe.json",
        "pre_tool_call_command_dangerous.json",
        "pre_tool_call_file_write_protected.json",
        "pre_llm_call.json",
        "post_llm_call.json",
        "on_session_end.json",
        "subagent_stop.json",
    };

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    for (fixtures) |fixture| {
        const path = try std.fs.path.join(allocator, &.{ fixture_dir, fixture });
        defer allocator.free(path);

        const content = try readFile(allocator, path);
        defer allocator.free(content);

        try std.testing.expect(std.mem.indexOf(u8, content, "ghp_") == null);
        try std.testing.expect(std.mem.indexOf(u8, content, "sk-") == null);
        try std.testing.expect(std.mem.indexOf(u8, content, "password123") == null);
    }
}
