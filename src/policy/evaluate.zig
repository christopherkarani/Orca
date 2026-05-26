const std = @import("std");

const core = @import("../core/mod.zig");
const network_guard = @import("network_eval.zig");
const matchers = @import("matchers.zig");
const schema = @import("schema.zig");

const Surface = enum {
    file_read,
    file_write,
    env,
    command,
    network,
    mcp,
};

pub fn action(policy: *const schema.Policy, requested: core.types.Action, ctx: schema.EvaluationContext, allocator: std.mem.Allocator) !schema.Evaluation {
    const mode = ctx.mode orelse policy.mode;
    return switch (requested) {
        .file_read => |file| evaluateRuleSet(allocator, mode, .file_read, "files.read", policy.files.read, file.path.raw),
        .file_write => |file| evaluateRuleSet(allocator, mode, .file_write, "files.write", policy.files.write, file.path.raw),
        .env_read => |env_action| evaluateEnv(allocator, mode, policy.env, env_action.name),
        .command_exec => |command_action| {
            const display = try commandDisplay(allocator, command_action.argv);
            defer allocator.free(display);
            return evaluateRuleSet(allocator, mode, .command, "commands", policy.commands, display);
        },
        .network_connect => |network_action| {
            const destination_text = try networkDestinationText(allocator, network_action);
            defer allocator.free(destination_text);
            var network_decision = try network_guard.evaluate(allocator, policy, mode, destination_text, .{ .ci_mode = mode == .ci });
            defer network_decision.deinit(allocator);
            const owned_rule_id = if (network_decision.decision.rule_id) |rule_id| try allocator.dupe(u8, rule_id) else null;
            errdefer if (owned_rule_id) |rule_id| allocator.free(rule_id);
            const explanation = try allocator.dupe(u8, network_decision.decision.reason);
            errdefer allocator.free(explanation);
            return .{
                .decision = .{
                    .result = network_decision.decision.result,
                    .rule_id = owned_rule_id,
                    .reason = explanation,
                    .risk_score = network_decision.decision.risk_score,
                    .requires_user = network_decision.decision.requires_user,
                    .ci_may_proceed = network_decision.decision.ci_may_proceed,
                },
                .matched_rule = if (network_decision.matched_rule) |rule| .{ .id = owned_rule_id.?, .pattern = rule.pattern } else null,
                .explanation = explanation,
                .owned_rule_id = owned_rule_id,
            };
        },
        .mcp_tool_call => |tool| {
            const selector = try mcpSelector(allocator, tool.server, tool.tool_name);
            defer allocator.free(selector);
            return evaluateRuleSet(allocator, mode, .mcp, "mcp", policy.mcp, selector);
        },
        .mcp_resource_read => |resource| {
            const selector = try mcpSelector(allocator, resource.server, resource.uri);
            defer allocator.free(selector);
            return evaluateRuleSet(allocator, mode, .mcp, "mcp", policy.mcp, selector);
        },
        .mcp_prompt_get => |prompt| {
            const selector = try mcpSelector(allocator, prompt.server, prompt.prompt_name);
            defer allocator.free(selector);
            return evaluateRuleSet(allocator, mode, .mcp, "mcp", policy.mcp, selector);
        },
        .mcp_sampling_request => |sampling| {
            const selector = try mcpSelector(allocator, sampling.server, sampling.model orelse "sampling");
            defer allocator.free(selector);
            return evaluateRuleSet(allocator, mode, .mcp, "mcp", policy.mcp, selector);
        },
        .edge_vehicle_state_read,
        .edge_vehicle_command_request,
        .edge_mission_upload_request,
        .edge_geofence_evaluation_request,
        .edge_telemetry_egress_request,
        .edge_emergency_command_request,
        .edge_safety_envelope_evaluation_request,
        => edgePlaceholderDecision(allocator, mode, edgeActionName(requested), edgeActionTarget(requested)),
        .approval_decision, .staging_decision => defaultDecision(allocator, mode, null, "unsupported policy action surface"),
    };
}

