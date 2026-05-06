const std = @import("std");

const core = @import("../core/mod.zig");
const redact_bridge = @import("redact_bridge.zig");

pub const hex_hash_len = 64;
pub const HashHex = [hex_hash_len]u8;

pub fn eventHash(previous_hash: ?[]const u8, canonical_event_without_hash: []const u8) HashHex {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    if (previous_hash) |hash| hasher.update(hash);
    hasher.update(canonical_event_without_hash);

    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return std.fmt.bytesToHex(digest, .lower);
}

pub fn writeCanonicalEventWithoutHash(writer: anytype, ev: core.event.Event, previous_hash: ?[]const u8) !void {
    try writeEventFields(writer, ev, previous_hash, null);
}

pub fn writeEventJsonLine(writer: anytype, ev: core.event.Event, previous_hash: ?[]const u8, event_hash_value: []const u8) !void {
    try writeEventFields(writer, ev, previous_hash, event_hash_value);
    try writer.writeByte('\n');
}

fn writeEventFields(writer: anytype, ev: core.event.Event, previous_hash: ?[]const u8, event_hash_value: ?[]const u8) !void {
    var timestamp_buf: [32]u8 = undefined;
    const timestamp = try ev.timestamp.formatIso(&timestamp_buf);

    try writer.writeByte('{');
    try writer.print("\"version\":{d}", .{ev.schema_version});
    try writer.writeAll(",\"session_id\":");
    try core.util.writeJsonString(writer, ev.session_id.slice());
    try writer.writeAll(",\"event_id\":");
    try core.util.writeJsonString(writer, ev.event_id.slice());
    try writer.writeAll(",\"timestamp\":");
    try core.util.writeJsonString(writer, timestamp);
    try writer.writeAll(",\"type\":");
    try core.util.writeJsonString(writer, ev.event_type.toString());
    try writer.writeAll(",\"actor\":");
    try writeActor(writer, ev.actor);
    try writer.writeAll(",\"target\":");
    try writeTarget(writer, ev.target);
    try writer.writeAll(",\"decision\":");
    try writeDecision(writer, ev.decision);
    try writer.writeAll(",\"redactions\":");
    try writeRedactions(writer, ev.redactions);
    try writer.writeAll(",\"previous_hash\":");
    try writeNullableString(writer, previous_hash);
    if (event_hash_value) |hash| {
        try writer.writeAll(",\"event_hash\":");
        try core.util.writeJsonString(writer, hash);
    }
    try writer.writeByte('}');
}

fn writeActor(writer: anytype, actor: core.types.Actor) !void {
    try writer.writeByte('{');
    try writer.writeAll("\"kind\":");
    try core.util.writeJsonString(writer, @tagName(actor.kind));
    try writer.writeAll(",\"id\":");
    try writeNullableString(writer, actor.id);
    try writer.writeAll(",\"display\":");
    try writeNullableString(writer, actor.display);
    try writer.writeByte('}');
}

fn writeTarget(writer: anytype, target: core.types.Target) !void {
    try writer.writeByte('{');
    try writer.writeAll("\"kind\":");
    try core.util.writeJsonString(writer, @tagName(target.kind));
    try writer.writeAll(",\"value\":");
    try core.util.writeJsonString(writer, redact_bridge.redactString(target.value));
    try writer.writeByte('}');
}

fn writeDecision(writer: anytype, maybe_decision: ?core.decision.Decision) !void {
    const decision = maybe_decision orelse {
        try writer.writeAll("null");
        return;
    };
    try writer.writeByte('{');
    try writer.writeAll("\"result\":");
    try core.util.writeJsonString(writer, decision.result.toString());
    try writer.writeAll(",\"rule_id\":");
    try writeNullableString(writer, decision.rule_id);
    try writer.writeAll(",\"reason\":");
    try core.util.writeJsonString(writer, redact_bridge.redactString(decision.reason));
    try writer.writeAll(",\"risk_score\":");
    if (decision.risk_score) |score| {
        try writer.print("{d}", .{score});
    } else {
        try writer.writeAll("null");
    }
    try writer.print(",\"requires_user\":{},\"ci_may_proceed\":{}", .{ decision.requires_user, decision.ci_may_proceed });
    try writer.writeByte('}');
}

fn writeRedactions(writer: anytype, redactions: core.event.RedactionSummary) !void {
    try writer.print("{{\"count\":{d},\"labels\":[", .{redactions.count});
    for (redactions.labels, 0..) |label, index| {
        if (index > 0) try writer.writeByte(',');
        try core.util.writeJsonString(writer, label);
    }
    try writer.writeAll("]}");
}

fn writeNullableString(writer: anytype, value: ?[]const u8) !void {
    if (value) |string| {
        try core.util.writeJsonString(writer, redact_bridge.redactString(string));
    } else {
        try writer.writeAll("null");
    }
}

pub fn canonicalEventAlloc(allocator: std.mem.Allocator, ev: core.event.Event, previous_hash: ?[]const u8) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try writeCanonicalEventWithoutHash(list.writer(allocator), ev, previous_hash);
    return try list.toOwnedSlice(allocator);
}

test "event serialization is deterministic and excludes event_hash from hash input" {
    const ts = core.time.Timestamp.fromUnixSeconds(1_777_983_130);
    const sid = try core.session.generateSessionId(ts);
    var eid: core.event.EventId = .{ .value = undefined, .len = 0 };
    const eid_text = try std.fmt.bufPrint(&eid.value, "evt_000001", .{});
    eid.len = eid_text.len;
    const ev: core.event.Event = .{
        .session_id = sid,
        .event_id = eid,
        .timestamp = ts,
        .event_type = .process_launch,
        .actor = .{ .kind = .aegis, .display = "aegis" },
        .target = .{ .kind = .command, .value = "echo hello" },
    };

    const first = try canonicalEventAlloc(std.testing.allocator, ev, null);
    defer std.testing.allocator.free(first);
    const second = try canonicalEventAlloc(std.testing.allocator, ev, null);
    defer std.testing.allocator.free(second);

    try std.testing.expectEqualStrings(first, second);
    try std.testing.expect(std.mem.indexOf(u8, first, "event_hash") == null);
    const hash = eventHash(null, first);
    try std.testing.expectEqual(@as(usize, hex_hash_len), hash.len);
}
