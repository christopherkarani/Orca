const std = @import("std");

const core = @import("aegis_core").core;
const core_api = @import("aegis_core").api;
const intercept = @import("../intercept/mod.zig");
const policy = @import("aegis_core").policy;
const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");

const ShimOptions = struct {
    command_argv: []const []const u8 = &.{},
};

pub fn command(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    const options = parseOptions(argv, stdout, stderr) catch |err| switch (err) {
        error.HelpShown => return exit_codes.success,
        error.Usage => return exit_codes.usage,
        else => return err,
    };
    return exec(options.command_argv, stdout, stderr);
}

fn exec(command_argv: []const []const u8, _: anytype, stderr: anytype) !u8 {
    if (command_argv.len == 0) {
        try stderr.writeAll("orca shim exec: missing command after '--'.\n");
        return exit_codes.usage;
    }

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();
    return execWithEnv(allocator, command_argv, &env_map, stderr);
}

fn execWithEnv(allocator: std.mem.Allocator, command_argv: []const []const u8, env_map: *std.process.EnvMap, stderr: anytype) !u8 {
    const session_id = env_map.get("ORCA_SESSION_ID") orelse {
        try stderr.writeAll("orca shim exec: missing ORCA_SESSION_ID; shims only work inside an Orca session.\n");
        return exit_codes.general;
    };
    const workspace_root = env_map.get("ORCA_WORKSPACE_ROOT") orelse {
        try stderr.writeAll("orca shim exec: missing ORCA_WORKSPACE_ROOT; shims only work inside an Orca session.\n");
        return exit_codes.general;
    };
    const shim_dir = env_map.get("ORCA_SHIM_DIR") orelse {
        try stderr.writeAll("orca shim exec: missing ORCA_SHIM_DIR; refusing unsafe delegation.\n");
        return exit_codes.general;
    };
    const path_value = env_map.get("PATH") orelse "";
    const adjusted_path = try intercept.commands.pathWithoutShimAlloc(allocator, path_value, shim_dir);
    defer allocator.free(adjusted_path);

    const real_binary = intercept.commands.resolveRealBinaryAlloc(allocator, command_argv[0], adjusted_path, shim_dir) catch |err| switch (err) {
        error.CommandNotFound => {
            try stderr.print("orca shim exec: real command not found after removing shim path: {s}\n", .{command_argv[0]});
            return exit_codes.general;
        },
        else => return err,
    };
    defer allocator.free(real_binary);

    var writer = core_api.openAuditWriter(allocator, workspace_root, session_id) catch |err| {
        try stderr.print("orca shim exec: failed to open audit log: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer writer.deinit();

    const display = try intercept.commands.displayArgvAlloc(allocator, command_argv);
    defer allocator.free(display);
    try appendCommandEvent(&writer, session_id, .command_attempt, display, null);

    var selected = loadPolicyForShim(allocator, workspace_root, session_id, env_map) catch |err| switch (err) {
        error.UntrustedPolicyPath => {
            const decision: core.decision.Decision = .{
                .result = .deny,
                .reason = "untrusted ORCA_POLICY_PATH; refusing child-controlled policy override",
                .risk_score = 90,
                .ci_may_proceed = false,
            };
            try appendCommandEvent(&writer, session_id, .command_denied, display, decision);
            try stderr.writeAll("orca shim exec: untrusted ORCA_POLICY_PATH; refusing child-controlled policy override.\n");
            return exit_codes.denial;
        },
        else => return err,
    };
    defer selected.deinit();
    const effective_mode = shimMode(&selected.policy, env_map);

    var command_decision = try intercept.commands.evaluate(allocator, &selected.policy, effective_mode, command_argv);
    defer command_decision.deinit(allocator);
    if (command_decision.decision.result != .allow and command_decision.decision.result != .observe) {
        if (intercept.commands.approvalEnvMatches(env_map, display) and try approvalRecordedForCommand(allocator, workspace_root, session_id, display)) {
            try intercept.commands.consumeOnceApproval(allocator, env_map, display);
            const decision: core.decision.Decision = .{
                .result = .allow,
                .reason = "parent approval matched command hash",
                .risk_score = command_decision.decision.risk_score,
                .ci_may_proceed = true,
            };
            try appendCommandEvent(&writer, session_id, .command_allowed, display, decision);
        } else {
            try appendCommandEvent(&writer, session_id, .command_denied, display, command_decision.decision);
            try stderr.print("orca shim exec: command denied: {s}\n", .{command_decision.decision.reason});
            return exit_codes.denial;
        }
    } else {
        try appendCommandEvent(&writer, session_id, .command_allowed, display, command_decision.decision);
    }

    var child_argv = try allocator.alloc([]const u8, command_argv.len);
    defer allocator.free(child_argv);
    child_argv[0] = real_binary;
    if (command_argv.len > 1) @memcpy(child_argv[1..], command_argv[1..]);

    try env_map.put("PATH", adjusted_path);

    var child = std.process.Child.init(child_argv, allocator);
    child.env_map = env_map;
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    child.spawn() catch |err| switch (err) {
        error.FileNotFound => {
            try stderr.print("orca shim exec: command not found: {s}\n", .{command_argv[0]});
            return exit_codes.general;
        },
        else => return err,
    };
    const term = try child.wait();
    return switch (term) {
        .Exited => |code| code,
        .Signal, .Stopped, .Unknown => exit_codes.child_failure,
    };
}

fn parseOptions(argv: []const []const u8, stdout: anytype, stderr: anytype) !ShimOptions {
    if (argv.len == 0 or std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h")) {
        _ = try help.writeCommand(stdout, "shim");
        return error.HelpShown;
    }
    if (!std.mem.eql(u8, argv[0], "exec")) {
        try stderr.writeAll("orca shim: expected subcommand 'exec'.\n");
        return error.Usage;
    }
    if (argv.len < 2 or !std.mem.eql(u8, argv[1], "--")) {
        try stderr.writeAll("orca shim exec: expected '--' before command.\n");
        return error.Usage;
    }
    return .{ .command_argv = argv[2..] };
}

fn loadPolicyForShim(allocator: std.mem.Allocator, workspace_root: []const u8, session_id: []const u8, env_map: *const std.process.EnvMap) !policy.schema.LoadedPolicy {
    if (env_map.get("ORCA_POLICY_PATH")) |path| {
        if (!try policyPathRecordedForSession(allocator, workspace_root, session_id, path)) return error.UntrustedPolicyPath;
        return loadRecordedPolicySource(allocator, path, workspace_root);
    }
    return core_api.discoverPolicy(allocator, null, workspace_root);
}

fn loadRecordedPolicySource(allocator: std.mem.Allocator, source: []const u8, workspace_root: []const u8) !policy.schema.LoadedPolicy {
    const builtin_prefix = "builtin:";
    if (std.mem.startsWith(u8, source, builtin_prefix)) {
        const preset_name = source[builtin_prefix.len..];
        const preset = policy.presets.Preset.parse(preset_name) orelse return error.InvalidPolicy;
        var loaded = try policy.load.loadPreset(allocator, preset);
        errdefer loaded.deinit();
        return .{
            .policy = loaded,
            .source = .builtin,
            .path = try allocator.dupe(u8, source),
        };
    }
    return core_api.discoverPolicy(allocator, source, workspace_root);
}

fn shimMode(selected: *const policy.schema.Policy, env_map: *const std.process.EnvMap) policy.schema.Mode {
    if (env_map.get("ORCA_MODE")) |mode_text| {
        return policy.schema.Mode.parse(mode_text) orelse selected.mode;
    }
    return selected.mode;
}

fn approvalRecordedForCommand(allocator: std.mem.Allocator, workspace_root: []const u8, session_id: []const u8, command_display: []const u8) !bool {
    const events_path = try std.fs.path.join(allocator, &.{ workspace_root, ".orca", "sessions", session_id, "events.jsonl" });
    defer allocator.free(events_path);
    const events_text = std.fs.cwd().readFileAlloc(allocator, events_path, core.limits.max_audit_log_len) catch return false;
    defer allocator.free(events_text);

    var lines = std.mem.splitScalar(u8, events_text, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch return false;
        defer parsed.deinit();
        if (parsed.value != .object) return false;
        const object = parsed.value.object;
        const event_type = object.get("type") orelse continue;
        if (event_type != .string or !std.mem.eql(u8, event_type.string, "user_approval")) continue;
        const target = object.get("target") orelse continue;
        if (target != .object) continue;
        const target_value = target.object.get("value") orelse continue;
        if (target_value != .string or !std.mem.eql(u8, target_value.string, command_display)) continue;
        const decision = object.get("decision") orelse continue;
        if (decision != .object) continue;
        const result = decision.object.get("result") orelse continue;
        if (result == .string and std.mem.eql(u8, result.string, "allow")) return true;
    }
    return false;
}

fn policyPathRecordedForSession(allocator: std.mem.Allocator, workspace_root: []const u8, session_id: []const u8, policy_source: []const u8) !bool {
    const events_path = try std.fs.path.join(allocator, &.{ workspace_root, ".orca", "sessions", session_id, "events.jsonl" });
    defer allocator.free(events_path);
    const events_text = std.fs.cwd().readFileAlloc(allocator, events_path, core.limits.max_audit_log_len) catch return false;
    defer allocator.free(events_text);

    var lines = std.mem.splitScalar(u8, events_text, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch return false;
        defer parsed.deinit();
        if (parsed.value != .object) return false;
        const object = parsed.value.object;
        const event_type = object.get("type") orelse continue;
        if (event_type != .string or !std.mem.eql(u8, event_type.string, "policy_loaded")) continue;
        const target = object.get("target") orelse continue;
        if (target != .object) continue;
        const target_value = target.object.get("value") orelse continue;
        if (target_value == .string and std.mem.eql(u8, target_value.string, policy_source)) return true;
    }
    return false;
}

fn appendCommandEvent(writer: *core_api.AuditWriter, session_id_text: []const u8, event_type: core.event.EventType, display: []const u8, decision: ?core.decision.Decision) !void {
    var session_id: core.session.SessionId = .{ .value = undefined, .len = 0 };
    if (session_id_text.len > session_id.value.len) return error.InvalidSessionId;
    @memcpy(session_id.value[0..session_id_text.len], session_id_text);
    session_id.len = session_id_text.len;
    const ts = core.time.Timestamp.now();
    const ev: core.event.Event = .{
        .session_id = session_id,
        .event_id = try core.event.generateEventId(ts),
        .timestamp = ts,
        .event_type = event_type,
        .actor = .{ .kind = .orca, .display = "orca-shim" },
        .target = .{ .kind = .command, .value = display },
        .decision = decision,
    };
    try core_api.appendAuditEvent(writer, ev);
    updateSummaryIfPresent(writer) catch {};
}

fn updateSummaryIfPresent(writer: *core_api.AuditWriter) !void {
    const summary_path = try std.fs.path.join(writer.allocator, &.{ writer.session_dir_path, "summary.json" });
    defer writer.allocator.free(summary_path);
    std.fs.cwd().access(summary_path, .{}) catch return;
    const final_hash = writer.finalHash() orelse return;
    try core_api.updateAuditSummaryFinalHash(writer.allocator, writer.session_dir_path, writer.event_count, final_hash);
}

test "shim parser rejects missing separator" {
    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    const code = try command(&.{ "exec", "git", "status" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "expected '--'") != null);
}

test "shim callback delegates allowed commands and removes shim path" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    try tmp.dir.makePath("real");
    try tmp.dir.makePath("shim");
    try writeTestScript(tmp.dir, "real/true", "exit 0\n");
    try writeTestScript(tmp.dir, "shim/true", "exit 9\n");
    const real_dir = try tmp.dir.realpathAlloc(std.testing.allocator, "real");
    defer std.testing.allocator.free(real_dir);
    const shim_dir = try tmp.dir.realpathAlloc(std.testing.allocator, "shim");
    defer std.testing.allocator.free(shim_dir);
    const session_id = try prepareShimSession(std.testing.allocator, root);
    defer std.testing.allocator.free(session_id);

    var env_map = std.process.EnvMap.init(std.testing.allocator);
    defer env_map.deinit();
    const path_value = try std.fmt.allocPrint(std.testing.allocator, "{s}:{s}", .{ shim_dir, real_dir });
    defer std.testing.allocator.free(path_value);
    try env_map.put("PATH", path_value);
    try env_map.put("ORCA_SESSION_ID", session_id);
    try env_map.put("ORCA_WORKSPACE_ROOT", root);
    try env_map.put("ORCA_SHIM_DIR", shim_dir);
    try env_map.put("ORCA_MODE", "strict");

    var stderr_buf: [1024]u8 = undefined;
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    const code = try execWithEnv(std.testing.allocator, &.{"true"}, &env_map, stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);
}

test "shim callback blocks denied commands before delegation" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    try tmp.dir.makePath("real");
    try tmp.dir.makePath("shim");
    try writeTestScript(tmp.dir, "real/rm", "exit 42\n");
    const real_dir = try tmp.dir.realpathAlloc(std.testing.allocator, "real");
    defer std.testing.allocator.free(real_dir);
    const shim_dir = try tmp.dir.realpathAlloc(std.testing.allocator, "shim");
    defer std.testing.allocator.free(shim_dir);
    const session_id = try prepareShimSession(std.testing.allocator, root);
    defer std.testing.allocator.free(session_id);

    var env_map = std.process.EnvMap.init(std.testing.allocator);
    defer env_map.deinit();
    const path_value = try std.fmt.allocPrint(std.testing.allocator, "{s}:{s}", .{ shim_dir, real_dir });
    defer std.testing.allocator.free(path_value);
    try env_map.put("PATH", path_value);
    try env_map.put("ORCA_SESSION_ID", session_id);
    try env_map.put("ORCA_WORKSPACE_ROOT", root);
    try env_map.put("ORCA_SHIM_DIR", shim_dir);
    try env_map.put("ORCA_MODE", "strict");

    var stderr_buf: [1024]u8 = undefined;
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    const code = try execWithEnv(std.testing.allocator, &.{ "rm", "-rf", "/" }, &env_map, stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.denial, code);

    const events = try readSessionEvents(std.testing.allocator, root, session_id);
    defer std.testing.allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"type\":\"command_denied\"") != null);
}

