const std = @import("std");
const edge = @import("aegis_edge");

const fixture_mod = edge.redteam.fixture;
const runner = edge.redteam.runner;
const report = edge.redteam.report;
const safety_report = edge.audit.safety_report;

test "phase 34 fixture format validates required fields and rejects unsafe shapes" {
    const allocator = std.testing.allocator;

    var parsed = try fixture_mod.parseSlice(allocator, "fixture.yaml",
        \\version: 1
        \\id: phase34-valid
        \\name: Phase 34 valid fixture
        \\category: geofence
        \\environment: fake_adapter
        \\description: Valid fixture.
        \\policy: examples/edge/redteam/policies/redteam-envelope.yaml
        \\faults:
        \\  - waypoint_outside_geofence
        \\expected:
        \\  decision: deny
        \\  findings:
        \\    - geofence
        \\  events:
        \\    - safety.geofence_violation
        \\  no_log_contains:
        \\    - fake-secret-value
        \\requirements:
        \\  capabilities:
        \\    - fake_adapter
        \\skip_conditions:
        \\  - none
        \\
    );
    defer parsed.deinit();
    try std.testing.expectEqual(fixture_mod.Category.geofence, parsed.category);
    try std.testing.expectEqual(fixture_mod.Environment.fake_adapter, parsed.environment);
    try std.testing.expectEqual(@as(usize, 1), parsed.requirements.capabilities.len);
    try std.testing.expectEqual(@as(usize, 1), parsed.skip_conditions.len);

    try std.testing.expectError(error.MissingExpectedDecision, fixture_mod.parseSlice(allocator, "bad.yaml",
        \\version: 1
        \\id: missing-decision
        \\name: Missing decision
        \\category: geofence
        \\environment: fake_adapter
        \\description: Invalid.
        \\faults:
        \\  - waypoint_outside_geofence
        \\expected:
        \\  events:
        \\    - safety.geofence_violation
        \\
    ));

    try std.testing.expectError(error.InvalidRedteamFixtureCategory, fixture_mod.parseSlice(allocator, "bad.yaml",
        \\version: 1
        \\id: bad-category
        \\name: Bad category
        \\category: not_a_category
        \\environment: fake_adapter
        \\description: Invalid.
        \\faults:
        \\  - waypoint_outside_geofence
        \\expected:
        \\  decision: deny
        \\
    ));

    try std.testing.expectError(error.RealHardwareFixturesUnsupported, fixture_mod.parseSlice(allocator, "bad.yaml",
        \\version: 1
        \\id: real-hardware
        \\name: Real hardware
        \\category: geofence
        \\environment: fake_adapter
        \\description: Invalid.
        \\faults:
        \\  - waypoint_outside_geofence
        \\expected:
        \\  decision: deny
        \\requirements:
        \\  real_hardware: true
        \\
    ));
}

test "phase 34 fixture discovery filters and rejects duplicate ids" {
    const allocator = std.testing.allocator;
    var all = try runner.discover(allocator, .{});
    defer all.deinit();
    try std.testing.expect(all.fixtures.len >= 30);

    var geofence = try runner.discover(allocator, .{ .category = .geofence });
    defer geofence.deinit();
    try std.testing.expect(geofence.fixtures.len >= 4);
    for (geofence.fixtures) |item| try std.testing.expectEqual(fixture_mod.Category.geofence, item.category);

    var one = try runner.discover(allocator, .{ .fixture_id = "geofence-waypoint-outside-circular-denied" });
    defer one.deinit();
    try std.testing.expectEqual(@as(usize, 1), one.fixtures.len);

    var px4 = try runner.discover(allocator, .{ .environment = .px4_sitl });
    defer px4.deinit();
    try std.testing.expect(px4.fixtures.len >= 5);
    for (px4.fixtures) |item| try std.testing.expect(!item.required);

    const first = try fixture_mod.parseSlice(allocator, "a.yaml",
        \\version: 1
        \\id: duplicate-id
        \\name: First
        \\category: geofence
        \\environment: fake_adapter
        \\description: First.
        \\faults:
        \\  - waypoint_outside_geofence
        \\expected:
        \\  decision: deny
        \\
    );
    const second = try fixture_mod.parseSlice(allocator, "b.yaml",
        \\version: 1
        \\id: duplicate-id
        \\name: Second
        \\category: geofence
        \\environment: fake_adapter
        \\description: Second.
        \\faults:
        \\  - waypoint_outside_geofence
        \\expected:
        \\  decision: deny
        \\
    );
    var duplicates = [_]fixture_mod.Fixture{ first, second };
    defer {
        duplicates[0].deinit();
        duplicates[1].deinit();
    }
    try std.testing.expectError(error.DuplicateRedteamFixtureId, fixture_mod.validateUniqueIds(&duplicates));
}

