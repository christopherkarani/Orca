const std = @import("std");
const edge = @import("aegis_edge");
const schema_documents = @import("edge_schema_documents");

const usage =
    \\Aegis Edge policy evaluation
    \\
    \\Usage:
    \\  aegis-edge <command> [args]
    \\
    \\Commands:
    \\  doctor                         Show domain/schema capability status
    \\  ardupilot doctor               Show ArduPilot SITL simulation capability status
    \\  ardupilot scenario run --policy <policy> --scenario <scenario>
    \\                                 Run a deterministic fake-ArduPilot or opt-in SITL scenario
    \\  ardupilot observe --duration <seconds>
    \\                                 Observe deterministic fake-ArduPilot state unless SITL is explicitly enabled
    \\  ardupilot gateway --policy <policy> --endpoint <endpoint> --mode observe|enforce|simulation
    \\                                 Configure ArduPilot SITL mediation parameters without hardware assumptions
    \\  ardupilot test-fixture --name <fixture>
    \\                                 Print deterministic fake-ArduPilot fixture metadata
    \\  px4 doctor                     Show PX4 SITL simulation capability status
    \\  px4 scenario run --policy <policy> --scenario <scenario>
    \\                                 Run a deterministic fake-PX4 or opt-in SITL scenario
    \\  px4 observe --duration <seconds>
    \\                                 Observe deterministic fake-PX4 state unless SITL is explicitly enabled
    \\  px4 gateway --policy <policy> --endpoint <endpoint> --mode observe|enforce|simulation
    \\                                 Configure PX4 SITL mediation parameters without hardware assumptions
    \\  px4 test-fixture --name <fixture>
    \\                                 Print deterministic fake-PX4 fixture metadata
    \\  mavlink doctor                 Show MAVLink gateway capabilities and limitations
    \\  mavlink inspect-frame <file-or-hex>
    \\                                 Parse one MAVLink frame and print bounded metadata
    \\  mavlink classify <file-or-hex>  Classify and map one MAVLink frame where supported
    \\  mavlink simulate --policy <policy> --scenario <scenario>
    \\                                 Run a deterministic fake-transport scenario
    \\  mavlink gateway --fake --policy <policy>
    \\                                 Configure fake/in-memory gateway mode only
    \\  policy check <policy>          Validate an Edge policy file
    \\  policy explain <policy> <cmd>   Explain one command decision with fake state
    \\  policy evaluate <policy> --request <request.json> --state <state.json>
    \\                                 Evaluate a command request without sending it
    \\  schema list                    List versioned Edge schemas
    \\  schema print <schema-id>       Print a built-in schema document
    \\  help                           Show this help
    \\
    \\MAVLink fake transport is deterministic by default. PX4 and ArduPilot SITL are opt-in local simulation only. No real hardware, ROS2, or real-flight endpoint is opened by default.
    \\
;

const edge_policy_schema_document = schema_documents.edge_policy_v1;
const edge_event_schema_document = schema_documents.edge_event_v1;
const safety_report_schema_document = schema_documents.safety_report_v1;

pub fn main() !void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    var stdout_buffer: [4096]u8 = undefined;
    var stderr_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);

    const code = try run(argv[1..], &stdout_writer.interface, &stderr_writer.interface);
    try stdout_writer.interface.flush();
    try stderr_writer.interface.flush();
    std.process.exit(code);
}

pub fn run(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0) {
        try stdout.writeAll(usage);
        return 0;
    }

    const command = argv[0];
    if (std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h") or std.mem.eql(u8, command, "help")) {
        try stdout.writeAll(usage);
        return 0;
    }
    if (std.mem.eql(u8, command, "doctor")) {
        if (argv.len != 1) {
            try stderr.writeAll("aegis-edge doctor: expected no arguments.\n");
            return 64;
        }
        try edge.doctor(stdout);
        return 0;
    }
    if (std.mem.eql(u8, command, "schema")) {
        return runSchema(argv[1..], stdout, stderr);
    }
    if (std.mem.eql(u8, command, "ardupilot")) {
        return runArduPilot(argv[1..], stdout, stderr);
    }
    if (std.mem.eql(u8, command, "px4")) {
        return runPx4(argv[1..], stdout, stderr);
    }
    if (std.mem.eql(u8, command, "mavlink")) {
        return runMavlink(argv[1..], stdout, stderr);
    }
    if (std.mem.eql(u8, command, "policy")) {
        return runPolicy(argv[1..], stdout, stderr);
    }

    try stderr.print("aegis-edge: unknown command '{s}'. Run 'aegis-edge --help' for usage.\n", .{command});
    return 64;
}

fn runPx4(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0) {
        try stderr.writeAll("aegis-edge px4: expected doctor, scenario, observe, gateway, or test-fixture.\n");
        return 64;
    }
    if (std.mem.eql(u8, argv[0], "doctor")) return runPx4Doctor(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "scenario")) return runPx4Scenario(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "observe")) return runPx4Observe(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "gateway")) return runPx4Gateway(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "test-fixture")) return runPx4TestFixture(argv[1..], stdout, stderr);
    try stderr.print("aegis-edge px4: unknown subcommand '{s}'.\n", .{argv[0]});
    return 64;
}

fn runPx4Doctor(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len != 0) return usageError(stderr, "aegis-edge px4 doctor: expected no arguments.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var gate = try edge.px4.connection.integrationTestGateFromEnv(allocator);
    defer gate.deinit(allocator);
    var config = edge.px4.connection.defaultConfig();
    const version = try edge.px4.connection.testedVersionFromEnv(allocator);
    defer allocator.free(version);
    config.tested_version = version;
    if (gate.endpoint) |endpoint| config.endpoint = endpoint;
    try edge.px4.health.writeDoctor(stdout, .{ .config = config, .gate = gate });
    return 0;
}

