const std = @import("std");

const domain = @import("../domain/mod.zig");
const operator = @import("../operator/mod.zig");
const policy = @import("../policy/mod.zig");
const schema = @import("../schema/mod.zig");
const evaluator = @import("evaluator.zig");
const core = @import("aegis_core");

pub const RunOptions = struct {
    policy_path: []const u8,
    scenario_path: []const u8,
    artifact_dir: ?[]const u8 = null,
    now_ms: i128 = 1_000_500,
};

pub const RunResult = struct {
    allocator: std.mem.Allocator,
    scenario_id: []u8,
    decision: core.decision.DecisionResult,
    artifact_dir: ?[]u8 = null,
    summary: []u8,

    pub fn deinit(self: *RunResult) void {
        self.allocator.free(self.scenario_id);
        if (self.artifact_dir) |dir| self.allocator.free(dir);
        self.allocator.free(self.summary);
        self.* = undefined;
    }
};

const ScenarioCommand = enum {
    arm,
    takeoff,
    upload_mission,
    waypoint_inside,
    waypoint_outside_geofence,
    altitude_above_ceiling,
    velocity_too_high,
    takeoff_low_battery,
    disable_failsafe,
    raw_actuator_output,
    emergency_land,
    return_to_home,
    stale_waypoint,
    mission_outside_geofence,
};

const ScenarioSpec = struct {
    allocator: std.mem.Allocator,
    id: []u8,
    command: ScenarioCommand,
    mode: evaluator.EvaluationMode = .strict,
    approval_seed: operator.ApprovalSeedKind = .none,
    expected_decision: ?core.decision.DecisionResult = null,
    note: []u8,

    fn deinit(self: *ScenarioSpec) void {
        self.allocator.free(self.id);
        self.allocator.free(self.note);
        self.* = undefined;
    }
};

pub fn run(allocator: std.mem.Allocator, options: RunOptions) !RunResult {
    var loaded = try policy.loadFile(allocator, options.policy_path, .{});
    defer loaded.deinit();
    var spec = try loadScenario(allocator, options.scenario_path);
    defer spec.deinit();

    const context: evaluator.EvaluationContext = .{
        .mode = spec.mode,
        .now_ms = options.now_ms,
        .non_interactive = spec.mode == .ci or spec.mode == .redteam,
    };

    var evaluation = try evaluationForScenario(allocator, &loaded.value, spec, context);
    defer evaluation.deinit();

    if (spec.expected_decision) |expected| {
        if (evaluation.decision.result != expected) return error.SafetyScenarioDecisionMismatch;
    }

    const artifact_dir = if (options.artifact_dir) |dir| try allocator.dupe(u8, dir) else try defaultArtifactDir(allocator, spec.id);
    errdefer allocator.free(artifact_dir);
    try writeArtifacts(allocator, artifact_dir, spec, evaluation);

    const summary = try std.fmt.allocPrint(
        allocator,
        "Scenario {s} decision={s} artifacts={s}. Evidence is fake/simulation-only and not real-flight readiness.",
        .{ spec.id, evaluation.decision.result.toString(), artifact_dir },
    );
    return .{
        .allocator = allocator,
        .scenario_id = try allocator.dupe(u8, spec.id),
        .decision = evaluation.decision.result,
        .artifact_dir = artifact_dir,
        .summary = summary,
    };
}

