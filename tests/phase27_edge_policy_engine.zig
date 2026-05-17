const std = @import("std");
const edge = @import("aegis_edge");

const domain = edge.domain;
const policy = edge.policy;

const valid_policy_yaml =
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
    \\    max_radius_m: 500
    \\    altitude_floor_m: 2
    \\    altitude_ceiling_m: 120
    \\    altitude_reference: amsl
    \\    boundary_action: deny
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
    \\  deny:
    \\    - disable_failsafe
    \\    - disable_geofence
    \\    - raw_actuator_output
    \\    - firmware_update
    \\    - override_operator
    \\
    \\network:
    \\  mode: allowlist
    \\
    \\audit:
    \\  level: full
    \\  redact_secrets: true
;

test "phase 27 edge policy loading validates versioned safety shape" {
    var loaded = try policy.loadFromSlice(std.testing.allocator, valid_policy_yaml, "valid-edge-policy.yaml", .{});
    defer loaded.deinit();

    try std.testing.expectEqual(@as(u32, 1), loaded.value.version);
    try std.testing.expectEqual(domain.vehicle.VehicleKind.drone_multirotor, loaded.value.vehicle.kind);
    try std.testing.expectEqual(domain.vehicle.AdapterKind.fake, loaded.value.vehicle.adapter);
    try std.testing.expectEqual(domain.geofence.BoundaryAction.deny, loaded.value.safety.geofence.?.boundary_action);
    try std.testing.expectEqual(domain.safety_envelope.CommandDisposition.deny, loaded.value.commands.resolve(.disable_failsafe));
}

test "phase 27 policy loader supports geofence home position in YAML and JSON" {
    const yaml_with_home = replaceFirst(valid_policy_yaml,
        \\    max_radius_m: 500
    ,
        \\    home_position:
        \\      latitude_deg: 37.100000
        \\      longitude_deg: -122.100000
        \\      altitude_m: 5
        \\      altitude_reference: amsl
        \\    max_radius_m: 500
    );
    var yaml_loaded = try policy.loadFromSlice(std.testing.allocator, yaml_with_home, "home-position.yaml", .{});
    defer yaml_loaded.deinit();
    const yaml_home = yaml_loaded.value.safety.geofence.?.home_position orelse return error.TestUnexpectedResult;
    try std.testing.expectApproxEqAbs(@as(f64, 37.1), yaml_home.latitude_deg, 0.000001);
    try std.testing.expectApproxEqAbs(@as(f64, -122.1), yaml_home.longitude_deg, 0.000001);
    try std.testing.expectEqual(domain.coordinates.AltitudeReference.amsl, yaml_home.altitude_reference);

    const json_with_home =
        \\{
        \\  "version": 1,
        \\  "vehicle": { "kind": "drone_multirotor", "autopilot": "px4", "adapter": "fake" },
        \\  "safety": {
        \\    "state_freshness": { "max_state_age_ms": 1000, "deny_commands_on_stale_state": true },
        \\    "geofence": {
        \\      "type": "circle",
        \\      "center": { "latitude_deg": 37.0, "longitude_deg": -122.0, "altitude_m": 0, "altitude_reference": "amsl" },
        \\      "home_position": { "latitude_deg": 37.2, "longitude_deg": -122.2, "altitude_m": 6, "altitude_reference": "amsl" },
        \\      "max_radius_m": 500,
        \\      "altitude_floor_m": 2,
        \\      "altitude_ceiling_m": 120,
        \\      "altitude_reference": "amsl",
        \\      "boundary_action": "deny"
        \\    },
        \\    "velocity": { "max_horizontal_mps": 8, "max_vertical_mps": 2 },
        \\    "battery": { "deny_takeoff_below_percent": 35, "return_home_below_percent": 25, "land_below_percent": 15 }
        \\  },
        \\  "commands": {
        \\    "allow": ["read_telemetry", "read_vehicle_state", "land", "return_to_home"],
        \\    "ask": ["arm", "takeoff", "set_waypoint", "set_velocity", "set_altitude"],
        \\    "deny": ["disable_failsafe", "disable_geofence", "raw_actuator_output"]
        \\  },
        \\  "network": { "mode": "allowlist" },
        \\  "audit": { "level": "full", "redact_secrets": true }
        \\}
    ;
    var json_loaded = try policy.loadFromSlice(std.testing.allocator, json_with_home, "home-position.json", .{});
    defer json_loaded.deinit();
    const json_home = json_loaded.value.safety.geofence.?.home_position orelse return error.TestUnexpectedResult;
    try std.testing.expectApproxEqAbs(@as(f64, 37.2), json_home.latitude_deg, 0.000001);
    try std.testing.expectApproxEqAbs(@as(f64, -122.2), json_home.longitude_deg, 0.000001);
}

