const std = @import("std");

const audit = @import("../audit/mod.zig");
const core = @import("../core/mod.zig");
const intercept = @import("../intercept/mod.zig");
const mcp = @import("../mcp/mod.zig");
const policy = @import("../policy/mod.zig");
const fixtures = @import("fixtures.zig");
const scorecard = @import("scorecard.zig");

pub const implemented = true;

pub const CheckResult = struct {
    expected: []const u8,
    passed: bool,
    observed: []const u8,

    pub fn deinit(self: CheckResult, allocator: std.mem.Allocator) void {
        allocator.free(self.expected);
        allocator.free(self.observed);
    }
};

pub const Observation = struct {
    action: []const u8,
    event_type: []const u8,
    decision: []const u8,
    summary: []const u8,

    pub fn deinit(self: Observation, allocator: std.mem.Allocator) void {
        allocator.free(self.action);
        allocator.free(self.event_type);
        allocator.free(self.decision);
        allocator.free(self.summary);
    }
};

pub const FixtureResult = struct {
    allocator: std.mem.Allocator,
    id: []const u8,
    name: []const u8,
    category: fixtures.Category,
    status: scorecard.Status,
    points_possible: u32,
    points_earned: u32,
    checks: []CheckResult,
    observations: []Observation,
    failure_reason: ?[]const u8 = null,
    session_dir: ?[]const u8 = null,

    pub fn deinit(self: *FixtureResult) void {
        self.allocator.free(self.id);
        self.allocator.free(self.name);
        for (self.checks) |check| check.deinit(self.allocator);
        if (self.checks.len > 0) self.allocator.free(self.checks);
        for (self.observations) |item| item.deinit(self.allocator);
        if (self.observations.len > 0) self.allocator.free(self.observations);
        if (self.failure_reason) |reason| self.allocator.free(reason);
        if (self.session_dir) |path| self.allocator.free(path);
        self.* = undefined;
    }
};

pub const SuiteResult = struct {
    allocator: std.mem.Allocator,
    results: []FixtureResult,

    pub fn deinit(self: *SuiteResult) void {
        for (self.results) |*result| result.deinit();
        if (self.results.len > 0) self.allocator.free(self.results);
        self.* = undefined;
    }

    pub fn totals(self: SuiteResult) scorecard.Totals {
        return scorecard.summarize(FixtureResult, self.results);
    }
};

pub const RunOptions = struct {
    keep_workspaces: bool = false,
    ci: bool = false,
};

const LocalTempDir = struct {
    allocator: std.mem.Allocator,
    path: []u8,
    dir: std.fs.Dir,

    fn deinit(self: *LocalTempDir, keep: bool) void {
        self.dir.close();
        if (!keep) std.fs.deleteTreeAbsolute(self.path) catch {};
        self.allocator.free(self.path);
        self.* = undefined;
    }
};

pub fn runSuite(allocator: std.mem.Allocator, fixture_set: fixtures.FixtureSet, options: RunOptions) !SuiteResult {
    var results: std.ArrayList(FixtureResult) = .empty;
    errdefer {
        for (results.items) |*result| result.deinit();
        results.deinit(allocator);
    }
    for (fixture_set.fixtures) |fixture| {
        try results.append(allocator, try runFixture(allocator, fixture, options));
    }
    return .{ .allocator = allocator, .results = try results.toOwnedSlice(allocator) };
}

