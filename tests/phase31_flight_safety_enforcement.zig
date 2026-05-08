const std = @import("std");
const edge = @import("aegis_edge");

const domain = edge.domain;
const safety = edge.safety;

const strict_policy_yaml =
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
    \\
    \\commands:
    \\  allow:
    \\    - read_telemetry
    \\    - read_vehicle_state
    \\    - land
    \\    - return_to_home
    \\  ask:
    \\    - arm
    \\    - takeoff
    \\    - upload_mission
    \\    - start_mission
    \\    - set_waypoint
    \\    - set_velocity
    \\    - set_altitude
    \\    - set_mode
    \\  deny:
    \\    - disable_failsafe
    \\    - disable_geofence
    \\    - raw_actuator_output
    \\    - payload_release
    \\    - firmware_update
    \\    - override_operator
    \\    - companion_computer_reboot
    \\
    \\network:
    \\  mode: allowlist
    \\
    \\audit:
    \\  level: full
    \\  redact_secrets: true
;

test "phase 31 compiled envelope rejects invalid limits and unsupported features" {
    var loaded = try edge.policy.loadFromSlice(std.testing.allocator, strict_policy_yaml, "phase31-strict.yaml", .{});
    defer loaded.deinit();

    var compiled = try safety.compileEnvelope(std.testing.allocator, &loaded.value);
    defer compiled.deinit();
    try std.testing.expectEqual(@as(usize, 1), compiled.geofence_count);
    try std.testing.expect(compiled.hasRule("commands.deny[0]"));
    try std.testing.expect(compiled.hasUnsupportedFeature("polygon_geofence") == false);

    try expectPolicyError(error.InvalidSpeedLimit, replaceFirst(strict_policy_yaml, "max_horizontal_mps: 8", "max_horizontal_mps: 0"));
    try expectPolicyError(error.InvalidGeofenceRadius, replaceFirst(strict_policy_yaml, "max_radius_m: 500", "max_radius_m: 0"));
    try expectPolicyError(error.UnsupportedGeofenceShape, replaceFirst(strict_policy_yaml, "type: circle", "type: polygon"));
    try expectPolicyError(error.UnknownAltitudeReference, replaceFirst(strict_policy_yaml, "altitude_reference: amsl", "altitude_reference: unknown"));
}

test "phase 31 safety evaluator returns structured findings for envelope violations" {
    var loaded = try edge.policy.loadFromSlice(std.testing.allocator, strict_policy_yaml, "phase31-strict.yaml", .{});
    defer loaded.deinit();
    const state = freshState(.px4, .fake_adapter, 80, .fresh);

    var outside = try safety.evaluateSafety(std.testing.allocator, &loaded.value, state, waypointRequest(37.0100, -122.0000, 20), context(.ask));
    defer outside.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, outside.decision.result);
    try std.testing.expect(outside.hasFindingCategory(.geofence));
    try std.testing.expect(outside.hasAuditEvent("safety.finding_created"));
    try std.testing.expect(outside.hasAuditEvent("safety.geofence_violation"));
    try std.testing.expectEqualStrings("geofence.circle", outside.findings[0].constraint_id.?);
    try std.testing.expectEqual(safety.findings.Severity.high, outside.findings[0].severity);

    var above = try safety.evaluateSafety(std.testing.allocator, &loaded.value, state, waypointRequest(37.0005, -122.0000, 121), context(.ask));
    defer above.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, above.decision.result);
    try std.testing.expect(above.hasFindingCategory(.altitude));

    var velocity = try safety.evaluateSafety(std.testing.allocator, &loaded.value, state, request(.set_velocity, .{ .velocity = .{ .vx_mps = 9, .vy_mps = 0, .vz_mps = -3, .frame = .local_ned } }), context(.ask));
    defer velocity.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, velocity.decision.result);
    try std.testing.expect(velocity.hasFindingCategory(.velocity));

    const low_battery = freshState(.px4, .fake_adapter, 20, .fresh);
    var takeoff = try safety.evaluateSafety(std.testing.allocator, &loaded.value, low_battery, request(.takeoff, .{ .altitude = .{ .altitude_m = 20, .altitude_reference = .amsl } }), context(.strict));
    defer takeoff.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, takeoff.decision.result);
    try std.testing.expectEqual(domain.commands.CommandAction.return_to_home, takeoff.recommended_fallback.?);
    try std.testing.expect(takeoff.hasFindingCategory(.battery));
}

test "phase 31 command risk defaults deny critical and non-interactive ask commands" {
    var loaded = try edge.policy.loadFromSlice(std.testing.allocator, strict_policy_yaml, "phase31-strict.yaml", .{});
    defer loaded.deinit();
    const state = freshState(.px4, .fake_adapter, 80, .fresh);

    var ci_arm = try safety.evaluateSafety(std.testing.allocator, &loaded.value, state, request(.arm, .none), .{ .mode = .ci, .now_ms = 1_000_500, .non_interactive = true });
    defer ci_arm.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, ci_arm.decision.result);
    try std.testing.expect(!ci_arm.ci_may_proceed);
    try std.testing.expect(ci_arm.operator_approval_required);

    const critical = [_]domain.commands.CommandAction{ .disable_failsafe, .disable_geofence, .raw_actuator_output, .override_operator, .firmware_update, .companion_computer_reboot, .payload_release };
    for (critical) |action| {
        var result = try safety.evaluateSafety(std.testing.allocator, &loaded.value, state, request(action, .none), context(.strict));
        defer result.deinit();
        try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, result.decision.result);
        try std.testing.expect(result.hasFindingCategory(.command_risk) or result.hasFindingCategory(.authority_constraint));
    }
}

