const std = @import("std");
const edge = @import("aegis_edge");

const domain = edge.domain;
const mavlink = edge.mavlink;
const px4 = edge.px4;

const policy_yaml =
    \\version: 1
    \\
    \\vehicle:
    \\  kind: drone_multirotor
    \\  autopilot: px4
    \\  adapter: mavlink
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
    \\    - payload_release
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

test "phase 29 fake PX4 heartbeat position battery and stale mapping" {
    const allocator = std.testing.allocator;
    var fake = px4.fake_adapter.FakePx4Adapter.init(allocator, .{ .sysid = 42, .compid = 1 });
    defer fake.deinit();

    var mapper = px4.telemetry_mapping.StateMapper.init(.{
        .vehicle_id = "edge-vehicle-1",
        .provenance = .fake_adapter,
        .now_ms = 1_000_000,
        .stale_after_ms = 1_000,
        .expire_after_ms = 5_000,
    });

    const heartbeat = try fake.heartbeatFrame(.{ .armed = true, .base_mode = 0x80 });
    defer allocator.free(heartbeat);
    try mapper.observeFrame(try mavlink.framing.parseFrame(heartbeat));

    const position = try fake.globalPositionFrame(.{
        .lat_int = 370000000,
        .lon_int = -1220000000,
        .alt_mm = 25_000,
        .relative_alt_mm = 20_000,
        .heading_cdeg = 9000,
    });
    defer allocator.free(position);
    try mapper.observeFrame(try mavlink.framing.parseFrame(position));

    const local_position = try fake.localPositionFrame(.{ .x = 1.5, .y = -2.0, .z = -10.0, .vx = 0.2, .vy = 0.0, .vz = -0.1 });
    defer allocator.free(local_position);
    try mapper.observeFrame(try mavlink.framing.parseFrame(local_position));

    const attitude = try fake.attitudeFrame(.{ .roll = 0.1, .pitch = -0.2, .yaw = 1.57 });
    defer allocator.free(attitude);
    try mapper.observeFrame(try mavlink.framing.parseFrame(attitude));

    const battery = try fake.batteryStatusFrame(.{ .percent_remaining = 64, .voltage_mv = 15100, .current_ca = 210 });
    defer allocator.free(battery);
    try mapper.observeFrame(try mavlink.framing.parseFrame(battery));

    var state = mapper.state();
    try std.testing.expectEqual(domain.state.StateProvenance.fake_adapter, state.provenance);
    try std.testing.expectEqual(domain.vehicle.AutopilotKind.px4, state.autopilot_kind);
    try std.testing.expectEqual(domain.vehicle.ArmState.armed, state.arm_state);
    try std.testing.expectEqual(domain.vehicle.VehicleMode.guided, state.mode);
    try std.testing.expectEqual(domain.coordinates.AltitudeReference.amsl, state.position.?.altitude_reference);
    try std.testing.expectApproxEqAbs(@as(f64, 37.0), state.position.?.latitude_deg, 0.000001);
    try std.testing.expectApproxEqAbs(@as(f64, -122.0), state.position.?.longitude_deg, 0.000001);
    try std.testing.expectEqual(domain.coordinates.CoordinateFrame.local_ned, state.local_position.?.frame);
    try std.testing.expectApproxEqAbs(@as(f64, 64), state.battery_state.?.percent_remaining, 0.001);
    try std.testing.expectEqual(domain.coordinates.TimestampSource.autopilot, state.battery_state.?.source);
    try std.testing.expectEqual(domain.state.StateFreshness.fresh, state.state_freshness);

    mapper.refreshFreshness(1_002_500);
    state = mapper.state();
    try std.testing.expectEqual(domain.state.StateFreshness.stale, state.state_freshness);

    mapper.refreshFreshness(1_007_000);
    state = mapper.state();
    try std.testing.expectEqual(domain.state.StateFreshness.expired, state.state_freshness);
}