fn runPx4Scenario(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0 or !std.mem.eql(u8, argv[0], "run")) return usageError(stderr, "aegis-edge px4 scenario: expected run --policy <policy> --scenario <scenario>.\n");
    var policy_path: ?[]const u8 = null;
    var scenario_path: ?[]const u8 = null;
    var artifact_dir: ?[]const u8 = null;
    var index: usize = 1;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--policy")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge px4 scenario run: --policy requires a file.\n");
            policy_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--scenario")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge px4 scenario run: --scenario requires a file.\n");
            scenario_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--artifacts")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge px4 scenario run: --artifacts requires a directory.\n");
            artifact_dir = argv[index];
        } else {
            try stderr.print("aegis-edge px4 scenario run: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected_policy = policy_path orelse return usageError(stderr, "aegis-edge px4 scenario run: missing --policy.\n");
    const selected_scenario = scenario_path orelse return usageError(stderr, "aegis-edge px4 scenario run: missing --scenario.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var gate = try edge.px4.connection.integrationTestGateFromEnv(allocator);
    defer gate.deinit(allocator);
    var result = edge.px4.scenario.run(allocator, .{
        .policy_path = selected_policy,
        .scenario_path = selected_scenario,
        .artifact_dir = artifact_dir,
        .gate = gate,
    }) catch |err| {
        try stderr.print("PX4 scenario failed: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer result.deinit();
    try stdout.print("{s}\n", .{result.summary});
    if (result.skipped) {
        try stdout.writeAll("Skipped result is not a fake-PX4 pass and not PX4 SITL success.\n");
    } else {
        try stdout.print("Environment: {s}\nDecision: {s}\nForwarded: {}\nBlocked: {}\n", .{ result.environment.toString(), if (result.decision) |decision| decision.toString() else "none", result.forwarded, result.blocked });
        if (result.artifact_dir) |dir| try stdout.print("Artifacts: {s}\n", .{dir});
    }
    try stdout.writeAll("Limitations: simulation evidence only; not ready for real flight; no hardware integration; PX4 evidence is distinct from ArduPilot evidence.\n");
    return 0;
}

fn runPx4Observe(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var duration: u64 = 5;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--duration")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge px4 observe: --duration requires seconds.\n");
            duration = std.fmt.parseInt(u64, argv[index], 10) catch return usageError(stderr, "aegis-edge px4 observe: invalid --duration.\n");
        } else {
            try stderr.print("aegis-edge px4 observe: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var fake = edge.px4.fake_adapter.FakePx4Adapter.init(allocator, .{});
    defer fake.deinit();
    var mapper = edge.px4.telemetry_mapping.StateMapper.init(.{ .vehicle_id = "edge-vehicle-1", .provenance = .fake_adapter, .now_ms = 1_000_000 });
    const heartbeat = try fake.heartbeatFrame(.{ .armed = true, .base_mode = 0x08 });
    defer allocator.free(heartbeat);
    try mapper.observeFrame(try edge.mavlink.framing.parseFrame(heartbeat));
    const state = mapper.state();
    try stdout.print("PX4 observe environment: fake_px4\nDuration requested: {d}s\nVehicle: {s}\nMode: {s}\nArm state: {s}\nProvenance: {s}\n", .{ duration, state.vehicle_id.value, @tagName(state.mode), @tagName(state.arm_state), @tagName(state.provenance) });
    try stdout.writeAll("No PX4 SITL endpoint or hardware was opened. Use opt-in PX4 SITL tests for local simulator evidence.\n");
    return 0;
}

fn runPx4Gateway(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var policy_path: ?[]const u8 = null;
    var endpoint_text: []const u8 = "127.0.0.1:14540";
    var mode: edge.px4.connection.Mode = .observe;
    var protocol: edge.px4.connection.Protocol = .udp;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--policy")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge px4 gateway: --policy requires a file.\n");
            policy_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--endpoint")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge px4 gateway: --endpoint requires host:port.\n");
            endpoint_text = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--mode")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge px4 gateway: --mode requires observe|enforce|simulation.\n");
            mode = edge.px4.connection.Mode.parse(argv[index]) catch return usageError(stderr, "aegis-edge px4 gateway: invalid --mode.\n");
        } else if (std.mem.eql(u8, argv[index], "--protocol")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge px4 gateway: --protocol requires udp|tcp.\n");
            protocol = edge.px4.connection.Protocol.parse(argv[index]) catch return usageError(stderr, "aegis-edge px4 gateway: invalid --protocol.\n");
        } else {
            try stderr.print("aegis-edge px4 gateway: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected_policy = policy_path orelse return usageError(stderr, "aegis-edge px4 gateway: missing --policy.\n");
    const endpoint = edge.px4.connection.Endpoint.parse(endpoint_text) catch return usageError(stderr, "aegis-edge px4 gateway: invalid endpoint.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    var loaded = edge.policy.loadFile(gpa_state.allocator(), selected_policy, .{}) catch |err| {
        try stderr.print("Edge policy invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer loaded.deinit();
    try stdout.print("PX4 SITL gateway configured: endpoint={s}:{d} protocol={s} mode={s}\n", .{ endpoint.host, endpoint.port, protocol.toString(), mode.toString() });
    try stdout.print("Policy: {s}\n", .{selected_policy});
    try stdout.writeAll("Live PX4 SITL transport is opt-in local simulation only; this command does not assume hardware or real flight.\n");
    try stdout.writeAll("Mapped commands are mediated through the Phase 28 MAVLink gateway and Phase 27 Edge policy engine.\n");
    return 0;
}

fn runPx4TestFixture(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var name: ?[]const u8 = null;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--name")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge px4 test-fixture: --name requires a fixture name.\n");
            name = argv[index];
        } else {
            try stderr.print("aegis-edge px4 test-fixture: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected = name orelse return usageError(stderr, "aegis-edge px4 test-fixture: missing --name.\n");
    try stdout.print("PX4 fake fixture: {s}\n", .{selected});
    try stdout.writeAll("Environment: fake_px4\nProvenance: fake_adapter\nSupported names: heartbeat, position, battery, land, disable_failsafe, waypoint_outside_geofence\n");
    try stdout.writeAll("Fixtures are deterministic fake-PX4 records and are not PX4 SITL success evidence.\n");
    return 0;
}

fn runArduPilot(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0) {
        try stderr.writeAll("aegis-edge ardupilot: expected doctor, scenario, observe, gateway, or test-fixture.\n");
        return 64;
    }
    if (std.mem.eql(u8, argv[0], "doctor")) return runArduPilotDoctor(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "scenario")) return runArduPilotScenario(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "observe")) return runArduPilotObserve(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "gateway")) return runArduPilotGateway(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "test-fixture")) return runArduPilotTestFixture(argv[1..], stdout, stderr);
    try stderr.print("aegis-edge ardupilot: unknown subcommand '{s}'.\n", .{argv[0]});
    return 64;
}

fn runArduPilotDoctor(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len != 0) return usageError(stderr, "aegis-edge ardupilot doctor: expected no arguments.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var gate = try edge.ardupilot.connection.integrationTestGateFromEnv(allocator);
    defer gate.deinit(allocator);
    var config = edge.ardupilot.connection.defaultConfig();
    const version = try edge.ardupilot.connection.testedVersionFromEnv(allocator);
    defer allocator.free(version);
    config.tested_version = version;
    config.vehicle = gate.vehicle;
    if (gate.endpoint) |endpoint| config.endpoint = endpoint;
    try edge.ardupilot.health.writeDoctor(stdout, .{ .config = config, .gate = gate });
    return 0;
}

