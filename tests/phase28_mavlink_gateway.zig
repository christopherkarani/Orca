const std = @import("std");
const edge = @import("aegis_edge");

const mavlink = edge.mavlink;
const domain = edge.domain;

const policy_yaml =
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

test "phase 28 parser handles v1 v2 partial multiple invalid and checksum failures" {
    const allocator = std.testing.allocator;
    const heartbeat = try mavlink.fake_transport.frameHeartbeatV1(allocator, .{ .seq = 7, .sysid = 1, .compid = 1 });
    defer allocator.free(heartbeat);
    const arm = try mavlink.fake_transport.frameCommandLongV2(allocator, .{ .seq = 8, .sysid = 42, .compid = 191 }, mavlink.commands.MAV_CMD_COMPONENT_ARM_DISARM, 1, .{});
    defer allocator.free(arm);

    const one = try mavlink.framing.parseFrame(heartbeat);
    try std.testing.expectEqual(mavlink.framing.Version.v1, one.version);
    try std.testing.expectEqual(@as(u32, mavlink.dialect.HEARTBEAT), one.msgid);
    try std.testing.expectEqual(@as(u8, 7), one.sequence);
    try std.testing.expectEqual(@as(u8, 1), one.sysid);
    try std.testing.expectEqual(@as(?bool, true), one.checksum_valid);

    const two = try mavlink.framing.parseFrame(arm);
    try std.testing.expectEqual(mavlink.framing.Version.v2, two.version);
    try std.testing.expectEqual(@as(u32, mavlink.dialect.COMMAND_LONG), two.msgid);
    try std.testing.expect(!two.signature_present);

    var parser = mavlink.parser.Parser.init();
    var frames: std.ArrayList(mavlink.framing.Frame) = .empty;
    defer frames.deinit(allocator);
    const half = arm.len / 2;
    var stats = try parser.feed(allocator, arm[0..half], &frames);
    try std.testing.expectEqual(@as(usize, 0), frames.items.len);
    try std.testing.expect(stats.partial);
    stats = try parser.feed(allocator, arm[half..], &frames);
    try std.testing.expectEqual(@as(usize, 1), frames.items.len);
    try std.testing.expect(!stats.partial);

    var stream: std.ArrayList(u8) = .empty;
    defer stream.deinit(allocator);
    try stream.appendSlice(allocator, &.{ 0x00, 0x13, 0x37 });
    try stream.appendSlice(allocator, heartbeat);
    try stream.appendSlice(allocator, arm);
    var recovered = mavlink.parser.Parser.init();
    var recovered_frames: std.ArrayList(mavlink.framing.Frame) = .empty;
    defer recovered_frames.deinit(allocator);
    stats = try recovered.feed(allocator, stream.items, &recovered_frames);
    try std.testing.expectEqual(@as(usize, 2), recovered_frames.items.len);
    try std.testing.expectEqual(@as(usize, 3), stats.invalid_bytes);

    try std.testing.expectError(error.TruncatedFrame, mavlink.framing.parseFrame(arm[0 .. arm.len - 1]));

    const corrupted = try allocator.dupe(u8, arm);
    defer allocator.free(corrupted);
    corrupted[corrupted.len - 2] ^= 0xff;
    try std.testing.expectError(error.InvalidChecksum, mavlink.framing.parseFrame(corrupted));

    var malformed = [_]u8{0xfd} ++ [_]u8{0} ** 400;
    try std.testing.expectError(error.OversizedFrame, mavlink.framing.parseFrame(malformed[0..]));
}

test "phase 28 parser drains valid frame batches larger than one frame buffer" {
    const allocator = std.testing.allocator;
    var batch: std.ArrayList(u8) = .empty;
    defer batch.deinit(allocator);

    var expected_frames: usize = 0;
    var seq: u8 = 0;
    while (batch.items.len <= mavlink.framing.max_frame_len + 64) : (seq += 1) {
        const frame = try mavlink.fake_transport.frameCommandLongV2(
            allocator,
            .{ .seq = seq, .sysid = 42, .compid = 191 },
            mavlink.commands.MAV_CMD_COMPONENT_ARM_DISARM,
            1,
            .{},
        );
        defer allocator.free(frame);
        try batch.appendSlice(allocator, frame);
        expected_frames += 1;
    }

    var parser = mavlink.parser.Parser.init();
    var frames: std.ArrayList(mavlink.framing.Frame) = .empty;
    defer frames.deinit(allocator);
    const stats = try parser.feed(allocator, batch.items, &frames);

    try std.testing.expectEqual(expected_frames, stats.frames);
    try std.testing.expectEqual(expected_frames, frames.items.len);
    try std.testing.expect(!stats.partial);
}

