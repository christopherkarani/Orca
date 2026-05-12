const std = @import("std");

const domain = @import("../domain/mod.zig");
const mavlink = @import("../mavlink/mod.zig");
const operator = @import("../operator/mod.zig");
const policy = @import("../policy/mod.zig");
const safety = @import("../safety/mod.zig");
const connection = @import("connection.zig");
const fake_adapter = @import("fake_adapter.zig");
const px4_audit = @import("audit.zig");
const sitl_adapter = @import("sitl_adapter.zig");

pub const RunOptions = struct {
    policy_path: []const u8,
    scenario_path: []const u8,
    artifact_dir: ?[]const u8 = null,
    now_ms: i128 = 1_000_500,
    gate: ?connection.IntegrationGate = null,
};

pub const RunResult = struct {
    allocator: std.mem.Allocator,
    scenario_id: []u8,
    environment: connection.Environment,
    skipped: bool = false,
    decision: ?@import("aegis_core").decision.DecisionResult = null,
    forwarded: bool = false,
    blocked: bool = false,
    artifact_dir: ?[]u8 = null,
    summary: []u8,

    pub fn deinit(self: *RunResult) void {
        self.allocator.free(self.scenario_id);
        if (self.artifact_dir) |dir| self.allocator.free(dir);
        self.allocator.free(self.summary);
        self.* = undefined;
    }
};

const ScenarioSpec = struct {
    allocator: std.mem.Allocator,
    id: []u8,
    environment: connection.Environment = .fake_px4,
    mode: connection.Mode = .enforce,
    command: fake_adapter.CommandAction = .unknown,
    lat_int: i32 = 370000000,
    lon_int: i32 = -1220000000,
    alt_m: f32 = 20,
    battery_percent: f64 = 80,
    state_freshness: domain.state.StateFreshness = .fresh,
    approval_seed: operator.ApprovalSeedKind = .none,
    expected_decision: ?@import("aegis_core").decision.DecisionResult = null,
    expected_forwarded: ?bool = null,
    requires_px4_sitl: bool = false,
    timeout_ms: u64 = 2_000,
    note: []u8,

    fn deinit(self: *ScenarioSpec) void {
        self.allocator.free(self.id);
        self.allocator.free(self.note);
        self.* = undefined;
    }
};

pub fn run(allocator: std.mem.Allocator, options: RunOptions) !RunResult {
    var spec = try loadScenario(allocator, options.scenario_path);
    defer spec.deinit();

    const gate = options.gate orelse connection.integrationTestGate(.{ .run_px4_sitl_tests = null, .endpoint = null });
    if (spec.requires_px4_sitl and spec.environment != .px4_sitl) return error.Px4ScenarioRequiresSitlEnvironment;
    if ((spec.environment == .px4_sitl or spec.requires_px4_sitl) and (gate.availability != .configured or !gate.enabled)) {
        const summary = try std.fmt.allocPrint(allocator, "Scenario {s} skipped: PX4 SITL unavailable ({s}). No fake pass was recorded.", .{ spec.id, gate.reason });
        return .{
            .allocator = allocator,
            .scenario_id = try allocator.dupe(u8, spec.id),
            .environment = .px4_sitl,
            .skipped = true,
            .summary = summary,
        };
    }
    if (spec.environment == .px4_sitl) return error.Px4SitlLiveTransportUnavailable;

    var loaded = try policy.loadFile(allocator, options.policy_path, .{});
    defer loaded.deinit();

    var fake = fake_adapter.FakePx4Adapter.init(allocator, .{ .sysid = 42, .compid = 191 });
    defer fake.deinit();
    const frame_bytes = try frameForScenario(&fake, spec);
    defer allocator.free(frame_bytes);
    const frame = try mavlink.framing.parseFrame(frame_bytes);

    const state = stateForScenario(spec, options.now_ms - 500);

    var approval_decision = try approvalForFrame(allocator, &loaded.value, state, frame, spec, options.now_ms);
    defer if (approval_decision) |*approval| approval.deinit(allocator);
    const approval_ptr: ?*operator.ApprovalDecision = if (approval_decision) |*approval| approval else null;
    const process_options: mavlink.gateway.ProcessOptions = .{
        .mode = sitl_adapter.gatewayMode(spec.mode),
        .direction = .companion_to_vehicle,
        .vehicle_id = "edge-vehicle-1",
        .now_ms = options.now_ms,
        .command_source = sitl_adapter.provenanceFor(spec.environment),
        .approval_decision = approval_ptr,
    };

    var result = if (spec.command == .start_mission) blk: {
        var tracker = mavlink.mission.MissionTracker.init();
        const count = try mavlink.fake_transport.frameMissionCountV2(allocator, .{ .seq = 1, .sysid = 42, .compid = 191 }, 1);
        defer allocator.free(count);
        try tracker.observe(try mavlink.messages.decode(try mavlink.framing.parseFrame(count)));
        break :blk try mavlink.gateway.processMissionFrame(allocator, process_options, &loaded.value, state, frame, &tracker);
    } else try mavlink.gateway.processFrame(allocator, process_options, &loaded.value, state, frame);
    defer result.deinit();

    if (spec.expected_decision) |expected| {
        const actual = result.decision orelse return error.MissingScenarioDecision;
        if (actual != expected) return error.Px4ScenarioDecisionMismatch;
    }
    if (spec.expected_forwarded) |expected| {
        if (result.forwarded != expected) return error.Px4ScenarioForwardingMismatch;
    }

    const artifact_dir = if (options.artifact_dir) |dir| try allocator.dupe(u8, dir) else try defaultArtifactDir(allocator, spec.id);
    errdefer allocator.free(artifact_dir);
    const endpoint = "127.0.0.1:14540";
    try px4_audit.writeArtifacts(allocator, artifact_dir, .{
        .scenario_id = spec.id,
        .environment = spec.environment,
        .tested_version = "documented-by-phase-29",
        .endpoint = endpoint,
    }, result, spec.note);

    const summary = try std.fmt.allocPrint(
        allocator,
        "Scenario {s} environment={s} decision={s} forwarded={} blocked={} artifacts={s}. Evidence is simulation-only and not real-flight readiness.",
        .{ spec.id, spec.environment.toString(), if (result.decision) |decision| decision.toString() else "none", result.forwarded, result.blocked, artifact_dir },
    );
    return .{
        .allocator = allocator,
        .scenario_id = try allocator.dupe(u8, spec.id),
        .environment = spec.environment,
        .decision = result.decision,
        .forwarded = result.forwarded,
        .blocked = result.blocked,
        .artifact_dir = artifact_dir,
        .summary = summary,
    };
}

