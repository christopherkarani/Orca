const std = @import("std");

const core = @import("orca_core").core;
const supervisor = core.supervisor;
const core_api = @import("orca_core").api;
const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");
const tui = @import("../tui/mod.zig");
const suggestions = @import("suggestions.zig");

const ReplayCliOptions = struct {
    session: []const u8 = "last",
    json: bool = false,
    only_denied: bool = false,
    verify: bool = false,
    list: bool = false,
    /// When true, a missing default `last` session lists sessions instead of erroring.
    fallback_to_list: bool = false,
};

pub fn command(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    const options = parseOptions(io, argv, stdout, stderr) catch |err| switch (err) {
        error.HelpShown => return exit_codes.success,
        error.Usage => return exit_codes.usage,
        else => return err,
    };

    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const workspace_root = supervisor.resolveWorkspaceRoot(io, allocator, null, ".") catch |err| {
        try stderr.print("orca replay: failed to resolve workspace: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer allocator.free(workspace_root);

    if (options.list) {
        return listSessions(io, allocator, workspace_root, stdout);
    }

    return replaySession(io, allocator, workspace_root, options, stdout, stderr);
}

fn replaySession(
    io: std.Io,
    allocator: std.mem.Allocator,
    workspace_root: []const u8,
    options: ReplayCliOptions,
    stdout: anytype,
    stderr: anytype,
) !u8 {
    var session = core_api.loadReplay(io, allocator, workspace_root, .{
        .session = options.session,
        .only_denied = options.only_denied,
        .verify = options.verify,
    }) catch |err| switch (err) {
        error.FileNotFound => {
            if (options.fallback_to_list) {
                return listSessions(io, allocator, workspace_root, stdout);
            }
            try stderr.writeAll("orca replay: session not found.\n");
            return exit_codes.general;
        },
        error.HashVerificationFailed => {
            const session_dir_path = sessionDirPathForError(io, allocator, workspace_root, options.session) catch null;
            defer if (session_dir_path) |path| allocator.free(path);
            const verify_result = if (session_dir_path) |path| core_api.verifyReplay(io, allocator, path) catch null else null;
            if (verify_result) |result| {
                defer result.deinit(allocator);
                if (result.reason) |reason| try stderr.print("orca replay: hash verification failed: {s}\n", .{reason}) else try stderr.writeAll("orca replay: hash verification failed.\n");
            } else {
                try stderr.writeAll("orca replay: hash verification failed.\n");
            }
            return exit_codes.general;
        },
        else => {
            try stderr.print("orca replay: failed: {s}\n", .{@errorName(err)});
            return exit_codes.general;
        },
    };
    defer session.deinit();

    if (options.json) {
        try core_api.writeReplayJson(stdout, session);
    } else {
        try writeReplayHuman(io, allocator, stdout, session, options.verify);
    }
    return exit_codes.success;
}

fn writeReplayHuman(
    io: std.Io,
    allocator: std.mem.Allocator,
    stdout: anytype,
    session: core_api.ReplaySession,
    show_verify: bool,
) !void {
    try tui.render.definitionList(io, stdout, &.{
        .{ .term = "Session", .description = session.session_id },
        .{ .term = "Command", .description = session.command_display },
        .{ .term = "Policy", .description = session.policy },
        .{ .term = "Status", .description = session.status_display },
    });
    try stdout.writeByte('\n');

    const timeline_events = try allocator.alloc(tui.render.TimelineEvent, session.events.len);
    defer allocator.free(timeline_events);
    const owned_details = try allocator.alloc(?[]u8, session.events.len);
    defer allocator.free(owned_details);
    @memset(owned_details, null);
    defer for (owned_details) |detail| if (detail) |value| allocator.free(value);

    var timeline_len: usize = 0;
    var event_index: usize = 0;
    while (event_index < session.events.len) {
        const event = session.events[event_index];
        var group_len: usize = 1;
        if (std.mem.eql(u8, event.event_type, "secret_redacted")) {
            while (event_index + group_len < session.events.len and
                std.mem.eql(u8, session.events[event_index + group_len].event_type, "secret_redacted"))
            {
                group_len += 1;
            }
        }

        const detail = if (group_len > 1)
            try std.fmt.allocPrint(allocator, "{s} · {s} · {d} secret redactions · {s}", .{
                event.timestamp,
                event.event_type,
                group_len,
                event.target_value,
            })
        else
            try std.fmt.allocPrint(allocator, "{s} · {s} · {s}", .{
                event.timestamp,
                event.event_type,
                event.target_value,
            });
        owned_details[timeline_len] = detail;
        timeline_events[timeline_len] = .{ .label = replayEventIcon(event.event_type), .detail = detail };
        timeline_len += 1;
        event_index += group_len;
    }

    try tui.render.timeline(io, stdout, timeline_events[0..timeline_len]);
    if (show_verify) {
        try stdout.writeByte('\n');
        try tui.render.callout(io, stdout, if (session.verified) .success else .warn, "Hash chain", if (session.verified) "verified" else "not verified");
    }
}

fn replayEventIcon(event_type: []const u8) []const u8 {
    if (std.mem.eql(u8, event_type, "command_allowed")) return "✓";
    if (std.mem.eql(u8, event_type, "command_denied")) return "✗";
    if (std.mem.eql(u8, event_type, "secret_redacted")) return "⚠";
    if (std.mem.startsWith(u8, event_type, "session_")) return "ℹ";
    return "•";
}

fn listSessions(io: std.Io, allocator: std.mem.Allocator, workspace_root: []const u8, stdout: anytype) !u8 {
    const sessions_dir = try std.fs.path.join(allocator, &.{ workspace_root, ".orca", "sessions" });
    defer allocator.free(sessions_dir);

    var dir = std.Io.Dir.cwd().openDir(io, sessions_dir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => {
            try stdout.writeAll("No sessions found. Run `orca run -- <command>` to create one.\n");
            return exit_codes.success;
        },
        else => return err,
    };
    defer dir.close(io);

    try stdout.writeAll("SESSION ID\n");

    var count: usize = 0;
    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        try stdout.print("{s}\n", .{entry.name});
        count += 1;
    }

    if (count == 0) {
        try stdout.writeAll("\nNo sessions found. Run `orca run -- <command>` to create one.\n");
    } else {
        try stdout.print("\n{d} session(s) found.\n", .{count});
        try stdout.writeAll("Run `orca replay --session <id>` to view a session.\n");
    }

    return exit_codes.success;
}

fn parseOptions(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !ReplayCliOptions {
    var options: ReplayCliOptions = .{
        .fallback_to_list = argv.len == 0,
    };
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        const arg = argv[index];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            _ = try help.writeCommand(io, stdout, "replay");
            return error.HelpShown;
        } else if (std.mem.eql(u8, arg, "--list")) {
            options.list = true;
        } else if (std.mem.eql(u8, arg, "--session")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("orca replay: --session requires a session id or 'last'.\n");
                return error.Usage;
            }
            options.session = argv[index];
            options.fallback_to_list = false;
        } else if (std.mem.eql(u8, arg, "--json")) {
            options.json = true;
            options.fallback_to_list = false;
        } else if (std.mem.eql(u8, arg, "--verify")) {
            options.verify = true;
            options.fallback_to_list = false;
        } else if (std.mem.eql(u8, arg, "--only")) {
            index += 1;
            if (index >= argv.len or !std.mem.eql(u8, argv[index], "denied")) {
                try stderr.writeAll("orca replay: --only currently supports only 'denied'.\n");
                return error.Usage;
            }
            options.only_denied = true;
            options.fallback_to_list = false;
        } else {
            try suggestions.writeUnknownOption(stderr, "orca replay", arg, &.{ "--list", "--session", "--json", "--verify", "--only", "--help", "-h" }, "replay");
            return error.Usage;
        }
    }
    return options;
}