test "phase 28 MAVLink audit event names are accepted by Edge event schemas" {
    const allocator = std.testing.allocator;
    const text = try std.fs.cwd().readFileAlloc(allocator, "schemas/edge-event-v1.json", 128 * 1024);
    defer allocator.free(text);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, text, .{});
    defer parsed.deinit();

    const event_enum = parsed.value.object
        .get("properties").?.object
        .get("event_type").?.object
        .get("enum").?.array.items;

    inline for (std.meta.fields(mavlink.audit.EventKind)) |field| {
        const event_type = @field(mavlink.audit.EventKind, field.name).toString();
        try std.testing.expect(edge.schema.edge_event_schema.hasEventType(event_type));
        try expectJsonStringInArray(event_enum, event_type);
    }
}

test "phase 28 classifier and mapping cover command subset and unknowns fail closed" {
    const allocator = std.testing.allocator;
    const heartbeat = try mavlink.fake_transport.frameHeartbeatV1(allocator, .{ .seq = 1, .sysid = 1, .compid = 1 });
    defer allocator.free(heartbeat);
    const heartbeat_frame = try mavlink.framing.parseFrame(heartbeat);
    const heartbeat_class = try mavlink.classifier.classifyFrame(heartbeat_frame);
    try std.testing.expectEqual(mavlink.classifier.MessageCategory.telemetry_state, heartbeat_class.category);

    const arm_frame_bytes = try mavlink.fake_transport.frameCommandLongV2(allocator, .{ .seq = 2, .sysid = 42, .compid = 191 }, mavlink.commands.MAV_CMD_COMPONENT_ARM_DISARM, 1, .{});
    defer allocator.free(arm_frame_bytes);
    const arm_frame = try mavlink.framing.parseFrame(arm_frame_bytes);
    var arm_mapping = try mavlink.mapping.mapFrameToCommand(allocator, arm_frame, .{ .vehicle_id = "edge-vehicle-1", .now_ms = 1_000_100 });
    defer arm_mapping.deinit();
    try std.testing.expectEqual(domain.commands.CommandAction.arm, arm_mapping.request.?.action);
    try std.testing.expect(arm_mapping.request.?.raw_protocol_reference != null);

    const disarm_bytes = try mavlink.fake_transport.frameCommandLongV2(allocator, .{ .seq = 3, .sysid = 42, .compid = 191 }, mavlink.commands.MAV_CMD_COMPONENT_ARM_DISARM, 0, .{});
    defer allocator.free(disarm_bytes);
    var disarm_mapping = try mavlink.mapping.mapFrameToCommand(allocator, try mavlink.framing.parseFrame(disarm_bytes), .{ .vehicle_id = "edge-vehicle-1", .now_ms = 1_000_100 });
    defer disarm_mapping.deinit();
    try std.testing.expectEqual(domain.commands.CommandAction.disarm, disarm_mapping.request.?.action);

    const takeoff_bytes = try mavlink.fake_transport.frameCommandLongV2(allocator, .{ .seq = 4, .sysid = 42, .compid = 191 }, mavlink.commands.MAV_CMD_NAV_TAKEOFF, 0, .{ .param7 = 30 });
    defer allocator.free(takeoff_bytes);
    var takeoff_mapping = try mavlink.mapping.mapFrameToCommand(allocator, try mavlink.framing.parseFrame(takeoff_bytes), .{ .vehicle_id = "edge-vehicle-1", .now_ms = 1_000_100 });
    defer takeoff_mapping.deinit();
    try std.testing.expectEqual(domain.commands.CommandAction.takeoff, takeoff_mapping.request.?.action);
    try std.testing.expect(takeoff_mapping.request.?.parameters == .altitude);

    const land_bytes = try mavlink.fake_transport.frameCommandLongV2(allocator, .{ .seq = 5, .sysid = 42, .compid = 191 }, mavlink.commands.MAV_CMD_NAV_LAND, 0, .{});
    defer allocator.free(land_bytes);
    var land_mapping = try mavlink.mapping.mapFrameToCommand(allocator, try mavlink.framing.parseFrame(land_bytes), .{ .vehicle_id = "edge-vehicle-1", .now_ms = 1_000_100 });
    defer land_mapping.deinit();
    try std.testing.expectEqual(domain.commands.CommandAction.land, land_mapping.request.?.action);

    const rtl_bytes = try mavlink.fake_transport.frameCommandLongV2(allocator, .{ .seq = 6, .sysid = 42, .compid = 191 }, mavlink.commands.MAV_CMD_NAV_RETURN_TO_LAUNCH, 0, .{});
    defer allocator.free(rtl_bytes);
    var rtl_mapping = try mavlink.mapping.mapFrameToCommand(allocator, try mavlink.framing.parseFrame(rtl_bytes), .{ .vehicle_id = "edge-vehicle-1", .now_ms = 1_000_100 });
    defer rtl_mapping.deinit();
    try std.testing.expectEqual(domain.commands.CommandAction.return_to_home, rtl_mapping.request.?.action);

    const failsafe_bytes = try mavlink.fake_transport.frameParamSetV2(allocator, .{ .seq = 7, .sysid = 42, .compid = 191 }, "COM_FAIL_ACT", 0);
    defer allocator.free(failsafe_bytes);
    var failsafe_mapping = try mavlink.mapping.mapFrameToCommand(allocator, try mavlink.framing.parseFrame(failsafe_bytes), .{ .vehicle_id = "edge-vehicle-1", .now_ms = 1_000_100 });
    defer failsafe_mapping.deinit();
    try std.testing.expectEqual(domain.commands.CommandAction.disable_failsafe, failsafe_mapping.request.?.action);

    const servo_bytes = try mavlink.fake_transport.frameCommandLongV2(allocator, .{ .seq = 8, .sysid = 42, .compid = 191 }, mavlink.commands.MAV_CMD_DO_SET_SERVO, 0, .{ .param1 = 1, .param2 = 1500 });
    defer allocator.free(servo_bytes);
    var servo_mapping = try mavlink.mapping.mapFrameToCommand(allocator, try mavlink.framing.parseFrame(servo_bytes), .{ .vehicle_id = "edge-vehicle-1", .now_ms = 1_000_100 });
    defer servo_mapping.deinit();
    try std.testing.expectEqual(domain.commands.CommandAction.raw_actuator_output, servo_mapping.request.?.action);

    const unknown_command = try mavlink.fake_transport.frameCommandLongV2(allocator, .{ .seq = 9, .sysid = 42, .compid = 191 }, 65_000, 0, .{});
    defer allocator.free(unknown_command);
    var unknown_mapping = try mavlink.mapping.mapFrameToCommand(allocator, try mavlink.framing.parseFrame(unknown_command), .{ .vehicle_id = "edge-vehicle-1", .now_ms = 1_000_100 });
    defer unknown_mapping.deinit();
    try std.testing.expect(unknown_mapping.unsupported != null);
    try std.testing.expectEqual(domain.commands.RiskCategory.unknown, unknown_mapping.unsupported.?.risk);
}