test "shim callback preserves parent approval for ask-class command" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    try tmp.dir.makePath("real");
    try tmp.dir.makePath("shim");
    try writeTestScript(tmp.dir, "real/npm", "exit 0\n");
    const real_dir = try tmp.dir.realpathAlloc(std.testing.allocator, "real");
    defer std.testing.allocator.free(real_dir);
    const shim_dir = try tmp.dir.realpathAlloc(std.testing.allocator, "shim");
    defer std.testing.allocator.free(shim_dir);
    const session_id = try prepareShimSession(std.testing.allocator, root);
    defer std.testing.allocator.free(session_id);

    var env_map = std.process.EnvMap.init(std.testing.allocator);
    defer env_map.deinit();
    const path_value = try std.fmt.allocPrint(std.testing.allocator, "{s}:{s}", .{ shim_dir, real_dir });
    defer std.testing.allocator.free(path_value);
    try env_map.put("PATH", path_value);
    try env_map.put("ORCA_SESSION_ID", session_id);
    try env_map.put("ORCA_WORKSPACE_ROOT", root);
    try env_map.put("ORCA_SHIM_DIR", shim_dir);
    try env_map.put("ORCA_MODE", "strict");
    const display = try intercept.commands.displayArgvAlloc(std.testing.allocator, &.{ "npm", "install" });
    defer std.testing.allocator.free(display);
    try recordShimApproval(std.testing.allocator, root, session_id, display);
    try intercept.commands.appendApprovalHashEnv(std.testing.allocator, &env_map, intercept.commands.approved_once_env, display);

    var stderr_buf: [1024]u8 = undefined;
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    const code = try execWithEnv(std.testing.allocator, &.{ "npm", "install" }, &env_map, stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(env_map.get(intercept.commands.approved_once_env) == null);

    const events = try readSessionEvents(std.testing.allocator, root, session_id);
    defer std.testing.allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "parent approval matched command hash") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"type\":\"command_denied\"") == null);
}

