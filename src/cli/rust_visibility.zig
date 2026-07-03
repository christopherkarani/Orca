const std = @import("std");

const core = @import("orca_core").core;
const core_api = @import("orca_core").api;
const daemon = @import("daemon.zig");
pub const decision_source_rust = "rust-daemon";
pub const decision_source_zig = "zig-native";
pub const event_source_hook = "hook";
pub const event_source_run = "run";
pub const target_summary_shell = "shell command (redacted)";

pub const GuiDaemonHealth = struct {
    status: []const u8,
    detail: []const u8,

    pub fn deinit(self: *GuiDaemonHealth, allocator: std.mem.Allocator) void {
        allocator.free(self.status);
        allocator.free(self.detail);
        self.* = undefined;
    }
};

pub const RustShellFeedRecord = struct {
    timestamp: []const u8,
    workspace_root: []const u8,
    event_type: []const u8,
    decision: []const u8,
    decision_source: []const u8,
    event_source: []const u8,
    host: ?[]const u8,
    daemon_status: []const u8,
    pack_id: ?[]const u8,
    severity: ?[]const u8,
    reason: []const u8,
    remediation: ?[]const u8,
    target_summary: []const u8,
    session_id: ?[]const u8,
    verified: bool,

    pub fn deinit(self: *RustShellFeedRecord, allocator: std.mem.Allocator) void {
        allocator.free(self.timestamp);
        allocator.free(self.workspace_root);
        allocator.free(self.event_type);
        allocator.free(self.decision);
        allocator.free(self.decision_source);
        allocator.free(self.event_source);
        if (self.host) |host| allocator.free(host);
        allocator.free(self.daemon_status);
        if (self.pack_id) |pack_id| allocator.free(pack_id);
        if (self.severity) |severity| allocator.free(severity);
        allocator.free(self.reason);
        if (self.remediation) |remediation| allocator.free(remediation);
        allocator.free(self.target_summary);
        if (self.session_id) |session_id| allocator.free(session_id);
        self.* = undefined;
    }
};

fn daemonUnavailableReason(err: daemon.DaemonError) []const u8 {
    return switch (err) {
        error.HomeDirectoryNotFound => "daemon unavailable: HOME not set",
        error.DaemonBinaryNotFound => "daemon unavailable: orca-daemon binary not found",
        error.DaemonBinaryNotExecutable => "daemon unavailable: orca-daemon is not executable",
        error.DaemonSpawnFailed => "daemon unavailable: failed to spawn orca-daemon",
        error.DaemonStartTimeout => "daemon unavailable: startup timed out",
        error.DaemonNotReady => "daemon unavailable: daemon not ready",
        error.StaleSocket => "daemon unavailable: stale socket artifact",
        error.SocketConnectFailed => "daemon unavailable: socket connect failed",
        error.SocketWriteFailed => "daemon unavailable: socket write failed",
        error.SocketReadFailed => "daemon unavailable: socket read failed",
        error.InvalidWorkingDirectory => "daemon unavailable: command working directory does not exist",
        error.RequestSerializationFailed => "daemon unavailable: request serialization failed",
        error.ResponseParseFailed => "daemon unavailable: malformed daemon response",
        error.DaemonProtocolError => "daemon unavailable: protocol error",
        error.MissingHandshake => "daemon unavailable: missing protocol handshake",
        error.HandshakeMalformed => "daemon unavailable: malformed protocol handshake",
        error.ProtocolMismatch => "daemon unavailable: incompatible daemon protocol",
        error.OutOfMemory => "daemon unavailable: out of memory",
    };
}

fn buildDaemonDenyReason(
    allocator: std.mem.Allocator,
    result: std.json.Value,
) !struct {
    reason: []const u8,
    rule: ?[]const u8,
} {
    const rule = if (daemon.responseDenyRule(result)) |rule_name| try allocator.dupe(u8, rule_name) else null;
    errdefer if (rule) |rule_name| allocator.free(rule_name);

    const reason = if (rule) |rule_name|
        try std.fmt.allocPrint(allocator, "blocked by Orca policy rule: {s}", .{rule_name})
    else
        try allocator.dupe(u8, "command denied by Orca policy");

    return .{ .reason = reason, .rule = rule };
}

