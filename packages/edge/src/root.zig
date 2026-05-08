const std = @import("std");
const aegis_core = @import("aegis_core");

pub const domain = @import("domain/mod.zig");
pub const mavlink = @import("mavlink/mod.zig");
pub const policy = @import("policy/mod.zig");
pub const safety = @import("safety/mod.zig");
pub const operator = @import("operator/mod.zig");
pub const emergency = @import("emergency/mod.zig");
pub const audit = @import("audit/mod.zig");
pub const px4 = @import("px4/mod.zig");
pub const ardupilot = @import("ardupilot/mod.zig");
pub const schema = @import("schema/mod.zig");
pub const redteam = @import("redteam/mod.zig");

pub const phase = "34-edge-redteam-and-fault-injection";
pub const installed_message = "Aegis Edge red-team and fault-injection evidence generation is installed for deterministic fake-adapter, PX4 SITL, and ArduPilot SITL evaluation evidence only; it is not ready for real flight.";
pub const core = aegis_core;

pub const CapabilityStatus = enum {
    active,
    partial,
    unavailable,
    scaffolded,
    not_implemented,

    pub fn toString(self: CapabilityStatus) []const u8 {
        return switch (self) {
            .active => "active",
            .partial => "partial",
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
    policy_evaluation,
    mavlink_gateway,
    flight_safety_enforcement,
    operator_approval,
    emergency_modes,
    audit_replay,
    safety_case_reports,
    evidence_bundles,
    redteam_fault_injection,
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
            .policy_evaluation => "edge policy evaluation",
            .mavlink_gateway => "MAVLink gateway",
            .flight_safety_enforcement => "flight safety enforcement",
            .operator_approval => "operator approval",
            .emergency_modes => "emergency modes",
            .audit_replay => "Edge audit/replay",
            .safety_case_reports => "safety-case reports",
            .evidence_bundles => "evidence bundles",
            .redteam_fault_injection => "red-team and fault injection",
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
            .{ .capability = .command_mediation, .status = .active, .note = "MAVLink command mediation exists for fake/in-memory gateway tests only; no real endpoints." },
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
        .{ .capability = .policy_scaffold, .status = .scaffolded, .note = "Phase 26 domain types and versioned safety schema descriptors exist for Edge policy work." },
        .{ .capability = .policy_evaluation, .status = .active, .note = "Phase 27 evaluates Edge policy decisions locally for fake/simulation/bench evidence." },
        .{ .capability = .fake_adapter, .status = .active, .note = "Deterministic fake MAVLink transport is available for local tests and examples only." },
        .{ .capability = .command_mediation, .status = .active, .note = "Phase 28 maps supported MAVLink commands through policy in fake gateway mode; no real endpoints." },
        .{ .capability = .mavlink_gateway, .status = .active, .note = "MAVLink v1/v2 parsing, classification, mapping, mission tracking, and gateway decisions are active for simulation/protocol mediation." },
        .{ .capability = .flight_safety_enforcement, .status = .active, .note = "Phase 31 evaluates commands and mission plans against geofence, altitude, velocity, battery, freshness, mode, authority, and command-risk constraints for fake/SITL evidence only." },
        .{ .capability = .operator_approval, .status = .active, .note = "Phase 32 creates and validates bounded local operator approvals for fake/SITL/bench-preparation contexts; CI and red-team modes deny ask decisions without prompting." },
        .{ .capability = .emergency_modes, .status = .active, .note = "Phase 32 evaluates policy-controlled LAND/HOLD/RTH emergency fallback decisions in fake/SITL contexts only; it does not send real hardware commands." },
        .{ .capability = .audit_replay, .status = .active, .note = "Phase 33 records hash-chained Edge sessions through the Aegis Core audit writer under .aegis-edge and replays them with Core verification." },
        .{ .capability = .safety_case_reports, .status = .active, .note = "Phase 33 generates bounded JSON and Markdown safety-case reports for fake/SITL/bench-preparation evaluation evidence with explicit non-certification limitations." },
        .{ .capability = .evidence_bundles, .status = .active, .note = "Phase 33 creates local directory evidence bundles with policy/scenario copies, reports, replay, findings, commands, limitations, hashes, and provenance." },
        .{ .capability = .redteam_fault_injection, .status = .active, .note = "Phase 34 runs deterministic simulation-only Edge red-team fixtures and fault injections with scorecards, redacted audit/replay artifacts, and safety-case evidence; no real hardware or real-flight claims." },
        .{ .capability = .px4_adapter, .status = .partial, .note = "PX4 SITL adapter supports opt-in local simulation checks plus deterministic fake-PX4 scenarios; no hardware or real-flight support." },
        .{ .capability = .ardupilot_adapter, .status = .partial, .note = "ArduPilot SITL adapter supports opt-in local simulation checks plus deterministic fake-ArduPilot scenarios; Copter-oriented coverage starts Phase 30; no hardware or real-flight support." },
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
    try writer.writeAll("\nPX4:\n");
    try px4.health.writeDoctor(writer, .{});
    try writer.writeAll("\nArduPilot:\n");
    try ardupilot.health.writeDoctor(writer, .{});
}

test {
    _ = ardupilot;
    _ = core;
    _ = domain;
    _ = mavlink;
    _ = operator;
    _ = emergency;
    _ = audit;
    _ = policy;
    _ = safety;
    _ = px4;
    _ = schema;
    _ = redteam;
    _ = capabilityReports;
    _ = FakeAdapter;
    _ = evaluateVehicleStateReadThroughCore;
}