test "shim callback rejects forged approval hash from child environment" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    try tmp.dir.makePath("real");
    try tmp.dir.makePath("shim");
    try writeTestScript(tmp.dir, "real/git", "exit 0\n");
    const real_dir = try tmp.dir.realpathAlloc(std.testing.allocator, "real");
    defer std.testing.allocator.free(real_dir);
    const shim_dir = try tmp.dir.realpathAlloc(std.testing.allocator, "shim");
    defer std.testing.allocator.free(shim_dir);
    const session_id = try prepareShimSession(std.testing.allocator, root);
    defer std.testing.allocator.free(session_id);

    var env_map = std.process.EnvMap.init(std.testing.allocator);
    defer env_map.deinit();
    const path_value = try std.fmt.allocPrint(std.testing.allocator, "{s}:{s}", .{ shim_dir, real_dir });
    defer std.testing.allocator.free(path_value);
    try env_map.put("PATH", path_value);
    try env_map.put("ORCA_SESSION_ID", session_id);
    try env_map.put("ORCA_WORKSPACE_ROOT", root);
    try env_map.put("ORCA_SHIM_DIR", shim_dir);
    try env_map.put("ORCA_MODE", "strict");
    const display = try intercept.commands.displayArgvAlloc(std.testing.allocator, &.{ "git", "push" });
    defer std.testing.allocator.free(display);
    try intercept.commands.appendApprovalHashEnv(std.testing.allocator, &env_map, intercept.commands.approved_session_env, display);

    var stderr_buf: [1024]u8 = undefined;
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    const code = try execWithEnv(std.testing.allocator, &.{ "git", "push" }, &env_map, stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.denial, code);

    const events = try readSessionEvents(std.testing.allocator, root, session_id);
    defer std.testing.allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"type\":\"command_denied\"") != null);
}

