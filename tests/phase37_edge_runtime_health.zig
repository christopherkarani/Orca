const std = @import("std");
const edge = @import("aegis_edge");

const domain = edge.domain;
const health = edge.health;
const decision = edge.core.decision.DecisionResult;

const watchdog_policy_yaml =
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
    \\    allow_return_home_on_stale_state: true
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
    \\  emergency:
    \\    allow_land: true
    \\    allow_return_to_home: true
    \\    allow_hold_position: true
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
    \\    - set_waypoint
    \\    - set_velocity
    \\    - set_altitude
    \\  deny:
    \\    - disable_failsafe
    \\    - disable_geofence
    \\    - raw_actuator_output
    \\    - override_operator
    \\
    \\watchdog:
    \\  enabled: true
    \\  heartbeat:
    \\    agent_max_age_ms: 1000
    \\    adapter_max_age_ms: 1000
    \\    mavlink_max_age_ms: 1000
    \\    px4_sitl_max_age_ms: 1500
    \\    ardupilot_sitl_max_age_ms: 1500
    \\  telemetry:
    \\    vehicle_state_max_age_ms: 1000
    \\    position_max_age_ms: 1000
    \\    battery_max_age_ms: 2000
    \\    gps_max_age_ms: 2000
    \\    link_max_age_ms: 1000
    \\  audit:
    \\    require_audit_writer: true
    \\    fail_closed_on_audit_error: true
    \\    max_event_append_latency_ms: 100
    \\  degraded_mode:
    \\    on_agent_stale: deny_high_risk
    \\    on_adapter_stale: deny_high_risk
    \\    on_telemetry_stale: deny_movement
    \\    on_audit_failure: fail_closed
    \\    on_policy_error: fail_closed
    \\    allow_emergency_land: true
    \\    allow_return_to_home: policy
    \\    allow_hold: policy
    \\  resource:
    \\    max_memory_mb: 512
    \\    max_cpu_percent: 90
    \\    max_event_queue_depth: 1000
    \\
    \\network:
    \\  mode: allowlist
    \\
    \\audit:
    \\  level: full
    \\  redact_secrets: true
;

test "phase 37 health status model constructs structured findings" {
    try std.testing.expectEqualStrings("healthy", health.HealthStatus.healthy.toString());
    try std.testing.expectEqualStrings("degraded", health.HealthStatus.degraded.toString());
    try std.testing.expectEqualStrings("critical", health.HealthStatus.critical.toString());
    try std.testing.expectEqualStrings("unavailable", health.HealthStatus.unavailable.toString());
    try std.testing.expectEqualStrings("unknown", health.HealthStatus.unknown.toString());
    try std.testing.expectEqual(health.Severity.critical, health.HealthStatus.failed.defaultSeverity());

    const finding = health.HealthFinding.init(.{
        .finding_id = "health-agent-stale",
        .domain = .agent,
        .status = .critical,
        .severity = .critical,
        .reason = "agent heartbeat expired",
        .observed_value = "age_ms=3000",
        .threshold = "agent_max_age_ms=1000",
        .timestamp_ms = 1_003_000,
        .provenance = .fake_adapter,
        .scenario_id = "stale-agent-deny-high-risk",
        .vehicle_id = "edge-vehicle-1",
        .matched_rule = "watchdog.heartbeat.agent_max_age_ms",
        .recommended_behavior = .deny_high_risk,
        .audit_event_reference = "health.watchdog.finding",
    });
    try std.testing.expectEqual(health.HealthDomain.agent, finding.domain);
    try std.testing.expectEqual(health.DegradedBehavior.deny_high_risk, finding.recommended_behavior);
    try std.testing.expectEqualStrings("fake_adapter", finding.provenance.toString());
}

test "phase 37 watchdog policy parses and rejects unsafe configuration" {
    var loaded = try edge.policy.loadFromSlice(std.testing.allocator, watchdog_policy_yaml, "phase37-watchdog.yaml", .{});
    defer loaded.deinit();
    try std.testing.expect(loaded.value.watchdog.enabled);
    try std.testing.expectEqual(@as(u64, 1000), loaded.value.watchdog.heartbeat.agent_max_age_ms);
    try std.testing.expectEqual(@as(u64, 2000), loaded.value.watchdog.telemetry.battery_max_age_ms);
    try std.testing.expect(loaded.value.watchdog.audit.fail_closed_on_audit_error);
    try std.testing.expectEqual(health.DegradedBehavior.deny_movement, loaded.value.watchdog.degraded_mode.on_telemetry_stale);

    try expectPolicyReplacementError(error.InvalidWatchdogPolicy, "agent_max_age_ms: 1000", "agent_max_age_ms: 0");
    try expectPolicyReplacementError(error.InvalidPolicy, "adapter_max_age_ms: 1000", "adapter_max_age_ms: -1");
    try expectPolicyReplacementError(error.UnknownDegradedBehavior, "on_agent_stale: deny_high_risk", "on_agent_stale: launch_autonomy");
    try expectPolicyReplacementError(error.InvalidWatchdogPolicy, "max_cpu_percent: 90", "max_cpu_percent: 101");

    var strict_default = health.WatchdogPolicy{};
    try strict_default.applyModeDefaults(.ci);
    try std.testing.expect(strict_default.audit.fail_closed_on_audit_error);
    try std.testing.expect(strict_default.audit.require_audit_writer);
}

