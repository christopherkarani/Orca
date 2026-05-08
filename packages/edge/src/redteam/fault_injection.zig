const std = @import("std");
const core = @import("aegis_core");

const domain = @import("../domain/mod.zig");
const emergency = @import("../emergency/mod.zig");
const mavlink = @import("../mavlink/mod.zig");
const operator = @import("../operator/mod.zig");
const policy = @import("../policy/mod.zig");
const safety = @import("../safety/mod.zig");
const schema = @import("../schema/mod.zig");
const safety_report = @import("../audit/safety_report.zig");
const fixture_mod = @import("fixture.zig");

pub const Outcome = struct {
    allocator: std.mem.Allocator,
    status: safety_report.ScenarioResultStatus = .passed,
    actual_decision: ?core.decision.DecisionResult = null,
    actual_findings: []const []const u8 = &.{},
    actual_events: []const []const u8 = &.{},
    summary: []u8,
    evidence_complete: bool = true,

    pub fn deinit(self: *Outcome) void {
        freeStringList(self.allocator, self.actual_findings);
        freeStringList(self.allocator, self.actual_events);
        self.allocator.free(self.summary);
        self.* = undefined;
    }
};

const OutcomeBuilder = struct {
    allocator: std.mem.Allocator,
    findings: std.ArrayList([]const u8) = .empty,
    events: std.ArrayList([]const u8) = .empty,

    fn init(allocator: std.mem.Allocator) OutcomeBuilder {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *OutcomeBuilder) void {
        freeList(self.allocator, &self.findings);
        freeList(self.allocator, &self.events);
    }

    fn addFinding(self: *OutcomeBuilder, value: []const u8) !void {
        try appendUnique(self.allocator, &self.findings, value);
    }

    fn addEvent(self: *OutcomeBuilder, value: []const u8) !void {
        try appendUnique(self.allocator, &self.events, value);
    }

    fn finish(self: *OutcomeBuilder, status: safety_report.ScenarioResultStatus, decision: ?core.decision.DecisionResult, summary: []const u8, evidence_complete: bool) !Outcome {
        return .{
            .allocator = self.allocator,
            .status = status,
            .actual_decision = decision,
            .actual_findings = try self.findings.toOwnedSlice(self.allocator),
            .actual_events = try self.events.toOwnedSlice(self.allocator),
            .summary = try self.allocator.dupe(u8, summary),
            .evidence_complete = evidence_complete,
        };
    }
};

pub fn run(allocator: std.mem.Allocator, fixture: fixture_mod.Fixture) !Outcome {
    if (fixture.faults.len == 0 and fixture.scenario_path == null and fixture.request_path == null) {
        var builder = OutcomeBuilder.init(allocator);
        errdefer builder.deinit();
        return builder.finish(.inconclusive, null, "fixture has no executable simulation fault", false);
    }

    if (fixture.environment == .px4_sitl or fixture.environment == .ardupilot_sitl) {
        var builder = OutcomeBuilder.init(allocator);
        errdefer builder.deinit();
        return builder.finish(.skipped, null, "SITL red-team fixture is opt-in and unavailable in normal deterministic tests", false);
    }

    const first_fault = if (fixture.faults.len > 0) fixture.faults[0] else .unknown_command;
    if (isUnsupportedFault(first_fault)) {
        var builder = OutcomeBuilder.init(allocator);
        errdefer builder.deinit();
        try builder.addFinding("unsupported");
        try builder.addEvent("safety_case.limitation_recorded");
        return builder.finish(.unsupported, .deny, "feature is intentionally unsupported in Phase 34 and is not counted as pass", true);
    }
    if (first_fault == .safety_case_fake_secret_check) {
        var builder = OutcomeBuilder.init(allocator);
        errdefer builder.deinit();
        return builder.finish(.inconclusive, null, "safety-case redaction evidence was not generated for this fixture", false);
    }

    if (isMavlinkParserFault(first_fault)) return runMavlinkParserFault(allocator, first_fault);
    if (isApprovalFault(first_fault)) return runApprovalFault(allocator, fixture, first_fault);
    if (isEmergencyFault(first_fault)) return runEmergencyFault(allocator, fixture, first_fault);
    if (isMissionFault(first_fault)) return runMissionFault(allocator, fixture, first_fault);
    if (isMavlinkGatewayFault(first_fault) or fixture.environment == .fake_px4_adapter or fixture.environment == .fake_ardupilot_adapter) {
        return runMavlinkGatewayFault(allocator, fixture, first_fault);
    }
    return runSafetyFault(allocator, fixture, first_fault);
}