fn runArduPilotScenario(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0 or !std.mem.eql(u8, argv[0], "run")) return usageError(stderr, "aegis-edge ardupilot scenario: expected run --policy <policy> --scenario <scenario>.\n");
    var policy_path: ?[]const u8 = null;
    var scenario_path: ?[]const u8 = null;
    var artifact_dir: ?[]const u8 = null;
    var index: usize = 1;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--policy")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge ardupilot scenario run: --policy requires a file.\n");
            policy_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--scenario")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge ardupilot scenario run: --scenario requires a file.\n");
            scenario_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--artifacts")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge ardupilot scenario run: --artifacts requires a directory.\n");
            artifact_dir = argv[index];
        } else {
            try stderr.print("aegis-edge ardupilot scenario run: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected_policy = policy_path orelse return usageError(stderr, "aegis-edge ardupilot scenario run: missing --policy.\n");
    const selected_scenario = scenario_path orelse return usageError(stderr, "aegis-edge ardupilot scenario run: missing --scenario.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var gate = try edge.ardupilot.connection.integrationTestGateFromEnv(allocator);
    defer gate.deinit(allocator);
    var result = edge.ardupilot.scenario.run(allocator, .{
        .policy_path = selected_policy,
        .scenario_path = selected_scenario,
        .artifact_dir = artifact_dir,
        .gate = gate,
    }) catch |err| {
        try stderr.print("ArduPilot scenario failed: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer result.deinit();
    try stdout.print("{s}\n", .{result.summary});
    if (result.skipped) {
        try stdout.writeAll("Skipped result is not a fake-ArduPilot pass and not ArduPilot SITL success.\n");
    } else {
        try stdout.print("Environment: {s}\nVehicle: {s}\nDecision: {s}\nForwarded: {}\nBlocked: {}\n", .{ result.environment.toString(), result.vehicle.toString(), if (result.decision) |decision| decision.toString() else "none", result.forwarded, result.blocked });
        if (result.artifact_dir) |dir| try stdout.print("Artifacts: {s}\n", .{dir});
    }
    try stdout.writeAll("Limitations: simulation evidence only; not ready for real flight; no hardware integration; ArduPilot behavior is not identical to PX4 behavior.\n");
    return 0;
}

fn runArduPilotObserve(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var duration: u64 = 5;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--duration")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge ardupilot observe: --duration requires seconds.\n");
            duration = std.fmt.parseInt(u64, argv[index], 10) catch return usageError(stderr, "aegis-edge ardupilot observe: invalid --duration.\n");
        } else {
            try stderr.print("aegis-edge ardupilot observe: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var fake = edge.ardupilot.fake_adapter.FakeArduPilotAdapter.init(allocator, .{ .vehicle = .copter });
    defer fake.deinit();
    var mapper = edge.ardupilot.telemetry_mapping.StateMapper.init(.{
        .vehicle_id = "edge-vehicle-1",
        .vehicle = .copter,
        .provenance = .fake_ardupilot_adapter,
        .now_ms = 1_000_000,
    });
    const heartbeat = try fake.heartbeatFrame(.{ .armed = true, .custom_mode = edge.ardupilot.telemetry_mapping.copter_mode_guided });
    defer allocator.free(heartbeat);
    try mapper.observeFrame(try edge.mavlink.framing.parseFrame(heartbeat));
    const state = mapper.state();
    try stdout.print("ArduPilot observe environment: fake_ardupilot\nDuration requested: {d}s\nVehicle: {s}\nMode: {s}\nArm state: {s}\nProvenance: {s}\n", .{ duration, state.vehicle_id.value, @tagName(state.mode), @tagName(state.arm_state), @tagName(state.provenance) });
    try stdout.writeAll("No ArduPilot SITL endpoint or hardware was opened. Use opt-in ArduPilot SITL tests for local simulator evidence.\n");
    return 0;
}

fn runArduPilotGateway(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var policy_path: ?[]const u8 = null;
    var endpoint_text: []const u8 = "127.0.0.1:14550";
    var mode: edge.ardupilot.connection.Mode = .observe;
    var protocol: edge.ardupilot.connection.Protocol = .udp;
    var vehicle: edge.ardupilot.vehicle_kind.VehicleKind = .copter;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--policy")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge ardupilot gateway: --policy requires a file.\n");
            policy_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--endpoint")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge ardupilot gateway: --endpoint requires host:port.\n");
            endpoint_text = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--mode")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge ardupilot gateway: --mode requires observe|enforce|simulation.\n");
            mode = edge.ardupilot.connection.Mode.parse(argv[index]) catch return usageError(stderr, "aegis-edge ardupilot gateway: invalid --mode.\n");
        } else if (std.mem.eql(u8, argv[index], "--protocol")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge ardupilot gateway: --protocol requires udp|tcp.\n");
            protocol = edge.ardupilot.connection.Protocol.parse(argv[index]) catch return usageError(stderr, "aegis-edge ardupilot gateway: invalid --protocol.\n");
        } else if (std.mem.eql(u8, argv[index], "--vehicle")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge ardupilot gateway: --vehicle requires copter|plane|rover|sub|unknown.\n");
            vehicle = edge.ardupilot.vehicle_kind.VehicleKind.parse(argv[index]) catch return usageError(stderr, "aegis-edge ardupilot gateway: invalid --vehicle.\n");
        } else {
            try stderr.print("aegis-edge ardupilot gateway: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected_policy = policy_path orelse return usageError(stderr, "aegis-edge ardupilot gateway: missing --policy.\n");
    const endpoint = edge.ardupilot.connection.Endpoint.parse(endpoint_text) catch return usageError(stderr, "aegis-edge ardupilot gateway: invalid endpoint.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    var loaded = edge.policy.loadFile(gpa_state.allocator(), selected_policy, .{}) catch |err| {
        try stderr.print("Edge policy invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer loaded.deinit();
    try stdout.print("ArduPilot SITL gateway configured: endpoint={s}:{d} protocol={s} mode={s} vehicle={s}\n", .{ endpoint.host, endpoint.port, protocol.toString(), mode.toString(), vehicle.toString() });
    try stdout.print("Policy: {s}\n", .{selected_policy});
    try stdout.writeAll("Live ArduPilot SITL transport is opt-in local simulation only; this command does not assume hardware or real flight.\n");
    try stdout.writeAll("Mapped commands are mediated through the Phase 28 MAVLink gateway and Phase 27 Edge policy engine.\n");
    return 0;
}

fn runArduPilotTestFixture(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var name: ?[]const u8 = null;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--name")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge ardupilot test-fixture: --name requires a fixture name.\n");
            name = argv[index];
        } else {
            try stderr.print("aegis-edge ardupilot test-fixture: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected = name orelse return usageError(stderr, "aegis-edge ardupilot test-fixture: missing --name.\n");
    try stdout.print("ArduPilot fake fixture: {s}\n", .{selected});
    try stdout.writeAll("Environment: fake_ardupilot\nProvenance: fake_ardupilot_adapter\nSupported names: heartbeat, position, battery, land, rtl, disable_failsafe, waypoint_outside_geofence\n");
    try stdout.writeAll("Fixtures are deterministic fake-ArduPilot records and are not ArduPilot SITL success evidence.\n");
    return 0;
}

fn runMavlink(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0) {
        try stderr.writeAll("aegis-edge mavlink: expected doctor, inspect-frame, classify, simulate, or gateway.\n");
        return 64;
    }
    if (std.mem.eql(u8, argv[0], "doctor")) return runMavlinkDoctor(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "inspect-frame")) return runMavlinkInspect(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "classify")) return runMavlinkClassify(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "simulate")) return runMavlinkSimulate(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "gateway")) return runMavlinkGateway(argv[1..], stdout, stderr);
    try stderr.print("aegis-edge mavlink: unknown subcommand '{s}'.\n", .{argv[0]});
    return 64;
}

