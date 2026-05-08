const std = @import("std");

const domain = @import("../domain/mod.zig");

pub const ApprovalScopeKind = enum {
    exact_action_only,
    command_type,
    mission_id,
    scenario_id,
    vehicle_id,
    time_window,
};

pub const ApprovalScope = struct {
    kind: ApprovalScopeKind = .exact_action_only,
    command_type: domain.commands.CommandAction,
    vehicle_id: []u8,
    mission_id: ?[]u8 = null,
    scenario_id: ?[]u8 = null,
    not_before_ms: ?i128 = null,
    expires_at_ms: i128,
    max_uses: u32 = 1,
    safety_constraints_hash: []u8,
    policy_hash: []u8,
    state_snapshot_hash: []u8,
    command_request_hash: []u8,

    pub fn exact(
        allocator: std.mem.Allocator,
        command: domain.commands.CommandRequest,
        expires_at_ms: i128,
        max_uses: u32,
        policy_hash: []const u8,
        state_snapshot_hash: []const u8,
        safety_constraints_hash: []const u8,
        command_request_hash: []const u8,
    ) !ApprovalScope {
        return .{
            .kind = .exact_action_only,
            .command_type = command.action,
            .vehicle_id = try allocator.dupe(u8, command.vehicle_id.value),
            .mission_id = if (command.mission_id) |mission| try allocator.dupe(u8, mission) else null,
            .expires_at_ms = expires_at_ms,
            .max_uses = if (max_uses == 0) 1 else max_uses,
            .safety_constraints_hash = try allocator.dupe(u8, safety_constraints_hash),
            .policy_hash = try allocator.dupe(u8, policy_hash),
            .state_snapshot_hash = try allocator.dupe(u8, state_snapshot_hash),
            .command_request_hash = try allocator.dupe(u8, command_request_hash),
        };
    }

    pub fn clone(self: ApprovalScope, allocator: std.mem.Allocator) !ApprovalScope {
        return .{
            .kind = self.kind,
            .command_type = self.command_type,
            .vehicle_id = try allocator.dupe(u8, self.vehicle_id),
            .mission_id = if (self.mission_id) |mission| try allocator.dupe(u8, mission) else null,
            .scenario_id = if (self.scenario_id) |scenario| try allocator.dupe(u8, scenario) else null,
            .not_before_ms = self.not_before_ms,
            .expires_at_ms = self.expires_at_ms,
            .max_uses = self.max_uses,
            .safety_constraints_hash = try allocator.dupe(u8, self.safety_constraints_hash),
            .policy_hash = try allocator.dupe(u8, self.policy_hash),
            .state_snapshot_hash = try allocator.dupe(u8, self.state_snapshot_hash),
            .command_request_hash = try allocator.dupe(u8, self.command_request_hash),
        };
    }

    pub fn deinit(self: *ApprovalScope, allocator: std.mem.Allocator) void {
        allocator.free(self.vehicle_id);
        if (self.mission_id) |mission| allocator.free(mission);
        if (self.scenario_id) |scenario| allocator.free(scenario);
        allocator.free(self.safety_constraints_hash);
        allocator.free(self.policy_hash);
        allocator.free(self.state_snapshot_hash);
        allocator.free(self.command_request_hash);
        self.* = undefined;
    }
};