test "phase 29 SITL provenance is never used for fake PX4 adapter frames" {
    const allocator = std.testing.allocator;
    var fake = px4.fake_adapter.FakePx4Adapter.init(allocator, .{});
    defer fake.deinit();
    var mapper = px4.telemetry_mapping.StateMapper.init(.{ .vehicle_id = "edge-vehicle-1", .provenance = .fake_adapter, .now_ms = 1_000_000 });
    const heartbeat = try fake.heartbeatFrame(.{});
    defer allocator.free(heartbeat);
    try mapper.observeFrame(try mavlink.framing.parseFrame(heartbeat));
    try std.testing.expectEqual(domain.state.StateProvenance.fake_adapter, mapper.state().provenance);
    try std.testing.expect(mapper.state().provenance != .sitl_px4);
}

test "phase 29 PX4 mediation reuses MAVLink gateway policy decisions" {
    const allocator = std.testing.allocator;
    var loaded = try edge.policy.loadFromSlice(allocator, policy_yaml, "phase29-policy.yaml", .{});
    defer loaded.deinit();
    var fake = px4.fake_adapter.FakePx4Adapter.init(allocator, .{ .sysid = 42, .compid = 191 });
    defer fake.deinit();
    const adapter = px4.sitl_adapter.Adapter.init(.{
        .environment = .fake_px4,
        .mode = .enforce,
        .vehicle_id = "edge-vehicle-1",
        .now_ms = 1_000_500,
    });
    const state = fakeFreshState(80, .fresh);

    const outside_waypoint = try fake.commandFrame(.{
        .action = .set_waypoint,
        .lat_int = 370100000,
        .lon_int = -1220000000,
        .alt_m = 25,
    });
    defer allocator.free(outside_waypoint);
    var outside_result = try adapter.mediateFrame(allocator, &loaded.value, state, try mavlink.framing.parseFrame(outside_waypoint));
    defer outside_result.deinit();
    try std.testing.expect(outside_result.blocked);
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, outside_result.decision.?);
    try std.testing.expect(outside_result.audit.hasEvent(.safety_geofence_violation));

    const land = try fake.commandFrame(.{ .action = .land });
    defer allocator.free(land);
    var land_result = try adapter.mediateFrame(allocator, &loaded.value, state, try mavlink.framing.parseFrame(land));
    defer land_result.deinit();
    try std.testing.expect(land_result.forwarded);
    try std.testing.expect(land_result.audit.hasEvent(.command_allowed));

    const disable_failsafe = try fake.commandFrame(.{ .action = .disable_failsafe });
    defer allocator.free(disable_failsafe);
    var failsafe_result = try adapter.mediateFrame(allocator, &loaded.value, state, try mavlink.framing.parseFrame(disable_failsafe));
    defer failsafe_result.deinit();
    try std.testing.expect(failsafe_result.blocked);
    try std.testing.expect(failsafe_result.audit.hasEvent(.command_denied));

    const raw_actuator = try fake.commandFrame(.{ .action = .raw_actuator_output });
    defer allocator.free(raw_actuator);
    var raw_result = try adapter.mediateFrame(allocator, &loaded.value, state, try mavlink.framing.parseFrame(raw_actuator));
    defer raw_result.deinit();
    try std.testing.expect(raw_result.blocked);
    try std.testing.expect(raw_result.audit.hasEvent(.command_denied));

    const unknown = try fake.commandFrame(.{ .action = .unknown });
    defer allocator.free(unknown);
    var unknown_result = try adapter.mediateFrame(allocator, &loaded.value, state, try mavlink.framing.parseFrame(unknown));
    defer unknown_result.deinit();
    try std.testing.expect(unknown_result.blocked);
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, unknown_result.decision.?);
}

test "phase 29 CI converts ask to deny and observe logs while forwarding" {
    const allocator = std.testing.allocator;
    var loaded = try edge.policy.loadFromSlice(allocator, policy_yaml, "phase29-policy.yaml", .{});
    defer loaded.deinit();
    var fake = px4.fake_adapter.FakePx4Adapter.init(allocator, .{ .sysid = 42, .compid = 191 });
    defer fake.deinit();
    const arm = try fake.commandFrame(.{ .action = .arm });
    defer allocator.free(arm);
    const frame = try mavlink.framing.parseFrame(arm);

    const ci_adapter = px4.sitl_adapter.Adapter.init(.{ .environment = .fake_px4, .mode = .ci, .vehicle_id = "edge-vehicle-1", .now_ms = 1_000_500 });
    var ci = try ci_adapter.mediateFrame(allocator, &loaded.value, fakeFreshState(80, .fresh), frame);
    defer ci.deinit();
    try std.testing.expect(ci.blocked);
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, ci.decision.?);

    const observe_adapter = px4.sitl_adapter.Adapter.init(.{ .environment = .fake_px4, .mode = .observe, .vehicle_id = "edge-vehicle-1", .now_ms = 1_000_500 });
    var observed = try observe_adapter.mediateFrame(allocator, &loaded.value, fakeFreshState(80, .fresh), frame);
    defer observed.deinit();
    try std.testing.expect(observed.forwarded);
    try std.testing.expectEqual(edge.core.decision.DecisionResult.observe, observed.decision.?);
    try std.testing.expect(observed.audit.hasEvent(.command_observed));
}