test "phase 27 policy validation rejects unsafe or ambiguous policy input" {
    try expectPolicyError(error.MissingPolicyVersion,
        \\vehicle:
        \\  kind: drone_multirotor
    );
    try expectPolicyError(error.UnknownVehicleKind, replaceFirst(valid_policy_yaml, "drone_multirotor", "spacecraft"));
    try expectPolicyError(error.UnknownAltitudeReference, replaceFirst(valid_policy_yaml, "altitude_reference: amsl", "altitude_reference: pressure_altitude"));
    try expectPolicyError(error.InvalidLatitude, replaceFirst(valid_policy_yaml, "latitude_deg: 37.000000", "latitude_deg: 91"));
    try expectPolicyError(error.InvalidLongitude, replaceFirst(valid_policy_yaml, "longitude_deg: -122.000000", "longitude_deg: -181"));
    try expectPolicyError(error.InvalidGeofenceRadius, replaceFirst(valid_policy_yaml, "max_radius_m: 500", "max_radius_m: -1"));
    try expectPolicyError(error.InvalidAltitudeLimit, replaceFirst(valid_policy_yaml, "altitude_ceiling_m: 120", "altitude_ceiling_m: 1"));
    try expectPolicyError(error.InvalidSpeedLimit, replaceFirst(valid_policy_yaml, "max_horizontal_mps: 8", "max_horizontal_mps: -1"));
    try expectPolicyError(error.InvalidBatteryThreshold, replaceFirst(valid_policy_yaml, "return_home_below_percent: 25", "return_home_below_percent: 40"));
    try expectPolicyError(error.DuplicateCommandPolicyEntry, replaceFirst(valid_policy_yaml, "    - set_altitude", "    - set_altitude\n    - land"));
    try expectPolicyError(error.AmbiguousStateFreshnessPolicy, replaceFirst(valid_policy_yaml, "deny_commands_on_stale_state: true", "deny_commands_on_stale_state: false"));
    try expectPolicyError(error.UnsupportedGeofenceShape, replaceFirst(valid_policy_yaml, "type: circle", "type: allowed_polygon"));
    try expectPolicyError(error.InvalidNetworkPolicy, replaceFirst(valid_policy_yaml, "mode: allowlist", "mode: internet"));
    try expectPolicyError(error.InvalidAuditPolicy, replaceFirst(valid_policy_yaml, "level: full", "level: noisy"));
}