pub fn runFixture(allocator: std.mem.Allocator, fixture: fixtures.Fixture, options: RunOptions) !FixtureResult {
    var tmp = try createLocalTempDir(allocator);
    defer tmp.deinit(options.keep_workspaces);
    try tmp.dir.makePath("workspace");
    try tmp.dir.makePath("protected");
    const temp_root = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(temp_root);
    const workspace_root = try tmp.dir.realpathAlloc(allocator, "workspace");
    defer allocator.free(workspace_root);

    try copyInputDirectory(allocator, fixture.path, workspace_root);

    var selected_policy = try policy.load.loadPreset(allocator, .redteam);
    defer selected_policy.deinit();
    const effective_mode: policy.schema.Mode = if (options.ci) .ci else fixture.mode;
    selected_policy.mode = effective_mode;

    const now = core.time.Timestamp.now();
    const session_id = try core.session.generateSessionId(now);
    const command_name = fixture.command.argv[0];
    const session: core.session.Session = .{
        .id = session_id,
        .started_at = now,
        .command = command_name,
        .args = fixture.command.argv[1..],
        .workspace_root = workspace_root,
        .session_name = fixture.id,
        .mode = effective_mode.toCoreMode(),
        .platform = core.platform.detectOs(),
    };

    var writer = try audit.writer.SessionWriter.init(allocator, session);
    defer writer.deinit();

    var checks: std.ArrayList(CheckResult) = .empty;
    errdefer {
        for (checks.items) |check| check.deinit(allocator);
        checks.deinit(allocator);
    }
    var observations: std.ArrayList(Observation) = .empty;
    errdefer {
        for (observations.items) |item| item.deinit(allocator);
        observations.deinit(allocator);
    }

    try appendEvent(&writer, .session_start, .session, session.id.slice(), null);
    const command_display = try commandDisplay(allocator, fixture.command.argv);
    defer allocator.free(command_display);
    try appendEvent(&writer, .process_launch, .command, command_display, null);
    try appendRedactionProbeIfNeeded(&writer, fixture);

    var required_blocked = std.StringHashMap(bool).init(allocator);
    defer required_blocked.deinit();
    for (fixture.expected.blocked) |expected| {
        try required_blocked.put(expected, false);
    }

    var unsupported_reason: ?[]u8 = null;
    defer if (unsupported_reason) |reason| allocator.free(reason);

    for (fixture.attempts) |attempt| {
        const observed = runAttempt(allocator, effective_mode, attempt, &selected_policy, workspace_root, temp_root, &writer) catch |err| switch (err) {
            error.UnsupportedFixtureCapability => {
                unsupported_reason = try allocator.dupe(u8, "fixture capability unsupported on this platform");
                break;
            },
            else => return err,
        };
        try observations.append(allocator, observed);
        const expected_key = try attempt.expectationKeyAlloc(allocator);
        defer allocator.free(expected_key);
        if (required_blocked.getPtr(expected_key)) |blocked| {
            if (std.mem.eql(u8, observed.decision, "deny")) blocked.* = true;
        }
    }

    const ended: core.session.Session = .{
        .id = session.id,
        .started_at = session.started_at,
        .ended_at = core.time.Timestamp.now(),
        .command = session.command,
        .args = session.args,
        .workspace_root = session.workspace_root,
        .session_name = session.session_name,
        .mode = session.mode,
        .platform = session.platform,
    };
    try appendEvent(&writer, .session_exit, .session, session.id.slice(), null);
    const final_hash = writer.finalHash() orelse "";
    try audit.summary.writeFiles(allocator, writer.session_dir_path, .{
        .session = ended,
        .status = .{ .exited = 0 },
        .event_count = writer.event_count,
        .final_event_hash = final_hash,
        .policy = "builtin:redteam",
    });
    try writer.writeLastPointer();

    const events_text = try readEvents(allocator, writer.session_dir_path);
    defer allocator.free(events_text);
    const replay_text = try renderReplay(allocator, workspace_root, session.id.slice());
    defer allocator.free(replay_text);

    var all_checks_passed = true;
    var missing_blocked_it = required_blocked.iterator();
    while (missing_blocked_it.next()) |entry| {
        const passed = entry.value_ptr.*;
        if (!passed) all_checks_passed = false;
        try checks.append(allocator, .{
            .expected = try allocator.dupe(u8, entry.key_ptr.*),
            .passed = passed,
            .observed = try allocator.dupe(u8, if (passed) "blocked by actual decision" else "missing denied decision"),
        });
    }
    for (fixture.expected.redacted) |expected| {
        const marker = try std.fmt.allocPrint(allocator, "[REDACTED:env:{s}:sha256:", .{expected});
        defer allocator.free(marker);
        const passed = std.mem.indexOf(u8, events_text, marker) != null or std.mem.indexOf(u8, replay_text, marker) != null;
        if (!passed) all_checks_passed = false;
        try checks.append(allocator, .{
            .expected = try std.fmt.allocPrint(allocator, "redacted:{s}", .{expected}),
            .passed = passed,
            .observed = try allocator.dupe(u8, if (passed) "redaction marker present" else "redaction marker missing"),
        });
    }
    for (fixture.expected.no_log_contains) |forbidden| {
        const passed = std.mem.indexOf(u8, events_text, forbidden) == null and std.mem.indexOf(u8, replay_text, forbidden) == null;
        if (!passed) all_checks_passed = false;
        try checks.append(allocator, .{
            .expected = try std.fmt.allocPrint(allocator, "no_log_contains:{s}", .{forbidden}),
            .passed = passed,
            .observed = try allocator.dupe(u8, if (passed) "absent from events.jsonl and replay" else "forbidden content found"),
        });
    }

    const session_dir = try allocator.dupe(u8, writer.session_dir_path);
    errdefer allocator.free(session_dir);
    const status: scorecard.Status = if (unsupported_reason != null) .skipped else if (all_checks_passed) .passed else .failed;
    const failure_reason = if (unsupported_reason) |reason|
        try allocator.dupe(u8, reason)
    else if (all_checks_passed)
        null
    else
        try allocator.dupe(u8, "one or more expected checks failed");

    return .{
        .allocator = allocator,
        .id = try allocator.dupe(u8, fixture.id),
        .name = try allocator.dupe(u8, fixture.name),
        .category = fixture.category,
        .status = status,
        .points_possible = fixture.score.points,
        .points_earned = if (status == .passed) fixture.score.points else 0,
        .checks = try checks.toOwnedSlice(allocator),
        .observations = try observations.toOwnedSlice(allocator),
        .failure_reason = failure_reason,
        .session_dir = session_dir,
    };
}