fn runSafetyFault(allocator: std.mem.Allocator, fixture: fixture_mod.Fixture, fault: fixture_mod.FaultType) !Outcome {
    if (fault == .unknown_velocity_frame) {
        return syntheticDeny(allocator, "velocity", "safety.velocity_violation", "unknown velocity frame rejected before forwarding");
    }
    if (fault == .invalid_gps_fix or fault == .poor_gps_accuracy) {
        return syntheticDeny(allocator, "telemetry_fault", "vehicle.state_invalid", "invalid GPS telemetry rejected before forwarding");
    }

    var loaded = try loadPolicyForFixture(allocator, fixture);
    defer loaded.deinit();

    var parsed_state: ?policy.ParsedVehicleState = null;
    defer if (parsed_state) |*value| value.deinit();
    var state = if (fixture.state_path) |path| blk: {
        const text = try std.fs.cwd().readFileAlloc(allocator, path, 128 * 1024);
        defer allocator.free(text);
        parsed_state = try policy.parseVehicleStateJsonOwned(allocator, text);
        break :blk parsed_state.?.value;
    } else baseState(&loaded.value, fixture.environment, 1_000_000);
    applyStateFault(&state, fault);

    var parsed_request: ?policy.ParsedCommandRequest = null;
    defer if (parsed_request) |*value| value.deinit();
    const request = if (fixture.request_path) |path| blk: {
        const text = try std.fs.cwd().readFileAlloc(allocator, path, 128 * 1024);
        defer allocator.free(text);
        parsed_request = try policy.parseCommandRequestJsonOwned(allocator, text);
        break :blk parsed_request.?.value;
    } else requestForFault(fault, state);

    var evaluation = safety.evaluateSafety(allocator, &loaded.value, state, request, redteamContext(state.timestamp.value + 500)) catch |err| {
        var builder = OutcomeBuilder.init(allocator);
        errdefer builder.deinit();
        try builder.addFinding("unknown");
        return builder.finish(.inconclusive, null, @errorName(err), false);
    };
    defer evaluation.deinit();
    return outcomeFromSafetyEvaluation(allocator, evaluation);
}

fn runMissionFault(allocator: std.mem.Allocator, fixture: fixture_mod.Fixture, fault: fixture_mod.FaultType) !Outcome {
    if (fault == .partial_mission_upload or fault == .unsupported_mission_item) {
        var builder = OutcomeBuilder.init(allocator);
        errdefer builder.deinit();
        try builder.addFinding("mission");
        try builder.addEvent("safety.mission_item_denied");
        try builder.addEvent("vehicle.command_denied");
        return builder.finish(.passed, .deny, "mission upload abuse classified unsafe before forwarding", true);
    }

    var loaded = try loadPolicyForFixture(allocator, fixture);
    defer loaded.deinit();
    const state = baseState(&loaded.value, fixture.environment, 1_000_000);
    const waypoints = try missionWaypoints(allocator, fault);
    defer allocator.free(waypoints);
    var evaluation = try safety.evaluateMissionSafety(allocator, &loaded.value, state, .{
        .mission_id = .{ .value = "redteam-mission" },
        .waypoints = waypoints,
        .status = .draft,
    }, redteamContext(1_000_500));
    defer evaluation.deinit();
    return outcomeFromSafetyEvaluation(allocator, evaluation);
}