test "phase 28 MISSION_ITEM float layout maps to real waypoint degrees" {
    const allocator = std.testing.allocator;
    const item = try mavlink.fake_transport.frameMissionItemV2(allocator, .{ .seq = 10, .sysid = 42, .compid = 191 }, .{
        .seq = 0,
        .command = mavlink.commands.MAV_CMD_NAV_WAYPOINT,
        .frame = mavlink.messages.MAV_FRAME_GLOBAL,
        .x = 37.0125,
        .y = -122.125,
        .z = 45,
    });
    defer allocator.free(item);

    var mapped = try mavlink.mapping.mapFrameToCommand(
        allocator,
        try mavlink.framing.parseFrame(item),
        .{ .vehicle_id = "edge-vehicle-1", .now_ms = 1_000_100 },
    );
    defer mapped.deinit();

    try std.testing.expectEqual(domain.commands.CommandAction.set_waypoint, mapped.request.?.action);
    const waypoint = mapped.request.?.parameters.waypoint;
    try std.testing.expectApproxEqAbs(@as(f64, 37.0125), waypoint.latitude_deg, 0.000001);
    try std.testing.expectApproxEqAbs(@as(f64, -122.125), waypoint.longitude_deg, 0.000001);
    try std.testing.expectEqual(domain.coordinates.AltitudeReference.amsl, waypoint.altitude_reference);
}