pub fn fileRead(policy: *const schema.Policy, path: []const u8, allocator: std.mem.Allocator) !schema.Evaluation {
    return action(policy, .{ .file_read = .{ .path = try core.types.Path.init(path) } }, .{}, allocator);
}

pub fn fileWrite(policy: *const schema.Policy, path: []const u8, allocator: std.mem.Allocator) !schema.Evaluation {
    return action(policy, .{ .file_write = .{ .path = try core.types.Path.init(path) } }, .{}, allocator);
}

pub fn env(policy: *const schema.Policy, name: []const u8, allocator: std.mem.Allocator) !schema.Evaluation {
    return action(policy, .{ .env_read = .{ .name = name } }, .{}, allocator);
}

pub fn command(policy: *const schema.Policy, command_text: []const u8, allocator: std.mem.Allocator) !schema.Evaluation {
    return evaluateRuleSet(allocator, policy.mode, .command, "commands", policy.commands, command_text);
}

pub fn network(policy: *const schema.Policy, host: []const u8, allocator: std.mem.Allocator) !schema.Evaluation {
    return action(policy, .{ .network_connect = .{ .host = host } }, .{}, allocator);
}

pub fn mcp(policy: *const schema.Policy, selector: []const u8, allocator: std.mem.Allocator) !schema.Evaluation {
    return evaluateRuleSet(allocator, policy.mode, .mcp, "mcp", policy.mcp, selector);
}

fn evaluateEnv(allocator: std.mem.Allocator, mode: schema.Mode, env_policy: schema.EnvPolicy, name: []const u8) !schema.Evaluation {
    if (findMatch(.env, env_policy.deny_patterns, name)) |match| return explicit(allocator, mode, .deny, "env.deny_patterns", match.index, match.pattern);
    if (findMatch(.env, env_policy.allow, name)) |match| return explicit(allocator, mode, .allow, "env.allow", match.index, match.pattern);
    if (findMatch(.env, env_policy.ask, name)) |match| return explicit(allocator, mode, .ask, "env.ask", match.index, match.pattern);
    if (riskHeuristic(.env, name)) |risk| return riskDecision(allocator, mode, risk);
    if (env_policy.default) |default| return defaultDecision(allocator, mode, default, "env.default");
    return defaultDecision(allocator, mode, null, "mode default");
}

fn evaluateRuleSet(
    allocator: std.mem.Allocator,
    mode: schema.Mode,
    surface: Surface,
    label: []const u8,
    rules: schema.RuleSet,
    value: []const u8,
) !schema.Evaluation {
    if (findMatch(surface, rules.deny, value)) |match| return explicit(allocator, mode, .deny, try std.fmt.allocPrint(allocator, "{s}.deny", .{label}), match.index, match.pattern);
    if (findMatch(surface, rules.allow, value)) |match| return explicit(allocator, mode, .allow, try std.fmt.allocPrint(allocator, "{s}.allow", .{label}), match.index, match.pattern);
    if (findMatch(surface, rules.ask, value)) |match| return explicit(allocator, mode, .ask, try std.fmt.allocPrint(allocator, "{s}.ask", .{label}), match.index, match.pattern);
    if (riskHeuristic(surface, value)) |risk| return riskDecision(allocator, mode, risk);
    if (rules.default) |default| {
        const default_label = try std.fmt.allocPrint(allocator, "{s}.default", .{label});
        defer allocator.free(default_label);
        return defaultDecision(allocator, mode, default, default_label);
    }
    return defaultDecision(allocator, mode, null, "mode default");
}

const Match = struct {
    index: usize,
    pattern: []const u8,
};

fn findMatch(surface: Surface, rules: []const []const u8, value: []const u8) ?Match {
    for (rules, 0..) |pattern, index| {
        const matched = switch (surface) {
            .file_read, .file_write => matchers.matchesPath(pattern, value),
            .env => matchers.matchesPattern(pattern, value),
            .command => matchers.matchesCommand(pattern, value),
            .network => matchers.matchesDomain(pattern, value),
            .mcp => matchers.matchesMcpSelector(pattern, value),
        };
        if (matched) return .{ .index = index, .pattern = pattern };
    }
    return null;
}

