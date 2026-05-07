const std = @import("std");
const aegis_core = @import("aegis_core");

pub const phase = "23-product-split-edge-scaffold";
pub const installed_message = "Aegis Edge scaffold is installed. Drone command mediation is not implemented yet.";
pub const core = aegis_core;

pub const CapabilityStatus = enum {
    unavailable,
    scaffolded,
    not_implemented,

    pub fn toString(self: CapabilityStatus) []const u8 {
        return switch (self) {
            .unavailable => "unavailable",
            .scaffolded => "scaffolded",
            .not_implemented => "not implemented",
        };
    }
};

pub const EdgeCapability = enum {
    policy_scaffold,
    fake_adapter,
    command_mediation,
    mavlink_gateway,
    px4_adapter,
    ardupilot_adapter,
    real_flight_enforcement,
    detect_and_avoid,
    regulatory_certification,

    pub fn label(self: EdgeCapability) []const u8 {
        return switch (self) {
            .policy_scaffold => "edge policy scaffold",
            .fake_adapter => "fake adapter scaffold",
            .command_mediation => "drone command mediation",
            .mavlink_gateway => "MAVLink gateway",
            .px4_adapter => "PX4 adapter",
            .ardupilot_adapter => "ArduPilot adapter",
            .real_flight_enforcement => "real-flight enforcement",
            .detect_and_avoid => "detect-and-avoid",
            .regulatory_certification => "regulatory certification",
        };
    }
};

pub const CapabilityReport = struct {
    capability: EdgeCapability,
    status: CapabilityStatus,
    note: []const u8,
};

pub const VehicleState = struct {
    vehicle_id: []const u8,
    armed: bool = false,
    mode: []const u8 = "unknown",
};

pub const CommandRequest = struct {
    vehicle_id: []const u8,
    command: []const u8,
    source: []const u8 = "unknown",
};

pub const SafetyDecisionKind = enum {
    unavailable,
    allow,
    deny,

    pub fn toCoreDecision(self: SafetyDecisionKind) aegis_core.decision.DecisionResult {
        return switch (self) {
            .unavailable => .observe,
            .allow => .allow,
            .deny => .deny,
        };
    }
};

pub const SafetyDecision = struct {
    kind: SafetyDecisionKind,
    reason: []const u8,
    enforced: bool = false,

    pub fn scaffoldUnavailable(reason: []const u8) SafetyDecision {
        return .{ .kind = .unavailable, .reason = reason, .enforced = false };
    }
};

pub const SafetyEnvelope = struct {
    name: []const u8,
    description: []const u8,
    active: bool = false,
};

pub const EdgePolicy = struct {
    name: []const u8 = "edge-scaffold",
    envelope: SafetyEnvelope = .{
        .name = "scaffold",
        .description = "Placeholder safety envelope; real command enforcement is not implemented in Phase 24.",
        .active = false,
    },
};

pub const EdgeAuditEvent = struct {
    event_type: []const u8 = "edge.scaffold",
    vehicle_id: []const u8,
    decision: SafetyDecision,
};

pub const Adapter = struct {
    name: []const u8,
    capabilities: []const CapabilityReport,
};

pub const FakeAdapter = struct {
    pub const name = "fake-edge-adapter";

    pub fn adapter() Adapter {
        return .{
            .name = name,
            .capabilities = FakeAdapter.capabilityReports(),
        };
    }

    pub fn capabilityReports() []const CapabilityReport {
        return &.{
            .{ .capability = .fake_adapter, .status = .scaffolded, .note = "Local fake adapter placeholder only; no hardware IO." },
            .{ .capability = .command_mediation, .status = .not_implemented, .note = "Drone command mediation is deferred to a later phase." },
        };
    }

    pub fn evaluate(_: VehicleState, _: CommandRequest, _: EdgePolicy) SafetyDecision {
        return SafetyDecision.scaffoldUnavailable("Fake adapter does not mediate or enforce drone commands in Phase 24.");
    }
};

pub fn vehicleStateReadAction(vehicle_id: []const u8) aegis_core.actions.Action {
    return .{ .edge_vehicle_state_read = .{ .vehicle_id = vehicle_id } };
}

pub fn evaluateVehicleStateReadThroughCore(
    allocator: std.mem.Allocator,
    selected_policy: *const aegis_core.api.Policy,
    vehicle_id: []const u8,
) !aegis_core.api.Evaluation {
    return aegis_core.api.evaluateAction(allocator, selected_policy, vehicleStateReadAction(vehicle_id), .{});
}

pub fn capabilityReports() []const CapabilityReport {
    return &.{
        .{ .capability = .policy_scaffold, .status = .scaffolded, .note = "Types and package boundaries exist for future Edge policy work." },
        .{ .capability = .fake_adapter, .status = .scaffolded, .note = "Fake adapter is local-only and has no hardware dependency." },
        .{ .capability = .command_mediation, .status = .not_implemented, .note = "Drone command mediation is not implemented yet." },
        .{ .capability = .mavlink_gateway, .status = .not_implemented, .note = "MAVLink is out of scope for Phase 24." },
        .{ .capability = .px4_adapter, .status = .not_implemented, .note = "PX4 integration is out of scope for Phase 24." },
        .{ .capability = .ardupilot_adapter, .status = .not_implemented, .note = "ArduPilot integration is out of scope for Phase 24." },
        .{ .capability = .real_flight_enforcement, .status = .unavailable, .note = "Real-flight behavior requires later simulation, bench, and customer safety validation phases." },
        .{ .capability = .detect_and_avoid, .status = .unavailable, .note = "Aegis Edge is not a detect-and-avoid system." },
        .{ .capability = .regulatory_certification, .status = .unavailable, .note = "Aegis Edge is not regulatory approval or certification." },
    };
}

pub fn doctor(writer: anytype) !void {
    try writer.writeAll(installed_message);
    try writer.writeAll("\n\nCapabilities:\n");
    for (capabilityReports()) |report| {
        try writer.print("  {s}: {s} - {s}\n", .{ report.capability.label(), report.status.toString(), report.note });
    }
}

test {
    _ = core;
    _ = capabilityReports;
    _ = FakeAdapter;
    _ = evaluateVehicleStateReadThroughCore;
}