test "phase 31 freshness mode authority and emergency-safe behavior are conservative" {
    var loaded = try edge.policy.loadFromSlice(std.testing.allocator, strict_policy_yaml, "phase31-strict.yaml", .{});
    defer loaded.deinit();

    var stale_waypoint = try safety.evaluateSafety(std.testing.allocator, &loaded.value, freshState(.px4, .fake_adapter, 80, .stale), waypointRequest(37.0005, -122.0000, 20), .{ .mode = .strict, .now_ms = 1_005_000 });
    defer stale_waypoint.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, stale_waypoint.decision.result);
    try std.testing.expect(stale_waypoint.hasFindingCategory(.stale_state));

    var stale_land = try safety.evaluateSafety(std.testing.allocator, &loaded.value, freshState(.px4, .fake_adapter, 80, .stale), request(.land, .none), .{ .mode = .strict, .now_ms = 1_005_000 });
    defer stale_land.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.allow, stale_land.decision.result);
    try std.testing.expectEqual(domain.commands.CommandAction.land, stale_land.recommended_fallback orelse .land);

    var no_home = freshState(.px4, .fake_adapter, 80, .stale);
    no_home.home_position = null;
    var stale_rth = try safety.evaluateSafety(std.testing.allocator, &loaded.value, no_home, request(.return_to_home, .none), .{ .mode = .strict, .now_ms = 1_005_000 });
    defer stale_rth.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, stale_rth.decision.result);

    var human = freshState(.px4, .fake_adapter, 80, .fresh);
    human.mode = .manual;
    human.control_authority = .human_operator;
    var human_result = try safety.evaluateSafety(std.testing.allocator, &loaded.value, human, waypointRequest(37.0005, -122.0000, 20), context(.strict));
    defer human_result.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, human_result.decision.result);
    try std.testing.expect(human_result.hasFindingCategory(.authority_constraint));

    var failsafe = freshState(.px4, .fake_adapter, 80, .fresh);
    failsafe.control_authority = .failsafe;
    var failsafe_result = try safety.evaluateSafety(std.testing.allocator, &loaded.value, failsafe, request(.takeoff, .{ .altitude = .{ .altitude_m = 20, .altitude_reference = .amsl } }), context(.strict));
    defer failsafe_result.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, failsafe_result.decision.result);
}

test "phase 31 disabled stale emergency actions deny despite command allow rules" {
    const land_disabled_policy = replaceFirst(strict_policy_yaml, "allow_land: true", "allow_land: false");
    var land_loaded = try edge.policy.loadFromSlice(std.testing.allocator, land_disabled_policy, "phase31-land-disabled.yaml", .{});
    defer land_loaded.deinit();

    var stale_land = try safety.evaluateSafety(std.testing.allocator, &land_loaded.value, freshState(.px4, .fake_adapter, 80, .stale), request(.land, .none), .{ .mode = .strict, .now_ms = 1_005_000 });
    defer stale_land.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, stale_land.decision.result);
    try std.testing.expect(stale_land.hasFindingCategory(.stale_state));
    try std.testing.expect(stale_land.hasAuditEvent("safety.stale_state_denied"));

    const rth_disabled_policy = replaceFirst(strict_policy_yaml, "allow_return_to_home: true", "allow_return_to_home: false");
    var rth_loaded = try edge.policy.loadFromSlice(std.testing.allocator, rth_disabled_policy, "phase31-rth-disabled.yaml", .{});
    defer rth_loaded.deinit();

    var stale_rth = try safety.evaluateSafety(std.testing.allocator, &rth_loaded.value, freshState(.px4, .fake_adapter, 80, .stale), request(.return_to_home, .none), .{ .mode = .strict, .now_ms = 1_005_000 });
    defer stale_rth.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, stale_rth.decision.result);
    try std.testing.expect(stale_rth.hasFindingCategory(.stale_state));
    try std.testing.expect(stale_rth.hasAuditEvent("safety.stale_state_denied"));
}

