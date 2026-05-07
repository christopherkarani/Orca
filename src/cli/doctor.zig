const std = @import("std");
const core = @import("../core/mod.zig");
const sandbox = @import("../sandbox/mod.zig");

const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");
const cli = @import("mod.zig");

const DoctorCapability = struct {
    label: []const u8,
    feature: ?sandbox.backend.Feature = null,
    capability: ?core.platform.Capability = null,
};

const doctor_capabilities = [_]DoctorCapability{
    .{ .label = "process supervision", .feature = .process_supervision },
    .{ .label = "env filtering", .feature = .env_filtering },
    .{ .label = "staged writes", .feature = .path_staging },
    .{ .label = "mcp stdio proxy", .feature = .mcp_stdio_proxy },
    .{ .label = "network policy engine", .capability = .network_policy_engine },
    .{ .label = "network observation", .feature = .network_observe },
    .{ .label = "transparent network enforcement", .feature = .network_enforce },
    .{ .label = "proxy-mediated enforcement", .capability = .network_proxy_enforce },
    .{ .label = "strong sandbox", .feature = .strong_sandbox },
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
        if (item.feature) |feature| {
            const report = backend_report.get(feature);
            try stdout.print("  {s}: {s} ({s})\n", .{ item.label, report.level.toString(), report.note });
        } else if (item.capability) |capability| {
            const report = core.platform.reportCapability(os, capability);
            try stdout.print("  {s}: {s} ({s})\n", .{ item.label, report.state.toString(), report.note });
        }
    }
    try stdout.writeByte('\n');
    if (os == .linux) {
        try stdout.writeAll("Linux backend:\n");
    } else if (os == .macos) {
        try stdout.writeAll("macOS backend:\n");
    } else if (os == .windows) {
        try stdout.writeAll("Windows backend:\n");
    } else {
        try stdout.writeAll("Backend:\n");
    }
    try stdout.print("  selected: {s}\n", .{backend_report.backend_name});
    try stdout.print("  fallback mode: {s} ({s})\n", .{ backend_report.fallback_level.toString(), backend_report.fallback_note });
    if (os == .windows) {
        try writeWindowsBackendReport(stdout, backend_report);
        return;
    }
    try writeBackendLine(stdout, backend_report, .policy_engine);
    try writeBackendLine(stdout, backend_report, .env_filtering);
    try writeBackendLine(stdout, backend_report, .path_staging);
    if (os == .macos) {
        try stdout.writeAll("  transparent file enforcement: limited (no transparent macOS filesystem monitor is installed; Aegis-mediated staging and protected path matching are active)\n");
    }
    try writeBackendLine(stdout, backend_report, .shell_wrapping);
    try writeBackendLine(stdout, backend_report, .path_shims);
    try writeBackendLine(stdout, backend_report, .process_supervision);
    if (os == .linux) {
        try writeBackendLine(stdout, backend_report, .user_namespaces);
        try writeBackendLine(stdout, backend_report, .mount_namespaces);
        try writeBackendLine(stdout, backend_report, .seccomp);
        try writeBackendLine(stdout, backend_report, .landlock);
        try writeBackendLine(stdout, backend_report, .cgroups);
    }
    try writeBackendLine(stdout, backend_report, .network_enforce);
    try writeBackendLine(stdout, backend_report, .mcp_stdio_proxy);
    try writeBackendLine(stdout, backend_report, .strong_sandbox);
    try writeBackendLine(stdout, backend_report, .audit);
}

fn writeWindowsBackendReport(stdout: anytype, backend_report: sandbox.backend.ReportSet) !void {
    try writeBackendLine(stdout, backend_report, .policy_engine);
    try writeBackendLine(stdout, backend_report, .env_filtering);
    try writeBackendLine(stdout, backend_report, .path_staging);
    try writeBackendLine(stdout, backend_report, .path_shims);
    const shell = backend_report.get(.shell_wrapping);
    try stdout.print("  cmd wrapper: partial ({s})\n", .{shell.note});
    try stdout.print("  PowerShell wrapper: partial ({s})\n", .{shell.note});
    const cleanup = backend_report.get(.process_supervision);
    try stdout.print("  process cleanup: {s} ({s})\n", .{ cleanup.level.toString(), cleanup.note });
    try stdout.writeAll("  transparent file enforcement: limited (no transparent Windows filesystem enforcement is installed; Aegis-mediated staging and protected path matching are active)\n");
    try writeBackendLine(stdout, backend_report, .network_enforce);
    try writeBackendLine(stdout, backend_report, .strong_sandbox);
    try writeBackendLine(stdout, backend_report, .mcp_stdio_proxy);
    try writeBackendLine(stdout, backend_report, .audit);
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
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "transparent network enforcement: unavailable") != null or std.mem.indexOf(u8, stdout_stream.getWritten(), "transparent network enforcement: limited") != null or std.mem.indexOf(u8, stdout_stream.getWritten(), "transparent network enforcement: observe-only") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "proxy-mediated enforcement: unavailable") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Backend:") != null or std.mem.indexOf(u8, stdout_stream.getWritten(), "Linux backend:") != null or std.mem.indexOf(u8, stdout_stream.getWritten(), "macOS backend:") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, written, "transparent network enforcement: observe-only") != null);
}

test "doctor can render macOS backend details from an injected report" {
    var stdout_buf: [4096]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    const report = sandbox.backend.detect(.macos);

    try writeReport(stdout_stream.writer(), .macos, report);

    const written = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, written, "macOS backend:") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "selected: macos") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "env filtering: active") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "path staging: active") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "transparent file enforcement: limited") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "shell shims: wrapper-only") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "process supervision: active") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "transparent network enforcement: limited") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "strong sandbox: unavailable") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "mcp stdio proxy: active") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "audit/replay: active") != null);
}

test "doctor can render Windows backend details from an injected report" {
    var stdout_buf: [4096]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    const report = sandbox.backend.detect(.windows);

    try writeReport(stdout_stream.writer(), .windows, report);

    const written = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, written, "Windows backend:") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "selected: windows") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "env filtering: active") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "path staging: active") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "PATH shims: wrapper-only") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "cmd wrapper: partial") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "PowerShell wrapper: partial") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "process cleanup: partial") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "transparent file enforcement: limited") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "transparent network enforcement: limited") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "strong sandbox: unavailable") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "mcp stdio proxy: active") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "audit/replay: active") != null);
}
