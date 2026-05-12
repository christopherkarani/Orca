pub const VehicleId = struct {
    value: []const u8,

    pub fn validate(self: VehicleId) !void {
        if (self.value.len == 0) return error.MissingVehicleId;
    }
};

pub const VehicleKind = enum {
    drone_multirotor,
    drone_fixed_wing,
    drone_vtol,
    ground_robot,
    simulated_vehicle,
    unknown,
};

pub const AutopilotKind = enum {
    px4,
    ardupilot,
    fake,
    custom,
    unknown,
};

pub const AdapterKind = enum {
    fake,
    mavlink,
    ros2,
    custom,
    unknown,
};

pub const VehicleMode = enum {
    unknown,
    manual,
    stabilized,
    guided,
    offboard,
    auto,
    mission,
    return_to_home,
    land,
    hold,
    emergency,
};

pub const ArmState = enum {
    armed,
    disarmed,
    unknown,
};

pub const ControlAuthority = enum {
    human_operator,
    onboard_agent,
    ground_station,
    failsafe,
    unknown,
};
