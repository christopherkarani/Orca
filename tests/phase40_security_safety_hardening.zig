const std = @import("std");
const edge = @import("aegis_edge");
const edge_main = @import("aegis_edge_main");

const domain = edge.domain;
const safety = edge.safety;
const mavlink = edge.mavlink;

const phase40_policy_yaml =
    \\version: 1
    \\
    \\vehicle:
    \\  kind: drone_multirotor
    \\  autopilot: px4
    \\  adapter: fake
    \\
    \\safety:
    \\  state_freshness:
    \\    max_state_age_ms: 1000
    \\    deny_commands_on_stale_state: true
    \\    allow_emergency_land_on_stale_state: true
    \\    allow_return_home_on_stale_state: false
    \\
    \\  geofence:
    \\    type: circle
    \\    center:
    \\      latitude_deg: 37.000000
    \\      longitude_deg: -122.000000
    \\      altitude_m: 0
    \\      altitude_reference: amsl
    \\    home_position:
    \\      latitude_deg: 37.000000
    \\      longitude_deg: -122.000000
    \\      altitude_m: 0
    \\      altitude_reference: amsl
    \\    max_radius_m: 500
    \\    altitude_floor_m: 2
    \\    altitude_ceiling_m: 120
    \\    altitude_reference: amsl
    \\    boundary_action: deny
    \\
    \\  altitude:
    \\    min_altitude_m: 2
    \\    max_altitude_m: 120
    \\    altitude_reference: amsl
    \\
    \\  velocity:
    \\    max_horizontal_mps: 8
    \\    max_vertical_mps: 2
    \\
    \\  battery:
    \\    deny_takeoff_below_percent: 35
    \\    return_home_below_percent: 25
    \\    land_below_percent: 15
    \\    require_fresh_battery_state: true
    \\
    \\  approval:
    \\    approval_ttl_ms: 60000
    \\    max_uses_default: 1
    \\    require_state_hash: true
    \\    allow_broad_scopes: false
    \\    allow_non_overridable_override: false
    \\
    \\  emergency:
    \\    allow_land: true
    \\    allow_return_to_home: true
    \\    allow_hold_position: true
    \\    fallback_order: land, hold_position, return_to_home
    \\
    \\commands:
    \\  allow:
    \\    - read_telemetry
    \\    - read_vehicle_state
    \\    - land
    \\    - return_to_home
    \\    - hold_position
    \\  ask:
    \\    - arm
    \\    - takeoff
    \\    - upload_mission
    \\    - start_mission
    \\    - set_waypoint
    \\    - set_velocity
    \\    - set_altitude
    \\  deny:
    \\    - disable_failsafe
    \\    - disable_geofence
    \\    - raw_actuator_output
    \\    - override_operator
    \\    - firmware_update
    \\
    \\network:
    \\  mode: allowlist
    \\
    \\audit:
    \\  level: full
    \\  redact_secrets: true
;

test "phase 40 review report risk register and known limitations exist and are honest" {
    const required = [_]struct { path: []const u8, markers: []const []const u8 }{
        .{ .path = "docs/edge/security-safety-review.md", .markers = &.{
            "Review date: TBD",
            "Reviewed version: TBD",
            "Scope",
            "Out of scope",
            "Safety boundary",
            "Security invariants checked",
            "Safety invariants checked",
            "Release blockers",
            "Recommendation: Ready for Phase 41 production release",
            "Edge must still not claim real-flight readiness",
        } },
        .{ .path = "docs/edge/risk-register.md", .markers = &.{
            "| Risk ID | Category | Description | Severity | Likelihood | Affected component | Mitigation | Test coverage | Status | Owner | Notes |",
            "incomplete MAVLink command coverage",
            "unsupported polygon geofence",
            "SITL not equivalent to real flight",
            "fake adapter not equivalent to SITL",
            "customer overinterpretation of safety reports",
        } },
        .{ .path = "docs/edge/known-limitations.md", .markers = &.{
            "No real-flight readiness",
            "No certification",
            "No BVLOS approval",
            "No detect-and-avoid",
            "No autopilot replacement",
            "No guarantee of all MAVLink commands covered",
            "Fake-adapter limitations",
            "Customer-specific integration limitations",
        } },
    };

    for (required) |item| {
        const text = try readFile(item.path);
        defer std.testing.allocator.free(text);
        for (item.markers) |marker| try expectContains(text, marker);
        try expectNotContains(text, "certified safe");
        try expectNotContains(text, "FAA approved");
        try expectNotContains(text, "guarantees safety");
    }
}