fn evaluationForScenario(
    allocator: std.mem.Allocator,
    selected_policy: *const schema.edge_policy_schema.EdgePolicyV1,
    spec: ScenarioSpec,
    context: evaluator.EvaluationContext,
) !evaluator.SafetyEvaluation {
    const base_state = stateForScenario(selected_policy, spec, context.now_ms - 500);
    if (spec.command == .mission_outside_geofence) {
        const items = [_]domain.mission.Waypoint{
            .{ .sequence = 0, .position = .{ .latitude_deg = 37.0001, .longitude_deg = -122.0000, .altitude_m = 20, .altitude_reference = .amsl } },
            .{ .sequence = 1, .position = .{ .latitude_deg = 37.0100, .longitude_deg = -122.0000, .altitude_m = 20, .altitude_reference = .amsl } },
        };
        return @import("mission_safety.zig").evaluateMissionSafety(allocator, selected_policy, base_state, .{
            .mission_id = .{ .value = "scenario-mission-outside" },
            .waypoints = items[0..],
            .status = .draft,
        }, context);
    }
    const request = requestForScenario(spec);
    if (spec.approval_seed != .none) {
        var base = try evaluator.evaluateSafety(allocator, selected_policy, base_state, request, context);
        defer base.deinit();
        var approval = (try operator.createSeededApprovalDecision(allocator, spec.approval_seed, .{
            .policy = selected_policy,
            .command = request,
            .state = base_state,
            .evaluation = base,
            .now_ms = context.now_ms,
            .actor_id = "aegis-edge-safety-scenario",
        })) orelse return evaluator.evaluateSafety(allocator, selected_policy, base_state, request, context);
        defer approval.deinit(allocator);
        return evaluator.evaluateSafetyWithApproval(allocator, selected_policy, base_state, request, context, &approval);
    }
    return evaluator.evaluateSafety(allocator, selected_policy, base_state, request, context);
}

fn stateForScenario(
    selected_policy: *const schema.edge_policy_schema.EdgePolicyV1,
    spec: ScenarioSpec,
    timestamp_ms: i128,
) domain.state.VehicleState {
    const center = if (selected_policy.safety.geofence) |geofence| switch (geofence.shape) {
        .circle => |circle| circle.center,
        .allowed_polygon => |_| domain.coordinates.GeoPoint{ .latitude_deg = 37, .longitude_deg = -122, .altitude_m = 0, .altitude_reference = .amsl },
    } else domain.coordinates.GeoPoint{ .latitude_deg = 37, .longitude_deg = -122, .altitude_m = 0, .altitude_reference = .amsl };
    const freshness: domain.state.StateFreshness = if (spec.command == .stale_waypoint or spec.command == .emergency_land) .stale else .fresh;
    const battery_percent: f64 = switch (spec.command) {
        .takeoff_low_battery => 20,
        else => 80,
    };
    return .{
        .vehicle_id = .{ .value = "edge-vehicle-1" },
        .vehicle_kind = selected_policy.vehicle.kind,
        .autopilot_kind = selected_policy.vehicle.autopilot,
        .mode = .guided,
        .arm_state = .armed,
        .position = .{ .latitude_deg = center.latitude_deg, .longitude_deg = center.longitude_deg, .altitude_m = 20, .altitude_reference = center.altitude_reference },
        .battery_state = .{ .percent_remaining = battery_percent, .voltage_v = 15.2, .current_a = 2.1, .source = .monotonic },
        .control_authority = .onboard_agent,
        .home_position = center,
        .timestamp = .{ .value = timestamp_ms, .source = .monotonic },
        .state_freshness = freshness,
        .provenance = provenanceForPolicy(selected_policy),
    };
}

