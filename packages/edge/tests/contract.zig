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
            .px4_adapter,
            => try std.testing.expectEqual(edge.CapabilityStatus.partial, report.status),
            .ardupilot_adapter,
            => try std.testing.expectEqual(edge.CapabilityStatus.partial, report.status),
            .command_mediation,
            => try std.testing.expectEqual(edge.CapabilityStatus.active, report.status),
            .mavlink_gateway,
            => try std.testing.expectEqual(edge.CapabilityStatus.active, report.status),
            .flight_safety_enforcement,
            => try std.testing.expectEqual(edge.CapabilityStatus.active, report.status),
            .operator_approval,
            => try std.testing.expectEqual(edge.CapabilityStatus.active, report.status),
            .emergency_modes,
            .audit_replay,
            .safety_case_reports,
            .evidence_bundles,
            .redteam_fault_injection,
            .data_network_guard,
            => try std.testing.expectEqual(edge.CapabilityStatus.active, report.status),
            .real_flight_enforcement,
            .detect_and_avoid,
            .regulatory_certification,
            => try std.testing.expectEqual(edge.CapabilityStatus.unavailable, report.status),
            .policy_scaffold,
            => try std.testing.expectEqual(edge.CapabilityStatus.scaffolded, report.status),
            .fake_adapter,
            => try std.testing.expectEqual(edge.CapabilityStatus.active, report.status),
            .policy_evaluation,
            => try std.testing.expectEqual(edge.CapabilityStatus.active, report.status),
        }
    }
}

test "edge doctor output names scaffold and not implemented states" {
    var buffer: [8192]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    try edge.doctor(stream.writer());
    const written = stream.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, written, edge.installed_message) != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "MAVLink gateway: active") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "real-flight enforcement: unavailable") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "regulatory certification: unavailable") != null);
}

test "edge package calls Core policy audit and redaction APIs for placeholder actions" {
    var selected = try edge.core.api.parsePolicyFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: observe
    , "edge-core-import.yaml");
    defer selected.deinit();

    var evaluation = try edge.evaluateVehicleStateReadThroughCore(std.testing.allocator, &selected, "vehicle-1");
    defer evaluation.deinit(std.testing.allocator);
    try std.testing.expectEqual(edge.core.decision.DecisionResult.observe, evaluation.decision.result);
    try std.testing.expect(std.mem.indexOf(u8, evaluation.explanation, "edge.vehicle_state_read") != null);

    var redaction_buffer: [128]u8 = undefined;
    const redacted = edge.core.api.redactStringBounded("EDGE_FAKE_TOKEN=fake_secret_value_phase24", &redaction_buffer);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "fake_secret_value_phase24") == null);

    const ts = edge.core.core.time.Timestamp.fromUnixSeconds(1_777_983_130);
    const session_id = try edge.core.core.session.generateSessionId(ts);
    const event = try edge.core.api.createAuditEvent(.{
        .session_id = session_id,
        .event_id = try edge.core.core.event.generateEventId(ts),
        .timestamp = ts,
        .event_type = .mcp_tool_call,
        .actor = .{ .kind = .aegis, .display = "aegis-edge" },
        .target = .{ .kind = .edge_vehicle_state, .value = "vehicle-1" },
        .decision = evaluation.decision,
    });
    try std.testing.expectEqual(edge.core.core.types.TargetKind.edge_vehicle_state, event.target.kind);
}
