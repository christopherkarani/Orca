const std = @import("std");

const core = @import("../core/mod.zig");
const hash_chain = @import("hash_chain.zig");

pub const ReplayOptions = struct {
    session: []const u8 = "last",
    only_denied: bool = false,
    verify: bool = false,
};

pub const ReplayEvent = struct {
    raw: []u8,
    timestamp: []u8,
    event_type: []u8,
    target_value: []u8,
    decision_result: ?[]u8,

    fn deinit(self: ReplayEvent, allocator: std.mem.Allocator) void {
        allocator.free(self.raw);
        allocator.free(self.timestamp);
        allocator.free(self.event_type);
        allocator.free(self.target_value);
        if (self.decision_result) |value| allocator.free(value);
    }
};

pub const ReplaySession = struct {
    allocator: std.mem.Allocator,
    session_id: []u8,
    session_dir_path: []u8,
    command_display: []u8,
    policy: []u8,
    status_display: []u8,
    events: []ReplayEvent,
    verified: bool = false,

    pub fn deinit(self: *ReplaySession) void {
        for (self.events) |ev| ev.deinit(self.allocator);
        self.allocator.free(self.events);
        self.allocator.free(self.session_id);
        self.allocator.free(self.session_dir_path);
        self.allocator.free(self.command_display);
        self.allocator.free(self.policy);
        self.allocator.free(self.status_display);
        self.* = undefined;
    }
};

pub fn load(allocator: std.mem.Allocator, workspace_root: []const u8, options: ReplayOptions) !ReplaySession {
    const session_id = try resolveSessionId(allocator, workspace_root, options.session);
    errdefer allocator.free(session_id);
    const session_dir_path = try std.fs.path.join(allocator, &.{ workspace_root, ".aegis", "sessions", session_id });
    errdefer allocator.free(session_dir_path);

    const verify_result = try verifySessionDir(allocator, session_dir_path);
    defer verify_result.deinit(allocator);
    if (options.verify and !verify_result.ok) return error.HashVerificationFailed;

    const events = try loadEvents(allocator, session_dir_path, options.only_denied);
    errdefer {
        for (events) |ev| ev.deinit(allocator);
        allocator.free(events);
    }
    const summary = try readSummaryFields(allocator, session_dir_path);
    errdefer summary.deinit(allocator);

    return .{
        .allocator = allocator,
        .session_id = session_id,
        .session_dir_path = session_dir_path,
        .command_display = summary.command_display,
        .policy = summary.policy,
        .status_display = summary.status_display,
        .events = events,
        .verified = verify_result.ok,
    };
}

pub fn writeHuman(writer: anytype, session: ReplaySession, show_verify: bool) !void {
    try writer.print(
        \\Session: {s}
        \\Command: {s}
        \\Policy: {s}
        \\Status: {s}
        \\
    , .{
        session.session_id,
        session.command_display,
        session.policy,
        session.status_display,
    });

    for (session.events) |ev| {
        try writer.print("{s}  {s}", .{ eventTime(ev.timestamp), ev.event_type });
        if (ev.target_value.len > 0) try writer.print("     {s}", .{ev.target_value});
        try writer.writeByte('\n');
    }
    if (show_verify) {
        try writer.print("\nHash chain: {s}\n", .{if (session.verified) "verified" else "not verified"});
    }
}

pub fn writeJson(writer: anytype, session: ReplaySession) !void {
    try writer.writeByte('[');
    for (session.events, 0..) |ev, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.writeAll(ev.raw);
    }
    try writer.writeAll("]\n");
}

pub const VerifyResult = struct {
    ok: bool,
    reason: ?[]u8 = null,

    pub fn deinit(self: VerifyResult, allocator: std.mem.Allocator) void {
        if (self.reason) |reason| allocator.free(reason);
    }
};