test "shim callback rejects forged policy path from child environment" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    try tmp.dir.makePath("real");
    try tmp.dir.makePath("shim");
    try writeTestScript(tmp.dir, "real/git", "exit 0\n");
    {
        const file = try tmp.dir.createFile("permissive.yaml", .{});
        defer file.close();
        try file.writeAll(
            \\version: 1
            \\mode: strict
            \\commands:
            \\  allow:
            \\    - "git push"
            \\
        );
    }
    const real_dir = try tmp.dir.realpathAlloc(std.testing.allocator, "real");
    defer std.testing.allocator.free(real_dir);
    const shim_dir = try tmp.dir.realpathAlloc(std.testing.allocator, "shim");
    defer std.testing.allocator.free(shim_dir);
    const policy_path = try tmp.dir.realpathAlloc(std.testing.allocator, "permissive.yaml");
    defer std.testing.allocator.free(policy_path);
    const session_id = try prepareShimSession(std.testing.allocator, root);
    defer std.testing.allocator.free(session_id);

    var env_map = std.process.EnvMap.init(std.testing.allocator);
    defer env_map.deinit();
    const path_value = try std.fmt.allocPrint(std.testing.allocator, "{s}:{s}", .{ shim_dir, real_dir });
    defer std.testing.allocator.free(path_value);
    try env_map.put("PATH", path_value);
    try env_map.put("ORCA_SESSION_ID", session_id);
    try env_map.put("ORCA_WORKSPACE_ROOT", root);
    try env_map.put("ORCA_SHIM_DIR", shim_dir);
    try env_map.put("ORCA_MODE", "strict");
    try env_map.put("ORCA_POLICY_PATH", policy_path);

    var stderr_buf: [1024]u8 = undefined;
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    const code = try execWithEnv(std.testing.allocator, &.{ "git", "push" }, &env_map, stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.denial, code);

    const events = try readSessionEvents(std.testing.allocator, root, session_id);
    defer std.testing.allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"type\":\"command_denied\"") != null);
}