test "phase 37 heartbeat freshness preserves fake and SITL provenance" {
    const policy = health.WatchdogPolicy{};
    const fresh = try health.evaluateHeartbeat(.{
        .source = .agent,
        .source_id = "agent-1",
        .timestamp_ms = 1_000_000,
        .timestamp_source = .monotonic,
        .sequence = 7,
        .provenance = .fake_adapter,
    }, .agent, policy, 1_000_500);
    try std.testing.expectEqual(health.HealthStatus.healthy, fresh.status);
    try std.testing.expectEqual(@as(u64, 500), fresh.age_ms.?);
    try std.testing.expectEqual(health.Provenance.fake_adapter, fresh.provenance);

    const stale = try health.evaluateHeartbeat(.{
        .source = .adapter,
        .source_id = "fake-adapter",
        .timestamp_ms = 1_000_000,
        .timestamp_source = .monotonic,
        .provenance = .fake_adapter,
    }, .adapter, policy, 1_001_500);
    try std.testing.expectEqual(health.HealthStatus.degraded, stale.status);
    try std.testing.expect(stale.finding != null);

    const expired = try health.evaluateHeartbeat(.{
        .source = .px4_sitl,
        .source_id = "px4-sitl",
        .timestamp_ms = 1_000_000,
        .timestamp_source = .monotonic,
        .provenance = .px4_sitl,
    }, .px4_sitl, policy, 1_003_500);
    try std.testing.expectEqual(health.HealthStatus.critical, expired.status);
    try std.testing.expectEqual(health.Provenance.px4_sitl, expired.provenance);

    const missing = try health.evaluateMissingHeartbeat(.ardupilot_sitl, policy, 1_000_000, .ardupilot_sitl);
    try std.testing.expectEqual(health.HealthStatus.unavailable, missing.status);
    try std.testing.expectEqual(health.Provenance.ardupilot_sitl, missing.provenance);
}

test "phase 37 telemetry audit and resource health produce conservative findings" {
    var loaded = try edge.policy.loadFromSlice(std.testing.allocator, watchdog_policy_yaml, "phase37-watchdog.yaml", .{});
    defer loaded.deinit();

    var stale_state = vehicleState(.fake_adapter, 80, .fresh, 1_000_000);
    stale_state.gps_state = null;
    stale_state.home_position = null;
    var telemetry_report = try health.evaluateTelemetryFreshness(std.testing.allocator, loaded.value.watchdog, stale_state, .{
        .now_ms = 1_003_000,
        .scenario_id = "stale-telemetry-deny-movement",
    });
    defer telemetry_report.deinit();
    try std.testing.expectEqual(health.HealthStatus.degraded, telemetry_report.overall_status);
    try std.testing.expect(telemetry_report.hasDomain(.telemetry));
    try std.testing.expect(telemetry_report.hasDomain(.gps_state));
    try std.testing.expect(telemetry_report.hasDomain(.vehicle_state));
    try std.testing.expectEqual(health.DegradedBehavior.deny_movement, telemetry_report.recommended_behavior);

    var audit_report = try health.audit_health.evaluateAuditHealth(std.testing.allocator, .{
        .writer_available = false,
        .append_failed = true,
        .hash_chain_verified = false,
        .append_latency_ms = 250,
        .provenance = .fake_adapter,
        .now_ms = 1_000_000,
    }, loaded.value.watchdog);
    defer audit_report.deinit();
    try std.testing.expectEqual(health.HealthStatus.critical, audit_report.overall_status);
    try std.testing.expectEqual(health.DegradedBehavior.fail_closed, audit_report.recommended_behavior);
    try std.testing.expect(audit_report.hasDomain(.audit_writer));

    var resource_report = try health.resource_health.evaluateResourceHealth(std.testing.allocator, .{
        .event_queue_depth = 1500,
        .memory_mb = 128,
        .cpu_percent = 20,
        .now_ms = 1_000_000,
        .provenance = .bench,
    }, loaded.value.watchdog);
    defer resource_report.deinit();
    try std.testing.expectEqual(health.HealthStatus.degraded, resource_report.overall_status);
    try std.testing.expect(resource_report.hasDomain(.resource_usage));
}