fn explicit(
    allocator: std.mem.Allocator,
    mode: schema.Mode,
    decision_value: schema.DecisionValue,
    label: []const u8,
    index: usize,
    pattern: []const u8,
) !schema.Evaluation {
    defer if (std.mem.indexOfScalar(u8, label, '.') != null and !std.mem.startsWith(u8, label, "env.")) allocator.free(label);
    var actual_decision = decision_value;
    if (mode == .ci and decision_value == .ask) {
        actual_decision = .deny;
    }
    const rule_id = try std.fmt.allocPrint(allocator, "{s}[{d}]", .{ label, index });
    errdefer allocator.free(rule_id);
    const explanation = try std.fmt.allocPrint(allocator, "matched {s} rule \"{s}\"", .{ label, pattern });
    return .{
        .decision = .{
            .result = actual_decision.toDecisionResult(),
            .rule_id = rule_id,
            .reason = explanation,
            .requires_user = actual_decision == .ask,
            .ci_may_proceed = actual_decision == .allow or actual_decision == .observe,
        },
        .matched_rule = .{ .id = rule_id, .pattern = pattern },
        .explanation = explanation,
        .owned_rule_id = rule_id,
    };
}

fn riskDecision(allocator: std.mem.Allocator, mode: schema.Mode, risk: Risk) !schema.Evaluation {
    const result: schema.DecisionValue = switch (mode) {
        .observe => .observe,
        .trusted, .ask => .ask,
        .strict, .ci, .redteam => .deny,
    };
    const explanation = try std.fmt.allocPrint(allocator, "risk heuristic: {s}", .{risk.reason});
    return .{
        .decision = .{
            .result = result.toDecisionResult(),
            .reason = explanation,
            .risk_score = risk.score,
            .requires_user = result == .ask,
            .ci_may_proceed = result == .allow or result == .observe,
        },
        .explanation = explanation,
    };
}

fn defaultDecision(allocator: std.mem.Allocator, mode: schema.Mode, explicit_default: ?schema.DecisionValue, label: []const u8) !schema.Evaluation {
    const value = explicit_default orelse modeDefault(mode);
    const actual = if (mode == .ci and value == .ask) schema.DecisionValue.deny else value;
    const explanation = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ label, if (mode == .ci and value == .ask) "ask converted to deny in ci mode" else actual.toString() });
    return .{
        .decision = .{
            .result = actual.toDecisionResult(),
            .reason = explanation,
            .requires_user = actual == .ask,
            .ci_may_proceed = actual == .allow or actual == .observe,
        },
        .explanation = explanation,
    };
}

fn edgePlaceholderDecision(allocator: std.mem.Allocator, mode: schema.Mode, action_name: []const u8, target: []const u8) !schema.Evaluation {
    _ = mode;
    const explanation = try std.fmt.allocPrint(
        allocator,
        "edge.{s}: generic Core placeholder for {s}; use Aegis Edge Phase 27 policy evaluation for domain safety decisions; no real drone command enforcement",
        .{ action_name, target },
    );
    return .{
        .decision = .{
            .result = .observe,
            .reason = explanation,
            .ci_may_proceed = true,
        },
        .explanation = explanation,
    };
}

fn edgeActionName(requested: core.types.Action) []const u8 {
    return switch (requested) {
        .edge_vehicle_state_read => "vehicle_state_read",
        .edge_vehicle_command_request => "vehicle_command_request",
        .edge_mission_upload_request => "mission_upload_request",
        .edge_geofence_evaluation_request => "geofence_evaluation_request",
        .edge_telemetry_egress_request => "telemetry_egress_request",
        .edge_emergency_command_request => "emergency_command_request",
        .edge_safety_envelope_evaluation_request => "safety_envelope_evaluation_request",
        else => "unknown",
    };
}

