const std = @import("std");

const domain = @import("../domain/mod.zig");
const schema = @import("../schema/mod.zig");
const core = @import("orca_core");

pub const DegradedBehavior = enum {
    observe_only,
    deny_high_risk,
    deny_movement,
    deny_external_egress,
    fail_closed,
    allow_emergency_land_only,
    allow_policy_emergency_only,
    no_safe_action,
    unknown,

    pub fn toString(self: DegradedBehavior) []const u8 {
        return @tagName(self);
    }

    pub fn parse(value: []const u8) ?DegradedBehavior {
        inline for (std.meta.fields(DegradedBehavior)) |field| {
            if (std.mem.eql(u8, field.name, value)) return @field(DegradedBehavior, field.name);
        }
        return null;
    }

    pub fn rank(self: DegradedBehavior) u8 {
        return switch (self) {
            .observe_only => 0,
            .deny_external_egress => 1,
            .deny_high_risk => 2,
            .deny_movement => 3,
            .allow_policy_emergency_only => 4,
            .allow_emergency_land_only => 5,
            .fail_closed => 6,
            .no_safe_action => 7,
            .unknown => 8,
        };
    }

    pub fn stricter(a: DegradedBehavior, b: DegradedBehavior) DegradedBehavior {
        return if (a.rank() >= b.rank()) a else b;
    }
};

pub const EmergencyAllowance = enum {
    deny,
    allow,
    policy,

    pub fn parse(value: []const u8) ?EmergencyAllowance {
        inline for (std.meta.fields(EmergencyAllowance)) |field| {
            if (std.mem.eql(u8, field.name, value)) return @field(EmergencyAllowance, field.name);
        }
        return null;
    }

    pub fn toString(self: EmergencyAllowance) []const u8 {
        return @tagName(self);
    }
};

pub const Decision = struct {
    decision: core.decision.DecisionResult,
    behavior: DegradedBehavior,
    reason: []const u8,
};

pub const Context = struct {
    mode: enum { observe, ask, strict, ci, redteam, simulation, bench } = .strict,
    now_ms: i128,
    non_interactive: bool = false,
};

pub fn isHighRisk(action: domain.commands.CommandAction) bool {
    return switch (domain.risk.classifyCommand(action)) {
        .high, .critical, .unknown => true,
        else => false,
    };
}

pub fn isMovement(action: domain.commands.CommandAction) bool {
    return switch (action) {
        .arm,
        .takeoff,
        .set_waypoint,
        .set_velocity,
        .set_altitude,
        .set_heading,
        .start_mission,
        .upload_mission,
        .set_mode,
        => true,
        else => false,
    };
}

pub fn isNeverSafe(action: domain.commands.CommandAction) bool {
    return switch (action) {
        .disable_failsafe,
        .disable_geofence,
        .raw_actuator_output,
        .override_operator,
        .firmware_update,
        .companion_computer_reboot,
        .payload_release,
        => true,
        else => false,
    };
}

pub fn emergencyDecision(
    policy: *const schema.edge_policy_schema.EdgePolicyV1,
    action: domain.commands.CommandAction,
    state: domain.state.VehicleState,
) ?Decision {
    switch (action) {
        .land => {
            if (policy.watchdog.degraded_mode.allow_emergency_land and policy.safety.emergency.allow_land and policy.commands.resolve(.land) != .deny) {
                return .{ .decision = .allow, .behavior = .allow_policy_emergency_only, .reason = "LAND remains policy-controlled under degraded health" };
            }
            return .{ .decision = .deny, .behavior = .fail_closed, .reason = "LAND disabled by emergency or command policy" };
        },
        .return_to_home => {
            if (state.home_position == null) return .{ .decision = .deny, .behavior = .fail_closed, .reason = "RTH denied without valid home position" };
            if (policy.watchdog.degraded_mode.allow_return_to_home == .policy and policy.safety.emergency.allow_return_to_home and policy.commands.resolve(.return_to_home) != .deny) {
                return .{ .decision = .allow, .behavior = .allow_policy_emergency_only, .reason = "RTH remains policy-controlled under degraded health" };
            }
            if (policy.watchdog.degraded_mode.allow_return_to_home == .allow and policy.commands.resolve(.return_to_home) != .deny) {
                return .{ .decision = .allow, .behavior = .allow_policy_emergency_only, .reason = "RTH allowed by watchdog emergency setting" };
            }
            return .{ .decision = .deny, .behavior = .fail_closed, .reason = "RTH disabled by degraded-mode policy" };
        },
        .hold_position => {
            if (state.position == null or state.control_authority == .unknown) return .{ .decision = .deny, .behavior = .fail_closed, .reason = "HOLD denied without valid position/control context" };
            if (policy.watchdog.degraded_mode.allow_hold == .policy and policy.safety.emergency.allow_hold_position and policy.commands.resolve(.hold_position) != .deny) {
                return .{ .decision = .allow, .behavior = .allow_policy_emergency_only, .reason = "HOLD remains policy-controlled under degraded health" };
            }
            if (policy.watchdog.degraded_mode.allow_hold == .allow and policy.commands.resolve(.hold_position) != .deny) {
                return .{ .decision = .allow, .behavior = .allow_policy_emergency_only, .reason = "HOLD allowed by watchdog emergency setting" };
            }
            return .{ .decision = .deny, .behavior = .fail_closed, .reason = "HOLD disabled by degraded-mode policy" };
        },
        else => return null,
    }
}