test "phase 27 command policy decisions use Core vocabulary and deny priority" {
    var loaded = try policy.loadFromSlice(std.testing.allocator, valid_policy_yaml, "valid-edge-policy.yaml", .{});
    defer loaded.deinit();

    const state = freshState(1_000_000);
    const now_ms: i128 = 1_000_500;

    var read_eval = try policy.evaluateEdgeAction(std.testing.allocator, &loaded.value, request(.read_telemetry, .none, 1_000_100), state, .{ .mode = .strict, .now_ms = now_ms });
    defer read_eval.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.allow, read_eval.decision.result);
    try std.testing.expect(read_eval.decision.ci_may_proceed);
    try std.testing.expect(read_eval.usesCoreDecisionModel());

    var takeoff_eval = try policy.evaluateEdgeAction(std.testing.allocator, &loaded.value, request(.takeoff, .{ .altitude = .{ .altitude_m = 20, .altitude_reference = .amsl } }, 1_000_100), state, .{ .mode = .ask, .now_ms = now_ms });
    defer takeoff_eval.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.ask, takeoff_eval.decision.result);
    try std.testing.expect(takeoff_eval.decision.requires_user);

    var ci_eval = try policy.evaluateEdgeAction(std.testing.allocator, &loaded.value, request(.arm, .none, 1_000_100), state, .{ .mode = .ci, .now_ms = now_ms, .non_interactive = true });
    defer ci_eval.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, ci_eval.decision.result);
    try std.testing.expect(!ci_eval.decision.ci_may_proceed);

    var land_eval = try policy.evaluateEdgeAction(std.testing.allocator, &loaded.value, request(.land, .none, 1_000_100), staleState(1_000_000), .{ .mode = .strict, .now_ms = 1_005_000 });
    defer land_eval.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.allow, land_eval.decision.result);
    try std.testing.expect(land_eval.hasAuditEvent("vehicle.command_allowed"));

    const critical = [_]domain.commands.CommandAction{ .disable_failsafe, .disable_geofence, .raw_actuator_output, .override_operator, .firmware_update };
    for (critical) |action| {
        var critical_eval = try policy.evaluateEdgeAction(std.testing.allocator, &loaded.value, request(action, .none, 1_000_100), state, .{ .mode = .strict, .now_ms = now_ms });
        defer critical_eval.deinit();
        try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, critical_eval.decision.result);
    }
}

test "phase 27 rejects mismatched request and state vehicle ids" {
    var loaded = try policy.loadFromSlice(std.testing.allocator, valid_policy_yaml, "valid-edge-policy.yaml", .{});
    defer loaded.deinit();

    var state = freshState(1_000_000);
    state.vehicle_id = .{ .value = "edge-vehicle-2" };

    try std.testing.expectError(
        error.VehicleIdMismatch,
        policy.evaluateEdgeAction(std.testing.allocator, &loaded.value, request(.read_telemetry, .none, 1_000_100), state, .{ .mode = .strict, .now_ms = 1_000_500 }),
    );
}

