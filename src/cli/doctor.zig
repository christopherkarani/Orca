const std = @import("std");
const core = @import("../core/mod.zig");

const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");
const cli = @import("mod.zig");

const DoctorCapability = struct {
    label: []const u8,
    capability: core.platform.Capability,
};

const doctor_capabilities = [_]DoctorCapability{
    .{ .label = "process supervision", .capability = .process_supervision },
    .{ .label = "env filtering", .capability = .env_filtering },
    .{ .label = "staged writes", .capability = .path_staging },
    .{ .label = "mcp stdio proxy", .capability = .mcp_stdio_proxy },
    .{ .label = "network enforcement", .capability = .network_enforce },
    .{ .label = "strong sandbox", .capability = .strong_sandbox },
};

pub fn command(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            _ = try help.writeCommand(stdout, "doctor");
            return exit_codes.success;
        }
        try stderr.print("aegis doctor: unknown option '{s}'.\n", .{arg});
        return exit_codes.usage;
    }

    const os = core.platform.detectOs();
    try stdout.writeAll("Aegis Doctor\n\n");
    try stdout.print("OS: {s}\n", .{os.toString()});
    try stdout.print("Version: {s}\n\n", .{cli.version});
    try stdout.writeAll("Capabilities:\n");
    for (doctor_capabilities) |item| {
        const report = core.platform.reportCapability(os, item.capability);
        try stdout.print("  {s}: planned ({s}; {s})\n", .{ item.label, report.state.toString(), report.note });
    }
    return exit_codes.success;
}

test "doctor prints OS and planned capabilities" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(&.{}, stdout_stream.writer(), stderr_stream.writer());

    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Aegis Doctor") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "OS:") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "process supervision: planned") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}