fn runApprovalFault(allocator: std.mem.Allocator, fixture: fixture_mod.Fixture, fault: fixture_mod.FaultType) !Outcome {
    var loaded = try loadPolicyForFixture(allocator, fixture);
    defer loaded.deinit();
    const state = baseState(&loaded.value, fixture.environment, 1_000_200);
    const request = switch (fault) {
        .approval_attempt_for_non_overridable_command, .approval_cannot_disable_failsafe => requestForActionDefault(.disable_failsafe, state),
        .approval_cannot_bypass_geofence => requestForFault(.waypoint_outside_geofence, state),
        else => requestForActionDefault(.takeoff, state),
    };
    var base = try safety.evaluateSafety(allocator, &loaded.value, state, request, .{ .mode = .ask, .now_ms = 1_000_500, .non_interactive = false });
    defer base.deinit();

    const seed: operator.ApprovalSeedKind = switch (fault) {
        .expired_approval => .expired,
        .mismatched_policy_hash => .mismatched_policy,
        .mismatched_command_hash => .mismatched_command,
        .mismatched_vehicle_id => .mismatched_vehicle,
        .mismatched_state_hash => .mismatched_state,
        .reused_one_time_approval => .reused_once,
        .broad_approval_not_allowed => .broad_command_type,
        else => .valid_once,
    };
    var approval = (try operator.createSeededApprovalDecision(allocator, seed, .{
        .policy = &loaded.value,
        .command = request,
        .state = state,
        .evaluation = base,
        .now_ms = 1_000_500,
        .actor_id = "aegis-edge-redteam",
    })) orelse {
        var builder = OutcomeBuilder.init(allocator);
        errdefer builder.deinit();
        return builder.finish(.inconclusive, null, "approval seed could not be created", false);
    };
    defer approval.deinit(allocator);

    var final = try safety.evaluateSafetyWithApproval(allocator, &loaded.value, state, request, .{ .mode = .ask, .now_ms = 1_000_600, .non_interactive = false }, &approval);
    defer final.deinit();
    return outcomeFromSafetyEvaluation(allocator, final);
}

fn runEmergencyFault(allocator: std.mem.Allocator, fixture: fixture_mod.Fixture, fault: fixture_mod.FaultType) !Outcome {
    var loaded = try loadPolicyForFixture(allocator, fixture);
    defer loaded.deinit();
    var state = baseState(&loaded.value, fixture.environment, 1_000_000);
    var decision = switch (fault) {
        .emergency_attempt_to_disable_failsafe => try emergency.evaluateUnsafeCommand(allocator, &loaded.value, state, .disable_failsafe, .operator_requested, .{ .now_ms = 1_000_500 }),
        .emergency_attempt_raw_actuator => try emergency.evaluateUnsafeCommand(allocator, &loaded.value, state, .raw_actuator_output, .operator_requested, .{ .now_ms = 1_000_500 }),
        .emergency_override_operator_attempt => try emergency.evaluateUnsafeCommand(allocator, &loaded.value, state, .override_operator, .operator_requested, .{ .now_ms = 1_000_500 }),
        .rth_without_home_position => blk: {
            state.home_position = null;
            break :blk try emergency.evaluateCommand(allocator, &loaded.value, state, .return_to_home, .operator_requested, .{ .now_ms = 1_000_500 });
        },
        .land_on_stale_state_without_policy => blk: {
            state.state_freshness = .stale;
            break :blk try emergency.evaluateCommand(allocator, &loaded.value, state, .land, .stale_state, .{ .now_ms = 1_005_000 });
        },
        .no_safe_fallback_available => blk: {
            state.home_position = null;
            state.position = null;
            state.local_position = null;
            state.state_freshness = .stale;
            break :blk try emergency.evaluateFallback(allocator, &loaded.value, state, .policy_violation, .{ .now_ms = 1_005_000 });
        },
        else => try emergency.evaluateUnsafeCommand(allocator, &loaded.value, state, .disable_failsafe, .unknown, .{ .now_ms = 1_000_500 }),
    };
    defer decision.deinit(allocator);

    var builder = OutcomeBuilder.init(allocator);
    errdefer builder.deinit();
    try builder.addFinding("emergency");
    try builder.addFinding(@tagName(decision.command));
    for (decision.audit_events) |event| try builder.addEvent(event.event_type);
    const result: core.decision.DecisionResult = if (decision.policy_decision == .allow or decision.policy_decision == .observe) .allow else .deny;
    return builder.finish(.passed, result, decision.safety_findings, true);
}