fn requestForScenario(spec: ScenarioSpec) domain.commands.CommandRequest {
    const action: domain.commands.CommandAction = switch (spec.command) {
        .arm => .arm,
        .takeoff => .takeoff,
        .upload_mission => .upload_mission,
        .waypoint_inside, .waypoint_outside_geofence, .stale_waypoint => .set_waypoint,
        .altitude_above_ceiling => .set_altitude,
        .velocity_too_high => .set_velocity,
        .takeoff_low_battery => .takeoff,
        .disable_failsafe => .disable_failsafe,
        .raw_actuator_output => .raw_actuator_output,
        .emergency_land => .land,
        .return_to_home => .return_to_home,
        .mission_outside_geofence => .upload_mission,
    };
    const params: domain.commands.CommandParameters = switch (spec.command) {
        .takeoff => .{ .altitude = .{ .altitude_m = 20, .altitude_reference = .amsl } },
        .waypoint_inside, .stale_waypoint => .{ .waypoint = .{ .latitude_deg = 37.0001, .longitude_deg = -122.0000, .altitude_m = 20, .altitude_reference = .amsl } },
        .waypoint_outside_geofence => .{ .waypoint = .{ .latitude_deg = 37.0100, .longitude_deg = -122.0000, .altitude_m = 20, .altitude_reference = .amsl } },
        .altitude_above_ceiling => .{ .altitude = .{ .altitude_m = 121, .altitude_reference = .amsl } },
        .velocity_too_high => .{ .velocity = .{ .vx_mps = 9, .vy_mps = 0, .vz_mps = -3, .frame = .local_ned } },
        .takeoff_low_battery => .{ .altitude = .{ .altitude_m = 20, .altitude_reference = .amsl } },
        else => .none,
    };
    return domain.commands.CommandRequest.init(.{
        .command_id = "safety-scenario-command",
        .vehicle_id = .{ .value = "edge-vehicle-1" },
        .action = action,
        .parameters = params,
        .actor = "aegis-edge-safety-scenario",
        .timestamp = .{ .value = 1_000_100, .source = .monotonic },
        .source = .fake_adapter,
        .mission_id = if (spec.command == .mission_outside_geofence) "scenario-mission-outside" else null,
    });
}

fn provenanceForPolicy(selected_policy: *const schema.edge_policy_schema.EdgePolicyV1) domain.state.StateProvenance {
    if (selected_policy.vehicle.autopilot == .ardupilot) return .fake_ardupilot_adapter;
    return .fake_adapter;
}

fn loadScenario(allocator: std.mem.Allocator, path: []const u8) !ScenarioSpec {
    const text = try std.fs.cwd().readFileAlloc(allocator, path, 32 * 1024);
    defer allocator.free(text);

    var id: ?[]const u8 = null;
    var command: ?ScenarioCommand = null;
    var mode: evaluator.EvaluationMode = .strict;
    var approval_seed: operator.ApprovalSeedKind = .none;
    var expected_decision: ?core.decision.DecisionResult = null;
    var note: []const u8 = "";

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const no_comment = if (std.mem.indexOfScalar(u8, raw_line, '#')) |index| raw_line[0..index] else raw_line;
        const line = std.mem.trim(u8, no_comment, " \t\r");
        if (line.len == 0) continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.InvalidSafetyScenario;
        const key = std.mem.trim(u8, line[0..colon], " \t");
        const value = cleanScalar(line[colon + 1 ..]);
        if (std.mem.eql(u8, key, "id") or std.mem.eql(u8, key, "name")) id = value else if (std.mem.eql(u8, key, "command")) command = std.meta.stringToEnum(ScenarioCommand, value) orelse return error.InvalidSafetyScenario else if (std.mem.eql(u8, key, "mode")) mode = std.meta.stringToEnum(evaluator.EvaluationMode, value) orelse return error.InvalidSafetyScenario else if (std.mem.eql(u8, key, "approval") or std.mem.eql(u8, key, "approval_seed")) approval_seed = try operator.parseApprovalSeedKind(value) else if (isOperatorScenarioMetadataKey(key)) {} else if (std.mem.eql(u8, key, "expected_decision")) expected_decision = std.meta.stringToEnum(core.decision.DecisionResult, value) orelse return error.InvalidSafetyScenario else if (std.mem.eql(u8, key, "note")) note = value else return error.InvalidSafetyScenario;
    }

    return .{
        .allocator = allocator,
        .id = try allocator.dupe(u8, id orelse std.fs.path.stem(path)),
        .command = command orelse return error.InvalidSafetyScenario,
        .mode = mode,
        .approval_seed = approval_seed,
        .expected_decision = expected_decision,
        .note = try allocator.dupe(u8, note),
    };
}

fn isOperatorScenarioMetadataKey(key: []const u8) bool {
    return std.mem.eql(u8, key, "request") or
        std.mem.eql(u8, key, "state") or
        std.mem.eql(u8, key, "approval_scope") or
        std.mem.eql(u8, key, "max_uses") or
        std.mem.eql(u8, key, "environment");
}

