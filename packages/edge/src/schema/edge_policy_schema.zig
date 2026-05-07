const domain = @import("../domain/mod.zig");

pub const VehicleProfile = struct {
    kind: domain.vehicle.VehicleKind,
    autopilot: domain.vehicle.AutopilotKind,
    adapter: domain.vehicle.AdapterKind,

    pub fn validate(self: VehicleProfile) !void {
        if (self.kind == .unknown) return error.UnknownStateIsUnsafe;
        if (self.autopilot == .unknown) return error.UnknownStateIsUnsafe;
        if (self.adapter == .unknown) return error.UnknownStateIsUnsafe;
    }
};

pub const AuditPolicy = struct {
    level: enum { full, summary } = .full,
    redact_secrets: bool = true,
};

pub const NetworkPolicy = domain.safety_envelope.NetworkConstraints;

pub const EdgePolicyV1 = struct {
    version: u32 = 1,
    vehicle: VehicleProfile,
    safety: domain.safety_envelope.SafetyEnvelope,
    commands: domain.safety_envelope.CommandPolicy,
    network: NetworkPolicy = .{},
    audit: AuditPolicy = .{},

    pub fn validate(self: EdgePolicyV1) !void {
        if (self.version != 1) return error.UnsupportedSchemaVersion;
        try self.vehicle.validate();
        try self.safety.validate();
        try self.commands.validate();
    }

    pub fn example() EdgePolicyV1 {
        const center = domain.coordinates.GeoPoint{
            .latitude_deg = 37.0,
            .longitude_deg = -122.0,
            .altitude_m = 0,
            .altitude_reference = .amsl,
        };
        return .{
            .vehicle = .{
                .kind = .drone_multirotor,
                .autopilot = .px4,
                .adapter = .fake,
            },
            .safety = .{
                .state_freshness = .{
                    .max_state_age_ms = 1000,
                    .deny_commands_on_stale_state = true,
                },
                .geofence = .{
                    .shape = .{ .circle = .{ .center = center, .max_radius_m = 500 } },
                    .altitude_floor_m = 2,
                    .altitude_ceiling_m = 120,
                    .altitude_reference = .amsl,
                    .boundary_action = .deny,
                },
                .velocity = .{
                    .max_horizontal_mps = 8,
                    .max_vertical_mps = 2,
                },
                .battery = .{
                    .deny_takeoff_below_percent = 35,
                    .return_home_below_percent = 25,
                    .land_below_percent = 15,
                },
            },
            .commands = .{
                .allow = &.{ .read_telemetry, .read_vehicle_state, .land, .return_to_home },
                .ask = &.{ .arm, .takeoff, .upload_mission, .start_mission },
                .deny = &.{ .disable_failsafe, .disable_geofence, .raw_actuator_output, .firmware_update },
            },
        };
    }
};