fn sessionDirPathForError(io: std.Io, allocator: std.mem.Allocator, workspace_root: []const u8, requested: []const u8) ![]u8 {
    const session_id = if (std.mem.eql(u8, requested, "last")) blk: {
        const last_path = try std.fs.path.join(allocator, &.{ workspace_root, ".orca", "last" });
        defer allocator.free(last_path);
        const text = try std.Io.Dir.cwd().readFileAlloc(io, last_path, allocator, .limited(core.limits.max_session_id_len + 2));
        defer allocator.free(text);
        break :blk try allocator.dupe(u8, std.mem.trim(u8, text, " \t\r\n"));
    } else try allocator.dupe(u8, requested);
    defer allocator.free(session_id);
    return try std.fs.path.join(allocator, &.{ workspace_root, ".orca", "sessions", session_id });
}

test "replay rejects invalid --only value" {
    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try command(std.testing.io, &.{ "--only", "allowed" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.usage, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "--only") != null);
}

test "replay --list prints sessions or friendly empty message" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, ".orca");
    {
        const policy_file = try tmp.dir.createFile(std.testing.io, ".orca/policy.yaml", .{});
        defer policy_file.close(std.testing.io);
        try policy_file.writeStreamingAll(std.testing.io, "version: 1\nmode: observe\n");
    }
    try tmp.dir.createDirPath(std.testing.io, ".orca/sessions/session-a");
    try tmp.dir.createDirPath(std.testing.io, ".orca/sessions/session-b");

    const prev_cwd = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(prev_cwd);
    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer std.process.setCurrentPath(std.testing.io, prev_cwd) catch {};

    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try command(std.testing.io, &.{"--list"}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);
    const output = stdout_writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "session-a") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "session-b") != null);
}

