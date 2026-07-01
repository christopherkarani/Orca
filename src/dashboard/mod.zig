const std = @import("std");
const build_options = @import("build_options");

const aggregate = @import("aggregate.zig");
const core_api = @import("orca_core").api;
const core = @import("orca_core").core;
const policy_mod = @import("orca_core").policy;
const credentials_runtime = @import("../intercept/credentials.zig");
const supervisor = core.supervisor;
const license_mod = @import("../license.zig");
const ci_check = @import("../ci_check.zig");
const rust_visibility = @import("../cli/rust_visibility.zig");
const feed_writer = @import("../cli/feed_writer.zig");

pub const max_request_body_len = 1024 * 1024;

pub const PolicySaveResult = struct {
    ok: bool,
    error_name: ?[]const u8 = null,
};

pub fn resolveWorkspaceRoot(io: std.Io, allocator: std.mem.Allocator) ![]u8 {
    return resolveWorkspaceRootFrom(io, allocator, ".");
}

pub fn resolveWorkspaceRootFrom(io: std.Io, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return supervisor.resolveWorkspaceRoot(io, allocator, null, path) catch try std.Io.Dir.cwd().realPathFileAlloc(io, path, allocator);
}

pub fn writeStatusJson(io: std.Io, allocator: std.mem.Allocator, writer: anytype, workspace_root: []const u8) !void {
    try writer.writeByte('{');
    try writer.writeAll("\"mode\":\"workspace\",\"workspace_count\":1,\"workspaces\":[{\"root\":");
    try core.util.writeJsonString(writer, workspace_root);
    try writer.writeAll("}],\"orca\":{");
    try writer.writeAll("\"installed\":true,\"version\":");
    try core.util.writeJsonString(writer, build_options.version);
    try writer.writeAll(",\"workspace_root\":");
    try core.util.writeJsonString(writer, workspace_root);
    try writer.writeAll("},\"policy\":");
    try writePolicySummaryJson(io, allocator, writer, workspace_root);
    try writer.writeAll(",\"secretless_runtime\":");
    try writeSecretlessRuntimeJson(io, allocator, writer, workspace_root);
    try writer.writeAll(",\"license\":");
    try writeLicenseJson(io, allocator, writer);
    try writer.writeAll(",\"ci_readiness\":");
    try writeCiReadinessJson(io, allocator, writer, workspace_root);
    try writer.writeAll(",\"plugins\":[");
    try writePluginCardJson(io, allocator, writer, workspace_root, "openclaw", "OpenClaw", "openclaw", "integrations/openclaw-plugin", "orca plugin doctor openclaw");
    try writer.writeByte(',');
    try writePluginCardJson(io, allocator, writer, workspace_root, "hermes", "Hermes", "hermes", "integrations/hermes-plugin", "orca plugin doctor hermes");
    try writer.writeAll("],\"sessions\":");
    try writeSessionsArrayJson(io, allocator, writer, workspace_root, 6);
    try writer.writeAll(",\"daemon_health\":");
    try writeDaemonHealthJson(allocator, writer);
    try writer.writeAll(",\"rust_shell_decisions\":");
    try writeRustShellDecisionsArrayJson(io, allocator, writer, workspace_root, 12);
    try writer.writeAll(",\"blocked_actions\":");
    try writeBlockedActionsArrayJson(io, allocator, writer, workspace_root, 8);
    try writer.writeAll(",\"quick_actions\":[");
    try writeQuickAction(writer, "doctor", "orca doctor");
    try writer.writeByte(',');
    try writeQuickAction(writer, "policy-check", "orca policy check .orca/policy.yaml");
    try writer.writeByte(',');
    try writeQuickAction(writer, "credentials-check", "orca credentials check");
    try writer.writeByte(',');
    try writeQuickAction(writer, "credentials-check-github", "orca credentials check github_pat");
    try writer.writeByte(',');
    try writeQuickAction(writer, "proxy-smoke", "orca run --secretless --network-backend proxy -- /usr/bin/env");
    try writer.writeByte(',');
    try writeQuickAction(writer, "policy-explain-github", "orca policy explain network https://api.github.com/repos/acme/app/issues --method POST");
    try writer.writeByte(',');
    try writeQuickAction(writer, "replay-last", "orca replay --session last --verify");
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

pub fn writeMachineStatusJson(
    io: std.Io,
    allocator: std.mem.Allocator,
    writer: anytype,
    dashboard_root: []const u8,
) !void {
    const workspaces = try aggregate.loadWorkspaces(io, allocator, dashboard_root);
    defer aggregate.deinitWorkspaces(allocator, workspaces);

    try writer.writeAll("{\"mode\":\"machine\",\"workspace_count\":");
    try writer.print("{d}", .{workspaces.len});
    try writer.writeAll(",\"workspaces\":");
    try aggregate.writeWorkspacesJson(writer, workspaces);
    try writer.writeAll(",\"orca\":{\"installed\":true,\"version\":");
    try core.util.writeJsonString(writer, build_options.version);
    try writer.writeAll(",\"workspace_root\":null},\"policy\":null,\"secretless_runtime\":null,\"license\":");
    try writeLicenseJson(io, allocator, writer);
    try writer.writeAll(",\"ci_readiness\":null,\"plugins\":[],\"sessions\":");
    try aggregate.writeSessionsJson(io, allocator, writer, workspaces, 20);
    try writer.writeAll(",\"daemon_health\":");
    try writeDaemonHealthJson(allocator, writer);
    try writer.writeAll(",\"rust_shell_decisions\":");
    try aggregate.writeGlobalFeedJson(io, allocator, writer, dashboard_root, 50, false);
    try writer.writeAll(",\"blocked_actions\":");
    try aggregate.writeGlobalFeedJson(io, allocator, writer, dashboard_root, 50, true);
    try writer.writeAll(",\"quick_actions\":[");
    try writeQuickAction(writer, "doctor", "orca doctor");
    try writer.writeByte(',');
    try writeQuickAction(writer, "license-status", "orca license status");
    try writer.writeAll("]}");
}

fn writeSecretlessRuntimeJson(io: std.Io, allocator: std.mem.Allocator, writer: anytype, workspace_root: []const u8) !void {
    const policy_path = try policyPath(allocator, workspace_root);
    defer allocator.free(policy_path);
    var loaded_policy: ?policy_mod.schema.Policy = null;
    var loaded_policy_handle: ?policy_mod.schema.LoadedPolicy = null;
    if (policy_mod.load.discover(io, allocator, policy_path, workspace_root)) |loaded| {
        loaded_policy_handle = loaded;
        loaded_policy = loaded.policy;
    } else |_| {}
    defer if (loaded_policy_handle) |*handle| handle.deinit();

    const active_broker_label = if (loaded_policy) |loaded|
        loaded.credentials.default_broker orelse if (loaded.credentials.brokers.len > 0) loaded.credentials.brokers[0].name else "local-dummy"
    else
        "local-dummy";
    const active_broker_kind = if (loaded_policy) |loaded|
        if (findBrokerKind(loaded.credentials, active_broker_label)) |kind| kind.toString() else "local-dummy"
    else
        "local-dummy";
    const proxy_backend = if (loaded_policy) |loaded| loaded.network.effectiveBackend() else .decision_only;
    const service_policy_template =
        \\credentials:
        \\  default_broker: onepassword
        \\  brokers:
        \\    onepassword:
        \\      type: 1password-cli
        \\      account: my-team
        \\    env_dev:
        \\      type: env-file-dev
        \\      path: .orca/dev-secrets.env
        \\  refs:
        \\    github_pat:
        \\      broker: onepassword
        \\      ref: "op://Engineering/GitHub PAT/token"
        \\
        \\network:
        \\  mode: allowlist
        \\  backend: proxy
        \\
        \\services:
        \\  github:
        \\    hosts:
        \\      - "api.github.com"
        \\    methods:
        \\      - "GET"
        \\      - "POST"
        \\    paths:
        \\      allow:
        \\        - "/repos/*/issues"
        \\        - "/repos/*/pulls"
        \\      deny:
        \\        - "/user/keys"
        \\        - "/orgs/*/secrets/*"
        \\    credentials:
        \\      use: github_pat
        \\    unmatched: deny
    ;
    try writer.writeAll(
        \\{"available":true,"active_broker":{"id":
    );
    try core.util.writeJsonString(writer, active_broker_label);
    try writer.writeAll(",\"label\":");
    try core.util.writeJsonString(writer, active_broker_label);
    try writer.writeAll(",\"kind\":");
    try core.util.writeJsonString(writer, active_broker_kind);
    try writer.writeAll(",\"status\":\"configured\",\"stores_raw_secrets\":false,\"injects_raw_credentials\":false,\"description\":\"Configured broker for Secretless credential references.\"},\"credential_refs\":");
    try writeCredentialRefsJson(writer, loaded_policy);
    try writer.writeAll(",\"broker_checks\":");
    try writeBrokerChecksJson(io, allocator, writer, workspace_root, loaded_policy);
    try writer.writeAll(",\"recent_audit_events\":");
    try writeRecentSecretlessAuditEventsJson(io, allocator, writer, workspace_root, 12);
    try writer.writeAll(",\"proxy_backend\":{");
    try writer.writeAll("\"status\":");
    try core.util.writeJsonString(writer, if (proxy_backend == .proxy) "limited" else "unavailable");
    try writer.writeAll(",\"bind\":");
    try core.util.writeJsonString(writer, if (proxy_backend == .proxy) "127.0.0.1:<allocated-per-run>" else "");
    try writer.writeAll(",\"https_visibility\":\"host-port-only\",\"method_path_visibility\":\"http-and-cooperative-hooks\",\"backend\":");
    try core.util.writeJsonString(writer, proxy_backend.toString());
    try writer.writeAll("},\"supported_brokers\":[{\"id\":\"local-dummy\",\"label\":\"Local dummy broker\",\"status\":\"available\",\"stores_raw_secrets\":false,\"notes\":\"Built in. Emits non-secret orca-secret:// references for local verification.\"},{\"id\":\"env-file-dev\",\"label\":\"Env-file dev broker\",\"status\":\"available\",\"stores_raw_secrets\":false,\"notes\":\"Local development only. Reads .orca/dev-secrets.env at runtime and never writes raw values to audit.\"},{\"id\":\"1password-cli\",\"label\":\"1Password CLI\",\"status\":\"available-when-op-installed\",\"stores_raw_secrets\":false,\"notes\":\"Runs op read without shell interpolation and discards resolved values after checks.\"},{\"id\":\"macos-keychain\",\"label\":\"macOS Keychain\",\"status\":\"available-on-macos\",\"stores_raw_secrets\":false,\"notes\":\"Uses /usr/bin/security find-generic-password for configured refs.\"},{\"id\":\"infisical-agent-vault\",\"label\":\"Infisical / Agent Vault\",\"status\":\"status-boundary\",\"stores_raw_secrets\":false,\"notes\":\"Configured as an extension boundary; resolution remains disabled until exact local API or CLI behavior is verified.\"}],\"capabilities\":[{\"label\":\"Env replacement\",\"state\":\"active\",\"detail\":\"orca run --secretless strips raw secret-like env values from the child and substitutes broker references.\"},{\"label\":\"Broker checks\",\"state\":\"active\",\"detail\":\"orca credentials check verifies broker config and refs without printing raw secret values.\"},{\"label\":\"Service policy\",\"state\":\"active\",\"detail\":\"services: rules support hosts, methods, allow/deny paths, credential references, unmatched behavior, and port-scoped hosts.\"},{\"label\":\"Proxy backend\",\"state\":\"limited\",\"detail\":\"orca run --network-backend proxy injects a loopback proxy. HTTPS CONNECT enforcement is host/port only without MITM.\"},{\"label\":\"Transparent OS interception\",\"state\":\"unavailable\",\"detail\":\"Orca does not claim OS-level transparent network interception.\"}],\"guarantees\":[\"Child processes launched with --secretless do not receive raw secret-like environment values that Orca detects.\",\"Broker references and checks never print or persist raw resolved secret values.\",\"Orca remains the runtime policy and audit layer; external brokers own secret storage.\"],\"limitations\":[\"Secretless mode only protects processes launched through orca run --secretless.\",\"HTTPS path and method enforcement is unavailable in proxy mode without MITM or cooperative metadata.\",\"Infisical/Agent Vault resolution is not enabled until its local contract is verified.\"],\"run_command\":\"orca run --secretless --network-backend proxy -- <agent-command>\",\"verify_commands\":[\"orca credentials check\",\"orca credentials check github_pat\",\"orca policy check .orca/policy.yaml\",\"orca policy explain network https://api.github.com/repos/acme/app/issues --method POST\",\"orca run --secretless --network-backend proxy -- /usr/bin/env\",\"orca replay --session last --verify\"],\"service_policy_template\":");
    try core.util.writeJsonString(writer, service_policy_template);
    try writer.writeByte('}');
}

fn findBrokerKind(credentials: policy_mod.schema.CredentialsPolicy, name: []const u8) ?policy_mod.schema.CredentialBrokerKind {
    for (credentials.brokers) |broker| {
        if (std.ascii.eqlIgnoreCase(broker.name, name)) return broker.kind;
    }
    return null;
}

fn writeCredentialRefsJson(writer: anytype, maybe_policy: ?policy_mod.schema.Policy) !void {
    try writer.writeByte('[');
    if (maybe_policy) |loaded| {
        for (loaded.credentials.refs, 0..) |credential_ref, index| {
            if (index > 0) try writer.writeByte(',');
            try writer.writeAll("{\"name\":");
            try core.util.writeJsonString(writer, credential_ref.name);
            try writer.writeAll(",\"broker\":");
            if (credential_ref.broker) |broker| try core.util.writeJsonString(writer, broker) else try writer.writeAll("null");
            try writer.writeAll(",\"ref\":");
            try core.util.writeJsonString(writer, credential_ref.ref);
            try writer.writeAll(",\"raw_value\":null}");
        }
    }
    try writer.writeByte(']');
}

fn writeBrokerChecksJson(io: std.Io, allocator: std.mem.Allocator, writer: anytype, workspace_root: []const u8, maybe_policy: ?policy_mod.schema.Policy) !void {
    if (maybe_policy) |loaded| {
        var report = credentials_runtime.check(io, allocator, &loaded, workspace_root, null) catch {
            try writer.writeAll("[]");
            return;
        };
        defer report.deinit(allocator);
        try writer.writeByte('[');
        for (report.statuses, 0..) |status, index| {
            if (index > 0) try writer.writeByte(',');
            try writer.writeAll("{\"broker\":");
            try core.util.writeJsonString(writer, status.name);
            try writer.writeAll(",\"kind\":");
            try core.util.writeJsonString(writer, status.kind.toString());
            try writer.writeAll(",\"status\":");
            try core.util.writeJsonString(writer, status.state.toString());
            try writer.writeAll(",\"message\":");
            try core.util.writeJsonString(writer, status.message);
            try writer.writeByte('}');
        }
        try writer.writeByte(']');
        return;
    }
    try writer.writeAll("[{\"broker\":\"local-dummy\",\"kind\":\"local-dummy\",\"status\":\"available\",\"message\":\"built-in reference broker available\"}]");
}

pub fn writePolicyJson(io: std.Io, allocator: std.mem.Allocator, writer: anytype, workspace_root: []const u8) !void {
    try writer.writeByte('{');
    try writer.writeAll("\"summary\":");
    try writePolicySummaryJson(io, allocator, writer, workspace_root);
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
    if (readFileIfExists(io, allocator, policy_path, core.limits.max_policy_file_len + 1)) |text| {
        defer allocator.free(text);
        try core.util.writeJsonString(writer, text);
    } else |_| {
        try writer.writeAll("null");
    }
    try writer.writeByte('}');
}

pub fn savePolicyText(io: std.Io, allocator: std.mem.Allocator, workspace_root: []const u8, text: []const u8) !PolicySaveResult {
    if (text.len > core.limits.max_policy_file_len) return .{ .ok = false, .error_name = "PolicyFileTooLarge" };
    var parsed = core_api.parsePolicyFromSlice(allocator, text, ".orca/policy.yaml") catch |err| {
        return .{ .ok = false, .error_name = @errorName(err) };
    };
    defer parsed.deinit();
    core_api.validatePolicy(parsed) catch |err| {
        return .{ .ok = false, .error_name = @errorName(err) };
    };

    const orca_dir = try std.fs.path.join(allocator, &.{ workspace_root, ".orca" });
    defer allocator.free(orca_dir);
    try std.Io.Dir.cwd().createDirPath(io, orca_dir);
    const path = try policyPath(allocator, workspace_root);
    defer allocator.free(path);
    const file = try std.Io.Dir.createFileAbsolute(io, path, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, text);
    try file.sync(io);
    return .{ .ok = true };
}

pub fn initPolicyFromPreset(io: std.Io, allocator: std.mem.Allocator, workspace_root: []const u8, preset_name: []const u8, force: bool) !PolicySaveResult {
    const preset = policy_mod.presets.AgentPreset.parse(preset_name) orelse return .{ .ok = false, .error_name = "UnsupportedPreset" };
    const path = try policyPath(allocator, workspace_root);
    defer allocator.free(path);
    if (!force and fileExistsAbsolute(io, path)) return .{ .ok = false, .error_name = "PolicyAlreadyExists" };
    return savePolicyText(io, allocator, workspace_root, policy_mod.presets.agentPresetText(preset));
}

pub fn writeSessionsJson(io: std.Io, allocator: std.mem.Allocator, writer: anytype, workspace_root: []const u8) !void {
    try writer.writeByte('{');
    try writer.writeAll("\"sessions\":");
    try writeSessionsArrayJson(io, allocator, writer, workspace_root, 20);
    try writer.writeAll(",\"blocked_actions\":");
    try writeBlockedActionsArrayJson(io, allocator, writer, workspace_root, 50);
    try writer.writeByte('}');
}

pub fn writeMachineSessionsJson(
    io: std.Io,
    allocator: std.mem.Allocator,
    writer: anytype,
    dashboard_root: []const u8,
) !void {
    const workspaces = try aggregate.loadWorkspaces(io, allocator, dashboard_root);
    defer aggregate.deinitWorkspaces(allocator, workspaces);
    try writer.writeAll("{\"sessions\":");
    try aggregate.writeSessionsJson(io, allocator, writer, workspaces, 50);
    try writer.writeAll(",\"blocked_actions\":");
    try aggregate.writeGlobalFeedJson(io, allocator, writer, dashboard_root, 100, true);
    try writer.writeByte('}');
}

fn writePolicySummaryJson(io: std.Io, allocator: std.mem.Allocator, writer: anytype, workspace_root: []const u8) !void {
    const path = try policyPath(allocator, workspace_root);
    defer allocator.free(path);
    try writer.writeByte('{');
    try writer.writeAll("\"path\":\".orca/policy.yaml\",");
    if (!fileExistsAbsolute(io, path)) {
        try writer.writeAll("\"exists\":false,\"valid\":false,\"mode\":null,\"error\":null");
        try writer.writeByte('}');
        return;
    }
    try writer.writeAll("\"exists\":true,");
    if (core_api.loadPolicyFile(io, allocator, path)) |loaded_policy| {
        var loaded = loaded_policy;
        defer loaded.deinit();
        try writer.writeAll("\"valid\":true,\"mode\":");
        try core.util.writeJsonString(writer, loaded.mode().toString());
        try writer.writeAll(",\"error\":null");
    } else |err| {
        if (err == error.OutOfMemory) return err;
        try writer.writeAll("\"valid\":false,\"mode\":null,\"error\":");
        try core.util.writeJsonString(writer, @errorName(err));
    }
    try writer.writeByte('}');
}

fn writeLicenseJson(io: std.Io, allocator: std.mem.Allocator, writer: anytype) !void {
    var current = license_mod.status(io, allocator) catch |err| switch (err) {
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

fn writeCiReadinessJson(io: std.Io, allocator: std.mem.Allocator, writer: anytype, workspace_root: []const u8) !void {
    var result = ci_check.run(io, allocator, workspace_root) catch |err| {
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
    io: std.Io,
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
    const host_found = try executableInPath(io, allocator, binary_name);
    const integration_present = pathExistsAbsolute(io, integration_abs);
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
            "orca setup",
            "orca plugin doctor hermes",
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

fn writeSessionsArrayJson(io: std.Io, allocator: std.mem.Allocator, writer: anytype, workspace_root: []const u8, max_count: usize) !void {
    const sessions_root = try std.fs.path.join(allocator, &.{ workspace_root, ".orca", "sessions" });
    defer allocator.free(sessions_root);
    var dir = std.Io.Dir.cwd().openDir(io, sessions_root, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => {
            try writer.writeAll("[]");
            return;
        },
        else => return err,
    };
    defer dir.close(io);

    try writer.writeByte('[');
    var it = dir.iterate();
    var count: usize = 0;
    while (count < max_count) {
        const entry = try it.next(io) orelse break;
        if (entry.kind != .directory) continue;
        if (core.session.validateSessionIdText(entry.name)) |_| {} else |_| continue;
        if (count > 0) try writer.writeByte(',');
        try writeSessionSummaryJson(io, allocator, writer, workspace_root, entry.name);
        count += 1;
    }
    try writer.writeByte(']');
}

fn writeSessionSummaryJson(io: std.Io, allocator: std.mem.Allocator, writer: anytype, workspace_root: []const u8, session_id: []const u8) !void {
    try writer.writeByte('{');
    try writer.writeAll("\"id\":");
    try core.util.writeJsonString(writer, session_id);
    if (core_api.loadReplay(io, allocator, workspace_root, .{ .session = session_id, .only_denied = true, .verify = false })) |loaded_replay| {
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

fn writeDaemonHealthJson(allocator: std.mem.Allocator, writer: anytype) !void {
    var health = rust_visibility.probeGuiDaemonHealth(allocator) catch {
        try writer.writeAll("{\"status\":\"unavailable\",\"detail\":\"failed to probe daemon health\"}");
        return;
    };
    defer health.deinit(allocator);
    try writer.writeByte('{');
    try writer.writeAll("\"status\":");
    try core.util.writeJsonString(writer, health.status);
    try writer.writeAll(",\"detail\":");
    try core.util.writeJsonString(writer, health.detail);
    try writer.writeByte('}');
}

fn writeRustShellDecisionsArrayJson(io: std.Io, allocator: std.mem.Allocator, writer: anytype, workspace_root: []const u8, max_count: usize) !void {
    const loaded = feed_writer.loadRecent(io, allocator, workspace_root, max_count) catch {
        try writer.writeAll("[]");
        return;
    };
    defer {
        for (loaded) |*item| item.deinit(allocator);
        allocator.free(loaded);
    }
    try writer.writeByte('[');
    for (loaded, 0..) |item, index| {
        if (index > 0) try writer.writeByte(',');
        try writeFeedRecordJson(writer, item.record);
    }
    try writer.writeByte(']');
}

fn writeFeedRecordJson(writer: anytype, record: rust_visibility.RustShellFeedRecord) !void {
    try writer.writeByte('{');
    try writer.writeAll("\"timestamp\":");
    try core.util.writeJsonString(writer, record.timestamp);
    try writer.writeAll(",\"workspace_root\":");
    try core.util.writeJsonString(writer, record.workspace_root);
    try writer.writeAll(",\"event_type\":");
    try core.util.writeJsonString(writer, record.event_type);
    try writer.writeAll(",\"decision\":");
    try core.util.writeJsonString(writer, record.decision);
    try writer.writeAll(",\"decision_source\":");
    try core.util.writeJsonString(writer, record.decision_source);
    try writer.writeAll(",\"event_source\":");
    try core.util.writeJsonString(writer, record.event_source);
    try writer.writeAll(",\"host\":");
    if (record.host) |host| try core.util.writeJsonString(writer, host) else try writer.writeAll("null");
    try writer.writeAll(",\"daemon_status\":");
    try core.util.writeJsonString(writer, record.daemon_status);
    try writer.writeAll(",\"pack_id\":");
    if (record.pack_id) |pack_id| try core.util.writeJsonString(writer, pack_id) else try writer.writeAll("null");
    try writer.writeAll(",\"severity\":");
    if (record.severity) |severity| try core.util.writeJsonString(writer, severity) else try writer.writeAll("null");
    try writer.writeAll(",\"reason\":");
    try core.util.writeJsonString(writer, record.reason);
    try writer.writeAll(",\"remediation\":");
    if (record.remediation) |remediation| try core.util.writeJsonString(writer, remediation) else try writer.writeAll("null");
    try writer.writeAll(",\"target\":");
    try core.util.writeJsonString(writer, record.target_summary);
    try writer.writeAll(",\"session_id\":");
    if (record.session_id) |session_id| try core.util.writeJsonString(writer, session_id) else try writer.writeAll("null");
    try writer.writeAll(",\"verified\":");
    try writer.writeAll(if (record.verified) "true" else "false");
    try writer.writeByte('}');
}

fn writeBlockedActionsArrayJson(io: std.Io, allocator: std.mem.Allocator, writer: anytype, workspace_root: []const u8, max_count: usize) !void {
    try writer.writeByte('[');
    var written: usize = 0;

    const feed_owned: ?[]feed_writer.LoadedFeedRecord = feed_writer.loadRecent(io, allocator, workspace_root, max_count) catch null;
    defer if (feed_owned) |owned| {
        for (owned) |*item| item.deinit(allocator);
        allocator.free(owned);
    };
    const feed = feed_owned orelse &[_]feed_writer.LoadedFeedRecord{};
    for (feed) |item| {
        if (written >= max_count) break;
        if (!std.mem.eql(u8, item.record.decision, "deny")) continue;
        if (written > 0) try writer.writeByte(',');
        try writeFeedRecordJson(writer, item.record);
        written += 1;
    }

    const sessions_root = std.fs.path.join(allocator, &.{ workspace_root, ".orca", "sessions" }) catch {
        try writer.writeByte(']');
        return;
    };
    defer allocator.free(sessions_root);
    var dir = std.Io.Dir.cwd().openDir(io, sessions_root, .{ .iterate = true }) catch {
        try writer.writeByte(']');
        return;
    };
    defer dir.close(io);

    var it = dir.iterate();
    while (written < max_count) {
        const entry = try it.next(io) orelse break;
        if (entry.kind != .directory) continue;
        if (core.session.validateSessionIdText(entry.name)) |_| {} else |_| continue;
        var replay = core_api.loadReplay(io, allocator, workspace_root, .{ .session = entry.name, .only_denied = true, .verify = false }) catch continue;
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

const ParsedMetadata = struct {
    decision_source: ?[]const u8 = null,
    event_source: ?[]const u8 = null,
    host: ?[]const u8 = null,
    daemon_status: ?[]const u8 = null,
    pack_id: ?[]const u8 = null,
    severity: ?[]const u8 = null,
    remediation: ?[]const u8 = null,
};

fn readEventMetadata(parsed: ?std.json.Parsed(std.json.Value)) ParsedMetadata {
    const object = if (parsed) |p| blk: {
        if (p.value != .object) return .{};
        break :blk p.value.object;
    } else return .{};
    const metadata = object.get("metadata") orelse return .{};
    if (metadata != .object) return .{};
    return .{
        .decision_source = readMetadataString(metadata.object, "decision_source"),
        .event_source = readMetadataString(metadata.object, "event_source"),
        .host = readMetadataString(metadata.object, "host"),
        .daemon_status = readMetadataString(metadata.object, "daemon_status"),
        .pack_id = readMetadataString(metadata.object, "pack_id"),
        .severity = readMetadataString(metadata.object, "severity"),
        .remediation = readMetadataString(metadata.object, "remediation"),
    };
}

fn readMetadataString(object: std.json.ObjectMap, field: []const u8) ?[]const u8 {
    const value = object.get(field) orelse return null;
    if (value != .string) return null;
    return value.string;
}

fn writeMetadataFields(writer: anytype, metadata: ParsedMetadata) !void {
    try writer.writeAll(",\"decision_source\":");
    if (metadata.decision_source) |value| try core.util.writeJsonString(writer, value) else try writer.writeAll("null");
    try writer.writeAll(",\"event_source\":");
    if (metadata.event_source) |value| try core.util.writeJsonString(writer, value) else try writer.writeAll("null");
    try writer.writeAll(",\"host\":");
    if (metadata.host) |value| try core.util.writeJsonString(writer, value) else try writer.writeAll("null");
    try writer.writeAll(",\"daemon_status\":");
    if (metadata.daemon_status) |value| try core.util.writeJsonString(writer, value) else try writer.writeAll("null");
    try writer.writeAll(",\"pack_id\":");
    if (metadata.pack_id) |value| try core.util.writeJsonString(writer, value) else try writer.writeAll("null");
    try writer.writeAll(",\"severity\":");
    if (metadata.severity) |value| try core.util.writeJsonString(writer, value) else try writer.writeAll("null");
    try writer.writeAll(",\"remediation\":");
    if (metadata.remediation) |value| try core.util.writeJsonString(writer, value) else try writer.writeAll("null");
}

fn writeBlockedActionJson(allocator: std.mem.Allocator, writer: anytype, session_id: []const u8, verified: bool, ev: anytype) !void {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, ev.raw, .{}) catch null;
    defer if (parsed) |*p| p.deinit();
    const metadata = readEventMetadata(parsed);
    const target = if (metadata.decision_source != null and std.mem.eql(u8, metadata.decision_source.?, rust_visibility.decision_source_rust))
        rust_visibility.target_summary_shell
    else
        ev.target_value;

    try writer.writeByte('{');
    try writer.writeAll("\"session_id\":");
    try core.util.writeJsonString(writer, session_id);
    try writer.writeAll(",\"timestamp\":");
    try core.util.writeJsonString(writer, ev.timestamp);
    try writer.writeAll(",\"event_type\":");
    try core.util.writeJsonString(writer, ev.event_type);
    try writer.writeAll(",\"target\":");
    try core.util.writeJsonString(writer, target);
    try writer.writeAll(",\"decision\":");
    if (ev.decision_result) |result| try core.util.writeJsonString(writer, result) else try writer.writeAll("null");
    try writer.writeAll(",\"verified\":");
    try writer.writeAll(if (verified) "true" else "false");
    try writer.writeAll(",\"rule\":");
    try writeDecisionField(writer, parsed, "rule_id");
    try writer.writeAll(",\"reason\":");
    try writeDecisionField(writer, parsed, "reason");
    try writeMetadataFields(writer, metadata);
    try writer.writeByte('}');
}
fn writeRecentSecretlessAuditEventsJson(io: std.Io, allocator: std.mem.Allocator, writer: anytype, workspace_root: []const u8, max_count: usize) !void {
    const sessions_root = try std.fs.path.join(allocator, &.{ workspace_root, ".orca", "sessions" });
    defer allocator.free(sessions_root);
    var dir = std.Io.Dir.cwd().openDir(io, sessions_root, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => {
            try writer.writeAll("[]");
            return;
        },
        else => return err,
    };
    defer dir.close(io);

    try writer.writeByte('[');
    var written: usize = 0;
    var it = dir.iterate();
    while (written < max_count) {
        const entry = try it.next(io) orelse break;
        if (entry.kind != .directory) continue;
        if (core.session.validateSessionIdText(entry.name)) |_| {} else |_| continue;
        var replay = core_api.loadReplay(io, allocator, workspace_root, .{ .session = entry.name, .only_denied = false, .verify = false }) catch continue;
        defer replay.deinit();
        for (replay.events) |ev| {
            if (written >= max_count) break;
            if (!isSecretlessEvidenceEvent(ev.event_type)) continue;
            if (written > 0) try writer.writeByte(',');
            try writer.writeByte('{');
            try writer.writeAll("\"session_id\":");
            try core.util.writeJsonString(writer, replay.session_id);
            try writer.writeAll(",\"timestamp\":");
            try core.util.writeJsonString(writer, ev.timestamp);
            try writer.writeAll(",\"event_type\":");
            try core.util.writeJsonString(writer, ev.event_type);
            try writer.writeAll(",\"target\":");
            try core.util.writeJsonString(writer, ev.target_value);
            try writer.writeAll(",\"decision\":");
            if (ev.decision_result) |result| try core.util.writeJsonString(writer, result) else try writer.writeAll("null");
            try writer.writeAll(",\"verified\":");
            try writer.writeAll(if (replay.verified) "true" else "false");
            try writer.writeByte('}');
            written += 1;
        }
    }
    try writer.writeByte(']');
}

fn isSecretlessEvidenceEvent(event_type: []const u8) bool {
    return std.mem.eql(u8, event_type, "secret_redacted") or
        std.mem.eql(u8, event_type, "network_proxy_start") or
        std.mem.eql(u8, event_type, "network_proxy_stop") or
        std.mem.eql(u8, event_type, "network_connect_attempt") or
        std.mem.eql(u8, event_type, "network_connect_allowed") or
        std.mem.eql(u8, event_type, "network_connect_denied");
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

fn fileExistsAbsolute(io: std.Io, path: []const u8) bool {
    std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}

fn pathExistsAbsolute(io: std.Io, path: []const u8) bool {
    std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}

fn readFileIfExists(io: std.Io, allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_bytes));
}

fn executableInPath(io: std.Io, allocator: std.mem.Allocator, name: []const u8) !bool {
    const env_util = @import("../env_util.zig");
    var env_map = try env_util.createProcessMap(allocator);
    defer env_map.deinit();
    const path = env_map.get("PATH") orelse return false;
    const separator: u8 = if (@import("builtin").os.tag == .windows) ';' else ':';
    var parts = std.mem.splitScalar(u8, path, separator);
    while (parts.next()) |part| {
        if (part.len == 0) continue;
        const candidate = try std.fs.path.join(allocator, &.{ part, name });
        defer allocator.free(candidate);
        if (fileExistsAbsolute(io, candidate)) return true;
    }
    return false;
}

test "policy save validates before writing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    const io = std.testing.io;
    const bad = try savePolicyText(io, std.testing.allocator, root, "version: 1\nmode: strict\ncommands: allow\n");
    try std.testing.expect(!bad.ok);
    try std.testing.expectEqualStrings("InvalidPolicy", bad.error_name.?);
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(io, ".orca/policy.yaml", .{}));

    const ok = try savePolicyText(io, std.testing.allocator, root, policy_mod.presets.agentPresetText(.generic_agent));
    try std.testing.expect(ok.ok);
    try tmp.dir.access(io, ".orca/policy.yaml", .{});
}

test "init policy refuses overwrite unless forced" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    const io = std.testing.io;
    const first = try initPolicyFromPreset(io, std.testing.allocator, root, "generic-agent", false);
    try std.testing.expect(first.ok);
    const second = try initPolicyFromPreset(io, std.testing.allocator, root, "strict-local", false);
    try std.testing.expect(!second.ok);
    try std.testing.expectEqualStrings("PolicyAlreadyExists", second.error_name.?);
    const forced = try initPolicyFromPreset(io, std.testing.allocator, root, "strict-local", true);
    try std.testing.expect(forced.ok);
}

test "status json includes policy and protected agent cards" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const io = std.testing.io;
    _ = try initPolicyFromPreset(io, std.testing.allocator, root, "generic-agent", false);
    try writeSecretlessEvidenceFixture(std.testing.allocator, root);

    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    try writeStatusJson(io, std.testing.allocator, &aw.writer, root);
    var out = aw.toArrayList();
    defer out.deinit(std.testing.allocator);

    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"policy\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"secretless_runtime\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"active_broker\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"credential_refs\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"broker_checks\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"proxy_backend\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"https_visibility\":\"host-port-only\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"recent_audit_events\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"network_connect_allowed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"network_proxy_start\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"service_policy_template\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"verify_commands\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"openclaw\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"hermes\"") != null);
}

test "dashboard assets expose dedicated secretless view" {
    const io = std.testing.io;
    const index = try std.Io.Dir.cwd().readFileAlloc(io, "src/dashboard/assets/index.html", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(index);
    const app = try std.Io.Dir.cwd().readFileAlloc(io, "src/dashboard/assets/app.js", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(app);

    try std.testing.expect(std.mem.indexOf(u8, index, "data-view=\"secretless\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, index, "secretlessPolicyTemplate") != null);
    try std.testing.expect(std.mem.indexOf(u8, index, "secretlessCredentialRefs") != null);
    try std.testing.expect(std.mem.indexOf(u8, index, "secretlessProxyMeta") != null);
    try std.testing.expect(std.mem.indexOf(u8, index, "secretlessBrokerChecks") != null);
    try std.testing.expect(std.mem.indexOf(u8, index, "modeTitle") != null);
    try std.testing.expect(std.mem.indexOf(u8, index, "workspaceList") != null);
    try std.testing.expect(std.mem.indexOf(u8, index, "data-workspace-only") != null);
    try std.testing.expect(std.mem.indexOf(u8, app, "renderSecretless") != null);
    try std.testing.expect(std.mem.indexOf(u8, app, "insertSecretlessPolicyTemplate") != null);
    try std.testing.expect(std.mem.indexOf(u8, app, "decision_source") != null);
    try std.testing.expect(std.mem.indexOf(u8, app, "daemon_health") != null);
    try std.testing.expect(std.mem.indexOf(u8, app, "daemonHealthLabel") != null);
    try std.testing.expect(std.mem.indexOf(u8, app, "remediation") != null);
    try std.testing.expect(std.mem.indexOf(u8, app, "data.mode === \"machine\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, app, "renderWorkspaces") != null);
    try std.testing.expect(std.mem.indexOf(u8, app, "workspace_root") != null);
}

test "sessions json filters denied replay events" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    try writeDeniedReplayFixture(std.testing.allocator, root);

    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    try writeSessionsJson(std.testing.io, std.testing.allocator, &aw.writer, root);
    var out = aw.toArrayList();
    defer out.deinit(std.testing.allocator);

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
    var writer = try core_api.createAuditWriter(std.testing.io, allocator, session);
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

fn writeSecretlessEvidenceFixture(allocator: std.mem.Allocator, root: []const u8) !void {
    const timestamp = core.time.Timestamp.fromUnixSeconds(1_777_983_131);
    var session = core.session.Session{
        .id = try core.session.generateSessionId(timestamp),
        .started_at = timestamp,
        .ended_at = timestamp,
        .command = "orca",
        .args = &.{ "run", "--secretless", "--network-backend", "proxy", "--", "agent" },
        .workspace_root = root,
        .mode = .observe,
        .platform = core.platform.detectOs(),
    };
    var writer = try core_api.createAuditWriter(std.testing.io, allocator, session);
    defer writer.deinit();
    try appendFixtureEvent(&writer, session, timestamp, .network_proxy_start, "http://127.0.0.1:49152", .observe);
    try appendFixtureEvent(&writer, session, timestamp, .network_connect_attempt, "http://127.0.0.1:49153/echo", .observe);
    try appendFixtureEvent(&writer, session, timestamp, .network_connect_allowed, "http://127.0.0.1:49153/echo", .allow);
    try writer.writeLastPointer();
    try core_api.writeAuditSummary(allocator, writer.sessionDirPath(), .{
        .session = session,
        .status = .{ .exited = 0 },
        .event_count = writer.event_count,
        .final_event_hash = writer.finalHash().?,
        .policy = ".orca/policy.yaml",
        .product_label = "Orca",
    });
    _ = &session;
}

fn appendFixtureEvent(
    writer: *core_api.AuditWriter,
    session: core.session.Session,
    timestamp: core.time.Timestamp,
    event_type: core.event.EventType,
    target: []const u8,
    result: core.decision.DecisionResult,
) !void {
    const event = try core_api.createAuditEvent(.{
        .session_id = session.id,
        .event_id = try core.event.generateEventId(timestamp),
        .timestamp = timestamp,
        .event_type = core_api.fromCoreEventType(event_type),
        .actor = .{ .kind = .orca, .display = "orca" },
        .target = .{ .kind = .network_endpoint, .value = target },
        .decision = core_api.makeDecision(.{ .result = result, .reason = "fixture evidence" }),
    });
    try core_api.appendAuditEvent(writer, event);
}

test "status json exposes daemon health and rust shell decisions feed" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var record = try rust_visibility.buildFeedRecordFromHookDecision(
        std.testing.allocator,
        std.testing.io,
        root,
        "claude",
        "healthy",
        "deny",
        "blocked by Orca policy rule: destructive_rm",
        "destructive_rm",
        "Critical",
        "Use a safer workflow.",
        "git",
        null,
    );
    defer record.deinit(std.testing.allocator);
    try feed_writer.appendRecord(std.testing.io, std.testing.allocator, root, record);

    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    try writeStatusJson(std.testing.io, std.testing.allocator, &aw.writer, root);
    var out = aw.toArrayList();
    defer out.deinit(std.testing.allocator);

    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"daemon_health\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"rust_shell_decisions\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"decision_source\":\"rust-daemon\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"pack_id\":\"git\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"severity\":\"Critical\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "shell command (redacted)") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "matched_text_preview") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"raw\"") == null);
}

test "machine status aggregates registered workspaces and exposes only global actions" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const workspace_a = try std.fs.path.join(std.testing.allocator, &.{ root, "project-a" });
    defer std.testing.allocator.free(workspace_a);
    const workspace_b = try std.fs.path.join(std.testing.allocator, &.{ root, "project-b" });
    defer std.testing.allocator.free(workspace_b);
    try std.Io.Dir.cwd().createDirPath(std.testing.io, workspace_a);
    try std.Io.Dir.cwd().createDirPath(std.testing.io, workspace_b);
    try writeDeniedReplayFixture(std.testing.allocator, workspace_a);
    try writeDeniedReplayFixture(std.testing.allocator, workspace_b);
    const dashboard_root = try std.fs.path.join(std.testing.allocator, &.{ root, "home", ".orca", "dashboard" });
    defer std.testing.allocator.free(dashboard_root);

    for ([_][]const u8{ workspace_a, workspace_b }) |workspace| {
        var record = try rust_visibility.buildFeedRecordFromHookDecision(
            std.testing.allocator,
            std.testing.io,
            workspace,
            "codex",
            "healthy",
            "deny",
            "blocked by Orca policy",
            null,
            null,
            null,
            null,
            null,
        );
        defer record.deinit(std.testing.allocator);
        try feed_writer.appendGlobalRecord(std.testing.io, std.testing.allocator, dashboard_root, record);
    }

    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    try writeMachineStatusJson(std.testing.io, std.testing.allocator, &aw.writer, dashboard_root);
    const out = try aw.toOwnedSlice();
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"mode\":\"machine\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"workspace_count\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, workspace_a) != null);
    try std.testing.expect(std.mem.indexOf(u8, out, workspace_b) != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"id\":\"doctor\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"id\":\"license-status\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "replay-last") == null);
}