fn frameForScenario(fake: *fake_adapter.FakePx4Adapter, spec: ScenarioSpec) ![]u8 {
    if (spec.command == .start_mission) return fake.missionWaypointFrame(spec.lat_int, spec.lon_int, spec.alt_m);
    return fake.commandFrame(.{
        .action = spec.command,
        .lat_int = spec.lat_int,
        .lon_int = spec.lon_int,
        .alt_m = spec.alt_m,
    });
}

fn stateForScenario(spec: ScenarioSpec, timestamp_ms: i128) domain.state.VehicleState {
    return .{
        .vehicle_id = .{ .value = "edge-vehicle-1" },
        .vehicle_kind = .drone_multirotor,
        .autopilot_kind = .px4,
        .mode = .guided,
        .arm_state = .armed,
        .position = .{ .latitude_deg = 37.0000, .longitude_deg = -122.0000, .altitude_m = 20, .altitude_reference = .amsl },
        .battery_state = .{ .percent_remaining = spec.battery_percent, .voltage_v = 15.2, .current_a = 2.1, .source = .monotonic },
        .control_authority = .onboard_agent,
        .home_position = .{ .latitude_deg = 37.0000, .longitude_deg = -122.0000, .altitude_m = 0, .altitude_reference = .amsl },
        .timestamp = .{ .value = timestamp_ms, .source = .monotonic },
        .state_freshness = spec.state_freshness,
        .provenance = sitl_adapter.provenanceFor(spec.environment),
    };
}

fn defaultArtifactDir(allocator: std.mem.Allocator, id: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, ".aegis/edge/px4/{s}", .{id});
}