test "replay with no args and no sessions lists instead of erroring" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, ".orca");
    {
        const policy_file = try tmp.dir.createFile(std.testing.io, ".orca/policy.yaml", .{});
        defer policy_file.close(std.testing.io);
        try policy_file.writeStreamingAll(std.testing.io, "version: 1\nmode: observe\n");
    }

    const prev_cwd = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(prev_cwd);
    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer std.process.setCurrentPath(std.testing.io, prev_cwd) catch {};

    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try command(std.testing.io, &.{}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);
    const output = stdout_writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "No sessions found") != null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

fn writeReplayTimelineFixture(io: std.Io, allocator: std.mem.Allocator, workspace_root: []const u8) ![]u8 {
    const now = core.time.Timestamp.fromUnixSeconds(1_777_983_130);
    var session_id: core.session.SessionId = .{ .value = undefined, .len = 0 };
    const session_id_text = try std.fmt.bufPrint(&session_id.value, "replay-timeline-fixture", .{});
    session_id.len = session_id_text.len;
    const session = core.session.Session{
        .id = session_id,
        .started_at = now,
        .ended_at = now,
        .command = "orca",
        .args = &.{ "run", "--", "echo", "ok" },
        .workspace_root = workspace_root,
        .session_name = "replay-timeline-test",
        .mode = .strict,
        .platform = core.platform.detectOs(),
    };
    var audit_writer = try core_api.createAuditWriter(io, allocator, session);
    defer audit_writer.deinit();

    for (0..3) |index| {
        var event_id: core.event.EventId = .{ .value = undefined, .len = 0 };
        const event_id_text = try std.fmt.bufPrint(&event_id.value, "redaction-{d}", .{index});
        event_id.len = event_id_text.len;
        const event = try core_api.createAuditEvent(.{
            .session_id = session.id,
            .event_id = event_id,
            .timestamp = now,
            .event_type = .secret_redacted,
            .actor = .{ .kind = .orca, .display = "orca" },
            .target = .{ .kind = .env_var, .value = "TOKEN\x1b[2J\nvalue" },
            .decision = null,
            .redactions = .{ .count = 1, .labels = &.{"TOKEN"} },
        });
        try core_api.appendAuditEvent(&audit_writer, event);
    }
    var allowed_id: core.event.EventId = .{ .value = undefined, .len = 0 };
    const allowed_id_text = try std.fmt.bufPrint(&allowed_id.value, "allowed", .{});
    allowed_id.len = allowed_id_text.len;
    const allowed = try core_api.createAuditEvent(.{
        .session_id = session.id,
        .event_id = allowed_id,
        .timestamp = now,
        .event_type = .command_allowed,
        .actor = .{ .kind = .orca, .display = "orca" },
        .target = .{ .kind = .command, .value = "echo ok" },
        .decision = core_api.makeDecision(.{ .result = .allow, .reason = "allowed" }),
    });
    try core_api.appendAuditEvent(&audit_writer, allowed);
    try audit_writer.writeLastPointer();
    try core_api.writeAuditSummary(allocator, audit_writer.sessionDirPath(), .{
        .session = session,
        .status = .{ .exited = 0 },
        .event_count = audit_writer.event_count,
        .final_event_hash = audit_writer.finalHash() orelse "",
        .policy = ".orca/policy.yaml",
        .product_label = "Orca",
    });
    return allocator.dupe(u8, audit_writer.session_id.slice());
}