test "phase 40 review CLI commands are local bounded and non-certifying" {
    var stdout_buf: [32 * 1024]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const docs_argv = [_][]const u8{ "review", "docs-check" };
    try std.testing.expectEqual(@as(u8, 0), try edge_main.run(docs_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try expectContains(stdout_stream.getWritten(), "Phase 40 docs check: passed");
    try expectContains(stdout_stream.getWritten(), "manual review required");
    try expectContains(stdout_stream.getWritten(), "No real hardware, external network, hosted telemetry, secrets, or certification claim");

    stdout_stream.reset();
    stderr_stream.reset();
    const report_argv = [_][]const u8{ "review", "report" };
    try std.testing.expectEqual(@as(u8, 0), try edge_main.run(report_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try expectContains(stdout_stream.getWritten(), "docs/edge/security-safety-review.md");
    try expectContains(stdout_stream.getWritten(), "Ready for Phase 41 production release");
    try expectContains(stdout_stream.getWritten(), "not real-flight readiness");

    stdout_stream.reset();
    stderr_stream.reset();
    const run_argv = [_][]const u8{ "review", "run" };
    try std.testing.expectEqual(@as(u8, 0), try edge_main.run(run_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try expectContains(stdout_stream.getWritten(), "Security and safety hardening review: ready for Phase 41");
    try expectContains(stdout_stream.getWritten(), "skipped/unsupported/inconclusive are not pass");
}

test "phase 40 safety invariants fail closed across unknown state command frames and explicit policy" {
    var loaded = try edge.policy.loadFromSlice(std.testing.allocator, phase40_policy_yaml, "phase40.yaml", .{});
    defer loaded.deinit();

    var unknown_state = freshState(.unknown);
    unknown_state.provenance = .unknown;
    var unknown_result = try safety.evaluateSafety(std.testing.allocator, &loaded.value, unknown_state, request(.set_waypoint, .{ .waypoint = waypoint(37.0001, -122.0, 20, .amsl) }), context(.strict));
    defer unknown_result.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, unknown_result.decision.result);
    try std.testing.expect(unknown_result.hasFindingCategory(.unknown) or unknown_result.hasFindingCategory(.stale_state));

    const unknown_velocity = request(.set_velocity, .{ .velocity = .{ .vx_mps = 1, .vy_mps = 0, .vz_mps = 0, .frame = .unknown } });
    try std.testing.expectError(error.UnknownCoordinateFrame, unknown_velocity.validate());

    const unknown_altitude = request(.takeoff, .{ .altitude = .{ .altitude_m = 20, .altitude_reference = .unknown } });
    try std.testing.expectError(error.UnknownAltitudeReference, unknown_altitude.validate());

    var deny_result = try safety.evaluateSafety(std.testing.allocator, &loaded.value, freshState(.fresh), request(.disable_failsafe, .none), context(.strict));
    defer deny_result.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, deny_result.decision.result);

    var outside_current = freshState(.fresh);
    outside_current.position = waypoint(37.0100, -122.0, 20, .amsl);
    var outside_result = try safety.evaluateSafety(std.testing.allocator, &loaded.value, outside_current, request(.set_velocity, .{ .velocity = .{ .vx_mps = 1, .vy_mps = 0, .vz_mps = 0, .frame = .local_ned } }), context(.strict));
    defer outside_result.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, outside_result.decision.result);
    try std.testing.expect(outside_result.hasFindingCategory(.geofence));
}

test "phase 40 MAVLink mutation paths recover stay bounded and unknown commands/messages stay unsupported" {
    var parser = mavlink.parser.Parser.init();
    var frames: std.ArrayList(mavlink.framing.Frame) = .empty;
    defer frames.deinit(std.testing.allocator);

    const random = [_]u8{ 0x01, 0x02, 0xfd, 0xff, 0x13, 0xfe, 0x00, 0xaa, 0xbb, 0xcc, 0xdd, 0xee };
    const stats = try parser.feed(std.testing.allocator, random[0..], &frames);
    try std.testing.expectEqual(@as(usize, 0), frames.items.len);
    try std.testing.expect(stats.invalid_bytes > 0 or stats.invalid_frames > 0 or stats.partial);

    var oversized: [mavlink.framing.max_frame_len * 4 + 1]u8 = undefined;
    @memset(&oversized, 0xfe);
    try std.testing.expectError(error.OversizedInput, parser.feed(std.testing.allocator, oversized[0..], &frames));

    const unknown_command = try mavlink.fake_transport.frameCommandLongV2(std.testing.allocator, .{ .seq = 9, .sysid = 42, .compid = 191 }, 65_000, 0, .{});
    defer std.testing.allocator.free(unknown_command);
    var mapped = try mavlink.mapping.mapFrameToCommand(std.testing.allocator, try mavlink.framing.parseFrame(unknown_command), .{ .vehicle_id = "edge-vehicle-1", .now_ms = 1_000_100 });
    defer mapped.deinit();
    try std.testing.expect(mapped.request == null);
    try std.testing.expect(mapped.unsupported != null);
    try std.testing.expectEqual(domain.commands.RiskCategory.unknown, mapped.unsupported.?.risk);

    const valid_heartbeat = try mavlink.fake_transport.frameHeartbeatV1(std.testing.allocator, .{ .seq = 10, .sysid = 1, .compid = 1 });
    defer std.testing.allocator.free(valid_heartbeat);
    const corrupted = try std.testing.allocator.dupe(u8, valid_heartbeat);
    defer std.testing.allocator.free(corrupted);
    corrupted[corrupted.len - 2] ^= 0xff;
    var stream: std.ArrayList(u8) = .empty;
    defer stream.deinit(std.testing.allocator);
    try stream.appendSlice(std.testing.allocator, corrupted);
    try stream.appendSlice(std.testing.allocator, valid_heartbeat);
    parser.reset();
    frames.clearRetainingCapacity();
    const recovery = try parser.feed(std.testing.allocator, stream.items, &frames);
    try std.testing.expectEqual(@as(usize, 1), recovery.invalid_frames);
    try std.testing.expectEqual(@as(usize, 1), frames.items.len);
    try std.testing.expect(!recovery.partial);

    const unknown_message = [_]u8{ 0xfd, 0, 0, 0, 11, 42, 191, 0xef, 0xcd, 0xab, 0, 0 };
    const unknown_frame = try mavlink.framing.parseFrame(unknown_message[0..]);
    var unknown_msg_mapping = try mavlink.mapping.mapFrameToCommand(std.testing.allocator, unknown_frame, .{ .vehicle_id = "edge-vehicle-1", .now_ms = 1_000_100 });
    defer unknown_msg_mapping.deinit();
    try std.testing.expect(unknown_msg_mapping.request == null);
    try std.testing.expect(unknown_msg_mapping.unsupported != null);
}

test "phase 40 generated safety-case artifacts redact fake secrets and keep provenance limitations" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    var result = try edge.audit.safety_case.generate(std.testing.allocator, .{
        .policy_path = "examples/edge/px4/policies/px4-geofence-basic.yaml",
        .scenario_path = "examples/edge/px4/scenarios/waypoint-outside-geofence-deny.yaml",
        .workspace_root = root,
        .now = edge.core.core.time.Timestamp.fromUnixSeconds(1_777_983_130),
    });
    defer result.deinit();

    const paths = [_][]const u8{ "events.jsonl", "summary.json", "summary.md", "safety-report.json", "safety-report.md" };
    for (paths) |name| {
        const path = try std.fs.path.join(std.testing.allocator, &.{ result.session_dir, name });
        defer std.testing.allocator.free(path);
        const text = try readFile(path);
        defer std.testing.allocator.free(text);
        try expectNotContains(text, "sk-fakeSyntheticOpenAIKey1234567890");
        try expectNotContains(text, "fake_secret_value_phase35");
    }

    const report_path = try std.fs.path.join(std.testing.allocator, &.{ result.session_dir, "safety-report.md" });
    defer std.testing.allocator.free(report_path);
    const report = try readFile(report_path);
    defer std.testing.allocator.free(report);
    try expectContains(report, "Fake adapter evidence is not PX4 SITL");
    try expectContains(report, "SITL evidence, when present, is local simulation evidence and is not real-flight validation.");
}

test "phase 40 safety-case verification fails when report artifacts are tampered" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    var result = try edge.audit.safety_case.generate(std.testing.allocator, .{
        .policy_path = "examples/edge/safety/policies/safety-strict.yaml",
        .scenario_path = "examples/edge/safety/scenarios/geofence-deny.yaml",
        .workspace_root = root,
        .now = edge.core.core.time.Timestamp.fromUnixSeconds(1_777_983_130),
    });
    defer result.deinit();

    var verified = try edge.audit.safety_case.verify(std.testing.allocator, root, "last");
    defer verified.deinit(std.testing.allocator);
    try std.testing.expect(verified.ok);

    const report_path = try std.fs.path.join(std.testing.allocator, &.{ result.session_dir, "safety-report.json" });
    defer std.testing.allocator.free(report_path);
    const file = try std.fs.cwd().openFile(report_path, .{ .mode = .write_only });
    defer file.close();
    try file.writeAll("tampered");
    try file.sync();

    var tampered = try edge.audit.safety_case.verify(std.testing.allocator, root, "last");
    defer tampered.deinit(std.testing.allocator);
    try std.testing.expect(!tampered.ok);
    try expectContains(tampered.reason.?, "integrity mismatch");
}

test "phase 40 data guard heuristic exfiltration findings deny in strict and observe in observe" {
    const endpoint = edge.data_guard.endpoint_policy.Endpoint{
        .host = "abc123def456ghi789.webhook.site",
        .scheme = "https",
        .path = "/collect",
        .query = "payload=VGhpcyBpcyBhIHN5bnRoZXRpYyB2ZWhpY2xlIG1pc3Npb24gcGxhbiBleGZpbHRyYXRpb24gcHJvYmU",
        .label = "webhook",
    };
    var strict = try edge.data_guard.evaluateWithDefaultPolicy(std.testing.allocator, .{
        .channel_kind = .mavlink_telemetry,
        .direction = .outbound,
        .vehicle_id = "edge-vehicle-1",
        .provenance = "fake_adapter",
        .payload = "{\"vehicle_id\":\"edge-vehicle-1\",\"latitude\":37.0,\"longitude\":-122.0,\"mavlink\":\"COMMAND_LONG\"}",
    }, endpoint, .{ .mode = .strict });
    defer strict.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, strict.decision.result);
    try std.testing.expect(strict.hasFindingCategory(.exfiltration));

    var observe = try edge.data_guard.evaluateWithDefaultPolicy(std.testing.allocator, .{
        .channel_kind = .mavlink_telemetry,
        .direction = .outbound,
        .vehicle_id = "edge-vehicle-1",
        .provenance = "fake_adapter",
        .payload = "{\"vehicle_id\":\"edge-vehicle-1\",\"latitude\":37.0,\"longitude\":-122.0,\"mavlink\":\"COMMAND_LONG\"}",
    }, endpoint, .{ .mode = .observe });
    defer observe.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.observe, observe.decision.result);
    try std.testing.expect(observe.hasFindingCategory(.exfiltration));
}