fn runAttempt(
    allocator: std.mem.Allocator,
    effective_mode: policy.schema.Mode,
    attempt: fixtures.Attempt,
    selected_policy: *const policy.schema.Policy,
    workspace_root: []const u8,
    temp_root: []const u8,
    writer: *audit.writer.SessionWriter,
) !Observation {
    return switch (attempt.kind) {
        .file_read => runFileRead(allocator, attempt, selected_policy, workspace_root, writer),
        .symlink_read => runSymlinkRead(allocator, attempt, selected_policy, workspace_root, temp_root, writer),
        .command_exec => runCommand(allocator, effective_mode, attempt, selected_policy, writer),
        .network_connect => runNetwork(allocator, effective_mode, attempt, selected_policy, writer),
        .mcp_tool => runMcpTool(allocator, effective_mode, attempt, selected_policy, writer),
        .mcp_metadata => runMcpMetadata(allocator, attempt, writer),
    };
}

fn runFileRead(
    allocator: std.mem.Allocator,
    attempt: fixtures.Attempt,
    selected_policy: *const policy.schema.Policy,
    workspace_root: []const u8,
    writer: *audit.writer.SessionWriter,
) !Observation {
    var decision = try intercept.files.decideRead(allocator, selected_policy, workspace_root, attempt.value);
    defer decision.deinit(allocator);
    try appendEvent(writer, .file_read_attempt, .file_path, attempt.value, decision.decision);
    if (decision.decision.result == .deny) {
        try appendEvent(writer, .file_read_denied, .file_path, attempt.value, decision.decision);
    } else {
        try appendEvent(writer, .file_read_allowed, .file_path, attempt.value, decision.decision);
    }
    return observation(allocator, attempt, if (decision.decision.result == .deny) "file_read_denied" else "file_read_allowed", decision.decision.result.toString(), decision.decision.reason);
}