test "phase 29 stale state denies high risk takeoff unless emergency land" {
    const allocator = std.testing.allocator;
    var loaded = try edge.policy.loadFromSlice(allocator, policy_yaml, "phase29-policy.yaml", .{});
    defer loaded.deinit();
    var fake = px4.fake_adapter.FakePx4Adapter.init(allocator, .{ .sysid = 42, .compid = 191 });
    defer fake.deinit();
    const adapter = px4.sitl_adapter.Adapter.init(.{ .environment = .fake_px4, .mode = .enforce, .vehicle_id = "edge-vehicle-1", .now_ms = 1_000_500 });

    const takeoff = try fake.commandFrame(.{ .action = .takeoff, .alt_m = 20 });
    defer allocator.free(takeoff);
    var takeoff_result = try adapter.mediateFrame(allocator, &loaded.value, fakeFreshState(80, .stale), try mavlink.framing.parseFrame(takeoff));
    defer takeoff_result.deinit();
    try std.testing.expect(takeoff_result.blocked);
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, takeoff_result.decision.?);

    const land = try fake.commandFrame(.{ .action = .land });
    defer allocator.free(land);
    var land_result = try adapter.mediateFrame(allocator, &loaded.value, fakeFreshState(80, .stale), try mavlink.framing.parseFrame(land));
    defer land_result.deinit();
    try std.testing.expect(land_result.forwarded);
}

test "phase 29 fake scenario creates redacted artifacts and distinguishes fake from SITL" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root);

    var result = try px4.scenario.run(allocator, .{
        .policy_path = "examples/edge/px4/policies/px4-geofence-basic.yaml",
        .scenario_path = "examples/edge/px4/scenarios/waypoint-outside-geofence-deny.yaml",
        .artifact_dir = root,
        .now_ms = 1_000_500,
    });
    defer result.deinit();

    try std.testing.expect(!result.skipped);
    try std.testing.expectEqual(px4.connection.Environment.fake_px4, result.environment);
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, result.decision.?);
    try std.testing.expect(std.mem.indexOf(u8, result.summary, "fake_px4") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.summary, "px4_sitl success") == null);

    const events_path = try std.fs.path.join(allocator, &.{ root, "events.jsonl" });
    defer allocator.free(events_path);
    const events = try std.fs.cwd().readFileAlloc(allocator, events_path, 32 * 1024);
    defer allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "fake_px4") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "sk-fakeSyntheticOpenAIKey1234567890") == null);
}

test "phase 29 missing PX4 SITL skips only when integration tests are not enabled" {
    const gate = px4.connection.integrationTestGate(.{
        .run_px4_sitl_tests = null,
        .endpoint = null,
    });
    try std.testing.expect(!gate.enabled);
    try std.testing.expectEqual(px4.connection.IntegrationAvailability.skipped, gate.availability);

    const enabled_missing = px4.connection.integrationTestGate(.{
        .run_px4_sitl_tests = "1",
        .endpoint = null,
    });
    try std.testing.expect(enabled_missing.enabled);
    try std.testing.expectEqual(px4.connection.IntegrationAvailability.unavailable, enabled_missing.availability);
}

