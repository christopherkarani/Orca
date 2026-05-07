const std = @import("std");
const edge = @import("aegis_edge");

const usage =
    \\Aegis Edge policy evaluation
    \\
    \\Usage:
    \\  aegis-edge <command> [args]
    \\
    \\Commands:
    \\  doctor                         Show domain/schema capability status
    \\  policy check <policy>          Validate an Edge policy file
    \\  policy explain <policy> <cmd>   Explain one command decision with fake state
    \\  policy evaluate <policy> --request <request.json> --state <state.json>
    \\                                 Evaluate a command request without sending it
    \\  schema list                    List versioned Edge schemas
    \\  schema print <schema-id>       Print a built-in schema document
    \\  help                           Show this help
    \\
    \\Policy evaluation is local-only. Drone command mediation is not implemented yet.
    \\
;

const edge_policy_schema_path = "schemas/edge-policy-v1.json";
const edge_event_schema_path = "schemas/edge-event-v1.json";
const safety_report_schema_path = "schemas/safety-report-v1.json";

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
    if (std.mem.eql(u8, command, "policy")) {
        return runPolicy(argv[1..], stdout, stderr);
    }

    try stderr.print("aegis-edge: unknown command '{s}'. Run 'aegis-edge --help' for usage.\n", .{command});
    return 64;
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
    var evaluation = try edge.policy.evaluateEdgeAction(allocator, &loaded.value, command, state, .{ .mode = mode, .now_ms = 1_000_500, .non_interactive = mode == .ci });
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
            return printSchemaFile(stdout, edge_policy_schema_path);
        }
        if (std.mem.eql(u8, schema_id, "edge-event-v1")) {
            return printSchemaFile(stdout, edge_event_schema_path);
        }
        if (std.mem.eql(u8, schema_id, "safety-report-v1")) {
            return printSchemaFile(stdout, safety_report_schema_path);
        }
        try stderr.print("aegis-edge schema print: unknown schema id '{s}'.\n", .{schema_id});
        return 64;
    }

    try stderr.print("aegis-edge schema: unknown subcommand '{s}'.\n", .{argv[0]});
    return 64;
}

fn printSchemaFile(stdout: anytype, path: []const u8) !u8 {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const text = try std.fs.cwd().readFileAlloc(gpa_state.allocator(), path, 256 * 1024);
    defer gpa_state.allocator().free(text);
    try stdout.writeAll(text);
    try stdout.writeByte('\n');
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

test "aegis-edge help is honest policy evaluation output" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [128]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    const argv = [_][]const u8{"--help"};

    const code = try run(argv[0..], stdout_stream.writer(), stderr_stream.writer());

    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "policy evaluate") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Drone command mediation is not implemented yet") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "aegis-edge schema print uses checked-in edge policy schema" {
    var stdout_buf: [8192]u8 = undefined;
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
