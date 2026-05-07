const std = @import("std");
const edge = @import("aegis_edge");

test "edge scaffold exposes domain types without active enforcement claims" {
    const decision = edge.FakeAdapter.evaluate(
        .{ .vehicle_id = "vehicle-1" },
        .{ .vehicle_id = "vehicle-1", .command = "arm" },
        .{},
    );

    try std.testing.expectEqual(edge.SafetyDecisionKind.unavailable, decision.kind);
    try std.testing.expect(!decision.enforced);
    try std.testing.expect(std.mem.indexOf(u8, decision.reason, "does not mediate or enforce") != null);
}

test "edge capabilities report unsupported integrations as unavailable or not implemented" {
    for (edge.capabilityReports()) |report| {
        switch (report.capability) {
            .mavlink_gateway,
            .px4_adapter,
            .ardupilot_adapter,
            .command_mediation,
            => try std.testing.expectEqual(edge.CapabilityStatus.not_implemented, report.status),
            .real_flight_enforcement,
            .detect_and_avoid,
            .regulatory_certification,
            => try std.testing.expectEqual(edge.CapabilityStatus.unavailable, report.status),
            .policy_scaffold,
            .fake_adapter,
            => try std.testing.expectEqual(edge.CapabilityStatus.scaffolded, report.status),
        }
    }
}

test "edge doctor output names scaffold and not implemented states" {
    var buffer: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    try edge.doctor(stream.writer());
    const written = stream.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, written, edge.installed_message) != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "MAVLink gateway: not implemented") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "real-flight enforcement: unavailable") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "regulatory certification: unavailable") != null);
}
