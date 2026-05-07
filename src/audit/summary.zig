const std = @import("std");

const core = @import("../core/mod.zig");
const redact_bridge = @import("redact_bridge.zig");

pub const summary_hash_len = 64;
pub const SummaryHashHex = [summary_hash_len]u8;

pub const SummaryInput = struct {
    session: core.session.Session,
    status: core.supervisor.ChildStatus,
    event_count: usize,
    final_event_hash: []const u8,
    policy: []const u8 = "none",
};

pub fn summaryHash(canonical_summary_without_hash: []const u8) SummaryHashHex {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(canonical_summary_without_hash);

    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return std.fmt.bytesToHex(digest, .lower);
}

pub fn writeFiles(allocator: std.mem.Allocator, session_dir_path: []const u8, input: SummaryInput) !void {
    const json_path = try std.fs.path.join(allocator, &.{ session_dir_path, "summary.json" });
    defer allocator.free(json_path);
    const md_path = try std.fs.path.join(allocator, &.{ session_dir_path, "summary.md" });
    defer allocator.free(md_path);

    {
        const file = try std.fs.cwd().createFile(json_path, .{});
        defer file.close();
        var list: std.ArrayList(u8) = .empty;
        defer list.deinit(allocator);
        try writeJsonAlloc(allocator, list.writer(allocator), input);
        try file.writeAll(list.items);
        try file.writeAll("\n");
        try file.sync();
    }
    {
        const file = try std.fs.cwd().createFile(md_path, .{});
        defer file.close();
        var list: std.ArrayList(u8) = .empty;
        defer list.deinit(allocator);
        try writeMarkdown(list.writer(allocator), input);
        try file.writeAll(list.items);
        try file.sync();
    }
}

pub fn updateFinalHash(allocator: std.mem.Allocator, session_dir_path: []const u8, event_count: usize, final_event_hash: []const u8) !void {
    const json_path = try std.fs.path.join(allocator, &.{ session_dir_path, "summary.json" });
    defer allocator.free(json_path);
    const md_path = try std.fs.path.join(allocator, &.{ session_dir_path, "summary.md" });
    defer allocator.free(md_path);
    const text = try std.fs.cwd().readFileAlloc(allocator, json_path, core.limits.max_event_field_len);
    defer allocator.free(text);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, text, .{});
    defer parsed.deinit();
    const object = try expectObject(parsed.value);
    try verifyStoredSummaryHash(allocator, parsed.value);

    var canonical: std.ArrayList(u8) = .empty;
    defer canonical.deinit(allocator);
    try writeCanonicalSummaryFromJson(canonical.writer(allocator), object, event_count, final_event_hash);
    const computed_summary_hash = summaryHash(canonical.items);

    const file = try std.fs.cwd().createFile(json_path, .{});
    defer file.close();
    var file_buf: [4096]u8 = undefined;
    var file_writer = file.writer(&file_buf);
    try writeSummaryWithHash(&file_writer.interface, canonical.items, &computed_summary_hash);
    try file_writer.interface.writeByte('\n');
    try file_writer.interface.flush();
    try file.sync();

    var md: std.ArrayList(u8) = .empty;
    defer md.deinit(allocator);
    const md_writer = md.writer(allocator);
    try md_writer.print("# Aegis Session {s}\n\n- Command: `", .{object.get("session_id").?.string});
    try writeCommandDisplayFromJson(md_writer, object.get("command").?.array);
    try md_writer.print("`\n- Policy: {s}\n- Mode: {s}\n- Status: {s} {d}\n- Events: {d}\n- Final event hash: `{s}`\n", .{
        object.get("policy").?.string,
        object.get("mode").?.string,
        object.get("status").?.object.get("kind").?.string,
        object.get("status").?.object.get("code").?.integer,
        event_count,
        final_event_hash,
    });
    {
        const md_file = try std.fs.cwd().createFile(md_path, .{});
        defer md_file.close();
        try md_file.writeAll(md.items);
        try md_file.sync();
    }
}

pub fn writeJson(writer: anytype, input: SummaryInput) !void {
    try writeJsonAlloc(std.heap.page_allocator, writer, input);
}

pub fn writeJsonAlloc(allocator: std.mem.Allocator, writer: anytype, input: SummaryInput) !void {
    var canonical: std.ArrayList(u8) = .empty;
    defer canonical.deinit(allocator);
    try writeCanonicalSummaryInput(canonical.writer(allocator), input);
    const computed_summary_hash = summaryHash(canonical.items);
    try writeSummaryWithHash(writer, canonical.items, &computed_summary_hash);
}