test "phase 37 degraded-mode decisions deny unsafe commands and preserve emergency policy" {
    var loaded = try edge.policy.loadFromSlice(std.testing.allocator, watchdog_policy_yaml, "phase37-watchdog.yaml", .{});
    defer loaded.deinit();
    const report = health.HealthReport.initStatic(.{
        .overall_status = .degraded,
        .recommended_behavior = .deny_movement,
        .findings = &.{health.HealthFinding.init(.{
            .finding_id = "health-telemetry-stale",
            .domain = .telemetry,
            .status = .degraded,
            .severity = .high,
            .reason = "position stale",
            .observed_value = "age_ms=3000",
            .threshold = "position_max_age_ms=1000",
            .timestamp_ms = 1_003_000,
            .provenance = .fake_adapter,
            .recommended_behavior = .deny_movement,
        })},
    });

    const state = vehicleState(.fake_adapter, 80, .fresh, 1_000_000);
    const movement = health.decideForCommand(&loaded.value, report, request(.set_waypoint), state, .{ .mode = .strict, .now_ms = 1_003_000, .non_interactive = true });
    try std.testing.expectEqual(decision.deny, movement.decision);
    try std.testing.expectEqual(health.DegradedBehavior.deny_movement, movement.behavior);

    const land = health.decideForCommand(&loaded.value, report, request(.land), state, .{ .mode = .strict, .now_ms = 1_003_000, .non_interactive = true });
    try std.testing.expectEqual(decision.allow, land.decision);
    try std.testing.expectEqual(health.DegradedBehavior.allow_policy_emergency_only, land.behavior);

    var no_home = state;
    no_home.home_position = null;
    const rth = health.decideForCommand(&loaded.value, report, request(.return_to_home), no_home, .{ .mode = .strict, .now_ms = 1_003_000, .non_interactive = true });
    try std.testing.expectEqual(decision.deny, rth.decision);

    var fail_closed = report;
    fail_closed.overall_status = .critical;
    fail_closed.recommended_behavior = .fail_closed;
    const disable = health.decideForCommand(&loaded.value, fail_closed, request(.disable_failsafe), state, .{ .mode = .ci, .now_ms = 1_003_000, .non_interactive = true });
    try std.testing.expectEqual(decision.deny, disable.decision);
    try std.testing.expectEqual(health.DegradedBehavior.fail_closed, disable.behavior);

    const fail_closed_land = health.decideForCommand(&loaded.value, fail_closed, request(.land), state, .{ .mode = .ci, .now_ms = 1_003_000, .non_interactive = true });
    try std.testing.expectEqual(decision.deny, fail_closed_land.decision);
    try std.testing.expectEqual(health.DegradedBehavior.fail_closed, fail_closed_land.behavior);
}

test "phase 37 safety evaluator consumes health report and emits health findings" {
    var loaded = try edge.policy.loadFromSlice(std.testing.allocator, watchdog_policy_yaml, "phase37-watchdog.yaml", .{});
    defer loaded.deinit();
    const state = vehicleState(.fake_adapter, 80, .fresh, 1_000_000);
    var report = health.HealthReport.initStatic(.{
        .overall_status = .critical,
        .recommended_behavior = .deny_high_risk,
        .findings = &.{health.HealthFinding.init(.{
            .finding_id = "health-agent-expired",
            .domain = .agent,
            .status = .critical,
            .severity = .critical,
            .reason = "agent heartbeat expired",
            .observed_value = "age_ms=3000",
            .threshold = "agent_max_age_ms=1000",
            .timestamp_ms = 1_003_000,
            .provenance = .fake_adapter,
            .recommended_behavior = .deny_high_risk,
            .audit_event_reference = "health.watchdog.finding",
        })},
    });

    var evaluation = try edge.safety.evaluateSafety(std.testing.allocator, &loaded.value, state, request(.takeoff), .{
        .mode = .ci,
        .now_ms = 1_003_000,
        .non_interactive = true,
        .health_report = &report,
    });
    defer evaluation.deinit();
    try std.testing.expectEqual(decision.deny, evaluation.decision.result);
    try std.testing.expect(evaluation.hasFindingCategory(.health));
    try std.testing.expect(evaluation.hasAuditEvent("health.watchdog.finding"));
    try std.testing.expect(evaluation.hasAuditEvent("health.command_denied"));
    try std.testing.expect(std.mem.indexOf(u8, evaluation.explanation, "health") != null);
}