test "phase 28 relative altitude MAVLink frames remain home-relative" {
    const allocator = std.testing.allocator;
    const setpoint = try mavlink.fake_transport.frameSetPositionTargetGlobalIntV2(allocator, .{ .seq = 11, .sysid = 42, .compid = 191 }, .{
        .target_system = 1,
        .target_component = 1,
        .lat_int = 370000000,
        .lon_int = -1220000000,
        .alt_m = 25,
        .type_mask = mavlink.messages.position_mask_velocity_ignored,
        .coordinate_frame = mavlink.messages.MAV_FRAME_GLOBAL_RELATIVE_ALT_INT,
    });
    defer allocator.free(setpoint);

    var setpoint_mapping = try mavlink.mapping.mapFrameToCommand(
        allocator,
        try mavlink.framing.parseFrame(setpoint),
        .{ .vehicle_id = "edge-vehicle-1", .now_ms = 1_000_100 },
    );
    defer setpoint_mapping.deinit();
    try std.testing.expectEqual(domain.coordinates.AltitudeReference.home_relative, setpoint_mapping.request.?.parameters.waypoint.altitude_reference);

    const mission_item = try mavlink.fake_transport.frameMissionItemIntV2(allocator, .{ .seq = 12, .sysid = 42, .compid = 191 }, .{
        .seq = 0,
        .command = mavlink.commands.MAV_CMD_NAV_WAYPOINT,
        .frame = mavlink.messages.MAV_FRAME_GLOBAL_RELATIVE_ALT_INT,
        .x = 370000000,
        .y = -1220000000,
        .z = 25,
    });
    defer allocator.free(mission_item);

    var mission_mapping = try mavlink.mapping.mapFrameToCommand(
        allocator,
        try mavlink.framing.parseFrame(mission_item),
        .{ .vehicle_id = "edge-vehicle-1", .now_ms = 1_000_100 },
    );
    defer mission_mapping.deinit();
    try std.testing.expectEqual(domain.coordinates.AltitudeReference.home_relative, mission_mapping.request.?.parameters.waypoint.altitude_reference);
}

test "phase 28 gateway policy integration observes allows denies and blocks safely" {
    const allocator = std.testing.allocator;
    var loaded = try edge.policy.loadFromSlice(allocator, policy_yaml, "phase28-policy.yaml", .{});
    defer loaded.deinit();
    const state = freshState();

    const arm = try mavlink.fake_transport.frameCommandLongV2(allocator, .{ .seq = 1, .sysid = 42, .compid = 191 }, mavlink.commands.MAV_CMD_COMPONENT_ARM_DISARM, 1, .{});
    defer allocator.free(arm);
    var observed = try mavlink.gateway.processFrame(allocator, .{
        .mode = .observe,
        .direction = .companion_to_vehicle,
        .vehicle_id = "edge-vehicle-1",
        .now_ms = 1_000_500,
    }, &loaded.value, state, try mavlink.framing.parseFrame(arm));
    defer observed.deinit();
    try std.testing.expect(observed.forwarded);
    try std.testing.expectEqual(edge.core.decision.DecisionResult.observe, observed.decision.?);
    try std.testing.expect(observed.audit.hasEvent(.command_observed));
    try std.testing.expect(observed.audit.hasEvent(.message_forwarded));

    var ci = try mavlink.gateway.processFrame(allocator, .{
        .mode = .ci,
        .direction = .companion_to_vehicle,
        .vehicle_id = "edge-vehicle-1",
        .now_ms = 1_000_500,
    }, &loaded.value, state, try mavlink.framing.parseFrame(arm));
    defer ci.deinit();
    try std.testing.expect(ci.blocked);
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, ci.decision.?);

    const land = try mavlink.fake_transport.frameCommandLongV2(allocator, .{ .seq = 2, .sysid = 42, .compid = 191 }, mavlink.commands.MAV_CMD_NAV_LAND, 0, .{});
    defer allocator.free(land);
    var land_result = try mavlink.gateway.processFrame(allocator, .{
        .mode = .enforce,
        .direction = .companion_to_vehicle,
        .vehicle_id = "edge-vehicle-1",
        .now_ms = 1_000_500,
    }, &loaded.value, state, try mavlink.framing.parseFrame(land));
    defer land_result.deinit();
    try std.testing.expect(land_result.forwarded);
    try std.testing.expect(land_result.audit.hasEvent(.command_allowed));

    const disable = try mavlink.fake_transport.frameParamSetV2(allocator, .{ .seq = 3, .sysid = 42, .compid = 191 }, "COM_FAIL_ACT", 0);
    defer allocator.free(disable);
    var disable_result = try mavlink.gateway.processFrame(allocator, .{
        .mode = .enforce,
        .direction = .companion_to_vehicle,
        .vehicle_id = "edge-vehicle-1",
        .now_ms = 1_000_500,
    }, &loaded.value, state, try mavlink.framing.parseFrame(disable));
    defer disable_result.deinit();
    try std.testing.expect(disable_result.blocked);
    try std.testing.expect(disable_result.audit.hasEvent(.command_denied));
    try std.testing.expect(disable_result.audit.hasEvent(.message_blocked));
}