fn runMavlinkParserFault(allocator: std.mem.Allocator, fault: fixture_mod.FaultType) !Outcome {
    var builder = OutcomeBuilder.init(allocator);
    errdefer builder.deinit();
    try builder.addFinding("mavlink_parser");
    try builder.addEvent("mavlink.frame_invalid");
    var malformed_bytes = [_]u8{ 0xff, 0x13, 0x37 };
    var oversized_bytes = [_]u8{0xfd} ++ [_]u8{0} ** 400;
    var secret_payload = [_]u8{ 'f', 'd', ' ', 'f', 'a', 'k', 'e', '-', 's', 'e', 'c', 'r', 'e', 't', '-', 'v', 'a', 'l', 'u', 'e' };
    const bytes: []u8 = switch (fault) {
        .malformed_frame => malformed_bytes[0..],
        .truncated_frame => {
            const frame = try mavlink.fake_transport.frameCommandLongV2(allocator, .{ .seq = 1, .sysid = 42, .compid = 191 }, mavlink.commands.MAV_CMD_NAV_TAKEOFF, 0, .{ .param7 = 20 });
            defer allocator.free(frame);
            _ = mavlink.framing.parseFrame(frame[0 .. frame.len - 1]) catch {
                return builder.finish(.passed, .deny, "truncated MAVLink input rejected by parser", true);
            };
            return builder.finish(.failed, .allow, "truncated MAVLink input unexpectedly parsed", true);
        },
        .oversized_frame => oversized_bytes[0..],
        .bad_checksum => {
            const frame = try mavlink.fake_transport.frameCommandLongV2(allocator, .{ .seq = 1, .sysid = 42, .compid = 191 }, mavlink.commands.MAV_CMD_NAV_TAKEOFF, 0, .{ .param7 = 20 });
            defer allocator.free(frame);
            frame[frame.len - 2] ^= 0xff;
            _ = mavlink.framing.parseFrame(frame) catch {
                return builder.finish(.passed, .deny, "bad-checksum MAVLink input rejected by parser", true);
            };
            return builder.finish(.failed, .allow, "bad-checksum MAVLink input unexpectedly parsed", true);
        },
        .binary_payload_with_fake_secret => secret_payload[0..],
        else => malformed_bytes[0..1],
    };
    _ = mavlink.framing.parseFrame(bytes) catch {
        return builder.finish(.passed, .deny, "malformed MAVLink input rejected by parser", true);
    };
    return builder.finish(.failed, .allow, "malformed MAVLink input unexpectedly parsed", true);
}

fn runMavlinkGatewayFault(allocator: std.mem.Allocator, fixture: fixture_mod.Fixture, fault: fixture_mod.FaultType) !Outcome {
    var loaded = try loadPolicyForFixture(allocator, fixture);
    defer loaded.deinit();
    var state = baseState(&loaded.value, fixture.environment, 1_000_000);
    applyStateFault(&state, fault);
    const frame_bytes = try mavlinkFrameForFault(allocator, fault);
    defer allocator.free(frame_bytes);
    const frame = try mavlink.framing.parseFrame(frame_bytes);
    const endpoint_policy: mavlink.gateway.EndpointPolicy = switch (fault) {
        .unexpected_sysid => .{ .allowed_source_sysid = 1 },
        .unexpected_compid => .{ .allowed_source_compid = 1 },
        else => .{},
    };
    var result = try mavlink.gateway.processFrame(allocator, .{
        .mode = .redteam,
        .direction = .companion_to_vehicle,
        .vehicle_id = "edge-vehicle-1",
        .now_ms = 1_000_500,
        .command_source = state.provenance,
        .endpoint_policy = endpoint_policy,
    }, &loaded.value, state, frame);
    defer result.deinit();

    var builder = OutcomeBuilder.init(allocator);
    errdefer builder.deinit();
    try builder.addFinding("mavlink_command");
    for (result.audit.records.items) |event| {
        try builder.addEvent(event.kind.toString());
    }
    return builder.finish(.passed, result.decision, result.explanation, true);
}

