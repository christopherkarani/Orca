const std = @import("std");
const core = @import("orca_core");

const edge_event = @import("../audit/edge_event.zig");
const edge_replay = @import("../audit/edge_replay.zig");
const edge_session = @import("../audit/edge_session.zig");
const deployment = @import("../deployment/mod.zig");
const safety_report = @import("../audit/safety_report.zig");
const fixture_mod = @import("fixture.zig");
const fault_injection = @import("fault_injection.zig");
const scorecard = @import("scorecard.zig");

pub const CheckResult = struct {
    name: []u8,
    passed: bool,
    observed: []u8,

    pub fn deinit(self: CheckResult, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.observed);
    }
};

pub const FixtureResult = struct {
    allocator: std.mem.Allocator,
    id: []u8,
    name: []u8,
    category: fixture_mod.Category,
    environment: fixture_mod.Environment,
    status: safety_report.ScenarioResultStatus,
    required: bool,
    points_possible: u32,
    points_earned: u32,
    expected_decision: core.decision.DecisionResult,
    actual_decision: ?core.decision.DecisionResult = null,
    expected_findings: []const []const u8 = &.{},
    actual_findings: []const []const u8 = &.{},
    expected_events: []const []const u8 = &.{},
    actual_events: []const []const u8 = &.{},
    checks: []CheckResult = &.{},
    forbidden_log_check_passed: bool = true,
    audit_session_id: []u8,
    safety_case_report_path: ?[]u8 = null,
    reason: ?[]u8 = null,
    limitations: []const []const u8 = &.{},

    pub fn deinit(self: *FixtureResult) void {
        self.allocator.free(self.id);
        self.allocator.free(self.name);
        freeStringList(self.allocator, self.expected_findings);
        freeStringList(self.allocator, self.actual_findings);
        freeStringList(self.allocator, self.expected_events);
        freeStringList(self.allocator, self.actual_events);
        for (self.checks) |check| check.deinit(self.allocator);
        if (self.checks.len > 0) self.allocator.free(self.checks);
        self.allocator.free(self.audit_session_id);
        if (self.safety_case_report_path) |path| self.allocator.free(path);
        if (self.reason) |reason| self.allocator.free(reason);
        freeStringList(self.allocator, self.limitations);
        self.* = undefined;
    }
};

pub const SuiteResult = struct {
    allocator: std.mem.Allocator,
    run_id: []u8,
    session_id: []u8,
    session_dir: []u8,
    output_dir: []u8,
    deployment_profile: ?[]u8 = null,
    results: []FixtureResult,

    pub fn deinit(self: *SuiteResult) void {
        self.allocator.free(self.run_id);
        self.allocator.free(self.session_id);
        self.allocator.free(self.session_dir);
        self.allocator.free(self.output_dir);
        if (self.deployment_profile) |value| self.allocator.free(value);
        for (self.results) |*result| result.deinit();
        if (self.results.len > 0) self.allocator.free(self.results);
        self.* = undefined;
    }

    pub fn totals(self: SuiteResult) scorecard.Totals {
        return scorecard.summarize(FixtureResult, self.results);
    }

    pub fn allRequiredPassed(self: SuiteResult) bool {
        for (self.results) |result| {
            if (result.required and result.status != .passed) return false;
        }
        return true;
    }
};

pub const RunOptions = struct {
    root_path: []const u8 = "examples/edge/redteam",
    category: ?fixture_mod.Category = null,
    fixture_id: ?[]const u8 = null,
    environment: ?fixture_mod.Environment = null,
    output_dir: ?[]const u8 = null,
    deployment_profile: ?[]const u8 = null,
    ci: bool = false,
    safety_case_report: bool = false,
};