test "phase 27 parameterized commands require matching parameters" {
    const timestamp = domain.coordinates.Timestamp{ .value = 1_000_100, .source = .monotonic };
    const base = domain.commands.CommandRequestInit{
        .command_id = "cmd-parameter-test",
        .vehicle_id = .{ .value = "edge-vehicle-1" },
        .action = .set_waypoint,
        .actor = "agent-under-test",
        .timestamp = timestamp,
        .source = .fake_adapter,
    };

    try std.testing.expectError(error.MissingCommandParameters, domain.commands.CommandRequest.init(base).validate());
    try std.testing.expectError(error.InvalidCommandParameters, domain.commands.CommandRequest.init(.{
        .command_id = base.command_id,
        .vehicle_id = base.vehicle_id,
        .action = .set_waypoint,
        .parameters = .{ .velocity = .{ .vx_mps = 1, .vy_mps = 0, .vz_mps = 0, .frame = .local_ned } },
        .actor = base.actor,
        .timestamp = timestamp,
        .source = .fake_adapter,
    }).validate());
    try std.testing.expectError(error.MissingCommandParameters, domain.commands.CommandRequest.init(.{
        .command_id = base.command_id,
        .vehicle_id = base.vehicle_id,
        .action = .takeoff,
        .actor = base.actor,
        .timestamp = timestamp,
        .source = .fake_adapter,
    }).validate());
    try std.testing.expectError(error.MissingCommandParameters, domain.commands.CommandRequest.init(.{
        .command_id = base.command_id,
        .vehicle_id = base.vehicle_id,
        .action = .set_velocity,
        .actor = base.actor,
        .timestamp = timestamp,
        .source = .fake_adapter,
    }).validate());
    try std.testing.expectError(error.InvalidCommandParameters, domain.commands.CommandRequest.init(.{
        .command_id = base.command_id,
        .vehicle_id = base.vehicle_id,
        .action = .set_altitude,
        .parameters = .{ .velocity = .{ .vx_mps = 1, .vy_mps = 0, .vz_mps = 0, .frame = .local_ned } },
        .actor = base.actor,
        .timestamp = timestamp,
        .source = .fake_adapter,
    }).validate());
    try std.testing.expectError(error.MissingCommandParameters, domain.commands.CommandRequest.init(.{
        .command_id = base.command_id,
        .vehicle_id = base.vehicle_id,
        .action = .set_heading,
        .actor = base.actor,
        .timestamp = timestamp,
        .source = .fake_adapter,
    }).validate());
    try std.testing.expectError(error.MissingCommandParameters, domain.commands.CommandRequest.init(.{
        .command_id = base.command_id,
        .vehicle_id = base.vehicle_id,
        .action = .set_mode,
        .actor = base.actor,
        .timestamp = timestamp,
        .source = .fake_adapter,
    }).validate());
    try domain.commands.CommandRequest.init(.{
        .command_id = base.command_id,
        .vehicle_id = base.vehicle_id,
        .action = .set_waypoint,
        .parameters = .{ .waypoint = .{ .latitude_deg = 37, .longitude_deg = -122, .altitude_m = 20, .altitude_reference = .amsl } },
        .actor = base.actor,
        .timestamp = timestamp,
        .source = .fake_adapter,
    }).validate();
    try domain.commands.CommandRequest.init(.{
        .command_id = base.command_id,
        .vehicle_id = base.vehicle_id,
        .action = .set_velocity,
        .parameters = .{ .velocity = .{ .vx_mps = 1, .vy_mps = 0, .vz_mps = 0, .frame = .local_ned } },
        .actor = base.actor,
        .timestamp = timestamp,
        .source = .fake_adapter,
    }).validate();
    try domain.commands.CommandRequest.init(.{
        .command_id = base.command_id,
        .vehicle_id = base.vehicle_id,
        .action = .set_altitude,
        .parameters = .{ .altitude = .{ .altitude_m = 20, .altitude_reference = .amsl } },
        .actor = base.actor,
        .timestamp = timestamp,
        .source = .fake_adapter,
    }).validate();
    try domain.commands.CommandRequest.init(.{
        .command_id = base.command_id,
        .vehicle_id = base.vehicle_id,
        .action = .set_heading,
        .parameters = .{ .heading = domain.coordinates.Heading.degrees(90) },
        .actor = base.actor,
        .timestamp = timestamp,
        .source = .fake_adapter,
    }).validate();
    try domain.commands.CommandRequest.init(.{
        .command_id = base.command_id,
        .vehicle_id = base.vehicle_id,
        .action = .set_mode,
        .parameters = .{ .mode = .mission },
        .actor = base.actor,
        .timestamp = timestamp,
        .source = .fake_adapter,
    }).validate();
}

test "phase 27 command request parser supports required heading parameters" {
    const request_text =
        \\{
        \\  "command_id": "cmd-heading",
        \\  "vehicle_id": "edge-vehicle-1",
        \\  "action": "set_heading",
        \\  "actor": "agent-under-test",
        \\  "timestamp_ms": 1000100,
        \\  "source": "fake_adapter",
        \\  "parameters": {
        \\    "heading": {
        \\      "value": 90,
        \\      "unit": "degrees"
        \\    }
        \\  }
        \\}
    ;

    const parsed = try policy.parseCommandRequestJson(std.testing.allocator, request_text);
    try std.testing.expectEqual(domain.commands.CommandAction.set_heading, parsed.action);
    try std.testing.expect(parsed.parameters == .heading);
    try parsed.validate();
}