test "replay human timeline collapses repeated redactions and json remains exact" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    try tmp.dir.createDirPath(std.testing.io, ".orca");
    {
        const policy_file = try tmp.dir.createFile(std.testing.io, ".orca/policy.yaml", .{});
        defer policy_file.close(std.testing.io);
        try policy_file.writeStreamingAll(std.testing.io, "version: 1\nmode: strict\n");
    }
    const session_id = try writeReplayTimelineFixture(std.testing.io, std.testing.allocator, root);
    defer std.testing.allocator.free(session_id);

    const previous_cwd = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(previous_cwd);
    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer std.process.setCurrentPath(std.testing.io, previous_cwd) catch {};

    var human_stdout_buf: [4096]u8 = undefined;
    var human_stderr_buf: [512]u8 = undefined;
    var human_stdout: std.Io.Writer = .fixed(&human_stdout_buf);
    var human_stderr: std.Io.Writer = .fixed(&human_stderr_buf);
    const human_code = try command(std.testing.io, &.{ "--session", session_id }, &human_stdout, &human_stderr);

    try std.testing.expectEqual(exit_codes.success, human_code);
    try std.testing.expectEqualStrings("", human_stderr.buffered());
    try std.testing.expect(std.mem.indexOf(u8, human_stdout.buffered(), "3 secret redactions") != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, human_stdout.buffered(), "secret_redacted"));
    try std.testing.expect(std.mem.indexOf(u8, human_stdout.buffered(), "├ ⚠") != null);
    try std.testing.expect(std.mem.indexOf(u8, human_stdout.buffered(), "└ ✓") != null);
    try std.testing.expect(std.mem.indexOf(u8, human_stdout.buffered(), "TOKEN value") != null);
    try std.testing.expect(std.mem.indexOf(u8, human_stdout.buffered(), "[2J") == null);
    try std.testing.expect(std.mem.indexOf(u8, human_stdout.buffered(), "\nvalue") == null);
    try std.testing.expect(std.mem.indexOfScalar(u8, human_stdout.buffered(), 0x1b) == null);

    var actual_json_buf: [8192]u8 = undefined;
    var json_stderr_buf: [512]u8 = undefined;
    var actual_json: std.Io.Writer = .fixed(&actual_json_buf);
    var json_stderr: std.Io.Writer = .fixed(&json_stderr_buf);
    const json_code = try command(std.testing.io, &.{ "--session", session_id, "--json" }, &actual_json, &json_stderr);

    try std.testing.expectEqual(exit_codes.success, json_code);
    const expected_json =
        \\[{"version":1,"session_id":"replay-timeline-fixture","event_id":"redaction-0","timestamp":"2026-05-05T12:12:10Z","type":"secret_redacted","actor":{"kind":"orca","id":null,"display":"orca"},"target":{"kind":"env_var","value":"TOKEN\u001b[2J\nvalue"},"decision":null,"redactions":{"count":1,"labels":["TOKEN"]},"previous_hash":null,"event_hash":"29372432ed1651996bc928c2cc25c8ff157175ead9291b4068659b20c1f8d44d"},{"version":1,"session_id":"replay-timeline-fixture","event_id":"redaction-1","timestamp":"2026-05-05T12:12:10Z","type":"secret_redacted","actor":{"kind":"orca","id":null,"display":"orca"},"target":{"kind":"env_var","value":"TOKEN\u001b[2J\nvalue"},"decision":null,"redactions":{"count":1,"labels":["TOKEN"]},"previous_hash":"29372432ed1651996bc928c2cc25c8ff157175ead9291b4068659b20c1f8d44d","event_hash":"5eb6b50592a40e8bfa8ce1954c43200f268bc29b3e8bbd803ae3c689250b7174"},{"version":1,"session_id":"replay-timeline-fixture","event_id":"redaction-2","timestamp":"2026-05-05T12:12:10Z","type":"secret_redacted","actor":{"kind":"orca","id":null,"display":"orca"},"target":{"kind":"env_var","value":"TOKEN\u001b[2J\nvalue"},"decision":null,"redactions":{"count":1,"labels":["TOKEN"]},"previous_hash":"5eb6b50592a40e8bfa8ce1954c43200f268bc29b3e8bbd803ae3c689250b7174","event_hash":"21f702fdba304ea68cefd97047a832d036955a10228d71b12365182c1df47ff4"},{"version":1,"session_id":"replay-timeline-fixture","event_id":"allowed","timestamp":"2026-05-05T12:12:10Z","type":"command_allowed","actor":{"kind":"orca","id":null,"display":"orca"},"target":{"kind":"command","value":"echo ok"},"decision":{"result":"allow","rule_id":null,"reason":"allowed","risk_score":null,"requires_user":false,"ci_may_proceed":false},"redactions":{"count":0,"labels":[]},"previous_hash":"21f702fdba304ea68cefd97047a832d036955a10228d71b12365182c1df47ff4","event_hash":"4a05248fac600beccd0816b25c49895076e4af2a457bba92f85eecd9c8765667"}]
        \\
    ;
    try std.testing.expectEqualStrings(expected_json, actual_json.buffered());
    try std.testing.expectEqualStrings("", json_stderr.buffered());
}