test "shim callback accepts recorded builtin policy source" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    try tmp.dir.makePath("real");
    try tmp.dir.makePath("shim");
    try writeTestScript(tmp.dir, "real/git", "exit 0\n");
    const real_dir = try tmp.dir.realpathAlloc(std.testing.allocator, "real");
    defer std.testing.allocator.free(real_dir);
    const shim_dir = try tmp.dir.realpathAlloc(std.testing.allocator, "shim");
    defer std.testing.allocator.free(shim_dir);
    const session_id = try prepareShimSession(std.testing.allocator, root);
    defer std.testing.allocator.free(session_id);
    try recordShimPolicyLoaded(std.testing.allocator, root, session_id, "builtin:strict");

    var env_map = std.process.EnvMap.init(std.testing.allocator);
    defer env_map.deinit();
    const path_value = try std.fmt.allocPrint(std.testing.allocator, "{s}:{s}", .{ shim_dir, real_dir });
    defer std.testing.allocator.free(path_value);
    try env_map.put("PATH", path_value);
    try env_map.put("ORCA_SESSION_ID", session_id);
    try env_map.put("ORCA_WORKSPACE_ROOT", root);
    try env_map.put("ORCA_SHIM_DIR", shim_dir);
    try env_map.put("ORCA_MODE", "strict");
    try env_map.put("ORCA_POLICY_PATH", "builtin:strict");

    var stderr_buf: [1024]u8 = undefined;
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    const code = try execWithEnv(std.testing.allocator, &.{ "git", "status" }, &env_map, stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);
}