fn edgeActionTarget(requested: core.types.Action) []const u8 {
    return switch (requested) {
        .edge_vehicle_state_read => |action_value| action_value.vehicle_id,
        .edge_vehicle_command_request => |action_value| action_value.vehicle_id,
        .edge_mission_upload_request => |action_value| action_value.vehicle_id,
        .edge_geofence_evaluation_request => |action_value| action_value.vehicle_id,
        .edge_telemetry_egress_request => |action_value| action_value.vehicle_id,
        .edge_emergency_command_request => |action_value| action_value.vehicle_id,
        .edge_safety_envelope_evaluation_request => |action_value| action_value.vehicle_id,
        else => "edge-placeholder",
    };
}

fn modeDefault(mode: schema.Mode) schema.DecisionValue {
    return switch (mode) {
        .observe => .observe,
        .ask, .trusted => .ask,
        .strict, .ci, .redteam => .deny,
    };
}

const Risk = struct {
    score: u8,
    reason: []const u8,
};

fn riskHeuristic(surface: Surface, value: []const u8) ?Risk {
    return switch (surface) {
        .file_read => if (matchers.matchesPath("~/.ssh/**", value) or matchers.matchesPath("~/.aws/**", value) or matchers.matchesPath("./.env*", value)) .{ .score = 90, .reason = "sensitive file path" } else null,
        .file_write => if (matchers.matchesPath("./.git/**", value) or matchers.matchesPath("./.aegis/**", value)) .{ .score = 80, .reason = "control directory write" } else null,
        .env => if (isSecretLikeEnvName(value)) .{ .score = 90, .reason = "secret-like environment variable" } else null,
        .command => commandRiskHeuristic(value),
        .network => if (std.mem.indexOf(u8, value, "localhost") != null or std.mem.startsWith(u8, value, "127.")) .{ .score = 40, .reason = "local network destination" } else null,
        .mcp => null,
    };
}

fn commandRiskHeuristic(value: []const u8) ?Risk {
    if (matchers.matchesCommand("rm -rf *", value) or
        matchers.matchesCommand("find * -delete", value) or
        matchers.matchesCommand("shred *", value) or
        matchers.matchesCommand("sudo *", value) or
        matchers.matchesCommand("su *", value) or
        matchers.matchesCommand("doas *", value) or
        matchers.matchesCommand("cat .env", value) or
        matchers.matchesCommand("cat ~/.ssh/*", value) or
        containsIgnoreCase(value, "powershell -encodedcommand") or
        containsIgnoreCase(value, "powershell -enc") or
        containsIgnoreCase(value, "base64 -d | sh") or
        containsIgnoreCase(value, "base64 -d | bash"))
    {
        return .{ .score = 95, .reason = "high-risk command pattern" };
    }
    if ((containsIgnoreCase(value, "curl") or containsIgnoreCase(value, "wget")) and
        (containsIgnoreCase(value, "| sh") or containsIgnoreCase(value, "| bash")))
    {
        return .{ .score = 90, .reason = "network script command pattern" };
    }
    if (matchers.matchesCommand("git push --force*", value)) return .{ .score = 95, .reason = "force git remote write" };
    if (matchers.matchesCommand("git push*", value)) return .{ .score = 80, .reason = "git remote write" };
    if (matchers.matchesCommand("npm install*", value) or matchers.matchesCommand("pip install*", value)) return .{ .score = 70, .reason = "package install command" };
    return null;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    return std.ascii.indexOfIgnoreCase(haystack, needle) != null;
}

fn isSecretLikeEnvName(value: []const u8) bool {
    const patterns = [_][]const u8{
        "*TOKEN*",
        "*SECRET*",
        "*PASSWORD*",
        "*PASSWD*",
        "*PRIVATE*",
        "*KEY*",
        "AWS_*",
        "AZURE_*",
        "GITHUB_TOKEN",
        "GH_TOKEN",
        "OPENAI_API_KEY",
        "ANTHROPIC_API_KEY",
        "GOOGLE_API_KEY",
        "GOOGLE_APPLICATION_CREDENTIALS",
        "NPM_TOKEN",
        "PYPI_TOKEN",
        "SSH_AUTH_SOCK",
    };
    for (patterns) |pattern| {
        if (matchers.matchesPattern(pattern, value)) return true;
    }
    return false;
}