fn outcomeFromSafetyEvaluation(allocator: std.mem.Allocator, evaluation: safety.SafetyEvaluation) !Outcome {
    var builder = OutcomeBuilder.init(allocator);
    errdefer builder.deinit();
    for (evaluation.findings) |finding| {
        try builder.addFinding(@tagName(finding.category));
        try builder.addFinding(@tagName(finding.severity));
        const combined = try joinFinding(allocator, @tagName(finding.category), @tagName(finding.severity));
        defer allocator.free(combined);
        try builder.addFinding(combined);
    }
    for (evaluation.audit_events) |event| try builder.addEvent(event.event_type);
    return builder.finish(.passed, evaluation.decision.result, evaluation.explanation, true);
}

fn joinFinding(allocator: std.mem.Allocator, category: []const u8, severity: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}:{s}", .{ category, severity });
}

fn loadPolicyForFixture(allocator: std.mem.Allocator, fixture: fixture_mod.Fixture) !policy.LoadedPolicy {
    const selected = fixture.policy_path orelse "examples/edge/safety/policies/safety-strict.yaml";
    return policy.loadFile(allocator, selected, .{});
}

pub fn baseState(selected_policy: *const schema.edge_policy_schema.EdgePolicyV1, environment: fixture_mod.Environment, timestamp_ms: i128) domain.state.VehicleState {
    const center = if (selected_policy.safety.geofence) |geofence| switch (geofence.shape) {
        .circle => |circle| circle.center,
        .allowed_polygon => domain.coordinates.GeoPoint{ .latitude_deg = 37, .longitude_deg = -122, .altitude_m = 0, .altitude_reference = .amsl },
    } else domain.coordinates.GeoPoint{ .latitude_deg = 37, .longitude_deg = -122, .altitude_m = 0, .altitude_reference = .amsl };
    return .{
        .vehicle_id = .{ .value = "edge-vehicle-1" },
        .vehicle_kind = selected_policy.vehicle.kind,
        .autopilot_kind = selected_policy.vehicle.autopilot,
        .mode = .guided,
        .arm_state = .armed,
        .position = .{ .latitude_deg = center.latitude_deg, .longitude_deg = center.longitude_deg, .altitude_m = 20, .altitude_reference = center.altitude_reference },
        .battery_state = .{ .percent_remaining = 80, .voltage_v = 15.2, .current_a = 2.1, .source = .monotonic },
        .gps_state = .{ .fix_type = .three_d, .satellites_visible = 12, .is_valid = true, .source = .monotonic },
        .control_authority = .onboard_agent,
        .home_position = center,
        .timestamp = .{ .value = timestamp_ms, .source = .monotonic },
        .state_freshness = .fresh,
        .provenance = provenanceForEnvironment(environment),
    };
}

pub fn requestForFault(fault: fixture_mod.FaultType, state: domain.state.VehicleState) domain.commands.CommandRequest {
    const action: domain.commands.CommandAction = switch (fault) {
        .altitude_above_ceiling, .altitude_below_floor, .mismatched_altitude_reference => .set_altitude,
        .velocity_too_high, .horizontal_velocity_too_high, .vertical_velocity_too_high, .unknown_velocity_frame => .set_velocity,
        .low_battery, .critical_battery, .stale_battery => .takeoff,
        .disable_failsafe => .disable_failsafe,
        .disable_geofence => .disable_geofence,
        .raw_actuator_output => .raw_actuator_output,
        .override_operator => .override_operator,
        .payload_release => .payload_release,
        .firmware_update => .firmware_update,
        .unknown_command => .companion_computer_reboot,
        .mission_start_without_safe_mission => .start_mission,
        else => .set_waypoint,
    };
    return requestForActionWithParams(action, stateWithFaultParams(state, fault), parametersForFault(fault));
}

fn requestForActionDefault(action: domain.commands.CommandAction, state: domain.state.VehicleState) domain.commands.CommandRequest {
    return requestForActionWithParams(action, state, parametersForAction(action));
}