test "phase 29 integration gate owns endpoint host copied from env buffers" {
    const allocator = std.testing.allocator;
    const run_source = try allocator.dupe(u8, "1");
    const endpoint_source = try allocator.dupe(u8, "127.0.0.1:14540");

    var gate = try px4.connection.integrationTestGateOwned(allocator, .{
        .run_px4_sitl_tests = run_source,
        .endpoint = endpoint_source,
    });
    defer gate.deinit(allocator);
    allocator.free(run_source);
    allocator.free(endpoint_source);

    try std.testing.expect(gate.enabled);
    try std.testing.expectEqual(px4.connection.IntegrationAvailability.configured, gate.availability);
    try std.testing.expectEqualStrings("127.0.0.1", gate.endpoint.?.host);
    try std.testing.expectEqual(@as(u16, 14540), gate.endpoint.?.port);
}

test "phase 29 SITL-required scenario cannot fall back to fake adapter metadata" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const inconsistent_scenario =
        \\id: requires-sitl-without-env
        \\mode: observe
        \\command: land
        \\requires_px4_sitl: true
        \\expected_decision: allow
        \\expected_forwarded: true
        \\note: "This metadata is intentionally inconsistent and must not fake-pass."
    ;
    try tmp.dir.writeFile(.{ .sub_path = "requires-sitl-without-env.yaml", .data = inconsistent_scenario });
    const root = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root);
    const scenario_path = try std.fs.path.join(allocator, &.{ root, "requires-sitl-without-env.yaml" });
    defer allocator.free(scenario_path);

    try std.testing.expectError(error.Px4ScenarioRequiresSitlEnvironment, px4.scenario.run(allocator, .{
        .policy_path = "examples/edge/px4/policies/px4-geofence-basic.yaml",
        .scenario_path = scenario_path,
    }));
}

test "phase 29 edge policy schema matches runtime circle geofence and altitude limits" {
    const allocator = std.testing.allocator;
    const text = try std.fs.cwd().readFileAlloc(allocator, "schemas/edge-policy-v1.json", 128 * 1024);
    defer allocator.free(text);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, text, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const safety = root.get("properties").?.object.get("safety").?.object;
    const safety_properties = safety.get("properties").?.object;
    const geofence = safety_properties.get("geofence").?.object;
    const geofence_required = geofence.get("required").?.array.items;
    try expectJsonStringInArray(geofence_required, "center");
    try expectJsonStringInArray(geofence_required, "max_radius_m");
    try std.testing.expectEqualStrings("circle", geofence.get("properties").?.object.get("type").?.object.get("const").?.string);
    try std.testing.expect(geofence.get("properties").?.object.get("vertices") == null);

    const altitude = safety_properties.get("altitude").?.object;
    const altitude_required = altitude.get("required").?.array.items;
    try expectJsonStringInArray(altitude_required, "min_altitude_m");
    try expectJsonStringInArray(altitude_required, "max_altitude_m");
    try expectJsonStringInArray(altitude_required, "altitude_reference");
}

test "phase 29 doctor reports no hardware or real-flight readiness" {
    var stdout_buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&stdout_buf);
    try px4.health.writeDoctor(stream.writer(), .{});
    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "fake adapter: active") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "PX4 SITL support:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "real-flight ready") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "certified") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "detect-and-avoid") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "sk-fakeSyntheticOpenAIKey1234567890") == null);
}

fn expectJsonStringInArray(items: []const std.json.Value, expected: []const u8) !void {
    for (items) |item| {
        if (item == .string and std.mem.eql(u8, item.string, expected)) return;
    }
    return error.TestUnexpectedResult;
}

fn fakeFreshState(percent: f64, freshness: domain.state.StateFreshness) domain.state.VehicleState {
    return .{
        .vehicle_id = .{ .value = "edge-vehicle-1" },
        .vehicle_kind = .drone_multirotor,
        .autopilot_kind = .px4,
        .mode = .guided,
        .arm_state = .armed,
        .position = .{ .latitude_deg = 37.0000, .longitude_deg = -122.0000, .altitude_m = 20, .altitude_reference = .amsl },
        .battery_state = .{ .percent_remaining = percent, .voltage_v = 15.2, .current_a = 2.1, .source = .monotonic },
        .control_authority = .onboard_agent,
        .home_position = .{ .latitude_deg = 37.0000, .longitude_deg = -122.0000, .altitude_m = 0, .altitude_reference = .amsl },
        .timestamp = .{ .value = 1_000_000, .source = .monotonic },
        .state_freshness = freshness,
        .provenance = .fake_adapter,
    };
}
