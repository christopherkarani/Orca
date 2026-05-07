const std = @import("std");
const edge = @import("aegis_edge");

const usage =
    \\Aegis Edge scaffold
    \\
    \\Usage:
    \\  aegis-edge <command>
    \\
    \\Commands:
    \\  doctor    Show scaffold capability status
    \\  help      Show this help
    \\
    \\Drone command mediation is not implemented yet.
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

    try stderr.print("aegis-edge: unknown command '{s}'. Run 'aegis-edge --help' for usage.\n", .{command});
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
