const std = @import("std");
const decision = @import("decision.zig");
const limits = @import("limits.zig");
const session = @import("session.zig");
const time = @import("time.zig");
const types = @import("types.zig");
const util = @import("util.zig");

pub const schema_version: u16 = 1;

pub const EventType = enum {
    session_start,
    session_exit,
    policy_loaded,
    process_launch,
    file_read_attempt,
    file_read_allowed,
    file_read_denied,
    file_write_attempt,
    file_write_staged,
    command_attempt,
    command_allowed,
    command_denied,
    network_connect_attempt,
    network_connect_allowed,
    network_connect_denied,
    mcp_initialize,
    mcp_tools_list,
    mcp_tool_call,
    mcp_resource_read,
    mcp_prompt_get,
    mcp_sampling_request,
    secret_redacted,
    user_approval,
    user_denial,

    pub fn toString(self: EventType) []const u8 {
        return @tagName(self);
    }
};

pub const EventId = struct {
    value: [limits.max_event_id_len]u8,
    len: usize,

    pub fn slice(self: *const EventId) []const u8 {
        return self.value[0..self.len];
    }
};

pub const EventHash = struct {
    value: []const u8,
};

pub const RedactionSummary = struct {
    count: u32 = 0,
    labels: []const []const u8 = &.{},
};

pub const Event = struct {
    schema_version: u16 = schema_version,
    session_id: session.SessionId,
    event_id: EventId,
    timestamp: time.Timestamp,
    event_type: EventType,
    actor: types.Actor,
    target: types.Target,
    decision: ?decision.Decision = null,
    redactions: RedactionSummary = .{},
    previous_hash: ?EventHash = null,
    event_hash: ?EventHash = null,
};

pub fn generateEventId(now: time.Timestamp) !EventId {
    var id: EventId = .{
        .value = undefined,
        .len = 0,
    };
    var timestamp_buf: [32]u8 = undefined;
    const timestamp = try now.formatFilenameSafe(&timestamp_buf);
    var suffix_buf: [8]u8 = undefined;
    const suffix = try util.randomHexSuffix(&suffix_buf);
    const written = try std.fmt.bufPrint(&id.value, "evt_{s}_{s}", .{ timestamp, suffix });
    id.len = written.len;
    return id;
}

test "event type string conversion works" {
    try std.testing.expectEqualStrings("session_start", EventType.session_start.toString());
    try std.testing.expectEqualStrings("mcp_sampling_request", EventType.mcp_sampling_request.toString());
}

test "event ids and model can be created deterministically enough for core tests" {
    const ts = time.Timestamp.fromUnixSeconds(1_777_983_130);
    const sid = try session.generateSessionId(ts);
    const eid = try generateEventId(ts);

    try std.testing.expect(std.mem.startsWith(u8, eid.slice(), "evt_2026-05-05T12-12-10Z_"));

    const ev: Event = .{
        .session_id = sid,
        .event_id = eid,
        .timestamp = ts,
        .event_type = .command_attempt,
        .actor = .{ .kind = .agent, .id = "agent-1" },
        .target = .{ .kind = .command, .value = "zig build" },
        .decision = .{
            .result = .observe,
            .reason = "phase 03 model only",
            .ci_may_proceed = true,
        },
    };

    try std.testing.expectEqual(schema_version, ev.schema_version);
    try std.testing.expectEqual(EventType.command_attempt, ev.event_type);
    try std.testing.expectEqual(types.TargetKind.command, ev.target.kind);
}