test "phase 34 required fake and simulation corpus passes with honest skip math" {
    const allocator = std.testing.allocator;
    var set = try runner.discover(allocator, .{});
    defer set.deinit();

    var required_count: usize = 0;
    for (set.fixtures) |item| {
        try std.testing.expect(!item.requirements.real_hardware);
        if (item.required) {
            required_count += 1;
            try std.testing.expect(item.environment != .px4_sitl);
            try std.testing.expect(item.environment != .ardupilot_sitl);
            try std.testing.expect(item.expected.no_log_contains.len > 0);
        }
    }
    try std.testing.expect(required_count >= 30);

    var suite = try runner.runSuite(allocator, set, .{ .output_dir = ".zig-cache/phase34-redteam-corpus-test", .ci = true });
    defer suite.deinit();
    const totals = suite.totals();
    try std.testing.expectEqual(required_count, totals.required);
    try std.testing.expectEqual(required_count, totals.passed);
    try std.testing.expectEqual(@as(usize, 0), totals.failed);
    try std.testing.expectEqual(@as(usize, 0), totals.inconclusive);
    try std.testing.expect(totals.skipped > 0);
    try std.testing.expect(totals.unsupported > 0);
    try std.testing.expect(suite.allRequiredPassed());

    for (suite.results) |result| {
        if (result.required) {
            try std.testing.expectEqual(safety_report.ScenarioResultStatus.passed, result.status);
            try std.testing.expect(result.actual_decision != null);
            try std.testing.expect(result.actual_events.len > 0);
            try std.testing.expect(result.audit_session_id.len > 0);
        } else if (result.status == .skipped or result.status == .unsupported) {
            try std.testing.expectEqual(@as(u32, 0), result.points_earned);
        }
    }
}

test "phase 34 runner classifies failed skipped unsupported and inconclusive distinctly" {
    const allocator = std.testing.allocator;

    var bad = try fixture_mod.parseSlice(allocator, "bad.yaml",
        \\version: 1
        \\id: bad-expectation
        \\name: Bad expectation
        \\category: geofence
        \\environment: fake_adapter
        \\description: Expected allow mismatches denial.
        \\policy: examples/edge/redteam/policies/redteam-envelope.yaml
        \\faults:
        \\  - waypoint_outside_geofence
        \\expected:
        \\  decision: allow
        \\
    );
    defer bad.deinit();
    var failed = try runner.runFixture(allocator, bad, "phase34-session", .{});
    defer failed.deinit();
    try std.testing.expectEqual(safety_report.ScenarioResultStatus.failed, failed.status);

    var inconclusive_fixture = try fixture_mod.parseSlice(allocator, "inconclusive.yaml",
        \\version: 1
        \\id: inconclusive
        \\name: Inconclusive
        \\category: telemetry_fault
        \\environment: fake_adapter
        \\description: Missing executable evidence.
        \\faults:
        \\  - safety_case_fake_secret_check
        \\expected:
        \\  decision: deny
        \\
    );
    defer inconclusive_fixture.deinit();
    var inconclusive = try runner.runFixture(allocator, inconclusive_fixture, "phase34-session", .{});
    defer inconclusive.deinit();
    try std.testing.expectEqual(safety_report.ScenarioResultStatus.inconclusive, inconclusive.status);

    var unsupported = try runner.discover(allocator, .{ .fixture_id = "geofence-unsupported-polygon-marked-unsupported" });
    defer unsupported.deinit();
    var unsupported_result = try runner.runFixture(allocator, unsupported.fixtures[0], "phase34-session", .{});
    defer unsupported_result.deinit();
    try std.testing.expectEqual(safety_report.ScenarioResultStatus.unsupported, unsupported_result.status);

    var px4 = try runner.discover(allocator, .{ .fixture_id = "px4-sitl-waypoint-outside-geofence-denied" });
    defer px4.deinit();
    var skipped = try runner.runFixture(allocator, px4.fixtures[0], "phase34-session", .{});
    defer skipped.deinit();
    try std.testing.expectEqual(safety_report.ScenarioResultStatus.skipped, skipped.status);
}