pub fn discover(allocator: std.mem.Allocator, options: RunOptions) !fixture_mod.FixtureSet {
    var set = try fixture_mod.discover(allocator, options.root_path, options.fixture_id);
    errdefer set.deinit();
    if (options.category == null and options.environment == null) return set;

    var filtered: std.ArrayList(fixture_mod.Fixture) = .empty;
    errdefer {
        for (filtered.items) |*item| item.deinit();
        filtered.deinit(allocator);
    }
    for (set.fixtures) |*item| {
        const category_matches = if (options.category) |category| item.category == category else true;
        const environment_matches = if (options.environment) |environment| item.environment == environment else true;
        if (category_matches and environment_matches) {
            try filtered.append(allocator, item.*);
            item.* = undefined;
        } else {
            item.deinit();
        }
    }
    if (set.fixtures.len > 0) allocator.free(set.fixtures);
    set.fixtures = try filtered.toOwnedSlice(allocator);
    return set;
}

pub fn validateFixtures(allocator: std.mem.Allocator, options: RunOptions) !fixture_mod.FixtureSet {
    return discover(allocator, options);
}

pub fn runSuite(allocator: std.mem.Allocator, fixture_set: fixture_mod.FixtureSet, options: RunOptions) !SuiteResult {
    try validateDeploymentProfile(allocator, options.deployment_profile);

    const workspace_root = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(workspace_root);
    const now = core.core.time.Timestamp.now();
    const session_id_value = try core.session.generateSessionId(now);
    const run_id = try std.fmt.allocPrint(allocator, "redteam-{s}", .{session_id_value.slice()});
    errdefer allocator.free(run_id);
    const output_dir = if (options.output_dir) |dir| try allocator.dupe(u8, dir) else try std.fs.path.join(allocator, &.{ ".edge", "redteam", run_id });
    errdefer allocator.free(output_dir);
    try std.fs.cwd().makePath(output_dir);

    var session: core.session.Session = .{
        .id = session_id_value,
        .started_at = now,
        .command = "edge",
        .args = &.{"redteam"},
        .workspace_root = workspace_root,
        .session_name = "edge-redteam",
        .mode = if (options.ci) .ci else .strict,
        .platform = core.platform.detectOs(),
    };
    var writer = try edge_session.createWriter(allocator, session);
    defer writer.deinit();
    const session_dir = try allocator.dupe(u8, writer.sessionDirPath());
    errdefer allocator.free(session_dir);

    var sequence: usize = 0;
    try appendNamedEvent(allocator, &writer, &sequence, session, "edge.session_start", .session, session.id.slice(), .observe, "edge red-team session started");

    var results: std.ArrayList(FixtureResult) = .empty;
    errdefer {
        for (results.items) |*result| result.deinit();
        results.deinit(allocator);
    }
    var fixture_options = options;
    fixture_options.output_dir = output_dir;
    for (fixture_set.fixtures) |fixture| {
        try appendNamedEvent(allocator, &writer, &sequence, session, "edge.scenario_start", .extension_target, fixture.id, .observe, fixture.name);
        var result = try runFixture(allocator, fixture, session.id.slice(), fixture_options);
        errdefer result.deinit();
        for (result.actual_events) |event_type| {
            const decision = result.actual_decision orelse .observe;
            try appendNamedEvent(allocator, &writer, &sequence, session, event_type, .extension_target, result.id, decision, result.reason orelse result.name);
        }
        try appendNamedEvent(allocator, &writer, &sequence, session, "edge.scenario_exit", .extension_target, result.status.toString(), .observe, result.reason orelse result.name);
        try results.append(allocator, result);
    }
    try appendNamedEvent(allocator, &writer, &sequence, session, "safety_case.evidence_collected", .extension_target, run_id, .observe, "red-team evidence collected");
    try appendNamedEvent(allocator, &writer, &sequence, session, "edge.session_exit", .session, session.id.slice(), .observe, "edge red-team session completed");

    session.ended_at = core.core.time.Timestamp.now();
    const final_hash = writer.finalHash() orelse "";
    try core.api.writeAuditSummary(allocator, writer.sessionDirPath(), .{
        .session = session,
        .status = .{ .exited = 0 },
        .event_count = writer.event_count,
        .final_event_hash = final_hash,
        .policy = "edge-redteam",
    });
    try writer.writeLastPointer();

    const replay_path = try std.fs.path.join(allocator, &.{ output_dir, "replay.md" });
    defer allocator.free(replay_path);
    try writeReplayFile(allocator, workspace_root, session.id.slice(), replay_path);

    return .{
        .allocator = allocator,
        .run_id = run_id,
        .session_id = try allocator.dupe(u8, session.id.slice()),
        .session_dir = session_dir,
        .output_dir = output_dir,
        .deployment_profile = if (options.deployment_profile) |value| try allocator.dupe(u8, value) else null,
        .results = try results.toOwnedSlice(allocator),
    };
}