pub fn probeGuiDaemonHealth(allocator: std.mem.Allocator) !GuiDaemonHealth {
    if (daemon.checkCompatibility(allocator)) |_| {
        return .{
            .status = try allocator.dupe(u8, "healthy"),
            .detail = try allocator.dupe(u8, "Daemon handshake succeeded with a compatible protocol."),
        };
    } else |err| {
        const status: []const u8 = switch (err) {
            error.ProtocolMismatch => "incompatible",
            error.MissingHandshake, error.HandshakeMalformed, error.DaemonProtocolError, error.ResponseParseFailed => "degraded",
            else => "unavailable",
        };
        const detail = try std.fmt.allocPrint(allocator, "{s}", .{daemonUnavailableReason(err)});
        return .{
            .status = try allocator.dupe(u8, status),
            .detail = detail,
        };
    }
}

pub fn guiDaemonStatusFromDoctorStatus(doctor_status: []const u8) []const u8 {
    if (std.mem.eql(u8, doctor_status, "compatible")) return "healthy";
    return doctor_status;
}

pub fn normalizeSeverity(severity: ?[]const u8) ?[]const u8 {
    const value = severity orelse return null;
    if (value.len == 0) return null;
    return value;
}

pub fn packIdFromDaemonResult(result: std.json.Value) ?[]const u8 {
    return daemon.responseStringField(result, "pack_id");
}

pub fn severityFromDaemonResult(result: std.json.Value) ?[]const u8 {
    return normalizeSeverity(daemon.responseStringField(result, "severity"));
}

pub fn remediationFromDaemonResult(allocator: std.mem.Allocator, result: std.json.Value) !?[]const u8 {
    if (daemon.responseArrayField(result, "suggestions")) |items| {
        if (items.len > 0) {
            const first = items[0];
            if (first == .object) {
                if (first.object.get("text")) |text_value| {
                    if (text_value == .string) {
                        return try sanitizeRemediationText(allocator, text_value.string);
                    }
                }
            }
        }
    }
    if (daemon.responseStringField(result, "explanation")) |explanation| {
        return try sanitizeRemediationText(allocator, explanation);
    }
    return null;
}

pub fn safeReasonFromDaemonResult(allocator: std.mem.Allocator, result: std.json.Value) ![]const u8 {
    return switch (daemon.responseStatus(result)) {
        .allow => try allocator.dupe(u8, daemon.responseReason(result) orelse "command allowed by Orca policy"),
        .deny => blk: {
            const deny = try buildDaemonDenyReason(allocator, result);
            defer if (deny.rule) |rule| allocator.free(rule);
            break :blk deny.reason;
        },
        else => try allocator.dupe(u8, daemon.responseErrorMessage(result) orelse "daemon evaluation error"),
    };
}

pub fn safeReasonFromUnavailable(allocator: std.mem.Allocator, err: daemon.DaemonError) ![]const u8 {
    return try allocator.dupe(u8, daemonUnavailableReason(err));
}

pub fn decisionResultTag(result: std.json.Value) []const u8 {
    return switch (daemon.responseStatus(result)) {
        .allow => "allow",
        .deny => "deny",
        .error_status => "error",
        else => "error",
    };
}

pub fn eventTypeForDecision(decision: []const u8) []const u8 {
    if (std.mem.eql(u8, decision, "allow") or std.mem.eql(u8, decision, "observe")) return "command_allowed";
    return "command_denied";
}

pub fn hookEventTypeForDecisionTag(decision_tag: []const u8) []const u8 {
    if (std.mem.eql(u8, decision_tag, "allow") or std.mem.eql(u8, decision_tag, "observe")) return "command_allowed";
    return "command_denied";
}