fn writeCanonicalSummaryInput(writer: anytype, input: SummaryInput) !void {
    var started_buf: [32]u8 = undefined;
    const started = try input.session.started_at.formatIso(&started_buf);
    var ended_buf: [32]u8 = undefined;
    const ended = if (input.session.ended_at) |ended_at| try ended_at.formatIso(&ended_buf) else null;

    try writer.writeByte('{');
    try writer.writeAll("\"version\":1,\"session_id\":");
    try core.util.writeJsonString(writer, input.session.id.slice());
    try writer.writeAll(",\"started_at\":");
    try core.util.writeJsonString(writer, started);
    try writer.writeAll(",\"ended_at\":");
    if (ended) |value| try core.util.writeJsonString(writer, value) else try writer.writeAll("null");
    try writer.writeAll(",\"workspace_root\":");
    try core.util.writeJsonString(writer, input.session.workspace_root);
    try writer.writeAll(",\"mode\":");
    try core.util.writeJsonString(writer, input.session.mode.toString());
    try writer.writeAll(",\"policy\":");
    var policy_buf: [256]u8 = undefined;
    try core.util.writeJsonString(writer, redact_bridge.redactStringBounded(input.policy, &policy_buf));
    try writer.writeAll(",\"command\":");
    try writeCommandArray(writer, input.session.command, input.session.args);
    try writer.writeAll(",\"status\":");
    try writeStatus(writer, input.status);
    try writer.print(",\"event_count\":{d},\"final_event_hash\":", .{input.event_count});
    try core.util.writeJsonString(writer, input.final_event_hash);
    try writer.writeByte('}');
}

fn writeSummaryWithHash(writer: anytype, canonical: []const u8, computed_summary_hash: []const u8) !void {
    if (canonical.len == 0 or canonical[canonical.len - 1] != '}') return error.InvalidEventSchema;
    try writer.writeAll(canonical[0 .. canonical.len - 1]);
    try writer.writeAll(",\"summary_hash\":");
    try core.util.writeJsonString(writer, computed_summary_hash);
    try writer.writeByte('}');
}

pub fn canonicalFromJsonValue(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    const object = try expectObject(value);
    try writeCanonicalSummaryFromJson(list.writer(allocator), object, null, null);
    return try list.toOwnedSlice(allocator);
}

fn verifyStoredSummaryHash(allocator: std.mem.Allocator, value: std.json.Value) !void {
    const object = try expectObject(value);
    const stored_hash = try expectString(try requiredField(object, "summary_hash"));
    const canonical = try canonicalFromJsonValue(allocator, value);
    defer allocator.free(canonical);
    const computed_hash = summaryHash(canonical);
    if (!std.mem.eql(u8, stored_hash, &computed_hash)) return error.InvalidEventSchema;
}

fn writeCanonicalSummaryFromJson(
    writer: anytype,
    object: std.json.ObjectMap,
    event_count_override: ?usize,
    final_hash_override: ?[]const u8,
) !void {
    try rejectUnknownKeys(object, &.{
        "version",
        "session_id",
        "started_at",
        "ended_at",
        "workspace_root",
        "mode",
        "policy",
        "command",
        "status",
        "event_count",
        "final_event_hash",
        "summary_hash",
    });
    if (object.get("summary_hash")) |hash_value| _ = try expectString(hash_value);

    try writer.writeByte('{');
    try writer.print("\"version\":{d}", .{try expectInteger(try requiredField(object, "version"))});
    try writeStringValueField(writer, "session_id", try requiredField(object, "session_id"));
    try writeStringValueField(writer, "started_at", try requiredField(object, "started_at"));
    try writer.writeAll(",\"ended_at\":");
    try writeNullableJsonValue(writer, try requiredField(object, "ended_at"));
    try writeStringValueField(writer, "workspace_root", try requiredField(object, "workspace_root"));
    try writeStringValueField(writer, "mode", try requiredField(object, "mode"));
    try writeStringValueField(writer, "policy", try requiredField(object, "policy"));
    try writer.writeAll(",\"command\":");
    try writeCommandJsonValue(writer, try expectArray(try requiredField(object, "command")));
    try writer.writeAll(",\"status\":");
    try writeStatusJsonValue(writer, try expectObject(try requiredField(object, "status")));
    const event_count = if (event_count_override) |count| count else count: {
        const parsed_count = try expectInteger(try requiredField(object, "event_count"));
        if (parsed_count < 0) return error.InvalidEventSchema;
        break :count @as(usize, @intCast(parsed_count));
    };
    try writer.print(",\"event_count\":{d},\"final_event_hash\":", .{event_count});
    if (final_hash_override) |final_hash| {
        try core.util.writeJsonString(writer, final_hash);
    } else {
        try core.util.writeJsonString(writer, try expectString(try requiredField(object, "final_event_hash")));
    }
    try writer.writeByte('}');
}