test "phase 27 state freshness denies unsafe stale expired and unknown state" {
    var loaded = try policy.loadFromSlice(std.testing.allocator, valid_policy_yaml, "valid-edge-policy.yaml", .{});
    defer loaded.deinit();

    var fresh_eval = try policy.evaluateEdgeAction(std.testing.allocator, &loaded.value, waypointRequest(37.0005, -122.0000, 20), freshState(1_000_000), .{ .mode = .ask, .now_ms = 1_000_500 });
    defer fresh_eval.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.ask, fresh_eval.decision.result);

    var stale_eval = try policy.evaluateEdgeAction(std.testing.allocator, &loaded.value, waypointRequest(37.0005, -122.0000, 20), staleState(1_000_000), .{ .mode = .strict, .now_ms = 1_005_000 });
    defer stale_eval.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, stale_eval.decision.result);
    try std.testing.expect(stale_eval.hasFinding(.state_freshness));
    try std.testing.expect(stale_eval.hasAuditEvent("safety.stale_state_denied"));

    var expired = staleState(1_000_000);
    expired.state_freshness = .expired;
    var expired_eval = try policy.evaluateEdgeAction(std.testing.allocator, &loaded.value, request(.start_mission, .none, 1_000_100), expired, .{ .mode = .strict, .now_ms = 1_005_000 });
    defer expired_eval.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, expired_eval.decision.result);

    var unknown = freshState(1_000_000);
    unknown.state_freshness = .unknown;
    var unknown_eval = try policy.evaluateEdgeAction(std.testing.allocator, &loaded.value, request(.takeoff, .{ .altitude = .{ .altitude_m = 20, .altitude_reference = .amsl } }, 1_000_100), unknown, .{ .mode = .strict, .now_ms = 1_000_500 });
    defer unknown_eval.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, unknown_eval.decision.result);
}

test "phase 27 geofence altitude velocity and battery constraints fail closed" {
    var loaded = try policy.loadFromSlice(std.testing.allocator, valid_policy_yaml, "valid-edge-policy.yaml", .{});
    defer loaded.deinit();

    const state = freshState(1_000_000);
    var outside = try policy.evaluateEdgeAction(std.testing.allocator, &loaded.value, waypointRequest(37.0100, -122.0000, 20), state, .{ .mode = .ask, .now_ms = 1_000_500 });
    defer outside.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, outside.decision.result);
    try std.testing.expect(outside.hasAuditEvent("safety.geofence_violation"));

    var above = try policy.evaluateEdgeAction(std.testing.allocator, &loaded.value, waypointRequest(37.0005, -122.0000, 121), state, .{ .mode = .ask, .now_ms = 1_000_500 });
    defer above.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, above.decision.result);
    try std.testing.expect(above.hasAuditEvent("safety.altitude_violation"));

    var below = try policy.evaluateEdgeAction(std.testing.allocator, &loaded.value, waypointRequest(37.0005, -122.0000, 1), state, .{ .mode = .ask, .now_ms = 1_000_500 });
    defer below.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, below.decision.result);

    var mismatch = try policy.evaluateEdgeAction(std.testing.allocator, &loaded.value, request(.set_altitude, .{ .altitude = .{ .altitude_m = 20, .altitude_reference = .agl } }, 1_000_100), state, .{ .mode = .ask, .now_ms = 1_000_500 });
    defer mismatch.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, mismatch.decision.result);

    var velocity_ok = try policy.evaluateEdgeAction(std.testing.allocator, &loaded.value, request(.set_velocity, .{ .velocity = .{ .vx_mps = 3, .vy_mps = 4, .vz_mps = -1, .frame = .local_ned } }, 1_000_100), state, .{ .mode = .ask, .now_ms = 1_000_500 });
    defer velocity_ok.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.ask, velocity_ok.decision.result);

    var velocity_bad = try policy.evaluateEdgeAction(std.testing.allocator, &loaded.value, request(.set_velocity, .{ .velocity = .{ .vx_mps = 9, .vy_mps = 0, .vz_mps = -3, .frame = .local_ned } }, 1_000_100), state, .{ .mode = .ask, .now_ms = 1_000_500 });
    defer velocity_bad.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, velocity_bad.decision.result);
    try std.testing.expect(velocity_bad.hasAuditEvent("safety.velocity_violation"));

    var low_battery_state = freshState(1_000_000);
    low_battery_state.battery_state.?.percent_remaining = 20;
    var low_battery_eval = try policy.evaluateEdgeAction(std.testing.allocator, &loaded.value, request(.takeoff, .{ .altitude = .{ .altitude_m = 20, .altitude_reference = .amsl } }, 1_000_100), low_battery_state, .{ .mode = .strict, .now_ms = 1_000_500 });
    defer low_battery_eval.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, low_battery_eval.decision.result);
    try std.testing.expectEqual(domain.commands.CommandAction.return_to_home, low_battery_eval.recommended_fallback.?);
    try std.testing.expect(low_battery_eval.hasAuditEvent("safety.battery_constraint"));
}

