const std = @import("std");
const core = @import("../core/mod.zig");
const sandbox = @import("../sandbox/mod.zig");

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
    .{ .label = "network policy engine", .capability = .network_policy_engine },
    .{ .label = "network observation", .capability = .network_observe },
    .{ .label = "transparent network enforcement", .capability = .network_enforce },
    .{ .label = "proxy-mediated enforcement", .capability = .network_proxy_enforce },
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
    const backend_report = sandbox.backend.detect(os);
    try writeReport(stdout, os, backend_report);
    return exit_codes.success;
}

fn writeReport(stdout: anytype, os: core.platform.Os, backend_report: sandbox.backend.ReportSet) !void {
    try stdout.writeAll("Aegis Doctor\n\n");
    try stdout.print("OS: {s}\n", .{os.toString()});
    try stdout.print("Version: {s}\n\n", .{cli.version});
    try stdout.writeAll("Capabilities:\n");
    for (doctor_capabilities) |item| {
        const report = core.platform.reportCapability(os, item.capability);
        try stdout.print("  {s}: {s} ({s})\n", .{ item.label, report.state.toString(), report.note });
    }
    try stdout.writeByte('\n');
    if (os == .linux) {
        try stdout.writeAll("Linux backend:\n");
    } else {
        try stdout.writeAll("Backend:\n");
    }
    try stdout.print("  selected: {s}\n", .{backend_report.backend_name});
    try stdout.print("  fallback mode: {s} ({s})\n", .{ backend_report.fallback_level.toString(), backend_report.fallback_note });
    try writeBackendLine(stdout, backend_report, .policy_engine);
    try writeBackendLine(stdout, backend_report, .audit);
    try writeBackendLine(stdout, backend_report, .env_filtering);
    try writeBackendLine(stdout, backend_report, .path_staging);
    try writeBackendLine(stdout, backend_report, .shell_wrapping);
    try writeBackendLine(stdout, backend_report, .path_shims);
    try writeBackendLine(stdout, backend_report, .process_supervision);
    try writeBackendLine(stdout, backend_report, .user_namespaces);
    try writeBackendLine(stdout, backend_report, .mount_namespaces);
    try writeBackendLine(stdout, backend_report, .seccomp);
    try writeBackendLine(stdout, backend_report, .landlock);
    try writeBackendLine(stdout, backend_report, .cgroups);
    try writeBackendLine(stdout, backend_report, .network_enforce);
    try writeBackendLine(stdout, backend_report, .strong_sandbox);
}

fn writeBackendLine(stdout: anytype, backend_report: sandbox.backend.ReportSet, feature: sandbox.backend.Feature) !void {
    const report = backend_report.get(feature);
    try stdout.print("  {s}: {s} ({s})\n", .{ report.feature.label(), report.level.toString(), report.note });
}

test "doctor prints OS and planned capabilities" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(&.{}, stdout_stream.writer(), stderr_stream.writer());

    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Aegis Doctor") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "OS:") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "process supervision:") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "network policy engine: active") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "transparent network enforcement: unavailable") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "proxy-mediated enforcement: unavailable") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Backend:") != null or std.mem.indexOf(u8, stdout_stream.getWritten(), "Linux backend:") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "env filtering: active") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "strong sandbox:") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "doctor can render Linux backend details from an injected report" {
    var stdout_buf: [4096]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    const report = sandbox.backend.detect(.linux);

    try writeReport(stdout_stream.writer(), .linux, report);

    const written = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, written, "Linux backend:") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "user namespace:") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "mount namespace:") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "seccomp:") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "landlock:") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "network enforcement: observe-only") != null);
}
