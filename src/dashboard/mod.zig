const std = @import("std");
const build_options = @import("build_options");

const core_api = @import("aegis_core").api;
const core = @import("aegis_core").core;
const policy_mod = @import("aegis_core").policy;
const supervisor = @import("../core/supervisor.zig");
const license_mod = @import("../license.zig");
const ci_check = @import("../ci_check.zig");

pub const max_request_body_len = 1024 * 1024;

pub const PolicySaveResult = struct {
    ok: bool,
    error_name: ?[]const u8 = null,
};

pub fn resolveWorkspaceRoot(allocator: std.mem.Allocator) ![]u8 {
    return supervisor.resolveWorkspaceRoot(allocator, null, ".") catch try std.fs.cwd().realpathAlloc(allocator, ".");
}

pub fn writeStatusJson(allocator: std.mem.Allocator, writer: anytype, workspace_root: []const u8) !void {
    try writer.writeByte('{');
    try writer.writeAll("\"orca\":{");
    try writer.writeAll("\"installed\":true,\"version\":");
    try core.util.writeJsonString(writer, build_options.version);
    try writer.writeAll(",\"workspace_root\":");
    try core.util.writeJsonString(writer, workspace_root);
    try writer.writeAll("},\"policy\":");
    try writePolicySummaryJson(allocator, writer, workspace_root);
    try writer.writeAll(",\"license\":");
    try writeLicenseJson(allocator, writer);
    try writer.writeAll(",\"ci_readiness\":");
    try writeCiReadinessJson(allocator, writer, workspace_root);
    try writer.writeAll(",\"plugins\":[");
    try writePluginCardJson(allocator, writer, workspace_root, "openclaw", "OpenClaw", "openclaw", "integrations/openclaw-plugin", "orca plugin doctor openclaw");
    try writer.writeByte(',');
    try writePluginCardJson(allocator, writer, workspace_root, "hermes", "Hermes", "hermes", "integrations/hermes-plugin", "orca plugin doctor hermes");
    try writer.writeAll("],\"sessions\":");
    try writeSessionsArrayJson(allocator, writer, workspace_root, 6);
    try writer.writeAll(",\"blocked_actions\":");
    try writeBlockedActionsArrayJson(allocator, writer, workspace_root, 8);
    try writer.writeAll(",\"quick_actions\":[");
    try writeQuickAction(writer, "doctor", "orca doctor");
    try writer.writeByte(',');
    try writeQuickAction(writer, "policy-check", "orca policy check .orca/policy.yaml");
    try writer.writeByte(',');
    try writeQuickAction(writer, "openclaw-doctor", "orca plugin doctor openclaw");
    try writer.writeByte(',');
    try writeQuickAction(writer, "hermes-doctor", "orca plugin doctor hermes");
    try writer.writeByte(',');
    try writeQuickAction(writer, "replay-denied", "orca replay --session last --only denied --verify");
    try writer.writeByte(',');
    try writeQuickAction(writer, "report-last", "orca report --session last --format markdown");
    try writer.writeByte(',');
    try writeQuickAction(writer, "ci-check", "orca ci check --format markdown");
    try writer.writeByte(',');
    try writeQuickAction(writer, "demo-blocked-action", "orca demo blocked-action");
    try writer.writeByte(',');
    try writeQuickAction(writer, "license-status", "orca license status");
    try writer.writeAll("]}");
}

pub fn writePolicyJson(allocator: std.mem.Allocator, writer: anytype, workspace_root: []const u8) !void {
    try writer.writeByte('{');
    try writer.writeAll("\"summary\":");
    try writePolicySummaryJson(allocator, writer, workspace_root);
    try writer.writeAll(",\"presets\":[");
    for (policy_mod.presets.agent_preset_infos, 0..) |info, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try writer.writeAll("\"name\":");
        try core.util.writeJsonString(writer, info.name);
        try writer.writeAll(",\"experimental\":");
        try writer.writeAll(if (info.experimental) "true" else "false");
        try writer.writeAll(",\"warning\":");
        try core.util.writeJsonString(writer, info.warning);
        try writer.writeByte('}');
    }
    try writer.writeAll("],\"text\":");
    const policy_path = try policyPath(allocator, workspace_root);
    defer allocator.free(policy_path);
    if (readFileIfExists(allocator, policy_path, core.limits.max_policy_file_len + 1)) |text| {
        defer allocator.free(text);
        try core.util.writeJsonString(writer, text);
    } else |_| {
        try writer.writeAll("null");
    }
    try writer.writeByte('}');
}