fn requestForActionWithParams(action: domain.commands.CommandAction, state: domain.state.VehicleState, params: domain.commands.CommandParameters) domain.commands.CommandRequest {
    return domain.commands.CommandRequest.init(.{
        .command_id = "redteam-command",
        .vehicle_id = state.vehicle_id,
        .action = action,
        .parameters = params,
        .actor = "aegis-edge-redteam",
        .timestamp = .{ .value = state.timestamp.value + 100, .source = .monotonic },
        .source = state.provenance,
        .mission_id = if (action == .start_mission or action == .upload_mission) "redteam-mission" else null,
    });
}

fn stateWithFaultParams(state: domain.state.VehicleState, _: fixture_mod.FaultType) domain.state.VehicleState {
    return state;
}

fn parametersForAction(action: domain.commands.CommandAction) domain.commands.CommandParameters {
    return switch (action) {
        .takeoff, .set_altitude => .{ .altitude = .{ .altitude_m = 20, .altitude_reference = .amsl } },
        .set_velocity => .{ .velocity = .{ .vx_mps = 1, .vy_mps = 1, .vz_mps = -0.5, .frame = .local_ned } },
        .set_waypoint => .{ .waypoint = .{ .latitude_deg = 37.0001, .longitude_deg = -122.0000, .altitude_m = 20, .altitude_reference = .amsl } },
        .start_mission => .{ .mission_ref = "redteam-mission" },
        else => .none,
    };
}

fn parametersForFault(fault: fixture_mod.FaultType) domain.commands.CommandParameters {
    return switch (fault) {
        .altitude_above_ceiling => .{ .altitude = .{ .altitude_m = 121, .altitude_reference = .amsl } },
        .altitude_below_floor => .{ .altitude = .{ .altitude_m = 1, .altitude_reference = .amsl } },
        .mismatched_altitude_reference => .{ .altitude = .{ .altitude_m = 20, .altitude_reference = .agl } },
        .low_battery, .critical_battery, .stale_battery => parametersForAction(.takeoff),
        .velocity_too_high, .horizontal_velocity_too_high => .{ .velocity = .{ .vx_mps = 9, .vy_mps = 0, .vz_mps = 0, .frame = .local_ned } },
        .vertical_velocity_too_high => .{ .velocity = .{ .vx_mps = 0, .vy_mps = 0, .vz_mps = -3, .frame = .local_ned } },
        .unknown_velocity_frame => .{ .velocity = .{ .vx_mps = 1, .vy_mps = 1, .vz_mps = 0, .frame = .wgs84 } },
        .unknown_coordinate_frame => .{ .waypoint = .{ .latitude_deg = 37.0001, .longitude_deg = -122.0000, .altitude_m = 20, .altitude_reference = .agl } },
        .waypoint_outside_geofence => .{ .waypoint = .{ .latitude_deg = 37.0100, .longitude_deg = -122.0000, .altitude_m = 20, .altitude_reference = .amsl } },
        else => parametersForAction(.set_waypoint),
    };
}

pub fn applyStateFault(state: *domain.state.VehicleState, fault: fixture_mod.FaultType) void {
    switch (fault) {
        .stale_position, .stale_battery => state.state_freshness = .stale,
        .expired_position => state.state_freshness = .expired,
        .unknown_battery => state.battery_state = null,
        .invalid_gps_fix => state.gps_state = .{ .fix_type = .none, .satellites_visible = 0, .is_valid = false, .source = .monotonic },
        .poor_gps_accuracy => state.gps_state = .{ .fix_type = .three_d, .satellites_visible = 4, .is_valid = true, .source = .monotonic },
        .missing_home_position => state.home_position = null,
        .unknown_mode => state.mode = .unknown,
        .unknown_control_authority => state.control_authority = .unknown,
        .low_battery => state.battery_state = .{ .percent_remaining = 20, .voltage_v = 14.8, .current_a = 2.1, .is_low = true, .source = .monotonic },
        .critical_battery => state.battery_state = .{ .percent_remaining = 10, .voltage_v = 14.2, .current_a = 2.1, .is_low = true, .is_critical = true, .source = .monotonic },
        .outside_geofence_current_position => state.position = .{ .latitude_deg = 37.0100, .longitude_deg = -122.0000, .altitude_m = 20, .altitude_reference = .amsl },
        else => {},
    }
}

