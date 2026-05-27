const std = @import("std");
const edge = @import("orca_edge");

const domain = edge.domain;
const schema = edge.schema;

test "phase 26 coordinate validation requires explicit geographic bounds and altitude references" {
    try std.testing.expectError(error.InvalidLatitude, (domain.coordinates.GeoPoint{
        .latitude_deg = 91,
        .longitude_deg = 0,
        .altitude_m = 10,
        .altitude_reference = .amsl,
    }).validate());

    try std.testing.expectError(error.InvalidLongitude, (domain.coordinates.GeoPoint{
        .latitude_deg = 0,
        .longitude_deg = -181,
        .altitude_m = 10,
        .altitude_reference = .amsl,
    }).validate());

    try std.testing.expectError(error.UnknownAltitudeReference, (domain.coordinates.GeoPoint{
        .latitude_deg = 37,
        .longitude_deg = -122,
        .altitude_m = 10,
        .altitude_reference = .unknown,
    }).validate());
}

test "phase 26 local frame mismatch is rejected unless explicit conversion exists" {
    const ned = domain.coordinates.LocalPosition{ .x_m = 1, .y_m = 2, .z_m = -3, .frame = .local_ned };
    try std.testing.expectError(error.UnsupportedCoordinateConversion, domain.coordinates.convertLocalPosition(ned, .local_enu));
    try std.testing.expectError(error.CoordinateFrameMismatch, domain.coordinates.requireMatchingFrames(.local_ned, .local_enu));
    try domain.coordinates.requireMatchingFrames(.local_ned, .local_ned);
}

test "phase 26 envelope validation catches bad limits and command policy conflicts" {
    try std.testing.expectError(error.InvalidSpeedLimit, (domain.safety_envelope.VelocityLimits{
        .max_horizontal_mps = -1,
        .max_vertical_mps = 2,
    }).validate());

    try std.testing.expectError(error.InvalidAltitudeLimit, (domain.safety_envelope.AltitudeLimits{
        .min_altitude_m = 120,
        .max_altitude_m = 20,
        .altitude_reference = .amsl,
    }).validate());

    try std.testing.expectError(error.InvalidBatteryThreshold, (domain.safety_envelope.BatteryPolicy{
        .deny_takeoff_below_percent = 20,
        .return_home_below_percent = 30,
        .land_below_percent = 10,
    }).validate());

    try std.testing.expectError(error.DuplicateCommandPolicyEntry, (domain.safety_envelope.CommandPolicy{
        .allow = &.{ .read_telemetry, .land },
        .ask = &.{.takeoff},
        .deny = &.{.land},
        .require_operator_approval = &.{.arm},
    }).validate());

    const policy = domain.safety_envelope.CommandPolicy{
        .allow = &.{.land},
        .ask = &.{.takeoff},
        .deny = &.{.raw_actuator_output},
        .require_operator_approval = &.{.arm},
    };
    try policy.validate();
    try std.testing.expectEqual(domain.safety_envelope.CommandDisposition.deny, policy.resolve(.raw_actuator_output));
}

test "phase 26 geofence validation is schema-only and does not enforce geography" {
    const home = domain.coordinates.GeoPoint{
        .latitude_deg = 37,
        .longitude_deg = -122,
        .altitude_m = 0,
        .altitude_reference = .amsl,
    };

    try std.testing.expectError(error.InvalidGeofenceRadius, (domain.geofence.Geofence{
        .shape = .{ .circle = .{ .center = home, .max_radius_m = -1 } },
        .altitude_floor_m = 2,
        .altitude_ceiling_m = 120,
        .altitude_reference = .amsl,
        .boundary_action = .deny,
    }).validate());

    try (domain.geofence.Geofence{
        .shape = .{ .circle = .{ .center = home, .max_radius_m = 500 } },
        .altitude_floor_m = 2,
        .altitude_ceiling_m = 120,
        .altitude_reference = .amsl,
        .boundary_action = .deny,
    }).validate();
}

test "phase 26 vehicle state validation preserves freshness and provenance boundaries" {
    var state = domain.state.VehicleState{
        .vehicle_id = .{ .value = "edge-vehicle-1" },
        .vehicle_kind = .drone_multirotor,
        .autopilot_kind = .px4,
        .mode = .hold,
        .arm_state = .disarmed,
        .control_authority = .human_operator,
        .timestamp = .{ .value = 1_777_983_130_000, .source = .monotonic },
        .state_freshness = .fresh,
        .provenance = .fake_adapter,
    };
    try state.validateForAudit();
    try state.validateFreshKnown();

    state.state_freshness = .stale;
    try std.testing.expectError(error.StateNotFresh, state.validateFreshKnown());

    state.state_freshness = .fresh;
    state.vehicle_kind = .unknown;
    try std.testing.expectError(error.UnknownStateIsUnsafe, state.validateFreshKnown());

    state.vehicle_kind = .drone_multirotor;
    state.provenance = .sitl_px4;
    try std.testing.expectError(error.FakeStateMislabeledAsSitlOrHardware, state.requireFakeAdapterProvenance(.fake));
}

