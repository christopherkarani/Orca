const std = @import("std");

const core = @import("../core/mod.zig");
const redact_bridge = @import("redact_bridge.zig");

pub const SummaryInput = struct {
    session: core.session.Session,
    status: core.supervisor.ChildStatus,
    event_count: usize,
    final_event_hash: []const u8,
    policy: []const u8 = "none",
};

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
        try writeJson(list.writer(allocator), input);
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

pub fn writeJson(writer: anytype, input: SummaryInput) !void {
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