test "phase 40 redteam scorecard and safety-case status never count skipped unsupported or inconclusive as pass" {
    const Fake = struct {
        category: edge.redteam.fixture.Category,
        status: edge.audit.safety_report.ScenarioResultStatus,
        required: bool,
        points_possible: u32,
        points_earned: u32,
    };
    const results = [_]Fake{
        .{ .category = .geofence, .status = .passed, .required = true, .points_possible = 10, .points_earned = 10 },
        .{ .category = .px4_sitl, .status = .skipped, .required = true, .points_possible = 10, .points_earned = 10 },
        .{ .category = .ardupilot_sitl, .status = .unsupported, .required = true, .points_possible = 10, .points_earned = 10 },
        .{ .category = .safety_case, .status = .inconclusive, .required = true, .points_possible = 10, .points_earned = 10 },
    };
    const totals = edge.redteam.scorecard.summarize(Fake, &results);
    try std.testing.expectEqual(@as(usize, 1), totals.passed);
    try std.testing.expectEqual(@as(usize, 1), totals.skipped);
    try std.testing.expectEqual(@as(usize, 1), totals.unsupported);
    try std.testing.expectEqual(@as(usize, 1), totals.inconclusive);
    try std.testing.expectEqual(@as(u32, 20), totals.points_possible);
    try std.testing.expectEqual(@as(u32, 10), totals.points_earned);

    try std.testing.expectEqual(edge.audit.safety_report.ScenarioResultStatus.skipped, edge.audit.safety_case.classifyScenarioResult(null, .allow, true, false, true));
    try std.testing.expectEqual(edge.audit.safety_report.ScenarioResultStatus.unsupported, edge.audit.safety_case.classifyScenarioResult(null, .allow, false, true, true));
    try std.testing.expectEqual(edge.audit.safety_report.ScenarioResultStatus.inconclusive, edge.audit.safety_case.classifyScenarioResult(.deny, null, false, false, false));
}