pub fn buildFeedRecordFromHookDecision(
    allocator: std.mem.Allocator,
    io: std.Io,
    workspace_root: []const u8,
    host: []const u8,
    daemon_status: []const u8,
    decision_tag: []const u8,
    reason: []const u8,
    rule: ?[]const u8,
    severity: ?[]const u8,
    remediation: ?[]const u8,
    pack_id: ?[]const u8,
    session_id: ?[]const u8,
) !RustShellFeedRecord {
    _ = rule;
    var reason_buf: [512]u8 = undefined;
    const safe_reason = core_api.redactStringBounded(reason, &reason_buf);

    var timestamp_buf: [32]u8 = undefined;
    const timestamp = try core.time.Timestamp.now(io).formatIso(&timestamp_buf);

    return .{
        .timestamp = try allocator.dupe(u8, timestamp),
        .workspace_root = try allocator.dupe(u8, workspace_root),
        .event_type = try allocator.dupe(u8, hookEventTypeForDecisionTag(decision_tag)),
        .decision = try allocator.dupe(u8, decision_tag),
        .decision_source = try allocator.dupe(u8, decision_source_rust),
        .event_source = try allocator.dupe(u8, event_source_hook),
        .host = try allocator.dupe(u8, host),
        .daemon_status = try allocator.dupe(u8, daemon_status),
        .pack_id = if (pack_id) |pack| try allocator.dupe(u8, pack) else null,
        .severity = if (severity) |sev| try allocator.dupe(u8, sev) else null,
        .reason = try allocator.dupe(u8, safe_reason),
        .remediation = if (remediation) |text| blk: {
            break :blk try sanitizeRemediationText(allocator, text);
        } else null,
        .target_summary = try allocator.dupe(u8, target_summary_shell),
        .session_id = if (session_id) |sid| try allocator.dupe(u8, sid) else null,
        .verified = false,
    };
}

pub fn metadataFromDaemonResult(
    allocator: std.mem.Allocator,
    event_source: []const u8,
    host: ?[]const u8,
    daemon_status: []const u8,
    result: std.json.Value,
) !core.event.EventMetadata {
    const pack_id = packIdFromDaemonResult(result);
    const severity = severityFromDaemonResult(result);
    const remediation = try remediationFromDaemonResult(allocator, result);
    errdefer if (remediation) |text| allocator.free(text);

    return .{
        .decision_source = try allocator.dupe(u8, decision_source_rust),
        .event_source = try allocator.dupe(u8, event_source),
        .host = if (host) |host_name| try allocator.dupe(u8, host_name) else null,
        .daemon_status = try allocator.dupe(u8, daemon_status),
        .pack_id = if (pack_id) |pack| try allocator.dupe(u8, pack) else null,
        .severity = if (severity) |sev| try allocator.dupe(u8, sev) else null,
        .remediation = remediation,
    };
}

pub fn metadataForUnavailable(
    allocator: std.mem.Allocator,
    event_source: []const u8,
    host: ?[]const u8,
    err: daemon.DaemonError,
) !core.event.EventMetadata {
    const daemon_status: []const u8 = switch (err) {
        error.ProtocolMismatch => "incompatible",
        error.MissingHandshake, error.HandshakeMalformed, error.DaemonProtocolError, error.ResponseParseFailed => "degraded",
        else => "unavailable",
    };
    return .{
        .decision_source = try allocator.dupe(u8, decision_source_rust),
        .event_source = try allocator.dupe(u8, event_source),
        .host = if (host) |host_name| try allocator.dupe(u8, host_name) else null,
        .daemon_status = try allocator.dupe(u8, daemon_status),
    };
}