fn runMavlinkDoctor(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len != 0) return usageError(stderr, "aegis-edge mavlink doctor: expected no arguments.\n");
    try stdout.writeAll("MAVLink gateway foundation: active for fake_transport simulation/protocol mediation only.\n");
    try stdout.writeAll("Supported parsing: MAVLink v1 and v2 frames, bounded payloads, partial streams, known-message CRC validation, MAVLink2 signing detection.\n");
    try stdout.writeAll("Supported mediation subset: heartbeat/state, COMMAND_LONG, COMMAND_INT, SET_MODE, PARAM_SET safety toggles, setpoint targets, and generic mission upload messages.\n");
    try stdout.writeAll("Unsupported in this generic MAVLink subcommand: serial hardware endpoints, ROS2, real hardware flight, signing key management, and signing verification. Use aegis-edge px4 or aegis-edge ardupilot for opt-in SITL simulation evidence.\n");
    try stdout.writeAll("Recommendation for real deployments: use MAVLink2 signing at the deployment boundary; Aegis Edge Phase 28 only detects signing presence.\n");
    return 0;
}

fn runMavlinkInspect(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len != 1) return usageError(stderr, "aegis-edge mavlink inspect-frame: expected exactly one file path or hex string.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    const bytes = readFileOrHex(allocator, argv[0]) catch |err| {
        try stderr.print("MAVLink frame input invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer allocator.free(bytes);
    const frame = edge.mavlink.framing.parseFrame(bytes) catch |err| {
        try stderr.print("MAVLink frame invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    try stdout.print("MAVLink frame: version={s} msgid={d} name={s} seq={d} sysid={d} compid={d} payload_len={d}\n", .{
        @tagName(frame.version),
        frame.msgid,
        edge.mavlink.dialect.nameFor(frame.msgid),
        frame.sequence,
        frame.sysid,
        frame.compid,
        frame.payload.len,
    });
    try stdout.print("CRC: {s}\n", .{if (frame.checksum_valid == true) "valid" else if (frame.checksum_valid == false) "invalid" else "not-validated-for-unknown-message"});
    try stdout.print("MAVLink2 signing: {s}\n", .{if (frame.signature_present) "present-detection-only" else "absent"});
    try stdout.writeAll("Payload logging is bounded; raw payload bytes are not dumped unbounded.\n");
    return 0;
}

fn runMavlinkClassify(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len != 1) return usageError(stderr, "aegis-edge mavlink classify: expected exactly one file path or hex string.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    const bytes = readFileOrHex(allocator, argv[0]) catch |err| {
        try stderr.print("MAVLink frame input invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer allocator.free(bytes);
    const frame = edge.mavlink.framing.parseFrame(bytes) catch |err| {
        try stderr.print("MAVLink frame invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    const classification = edge.mavlink.classifier.classifyFrame(frame) catch |err| {
        try stderr.print("MAVLink classification failed: {s}\n", .{@errorName(err)});
        return 65;
    };
    var mapping = edge.mavlink.mapping.mapFrameToCommand(allocator, frame, .{ .vehicle_id = "edge-vehicle-1", .now_ms = 1_000_100 }) catch |err| {
        try stderr.print("MAVLink mapping failed: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer mapping.deinit();
    try stdout.print("Message: {s} ({d})\n", .{ classification.message_name, classification.message_id });
    try stdout.print("Category: {s}\n", .{@tagName(classification.category)});
    try stdout.print("Safety-sensitive: {}\n", .{classification.safety_sensitive});
    if (classification.command_id) |command_id| try stdout.print("MAV_CMD: {d} ({s})\n", .{ command_id, edge.mavlink.commands.nameFor(command_id) });
    if (mapping.request) |request| {
        try stdout.print("Mapped Edge action: {s}\n", .{@tagName(request.action)});
        try stdout.print("Risk: {s}\n", .{@tagName(request.risk_classification)});
    } else if (mapping.unsupported) |unsupported| {
        try stdout.print("Mapped Edge action: unsupported\nRisk: {s}\nReason: {s}\n", .{ @tagName(unsupported.risk), unsupported.reason });
    } else {
        try stdout.writeAll("Mapped Edge action: none\nRisk: low-or-unknown-message\n");
    }
    try stdout.writeAll("No command was sent to a vehicle, simulator, or flight controller.\n");
    return 0;
}

fn runMavlinkSimulate(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var policy_path: ?[]const u8 = null;
    var scenario_path: ?[]const u8 = null;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--policy")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge mavlink simulate: --policy requires a file.\n");
            policy_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--scenario")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge mavlink simulate: --scenario requires a file.\n");
            scenario_path = argv[index];
        } else {
            try stderr.print("aegis-edge mavlink simulate: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected_policy_path = policy_path orelse return usageError(stderr, "aegis-edge mavlink simulate: missing --policy.\n");
    const selected_scenario_path = scenario_path orelse return usageError(stderr, "aegis-edge mavlink simulate: missing --scenario.\n");

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var loaded = edge.policy.loadFile(allocator, selected_policy_path, .{}) catch |err| {
        try stderr.print("Edge policy invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer loaded.deinit();
    var scenario = loadScenario(allocator, selected_scenario_path) catch |err| {
        try stderr.print("MAVLink scenario invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer scenario.deinit();
    const frame = edge.mavlink.framing.parseFrame(scenario.frame_bytes) catch |err| {
        try stderr.print("Generated MAVLink scenario frame invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    var tracker = edge.mavlink.mission.MissionTracker.init();
    var result = if (edge.mavlink.dialect.isMission(frame.msgid)) blk: {
        const count = try edge.mavlink.fake_transport.frameMissionCountV2(allocator, .{ .seq = 1, .sysid = 42, .compid = 191 }, 1);
        defer allocator.free(count);
        try tracker.observe(try edge.mavlink.messages.decode(try edge.mavlink.framing.parseFrame(count)));
        break :blk try edge.mavlink.gateway.processMissionFrame(allocator, .{ .mode = .enforce, .direction = .companion_to_vehicle, .vehicle_id = "edge-vehicle-1", .now_ms = 1_000_500 }, &loaded.value, defaultStateForPolicy(&loaded.value, 1_000_000), frame, &tracker);
    } else try edge.mavlink.gateway.processFrame(allocator, .{ .mode = .enforce, .direction = .companion_to_vehicle, .vehicle_id = "edge-vehicle-1", .now_ms = 1_000_500 }, &loaded.value, defaultStateForPolicy(&loaded.value, 1_000_000), frame);
    defer result.deinit();

    if (scenario.expected_decision) |expected| {
        const actual = result.decision orelse {
            try stderr.writeAll("MAVLink scenario expectation failed: expected decision but gateway produced none.\n");
            return 65;
        };
        if (actual != expected) {
            try stderr.print("MAVLink scenario expectation failed: expected_decision={s} actual={s}\n", .{ expected.toString(), actual.toString() });
            return 65;
        }
    }
    if (scenario.expected_forwarded) |expected| {
        if (result.forwarded != expected) {
            try stderr.print("MAVLink scenario expectation failed: expected_forwarded={} actual={}\n", .{ expected, result.forwarded });
            return 65;
        }
    }

    try stdout.print("Scenario: {s}\n", .{selected_scenario_path});
    try stdout.writeAll("Transport: fake_transport/simulation\n");
    try stdout.print("Message: {s} ({d})\n", .{ result.classification.message_name, result.classification.message_id });
    try stdout.print("Decision: {s}\n", .{if (result.decision) |decision| decision.toString() else "none"});
    try stdout.print("Forwarded: {}\nBlocked: {}\n", .{ result.forwarded, result.blocked });
    try stdout.writeAll("Audit events:\n");
    for (result.audit.records.items) |record| try stdout.print("  - {s}\n", .{record.event_type});
    try stdout.writeAll("No serial hardware, SITL, ROS2, or hardware endpoint was opened by this fake MAVLink scenario.\n");
    return 0;
}

fn runMavlinkGateway(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var fake = false;
    var policy_path: ?[]const u8 = null;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--fake")) {
            fake = true;
        } else if (std.mem.eql(u8, argv[index], "--policy")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge mavlink gateway: --policy requires a file.\n");
            policy_path = argv[index];
        } else {
            try stderr.print("aegis-edge mavlink gateway: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    if (!fake) return usageError(stderr, "aegis-edge mavlink gateway: only --fake in-memory mode is implemented in Phase 28.\n");
    const selected_policy_path = policy_path orelse return usageError(stderr, "aegis-edge mavlink gateway: missing --policy.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    var loaded = edge.policy.loadFile(gpa_state.allocator(), selected_policy_path, .{}) catch |err| {
        try stderr.print("Edge policy invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer loaded.deinit();
    try stdout.print("MAVLink fake gateway configured with policy {s}\n", .{selected_policy_path});
    try stdout.writeAll("Mode: fake_transport only. Serial hardware endpoints were not opened.\n");
    return 0;
}

fn runPolicy(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0) {
        try stderr.writeAll("aegis-edge policy: expected check, explain, or evaluate.\n");
        return 64;
    }
    if (std.mem.eql(u8, argv[0], "check")) return runPolicyCheck(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "explain")) return runPolicyExplain(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "evaluate")) return runPolicyEvaluate(argv[1..], stdout, stderr);
    try stderr.print("aegis-edge policy: unknown subcommand '{s}'.\n", .{argv[0]});
    return 64;
}

fn runPolicyCheck(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var json = false;
    var policy_path: ?[]const u8 = null;
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--json")) {
            json = true;
        } else if (policy_path == null) {
            policy_path = arg;
        } else {
            try stderr.writeAll("aegis-edge policy check: expected one policy path and optional --json.\n");
            return 64;
        }
    }
    const path = policy_path orelse {
        try stderr.writeAll("aegis-edge policy check: missing policy path.\n");
        return 64;
    };

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    var loaded = edge.policy.loadFile(gpa_state.allocator(), path, .{}) catch |err| {
        try stderr.print("Edge policy invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer loaded.deinit();

    if (json) {
        try stdout.writeAll("{\"ok\":true,\"policy\":");
        try edge.core.core.util.writeJsonString(stdout, path);
        try stdout.print(",\"version\":{d}}}\n", .{loaded.value.version});
    } else {
        try stdout.print("Edge policy valid: {s}\n", .{path});
        try stdout.writeAll("No vehicle command mediation is active; this is policy validation only.\n");
    }
    return 0;
}

fn runPolicyExplain(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len < 2) {
        try stderr.writeAll("aegis-edge policy explain: expected <policy> <command> [--mode <mode>] [--json].\n");
        return 64;
    }
    const policy_path = argv[0];
    const action_text = argv[1];
    var mode: edge.policy.EvaluationMode = .strict;
    var json = false;
    var index: usize = 2;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--json")) {
            json = true;
        } else if (std.mem.eql(u8, argv[index], "--mode")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("aegis-edge policy explain: --mode requires a value.\n");
                return 64;
            }
            mode = parseMode(argv[index]) catch |err| {
                try stderr.print("aegis-edge policy explain: invalid mode: {s}\n", .{@errorName(err)});
                return 64;
            };
        } else {
            try stderr.print("aegis-edge policy explain: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var loaded = edge.policy.loadFile(allocator, policy_path, .{}) catch |err| {
        try stderr.print("Edge policy invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer loaded.deinit();
    const action = std.meta.stringToEnum(edge.domain.commands.CommandAction, action_text) orelse {
        try stderr.print("aegis-edge policy explain: unknown command '{s}'.\n", .{action_text});
        return 64;
    };
    const state = defaultStateForPolicy(&loaded.value, 1_000_000);
    const command = defaultRequestForAction(&loaded.value, action, 1_000_100);
    var evaluation = edge.policy.evaluateEdgeAction(allocator, &loaded.value, command, state, .{ .mode = mode, .now_ms = 1_000_500, .non_interactive = mode == .ci }) catch |err| {
        try stderr.print("Edge policy explain failed: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer evaluation.deinit();
    try writeEvaluation(stdout, evaluation, json);
    return 0;
}

fn runPolicyEvaluate(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len < 1) {
        try stderr.writeAll("aegis-edge policy evaluate: expected <policy> --request <request.json> --state <state.json>.\n");
        return 64;
    }
    const policy_path = argv[0];
    var request_path: ?[]const u8 = null;
    var state_path: ?[]const u8 = null;
    var mode: edge.policy.EvaluationMode = .strict;
    var json = false;
    var index: usize = 1;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--json")) {
            json = true;
        } else if (std.mem.eql(u8, argv[index], "--request")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge policy evaluate: --request requires a file.\n");
            request_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--state")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge policy evaluate: --state requires a file.\n");
            state_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--mode")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge policy evaluate: --mode requires a value.\n");
            mode = parseMode(argv[index]) catch |err| {
                try stderr.print("aegis-edge policy evaluate: invalid mode: {s}\n", .{@errorName(err)});
                return 64;
            };
        } else {
            try stderr.print("aegis-edge policy evaluate: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const request_file = request_path orelse return usageError(stderr, "aegis-edge policy evaluate: missing --request.\n");
    const state_file = state_path orelse return usageError(stderr, "aegis-edge policy evaluate: missing --state.\n");

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var loaded = edge.policy.loadFile(allocator, policy_path, .{}) catch |err| {
        try stderr.print("Edge policy invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer loaded.deinit();

    const request_text = try std.fs.cwd().readFileAlloc(allocator, request_file, 128 * 1024);
    defer allocator.free(request_text);
    const state_text = try std.fs.cwd().readFileAlloc(allocator, state_file, 128 * 1024);
    defer allocator.free(state_text);

    const command = edge.policy.parseCommandRequestJson(allocator, request_text) catch |err| {
        try stderr.print("Edge command request invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    const state = edge.policy.parseVehicleStateJson(allocator, state_text) catch |err| {
        try stderr.print("Edge vehicle state invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    var evaluation = edge.policy.evaluateEdgeAction(allocator, &loaded.value, command, state, .{ .mode = mode, .now_ms = state.timestamp.value + 500, .non_interactive = mode == .ci }) catch |err| {
        try stderr.print("Edge policy evaluation failed: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer evaluation.deinit();
    try writeEvaluation(stdout, evaluation, json);
    return 0;
}

fn usageError(stderr: anytype, message: []const u8) !u8 {
    try stderr.writeAll(message);
    return 64;
}

fn runSchema(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0) {
        try stderr.writeAll("aegis-edge schema: expected list or print.\n");
        return 64;
    }

    if (std.mem.eql(u8, argv[0], "list")) {
        if (argv.len != 1) {
            try stderr.writeAll("aegis-edge schema list: expected no arguments.\n");
            return 64;
        }
        for (edge.schema.registry) |descriptor| {
            try stdout.print("{s}\tversion={d}\t{s}\n", .{ descriptor.id, descriptor.version, descriptor.path });
        }
        return 0;
    }

    if (std.mem.eql(u8, argv[0], "print")) {
        if (argv.len != 2) {
            try stderr.writeAll("aegis-edge schema print: expected exactly one schema id.\n");
            return 64;
        }
        const schema_id = argv[1];
        if (std.mem.eql(u8, schema_id, "edge-policy-v1")) {
            return printSchemaDocument(stdout, edge_policy_schema_document);
        }
        if (std.mem.eql(u8, schema_id, "edge-event-v1")) {
            return printSchemaDocument(stdout, edge_event_schema_document);
        }
        if (std.mem.eql(u8, schema_id, "safety-report-v1")) {
            return printSchemaDocument(stdout, safety_report_schema_document);
        }
        try stderr.print("aegis-edge schema print: unknown schema id '{s}'.\n", .{schema_id});
        return 64;
    }

    try stderr.print("aegis-edge schema: unknown subcommand '{s}'.\n", .{argv[0]});
    return 64;
}

fn printSchemaDocument(stdout: anytype, document: []const u8) !u8 {
    try stdout.writeAll(document);
    if (document.len == 0 or document[document.len - 1] != '\n') try stdout.writeByte('\n');
    return 0;
}

fn parseMode(value: []const u8) !edge.policy.EvaluationMode {
    return std.meta.stringToEnum(edge.policy.EvaluationMode, value) orelse error.UnknownEvaluationMode;
}

fn defaultStateForPolicy(policy: *const edge.schema.edge_policy_schema.EdgePolicyV1, timestamp_ms: i128) edge.domain.state.VehicleState {
    const center = if (policy.safety.geofence) |geofence| switch (geofence.shape) {
        .circle => |circle| circle.center,
        .allowed_polygon => |_| edge.domain.coordinates.GeoPoint{ .latitude_deg = 0, .longitude_deg = 0, .altitude_m = 0, .altitude_reference = .amsl },
    } else edge.domain.coordinates.GeoPoint{ .latitude_deg = 0, .longitude_deg = 0, .altitude_m = 20, .altitude_reference = .amsl };
    return .{
        .vehicle_id = .{ .value = "edge-vehicle-1" },
        .vehicle_kind = policy.vehicle.kind,
        .autopilot_kind = policy.vehicle.autopilot,
        .mode = .guided,
        .arm_state = .armed,
        .position = .{
            .latitude_deg = center.latitude_deg,
            .longitude_deg = center.longitude_deg,
            .altitude_m = if (policy.safety.geofence) |geofence| @max(geofence.altitude_floor_m, center.altitude_m + 20) else center.altitude_m,
            .altitude_reference = center.altitude_reference,
        },
        .battery_state = .{ .percent_remaining = 80, .voltage_v = 15.2, .current_a = 2.1, .source = .monotonic },
        .control_authority = .onboard_agent,
        .home_position = center,
        .timestamp = .{ .value = timestamp_ms, .source = .monotonic },
        .state_freshness = .fresh,
        .provenance = .fake_adapter,
    };
}

fn defaultRequestForAction(policy: *const edge.schema.edge_policy_schema.EdgePolicyV1, action: edge.domain.commands.CommandAction, timestamp_ms: i128) edge.domain.commands.CommandRequest {
    const center = if (policy.safety.geofence) |geofence| switch (geofence.shape) {
        .circle => |circle| circle.center,
        .allowed_polygon => |_| edge.domain.coordinates.GeoPoint{ .latitude_deg = 0, .longitude_deg = 0, .altitude_m = 0, .altitude_reference = .amsl },
    } else edge.domain.coordinates.GeoPoint{ .latitude_deg = 0, .longitude_deg = 0, .altitude_m = 20, .altitude_reference = .amsl };
    const params: edge.domain.commands.CommandParameters = switch (action) {
        .set_waypoint => .{ .waypoint = .{ .latitude_deg = center.latitude_deg, .longitude_deg = center.longitude_deg, .altitude_m = center.altitude_m + 20, .altitude_reference = center.altitude_reference } },
        .set_velocity => .{ .velocity = .{ .vx_mps = 1, .vy_mps = 1, .vz_mps = 0, .frame = .local_ned } },
        .set_altitude, .takeoff => .{ .altitude = .{ .altitude_m = center.altitude_m + 20, .altitude_reference = center.altitude_reference } },
        .set_heading => .{ .heading = edge.domain.coordinates.Heading.degrees(90) },
        .set_mode => .{ .mode = .guided },
        else => .none,
    };
    return edge.domain.commands.CommandRequest.init(.{
        .command_id = "explain-command",
        .vehicle_id = .{ .value = "edge-vehicle-1" },
        .action = action,
        .parameters = params,
        .actor = "aegis-edge-explain",
        .timestamp = .{ .value = timestamp_ms, .source = .monotonic },
        .source = .fake_adapter,
    });
}

fn writeEvaluation(stdout: anytype, evaluation: edge.policy.EdgeEvaluation, json: bool) !void {
    if (json) {
        try stdout.writeAll("{\"result\":");
        try edge.core.core.util.writeJsonString(stdout, evaluation.decision.result.toString());
        try stdout.writeAll(",\"reason\":");
        try edge.core.core.util.writeJsonString(stdout, evaluation.explanation);
        try stdout.writeAll(",\"requires_operator_approval\":");
        try stdout.print("{}", .{evaluation.decision.requires_user});
        try stdout.writeAll(",\"ci_may_proceed\":");
        try stdout.print("{}", .{evaluation.decision.ci_may_proceed});
        if (evaluation.recommended_fallback) |fallback| {
            try stdout.writeAll(",\"recommended_fallback\":");
            try edge.core.core.util.writeJsonString(stdout, @tagName(fallback));
        }
        try stdout.writeAll(",\"audit_events\":[");
        for (evaluation.audit_events, 0..) |event, index| {
            if (index > 0) try stdout.writeByte(',');
            try edge.core.core.util.writeJsonString(stdout, event.event_type);
        }
        try stdout.writeAll("]}\n");
        return;
    }

    try stdout.print("Decision: {s}\n", .{evaluation.decision.result.toString()});
    try stdout.print("Reason: {s}\n", .{evaluation.explanation});
    if (evaluation.matched_rule) |rule| try stdout.print("Matched rule: {s} ({s})\n", .{ rule.id, rule.description });
    if (evaluation.recommended_fallback) |fallback| try stdout.print("Recommended fallback: {s}\n", .{@tagName(fallback)});
    if (evaluation.violated_constraints.len > 0) {
        try stdout.writeAll("Violated constraints:\n");
        for (evaluation.violated_constraints) |constraint| try stdout.print("  - {s}: {s}\n", .{ @tagName(constraint.kind), constraint.message });
    }
    if (evaluation.audit_events.len > 0) {
        try stdout.writeAll("Prepared audit events:\n");
        for (evaluation.audit_events) |event| try stdout.print("  - {s}\n", .{event.event_type});
    }
    try stdout.writeAll("No command was sent to a vehicle, adapter, simulator, or flight controller.\n");
}

fn readFileOrHex(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    const text = std.fs.cwd().readFileAlloc(allocator, value, 16 * 1024) catch |err| switch (err) {
        error.FileNotFound => return parseHexAlloc(allocator, value),
        else => return err,
    };
    errdefer allocator.free(text);
    if (text.len > 0 and (text[0] == edge.mavlink.framing.magic_v1 or text[0] == edge.mavlink.framing.magic_v2)) return text;
    const parsed = try parseHexAlloc(allocator, text);
    allocator.free(text);
    return parsed;
}

fn parseHexAlloc(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var compact: std.ArrayList(u8) = .empty;
    defer compact.deinit(allocator);
    var index: usize = 0;
    while (index < text.len) : (index += 1) {
        const byte = text[index];
        switch (byte) {
            ' ', '\t', '\r', '\n', ':', '_' => continue,
            '0' => if (index + 1 < text.len and (text[index + 1] == 'x' or text[index + 1] == 'X')) {
                index += 1;
                continue;
            },
            else => {},
        }
        try compact.append(allocator, byte);
    }
    if (compact.items.len == 0 or compact.items.len % 2 != 0) return error.InvalidHex;
    var bytes = try allocator.alloc(u8, compact.items.len / 2);
    errdefer allocator.free(bytes);
    var out_index: usize = 0;
    while (out_index < bytes.len) : (out_index += 1) {
        const hi = hexValue(compact.items[out_index * 2]) orelse return error.InvalidHex;
        const lo = hexValue(compact.items[out_index * 2 + 1]) orelse return error.InvalidHex;
        bytes[out_index] = (hi << 4) | lo;
    }
    return bytes;
}

fn hexValue(byte: u8) ?u8 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        'A'...'F' => byte - 'A' + 10,
        else => null,
    };
}

const Scenario = struct {
    allocator: std.mem.Allocator,
    frame_path: []u8,
    frame_bytes: []u8,
    expected_decision: ?edge.core.decision.DecisionResult = null,
    expected_forwarded: ?bool = null,

    fn deinit(self: *Scenario) void {
        self.allocator.free(self.frame_path);
        self.allocator.free(self.frame_bytes);
        self.* = undefined;
    }
};

fn loadScenario(allocator: std.mem.Allocator, scenario_path: []const u8) !Scenario {
    const text = try std.fs.cwd().readFileAlloc(allocator, scenario_path, 32 * 1024);
    defer allocator.free(text);

    var frame_value: ?[]const u8 = null;
    var expected_decision: ?edge.core.decision.DecisionResult = null;
    var expected_forwarded: ?bool = null;

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const no_comment = if (std.mem.indexOfScalar(u8, raw_line, '#')) |index| raw_line[0..index] else raw_line;
        const line = std.mem.trim(u8, no_comment, " \t\r");
        if (line.len == 0) continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.InvalidScenario;
        const key = std.mem.trim(u8, line[0..colon], " \t");
        const value = cleanScenarioScalar(line[colon + 1 ..]);
        if (std.mem.eql(u8, key, "frame")) {
            frame_value = value;
        } else if (std.mem.eql(u8, key, "expected_decision")) {
            expected_decision = std.meta.stringToEnum(edge.core.decision.DecisionResult, value) orelse return error.InvalidScenarioDecision;
        } else if (std.mem.eql(u8, key, "expected_forwarded")) {
            expected_forwarded = parseScenarioBool(value) catch return error.InvalidScenarioForwarded;
        } else if (std.mem.eql(u8, key, "transport")) {
            if (!std.mem.eql(u8, value, "fake_transport")) return error.UnsupportedScenarioTransport;
        }
    }

    const frame_ref = frame_value orelse return error.MissingScenarioFrame;
    const frame_path = try resolveScenarioPath(allocator, scenario_path, frame_ref);
    errdefer allocator.free(frame_path);
    const frame_bytes = try readFileOrHex(allocator, frame_path);
    errdefer allocator.free(frame_bytes);
    return .{
        .allocator = allocator,
        .frame_path = frame_path,
        .frame_bytes = frame_bytes,
        .expected_decision = expected_decision,
        .expected_forwarded = expected_forwarded,
    };
}

fn resolveScenarioPath(allocator: std.mem.Allocator, scenario_path: []const u8, frame_ref: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(frame_ref)) return try allocator.dupe(u8, frame_ref);
    const scenario_dir = std.fs.path.dirname(scenario_path) orelse ".";
    return try std.fs.path.join(allocator, &.{ scenario_dir, frame_ref });
}

fn cleanScenarioScalar(raw: []const u8) []const u8 {
    var value = std.mem.trim(u8, raw, " \t\r");
    if (value.len >= 2) {
        const first = value[0];
        const last = value[value.len - 1];
        if ((first == '"' and last == '"') or (first == '\'' and last == '\'')) value = value[1 .. value.len - 1];
    }
    return value;
}

fn parseScenarioBool(value: []const u8) !bool {
    if (std.mem.eql(u8, value, "true")) return true;
    if (std.mem.eql(u8, value, "false")) return false;
    return error.InvalidBool;
}

test "aegis-edge help is honest policy evaluation output" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [128]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    const argv = [_][]const u8{"--help"};

    const code = try run(argv[0..], stdout_stream.writer(), stderr_stream.writer());

    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "policy evaluate") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "PX4 and ArduPilot SITL are opt-in local simulation only") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "aegis-edge schema print uses embedded edge policy schema" {
    var stdout_buf: [16384]u8 = undefined;
    var stderr_buf: [128]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    const argv = [_][]const u8{ "schema", "print", "edge-policy-v1" };

    const code = try run(argv[0..], stdout_stream.writer(), stderr_stream.writer());

    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "\"required\": [\"version\", \"vehicle\", \"safety\", \"commands\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "domain-schema-only") == null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "aegis-edge schema print works outside repository cwd" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const original_cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(original_cwd);
    const tmp_cwd = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_cwd);
    try std.posix.chdir(tmp_cwd);
    defer std.posix.chdir(original_cwd) catch {};

    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [128]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    const argv = [_][]const u8{ "schema", "print", "edge-event-v1" };

    const code = try run(argv[0..], stdout_stream.writer(), stderr_stream.writer());

    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "\"event_type\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "mavlink.command_denied") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "aegis-edge schema list is honest domain/schema output" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [128]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    const argv = [_][]const u8{ "schema", "list" };

    const code = try run(argv[0..], stdout_stream.writer(), stderr_stream.writer());

    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "edge-policy-v1") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "aegis-edge policy explain supplies safe defaults for heading and mode commands" {
    inline for (.{ "set_heading", "set_mode" }) |command| {
        var stdout_buf: [4096]u8 = undefined;
        var stderr_buf: [512]u8 = undefined;
        var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
        var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
        const argv = [_][]const u8{ "policy", "explain", "examples/edge/policies/geofence-basic.yaml", command };

        const code = try run(argv[0..], stdout_stream.writer(), stderr_stream.writer());

        try std.testing.expectEqual(@as(u8, 0), code);
        try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Decision:") != null);
        try std.testing.expectEqualStrings("", stderr_stream.getWritten());
    }
}

test "aegis-edge policy check json escapes policy path" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const policy_text =
        \\version: 1
        \\vehicle:
        \\  kind: drone_multirotor
        \\  autopilot: px4
        \\  adapter: fake
        \\safety:
        \\  state_freshness:
        \\    max_state_age_ms: 1000
        \\    deny_commands_on_stale_state: true
        \\commands:
        \\  allow:
        \\    - read_telemetry
    ;
    try tmp.dir.writeFile(.{ .sub_path = "edge\"policy.yaml", .data = policy_text });
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    const policy_path = try std.fs.path.join(std.testing.allocator, &.{ root, "edge\"policy.yaml" });
    defer std.testing.allocator.free(policy_path);

    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    const argv = [_][]const u8{ "policy", "check", policy_path, "--json" };

    const code = try run(argv[0..], stdout_stream.writer(), stderr_stream.writer());

    try std.testing.expectEqual(@as(u8, 0), code);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, stdout_stream.getWritten(), .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings(policy_path, parsed.value.object.get("policy").?.string);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "aegis-edge mavlink doctor inspect classify and simulate use fake transport only" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const doctor_argv = [_][]const u8{ "mavlink", "doctor" };
    try std.testing.expectEqual(@as(u8, 0), try run(doctor_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "fake_transport") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "signing verification") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    stdout_stream.reset();
    stderr_stream.reset();
    const inspect_argv = [_][]const u8{ "mavlink", "inspect-frame", "fd2100002c2abf4c00000000803f0000000000000000000000000000000000000000000000009001010100b569" };
    try std.testing.expectEqual(@as(u8, 0), try run(inspect_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "COMMAND_LONG") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "CRC: valid") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    stdout_stream.reset();
    stderr_stream.reset();
    const classify_argv = [_][]const u8{ "mavlink", "classify", "fd2100002c2abf4c00000000000000000000000000000000000000000000000000000000f04116000101008700" };
    try std.testing.expectEqual(@as(u8, 0), try run(classify_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Mapped Edge action: takeoff") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    stdout_stream.reset();
    stderr_stream.reset();
    const simulate_argv = [_][]const u8{
        "mavlink",
        "simulate",
        "--policy",
        "examples/edge/mavlink/policies/geofence-mavlink-basic.yaml",
        "--scenario",
        "examples/edge/mavlink/scenarios/geofence-deny.yaml",
    };
    try std.testing.expectEqual(@as(u8, 0), try run(simulate_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Decision: deny") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "No serial hardware, SITL, ROS2, or hardware endpoint was opened") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "aegis-edge mavlink simulate reads scenario frame contents instead of filename" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const land_hex = try std.fs.cwd().readFileAlloc(std.testing.allocator, "examples/edge/mavlink/frames/command-land.hex", 1024);
    defer std.testing.allocator.free(land_hex);
    try tmp.dir.writeFile(.{ .sub_path = "renamed-frame.hex", .data = land_hex });
    const neutral_scenario =
        \\name: neutral-name
        \\transport: fake_transport
        \\frame: renamed-frame.hex
        \\expected_decision: allow
        \\expected_forwarded: true
    ;
    try tmp.dir.writeFile(.{ .sub_path = "neutral-name.yaml", .data = neutral_scenario });
    const mismatch_scenario =
        \\name: mismatch
        \\transport: fake_transport
        \\frame: renamed-frame.hex
        \\expected_decision: deny
        \\expected_forwarded: false
    ;
    try tmp.dir.writeFile(.{ .sub_path = "mismatch.yaml", .data = mismatch_scenario });
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    const scenario_path = try std.fs.path.join(std.testing.allocator, &.{ root, "neutral-name.yaml" });
    defer std.testing.allocator.free(scenario_path);
    const mismatch_path = try std.fs.path.join(std.testing.allocator, &.{ root, "mismatch.yaml" });
    defer std.testing.allocator.free(mismatch_path);

    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    const simulate_argv = [_][]const u8{
        "mavlink",
        "simulate",
        "--policy",
        "examples/edge/mavlink/policies/geofence-mavlink-basic.yaml",
        "--scenario",
        scenario_path,
    };
    try std.testing.expectEqual(@as(u8, 0), try run(simulate_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Decision: allow") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Forwarded: true") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    stdout_stream.reset();
    stderr_stream.reset();
    const mismatch_argv = [_][]const u8{
        "mavlink",
        "simulate",
        "--policy",
        "examples/edge/mavlink/policies/geofence-mavlink-basic.yaml",
        "--scenario",
        mismatch_path,
    };
    try std.testing.expectEqual(@as(u8, 65), try run(mismatch_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "MAVLink scenario expectation failed") != null);
}