fn context(mode: edge.policy.EvaluationMode) safety.EvaluationContext {
    return .{ .mode = mode, .now_ms = 1_000_500, .non_interactive = mode == .ci or mode == .redteam };
}

fn request(action: domain.commands.CommandAction, params: domain.commands.CommandParameters) domain.commands.CommandRequest {
    return domain.commands.CommandRequest.init(.{
        .command_id = "cmd-phase40",
        .vehicle_id = .{ .value = "edge-vehicle-1" },
        .action = action,
        .parameters = params,
        .actor = "phase40-test-agent",
        .timestamp = .{ .value = 1_000_100, .source = .monotonic },
        .source = .fake_adapter,
    });
}

fn waypoint(lat: f64, lon: f64, alt: f64, ref: domain.coordinates.AltitudeReference) domain.coordinates.GeoPoint {
    return .{ .latitude_deg = lat, .longitude_deg = lon, .altitude_m = alt, .altitude_reference = ref };
}

fn freshState(freshness: domain.state.StateFreshness) domain.state.VehicleState {
    return .{
        .vehicle_id = .{ .value = "edge-vehicle-1" },
        .vehicle_kind = .drone_multirotor,
        .autopilot_kind = .px4,
        .mode = .guided,
        .arm_state = .armed,
        .position = waypoint(37.0000, -122.0000, 20, .amsl),
        .local_position = .{ .x_m = 0, .y_m = 0, .z_m = -20, .frame = .local_ned },
        .battery_state = .{ .percent_remaining = 80, .voltage_v = 15.2, .current_a = 2.1, .source = .monotonic },
        .control_authority = .onboard_agent,
        .home_position = waypoint(37.0000, -122.0000, 0, .amsl),
        .timestamp = .{ .value = 1_000_000, .source = .monotonic },
        .state_freshness = freshness,
        .provenance = .fake_adapter,
    };
}

fn readFile(path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(std.testing.allocator, path, 512 * 1024);
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("missing marker: {s}\n", .{needle});
        return error.TestUnexpectedResult;
    }
}

fn expectNotContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) != null) {
        std.debug.print("unexpected marker: {s}\n", .{needle});
        return error.TestUnexpectedResult;
    }
}