test "phase 27 mode and authority constraints respect human and failsafe control" {
    var loaded = try policy.loadFromSlice(std.testing.allocator, valid_policy_yaml, "valid-edge-policy.yaml", .{});
    defer loaded.deinit();

    var human = freshState(1_000_000);
    human.mode = .manual;
    human.control_authority = .human_operator;
    var human_eval = try policy.evaluateEdgeAction(std.testing.allocator, &loaded.value, waypointRequest(37.0005, -122.0000, 20), human, .{ .mode = .strict, .now_ms = 1_000_500 });
    defer human_eval.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, human_eval.decision.result);
    try std.testing.expect(human_eval.hasAuditEvent("safety.authority_constraint"));

    var failsafe = freshState(1_000_000);
    failsafe.control_authority = .failsafe;
    var failsafe_eval = try policy.evaluateEdgeAction(std.testing.allocator, &loaded.value, request(.override_operator, .none, 1_000_100), failsafe, .{ .mode = .strict, .now_ms = 1_000_500 });
    defer failsafe_eval.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, failsafe_eval.decision.result);
}

test "phase 27 audit events pass through Core redaction and replay safely" {
    var loaded = try policy.loadFromSlice(std.testing.allocator, valid_policy_yaml, "valid-edge-policy.yaml", .{});
    defer loaded.deinit();

    var command = request(.disable_failsafe, .none, 1_000_100);
    command.actor = "agent fake_secret_value_phase27";
    var evaluation = try policy.evaluateEdgeAction(std.testing.allocator, &loaded.value, command, freshState(1_000_000), .{ .mode = .strict, .now_ms = 1_000_500 });
    defer evaluation.deinit();
    try std.testing.expect(evaluation.hasAuditEvent("vehicle.command_denied"));

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    const ts = edge.core.core.time.Timestamp.fromUnixSeconds(1_777_983_130);
    const session: edge.core.core.session.Session = .{
        .id = try edge.core.core.session.generateSessionId(ts),
        .started_at = ts,
        .ended_at = ts,
        .command = "edge",
        .args = &.{ "policy", "evaluate" },
        .workspace_root = root,
        .mode = .strict,
        .platform = edge.core.core.platform.detectOs(),
    };

    var writer = try edge.core.api.createAuditWriter(std.testing.allocator, session);
    defer writer.deinit();
    try policy.appendPreparedAuditEvents(std.testing.allocator, &writer, evaluation, session.id, ts);
    try writer.writeLastPointer();
    const final_hash = writer.finalHash() orelse "";
    try edge.core.api.writeAuditSummary(std.testing.allocator, writer.sessionDirPath(), .{
        .session = session,
        .status = .{ .exited = 0 },
        .event_count = writer.event_count,
        .final_event_hash = final_hash,
        .policy = "edge-policy fake_secret_value_phase27",
    });

    const events_path = try std.fs.path.join(std.testing.allocator, &.{ writer.sessionDirPath(), "events.jsonl" });
    defer std.testing.allocator.free(events_path);
    const events = try std.fs.cwd().readFileAlloc(std.testing.allocator, events_path, 64 * 1024);
    defer std.testing.allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "fake_secret_value_phase27") == null);
    try std.testing.expect(std.mem.indexOf(u8, events, "[REDACTED:") != null);

    var replay = try edge.core.api.loadReplay(std.testing.allocator, root, .{ .session = "last", .verify = true });
    defer replay.deinit();
    var replay_output: std.ArrayList(u8) = .empty;
    defer replay_output.deinit(std.testing.allocator);
    try edge.core.api.writeReplayHuman(replay_output.writer(std.testing.allocator), replay, true);
    try std.testing.expect(std.mem.indexOf(u8, replay_output.items, "fake_secret_value_phase27") == null);
}