fn validateDeploymentProfile(allocator: std.mem.Allocator, maybe_path: ?[]const u8) !void {
    const path = maybe_path orelse return;
    var profile = deployment.loadProfileFile(allocator, path) catch return error.DeploymentProfileInvalid;
    defer profile.deinit();
    const check = deployment.checkProfile(profile);
    if (check.status != .active) return error.DeploymentProfileNotActive;
}

pub fn runFixture(allocator: std.mem.Allocator, fixture: fixture_mod.Fixture, session_id: []const u8, options: RunOptions) !FixtureResult {
    if (fixture.requirements.real_hardware) return error.RealHardwareFixturesUnsupported;
    if (shouldSkipSitl(fixture)) |reason| {
        return makeNonExecutedResult(allocator, fixture, session_id, .skipped, reason);
    }

    var outcome = try fault_injection.run(allocator, fixture);
    defer outcome.deinit();

    var checks: std.ArrayList(CheckResult) = .empty;
    errdefer {
        for (checks.items) |check| check.deinit(allocator);
        checks.deinit(allocator);
    }
    var ok = true;
    if (outcome.actual_decision) |actual| {
        const passed = actual == fixture.expected.decision;
        if (!passed) ok = false;
        try appendCheck(allocator, &checks, "expected decision", passed, actual.toString());
    } else {
        ok = false;
        try appendCheck(allocator, &checks, "expected decision", false, "missing actual decision");
    }
    for (fixture.expected.findings) |expected| {
        const passed = containsString(outcome.actual_findings, expected);
        if (!passed) ok = false;
        try appendCheck(allocator, &checks, expected, passed, "finding check");
    }
    for (fixture.expected.events) |expected| {
        const passed = containsString(outcome.actual_events, expected);
        if (!passed) ok = false;
        try appendCheck(allocator, &checks, expected, passed, "event check");
    }
    var forbidden_ok = true;
    for (fixture.expected.no_log_contains) |forbidden| {
        const passed = !containsInOutcome(outcome, forbidden);
        if (!passed) {
            ok = false;
            forbidden_ok = false;
        }
        try appendCheck(allocator, &checks, forbidden, passed, "forbidden log substring check");
    }

    var status = outcome.status;
    if (fixture.expected.status) |expected_status| {
        if (status != expected_status) ok = false;
    }
    if (status == .passed and !outcome.evidence_complete) status = .inconclusive;
    if (status == .passed and !ok) status = .failed;
    if (status == .passed and outcome.actual_decision == null) status = .inconclusive;

    const report_path = if (options.safety_case_report) try safetyCasePath(allocator, options.output_dir, fixture.id) else null;
    errdefer if (report_path) |path| allocator.free(path);

    return .{
        .allocator = allocator,
        .id = try allocator.dupe(u8, fixture.id),
        .name = try allocator.dupe(u8, fixture.name),
        .category = fixture.category,
        .environment = fixture.environment,
        .status = status,
        .required = fixture.required,
        .points_possible = fixture.score.points,
        .points_earned = if (status == .passed) fixture.score.points else 0,
        .expected_decision = fixture.expected.decision,
        .actual_decision = outcome.actual_decision,
        .expected_findings = try dupeStringSlice(allocator, fixture.expected.findings),
        .actual_findings = try dupeStringSlice(allocator, outcome.actual_findings),
        .expected_events = try dupeStringSlice(allocator, fixture.expected.events),
        .actual_events = try dupeStringSlice(allocator, outcome.actual_events),
        .checks = try checks.toOwnedSlice(allocator),
        .forbidden_log_check_passed = forbidden_ok,
        .audit_session_id = try allocator.dupe(u8, session_id),
        .safety_case_report_path = report_path,
        .reason = try allocator.dupe(u8, outcome.summary),
        .limitations = try dupeStringSlice(allocator, fixture.limitations),
    };
}

