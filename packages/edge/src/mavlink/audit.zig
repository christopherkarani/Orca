const std = @import("std");

const framing = @import("framing.zig");
const core = @import("aegis_core");

pub const max_payload_preview_len = 48;

pub const EventKind = enum {
    frame_received,
    frame_invalid,
    message_classified,
    command_mapped,
    command_allowed,
    command_denied,
    command_observed,
    message_forwarded,
    message_blocked,
    mission_upload_started,
    mission_item_observed,
    mission_item_denied,
    mission_upload_completed,
    signing_detected,
    unexpected_endpoint,
    safety_geofence_violation,
    safety_altitude_violation,

    pub fn toString(self: EventKind) []const u8 {
        return switch (self) {
            .frame_received => "mavlink.frame_received",
            .frame_invalid => "mavlink.frame_invalid",
            .message_classified => "mavlink.message_classified",
            .command_mapped => "mavlink.command_mapped",
            .command_allowed => "mavlink.command_allowed",
            .command_denied => "mavlink.command_denied",
            .command_observed => "mavlink.command_observed",
            .message_forwarded => "mavlink.message_forwarded",
            .message_blocked => "mavlink.message_blocked",
            .mission_upload_started => "mavlink.mission_upload_started",
            .mission_item_observed => "mavlink.mission_item_observed",
            .mission_item_denied => "mavlink.mission_item_denied",
            .mission_upload_completed => "mavlink.mission_upload_completed",
            .signing_detected => "mavlink.signing_detected",
            .unexpected_endpoint => "mavlink.unexpected_endpoint",
            .safety_geofence_violation => "safety.geofence_violation",
            .safety_altitude_violation => "safety.altitude_violation",
        };
    }

    pub fn toCoreEventType(self: EventKind) core.event.EventType {
        return switch (self) {
            .frame_received => .mavlink_frame_received,
            .frame_invalid => .mavlink_frame_invalid,
            .message_classified => .mavlink_message_classified,
            .command_mapped => .mavlink_command_mapped,
            .command_allowed => .mavlink_command_allowed,
            .command_denied => .mavlink_command_denied,
            .command_observed => .mavlink_command_observed,
            .message_forwarded => .mavlink_message_forwarded,
            .message_blocked => .mavlink_message_blocked,
            .mission_upload_started => .mavlink_mission_upload_started,
            .mission_item_observed => .mavlink_mission_item_observed,
            .mission_item_denied => .mavlink_mission_item_denied,
            .mission_upload_completed => .mavlink_mission_upload_completed,
            .signing_detected => .mavlink_signing_detected,
            .unexpected_endpoint => .mavlink_unexpected_endpoint,
            .safety_geofence_violation => .safety_geofence_violation,
            .safety_altitude_violation => .safety_altitude_violation,
        };
    }
};

pub const AppendOptions = struct {
    note: []const u8 = "",
    decision: core.decision.DecisionResult = .observe,
};

pub const Record = struct {
    kind: EventKind,
    event_type: []const u8,
    source_sysid: u8,
    source_compid: u8,
    target_sysid: ?u8,
    target_compid: ?u8,
    message_id: u32,
    command_id: ?u16 = null,
    decision: core.decision.DecisionResult,
    payload_preview: []u8,
    note: []u8,

    fn deinit(self: Record, allocator: std.mem.Allocator) void {
        allocator.free(self.payload_preview);
        allocator.free(self.note);
    }
};

pub const AuditLog = struct {
    allocator: std.mem.Allocator,
    records: std.ArrayList(Record) = .empty,

    pub fn init(allocator: std.mem.Allocator) AuditLog {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *AuditLog) void {
        for (self.records.items) |record| record.deinit(self.allocator);
        self.records.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn append(self: *AuditLog, kind: EventKind, frame: framing.Frame, options: AppendOptions) !void {
        var note_buf: [256]u8 = undefined;
        var preview_buf: [max_payload_preview_len * 2]u8 = undefined;
        const redacted_note = core.api.redactStringBounded(options.note, &note_buf);
        const preview = boundedHex(frame.payload, &preview_buf);
        try self.records.append(self.allocator, .{
            .kind = kind,
            .event_type = kind.toString(),
            .source_sysid = frame.sysid,
            .source_compid = frame.compid,
            .target_sysid = frame.targetSystem(),
            .target_compid = frame.targetComponent(),
            .message_id = frame.msgid,
            .decision = options.decision,
            .payload_preview = try self.allocator.dupe(u8, preview),
            .note = try self.allocator.dupe(u8, redacted_note),
        });
    }

    pub fn appendCommand(self: *AuditLog, kind: EventKind, frame: framing.Frame, command_id: ?u16, options: AppendOptions) !void {
        try self.append(kind, frame, options);
        self.records.items[self.records.items.len - 1].command_id = command_id;
    }

    pub fn hasEvent(self: AuditLog, kind: EventKind) bool {
        for (self.records.items) |record| {
            if (record.kind == kind) return true;
        }
        return false;
    }
};

fn boundedHex(payload: []const u8, buffer: []u8) []const u8 {
    const n = if (payload.len > max_payload_preview_len) max_payload_preview_len else payload.len;
    const alphabet = "0123456789abcdef";
    var index: usize = 0;
    var out_len: usize = 0;
    while (index < n and out_len + 2 <= buffer.len) : (index += 1) {
        const byte = payload[index];
        buffer[out_len] = alphabet[byte >> 4];
        buffer[out_len + 1] = alphabet[byte & 0x0f];
        out_len += 2;
    }
    return buffer[0..out_len];
}