pub fn savePolicyText(allocator: std.mem.Allocator, workspace_root: []const u8, text: []const u8) !PolicySaveResult {
    if (text.len > core.limits.max_policy_file_len) return .{ .ok = false, .error_name = "PolicyFileTooLarge" };
    var parsed = core_api.parsePolicyFromSlice(allocator, text, ".orca/policy.yaml") catch |err| {
        return .{ .ok = false, .error_name = @errorName(err) };
    };
    defer parsed.deinit();
    core_api.validatePolicy(&parsed) catch |err| {
        return .{ .ok = false, .error_name = @errorName(err) };
    };

    const orca_dir = try std.fs.path.join(allocator, &.{ workspace_root, ".orca" });
    defer allocator.free(orca_dir);
    try std.fs.cwd().makePath(orca_dir);
    const path = try policyPath(allocator, workspace_root);
    defer allocator.free(path);
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(text);
    try file.sync();
    return .{ .ok = true };
}

pub fn initPolicyFromPreset(allocator: std.mem.Allocator, workspace_root: []const u8, preset_name: []const u8, force: bool) !PolicySaveResult {
    const preset = policy_mod.presets.AgentPreset.parse(preset_name) orelse return .{ .ok = false, .error_name = "UnsupportedPreset" };
    const path = try policyPath(allocator, workspace_root);
    defer allocator.free(path);
    if (!force and fileExistsAbsolute(path)) return .{ .ok = false, .error_name = "PolicyAlreadyExists" };
    return savePolicyText(allocator, workspace_root, policy_mod.presets.agentPresetText(preset));
}

pub fn writeSessionsJson(allocator: std.mem.Allocator, writer: anytype, workspace_root: []const u8) !void {
    try writer.writeByte('{');
    try writer.writeAll("\"sessions\":");
    try writeSessionsArrayJson(allocator, writer, workspace_root, 20);
    try writer.writeAll(",\"blocked_actions\":");
    try writeBlockedActionsArrayJson(allocator, writer, workspace_root, 50);
    try writer.writeByte('}');
}

fn writePolicySummaryJson(allocator: std.mem.Allocator, writer: anytype, workspace_root: []const u8) !void {
    const path = try policyPath(allocator, workspace_root);
    defer allocator.free(path);
    try writer.writeByte('{');
    try writer.writeAll("\"path\":\".orca/policy.yaml\",");
    if (!fileExistsAbsolute(path)) {
        try writer.writeAll("\"exists\":false,\"valid\":false,\"mode\":null,\"error\":null");
        try writer.writeByte('}');
        return;
    }
    try writer.writeAll("\"exists\":true,");
    if (core_api.loadPolicyFile(allocator, path)) |loaded_policy| {
        var loaded = loaded_policy;
        defer loaded.deinit();
        try writer.writeAll("\"valid\":true,\"mode\":");
        try core.util.writeJsonString(writer, loaded.mode.toString());
        try writer.writeAll(",\"error\":null");
    } else |err| {
        if (err == error.OutOfMemory) return err;
        try writer.writeAll("\"valid\":false,\"mode\":null,\"error\":");
        try core.util.writeJsonString(writer, @errorName(err));
    }
    try writer.writeByte('}');
}

fn writeLicenseJson(allocator: std.mem.Allocator, writer: anytype) !void {
    var current = license_mod.status(allocator) catch |err| switch (err) {
        error.InvalidLicense, error.InvalidLicenseSignature, error.UnsupportedLicenseIssuer, error.UnsupportedLicenseTier => {
            try writer.writeAll("{\"tier\":\"Free\",\"verified\":false,\"error\":");
            try core.util.writeJsonString(writer, @errorName(err));
            try writer.writeByte('}');
            return;
        },
        else => return err,
    };
    defer current.deinit();
    try writer.writeByte('{');
    try writer.writeAll("\"tier\":");
    try core.util.writeJsonString(writer, current.tier.label());
    try writer.writeAll(",\"verified\":");
    try writer.writeAll(if (current.verified) "true" else "false");
    try writer.writeAll(",\"report_export\":");
    try writer.writeAll(if (current.tier.allows(.report_export)) "true" else "false");
    try writer.writeAll(",\"error\":null}");
}