test "phase 28 endpoint policy flags unexpected sysid compid and strict modes fail closed" {
    const allocator = std.testing.allocator;
    var loaded = try edge.policy.loadFromSlice(allocator, policy_yaml, "phase28-policy.yaml", .{});
    defer loaded.deinit();

    const arm = try mavlink.fake_transport.frameCommandLongV2(allocator, .{ .seq = 1, .sysid = 99, .compid = 191 }, mavlink.commands.MAV_CMD_COMPONENT_ARM_DISARM, 1, .{});
    defer allocator.free(arm);
    var result = try mavlink.gateway.processFrame(allocator, .{
        .mode = .ci,
        .direction = .companion_to_vehicle,
        .vehicle_id = "edge-vehicle-1",
        .now_ms = 1_000_500,
        .endpoint_policy = .{ .allowed_source_sysid = 42, .allowed_source_compid = 191, .allowed_target_sysid = 1, .allowed_target_compid = 1 },
    }, &loaded.value, freshState(), try mavlink.framing.parseFrame(arm));
    defer result.deinit();
    try std.testing.expect(result.blocked);
    try std.testing.expect(result.audit.hasEvent(.unexpected_endpoint));
}

test "phase 28 setpoint and mission handling deny geofence and altitude violations" {
    const allocator = std.testing.allocator;
    var loaded = try edge.policy.loadFromSlice(allocator, policy_yaml, "phase28-policy.yaml", .{});
    defer loaded.deinit();

    const outside = try mavlink.fake_transport.frameSetPositionTargetGlobalIntV2(allocator, .{ .seq = 1, .sysid = 42, .compid = 191 }, .{
        .target_system = 1,
        .target_component = 1,
        .lat_int = 370100000,
        .lon_int = -1220000000,
        .alt_m = 20,
        .type_mask = mavlink.messages.position_mask_velocity_ignored,
    });
    defer allocator.free(outside);
    var outside_result = try mavlink.gateway.processFrame(allocator, .{
        .mode = .enforce,
        .direction = .companion_to_vehicle,
        .vehicle_id = "edge-vehicle-1",
        .now_ms = 1_000_500,
    }, &loaded.value, freshState(), try mavlink.framing.parseFrame(outside));
    defer outside_result.deinit();
    try std.testing.expect(outside_result.blocked);
    try std.testing.expect(outside_result.audit.hasEvent(.safety_geofence_violation));

    var tracker = mavlink.mission.MissionTracker.init();
    const count = try mavlink.fake_transport.frameMissionCountV2(allocator, .{ .seq = 2, .sysid = 42, .compid = 191 }, 2);
    defer allocator.free(count);
    try tracker.observe(try mavlink.messages.decode(try mavlink.framing.parseFrame(count)));
    try std.testing.expect(tracker.active);
    try std.testing.expectEqual(@as(u16, 2), tracker.expected_count.?);

    const item0 = try mavlink.fake_transport.frameMissionItemIntV2(allocator, .{ .seq = 3, .sysid = 42, .compid = 191 }, .{
        .seq = 0,
        .command = mavlink.commands.MAV_CMD_NAV_WAYPOINT,
        .frame = mavlink.messages.MAV_FRAME_GLOBAL_RELATIVE_ALT_INT,
        .x = 370000000,
        .y = -1220000000,
        .z = 20,
    });
    defer allocator.free(item0);
    try tracker.observe(try mavlink.messages.decode(try mavlink.framing.parseFrame(item0)));
    try std.testing.expect(tracker.received[0]);

    const item1 = try mavlink.fake_transport.frameMissionItemIntV2(allocator, .{ .seq = 4, .sysid = 42, .compid = 191 }, .{
        .seq = 1,
        .command = mavlink.commands.MAV_CMD_NAV_WAYPOINT,
        .frame = mavlink.messages.MAV_FRAME_GLOBAL_RELATIVE_ALT_INT,
        .x = 370100000,
        .y = -1220000000,
        .z = 20,
    });
    defer allocator.free(item1);
    var mission_result = try mavlink.gateway.processMissionFrame(allocator, .{
        .mode = .enforce,
        .direction = .companion_to_vehicle,
        .vehicle_id = "edge-vehicle-1",
        .now_ms = 1_000_600,
    }, &loaded.value, freshState(), try mavlink.framing.parseFrame(item1), &tracker);
    defer mission_result.deinit();
    try std.testing.expect(mission_result.blocked);
    try std.testing.expect(tracker.denied);
    try std.testing.expect(mission_result.audit.hasEvent(.mission_item_denied));

    try tracker.observe(try mavlink.messages.decode(try mavlink.framing.parseFrame(item0)));
    try std.testing.expect(tracker.duplicate_seen);
    try std.testing.expect(tracker.partialUploadFlagged());
}