test "phase 31 mission safety evaluates every item and blocks unsafe mission starts" {
    var loaded = try edge.policy.loadFromSlice(std.testing.allocator, strict_policy_yaml, "phase31-strict.yaml", .{});
    defer loaded.deinit();
    const state = freshState(.px4, .fake_adapter, 80, .fresh);

    const safe_items = [_]domain.mission.Waypoint{
        .{ .sequence = 0, .position = .{ .latitude_deg = 37.0001, .longitude_deg = -122.0000, .altitude_m = 20, .altitude_reference = .amsl } },
        .{ .sequence = 1, .position = .{ .latitude_deg = 37.0002, .longitude_deg = -122.0000, .altitude_m = 25, .altitude_reference = .amsl } },
    };
    var safe = try safety.evaluateMissionSafety(std.testing.allocator, &loaded.value, state, .{
        .mission_id = .{ .value = "mission-safe" },
        .waypoints = safe_items[0..],
        .status = .draft,
    }, context(.ask));
    defer safe.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.ask, safe.decision.result);

    const unsafe_items = [_]domain.mission.Waypoint{
        .{ .sequence = 0, .position = .{ .latitude_deg = 37.0001, .longitude_deg = -122.0000, .altitude_m = 20, .altitude_reference = .amsl } },
        .{ .sequence = 1, .position = .{ .latitude_deg = 37.0100, .longitude_deg = -122.0000, .altitude_m = 20, .altitude_reference = .amsl } },
    };
    var unsafe = try safety.evaluateMissionSafety(std.testing.allocator, &loaded.value, state, .{
        .mission_id = .{ .value = "mission-outside" },
        .waypoints = unsafe_items[0..],
        .status = .draft,
    }, context(.ask));
    defer unsafe.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, unsafe.decision.result);
    try std.testing.expect(unsafe.hasFindingCategory(.mission));
    try std.testing.expect(unsafe.hasAuditEvent("safety.mission_item_denied"));

    const duplicate_items = [_]domain.mission.Waypoint{
        .{ .sequence = 0, .position = .{ .latitude_deg = 37.0001, .longitude_deg = -122.0000, .altitude_m = 20, .altitude_reference = .amsl } },
        .{ .sequence = 0, .position = .{ .latitude_deg = 37.0002, .longitude_deg = -122.0000, .altitude_m = 25, .altitude_reference = .amsl } },
    };
    var duplicate = try safety.evaluateMissionSafety(std.testing.allocator, &loaded.value, state, .{
        .mission_id = .{ .value = "mission-duplicate" },
        .waypoints = duplicate_items[0..],
        .status = .draft,
    }, context(.ask));
    defer duplicate.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, duplicate.decision.result);
    try std.testing.expect(duplicate.hasFindingCategory(.mission));

    var start = try safety.evaluateSafety(std.testing.allocator, &loaded.value, state, request(.start_mission, .{ .mission_ref = "mission-unsafe" }), context(.strict));
    defer start.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, start.decision.result);
    try std.testing.expect(start.hasFindingCategory(.mission));
}

fn expectPolicyError(expected: anyerror, text: []const u8) !void {
    var loaded = edge.policy.loadFromSlice(std.testing.allocator, text, "phase31-invalid.yaml", .{}) catch |err| {
        try std.testing.expectEqual(expected, err);
        return;
    };
    defer loaded.deinit();
    return error.ExpectedPolicyFailure;
}

fn replaceFirst(comptime haystack: []const u8, comptime needle: []const u8, comptime replacement: []const u8) []const u8 {
    return comptime blk: {
        const index = std.mem.indexOf(u8, haystack, needle) orelse @compileError("needle missing");
        break :blk haystack[0..index] ++ replacement ++ haystack[index + needle.len ..];
    };
}

fn context(mode: edge.policy.EvaluationMode) safety.EvaluationContext {
    return .{ .mode = mode, .now_ms = 1_000_500, .non_interactive = mode == .ci };
}

fn request(action: domain.commands.CommandAction, params: domain.commands.CommandParameters) domain.commands.CommandRequest {
    return domain.commands.CommandRequest.init(.{
        .command_id = "cmd-phase31",
        .vehicle_id = .{ .value = "edge-vehicle-1" },
        .action = action,
        .parameters = params,
        .actor = "phase31-test-agent",
        .timestamp = .{ .value = 1_000_100, .source = .monotonic },
        .source = .fake_adapter,
    });
}

fn waypointRequest(lat: f64, lon: f64, alt: f64) domain.commands.CommandRequest {
    return request(.set_waypoint, .{ .waypoint = .{
        .latitude_deg = lat,
        .longitude_deg = lon,
        .altitude_m = alt,
        .altitude_reference = .amsl,
    } });
}

fn freshState(autopilot: domain.vehicle.AutopilotKind, provenance: domain.state.StateProvenance, percent: f64, freshness: domain.state.StateFreshness) domain.state.VehicleState {
    return .{
        .vehicle_id = .{ .value = "edge-vehicle-1" },
        .vehicle_kind = .drone_multirotor,
        .autopilot_kind = autopilot,
        .mode = .guided,
        .arm_state = .armed,
        .position = .{ .latitude_deg = 37.0000, .longitude_deg = -122.0000, .altitude_m = 20, .altitude_reference = .amsl },
        .battery_state = .{ .percent_remaining = percent, .voltage_v = 15.2, .current_a = 2.1, .source = .monotonic },
        .control_authority = .onboard_agent,
        .home_position = .{ .latitude_deg = 37.0000, .longitude_deg = -122.0000, .altitude_m = 0, .altitude_reference = .amsl },
        .timestamp = .{ .value = 1_000_000, .source = .monotonic },
        .state_freshness = freshness,
        .provenance = provenance,
    };
}
