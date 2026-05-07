const std = @import("std");
const edge = @import("aegis_edge");

const usage =
    \\Aegis Edge domain and safety schema
    \\
    \\Usage:
    \\  aegis-edge <command> [args]
    \\
    \\Commands:
    \\  doctor                         Show domain/schema capability status
    \\  schema list                    List versioned Edge schemas
    \\  schema print <schema-id>       Print a built-in schema document
    \\  help                           Show this help
    \\
    \\Drone command mediation is not implemented yet.
    \\
;

const edge_policy_schema_json =
    \\{
    \\  "$id": "https://aegis.local/schemas/edge-policy-v1.json",
    \\  "title": "Aegis Edge policy schema v1",
    \\  "version": 1,
    \\  "phase": "domain-schema-only",
    \\  "not_implemented": ["command mediation", "MAVLink", "PX4", "ArduPilot", "real flight"]
    \\}
    \\
;
const edge_event_schema_json =
    \\{
    \\  "$id": "https://aegis.local/schemas/edge-event-v1.json",
    \\  "title": "Aegis Edge event schema v1",
    \\  "version": 1
    \\}
    \\
;
const safety_report_schema_json =
    \\{
    \\  "$id": "https://aegis.local/schemas/safety-report-v1.json",
    \\  "title": "Aegis safety report schema v1",
    \\  "version": 1,
    \\  "disclaimer": "engineering audit artifact only; not certification"
    \\}
    \\
;

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

    try stderr.print("aegis-edge: unknown command '{s}'. Run 'aegis-edge --help' for usage.\n", .{command});
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
            try stdout.writeAll(edge_policy_schema_json);
            return 0;
        }
        if (std.mem.eql(u8, schema_id, "edge-event-v1")) {
            try stdout.writeAll(edge_event_schema_json);
            return 0;
        }
        if (std.mem.eql(u8, schema_id, "safety-report-v1")) {
            try stdout.writeAll(safety_report_schema_json);
            return 0;
        }
        try stderr.print("aegis-edge schema print: unknown schema id '{s}'.\n", .{schema_id});
        return 64;
    }

    try stderr.print("aegis-edge schema: unknown subcommand '{s}'.\n", .{argv[0]});
    return 64;
}

test "aegis-edge help is honest scaffold output" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [128]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    const argv = [_][]const u8{"--help"};

    const code = try run(argv[0..], stdout_stream.writer(), stderr_stream.writer());

    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Drone command mediation is not implemented yet") != null);
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