fn makeNonExecutedResult(allocator: std.mem.Allocator, fixture: fixture_mod.Fixture, session_id: []const u8, status: safety_report.ScenarioResultStatus, reason: []const u8) !FixtureResult {
    return .{
        .allocator = allocator,
        .id = try allocator.dupe(u8, fixture.id),
        .name = try allocator.dupe(u8, fixture.name),
        .category = fixture.category,
        .environment = fixture.environment,
        .status = status,
        .required = fixture.required,
        .points_possible = fixture.score.points,
        .points_earned = 0,
        .expected_decision = fixture.expected.decision,
        .checks = &.{},
        .audit_session_id = try allocator.dupe(u8, session_id),
        .reason = try allocator.dupe(u8, reason),
        .limitations = try dupeStringSlice(allocator, fixture.limitations),
    };
}

fn shouldSkipSitl(fixture: fixture_mod.Fixture) ?[]const u8 {
    if (fixture.environment == .px4_sitl or fixture.requirements.px4_sitl) return "PX4 SITL unavailable or not explicitly enabled; skipped and not counted as pass";
    if (fixture.environment == .ardupilot_sitl or fixture.requirements.ardupilot_sitl) return "ArduPilot SITL unavailable or not explicitly enabled; skipped and not counted as pass";
    return null;
}

fn appendNamedEvent(
    allocator: std.mem.Allocator,
    writer: anytype,
    sequence: *usize,
    session: core.session.Session,
    event_type: []const u8,
    target_kind: core.api.TargetKind,
    target_value: []const u8,
    decision_result: core.decision.DecisionResult,
    reason: []const u8,
) !void {
    sequence.* += 1;
    const core_event_type = edge_event.toCoreEventType(event_type) catch core.event.EventType.extension_event;
    const event = try core.api.createAuditEvent(.{
        .session_id = session.id,
        .event_id = try edge_event.eventIdFromSequence(sequence.*),
        .timestamp = core.core.time.Timestamp.now(),
        .event_type = core.api.fromCoreEventType(core_event_type),
        .actor = .{ .kind = .orca, .display = "edge" },
        .target = .{ .kind = target_kind, .value = target_value },
        .decision = core.api.makeDecision(.{
            .result = decision_result,
            .reason = reason,
            .risk_score = null,
            .requires_user = decision_result == .ask,
            .ci_may_proceed = decision_result == .allow or decision_result == .observe,
        }),
    });
    try core.api.appendAuditEvent(writer, event);
    _ = allocator;
}

fn writeReplayFile(allocator: std.mem.Allocator, workspace_root: []const u8, session_id: []const u8, path: []const u8) !void {
    try ensureParent(path);
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    var buffer: [8192]u8 = undefined;
    var writer = file.writer(&buffer);
    try edge_replay.write(&writer.interface, allocator, workspace_root, .{ .session = session_id, .verify = true });
    try writer.interface.flush();
    try file.sync();
}

fn appendCheck(allocator: std.mem.Allocator, checks: *std.ArrayList(CheckResult), name: []const u8, passed: bool, observed: []const u8) !void {
    try checks.append(allocator, .{
        .name = try allocator.dupe(u8, name),
        .passed = passed,
        .observed = try allocator.dupe(u8, observed),
    });
}