pub fn writeMarkdown(writer: anytype, input: SummaryInput) !void {
    var policy_buf: [256]u8 = undefined;
    const safe_policy = redact_bridge.redactStringBounded(input.policy, &policy_buf);
    try writer.print(
        \\# Aegis Session {s}
        \\
        \\- Command: `
    , .{input.session.id.slice()});
    try writeCommandDisplay(writer, input.session.command, input.session.args);
    try writer.print(
        \\`
        \\- Policy: {s}
        \\- Mode: {s}
        \\- Status: {s}
        \\- Events: {d}
        \\- Final event hash: `{s}`
        \\
    , .{
        safe_policy,
        input.session.mode.toString(),
        statusText(input.status),
        input.event_count,
        input.final_event_hash,
    });
}

fn writeCommandArray(writer: anytype, command: []const u8, args: []const []const u8) !void {
    try writer.writeByte('[');
    var command_buf: [256]u8 = undefined;
    try core.util.writeJsonString(writer, redact_bridge.redactStringBounded(command, &command_buf));
    for (args) |arg| {
        try writer.writeByte(',');
        var arg_buf: [256]u8 = undefined;
        try core.util.writeJsonString(writer, redact_bridge.redactStringBounded(arg, &arg_buf));
    }
    try writer.writeByte(']');
}

fn writeStatus(writer: anytype, status: core.supervisor.ChildStatus) !void {
    try writer.writeByte('{');
    switch (status) {
        .exited => |code| try writer.print("\"kind\":\"exit\",\"code\":{d}", .{code}),
        .signal => |signal| try writer.print("\"kind\":\"signal\",\"code\":{d}", .{signal}),
        .stopped => |signal| try writer.print("\"kind\":\"stopped\",\"code\":{d}", .{signal}),
        .unknown => |code| try writer.print("\"kind\":\"unknown\",\"code\":{d}", .{code}),
    }
    try writer.writeByte('}');
}

fn expectObject(value: std.json.Value) !std.json.ObjectMap {
    return switch (value) {
        .object => |object| object,
        else => error.InvalidEventSchema,
    };
}

fn expectArray(value: std.json.Value) !std.json.Array {
    return switch (value) {
        .array => |array| array,
        else => error.InvalidEventSchema,
    };
}

fn expectString(value: std.json.Value) ![]const u8 {
    return switch (value) {
        .string => |string| string,
        else => error.InvalidEventSchema,
    };
}

fn expectInteger(value: std.json.Value) !i64 {
    return switch (value) {
        .integer => |integer| integer,
        else => error.InvalidEventSchema,
    };
}

fn requiredField(object: std.json.ObjectMap, name: []const u8) !std.json.Value {
    return object.get(name) orelse error.InvalidEventSchema;
}

fn rejectUnknownKeys(object: std.json.ObjectMap, allowed: []const []const u8) !void {
    var iterator = object.iterator();
    while (iterator.next()) |entry| {
        var known = false;
        for (allowed) |name| {
            if (std.mem.eql(u8, entry.key_ptr.*, name)) {
                known = true;
                break;
            }
        }
        if (!known) return error.InvalidEventSchema;
    }
}

fn writeStringValueField(writer: anytype, name: []const u8, value: std.json.Value) !void {
    try writer.writeByte(',');
    try core.util.writeJsonString(writer, name);
    try writer.writeByte(':');
    try core.util.writeJsonString(writer, try expectString(value));
}

fn writeNullableJsonValue(writer: anytype, value: std.json.Value) !void {
    if (value == .null) try writer.writeAll("null") else try core.util.writeJsonString(writer, try expectString(value));
}

fn writeCommandJsonValue(writer: anytype, command: std.json.Array) !void {
    try writer.writeByte('[');
    for (command.items, 0..) |item, index| {
        if (index > 0) try writer.writeByte(',');
        try core.util.writeJsonString(writer, try expectString(item));
    }
    try writer.writeByte(']');
}

fn writeCommandDisplayFromJson(writer: anytype, command: std.json.Array) !void {
    for (command.items, 0..) |item, index| {
        if (index > 0) try writer.writeByte(' ');
        try writer.writeAll(try expectString(item));
    }
}

fn writeStatusJsonValue(writer: anytype, status: std.json.ObjectMap) !void {
    try rejectUnknownKeys(status, &.{ "kind", "code" });
    try writer.writeByte('{');
    try writer.writeAll("\"kind\":");
    try core.util.writeJsonString(writer, try expectString(try requiredField(status, "kind")));
    try writer.print(",\"code\":{d}", .{try expectInteger(try requiredField(status, "code"))});
    try writer.writeByte('}');
}

