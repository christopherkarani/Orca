const std = @import("std");
const orca_policy = @import("orca_core").policy;
const core = @import("orca_core").core;
const supervisor = core.supervisor;
const core_api = @import("orca_core").api;
const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");
const tui = @import("../tui/render.zig");

pub fn command(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len > 0 and (std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h"))) {
        _ = try help.writeCommand(io, stdout, "policy");
        return exit_codes.success;
    }
    if (argv.len == 0) {
        _ = try help.writeCommand(io, stdout, "policy");
        return exit_codes.success;
    }

    if (std.mem.eql(u8, argv[0], "check")) return check(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "explain")) return explain(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "packs")) return packs(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "apply-pack")) return applyPack(io, argv[1..], stdout, stderr);

    try stderr.print("orca policy: unknown subcommand '{s}'. Expected check, explain, packs, or apply-pack.\n", .{argv[0]});
    return exit_codes.usage;
}

fn check(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 1 and (std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h"))) {
        try stdout.writeAll("Usage:\n  orca policy check [policy-path]\n");
        return exit_codes.success;
    }
    if (argv.len > 1) {
        try stderr.writeAll("orca policy check: expected at most one policy path.\n");
        return exit_codes.usage;
    }

    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const source = if (argv.len == 1) argv[0] else "builtin:strict";
    var policy_value = if (argv.len == 1)
        core_api.loadPolicyFile(io, allocator, argv[0]) catch |err| {
            try stderr.print("orca policy check: invalid policy {s}: {s}\n", .{ argv[0], @errorName(err) });
            return exit_codes.general;
        }
    else
        try core_api.loadPolicyPreset(allocator, orca_policy.presets.defaultPreset());
    defer policy_value.deinit();

    try stdout.print("Policy OK: {s}\nMode: {s}\n", .{ source, policy_value.mode().toString() });
    return exit_codes.success;
}