pub fn verifySessionDir(allocator: std.mem.Allocator, session_dir_path: []const u8) !VerifyResult {
    const events_path = try std.fs.path.join(allocator, &.{ session_dir_path, "events.jsonl" });
    defer allocator.free(events_path);
    const events_text = try std.fs.cwd().readFileAlloc(allocator, events_path, core.limits.max_mcp_message_len);
    defer allocator.free(events_text);

    var previous_hash: ?hash_chain.HashHex = null;
    var last_hash: ?hash_chain.HashHex = null;
    var lines = std.mem.splitScalar(u8, events_text, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch {
            return fail(allocator, "invalid event JSON");
        };
        defer parsed.deinit();
        const object = expectObject(parsed.value) catch return fail(allocator, "malformed event");

        const previous_value = object.get("previous_hash") orelse return fail(allocator, "missing previous_hash");
        var expected_previous: ?[]const u8 = null;
        if (previous_hash) |*hash| expected_previous = hash[0..];
        if (!jsonNullableStringEquals(previous_value, expected_previous)) {
            return fail(allocator, "invalid previous_hash");
        }

        const canonical = canonicalFromJsonValue(allocator, parsed.value) catch |err| switch (err) {
            error.InvalidEventSchema => return fail(allocator, "malformed event"),
            else => return err,
        };
        defer allocator.free(canonical);
        const computed = hash_chain.eventHash(expected_previous, canonical);
        const event_hash_value = object.get("event_hash") orelse return fail(allocator, "missing event_hash");
        if (event_hash_value != .string or !std.mem.eql(u8, event_hash_value.string, &computed)) {
            return fail(allocator, "invalid event_hash");
        }

        previous_hash = computed;
        last_hash = computed;
    }

    const summary_hash = readSummaryFinalHash(allocator, session_dir_path) catch |err| switch (err) {
        error.FileNotFound => return fail(allocator, "missing summary.json"),
        error.InvalidEventSchema => return fail(allocator, "malformed summary.json"),
        else => return err,
    };
    defer allocator.free(summary_hash);
    if (last_hash) |hash| {
        if (!std.mem.eql(u8, summary_hash, &hash)) return fail(allocator, "summary final hash mismatch");
    } else if (summary_hash.len != 0) {
        return fail(allocator, "summary final hash mismatch");
    }

    return .{ .ok = true };
}

fn fail(allocator: std.mem.Allocator, reason: []const u8) !VerifyResult {
    return .{ .ok = false, .reason = try allocator.dupe(u8, reason) };
}

fn canonicalFromJsonValue(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    const writer = list.writer(allocator);
    const object = try expectObject(value);

    try writer.writeByte('{');
    try writer.print("\"version\":{d}", .{try expectInteger(try requiredField(object, "version"))});
    try writeStringField(writer, "session_id", try requiredField(object, "session_id"));
    try writeStringField(writer, "event_id", try requiredField(object, "event_id"));
    try writeStringField(writer, "timestamp", try requiredField(object, "timestamp"));
    try writeStringField(writer, "type", try requiredField(object, "type"));
    try writer.writeAll(",\"actor\":");
    try writeActorValue(writer, try requiredField(object, "actor"));
    try writer.writeAll(",\"target\":");
    try writeTargetValue(writer, try requiredField(object, "target"));
    try writer.writeAll(",\"decision\":");
    try writeDecisionValue(writer, try requiredField(object, "decision"));
    try writer.writeAll(",\"redactions\":");
    try writeRedactionsValue(writer, try requiredField(object, "redactions"));
    try writer.writeAll(",\"previous_hash\":");
    try writeNullableValue(writer, try requiredField(object, "previous_hash"));
    try writer.writeByte('}');
    return try list.toOwnedSlice(allocator);
}

fn writeStringField(writer: anytype, name: []const u8, value: std.json.Value) !void {
    try writer.writeByte(',');
    try core.util.writeJsonString(writer, name);
    try writer.writeByte(':');
    try core.util.writeJsonString(writer, try expectString(value));
}

fn writeActorValue(writer: anytype, value: std.json.Value) !void {
    const object = try expectObject(value);
    try writer.writeByte('{');
    try writer.writeAll("\"kind\":");
    try core.util.writeJsonString(writer, try expectString(try requiredField(object, "kind")));
    try writer.writeAll(",\"id\":");
    try writeNullableValue(writer, try requiredField(object, "id"));
    try writer.writeAll(",\"display\":");
    try writeNullableValue(writer, try requiredField(object, "display"));
    try writer.writeByte('}');
}

