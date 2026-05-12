const std = @import("std");
const domain = @import("../domain/mod.zig");

const MAV_TYPE_FIXED_WING: u8 = 1;
const MAV_TYPE_QUADROTOR: u8 = 2;
const MAV_TYPE_HELICOPTER: u8 = 4;
const MAV_TYPE_HEXAROTOR: u8 = 13;
const MAV_TYPE_OCTOROTOR: u8 = 14;
const MAV_TYPE_TRICOPTER: u8 = 15;
const MAV_TYPE_GROUND_ROVER: u8 = 10;
const MAV_TYPE_SUBMARINE: u8 = 12;

pub const VehicleKind = enum {
    copter,
    plane,
    rover,
    sub,
    unknown,

    pub fn parse(value: []const u8) !VehicleKind {
        return std.meta.stringToEnum(VehicleKind, value) orelse error.UnsupportedArduPilotVehicle;
    }

    pub fn toString(self: VehicleKind) []const u8 {
        return @tagName(self);
    }

    pub fn toDomainKind(self: VehicleKind) domain.vehicle.VehicleKind {
        return switch (self) {
            .copter => .drone_multirotor,
            .plane => .drone_fixed_wing,
            .rover => .ground_robot,
            .sub => .simulated_vehicle,
            .unknown => .unknown,
        };
    }
};

pub fn fromHeartbeatType(mav_type: u8) VehicleKind {
    return switch (mav_type) {
        MAV_TYPE_QUADROTOR,
        MAV_TYPE_HELICOPTER,
        MAV_TYPE_HEXAROTOR,
        MAV_TYPE_OCTOROTOR,
        MAV_TYPE_TRICOPTER,
        => .copter,
        MAV_TYPE_FIXED_WING => .plane,
        MAV_TYPE_GROUND_ROVER => .rover,
        MAV_TYPE_SUBMARINE => .sub,
        else => .unknown,
    };
}

pub fn mavTypeFor(vehicle: VehicleKind) u8 {
    return switch (vehicle) {
        .copter => MAV_TYPE_QUADROTOR,
        .plane => MAV_TYPE_FIXED_WING,
        .rover => MAV_TYPE_GROUND_ROVER,
        .sub => MAV_TYPE_SUBMARINE,
        .unknown => 0,
    };
}
