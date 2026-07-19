//! Human-readable formatting for effect classification hits.
//! Never includes argument values (secret-safe).

const std = @import("std");
const catalog = @import("catalog.zig");

pub const EffectHit = catalog.EffectHit;

/// Compact single-hit form: `comms.message [high catalog…]`
pub fn formatHitCompact(hit: EffectHit, buf: []u8) ![]const u8 {
    return std.fmt.bufPrint(buf, "{s} [{s} {s}]", .{ hit.id, hit.confidence.toString(), hit.matcher });
}

/// Compact multi-hit form for inspect one-liners, or `(none)` when empty.
pub fn formatHitsCompact(hits: []const EffectHit, allocator: std.mem.Allocator) ![]u8 {
    if (hits.len == 0) return try allocator.dupe(u8, "(none)");

    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);

    for (hits, 0..) |hit, i| {
        if (i > 0) try list.appendSlice(allocator, ", ");
        var scratch: [512]u8 = undefined;
        const piece = try formatHitCompact(hit, &scratch);
        try list.appendSlice(allocator, piece);
    }
    return try list.toOwnedSlice(allocator);
}

/// Multi-line human listing for `tools classify`.
pub fn writeHitsHuman(writer: anytype, hits: []const EffectHit) !void {
    if (hits.len == 0) {
        try writer.writeAll("Effects: (none)\n");
        return;
    }
    try writer.writeAll("Effects:\n");
    for (hits) |hit| {
        try writer.print("  - {s}  confidence={s}  matcher={s}\n", .{
            hit.id,
            hit.confidence.toString(),
            hit.matcher,
        });
    }
}

test "formatHitsCompact empty is none" {
    const text = try formatHitsCompact(&.{}, std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("(none)", text);
}

test "formatHitsCompact includes id confidence matcher not values" {
    const hits = [_]EffectHit{
        .{ .id = "comms.message", .confidence = .high, .matcher = "catalog.comms.message.exact:send_email" },
    };
    const text = try formatHitsCompact(&hits, std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "comms.message") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "high") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "catalog.") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "body") == null);
}

test "writeHitsHuman structural matcher only" {
    var buf: [512]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    const hits = [_]EffectHit{
        .{ .id = "comms.message", .confidence = .medium, .matcher = "structural.comms.message.keys:to+body" },
    };
    try writeHitsHuman(&writer, &hits);
    const out = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, out, "structural.comms.message.keys:to+body") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "SECRET") == null);
}