fn writeCiReadinessJson(allocator: std.mem.Allocator, writer: anytype, workspace_root: []const u8) !void {
    var result = ci_check.run(allocator, workspace_root) catch |err| {
        try writer.writeAll("{\"ok\":false,\"error\":");
        try core.util.writeJsonString(writer, @errorName(err));
        try writer.writeAll(",\"checks\":[]}");
        return;
    };
    defer result.deinit();
    try writer.writeByte('{');
    try writer.writeAll("\"ok\":");
    try writer.writeAll(if (result.ok()) "true" else "false");
    try writer.writeAll(",\"error\":null,\"checks\":[");
    for (result.checks.items, 0..) |check, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.writeAll("{\"name\":");
        try core.util.writeJsonString(writer, check.name);
        try writer.writeAll(",\"status\":");
        try core.util.writeJsonString(writer, @tagName(check.status));
        try writer.writeAll(",\"message\":");
        try core.util.writeJsonString(writer, check.message);
        try writer.writeByte('}');
    }
    try writer.writeAll("]}");
}

fn writePluginCardJson(
    allocator: std.mem.Allocator,
    writer: anytype,
    workspace_root: []const u8,
    id: []const u8,
    label: []const u8,
    binary_name: []const u8,
    integration_path: []const u8,
    doctor_command: []const u8,
) !void {
    const integration_abs = try std.fs.path.join(allocator, &.{ workspace_root, integration_path });
    defer allocator.free(integration_abs);
    const host_found = try executableInPath(allocator, binary_name);
    const integration_present = pathExistsAbsolute(integration_abs);
    try writer.writeByte('{');
    try writer.writeAll("\"id\":");
    try core.util.writeJsonString(writer, id);
    try writer.writeAll(",\"label\":");
    try core.util.writeJsonString(writer, label);
    try writer.writeAll(",\"host_detected\":");
    try writer.writeAll(if (host_found) "true" else "false");
    try writer.writeAll(",\"integration_present\":");
    try writer.writeAll(if (integration_present) "true" else "false");
    try writer.writeAll(",\"doctor_command\":");
    try core.util.writeJsonString(writer, doctor_command);
    try writer.writeAll(",\"setup_commands\":[");
    if (std.mem.eql(u8, id, "openclaw")) {
        try writeStringArray(writer, &.{
            "orca init --preset generic-agent",
            "openclaw plugins install clawhub:orca-openclaw-plugin",
            "orca plugin doctor openclaw",
            "orca run -- openclaw",
        });
    } else {
        try writeStringArray(writer, &.{
            "orca init --preset generic-agent",
            "orca plugin install hermes --yes",
            "hermes plugins enable orca",
            "orca plugin doctor hermes",
            "orca run -- hermes",
        });
    }
    try writer.writeAll("]}");
}

fn writeQuickAction(writer: anytype, id: []const u8, command: []const u8) !void {
    try writer.writeByte('{');
    try writer.writeAll("\"id\":");
    try core.util.writeJsonString(writer, id);
    try writer.writeAll(",\"command\":");
    try core.util.writeJsonString(writer, command);
    try writer.writeByte('}');
}

fn writeSessionsArrayJson(allocator: std.mem.Allocator, writer: anytype, workspace_root: []const u8, max_count: usize) !void {
    const sessions_root = try std.fs.path.join(allocator, &.{ workspace_root, ".orca", "sessions" });
    defer allocator.free(sessions_root);
    var dir = std.fs.cwd().openDir(sessions_root, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => {
            try writer.writeAll("[]");
            return;
        },
        else => return err,
    };
    defer dir.close();

    try writer.writeByte('[');
    var it = dir.iterate();
    var count: usize = 0;
    while (count < max_count) {
        const entry = try it.next() orelse break;
        if (entry.kind != .directory) continue;
        if (core.session.validateSessionIdText(entry.name)) |_| {} else |_| continue;
        if (count > 0) try writer.writeByte(',');
        try writeSessionSummaryJson(allocator, writer, workspace_root, entry.name);
        count += 1;
    }
    try writer.writeByte(']');
}