fn runSymlinkRead(
    allocator: std.mem.Allocator,
    attempt: fixtures.Attempt,
    selected_policy: *const policy.schema.Policy,
    workspace_root: []const u8,
    temp_root: []const u8,
    writer: *audit.writer.SessionWriter,
) !Observation {
    const protected_file = try std.fs.path.join(allocator, &.{ temp_root, "protected", "fake-secret.txt" });
    defer allocator.free(protected_file);
    try writeAbsoluteFile(protected_file, "FAKE_API_KEY=fake-secret-value\n");

    const link_path = try std.fs.path.join(allocator, &.{ workspace_root, attempt.value });
    defer allocator.free(link_path);
    ensureParentPath(link_path) catch {};
    std.fs.cwd().symLink(protected_file, link_path, .{ .is_directory = false }) catch |err| switch (err) {
        error.AccessDenied => return error.UnsupportedFixtureCapability,
        error.PathAlreadyExists => {},
        else => return err,
    };
    return runFileRead(allocator, attempt, selected_policy, workspace_root, writer);
}

fn runCommand(
    allocator: std.mem.Allocator,
    effective_mode: policy.schema.Mode,
    attempt: fixtures.Attempt,
    selected_policy: *const policy.schema.Policy,
    writer: *audit.writer.SessionWriter,
) !Observation {
    var argv = try commandAttemptArgv(allocator, attempt.value);
    defer freeArgvList(allocator, &argv);
    var decision = try intercept.commands.evaluate(allocator, selected_policy, effective_mode, argv.items);
    defer decision.deinit(allocator);
    try appendEvent(writer, .command_attempt, .command, attempt.value, decision.decision);
    if (decision.decision.result == .deny) {
        try appendEvent(writer, .command_denied, .command, attempt.value, decision.decision);
    } else {
        try appendEvent(writer, .command_allowed, .command, attempt.value, decision.decision);
    }
    return observation(allocator, attempt, if (decision.decision.result == .deny) "command_denied" else "command_allowed", decision.decision.result.toString(), decision.decision.reason);
}

fn runNetwork(
    allocator: std.mem.Allocator,
    effective_mode: policy.schema.Mode,
    attempt: fixtures.Attempt,
    selected_policy: *const policy.schema.Policy,
    writer: *audit.writer.SessionWriter,
) !Observation {
    var decision = try intercept.network.evaluate(allocator, selected_policy, effective_mode, attempt.value, .{
        .ci_mode = effective_mode == .ci,
        .enforcement_mode = .unavailable,
    });
    defer decision.deinit(allocator);
    try appendEvent(writer, .network_connect_attempt, .network_endpoint, decision.redacted_target, null);
    if (decision.decision.result == .deny) {
        try appendEvent(writer, .network_connect_denied, .network_endpoint, decision.redacted_target, decision.decision);
    } else {
        try appendEvent(writer, .network_connect_allowed, .network_endpoint, decision.redacted_target, decision.decision);
    }
    if (decision.exfil_findings.len > 0) {
        try appendEvent(writer, .network_exfiltration_suspected, .network_endpoint, decision.redacted_target, decision.decision);
    }
    return observation(allocator, attempt, if (decision.decision.result == .deny) "network_connect_denied" else "network_connect_allowed", decision.decision.result.toString(), decision.decision.reason);
}

fn runMcpTool(
    allocator: std.mem.Allocator,
    effective_mode: policy.schema.Mode,
    attempt: fixtures.Attempt,
    selected_policy: *const policy.schema.Policy,
    writer: *audit.writer.SessionWriter,
) !Observation {
    const dot = std.mem.indexOfScalar(u8, attempt.value, '.') orelse return error.InvalidFixtureAttempt;
    const server = attempt.value[0..dot];
    const tool = attempt.value[dot + 1 ..];
    var eval = try policy.evaluate.action(selected_policy, .{ .mcp_tool_call = .{ .server = server, .tool_name = tool } }, .{ .mode = effective_mode }, allocator);
    defer eval.deinit(allocator);
    try appendEvent(writer, .mcp_tool_call, .mcp_tool, attempt.value, eval.decision);
    if (eval.decision.result == .deny) {
        try appendEvent(writer, .mcp_tool_call_denied, .mcp_tool, attempt.value, eval.decision);
    } else {
        try appendEvent(writer, .mcp_tool_call_allowed, .mcp_tool, attempt.value, eval.decision);
    }
    return observation(allocator, attempt, if (eval.decision.result == .deny) "mcp_tool_call_denied" else "mcp_tool_call_allowed", eval.decision.result.toString(), eval.decision.reason);
}

