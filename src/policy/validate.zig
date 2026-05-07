const std = @import("std");

const core = @import("../core/mod.zig");
const schema = @import("schema.zig");

pub fn policy(value: *const schema.Policy) !void {
    if (value.version_value != schema.version) return error.UnsupportedPolicyVersion;
    try validateString("workspace.root", value.workspace.root, core.limits.max_path_len);
    try validateEnv(value.env);
    try validateRuleSet("files.read", value.files.read, core.limits.max_path_len);
    try validateRuleSet("files.write", value.files.write, core.limits.max_path_len);
    try validateRuleSet("commands", value.commands, core.limits.max_command_len);
    try validateNetwork(value.network);
    try validateRuleSet("mcp", value.mcp, core.limits.max_event_field_len);
}

fn validateEnv(env: schema.EnvPolicy) !void {
    for (env.allow) |name| try validatePatternString("env.allow", name, core.limits.max_env_name_len);
    for (env.deny_patterns) |pattern| try validatePatternString("env.deny_patterns", pattern, core.limits.max_env_name_len);
    for (env.ask) |pattern| try validatePatternString("env.ask", pattern, core.limits.max_env_name_len);
}

fn validateRuleSet(label: []const u8, rules: schema.RuleSet, max_len: usize) !void {
    for (rules.allow) |rule| try validatePatternString(label, rule, max_len);
    for (rules.deny) |rule| try validatePatternString(label, rule, max_len);
    for (rules.ask) |rule| try validatePatternString(label, rule, max_len);
}

fn validateNetwork(network: schema.NetworkPolicy) !void {
    for (network.allow) |rule| try validatePatternString("network.allow", rule, core.limits.max_url_len);
    for (network.deny) |rule| try validatePatternString("network.deny", rule, core.limits.max_url_len);
    for (network.ask) |rule| try validatePatternString("network.ask", rule, core.limits.max_url_len);
}

fn validateString(_: []const u8, value: []const u8, max_len: usize) !void {
    if (value.len == 0 or value.len > max_len) return error.InvalidPolicy;
    if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidPolicy;
    if (std.mem.indexOfScalar(u8, value, 0) != null) return error.InvalidPolicy;
}

fn validatePatternString(label: []const u8, value: []const u8, max_len: usize) !void {
    try validateString(label, value, max_len);
    for (value) |char| {
        if (char < 0x20) return error.InvalidPolicy;
    }
}

test "built-in presets validate" {
    const load = @import("load.zig");

    var observe = try load.loadPreset(std.testing.allocator, .observe);
    defer observe.deinit();
    try policy(&observe);

    var ask = try load.loadPreset(std.testing.allocator, .ask);
    defer ask.deinit();
    try policy(&ask);

    var strict = try load.loadPreset(std.testing.allocator, .strict);
    defer strict.deinit();
    try policy(&strict);

    var ci = try load.loadPreset(std.testing.allocator, .ci);
    defer ci.deinit();
    try policy(&ci);

    for (@import("presets.zig").agent_preset_infos) |info| {
        var agent_preset = try load.loadAgentPreset(std.testing.allocator, info.preset);
        defer agent_preset.deinit();
        try policy(&agent_preset);
    }
}

test "policy patterns with unsafe control characters are rejected" {
    const load = @import("load.zig");
    const bad = "version: 1\nmode: strict\nfiles:\n  read:\n    deny:\n      - \"./bad\x1bpath\"\n";
    try std.testing.expectError(error.InvalidPolicy, load.parseFromSlice(std.testing.allocator, bad, "bad.yaml"));
}

test "literal bracketed policy paths validate and match literally" {
    const load = @import("load.zig");
    const matchers = @import("matchers.zig");
    var loaded = try load.parseFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: strict
        \\files:
        \\  read:
        \\    allow:
        \\      - "./src/routes/[id]/+page.svelte"
        \\      - "./docs/[draft].md"
    , "brackets.yaml");
    defer loaded.deinit();

    try std.testing.expectEqualStrings("./src/routes/[id]/+page.svelte", loaded.files.read.allow[0]);
    try std.testing.expect(matchers.matchesPath(loaded.files.read.allow[0], "./src/routes/[id]/+page.svelte"));
    try std.testing.expect(matchers.matchesPath(loaded.files.read.allow[1], "./docs/[draft].md"));
}

test "all policy preset files under policies/presets validate" {
    const load = @import("load.zig");
    var dir = try std.fs.cwd().openDir("policies/presets", .{ .iterate = true });
    defer dir.close();
    var count: usize = 0;
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".yaml")) continue;
        const path = try std.fs.path.join(std.testing.allocator, &.{ "policies/presets", entry.name });
        defer std.testing.allocator.free(path);
        var loaded = try load.loadFile(std.testing.allocator, path);
        defer loaded.deinit();
        try policy(&loaded);
        count += 1;
    }
    try std.testing.expect(count >= 10);
}