fn explain(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 1 and (std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h"))) {
        try stdout.writeAll("Usage:\n  orca policy explain [--policy <path>] <file.read|file.write|env|command|network|mcp> <target> [--method <HTTP_METHOD>]\n");
        return exit_codes.success;
    }
    var policy_path: ?[]const u8 = null;
    var start_index: usize = 0;
    while (start_index < argv.len and std.mem.startsWith(u8, argv[start_index], "--")) : (start_index += 1) {
        if (std.mem.eql(u8, argv[start_index], "--policy")) {
            start_index += 1;
            if (start_index >= argv.len) {
                try stderr.writeAll("orca policy explain: --policy requires a path.\n");
                return exit_codes.usage;
            }
            policy_path = argv[start_index];
        } else {
            break;
        }
    }
    const positional = argv[start_index..];
    if (positional.len < 2) {
        try stderr.writeAll("orca policy explain: expected a type and target.\n");
        return exit_codes.usage;
    }
    const kind = orca_policy.explain.ExplainKind.parse(positional[0]) orelse {
        try stderr.print("orca policy explain: unsupported type '{s}'.\n", .{positional[0]});
        return exit_codes.usage;
    };
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const parsed_target = try parseExplainTarget(allocator, kind, positional[1..], stderr);
    defer parsed_target.deinit(allocator);
    if (parsed_target.invalid) return exit_codes.usage;

    const root = supervisor.resolveWorkspaceRoot(io, allocator, null, ".") catch try allocator.dupe(u8, ".");
    defer allocator.free(root);
    var loaded = core_api.discoverPolicy(io, allocator, policy_path, root) catch |err| {
        if (policy_path) |path| {
            try stderr.print("orca policy explain: failed to load policy {s}: {s}\n", .{ path, @errorName(err) });
        } else {
            try stderr.print("orca policy explain: failed to load policy: {s}\n", .{@errorName(err)});
        }
        return exit_codes.general;
    };
    defer loaded.deinit();

    const evaluation = core_api.explainActionWithOptions(allocator, loaded.policy, kind, parsed_target.target, .{ .network_method = parsed_target.method }) catch |err| {
        try stderr.print("orca policy explain: failed to evaluate action: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer evaluation.deinit(allocator);

    try writePolicyExplanationHuman(io, stdout, loaded.policy, evaluation);
    return exit_codes.success;
}

fn writePolicyExplanationHuman(io: std.Io, stdout: anytype, policy_value: *const core_api.Policy, evaluation: core_api.Evaluation) !void {
    try stdout.writeAll("Decision  ");
    try tui.badge(io, stdout, switch (evaluation.decision.result) {
        .allow => .allow,
        .deny => .deny,
        .ask, .stage => .ask,
        .observe => .info,
        .redact => .warn,
        .broker => .neutral,
    });
    try stdout.writeAll("\n\n");

    const rule_id = if (evaluation.matched_rule) |rule| rule.id else "none";
    const matched = if (evaluation.matched_rule) |rule| rule.pattern else "none";
    const rows = [_]tui.KV{
        .{ .label = "Reason", .value = evaluation.decision.reason },
        .{ .label = "Rule", .value = rule_id },
        .{ .label = "Matched", .value = matched },
        .{ .label = "Mode", .value = policy_value.mode().toString() },
    };
    try tui.keyValue(io, stdout, &rows);
    const score = evaluation.decision.risk_score orelse 0;
    const risk_label = if (evaluation.decision.risk_score == null) "unknown" else if (score <= 25) "low" else if (score <= 50) "medium" else if (score <= 75) "high" else "critical";
    try stdout.writeAll("  Risk  ");
    try tui.meter(io, stdout, @as(f32, @floatFromInt(score)) / 100.0, risk_label);
    try stdout.writeAll("\n");
}

const ExplainTarget = struct {
    target: []const u8 = "",
    method: ?[]const u8 = null,
    invalid: bool = false,

    fn deinit(self: ExplainTarget, allocator: std.mem.Allocator) void {
        if (self.target.len > 0) allocator.free(self.target);
        if (self.method) |method| allocator.free(method);
    }
};

fn parseExplainTarget(allocator: std.mem.Allocator, kind: orca_policy.explain.ExplainKind, args: []const []const u8, stderr: anytype) !ExplainTarget {
    if (kind == .command) return .{ .target = try joinArgs(allocator, args) };
    if (kind != .network) {
        if (args.len != 1) return .{ .invalid = true };
        return .{ .target = try allocator.dupe(u8, args[0]) };
    }
    var target: ?[]const u8 = null;
    var method: ?[]const u8 = null;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--method")) {
            index += 1;
            if (index >= args.len) {
                try stderr.writeAll("orca policy explain: --method requires an HTTP method.\n");
                return .{ .invalid = true };
            }
            if (method) |old| allocator.free(old);
            method = try allocator.dupe(u8, args[index]);
        } else if (std.mem.startsWith(u8, arg, "-")) {
            try stderr.print("orca policy explain: unknown option '{s}'.\n", .{arg});
            if (target) |owned| allocator.free(owned);
            if (method) |owned| allocator.free(owned);
            return .{ .invalid = true };
        } else {
            if (target != null) {
                try stderr.writeAll("orca policy explain: expected one network target.\n");
                if (target) |owned| allocator.free(owned);
                if (method) |owned| allocator.free(owned);
                return .{ .invalid = true };
            }
            target = try allocator.dupe(u8, arg);
        }
    }
    if (target == null) {
        try stderr.writeAll("orca policy explain: expected a network target.\n");
        if (method) |owned| allocator.free(owned);
        return .{ .invalid = true };
    }
    return .{ .target = target.?, .method = method };
}

fn packs(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len != 0) {
        try stderr.writeAll("orca policy packs: expected no arguments.\n");
        return exit_codes.usage;
    }
    try stdout.writeAll("Policy packs:\n");
    for (orca_policy.presets.agent_preset_infos) |info| {
        const source = orca_policy.presets.agentPresetText(info.preset);
        if (std.mem.indexOf(u8, source, "policy pack:") == null and
            !std.mem.eql(u8, info.name, "strict-local")) continue;
        try stdout.print("  {s}\n", .{info.name});
    }
    return exit_codes.success;
}