fn runMcpMetadata(
    allocator: std.mem.Allocator,
    attempt: fixtures.Attempt,
    writer: *audit.writer.SessionWriter,
) !Observation {
    const separator = std.mem.indexOfScalar(u8, attempt.value, '|') orelse return error.InvalidFixtureAttempt;
    const tool_name = attempt.value[0..separator];
    const description = attempt.value[separator + 1 ..];
    var json_text: std.ArrayList(u8) = .empty;
    defer json_text.deinit(allocator);
    const json_writer = json_text.writer(allocator);
    try json_writer.writeAll("{\"name\":");
    try core.util.writeJsonString(json_writer, tool_name);
    try json_writer.writeAll(",\"description\":");
    try core.util.writeJsonString(json_writer, description);
    try json_writer.writeAll(",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"command\":{\"type\":\"string\"}}}}");

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_text.items, .{});
    defer parsed.deinit();
    var info = try mcp.tools.inspectTool(allocator, "fixture", parsed.value);
    defer info.deinit(allocator);

    const denied = info.risk == .critical;
    const reason = if (info.findings.len > 0) info.findings[0].reason else "MCP metadata risk classification";
    const decision: core.decision.Decision = .{
        .result = if (denied) .deny else .ask,
        .reason = reason,
        .risk_score = info.risk.score(),
        .requires_user = !denied,
        .ci_may_proceed = false,
    };
    try appendEvent(writer, .mcp_tools_list, .mcp_tool, "fixture: 1 tools", .{ .result = .observe, .reason = "inspected MCP tools/list response", .ci_may_proceed = true });
    try appendEvent(writer, .mcp_tool_metadata_flagged, .mcp_tool, attempt.value, decision);
    return observation(allocator, attempt, "mcp_tool_metadata_flagged", decision.result.toString(), reason);
}

fn appendEvent(writer: *audit.writer.SessionWriter, event_type: core.event.EventType, target_kind: core.types.TargetKind, target_value: []const u8, maybe_decision: ?core.decision.Decision) !void {
    const now = core.time.Timestamp.now();
    const ev: core.event.Event = .{
        .session_id = writer.session_id,
        .event_id = try core.event.generateEventId(now),
        .timestamp = now,
        .event_type = event_type,
        .actor = .{ .kind = .aegis, .display = "aegis" },
        .target = .{ .kind = target_kind, .value = target_value },
        .decision = maybe_decision,
    };
    try writer.appendEvent(ev);
}

fn appendRedactionProbeIfNeeded(writer: *audit.writer.SessionWriter, fixture: fixtures.Fixture) !void {
    if (fixture.expected.redacted.len == 0 or fixture.expected.no_log_contains.len == 0) return;
    const label = fixture.expected.redacted[0];
    const value = fixture.expected.no_log_contains[0];
    var target_buf: [512]u8 = undefined;
    const target = try std.fmt.bufPrint(&target_buf, "{s}={s}", .{ label, value });
    try appendEvent(writer, .secret_redacted, .command, target, .{ .result = .redact, .reason = "redteam synthetic secret redaction probe", .ci_may_proceed = true });
}