fn writeTargetValue(writer: anytype, value: std.json.Value) !void {
    const object = try expectObject(value);
    try writer.writeByte('{');
    try writer.writeAll("\"kind\":");
    try core.util.writeJsonString(writer, try expectString(try requiredField(object, "kind")));
    try writer.writeAll(",\"value\":");
    try core.util.writeJsonString(writer, try expectString(try requiredField(object, "value")));
    try writer.writeByte('}');
}

fn writeDecisionValue(writer: anytype, value: std.json.Value) !void {
    if (value == .null) {
        try writer.writeAll("null");
        return;
    }
    const object = try expectObject(value);
    try writer.writeByte('{');
    try writer.writeAll("\"result\":");
    try core.util.writeJsonString(writer, try expectString(try requiredField(object, "result")));
    try writer.writeAll(",\"rule_id\":");
    try writeNullableValue(writer, try requiredField(object, "rule_id"));
    try writer.writeAll(",\"reason\":");
    try core.util.writeJsonString(writer, try expectString(try requiredField(object, "reason")));
    try writer.writeAll(",\"risk_score\":");
    const risk = try requiredField(object, "risk_score");
    if (risk == .null) try writer.writeAll("null") else try writer.print("{d}", .{try expectInteger(risk)});
    try writer.print(",\"requires_user\":{},\"ci_may_proceed\":{}", .{
        try expectBool(try requiredField(object, "requires_user")),
        try expectBool(try requiredField(object, "ci_may_proceed")),
    });
    try writer.writeByte('}');
}

fn writeRedactionsValue(writer: anytype, value: std.json.Value) !void {
    const object = try expectObject(value);
    try writer.print("{{\"count\":{d},\"labels\":[", .{try expectInteger(try requiredField(object, "count"))});
    const labels = try expectArray(try requiredField(object, "labels"));
    for (labels.items, 0..) |label, index| {
        if (index > 0) try writer.writeByte(',');
        try core.util.writeJsonString(writer, try expectString(label));
    }
    try writer.writeAll("]}");
}

fn writeNullableValue(writer: anytype, value: std.json.Value) !void {
    if (value == .null) {
        try writer.writeAll("null");
    } else {
        try core.util.writeJsonString(writer, try expectString(value));
    }
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

fn expectBool(value: std.json.Value) !bool {
    return switch (value) {
        .bool => |boolean| boolean,
        else => error.InvalidEventSchema,
    };
}

fn requiredField(object: std.json.ObjectMap, name: []const u8) !std.json.Value {
    return object.get(name) orelse error.InvalidEventSchema;
}

fn jsonNullableStringEquals(value: std.json.Value, expected: ?[]const u8) bool {
    if (expected) |string| return value == .string and std.mem.eql(u8, value.string, string);
    return value == .null;
}

fn resolveSessionId(allocator: std.mem.Allocator, workspace_root: []const u8, requested: []const u8) ![]u8 {
    if (!std.mem.eql(u8, requested, "last")) return try allocator.dupe(u8, requested);
    const last_path = try std.fs.path.join(allocator, &.{ workspace_root, ".aegis", "last" });
    defer allocator.free(last_path);
    const text = try std.fs.cwd().readFileAlloc(allocator, last_path, core.limits.max_session_id_len + 2);
    defer allocator.free(text);
    return try allocator.dupe(u8, std.mem.trim(u8, text, " \t\r\n"));
}

fn loadEvents(allocator: std.mem.Allocator, session_dir_path: []const u8, only_denied: bool) ![]ReplayEvent {
    const events_path = try std.fs.path.join(allocator, &.{ session_dir_path, "events.jsonl" });
    defer allocator.free(events_path);
    const events_text = try std.fs.cwd().readFileAlloc(allocator, events_path, core.limits.max_mcp_message_len);
    defer allocator.free(events_text);

    var list: std.ArrayList(ReplayEvent) = .empty;
    errdefer {
        for (list.items) |ev| ev.deinit(allocator);
        list.deinit(allocator);
    }

    var lines = std.mem.splitScalar(u8, events_text, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, line, .{});
        defer parsed.deinit();
        if (only_denied and !isDenied(parsed.value)) continue;
        try list.append(allocator, try eventFromJson(allocator, line, parsed.value));
    }

    return try list.toOwnedSlice(allocator);
}

