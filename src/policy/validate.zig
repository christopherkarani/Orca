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
    for (env.allow) |name| try validateString("env.allow", name, core.limits.max_env_name_len);
    for (env.deny_patterns) |pattern| try validateString("env.deny_patterns", pattern, core.limits.max_env_name_len);
    for (env.ask) |pattern| try validateString("env.ask", pattern, core.limits.max_env_name_len);
}

fn validateRuleSet(label: []const u8, rules: schema.RuleSet, max_len: usize) !void {
    for (rules.allow) |rule| try validateString(label, rule, max_len);
    for (rules.deny) |rule| try validateString(label, rule, max_len);
    for (rules.ask) |rule| try validateString(label, rule, max_len);
}

fn validateNetwork(network: schema.NetworkPolicy) !void {
    for (network.allow) |rule| try validateString("network.allow", rule, core.limits.max_url_len);
    for (network.deny) |rule| try validateString("network.deny", rule, core.limits.max_url_len);
    for (network.ask) |rule| try validateString("network.ask", rule, core.limits.max_url_len);
}

fn validateString(_: []const u8, value: []const u8, max_len: usize) !void {
    if (value.len == 0 or value.len > max_len) return error.InvalidPolicy;
    if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidPolicy;
    if (std.mem.indexOfScalar(u8, value, 0) != null) return error.InvalidPolicy;
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