pub fn statusText(status: core.supervisor.ChildStatus) []const u8 {
    return switch (status) {
        .exited => |code| if (code == 0) "exit 0" else "exit nonzero",
        .signal => "signal",
        .stopped => "stopped",
        .unknown => "unknown",
    };
}

fn writeCommandDisplay(writer: anytype, command: []const u8, args: []const []const u8) !void {
    var command_buf: [256]u8 = undefined;
    try writer.writeAll(redact_bridge.redactStringBounded(command, &command_buf));
    for (args) |arg| {
        try writer.writeByte(' ');
        var arg_buf: [256]u8 = undefined;
        try writer.writeAll(redact_bridge.redactStringBounded(arg, &arg_buf));
    }
}

test "summary json records final hash and bounded command metadata" {
    const ts = core.time.Timestamp.fromUnixSeconds(1_777_983_130);
    const session: core.session.Session = .{
        .id = try core.session.generateSessionId(ts),
        .started_at = ts,
        .ended_at = ts,
        .command = "echo",
        .args = &.{"hello"},
        .workspace_root = "/tmp/aegis",
        .mode = .observe,
        .platform = core.platform.detectOs(),
    };
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    try writeJson(list.writer(std.testing.allocator), .{
        .session = session,
        .status = .{ .exited = 0 },
        .event_count = 3,
        .final_event_hash = "abc",
    });
    try std.testing.expect(std.mem.indexOf(u8, list.items, "\"final_event_hash\":\"abc\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, list.items, "\"command\":[\"echo\",\"hello\"]") != null);
}

test "summary redacts synthetic secret command metadata" {
    const ts = core.time.Timestamp.fromUnixSeconds(1_777_983_130);
    const session: core.session.Session = .{
        .id = try core.session.generateSessionId(ts),
        .started_at = ts,
        .ended_at = ts,
        .command = "echo",
        .args = &.{"fake_secret_value"},
        .workspace_root = "/tmp/aegis",
        .mode = .observe,
        .platform = core.platform.detectOs(),
    };
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    try writeJson(list.writer(std.testing.allocator), .{
        .session = session,
        .status = .{ .exited = 0 },
        .event_count = 3,
        .final_event_hash = "abc",
    });
    try std.testing.expect(std.mem.indexOf(u8, list.items, "fake_secret_value") == null);
    try std.testing.expect(std.mem.indexOf(u8, list.items, "[REDACTED:") != null);
}

test "update final hash rejects tampered summary before rewriting" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    const session_dir = try std.fs.path.join(std.testing.allocator, &.{ root, ".aegis", "sessions", "summary-tamper" });
    defer std.testing.allocator.free(session_dir);
    try std.fs.cwd().makePath(session_dir);

    const ts = core.time.Timestamp.fromUnixSeconds(1_777_983_130);
    const session: core.session.Session = .{
        .id = try core.session.generateSessionId(ts),
        .started_at = ts,
        .ended_at = ts,
        .command = "echo",
        .args = &.{"hello"},
        .workspace_root = root,
        .mode = .observe,
        .platform = core.platform.detectOs(),
    };
    try writeFiles(std.testing.allocator, session_dir, .{
        .session = session,
        .status = .{ .exited = 0 },
        .event_count = 3,
        .final_event_hash = "abc",
    });

    const summary_path = try std.fs.path.join(std.testing.allocator, &.{ session_dir, "summary.json" });
    defer std.testing.allocator.free(summary_path);
    const original = try std.fs.cwd().readFileAlloc(std.testing.allocator, summary_path, core.limits.max_event_field_len);
    defer std.testing.allocator.free(original);
    const tampered = try std.mem.replaceOwned(u8, std.testing.allocator, original, "hello", "changed");
    defer std.testing.allocator.free(tampered);
    {
        const file = try std.fs.cwd().createFile(summary_path, .{});
        defer file.close();
        try file.writeAll(tampered);
    }

    try std.testing.expectError(error.InvalidEventSchema, updateFinalHash(std.testing.allocator, session_dir, 4, "def"));

    const after = try std.fs.cwd().readFileAlloc(std.testing.allocator, summary_path, core.limits.max_event_field_len);
    defer std.testing.allocator.free(after);
    try std.testing.expect(std.mem.indexOf(u8, after, "changed") != null);
    try std.testing.expect(std.mem.indexOf(u8, after, "\"final_event_hash\":\"def\"") == null);
}