fn eventFromJson(allocator: std.mem.Allocator, raw: []const u8, value: std.json.Value) !ReplayEvent {
    const object = value.object;
    const target = object.get("target").?.object;
    const decision_result = decisionResultFromValue(allocator, object.get("decision").?) catch null;
    return .{
        .raw = try allocator.dupe(u8, raw),
        .timestamp = try allocator.dupe(u8, object.get("timestamp").?.string),
        .event_type = try allocator.dupe(u8, object.get("type").?.string),
        .target_value = try allocator.dupe(u8, target.get("value").?.string),
        .decision_result = decision_result,
    };
}

fn isDenied(value: std.json.Value) bool {
    const object = value.object;
    if (std.mem.endsWith(u8, object.get("type").?.string, "_denied")) return true;
    const decision = object.get("decision") orelse return false;
    if (decision == .null) return false;
    const result = decision.object.get("result") orelse return false;
    return result == .string and std.mem.eql(u8, result.string, "deny");
}

fn decisionResultFromValue(allocator: std.mem.Allocator, value: std.json.Value) !?[]u8 {
    if (value == .null) return null;
    const result = value.object.get("result") orelse return null;
    if (result != .string) return null;
    return try allocator.dupe(u8, result.string);
}

const SummaryFields = struct {
    command_display: []u8,
    policy: []u8,
    status_display: []u8,

    fn deinit(self: SummaryFields, allocator: std.mem.Allocator) void {
        allocator.free(self.command_display);
        allocator.free(self.policy);
        allocator.free(self.status_display);
    }
};

fn readSummaryFields(allocator: std.mem.Allocator, session_dir_path: []const u8) !SummaryFields {
    const summary_path = try std.fs.path.join(allocator, &.{ session_dir_path, "summary.json" });
    defer allocator.free(summary_path);
    const text = try std.fs.cwd().readFileAlloc(allocator, summary_path, core.limits.max_event_field_len);
    defer allocator.free(text);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, text, .{});
    defer parsed.deinit();
    const object = parsed.value.object;

    const command_display = try commandDisplayFromSummary(allocator, object.get("command").?.array);
    errdefer allocator.free(command_display);
    const policy = try allocator.dupe(u8, object.get("policy").?.string);
    errdefer allocator.free(policy);
    const status_display = try statusDisplayFromSummary(allocator, object.get("status").?);
    errdefer allocator.free(status_display);
    return .{ .command_display = command_display, .policy = policy, .status_display = status_display };
}

fn readSummaryFinalHash(allocator: std.mem.Allocator, session_dir_path: []const u8) ![]u8 {
    const summary_path = try std.fs.path.join(allocator, &.{ session_dir_path, "summary.json" });
    defer allocator.free(summary_path);
    const text = try std.fs.cwd().readFileAlloc(allocator, summary_path, core.limits.max_event_field_len);
    defer allocator.free(text);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, text, .{});
    defer parsed.deinit();
    const object = try expectObject(parsed.value);
    return try allocator.dupe(u8, try expectString(try requiredField(object, "final_event_hash")));
}

fn commandDisplayFromSummary(allocator: std.mem.Allocator, command_array: std.json.Array) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    for (command_array.items, 0..) |item, index| {
        if (index > 0) try list.append(allocator, ' ');
        try list.appendSlice(allocator, item.string);
    }
    return try list.toOwnedSlice(allocator);
}

fn statusDisplayFromSummary(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    const object = value.object;
    const kind = object.get("kind").?.string;
    const code = object.get("code").?.integer;
    return try std.fmt.allocPrint(allocator, "{s} {d}", .{ kind, code });
}

fn eventTime(timestamp: []const u8) []const u8 {
    if (timestamp.len >= 19) return timestamp[11..19];
    return timestamp;
}