test "phase 27 policy loader rejects missing required top-level sections" {
    try expectPolicyError(error.MissingPolicySafetySection,
        \\version: 1
        \\vehicle:
        \\  kind: drone_multirotor
        \\  autopilot: px4
        \\  adapter: fake
        \\commands:
        \\  allow:
        \\    - read_telemetry
    );
    try expectPolicyError(error.MissingPolicyCommandsSection,
        \\version: 1
        \\vehicle:
        \\  kind: drone_multirotor
        \\  autopilot: px4
        \\  adapter: fake
        \\safety:
        \\  state_freshness:
        \\    max_state_age_ms: 1000
        \\    deny_commands_on_stale_state: true
    );
}

fn expectPolicyError(expected: anyerror, text: []const u8) !void {
    var loaded = policy.loadFromSlice(std.testing.allocator, text, "invalid-edge-policy.yaml", .{}) catch |err| {
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

fn request(action: domain.commands.CommandAction, params: domain.commands.CommandParameters, timestamp_ms: i128) domain.commands.CommandRequest {
    return domain.commands.CommandRequest.init(.{
        .command_id = "cmd-1",
        .vehicle_id = .{ .value = "edge-vehicle-1" },
        .action = action,
        .parameters = params,
        .actor = "agent-under-test",
        .timestamp = .{ .value = timestamp_ms, .source = .monotonic },
        .source = .fake_adapter,
    });
}

fn waypointRequest(lat: f64, lon: f64, alt: f64) domain.commands.CommandRequest {
    return request(.set_waypoint, .{ .waypoint = .{
        .latitude_deg = lat,
        .longitude_deg = lon,
        .altitude_m = alt,
        .altitude_reference = .amsl,
    } }, 1_000_100);
}

fn freshState(timestamp_ms: i128) domain.state.VehicleState {
    return .{
        .vehicle_id = .{ .value = "edge-vehicle-1" },
        .vehicle_kind = .drone_multirotor,
        .autopilot_kind = .px4,
        .mode = .guided,
        .arm_state = .armed,
        .position = .{
            .latitude_deg = 37.0,
            .longitude_deg = -122.0,
            .altitude_m = 20,
            .altitude_reference = .amsl,
        },
        .battery_state = .{
            .percent_remaining = 80,
            .voltage_v = 15.2,
            .current_a = 2.1,
            .source = .monotonic,
        },
        .control_authority = .onboard_agent,
        .home_position = .{
            .latitude_deg = 37.0,
            .longitude_deg = -122.0,
            .altitude_m = 0,
            .altitude_reference = .amsl,
        },
        .timestamp = .{ .value = timestamp_ms, .source = .monotonic },
        .state_freshness = .fresh,
        .provenance = .fake_adapter,
    };
}

fn staleState(timestamp_ms: i128) domain.state.VehicleState {
    var state = freshState(timestamp_ms);
    state.state_freshness = .stale;
    return state;
}