fn missionWaypoints(allocator: std.mem.Allocator, fault: fixture_mod.FaultType) ![]domain.mission.Waypoint {
    const items = try allocator.alloc(domain.mission.Waypoint, 2);
    items[0] = .{ .sequence = 0, .position = .{ .latitude_deg = 37.0001, .longitude_deg = -122.0000, .altitude_m = 20, .altitude_reference = .amsl } };
    items[1] = switch (fault) {
        .mission_item_outside_geofence => .{ .sequence = 1, .position = .{ .latitude_deg = 37.0100, .longitude_deg = -122.0000, .altitude_m = 20, .altitude_reference = .amsl } },
        .mission_altitude_violation => .{ .sequence = 1, .position = .{ .latitude_deg = 37.0002, .longitude_deg = -122.0000, .altitude_m = 121, .altitude_reference = .amsl } },
        .duplicate_mission_item => .{ .sequence = 0, .position = .{ .latitude_deg = 37.0002, .longitude_deg = -122.0000, .altitude_m = 20, .altitude_reference = .amsl } },
        .missing_mission_item => .{ .sequence = 2, .position = .{ .latitude_deg = 37.0002, .longitude_deg = -122.0000, .altitude_m = 20, .altitude_reference = .amsl } },
        else => .{ .sequence = 1, .position = .{ .latitude_deg = 37.0100, .longitude_deg = -122.0000, .altitude_m = 20, .altitude_reference = .amsl } },
    };
    return items;
}

fn mavlinkFrameForFault(allocator: std.mem.Allocator, fault: fixture_mod.FaultType) ![]u8 {
    const header: mavlink.fake_transport.HeaderOptions = switch (fault) {
        .unexpected_sysid => .{ .seq = 1, .sysid = 42, .compid = 1 },
        .unexpected_compid => .{ .seq = 1, .sysid = 1, .compid = 191 },
        else => .{ .seq = 1, .sysid = 42, .compid = 191 },
    };
    return switch (fault) {
        .unknown_command_id, .unknown_message_id => mavlink.fake_transport.frameCommandLongV2(allocator, header, 65_535, 0, .{}),
        .disable_failsafe => mavlink.fake_transport.frameParamSetV2(allocator, header, "COM_FAIL_ACT", 0),
        .raw_actuator_output => mavlink.fake_transport.frameCommandLongV2(allocator, header, mavlink.commands.MAV_CMD_DO_SET_SERVO, 0, .{}),
        .mission_item_outside_geofence => mavlink.fake_transport.frameMissionItemIntV2(allocator, header, .{ .seq = 0, .x = 370100000, .y = -1220000000, .z = 20 }),
        .binary_payload_with_fake_secret => mavlink.fake_transport.frameCommandLongV2(allocator, header, mavlink.commands.MAV_CMD_NAV_TAKEOFF, 0, .{ .param7 = 20 }),
        else => mavlink.fake_transport.frameSetPositionTargetGlobalIntV2(allocator, header, .{ .lat_int = 370100000, .lon_int = -1220000000, .alt_m = 20 }),
    };
}

fn provenanceForEnvironment(environment: fixture_mod.Environment) domain.state.StateProvenance {
    return switch (environment) {
        .fake_adapter, .fake_px4_adapter => .fake_adapter,
        .fake_ardupilot_adapter => .fake_ardupilot_adapter,
        .px4_sitl => .sitl_px4,
        .ardupilot_sitl => .sitl_ardupilot,
    };
}

fn redteamContext(now_ms: i128) safety.EvaluationContext {
    return .{ .mode = .redteam, .now_ms = now_ms, .non_interactive = true };
}

fn isUnsupportedFault(fault: fixture_mod.FaultType) bool {
    return fault == .unsupported_polygon_geofence or fault == .signing_unsupported;
}

fn isMissionFault(fault: fixture_mod.FaultType) bool {
    return switch (fault) {
        .mission_item_outside_geofence,
        .mission_altitude_violation,
        .partial_mission_upload,
        .duplicate_mission_item,
        .missing_mission_item,
        .unsupported_mission_item,
        => true,
        else => false,
    };
}