test "phase 37 audit health event reference is preserved in safety evaluation" {
    var loaded = try edge.policy.loadFromSlice(std.testing.allocator, watchdog_policy_yaml, "phase37-watchdog.yaml", .{});
    defer loaded.deinit();
    const state = vehicleState(.fake_adapter, 80, .fresh, 1_000_000);
    var report = try health.audit_health.evaluateAuditHealth(std.testing.allocator, .{
        .writer_available = false,
        .append_failed = true,
        .hash_chain_verified = false,
        .append_latency_ms = 250,
        .provenance = .fake_adapter,
        .now_ms = 1_003_000,
    }, loaded.value.watchdog);
    defer report.deinit();

    var evaluation = try edge.safety.evaluateSafety(std.testing.allocator, &loaded.value, state, request(.takeoff), .{
        .mode = .ci,
        .now_ms = 1_003_000,
        .non_interactive = true,
        .health_report = &report,
    });
    defer evaluation.deinit();
    try std.testing.expectEqual(decision.deny, evaluation.decision.result);
    try std.testing.expect(evaluation.hasAuditEvent("health.audit.failure"));
    try std.testing.expect(evaluation.hasAuditEvent("health.command_denied"));
}

test "phase 37 MAVLink heartbeat creates link health and preserves provenance" {
    const allocator = std.testing.allocator;
    const frame_bytes = try edge.mavlink.fake_transport.frameHeartbeatV1(allocator, .{ .seq = 9, .sysid = 42, .compid = 191 });
    defer allocator.free(frame_bytes);
    const frame = try edge.mavlink.framing.parseFrame(frame_bytes);

    const heartbeat = try health.heartbeatFromMavlinkFrame(frame, 1_000_000, .fake_adapter);
    try std.testing.expectEqual(health.HeartbeatSource.mavlink, heartbeat.source);
    try std.testing.expectEqual(@as(u64, 9), heartbeat.sequence.?);
    try std.testing.expectEqual(health.Provenance.fake_adapter, heartbeat.provenance);

    const status = try health.evaluateHeartbeat(heartbeat, .mavlink, health.WatchdogPolicy{}, 1_000_250);
    try std.testing.expectEqual(health.HealthStatus.healthy, status.status);
}

test "phase 37 examples docs and event maps expose health without real-flight claims" {
    const allocator = std.testing.allocator;
    const policy_text = try std.fs.cwd().readFileAlloc(allocator, "examples/edge/health/policies/watchdog-strict.yaml", 128 * 1024);
    defer allocator.free(policy_text);
    var loaded = try edge.policy.loadFromSlice(allocator, policy_text, "examples/edge/health/policies/watchdog-strict.yaml", .{});
    defer loaded.deinit();
    try std.testing.expect(loaded.value.watchdog.enabled);

    const scenario_text = try std.fs.cwd().readFileAlloc(allocator, "examples/edge/health/scenarios/stale-agent-deny-high-risk.yaml", 64 * 1024);
    defer allocator.free(scenario_text);
    try std.testing.expect(std.mem.indexOf(u8, scenario_text, "fake_adapter") != null);
    try std.testing.expect(std.mem.indexOf(u8, scenario_text, "real_flight") == null);

    const docs = [_][]const u8{
        "docs/edge/runtime-health.md",
        "docs/edge/watchdog.md",
        "docs/edge/degraded-modes.md",
        "docs/edge/heartbeat-monitoring.md",
        "docs/edge/audit-health.md",
        "docs/edge/health-redteam.md",
        "docs/edge/safety-case.md",
        "docs/edge/simulation-vs-flight.md",
        "packages/edge/README.md",
    };
    for (docs) |path| {
        const text = try std.fs.cwd().readFileAlloc(allocator, path, 256 * 1024);
        defer allocator.free(text);
        try std.testing.expect(std.mem.indexOf(u8, text, "not real-flight readiness") != null or std.mem.indexOf(u8, text, "no real-flight readiness") != null);
        try std.testing.expect(std.mem.indexOf(u8, text, "regulatory certification") != null);
        try std.testing.expect(std.mem.indexOf(u8, text, "autopilot replacement") != null);
    }

    try std.testing.expect(edge.audit.edge_event.isKnown("health.watchdog.finding"));
    try std.testing.expect(edge.audit.edge_event.isKnown("health.command_denied"));
}