fn containsString(values: []const []const u8, expected: []const u8) bool {
    for (values) |value| {
        if (std.mem.eql(u8, value, expected)) return true;
        if (std.mem.indexOf(u8, value, expected) != null) return true;
    }
    return false;
}

fn containsInOutcome(outcome: fault_injection.Outcome, forbidden: []const u8) bool {
    if (std.mem.indexOf(u8, outcome.summary, forbidden) != null) return true;
    if (containsString(outcome.actual_findings, forbidden)) return true;
    if (containsString(outcome.actual_events, forbidden)) return true;
    return false;
}

fn safetyCasePath(allocator: std.mem.Allocator, output_dir: ?[]const u8, fixture_id: []const u8) ![]u8 {
    const root = output_dir orelse ".edge/redteam";
    _ = fixture_id;
    return std.fs.path.join(allocator, &.{ root, "safety-report.md" });
}

fn ensureParent(path: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| try std.fs.cwd().makePath(parent);
}

fn dupeStringSlice(allocator: std.mem.Allocator, values: []const []const u8) ![]const []const u8 {
    if (values.len == 0) return &.{};
    const out = try allocator.alloc([]const u8, values.len);
    errdefer allocator.free(out);
    for (values, 0..) |value, index| out[index] = try allocator.dupe(u8, value);
    return out;
}

fn freeStringList(allocator: std.mem.Allocator, values: []const []const u8) void {
    for (values) |value| allocator.free(value);
    if (values.len > 0) allocator.free(values);
}

test "edge redteam runner classifies failing expectation" {
    var fixture = try fixture_mod.parseSlice(std.testing.allocator, "fixture.yaml",
        \\version: 1
        \\id: bad-expectation
        \\name: Bad expectation
        \\category: geofence
        \\environment: fake_adapter
        \\description: Expected allow mismatches a deny.
        \\policy: examples/edge/safety/policies/safety-strict.yaml
        \\faults:
        \\  - waypoint_outside_geofence
        \\expected:
        \\  decision: allow
        \\score:
        \\  points: 1
        \\
    );
    defer fixture.deinit();
    var result = try runFixture(std.testing.allocator, fixture, "test-session", .{});
    defer result.deinit();
    try std.testing.expectEqual(safety_report.ScenarioResultStatus.failed, result.status);
}

test "edge redteam runner classifies unsupported and sitl skips" {
    var unsupported = try fixture_mod.parseSlice(std.testing.allocator, "fixture.yaml",
        \\version: 1
        \\id: unsupported-polygon
        \\name: Unsupported polygon
        \\category: unsupported_feature
        \\environment: fake_adapter
        \\description: Unsupported polygon.
        \\required: false
        \\faults:
        \\  - unsupported_polygon_geofence
        \\expected:
        \\  status: unsupported
        \\  decision: deny
        \\
    );
    defer unsupported.deinit();
    var unsupported_result = try runFixture(std.testing.allocator, unsupported, "test-session", .{});
    defer unsupported_result.deinit();
    try std.testing.expectEqual(safety_report.ScenarioResultStatus.unsupported, unsupported_result.status);

    var sitl = try fixture_mod.parseSlice(std.testing.allocator, "fixture.yaml",
        \\version: 1
        \\id: px4-sitl-skip
        \\name: PX4 SITL skip
        \\category: px4_sitl
        \\environment: px4_sitl
        \\description: SITL skip.
        \\required: false
        \\faults:
        \\  - waypoint_outside_geofence
        \\expected:
        \\  decision: deny
        \\
    );
    defer sitl.deinit();
    var skipped = try runFixture(std.testing.allocator, sitl, "test-session", .{});
    defer skipped.deinit();
    try std.testing.expectEqual(safety_report.ScenarioResultStatus.skipped, skipped.status);
}