fn commandDisplay(allocator: std.mem.Allocator, argv: []const []const u8) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    for (argv, 0..) |arg, index| {
        if (index > 0) try list.append(allocator, ' ');
        try list.appendSlice(allocator, arg);
    }
    return try list.toOwnedSlice(allocator);
}

fn mcpSelector(allocator: std.mem.Allocator, server: ?[]const u8, name: []const u8) ![]u8 {
    if (server) |server_name| return std.fmt.allocPrint(allocator, "{s}.{s}", .{ server_name, name });
    return allocator.dupe(u8, name);
}

fn networkDestinationText(allocator: std.mem.Allocator, network_action: core.types.NetworkAction) ![]u8 {
    const host = network_action.host;
    const host_for_port = if (std.mem.indexOfScalar(u8, host, ':') != null and !(std.mem.startsWith(u8, host, "[") and std.mem.endsWith(u8, host, "]")))
        try std.fmt.allocPrint(allocator, "[{s}]", .{host})
    else
        try allocator.dupe(u8, host);
    defer allocator.free(host_for_port);

    if (network_action.scheme) |scheme| {
        if (network_action.port) |port| return std.fmt.allocPrint(allocator, "{s}://{s}:{d}", .{ scheme, host_for_port, port });
        return std.fmt.allocPrint(allocator, "{s}://{s}", .{ scheme, host_for_port });
    }
    if (network_action.port) |port| return std.fmt.allocPrint(allocator, "{s}:{d}", .{ host_for_port, port });
    return allocator.dupe(u8, host);
}

test "deny priority beats allow for file paths" {
    const load = @import("load.zig");
    var policy = try load.parseFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: strict
        \\files:
        \\  read:
        \\    allow:
        \\      - "./**"
        \\    deny:
        \\      - "./.env"
    , "test.yaml");
    defer policy.deinit();

    const result = try fileRead(&policy, "./.env", std.testing.allocator);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, result.decision.result);
    try std.testing.expectEqualStrings("files.read.deny[0]", result.matched_rule.?.id);
}

test "rule matching covers env command network and mcp" {
    const load = @import("load.zig");
    var policy = try load.loadPreset(std.testing.allocator, .strict);
    defer policy.deinit();

    var env_result = try env(&policy, "GITHUB_TOKEN", std.testing.allocator);
    defer env_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, env_result.decision.result);

    var command_result = try command(&policy, "rm -rf /", std.testing.allocator);
    defer command_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, command_result.decision.result);

    var network_result = try network(&policy, "api.github.com", std.testing.allocator);
    defer network_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.allow, network_result.decision.result);

    var mcp_result = try mcp(&policy, "filesystem.run_command", std.testing.allocator);
    defer mcp_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, mcp_result.decision.result);
}

test "network action evaluation preserves scheme and port" {
    const load = @import("load.zig");
    var policy = try load.parseFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: strict
        \\network:
        \\  mode: allowlist
        \\  allow:
        \\    - "api.github.com:443"
    , "network-port.yaml");
    defer policy.deinit();

    const result = try action(&policy, .{ .network_connect = .{
        .host = "api.github.com",
        .port = 443,
        .scheme = "https",
    } }, .{}, std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(core.decision.DecisionResult.allow, result.decision.result);
    try std.testing.expectEqualStrings("network.allow[0]", result.matched_rule.?.id);
}

test "ci mode converts ask to deny without prompting" {
    const load = @import("load.zig");
    var policy = try load.parseFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: ci
        \\commands:
        \\  default: ask
    , "ci.yaml");
    defer policy.deinit();

    const result = try command(&policy, "git status", std.testing.allocator);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, result.decision.result);
    try std.testing.expect(!result.decision.requires_user);
    try std.testing.expect(!result.decision.ci_may_proceed);
}
