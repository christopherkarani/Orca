const coordinates = @import("coordinates.zig");
const commands = @import("commands.zig");
const geofence_mod = @import("geofence.zig");

pub const AltitudeLimits = struct {
    min_altitude_m: f64,
    max_altitude_m: f64,
    altitude_reference: coordinates.AltitudeReference,

    pub fn validate(self: AltitudeLimits) !void {
        if (self.altitude_reference == .unknown) return error.UnknownAltitudeReference;
        if (self.max_altitude_m < self.min_altitude_m) return error.InvalidAltitudeLimit;
    }
};

pub const VelocityLimits = struct {
    max_horizontal_mps: f64,
    max_vertical_mps: f64,

    pub fn validate(self: VelocityLimits) !void {
        if (self.max_horizontal_mps < 0 or self.max_vertical_mps < 0) return error.InvalidSpeedLimit;
    }
};

pub const BatteryPolicy = struct {
    deny_takeoff_below_percent: f64,
    return_home_below_percent: f64,
    land_below_percent: f64,
    require_fresh_battery_state: bool = true,

    pub fn validate(self: BatteryPolicy) !void {
        if (self.deny_takeoff_below_percent < 0 or self.deny_takeoff_below_percent > 100) return error.InvalidBatteryThreshold;
        if (self.return_home_below_percent < 0 or self.return_home_below_percent > 100) return error.InvalidBatteryThreshold;
        if (self.land_below_percent < 0 or self.land_below_percent > 100) return error.InvalidBatteryThreshold;
        if (!(self.deny_takeoff_below_percent >= self.return_home_below_percent and self.return_home_below_percent >= self.land_below_percent)) {
            return error.InvalidBatteryThreshold;
        }
    }
};

pub const StateFreshnessPolicy = struct {
    max_state_age_ms: u64,
    deny_commands_on_stale_state: bool = true,
    allow_emergency_land_on_stale_state: bool = true,

    pub fn validate(self: StateFreshnessPolicy) !void {
        if (self.max_state_age_ms == 0) return error.InvalidStateFreshnessPolicy;
    }
};

pub const CommandDisposition = enum {
    allow,
    ask,
    deny,
    require_operator_approval,
    unspecified,
};

pub const CommandPolicy = struct {
    allow: []const commands.CommandAction = &.{},
    ask: []const commands.CommandAction = &.{},
    deny: []const commands.CommandAction = &.{},
    require_operator_approval: []const commands.CommandAction = &.{},

    pub fn validate(self: CommandPolicy) !void {
        for (commands.CommandAction.all()) |action| {
            var count: u8 = 0;
            if (contains(self.allow, action)) count += 1;
            if (contains(self.ask, action)) count += 1;
            if (contains(self.deny, action)) count += 1;
            if (contains(self.require_operator_approval, action)) count += 1;
            if (count > 1) return error.DuplicateCommandPolicyEntry;
        }
    }

    /// Deny wins if callers intentionally skip validation and need a fail-closed answer.
    pub fn resolve(self: CommandPolicy, action: commands.CommandAction) CommandDisposition {
        if (contains(self.deny, action)) return .deny;
        if (contains(self.require_operator_approval, action)) return .require_operator_approval;
        if (contains(self.ask, action)) return .ask;
        if (contains(self.allow, action)) return .allow;
        return .unspecified;
    }

    fn contains(list: []const commands.CommandAction, action: commands.CommandAction) bool {
        for (list) |candidate| {
            if (candidate == action) return true;
        }
        return false;
    }
};

pub const ModeConstraints = struct {
    allowed_modes: []const @import("vehicle.zig").VehicleMode = &.{},
    denied_modes: []const @import("vehicle.zig").VehicleMode = &.{},
};

pub const NetworkConstraints = struct {
    mode: enum { allowlist, denylist, offline } = .allowlist,
};

pub const EmergencyBehaviorConstraints = struct {
    allow_land: bool = true,
    allow_return_to_home: bool = true,
};

pub const SafetyEnvelope = struct {
    geofence: ?geofence_mod.Geofence = null,
    altitude: ?AltitudeLimits = null,
    velocity: ?VelocityLimits = null,
    battery: ?BatteryPolicy = null,
    state_freshness: ?StateFreshnessPolicy = null,
    commands: CommandPolicy = .{},
    network: NetworkConstraints = .{},
    emergency: EmergencyBehaviorConstraints = .{},

    pub fn validate(self: SafetyEnvelope) !void {
        if (self.geofence) |geofence| try geofence.validate();
        if (self.altitude) |altitude| try altitude.validate();
        if (self.velocity) |velocity| try velocity.validate();
        if (self.battery) |battery| try battery.validate();
        if (self.state_freshness) |freshness| try freshness.validate();
        try self.commands.validate();
    }
};
