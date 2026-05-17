const std = @import("std");
const aegis_policy = @import("aegis_core").policy;
const core = @import("aegis_core").core;
const supervisor = @import("../core/supervisor.zig");
const core_api = @import("aegis_core").api;
const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");

pub fn command(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len > 0 and (std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h"))) {
        _ = try help.writeCommand(stdout, "policy");
        return exit_codes.success;
    }
    if (argv.len == 0) {
        _ = try help.writeCommand(stdout, "policy");
        return exit_codes.success;
    }

    if (std.mem.eql(u8, argv[0], "check")) return check(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "explain")) return explain(argv[1..], stdout, stderr);

    try stderr.print("orca policy: unknown subcommand '{s}'. Expected check or explain.\n", .{argv[0]});
    return exit_codes.usage;
}

fn check(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 1 and (std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h"))) {
        try stdout.writeAll("Usage:\n  orca policy check [policy-path]\n");
        return exit_codes.success;
    }
    if (argv.len > 1) {
        try stderr.writeAll("orca policy check: expected at most one policy path.\n");
        return exit_codes.usage;
    }

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const source = if (argv.len == 1) argv[0] else "builtin:strict";
    var policy_value = if (argv.len == 1)
        core_api.loadPolicyFile(allocator, argv[0]) catch |err| {
            try stderr.print("orca policy check: invalid policy {s}: {s}\n", .{ argv[0], @errorName(err) });
            return exit_codes.general;
        }
    else
        try core_api.loadPolicyPreset(allocator, aegis_policy.presets.defaultPreset());
    defer policy_value.deinit();

    try stdout.print("Policy OK: {s}\nMode: {s}\n", .{ source, policy_value.mode.toString() });
    return exit_codes.success;
}

fn explain(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 1 and (std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h"))) {
        try stdout.writeAll("Usage:\n  orca policy explain <file.read|file.write|env|command|network|mcp> <target>\n");
        return exit_codes.success;
    }
    if (argv.len < 2) {
        try stderr.writeAll("orca policy explain: expected a type and target.\n");
        return exit_codes.usage;
    }
    const kind = aegis_policy.explain.ExplainKind.parse(argv[0]) orelse {
        try stderr.print("orca policy explain: unsupported type '{s}'.\n", .{argv[0]});
        return exit_codes.usage;
    };
    if (argv.len > 2 and kind != .command) {
        try stderr.writeAll("orca policy explain: expected one target argument.\n");
        return exit_codes.usage;
    }

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const root = supervisor.resolveWorkspaceRoot(allocator, null, ".") catch try allocator.dupe(u8, ".");
    defer allocator.free(root);
    var loaded = core_api.discoverPolicy(allocator, null, root) catch |err| {
        try stderr.print("orca policy explain: failed to load policy: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer loaded.deinit();

    const target = if (kind == .command and argv.len > 2) try joinArgs(allocator, argv[1..]) else try allocator.dupe(u8, argv[1]);
    defer allocator.free(target);

    const evaluation = core_api.explainAction(allocator, &loaded.policy, kind, target) catch |err| {
        try stderr.print("orca policy explain: failed to evaluate action: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer evaluation.deinit(allocator);

    try core_api.writePolicyExplanation(stdout, &loaded.policy, evaluation);
    return exit_codes.success;
}

fn joinArgs(allocator: std.mem.Allocator, args: []const []const u8) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    for (args, 0..) |arg, index| {
        if (index > 0) try list.append(allocator, ' ');
        try list.appendSlice(allocator, arg);
    }
    return try list.toOwnedSlice(allocator);
}

test "policy check validates a file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    {
        const file = try tmp.dir.createFile("policy.yaml", .{});
        defer file.close();
        try file.writeAll(aegis_policy.presets.text(.strict));
    }
    const path = try tmp.dir.realpathAlloc(std.testing.allocator, "policy.yaml");
    defer std.testing.allocator.free(path);

    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(&.{ "check", path }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Policy OK") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "policy check rejects scalar values on object-only grouping keys" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    {
        const file = try tmp.dir.createFile("policy.yaml", .{});
        defer file.close();
        try file.writeAll(
            \\version: 1
            \\mode: strict
            \\commands: allow
        );
    }
    const path = try tmp.dir.realpathAlloc(std.testing.allocator, "policy.yaml");
    defer std.testing.allocator.free(path);

    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(&.{ "check", path }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.general, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "InvalidPolicy") != null);
}

test "policy check without path validates the built-in default policy" {
    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(&.{"check"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Policy OK: builtin:strict") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "policy explain reports matched deny rule" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(&.{ "explain", "file.read", "~/.ssh/id_ed25519" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Decision: deny") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Rule: files.read.deny") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}