test "phase 37 health red-team fixtures execute and safety-case reports health evidence" {
    const allocator = std.testing.allocator;
    var fixture_set = try edge.redteam.runner.discover(allocator, .{ .category = .health });
    defer fixture_set.deinit();
    try std.testing.expect(fixture_set.fixtures.len >= 10);

    var suite = try edge.redteam.runner.runSuite(allocator, fixture_set, .{ .output_dir = ".zig-cache/phase37-health-redteam", .ci = true });
    defer suite.deinit();
    try std.testing.expect(suite.allRequiredPassed());

    var generated = try edge.audit.safety_case.generate(allocator, .{
        .policy_path = "examples/edge/health/policies/watchdog-strict.yaml",
        .scenario_path = "examples/edge/health/scenarios/stale-agent-deny-high-risk.yaml",
    });
    defer generated.deinit();
    try std.testing.expectEqual(edge.audit.safety_report.ScenarioResultStatus.passed, generated.status);
    const report_json_path = try std.fs.path.join(allocator, &.{ generated.session_dir, "safety-report.json" });
    defer allocator.free(report_json_path);
    const report_json = try std.fs.cwd().readFileAlloc(allocator, report_json_path, 256 * 1024);
    defer allocator.free(report_json);
    try std.testing.expect(std.mem.indexOf(u8, report_json, "\"runtime_health\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, report_json, "\"category\":\"health\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, report_json, "health.watchdog.finding") != null);

    const runtime_health_path = try std.fs.path.join(allocator, &.{ generated.session_dir, "evidence", "runtime-health.json" });
    defer allocator.free(runtime_health_path);
    const runtime_health = try std.fs.cwd().readFileAlloc(allocator, runtime_health_path, 128 * 1024);
    defer allocator.free(runtime_health);
    try std.testing.expect(std.mem.indexOf(u8, runtime_health, "\"watchdog_findings\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, runtime_health, "real_flight") != null);
}

fn expectPolicyError(expected: anyerror, text: []const u8) !void {
    try std.testing.expectError(expected, edge.policy.loadFromSlice(std.testing.allocator, text, "invalid-watchdog.yaml", .{}));
}

fn expectPolicyReplacementError(expected: anyerror, needle: []const u8, replacement: []const u8) !void {
    const allocator = std.testing.allocator;
    const size = std.mem.replacementSize(u8, watchdog_policy_yaml, needle, replacement);
    const text = try allocator.alloc(u8, size);
    defer allocator.free(text);
    _ = std.mem.replace(u8, watchdog_policy_yaml, needle, replacement, text);
    try expectPolicyError(expected, text);
}

fn request(action: domain.commands.CommandAction) domain.commands.CommandRequest {
    const params: domain.commands.CommandParameters = switch (action) {
        .takeoff => .{ .altitude = .{ .altitude_m = 20, .altitude_reference = .amsl } },
        .set_waypoint => .{ .waypoint = .{ .latitude_deg = 37.0001, .longitude_deg = -122.0, .altitude_m = 20, .altitude_reference = .amsl } },
        .set_velocity => .{ .velocity = .{ .vx_mps = 3, .vy_mps = 0, .vz_mps = 0, .frame = .local_ned } },
        else => .none,
    };
    return domain.commands.CommandRequest.init(.{
        .command_id = "phase37-command",
        .vehicle_id = .{ .value = "edge-vehicle-1" },
        .action = action,
        .parameters = params,
        .actor = "phase37-test",
        .timestamp = .{ .value = 1_000_000, .source = .monotonic },
        .source = .fake_adapter,
    });
}

fn vehicleState(provenance: domain.state.StateProvenance, battery_percent: f64, freshness: domain.state.StateFreshness, timestamp_ms: i128) domain.state.VehicleState {
    const center = domain.coordinates.GeoPoint{ .latitude_deg = 37, .longitude_deg = -122, .altitude_m = 20, .altitude_reference = .amsl };
    return .{
        .vehicle_id = .{ .value = "edge-vehicle-1" },
        .vehicle_kind = .drone_multirotor,
        .autopilot_kind = .px4,
        .mode = .guided,
        .arm_state = .armed,
        .position = center,
        .battery_state = .{ .percent_remaining = battery_percent, .voltage_v = 15.2, .current_a = 2.1, .source = .monotonic },
        .gps_state = .{ .fix_type = .three_d, .satellites_visible = 12, .hdop = 0.8, .is_valid = true, .source = .monotonic },
        .link_state = .{ .connected = true, .last_heartbeat = .{ .value = timestamp_ms, .source = .monotonic }, .packet_loss_percent = 0.1, .source = .monotonic },
        .control_authority = .onboard_agent,
        .home_position = center,
        .timestamp = .{ .value = timestamp_ms, .source = .monotonic },
        .state_freshness = freshness,
        .provenance = provenance,
    };
}