test "phase 28 signing detection and audit redaction are bounded" {
    const allocator = std.testing.allocator;
    const signed = try mavlink.fake_transport.frameSignedHeartbeatV2(allocator, .{ .seq = 1, .sysid = 1, .compid = 1 });
    defer allocator.free(signed);
    const frame = try mavlink.framing.parseFrame(signed);
    try std.testing.expect(frame.signature_present);
    const signing = mavlink.signing.inspect(frame);
    try std.testing.expect(signing.present);
    try std.testing.expect(!signing.verification_available);

    var audit = mavlink.audit.AuditLog.init(allocator);
    defer audit.deinit();
    try audit.append(.frame_received, frame, .{ .note = "TOKEN=sk-fakeSyntheticOpenAIKey1234567890", .decision = .observe });
    try std.testing.expect(audit.records.items[0].payload_preview.len <= mavlink.audit.max_payload_preview_len);
    try std.testing.expect(std.mem.indexOf(u8, audit.records.items[0].note, "sk-fakeSyntheticOpenAIKey1234567890") == null);
}

fn freshState() domain.state.VehicleState {
    return .{
        .vehicle_id = .{ .value = "edge-vehicle-1" },
        .vehicle_kind = .drone_multirotor,
        .autopilot_kind = .px4,
        .mode = .guided,
        .arm_state = .armed,
        .position = .{ .latitude_deg = 37.0000, .longitude_deg = -122.0000, .altitude_m = 20, .altitude_reference = .amsl },
        .battery_state = .{ .percent_remaining = 80, .voltage_v = 15.2, .current_a = 2.1, .source = .monotonic },
        .control_authority = .onboard_agent,
        .home_position = .{ .latitude_deg = 37.0000, .longitude_deg = -122.0000, .altitude_m = 0, .altitude_reference = .amsl },
        .timestamp = .{ .value = 1_000_000, .source = .monotonic },
        .state_freshness = .fresh,
        .provenance = .fake_adapter,
    };
}

fn expectJsonStringInArray(items: []const std.json.Value, expected: []const u8) !void {
    for (items) |item| {
        if (item == .string and std.mem.eql(u8, item.string, expected)) return;
    }
    return error.TestUnexpectedResult;
}