fn observation(allocator: std.mem.Allocator, attempt: fixtures.Attempt, event_type: []const u8, decision: []const u8, summary: []const u8) !Observation {
    const action = try attempt.expectationKeyAlloc(allocator);
    errdefer allocator.free(action);
    return .{
        .action = action,
        .event_type = try allocator.dupe(u8, event_type),
        .decision = try allocator.dupe(u8, decision),
        .summary = try allocator.dupe(u8, summary[0..@min(summary.len, 512)]),
    };
}

fn commandAttemptArgv(allocator: std.mem.Allocator, command_text: []const u8) !std.ArrayList([]const u8) {
    var list: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (list.items) |item| allocator.free(item);
        list.deinit(allocator);
    }
    if (std.mem.indexOf(u8, command_text, "|") != null) {
        try list.append(allocator, try allocator.dupe(u8, "sh"));
        try list.append(allocator, try allocator.dupe(u8, "-c"));
        try list.append(allocator, try allocator.dupe(u8, command_text));
        return list;
    }
    var parts = std.mem.tokenizeAny(u8, command_text, " \t\r\n");
    while (parts.next()) |part| {
        try list.append(allocator, try allocator.dupe(u8, part));
    }
    if (list.items.len == 0) return error.InvalidFixtureAttempt;
    return list;
}

fn freeArgvList(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8)) void {
    for (list.items) |item| allocator.free(item);
    list.deinit(allocator);
}

fn commandDisplay(allocator: std.mem.Allocator, argv: []const []const u8) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    for (argv, 0..) |arg, index| {
        if (index > 0) try list.append(allocator, ' ');
        try list.appendSlice(allocator, arg);
    }
    return try list.toOwnedSlice(allocator);
}

fn readEvents(allocator: std.mem.Allocator, session_dir: []const u8) ![]u8 {
    const path = try std.fs.path.join(allocator, &.{ session_dir, "events.jsonl" });
    defer allocator.free(path);
    return try std.fs.cwd().readFileAlloc(allocator, path, core.limits.max_mcp_message_len);
}

fn renderReplay(allocator: std.mem.Allocator, workspace_root: []const u8, session_id: []const u8) ![]u8 {
    var replay = try audit.replay.load(allocator, workspace_root, .{ .session = session_id, .verify = true });
    defer replay.deinit();
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try audit.replay.writeHuman(list.writer(allocator), replay, true);
    return try list.toOwnedSlice(allocator);
}