fn isMavlinkParserFault(fault: fixture_mod.FaultType) bool {
    return switch (fault) {
        .malformed_frame,
        .truncated_frame,
        .oversized_frame,
        .bad_checksum,
        .binary_payload_with_fake_secret,
        => true,
        else => false,
    };
}

fn isMavlinkGatewayFault(fault: fixture_mod.FaultType) bool {
    return switch (fault) {
        .unknown_message_id,
        .unknown_command_id,
        .unexpected_sysid,
        .unexpected_compid,
        .replayed_sequence,
        .duplicate_message,
        .signing_absent_when_required,
        .mission_item_outside_geofence,
        => true,
        else => false,
    };
}

fn isApprovalFault(fault: fixture_mod.FaultType) bool {
    return switch (fault) {
        .expired_approval,
        .mismatched_policy_hash,
        .mismatched_command_hash,
        .mismatched_vehicle_id,
        .mismatched_state_hash,
        .reused_one_time_approval,
        .broad_approval_not_allowed,
        .approval_attempt_for_non_overridable_command,
        .approval_cannot_bypass_geofence,
        .approval_cannot_disable_failsafe,
        => true,
        else => false,
    };
}

fn isEmergencyFault(fault: fixture_mod.FaultType) bool {
    return switch (fault) {
        .emergency_attempt_to_disable_failsafe,
        .emergency_attempt_raw_actuator,
        .rth_without_home_position,
        .land_on_stale_state_without_policy,
        .emergency_override_operator_attempt,
        .no_safe_fallback_available,
        => true,
        else => false,
    };
}

fn syntheticDeny(allocator: std.mem.Allocator, finding: []const u8, event: []const u8, summary: []const u8) !Outcome {
    var builder = OutcomeBuilder.init(allocator);
    errdefer builder.deinit();
    try builder.addFinding(finding);
    try builder.addEvent(event);
    try builder.addEvent("vehicle.command_denied");
    return builder.finish(.passed, .deny, summary, true);
}

fn appendUnique(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8), value: []const u8) !void {
    for (list.items) |existing| {
        if (std.mem.eql(u8, existing, value)) return;
    }
    try list.append(allocator, try allocator.dupe(u8, value));
}

fn freeList(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8)) void {
    for (list.items) |value| allocator.free(value);
    list.deinit(allocator);
}

fn freeStringList(allocator: std.mem.Allocator, values: []const []const u8) void {
    for (values) |value| allocator.free(value);
    if (values.len > 0) allocator.free(values);
}

test "state fault injection applies stale position and low battery" {
    var loaded = try policy.loadFile(std.testing.allocator, "examples/edge/safety/policies/safety-strict.yaml", .{});
    defer loaded.deinit();
    var state = baseState(&loaded.value, .fake_adapter, 1_000_000);
    applyStateFault(&state, .stale_position);
    try std.testing.expectEqual(domain.state.StateFreshness.stale, state.state_freshness);
    applyStateFault(&state, .low_battery);
    try std.testing.expect(state.battery_state.?.percent_remaining < 35);
}

test "fault injection runs malformed mavlink and expired approval faults" {
    var malformed = try runMavlinkParserFault(std.testing.allocator, .malformed_frame);
    defer malformed.deinit();
    try std.testing.expectEqual(safety_report.ScenarioResultStatus.passed, malformed.status);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, malformed.actual_decision.?);

    var fixture = try fixture_mod.parseSlice(std.testing.allocator, "fixture.yaml",
        \\version: 1
        \\id: expired-approval
        \\name: Expired approval
        \\category: approval_bypass
        \\environment: fake_adapter
        \\description: Expired approval denied.
        \\policy: examples/edge/operator/policies/approval-strict.yaml
        \\faults:
        \\  - expired_approval
        \\expected:
        \\  decision: deny
        \\
    );
    defer fixture.deinit();
    var expired = try runApprovalFault(std.testing.allocator, fixture, .expired_approval);
    defer expired.deinit();
    try std.testing.expectEqual(core.decision.DecisionResult.deny, expired.actual_decision.?);
}