fn writeSessionSummaryJson(allocator: std.mem.Allocator, writer: anytype, workspace_root: []const u8, session_id: []const u8) !void {
    try writer.writeByte('{');
    try writer.writeAll("\"id\":");
    try core.util.writeJsonString(writer, session_id);
    if (core_api.loadReplay(allocator, workspace_root, .{ .session = session_id, .only_denied = true, .verify = false })) |loaded_replay| {
        var replay = loaded_replay;
        defer replay.deinit();
        try writer.writeAll(",\"command\":");
        try core.util.writeJsonString(writer, replay.command_display);
        try writer.writeAll(",\"policy\":");
        try core.util.writeJsonString(writer, replay.policy);
        try writer.writeAll(",\"status\":");
        try core.util.writeJsonString(writer, replay.status_display);
        try writer.print(",\"denied_count\":{d},\"verified\":{}", .{ replay.events.len, replay.verified });
    } else |err| {
        if (err == error.OutOfMemory) return err;
        try writer.writeAll(",\"command\":null,\"policy\":null,\"status\":\"unreadable\",\"denied_count\":0,\"verified\":false,\"error\":");
        try core.util.writeJsonString(writer, @errorName(err));
    }
    try writer.writeByte('}');
}

fn writeBlockedActionsArrayJson(allocator: std.mem.Allocator, writer: anytype, workspace_root: []const u8, max_count: usize) !void {
    const sessions_root = try std.fs.path.join(allocator, &.{ workspace_root, ".orca", "sessions" });
    defer allocator.free(sessions_root);
    var dir = std.fs.cwd().openDir(sessions_root, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => {
            try writer.writeAll("[]");
            return;
        },
        else => return err,
    };
    defer dir.close();

    try writer.writeByte('[');
    var written: usize = 0;
    var it = dir.iterate();
    while (written < max_count) {
        const entry = try it.next() orelse break;
        if (entry.kind != .directory) continue;
        if (core.session.validateSessionIdText(entry.name)) |_| {} else |_| continue;
        var replay = core_api.loadReplay(allocator, workspace_root, .{ .session = entry.name, .only_denied = true, .verify = false }) catch continue;
        defer replay.deinit();
        for (replay.events) |ev| {
            if (written >= max_count) break;
            if (written > 0) try writer.writeByte(',');
            try writeBlockedActionJson(allocator, writer, replay.session_id, replay.verified, ev);
            written += 1;
        }
    }
    try writer.writeByte(']');
}

fn writeBlockedActionJson(allocator: std.mem.Allocator, writer: anytype, session_id: []const u8, verified: bool, ev: anytype) !void {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, ev.raw, .{}) catch null;
    defer if (parsed) |*p| p.deinit();
    try writer.writeByte('{');
    try writer.writeAll("\"session_id\":");
    try core.util.writeJsonString(writer, session_id);
    try writer.writeAll(",\"timestamp\":");
    try core.util.writeJsonString(writer, ev.timestamp);
    try writer.writeAll(",\"event_type\":");
    try core.util.writeJsonString(writer, ev.event_type);
    try writer.writeAll(",\"target\":");
    try core.util.writeJsonString(writer, ev.target_value);
    try writer.writeAll(",\"decision\":");
    if (ev.decision_result) |result| try core.util.writeJsonString(writer, result) else try writer.writeAll("null");
    try writer.writeAll(",\"verified\":");
    try writer.writeAll(if (verified) "true" else "false");
    try writer.writeAll(",\"rule\":");
    try writeDecisionField(writer, parsed, "rule_id");
    try writer.writeAll(",\"reason\":");
    try writeDecisionField(writer, parsed, "reason");
    try writer.writeAll(",\"raw\":");
    try writer.writeAll(ev.raw);
    try writer.writeByte('}');
}

fn writeDecisionField(writer: anytype, parsed: ?std.json.Parsed(std.json.Value), field: []const u8) !void {
    const value = if (parsed) |p| blk: {
        if (p.value != .object) break :blk null;
        const decision = p.value.object.get("decision") orelse break :blk null;
        if (decision != .object) break :blk null;
        const raw = decision.object.get(field) orelse break :blk null;
        if (raw != .string) break :blk null;
        break :blk raw.string;
    } else null;
    if (value) |text| try core.util.writeJsonString(writer, text) else try writer.writeAll("null");
}

fn writeStringArray(writer: anytype, values: []const []const u8) !void {
    for (values, 0..) |value, index| {
        if (index > 0) try writer.writeByte(',');
        try core.util.writeJsonString(writer, value);
    }
}