fn loadScenario(allocator: std.mem.Allocator, path: []const u8) !ScenarioSpec {
    const text = try std.fs.cwd().readFileAlloc(allocator, path, 32 * 1024);
    defer allocator.free(text);

    var id: ?[]const u8 = null;
    var environment: connection.Environment = .fake_px4;
    var mode: connection.Mode = .enforce;
    var command: fake_adapter.CommandAction = .unknown;
    var lat_int: i32 = 370000000;
    var lon_int: i32 = -1220000000;
    var alt_m: f32 = 20;
    var battery_percent: f64 = 80;
    var freshness: domain.state.StateFreshness = .fresh;
    var approval_seed: operator.ApprovalSeedKind = .none;
    var expected_decision: ?@import("aegis_core").decision.DecisionResult = null;
    var expected_forwarded: ?bool = null;
    var requires_px4_sitl = false;
    var timeout_ms: u64 = 2_000;
    var note: []const u8 = "";

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const no_comment = if (std.mem.indexOfScalar(u8, raw_line, '#')) |index| raw_line[0..index] else raw_line;
        const line = std.mem.trim(u8, no_comment, " \t\r");
        if (line.len == 0) continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.InvalidPx4Scenario;
        const key = std.mem.trim(u8, line[0..colon], " \t");
        const value = cleanScalar(line[colon + 1 ..]);
        if (std.mem.eql(u8, key, "id") or std.mem.eql(u8, key, "name")) id = value else if (std.mem.eql(u8, key, "environment")) environment = try connection.Environment.parse(value) else if (std.mem.eql(u8, key, "mode")) mode = try connection.Mode.parse(value) else if (std.mem.eql(u8, key, "command")) command = try fake_adapter.actionFromName(value) else if (std.mem.eql(u8, key, "lat_int")) lat_int = try std.fmt.parseInt(i32, value, 10) else if (std.mem.eql(u8, key, "lon_int")) lon_int = try std.fmt.parseInt(i32, value, 10) else if (std.mem.eql(u8, key, "alt_m")) alt_m = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "battery_percent")) battery_percent = try std.fmt.parseFloat(f64, value) else if (std.mem.eql(u8, key, "state_freshness")) freshness = std.meta.stringToEnum(domain.state.StateFreshness, value) orelse return error.InvalidPx4Scenario else if (std.mem.eql(u8, key, "approval") or std.mem.eql(u8, key, "approval_seed")) approval_seed = try operator.parseApprovalSeedKind(value) else if (std.mem.eql(u8, key, "approval_scope")) {} else if (std.mem.eql(u8, key, "expected_decision")) expected_decision = std.meta.stringToEnum(@import("aegis_core").decision.DecisionResult, value) orelse return error.InvalidPx4Scenario else if (std.mem.eql(u8, key, "expected_forwarded")) expected_forwarded = try parseBool(value) else if (std.mem.eql(u8, key, "requires_px4_sitl")) requires_px4_sitl = try parseBool(value) else if (std.mem.eql(u8, key, "timeout_ms")) timeout_ms = try std.fmt.parseInt(u64, value, 10) else if (std.mem.eql(u8, key, "note")) note = value else return error.InvalidPx4Scenario;
    }

    return .{
        .allocator = allocator,
        .id = try allocator.dupe(u8, id orelse std.fs.path.stem(path)),
        .environment = environment,
        .mode = mode,
        .command = command,
        .lat_int = lat_int,
        .lon_int = lon_int,
        .alt_m = alt_m,
        .battery_percent = battery_percent,
        .state_freshness = freshness,
        .approval_seed = approval_seed,
        .expected_decision = expected_decision,
        .expected_forwarded = expected_forwarded,
        .requires_px4_sitl = requires_px4_sitl,
        .timeout_ms = timeout_ms,
        .note = try allocator.dupe(u8, note),
    };
}

fn approvalForFrame(
    allocator: std.mem.Allocator,
    selected_policy: *const @import("../schema/mod.zig").edge_policy_schema.EdgePolicyV1,
    state: domain.state.VehicleState,
    frame: mavlink.framing.Frame,
    spec: ScenarioSpec,
    now_ms: i128,
) !?operator.ApprovalDecision {
    if (spec.approval_seed == .none) return null;
    var mapped = try mavlink.mapping.mapFrameToCommand(allocator, frame, .{
        .vehicle_id = "edge-vehicle-1",
        .now_ms = now_ms,
        .source = sitl_adapter.provenanceFor(spec.environment),
    });
    defer mapped.deinit();
    const request = mapped.request orelse return null;
    var base = try safety.evaluateSafety(allocator, selected_policy, state, request, .{
        .mode = evaluationMode(spec.mode),
        .now_ms = now_ms,
        .non_interactive = spec.mode == .ci or spec.mode == .redteam,
    });
    defer base.deinit();
    return operator.createSeededApprovalDecision(allocator, spec.approval_seed, .{
        .policy = selected_policy,
        .command = request,
        .state = state,
        .evaluation = base,
        .now_ms = now_ms,
        .actor_id = "aegis-edge-px4-scenario",
    });
}

fn evaluationMode(mode: connection.Mode) policy.EvaluationMode {
    return switch (mode) {
        .observe => .observe,
        .enforce => .ask,
        .simulation => .simulation,
        .ci => .ci,
        .redteam => .redteam,
        .bench => .bench,
    };
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

fn parseBool(value: []const u8) !bool {
    if (std.mem.eql(u8, value, "true")) return true;
    if (std.mem.eql(u8, value, "false")) return false;
    return error.InvalidBool;
}