fn applyPack(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len < 1 or argv.len > 2) {
        try stderr.writeAll("orca policy apply-pack: expected <pack> [--force].\n");
        return exit_codes.usage;
    }
    var force = false;
    if (argv.len == 2) {
        if (!std.mem.eql(u8, argv[1], "--force")) {
            try stderr.writeAll("orca policy apply-pack: only --force is supported after the pack name.\n");
            return exit_codes.usage;
        }
        force = true;
    }
    const pack = orca_policy.presets.AgentPreset.parse(argv[0]) orelse {
        try stderr.print("orca policy apply-pack: unknown policy pack '{s}'.\n", .{argv[0]});
        return exit_codes.usage;
    };
    const pack_name = orca_policy.presets.agentPresetName(pack);
    if (!isProductPack(pack_name)) {
        try stderr.print("orca policy apply-pack: '{s}' is an init preset, not a product policy pack.\n", .{pack_name});
        return exit_codes.usage;
    }
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    const cwd = std.Io.Dir.cwd();
    const root = supervisor.resolveWorkspaceRoot(io, allocator, null, ".") catch try cwd.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(root);
    const orca_dir = try std.fs.path.join(allocator, &.{ root, ".orca" });
    defer allocator.free(orca_dir);
    try cwd.createDirPath(io, orca_dir);
    const path = try std.fs.path.join(allocator, &.{ orca_dir, "policy.yaml" });
    defer allocator.free(path);
    const flags: std.Io.File.CreateFlags = if (force) .{} else .{ .exclusive = true };
    const file = cwd.createFile(io, path, flags) catch |err| switch (err) {
        error.PathAlreadyExists => {
            try stderr.writeAll("orca policy apply-pack: .orca/policy.yaml already exists; use --force to overwrite.\n");
            return exit_codes.general;
        },
        else => return err,
    };
    defer file.close(io);
    try file.writeStreamingAll(io, orca_policy.presets.agentPresetText(pack));
    try stdout.print("Applied policy pack '{s}' to .orca/policy.yaml.\n", .{pack_name});
    return exit_codes.success;
}

fn isProductPack(name: []const u8) bool {
    return std.mem.eql(u8, name, "solo-dev") or
        std.mem.eql(u8, name, "strict-local") or
        std.mem.eql(u8, name, "team-ci") or
        std.mem.eql(u8, name, "openclaw-hermes");
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
        const file = try tmp.dir.createFile(std.testing.io, "policy.yaml", .{});
        defer file.close(std.testing.io);
        try file.writeStreamingAll(std.testing.io, orca_policy.presets.text(.strict));
    }
    const path = try tmp.dir.realPathFileAlloc(std.testing.io, "policy.yaml", std.testing.allocator);
    defer std.testing.allocator.free(path);

    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try command(std.testing.io, &.{ "check", path }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "Policy OK") != null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "policy check rejects scalar values on object-only grouping keys" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    {
        const file = try tmp.dir.createFile(std.testing.io, "policy.yaml", .{});
        defer file.close(std.testing.io);
        try file.writeStreamingAll(std.testing.io,
            \\version: 1
            \\mode: strict
            \\commands: allow
        );
    }
    const path = try tmp.dir.realPathFileAlloc(std.testing.io, "policy.yaml", std.testing.allocator);
    defer std.testing.allocator.free(path);

    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try command(std.testing.io, &.{ "check", path }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.general, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "InvalidPolicy") != null);
}

test "policy check without path validates the built-in default policy" {
    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try command(std.testing.io, &.{"check"}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "Policy OK: builtin:strict") != null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "policy explain reports matched deny rule" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try command(std.testing.io, &.{ "explain", "file.read", "~/.ssh/id_ed25519" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "[DENY]") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "files.read.deny") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "Mode") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "Risk") != null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "policy explain target parser accepts network method option" {
    var stderr_buf: [512]u8 = undefined;
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);
    const parsed = try parseExplainTarget(std.testing.allocator, .network, &.{ "--method", "POST", "https://api.github.com/repos/orca/orca/issues" }, &stderr_writer);
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expect(!parsed.invalid);
    try std.testing.expectEqualStrings("POST", parsed.method.?);
    try std.testing.expectEqualStrings("https://api.github.com/repos/orca/orca/issues", parsed.target);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "policy explain accepts explicit policy path" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    {
        const file = try tmp.dir.createFile(std.testing.io, "policy.yaml", .{});
        defer file.close(std.testing.io);
        try file.writeStreamingAll(std.testing.io,
            \\version: 1
            \\mode: strict
            \\commands:
            \\  default: allow
            \\  deny:
            \\    - "git push *"
        );
    }
    const path = try tmp.dir.realPathFileAlloc(std.testing.io, "policy.yaml", std.testing.allocator);
    defer std.testing.allocator.free(path);

    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try command(std.testing.io, &.{ "explain", "--policy", path, "command", "git", "push", "origin", "main" }, &stdout_writer, &stderr_writer);

    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "[DENY]") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "git push *") != null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "policy packs list productized packs" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);
    const code = try command(std.testing.io, &.{"packs"}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "solo-dev") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "team-ci") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "openclaw-hermes") != null);
}