fn policyPath(allocator: std.mem.Allocator, workspace_root: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ workspace_root, ".orca", "policy.yaml" });
}

fn fileExistsAbsolute(path: []const u8) bool {
    const file = std.fs.cwd().openFile(path, .{}) catch return false;
    file.close();
    return true;
}

fn pathExistsAbsolute(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn readFileIfExists(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
    return std.fs.cwd().readFileAlloc(allocator, path, max_bytes);
}

fn executableInPath(allocator: std.mem.Allocator, name: []const u8) !bool {
    const path = std.process.getEnvVarOwned(allocator, "PATH") catch return false;
    defer allocator.free(path);
    const separator: u8 = if (@import("builtin").os.tag == .windows) ';' else ':';
    var parts = std.mem.splitScalar(u8, path, separator);
    while (parts.next()) |part| {
        if (part.len == 0) continue;
        const candidate = try std.fs.path.join(allocator, &.{ part, name });
        defer allocator.free(candidate);
        if (fileExistsAbsolute(candidate)) return true;
    }
    return false;
}

test "policy save validates before writing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    const bad = try savePolicyText(std.testing.allocator, root, "version: 1\nmode: strict\ncommands: allow\n");
    try std.testing.expect(!bad.ok);
    try std.testing.expectEqualStrings("InvalidPolicy", bad.error_name.?);
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(".orca/policy.yaml", .{}));

    const ok = try savePolicyText(std.testing.allocator, root, policy_mod.presets.agentPresetText(.generic_agent));
    try std.testing.expect(ok.ok);
    try tmp.dir.access(".orca/policy.yaml", .{});
}

test "init policy refuses overwrite unless forced" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    const first = try initPolicyFromPreset(std.testing.allocator, root, "generic-agent", false);
    try std.testing.expect(first.ok);
    const second = try initPolicyFromPreset(std.testing.allocator, root, "strict-local", false);
    try std.testing.expect(!second.ok);
    try std.testing.expectEqualStrings("PolicyAlreadyExists", second.error_name.?);
    const forced = try initPolicyFromPreset(std.testing.allocator, root, "strict-local", true);
    try std.testing.expect(forced.ok);
}

test "status json includes policy and protected agent cards" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    _ = try initPolicyFromPreset(std.testing.allocator, root, "generic-agent", false);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);
    try writeStatusJson(std.testing.allocator, out.writer(std.testing.allocator), root);

    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"policy\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"openclaw\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"hermes\"") != null);
}

test "sessions json filters denied replay events" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    try writeDeniedReplayFixture(std.testing.allocator, root);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);
    try writeSessionsJson(std.testing.allocator, out.writer(std.testing.allocator), root);

    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"blocked_actions\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "rm -rf tmp") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"decision\":\"deny\"") != null);
}

fn writeDeniedReplayFixture(allocator: std.mem.Allocator, root: []const u8) !void {
    const timestamp = core.time.Timestamp.fromUnixSeconds(1_777_983_130);
    var session = core.session.Session{
        .id = try core.session.generateSessionId(timestamp),
        .started_at = timestamp,
        .ended_at = timestamp,
        .command = "orca",
        .args = &.{ "run", "--", "rm", "-rf", "tmp" },
        .workspace_root = root,
        .mode = .strict,
        .platform = core.platform.detectOs(),
    };
    var writer = try core_api.createAuditWriter(allocator, session);
    defer writer.deinit();
    const event = try core_api.createAuditEvent(.{
        .session_id = session.id,
        .event_id = try core.event.generateEventId(timestamp),
        .timestamp = timestamp,
        .event_type = .command_denied,
        .actor = .{ .kind = .orca, .display = "orca" },
        .target = .{ .kind = .command, .value = "rm -rf tmp" },
        .decision = core_api.makeDecision(.{ .result = .deny, .reason = "blocked by test policy" }),
    });
    try core_api.appendAuditEvent(&writer, event);
    try writer.writeLastPointer();
    try core_api.writeAuditSummary(allocator, writer.sessionDirPath(), .{
        .session = session,
        .status = .{ .exited = 1 },
        .event_count = writer.event_count,
        .final_event_hash = writer.finalHash().?,
        .policy = ".orca/policy.yaml",
        .product_label = "Orca",
    });
    _ = &session;
}
