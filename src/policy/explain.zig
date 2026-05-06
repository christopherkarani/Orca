const std = @import("std");

const evaluate = @import("evaluate.zig");
const schema = @import("schema.zig");

pub const ExplainKind = enum {
    file_read,
    file_write,
    env,
    command,
    network,
    mcp,

    pub fn parse(value: []const u8) ?ExplainKind {
        if (std.mem.eql(u8, value, "file.read")) return .file_read;
        if (std.mem.eql(u8, value, "file.write")) return .file_write;
        if (std.mem.eql(u8, value, "env")) return .env;
        if (std.mem.eql(u8, value, "command")) return .command;
        if (std.mem.eql(u8, value, "network")) return .network;
        if (std.mem.eql(u8, value, "mcp")) return .mcp;
        return null;
    }
};

pub fn explain(
    allocator: std.mem.Allocator,
    policy: *const schema.Policy,
    kind: ExplainKind,
    target: []const u8,
) !schema.Evaluation {
    return switch (kind) {
        .file_read => evaluate.fileRead(policy, target, allocator),
        .file_write => evaluate.fileWrite(policy, target, allocator),
        .env => evaluate.env(policy, target, allocator),
        .command => evaluate.command(policy, target, allocator),
        .network => evaluate.network(policy, target, allocator),
        .mcp => evaluate.mcp(policy, target, allocator),
    };
}

pub fn write(writer: anytype, policy: *const schema.Policy, evaluation: schema.Evaluation) !void {
    try writer.print("Decision: {s}\n", .{evaluation.decision.result.toString()});
    try writer.print("Reason: {s}\n", .{evaluation.decision.reason});
    if (evaluation.matched_rule) |rule| {
        try writer.print("Rule: {s}\n", .{rule.id});
        try writer.print("Matched: \"{s}\"\n", .{rule.pattern});
    } else {
        try writer.writeAll("Rule: none\n");
    }
    try writer.print("Mode: {s}\n", .{policy.mode.toString()});
}

test "explanation includes matched rule where possible" {
    const load = @import("load.zig");
    var policy = try load.loadPreset(std.testing.allocator, .strict);
    defer policy.deinit();

    const result = try explain(std.testing.allocator, &policy, .file_read, "~/.ssh/id_ed25519");
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("files.read.deny[2]", result.matched_rule.?.id);
    var buf: [512]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try write(stream.writer(), &policy, result);
    try std.testing.expect(std.mem.indexOf(u8, stream.getWritten(), "Decision: deny") != null);
    try std.testing.expect(std.mem.indexOf(u8, stream.getWritten(), "Rule: files.read.deny[2]") != null);
}