fn writeTestScript(dir: std.fs.Dir, path: []const u8, body: []const u8) !void {
    const file = try dir.createFile(path, .{ .mode = 0o755 });
    defer file.close();
    try file.writeAll("#!/bin/sh\n");
    try file.writeAll(body);
    try file.chmod(0o755);
}

fn prepareShimSession(allocator: std.mem.Allocator, root: []const u8) ![]u8 {
    const ts = core.time.Timestamp.fromUnixSeconds(1_777_983_130);
    const session: core.session.Session = .{
        .id = try core.session.generateSessionId(ts),
        .started_at = ts,
        .command = "true",
        .args = &.{},
        .workspace_root = root,
        .mode = .strict,
        .platform = core.platform.detectOs(),
    };
    var writer = try core_api.createAuditWriter(allocator, session);
    defer writer.deinit();
    return try allocator.dupe(u8, session.id.slice());
}

fn recordShimApproval(allocator: std.mem.Allocator, root: []const u8, session_id: []const u8, display: []const u8) !void {
    var writer = try core_api.openAuditWriter(allocator, root, session_id);
    defer writer.deinit();
    const decision: core.decision.Decision = .{
        .result = .allow,
        .reason = "user approved command once",
        .risk_score = 70,
        .ci_may_proceed = true,
    };
    try appendCommandEvent(&writer, session_id, .user_approval, display, decision);
}

fn recordShimPolicyLoaded(allocator: std.mem.Allocator, root: []const u8, session_id_text: []const u8, policy_source: []const u8) !void {
    var writer = try core_api.openAuditWriter(allocator, root, session_id_text);
    defer writer.deinit();
    var session_id: core.session.SessionId = .{ .value = undefined, .len = 0 };
    if (session_id_text.len > session_id.value.len) return error.InvalidSessionId;
    @memcpy(session_id.value[0..session_id_text.len], session_id_text);
    session_id.len = session_id_text.len;
    const ts = core.time.Timestamp.now();
    const ev: core.event.Event = .{
        .session_id = session_id,
        .event_id = try core.event.generateEventId(ts),
        .timestamp = ts,
        .event_type = .policy_loaded,
        .actor = .{ .kind = .orca, .display = "orca" },
        .target = .{ .kind = .file_path, .value = policy_source },
    };
    try core_api.appendAuditEvent(&writer, ev);
}

fn readSessionEvents(allocator: std.mem.Allocator, root: []const u8, session_id: []const u8) ![]u8 {
    const events_path = try std.fs.path.join(allocator, &.{ root, ".orca", "sessions", session_id, "events.jsonl" });
    defer allocator.free(events_path);
    return try std.fs.cwd().readFileAlloc(allocator, events_path, 64 * 1024);
}