test "verification detects modified event fields" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    const ts = core.time.Timestamp.fromUnixSeconds(1_777_983_130);
    const session_id = try core.session.generateSessionId(ts);
    const session_dir = try std.fs.path.join(std.testing.allocator, &.{ root, ".aegis", "sessions", session_id.slice() });
    defer std.testing.allocator.free(session_dir);
    try std.fs.cwd().makePath(session_dir);

    const event_path = try std.fs.path.join(std.testing.allocator, &.{ session_dir, "events.jsonl" });
    defer std.testing.allocator.free(event_path);
    const summary_path = try std.fs.path.join(std.testing.allocator, &.{ session_dir, "summary.json" });
    defer std.testing.allocator.free(summary_path);

    const event_text =
        "{\"version\":1,\"session_id\":\"s\",\"event_id\":\"e\",\"timestamp\":\"2026-05-05T12:12:10Z\",\"type\":\"session_start\",\"actor\":{\"kind\":\"aegis\",\"id\":null,\"display\":\"aegis\"},\"target\":{\"kind\":\"session\",\"value\":\"s\"},\"decision\":null,\"redactions\":{\"count\":0,\"labels\":[]},\"previous_hash\":null";
    const hash = blk: {
        const canonical = try std.fmt.allocPrint(std.testing.allocator, "{s}}}", .{event_text});
        defer std.testing.allocator.free(canonical);
        break :blk hash_chain.eventHash(null, canonical);
    };
    {
        const file = try std.fs.cwd().createFile(event_path, .{});
        defer file.close();
        var buf: [1024]u8 = undefined;
        var file_writer = file.writer(&buf);
        try file_writer.interface.print("{s},\"event_hash\":\"{s}\"}}\n", .{ event_text, &hash });
        try file_writer.interface.flush();
    }
    {
        const file = try std.fs.cwd().createFile(summary_path, .{});
        defer file.close();
        var buf: [1024]u8 = undefined;
        var file_writer = file.writer(&buf);
        try file_writer.interface.print("{{\"final_event_hash\":\"{s}\"}}\n", .{&hash});
        try file_writer.interface.flush();
    }
    var ok = try verifySessionDir(std.testing.allocator, session_dir);
    defer ok.deinit(std.testing.allocator);
    try std.testing.expect(ok.ok);

    {
        const file = try std.fs.cwd().createFile(event_path, .{});
        defer file.close();
        var buf: [1024]u8 = undefined;
        var file_writer = file.writer(&buf);
        try file_writer.interface.print("{s},\"event_hash\":\"{s}\"}}\n", .{ "{\"version\":1,\"session_id\":\"tampered\",\"event_id\":\"e\",\"timestamp\":\"2026-05-05T12:12:10Z\",\"type\":\"session_start\",\"actor\":{\"kind\":\"aegis\",\"id\":null,\"display\":\"aegis\"},\"target\":{\"kind\":\"session\",\"value\":\"s\"},\"decision\":null,\"redactions\":{\"count\":0,\"labels\":[]},\"previous_hash\":null", &hash });
        try file_writer.interface.flush();
    }
    var bad = try verifySessionDir(std.testing.allocator, session_dir);
    defer bad.deinit(std.testing.allocator);
    try std.testing.expect(!bad.ok);
}

test "verification reports malformed events instead of panicking" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    const session_dir = try std.fs.path.join(std.testing.allocator, &.{ root, ".aegis", "sessions", "malformed" });
    defer std.testing.allocator.free(session_dir);
    try std.fs.cwd().makePath(session_dir);

    const event_path = try std.fs.path.join(std.testing.allocator, &.{ session_dir, "events.jsonl" });
    defer std.testing.allocator.free(event_path);
    const summary_path = try std.fs.path.join(std.testing.allocator, &.{ session_dir, "summary.json" });
    defer std.testing.allocator.free(summary_path);

    {
        const file = try std.fs.cwd().createFile(event_path, .{});
        defer file.close();
        try file.writeAll("{\"version\":1,\"previous_hash\":null,\"event_hash\":\"abc\"}\n");
    }
    {
        const file = try std.fs.cwd().createFile(summary_path, .{});
        defer file.close();
        try file.writeAll("{\"final_event_hash\":\"abc\"}\n");
    }

    var result = try verifySessionDir(std.testing.allocator, session_dir);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!result.ok);
    try std.testing.expectEqualStrings("malformed event", result.reason.?);
}