pub fn buildFeedRecordFromDaemon(
    allocator: std.mem.Allocator,
    io: std.Io,
    workspace_root: []const u8,
    event_source: []const u8,
    host: ?[]const u8,
    daemon_status: []const u8,
    result: std.json.Value,
    session_id: ?[]const u8,
    verified: bool,
) !RustShellFeedRecord {
    const decision = decisionResultTag(result);
    const reason = try safeReasonFromDaemonResult(allocator, result);
    errdefer allocator.free(reason);
    const remediation = try remediationFromDaemonResult(allocator, result);
    errdefer if (remediation) |text| allocator.free(text);

    var timestamp_buf: [32]u8 = undefined;
    const timestamp = try core.time.Timestamp.now(io).formatIso(&timestamp_buf);

    return .{
        .timestamp = try allocator.dupe(u8, timestamp),
        .workspace_root = try allocator.dupe(u8, workspace_root),
        .event_type = try allocator.dupe(u8, eventTypeForDecision(decision)),
        .decision = try allocator.dupe(u8, decision),
        .decision_source = try allocator.dupe(u8, decision_source_rust),
        .event_source = try allocator.dupe(u8, event_source),
        .host = if (host) |host_name| try allocator.dupe(u8, host_name) else null,
        .daemon_status = try allocator.dupe(u8, daemon_status),
        .pack_id = if (packIdFromDaemonResult(result)) |pack| try allocator.dupe(u8, pack) else null,
        .severity = if (severityFromDaemonResult(result)) |sev| try allocator.dupe(u8, sev) else null,
        .reason = reason,
        .remediation = remediation,
        .target_summary = try allocator.dupe(u8, target_summary_shell),
        .session_id = if (session_id) |sid| try allocator.dupe(u8, sid) else null,
        .verified = verified,
    };
}

pub fn buildFeedRecordFromUnavailable(
    allocator: std.mem.Allocator,
    io: std.Io,
    workspace_root: []const u8,
    event_source: []const u8,
    host: ?[]const u8,
    err: daemon.DaemonError,
    session_id: ?[]const u8,
    verified: bool,
) !RustShellFeedRecord {
    const daemon_status: []const u8 = switch (err) {
        error.ProtocolMismatch => "incompatible",
        error.MissingHandshake, error.HandshakeMalformed, error.DaemonProtocolError, error.ResponseParseFailed => "degraded",
        else => "unavailable",
    };
    const reason = try safeReasonFromUnavailable(allocator, err);
    errdefer allocator.free(reason);

    var timestamp_buf: [32]u8 = undefined;
    const timestamp = try core.time.Timestamp.now(io).formatIso(&timestamp_buf);

    return .{
        .timestamp = try allocator.dupe(u8, timestamp),
        .workspace_root = try allocator.dupe(u8, workspace_root),
        .event_type = try allocator.dupe(u8, "command_denied"),
        .decision = try allocator.dupe(u8, "deny"),
        .decision_source = try allocator.dupe(u8, decision_source_rust),
        .event_source = try allocator.dupe(u8, event_source),
        .host = if (host) |host_name| try allocator.dupe(u8, host_name) else null,
        .daemon_status = try allocator.dupe(u8, daemon_status),
        .pack_id = null,
        .severity = null,
        .reason = reason,
        .remediation = null,
        .target_summary = try allocator.dupe(u8, target_summary_shell),
        .session_id = if (session_id) |sid| try allocator.dupe(u8, sid) else null,
        .verified = verified,
    };
}

pub fn buildFeedRecordFromHookActivity(
    allocator: std.mem.Allocator,
    io: std.Io,
    workspace_root: []const u8,
    event_source: []const u8,
    decision_source: []const u8,
    host: ?[]const u8,
    daemon_status: []const u8,
    event_type: []const u8,
    decision_tag: []const u8,
    reason: []const u8,
    target_summary: []const u8,
    session_id: ?[]const u8,
    verified: bool,
) !RustShellFeedRecord {
    var timestamp_buf: [32]u8 = undefined;
    const timestamp = try core.time.Timestamp.now(io).formatIso(&timestamp_buf);

    var reason_buf: [512]u8 = undefined;
    const safe_reason = core_api.redactStringBounded(reason, &reason_buf);

    var target_buf: [512]u8 = undefined;
    const safe_target = core_api.redactStringBounded(target_summary, &target_buf);

    return .{
        .timestamp = try allocator.dupe(u8, timestamp),
        .workspace_root = try allocator.dupe(u8, workspace_root),
        .event_type = try allocator.dupe(u8, event_type),
        .decision = try allocator.dupe(u8, decision_tag),
        .decision_source = try allocator.dupe(u8, decision_source),
        .event_source = try allocator.dupe(u8, event_source),
        .host = if (host) |host_name| try allocator.dupe(u8, host_name) else null,
        .daemon_status = try allocator.dupe(u8, daemon_status),
        .pack_id = null,
        .severity = null,
        .reason = try allocator.dupe(u8, safe_reason),
        .remediation = null,
        .target_summary = try allocator.dupe(u8, safe_target),
        .session_id = if (session_id) |sid| try allocator.dupe(u8, sid) else null,
        .verified = verified,
    };
}

