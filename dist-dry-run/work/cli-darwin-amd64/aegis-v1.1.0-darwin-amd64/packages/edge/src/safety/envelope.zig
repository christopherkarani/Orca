const std = @import("std");

const domain = @import("../domain/mod.zig");
const schema = @import("../schema/mod.zig");

pub const RuleRef = struct {
    id: []u8,
    description: []u8,

    fn deinit(self: RuleRef, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.description);
    }
};

pub const UnsupportedFeature = struct {
    id: []u8,
    reason: []u8,

    fn deinit(self: UnsupportedFeature, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.reason);
    }
};

pub const CompiledEnvelope = struct {
    allocator: std.mem.Allocator,
    geofence_count: usize = 0,
    altitude_limits_present: bool = false,
    velocity_limits_present: bool = false,
    battery_policy_present: bool = false,
    freshness_policy_present: bool = false,
    rules: []RuleRef = &.{},
    unsupported_features: []UnsupportedFeature = &.{},

    pub fn deinit(self: *CompiledEnvelope) void {
        for (self.rules) |rule| rule.deinit(self.allocator);
        self.allocator.free(self.rules);
        for (self.unsupported_features) |feature| feature.deinit(self.allocator);
        self.allocator.free(self.unsupported_features);
        self.* = undefined;
    }

    pub fn hasRule(self: CompiledEnvelope, id: []const u8) bool {
        for (self.rules) |rule| {
            if (std.mem.eql(u8, rule.id, id)) return true;
        }
        return false;
    }

    pub fn hasUnsupportedFeature(self: CompiledEnvelope, id: []const u8) bool {
        for (self.unsupported_features) |feature| {
            if (std.mem.eql(u8, feature.id, id)) return true;
        }
        return false;
    }
};

pub fn compileEnvelope(
    allocator: std.mem.Allocator,
    policy: *const schema.edge_policy_schema.EdgePolicyV1,
) !CompiledEnvelope {
    try policy.validate();

    var rules: std.ArrayList(RuleRef) = .empty;
    errdefer {
        for (rules.items) |rule| rule.deinit(allocator);
        rules.deinit(allocator);
    }
    try appendCommandRules(allocator, &rules, "commands.allow", policy.commands.allow);
    try appendCommandRules(allocator, &rules, "commands.ask", policy.commands.ask);
    try appendCommandRules(allocator, &rules, "commands.deny", policy.commands.deny);
    try appendCommandRules(allocator, &rules, "commands.require_operator_approval", policy.commands.require_operator_approval);

    var unsupported: std.ArrayList(UnsupportedFeature) = .empty;
    errdefer {
        for (unsupported.items) |feature| feature.deinit(allocator);
        unsupported.deinit(allocator);
    }

    var geofence_count: usize = 0;
    if (policy.safety.geofence) |geofence| {
        switch (geofence.shape) {
            .circle => geofence_count = 1,
            .allowed_polygon => {
                try unsupported.append(allocator, .{
                    .id = try allocator.dupe(u8, "polygon_geofence"),
                    .reason = try allocator.dupe(u8, "polygon geofences are reported as unsupported in Phase 31"),
                });
                return error.UnsupportedGeofenceShape;
            },
        }
    }

    return .{
        .allocator = allocator,
        .geofence_count = geofence_count,
        .altitude_limits_present = policy.safety.altitude != null or policy.safety.geofence != null,
        .velocity_limits_present = policy.safety.velocity != null,
        .battery_policy_present = policy.safety.battery != null,
        .freshness_policy_present = policy.safety.state_freshness != null,
        .rules = try rules.toOwnedSlice(allocator),
        .unsupported_features = try unsupported.toOwnedSlice(allocator),
    };
}

fn appendCommandRules(
    allocator: std.mem.Allocator,
    rules: *std.ArrayList(RuleRef),
    section: []const u8,
    actions: []const domain.commands.CommandAction,
) !void {
    for (actions, 0..) |action, index| {
        try rules.append(allocator, .{
            .id = try std.fmt.allocPrint(allocator, "{s}[{d}]", .{ section, index }),
            .description = try std.fmt.allocPrint(allocator, "{s} -> {s}", .{ section, @tagName(action) }),
        });
    }
}