fn writeArtifacts(
    allocator: std.mem.Allocator,
    artifact_dir: []const u8,
    spec: ScenarioSpec,
    evaluation: evaluator.SafetyEvaluation,
) !void {
    try std.fs.cwd().makePath(artifact_dir);
    const provenance = if (evaluation.findings.len > 0) evaluation.findings[0].provenance else "fake_adapter";
    const events_path = try std.fs.path.join(allocator, &.{ artifact_dir, "events.jsonl" });
    defer allocator.free(events_path);
    const replay_path = try std.fs.path.join(allocator, &.{ artifact_dir, "replay.json" });
    defer allocator.free(replay_path);

    {
        const file = try std.fs.cwd().createFile(events_path, .{ .truncate = true });
        defer file.close();
        var buffer: [4096]u8 = undefined;
        var writer = file.writer(&buffer);
        for (evaluation.audit_events) |event| {
            try writer.interface.writeByte('{');
            try writer.interface.writeAll("\"scenario_id\":");
            try writeRedactedJsonString(&writer.interface, spec.id);
            try writer.interface.writeAll(",\"environment\":\"fake_safety_simulation\",\"event_type\":");
            try writeRedactedJsonString(&writer.interface, event.event_type);
            try writer.interface.writeAll(",\"decision\":");
            try writeRedactedJsonString(&writer.interface, event.decision.result.toString());
            try writer.interface.writeAll(",\"target\":");
            try writeRedactedJsonString(&writer.interface, event.target_value);
            try writer.interface.writeAll(",\"provenance\":");
            try writeRedactedJsonString(&writer.interface, provenance);
            try writer.interface.writeAll(",\"limitations\":\"simulation evidence only; not real-flight readiness\"}\n");
        }
        try writer.interface.flush();
        try file.sync();
    }

    {
        const file = try std.fs.cwd().createFile(replay_path, .{ .truncate = true });
        defer file.close();
        var buffer: [2048]u8 = undefined;
        var writer = file.writer(&buffer);
        try writer.interface.writeAll("{\"scenario_id\":");
        try writeRedactedJsonString(&writer.interface, spec.id);
        try writer.interface.writeAll(",\"decision\":");
        try writeRedactedJsonString(&writer.interface, evaluation.decision.result.toString());
        try writer.interface.writeAll(",\"findings\":[");
        for (evaluation.findings, 0..) |finding, index| {
            if (index > 0) try writer.interface.writeByte(',');
            try writer.interface.writeByte('{');
            try writer.interface.writeAll("\"category\":");
            try writeRedactedJsonString(&writer.interface, @tagName(finding.category));
            try writer.interface.writeAll(",\"severity\":");
            try writeRedactedJsonString(&writer.interface, @tagName(finding.severity));
            try writer.interface.writeAll(",\"explanation\":");
            try writeRedactedJsonString(&writer.interface, finding.explanation);
            try writer.interface.writeByte('}');
        }
        try writer.interface.writeAll("],\"limitations\":\"simulation evidence only; not real-flight readiness\"}\n");
        try writer.interface.flush();
        try file.sync();
    }
}

fn writeRedactedJsonString(writer: anytype, value: []const u8) !void {
    var buffer: [512]u8 = undefined;
    const redacted = core.api.redactStringBounded(value, &buffer);
    try core.core.util.writeJsonString(writer, redacted);
}

fn cleanScalar(raw: []const u8) []const u8 {
    var value = std.mem.trim(u8, raw, " \t\r");
    if (value.len >= 2) {
        const first = value[0];
        const last = value[value.len - 1];
        if ((first == '"' and last == '"') or (first == '\'' and last == '\'')) value = value[1 .. value.len - 1];
    }
    return value;
}

fn defaultArtifactDir(allocator: std.mem.Allocator, id: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, ".aegis/edge/safety/{s}", .{id});
}