test "phase 26 command requests cover categories and default risk classification" {
    const timestamp = domain.coordinates.Timestamp{ .value = 1_777_983_130_000, .source = .monotonic };
    for (domain.commands.CommandAction.all()) |action| {
        const request = domain.commands.CommandRequest.init(.{
            .command_id = "cmd-1",
            .vehicle_id = .{ .value = "edge-vehicle-1" },
            .action = action,
            .parameters = validParametersFor(action),
            .actor = "agent-under-test",
            .timestamp = timestamp,
            .source = .fake_adapter,
        });
        try request.validate();
    }

    try std.testing.expectEqual(domain.risk.RiskCategory.low, domain.risk.classifyCommand(.read_telemetry));
    try std.testing.expectEqual(domain.risk.RiskCategory.high, domain.risk.classifyCommand(.arm));
    try std.testing.expectEqual(domain.risk.RiskCategory.high, domain.risk.classifyCommand(.takeoff));
    try std.testing.expectEqual(domain.risk.RiskCategory.emergency_safe, domain.risk.classifyCommand(.land));
    try std.testing.expectEqual(domain.risk.RiskCategory.critical, domain.risk.classifyCommand(.disable_failsafe));
    try std.testing.expectEqual(domain.risk.RiskCategory.critical, domain.risk.classifyCommand(.raw_actuator_output));
}

fn validParametersFor(action: domain.commands.CommandAction) domain.commands.CommandParameters {
    return switch (action) {
        .takeoff, .set_altitude => .{ .altitude = .{ .altitude_m = 20, .altitude_reference = .amsl } },
        .set_waypoint => .{ .waypoint = .{ .latitude_deg = 37, .longitude_deg = -122, .altitude_m = 20, .altitude_reference = .amsl } },
        .set_velocity => .{ .velocity = .{ .vx_mps = 1, .vy_mps = 1, .vz_mps = 0, .frame = .local_ned } },
        .set_heading => .{ .heading = domain.coordinates.Heading.degrees(90) },
        .set_mode => .{ .mode = .mission },
        else => .none,
    };
}

test "phase 26 edge policy schema validates versioned safety shape" {
    const policy = schema.edge_policy_schema.EdgePolicyV1.example();
    try policy.validate();

    var duplicate = policy;
    duplicate.commands.allow = &.{ .land, .takeoff };
    duplicate.commands.ask = &.{.takeoff};
    try std.testing.expectError(error.DuplicateCommandPolicyEntry, duplicate.validate());
}

test "phase 26 edge event and safety report schemas are discoverable" {
    try std.testing.expect(schema.edge_event_schema.hasEventType("vehicle.command_denied"));
    try std.testing.expect(schema.edge_event_schema.hasEventType("safety.stale_state_denied"));
    try std.testing.expect(schema.safety_report_schema.hasEnvironment("PX4 SITL"));
    try std.testing.expect(schema.safety_report_schema.hasLimitation(schema.safety_report_schema.non_certification_disclaimer));
}

test "phase 26 edge package imports Core and docs make no real-flight claims" {
    _ = edge.core;

    const docs = [_][]const u8{
        "packages/edge/README.md",
        "docs/edge/domain-model.md",
        "docs/edge/safety-policy.md",
        "docs/edge/coordinate-frames.md",
        "docs/edge/safety-schemas.md",
    };

    for (docs) |path| {
        const text = try std.fs.cwd().readFileAlloc(std.testing.allocator, path, 128 * 1024);
        defer std.testing.allocator.free(text);
        try std.testing.expect(std.mem.indexOf(u8, text, "not ready for real flight") != null or std.mem.indexOf(u8, text, "must not be used for real flight") != null);
        try expectNoForbiddenEdgeClaim(text);
    }
}

fn expectNoForbiddenEdgeClaim(text: []const u8) !void {
    const forbidden = [_][]const u8{
        "active MAVLink",
        "active PX4",
        "active ArduPilot",
        "production-flight-ready",
        "real-flight-ready",
        "certified for flight",
        "regulatory approved",
        "is a flight controller",
        "is an autopilot replacement",
        "is detect-and-avoid",
    };

    for (forbidden) |phrase| {
        try std.testing.expect(std.mem.indexOf(u8, text, phrase) == null);
    }
}
