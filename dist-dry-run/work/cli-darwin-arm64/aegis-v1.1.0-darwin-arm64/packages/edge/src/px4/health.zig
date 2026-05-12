const std = @import("std");

const connection = @import("connection.zig");

pub const DoctorOptions = struct {
    config: connection.Config = .{},
    gate: ?connection.IntegrationGate = null,
};

pub fn writeDoctor(writer: anytype, options: DoctorOptions) !void {
    const gate = options.gate orelse connection.integrationTestGate(.{ .run_px4_sitl_tests = null, .endpoint = null });
    const report = connection.health(options.config, gate);
    try writer.print("PX4 SITL support: {s}\n", .{report.support.toString()});
    try writer.print("Configured endpoint: {s}:{d} ({s})\n", .{ options.config.endpoint.host, options.config.endpoint.port, options.config.protocol.toString() });
    try writer.print("Local bind: {s}:{d}\n", .{ options.config.local_bind.host, options.config.local_bind.port });
    try writer.print("Mode default: {s}\n", .{options.config.mode.toString()});
    try writer.print("Endpoint reachable: {s}\n", .{if (report.endpoint_reachable) |reachable| if (reachable) "yes" else "no" else "not checked"});
    try writer.print("Tested PX4 version: {s}\n", .{options.config.tested_version});
    try writer.writeAll("MAVLink gateway support: active for policy-mediated simulation and configured SITL messages\n");
    try writer.writeAll("Offboard/control mediation: partial - supported mapped MAVLink commands are evaluated through Edge policy; unsupported commands fail closed\n");
    try writer.writeAll("fake adapter: active - deterministic fake-PX4 fixtures and scenarios use fake_adapter provenance\n");
    try writer.writeAll("SITL integration tests: opt-in with AEGIS_EDGE_RUN_PX4_SITL_TESTS=1 and AEGIS_EDGE_PX4_ENDPOINT\n");
    try writer.print("SITL integration-test availability: {s}\n", .{@tagName(gate.availability)});
    try writer.print("Status note: {s}\n", .{report.reason});
    try writer.writeAll("Limitations: simulation-only; no real hardware support, no real-flight readiness, no autopilot replacement, no detect-and-avoid capability, no regulatory approval or certification.\n");
}