test "phase 34 fault injection covers state command mavlink approval and emergency faults" {
    const allocator = std.testing.allocator;

    var loaded = try edge.policy.loadFile(allocator, "examples/edge/redteam/policies/redteam-envelope.yaml", .{});
    defer loaded.deinit();
    var state = edge.redteam.fault_injection.baseState(&loaded.value, .fake_adapter, 1_000_000);
    edge.redteam.fault_injection.applyStateFault(&state, .stale_position);
    try std.testing.expectEqual(edge.domain.state.StateFreshness.stale, state.state_freshness);
    edge.redteam.fault_injection.applyStateFault(&state, .low_battery);
    try std.testing.expect(state.battery_state.?.percent_remaining < 35);
    edge.redteam.fault_injection.applyStateFault(&state, .invalid_gps_fix);
    try std.testing.expect(!state.gps_state.?.is_valid);

    const cases = [_]struct {
        id: []const u8,
        expected: safety_report.ScenarioResultStatus,
    }{
        .{ .id = "geofence-waypoint-outside-circular-denied", .expected = .passed },
        .{ .id = "mavlink-malformed-frame-rejected", .expected = .passed },
        .{ .id = "approval-expired-denied", .expected = .passed },
        .{ .id = "emergency-cannot-disable-failsafe", .expected = .passed },
        .{ .id = "velocity-unknown-frame-denied", .expected = .passed },
    };
    for (cases) |case| {
        var set = try runner.discover(allocator, .{ .fixture_id = case.id });
        defer set.deinit();
        var result = try runner.runFixture(allocator, set.fixtures[0], "phase34-session", .{});
        defer result.deinit();
        try std.testing.expectEqual(case.expected, result.status);
    }
}

test "phase 34 safety-case artifacts are generated and redacted" {
    const allocator = std.testing.allocator;
    var set = try runner.discover(allocator, .{ .category = .geofence });
    defer set.deinit();
    var suite = try runner.runSuite(allocator, set, .{ .output_dir = ".zig-cache/phase34-redteam-report-test", .safety_case_report = true });
    defer suite.deinit();
    try report.writeArtifacts(allocator, suite, true);

    const files = [_][]const u8{
        ".zig-cache/phase34-redteam-report-test/scorecard.md",
        ".zig-cache/phase34-redteam-report-test/scorecard.json",
        ".zig-cache/phase34-redteam-report-test/safety-report.md",
        ".zig-cache/phase34-redteam-report-test/safety-report.json",
        ".zig-cache/phase34-redteam-report-test/replay.md",
    };
    for (files) |path| {
        const text = try std.fs.cwd().readFileAlloc(allocator, path, 512 * 1024);
        defer allocator.free(text);
        try std.testing.expect(std.mem.indexOf(u8, text, "fake-secret-value") == null);
    }

    const safety_md = try std.fs.cwd().readFileAlloc(allocator, ".zig-cache/phase34-redteam-report-test/safety-report.md", 512 * 1024);
    defer allocator.free(safety_md);
    try std.testing.expect(std.mem.indexOf(u8, safety_md, "Aegis Edge is not a flight controller") != null);
    try std.testing.expect(std.mem.indexOf(u8, safety_md, "SITL success is not real-flight readiness") != null);
    try std.testing.expect(std.mem.indexOf(u8, safety_md, "Fixture Results") != null);
}

test "phase 34 docs preserve simulation and certification boundaries" {
    const allocator = std.testing.allocator;
    const paths = [_][]const u8{
        "docs/edge/redteam.md",
        "docs/edge/fault-injection.md",
        "docs/edge/redteam-fixtures.md",
        "docs/edge/redteam-scorecards.md",
        "docs/edge/sitl-redteam.md",
        "docs/edge/safety-case.md",
        "docs/edge/simulation-vs-flight.md",
        "packages/edge/README.md",
    };
    for (paths) |path| {
        const text = try std.fs.cwd().readFileAlloc(allocator, path, 256 * 1024);
        defer allocator.free(text);
        try std.testing.expect(std.mem.indexOf(u8, text, "real-flight") != null);
        try std.testing.expect(std.mem.indexOf(u8, text, "certification") != null or std.mem.indexOf(u8, text, "Certification") != null);
        try std.testing.expect(std.mem.indexOf(u8, text, "detect-and-avoid") != null);
    }
}
