const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

pub const Metadata = struct {
    product: []const u8 = "orca",
    version: []const u8,
    commit: ?[]const u8,
    target: []const u8,
    target_triple: []const u8,
    build_date: ?[]const u8,
    release_channel: []const u8 = "stable",
    safety_boundary_version: []const u8 = "cli-local-dev-v1",
    safety_boundary: []const u8 = "Orca enforces local command, file, network, MCP, audit, and red-team controls; it does not provide hosted telemetry or cloud enforcement.",
};

pub fn current() Metadata {
    const target = targetName();
    return .{
        .version = build_options.version,
        .commit = optionalValue(build_options.commit),
        .target = target,
        .target_triple = target,
        .build_date = optionalValue(build_options.build_date),
    };
}

pub fn writePlain(writer: anytype, metadata: Metadata) !void {
    try writer.print("{s} {s} ({s}, {s})\n", .{ metadata.product, metadata.version, metadata.release_channel, metadata.target_triple });
}

pub fn writeJson(writer: anytype, metadata: Metadata) !void {
    try writer.writeAll("{\n");
    try writer.writeAll("  \"product\": ");
    try writeJsonString(writer, metadata.product);
    try writer.writeAll(",\n  \"version\": ");
    try writeJsonString(writer, metadata.version);
    try writer.writeAll(",\n  \"commit\": ");
    try writeJsonNullableString(writer, metadata.commit);
    try writer.writeAll(",\n  \"target\": ");
    try writeJsonString(writer, metadata.target);
    try writer.writeAll(",\n  \"target_triple\": ");
    try writeJsonString(writer, metadata.target_triple);
    try writer.writeAll(",\n  \"build_date\": ");
    try writeJsonNullableString(writer, metadata.build_date);
    try writer.writeAll(",\n  \"release_channel\": ");
    try writeJsonString(writer, metadata.release_channel);
    try writer.writeAll(",\n  \"safety_boundary_version\": ");
    try writeJsonString(writer, metadata.safety_boundary_version);
    try writer.writeAll(",\n  \"safety_boundary\": ");
    try writeJsonString(writer, metadata.safety_boundary);
    try writer.writeAll("\n}\n");
}

fn optionalValue(value: []const u8) ?[]const u8 {
    if (value.len == 0 or std.mem.eql(u8, value, "unknown")) return null;
    return value;
}

fn targetName() []const u8 {
    return @tagName(builtin.cpu.arch) ++ "-" ++ @tagName(builtin.os.tag);
}

fn writeJsonNullableString(writer: anytype, value: ?[]const u8) !void {
    if (value) |actual| {
        try writeJsonString(writer, actual);
    } else {
        try writer.writeAll("null");
    }
}

fn writeJsonString(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |byte| {
        switch (byte) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0...8, 11...12, 14...0x1f => try writer.print("\\u{x:0>4}", .{byte}),
            else => try writer.writeByte(byte),
        }
    }
    try writer.writeByte('"');
}

test "version json writer emits valid object shape with null metadata" {
    var buffer: [512]u8 = undefined;
    var stream_writer: std.Io.Writer = .fixed(&buffer);

    try writeJson(&stream_writer, .{
        .version = "1.0.0",
        .commit = null,
        .target = "x86_64-linux",
        .target_triple = "x86_64-linux",
        .build_date = null,
    });

    const json = stream_writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, json, "\"product\": \"orca\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"version\": \"1.0.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"commit\": null") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"target\": \"x86_64-linux\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"target_triple\": \"x86_64-linux\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"build_date\": null") != null);

    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value.object.get("version") != null);
}