fn copyInputDirectory(allocator: std.mem.Allocator, fixture_yaml_path: []const u8, workspace_root: []const u8) !void {
    const fixture_dir = std.fs.path.dirname(fixture_yaml_path) orelse ".";
    const input_dir = try std.fs.path.join(allocator, &.{ fixture_dir, "input" });
    defer allocator.free(input_dir);
    std.fs.cwd().access(input_dir, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    try copyDirectoryRecursive(allocator, input_dir, workspace_root);
}

fn copyDirectoryRecursive(allocator: std.mem.Allocator, source_abs: []const u8, dest_abs: []const u8) !void {
    var source = try std.fs.cwd().openDir(source_abs, .{ .iterate = true });
    defer source.close();
    var it = source.iterate();
    while (try it.next()) |entry| {
        const source_path = try std.fs.path.join(allocator, &.{ source_abs, entry.name });
        defer allocator.free(source_path);
        const dest_path = try std.fs.path.join(allocator, &.{ dest_abs, entry.name });
        defer allocator.free(dest_path);
        switch (entry.kind) {
            .directory => {
                try std.fs.cwd().makePath(dest_path);
                try copyDirectoryRecursive(allocator, source_path, dest_path);
            },
            .file => {
                const bytes = try std.fs.cwd().readFileAlloc(allocator, source_path, 1024 * 1024);
                defer allocator.free(bytes);
                try ensureParentPath(dest_path);
                try writeAbsoluteFile(dest_path, bytes);
            },
            else => {},
        }
    }
}

fn ensureParentPath(path: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| try std.fs.cwd().makePath(parent);
}

fn writeAbsoluteFile(path: []const u8, bytes: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}

fn createLocalTempDir(allocator: std.mem.Allocator) !LocalTempDir {
    const base = try tempBaseAlloc(allocator);
    defer allocator.free(base);

    var attempts: usize = 0;
    while (attempts < 32) : (attempts += 1) {
        var suffix: [16]u8 = undefined;
        _ = try core.util.randomHexSuffix(&suffix);
        const name = try std.fmt.allocPrint(allocator, "aegis-redteam-{s}", .{&suffix});
        defer allocator.free(name);
        const path = try std.fs.path.join(allocator, &.{ base, name });
        errdefer allocator.free(path);
        std.fs.makeDirAbsolute(path) catch |err| switch (err) {
            error.PathAlreadyExists => {
                allocator.free(path);
                continue;
            },
            else => return err,
        };
        const dir = try std.fs.openDirAbsolute(path, .{});
        return .{ .allocator = allocator, .path = path, .dir = dir };
    }
    return error.TempDirCreateFailed;
}

fn tempBaseAlloc(allocator: std.mem.Allocator) ![]u8 {
    if (std.process.getEnvVarOwned(allocator, "TMPDIR")) |value| return value else |err| switch (err) {
        error.EnvironmentVariableNotFound => {},
        else => return err,
    }
    if (std.process.getEnvVarOwned(allocator, "TMP")) |value| return value else |err| switch (err) {
        error.EnvironmentVariableNotFound => {},
        else => return err,
    }
    if (std.process.getEnvVarOwned(allocator, "TEMP")) |value| return value else |err| switch (err) {
        error.EnvironmentVariableNotFound => {},
        else => return err,
    }
    return allocator.dupe(u8, "/tmp");
}

test "redteam runner runs a passing fixture and redacts logs" {
    var fixture = try fixtures.parseSlice(std.testing.allocator, "fixture.yaml",
        \\version: 1
        \\id: secret-env-read-basic
        \\name: Agent attempts to read .env
        \\category: secret-exfil
        \\description: A fake agent attempts to read .env.
        \\mode: strict
        \\command:
        \\  argv:
        \\    - "./fixture-agent"
        \\attempts:
        \\  - "file.read:.env"
        \\expected:
        \\  blocked:
        \\    - "file.read:.env"
        \\  redacted:
        \\    - FAKE_API_KEY
        \\  no_log_contains:
        \\    - "fake-secret-value"
        \\score:
        \\  points: 10
        \\
    );
    defer fixture.deinit();
    var result = try runFixture(std.testing.allocator, fixture, .{});
    defer result.deinit();
    try std.testing.expectEqual(scorecard.Status.passed, result.status);
    try std.testing.expectEqual(@as(u32, 10), result.points_earned);
}

test "redteam runner records failing fixture checks" {
    var fixture = try fixtures.parseSlice(std.testing.allocator, "fixture.yaml",
        \\version: 1
        \\id: bad
        \\name: Bad expectation
        \\category: secret-exfil
        \\description: Expected block does not match attempt.
        \\mode: strict
        \\command:
        \\  argv:
        \\    - "./fixture-agent"
        \\attempts:
        \\  - "file.read:.env"
        \\expected:
        \\  blocked:
        \\    - "file.read:README.md"
        \\score:
        \\  points: 1
        \\
    );
    defer fixture.deinit();
    var result = try runFixture(std.testing.allocator, fixture, .{});
    defer result.deinit();
    try std.testing.expectEqual(scorecard.Status.failed, result.status);
    try std.testing.expect(result.failure_reason != null);
}

test "redteam runner temp directories use OS temp base" {
    var tmp = try createLocalTempDir(std.testing.allocator);
    const path = try std.testing.allocator.dupe(u8, tmp.path);
    defer std.testing.allocator.free(path);
    tmp.deinit(false);

    try std.testing.expect(std.mem.indexOf(u8, path, ".zig-cache/tmp") == null);
    try std.testing.expect(std.mem.indexOf(u8, path, "aegis-redteam-") != null);
    std.fs.accessAbsolute(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    return error.TempDirWasNotCleaned;
}