pub fn isBlockedFeedRecord(record: RustShellFeedRecord) bool {
    if (std.mem.eql(u8, record.decision, "deny")) return true;
    const host = record.host orelse return false;
    return std.mem.eql(u8, host, "hermes") and
        std.mem.eql(u8, record.event_type, "hermes_tool_call_blocked") and
        (std.mem.eql(u8, record.decision, "ask") or
            std.mem.eql(u8, record.decision, "warn") or
            std.mem.eql(u8, record.decision, "error"));
}

pub fn writeFeedRecordJson(writer: anytype, record: RustShellFeedRecord) !void {
    try writer.writeByte('{');
    try writeJsonField(writer, "timestamp", record.timestamp);
    try writer.writeByte(',');
    try writeJsonField(writer, "workspace_root", record.workspace_root);
    try writer.writeByte(',');
    try writeJsonField(writer, "event_type", record.event_type);
    try writer.writeByte(',');
    try writeJsonField(writer, "decision", record.decision);
    try writer.writeByte(',');
    try writeJsonField(writer, "decision_source", record.decision_source);
    try writer.writeByte(',');
    try writeJsonField(writer, "event_source", record.event_source);
    try writer.writeByte(',');
    try writeJsonFieldNullable(writer, "host", record.host);
    try writer.writeByte(',');
    try writeJsonField(writer, "daemon_status", record.daemon_status);
    try writer.writeByte(',');
    try writeJsonFieldNullable(writer, "pack_id", record.pack_id);
    try writer.writeByte(',');
    try writeJsonFieldNullable(writer, "severity", record.severity);
    try writer.writeByte(',');
    try writeJsonField(writer, "reason", record.reason);
    try writer.writeByte(',');
    try writeJsonFieldNullable(writer, "remediation", record.remediation);
    try writer.writeByte(',');
    try writeJsonField(writer, "target_summary", record.target_summary);
    try writer.writeByte(',');
    try writeJsonFieldNullable(writer, "session_id", record.session_id);
    try writer.writeAll(",\"verified\":");
    try writer.writeAll(if (record.verified) "true" else "false");
    try writer.writeByte('}');
}

fn writeJsonField(writer: anytype, field: []const u8, value: []const u8) !void {
    try writer.writeAll("\"");
    try writer.writeAll(field);
    try writer.writeAll("\":");
    var redacted_buf: [512]u8 = undefined;
    try core.util.writeJsonString(writer, core_api.redactStringBounded(value, &redacted_buf));
}

fn writeJsonFieldNullable(writer: anytype, field: []const u8, value: ?[]const u8) !void {
    try writer.writeAll("\"");
    try writer.writeAll(field);
    try writer.writeAll("\":");
    if (value) |text| {
        var redacted_buf: [512]u8 = undefined;
        try core.util.writeJsonString(writer, core_api.redactStringBounded(text, &redacted_buf));
    } else {
        try writer.writeAll("null");
    }
}

fn sanitizeRemediationText(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var buffer: [512]u8 = undefined;
    const redacted = core_api.redactStringBounded(text, &buffer);
    return try allocator.dupe(u8, redacted);
}

test "rust visibility redacts fake secret from feed reason" {
    const allocator = std.testing.allocator;
    const raw = "blocked OPENAI_API_KEY=sk-fakeSyntheticOpenAIKey1234567890 in command";
    var reason_buf: [512]u8 = undefined;
    const redacted = core_api.redactStringBounded(raw, &reason_buf);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "sk-fakeSyntheticOpenAIKey1234567890") == null);
    _ = allocator;
}

test "rust visibility maps doctor compatible status to healthy" {
    try std.testing.expectEqualStrings("healthy", guiDaemonStatusFromDoctorStatus("compatible"));
    try std.testing.expectEqualStrings("unavailable", guiDaemonStatusFromDoctorStatus("unavailable"));
}
