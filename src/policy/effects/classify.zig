//! Combined tool-call classification: catalog name (high) ∪ structural args (medium).

const std = @import("std");
const catalog = @import("catalog.zig");
const structural = @import("structural.zig");
const ids = @import("ids.zig");

pub const ToolArgsView = structural.ToolArgsView;
pub const EffectHit = catalog.EffectHit;
pub const Confidence = catalog.Confidence;

/// Prefer higher confidence when the same effect id is emitted by multiple matchers.
/// Confidence enum order: high < medium < low (lower @intFromEnum = stronger).
pub fn appendUniquePreferHigher(
    allocator: std.mem.Allocator,
    hits: *std.ArrayList(EffectHit),
    hit: EffectHit,
) !void {
    for (hits.items, 0..) |existing, i| {
        if (std.mem.eql(u8, existing.id, hit.id)) {
            if (@intFromEnum(hit.confidence) < @intFromEnum(existing.confidence)) {
                hits.items[i] = hit;
            }
            return;
        }
    }
    try hits.append(allocator, hit);
}

/// Classify a tool call by name and optional args.
/// Returned slice is owned by `allocator`. Matcher/id strings are static.
pub fn classifyToolCall(
    allocator: std.mem.Allocator,
    tool_name: []const u8,
    args: ?ToolArgsView,
) ![]EffectHit {
    // Name catalog first (high confidence).
    const name_hits = try catalog.classifyToolName(allocator, tool_name);
    defer allocator.free(name_hits);

    var hits: std.ArrayList(EffectHit) = .empty;
    errdefer hits.deinit(allocator);

    for (name_hits) |hit| {
        try appendUniquePreferHigher(allocator, &hits, hit);
    }

    if (args) |view| {
        const struct_hits = try structural.classifyArgs(allocator, tool_name, view);
        defer allocator.free(struct_hits);
        for (struct_hits) |hit| {
            try appendUniquePreferHigher(allocator, &hits, hit);
        }
    }

    for (hits.items) |hit| {
        std.debug.assert(ids.isKnownEffectId(hit.id));
    }
    return try hits.toOwnedSlice(allocator);
}

/// Name-only classification (Phase A compatible wrapper).
pub fn classifyToolName(allocator: std.mem.Allocator, tool_name: []const u8) ![]EffectHit {
    return classifyToolCall(allocator, tool_name, null);
}

test "notify + to/body classifies as comms.message medium" {
    const keys = [_][]const u8{ "to", "body" };
    const hits = try classifyToolCall(std.testing.allocator, "notify", .{ .keys = &keys });
    defer std.testing.allocator.free(hits);
    try std.testing.expect(hits.len >= 1);
    var found = false;
    for (hits) |h| {
        if (std.mem.eql(u8, h.id, "comms.message")) {
            found = true;
            try std.testing.expect(h.confidence == .medium);
            try std.testing.expect(std.mem.startsWith(u8, h.matcher, "structural."));
        }
    }
    try std.testing.expect(found);
}

test "send_email without args still high catalog" {
    const hits = try classifyToolCall(std.testing.allocator, "send_email", .{});
    defer std.testing.allocator.free(hits);
    try std.testing.expect(hits.len >= 1);
    try std.testing.expectEqualStrings("comms.message", hits[0].id);
    try std.testing.expect(hits[0].confidence == .high);
}

test "send_email with args keeps high over structural" {
    const keys = [_][]const u8{ "to", "body" };
    const hits = try classifyToolCall(std.testing.allocator, "send_email", .{ .keys = &keys });
    defer std.testing.allocator.free(hits);
    try std.testing.expect(hits.len >= 1);
    try std.testing.expectEqualStrings("comms.message", hits[0].id);
    try std.testing.expect(hits[0].confidence == .high);
}

test "empty args name-only for notify yields no hits" {
    const hits = try classifyToolCall(std.testing.allocator, "notify", .{});
    defer std.testing.allocator.free(hits);
    // notify is not in catalog
    try std.testing.expectEqual(@as(usize, 0), hits.len);
}

test "classifyToolName wrapper matches catalog for known tools" {
    const hits = try classifyToolName(std.testing.allocator, "post_twitter");
    defer std.testing.allocator.free(hits);
    try std.testing.expect(hits.len >= 1);
    try std.testing.expectEqualStrings("comms.publish", hits[0].id);
}
