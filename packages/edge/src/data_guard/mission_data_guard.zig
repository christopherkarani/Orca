const data_classification = @import("data_classification.zig");

pub fn classesForMissionUpload() []const data_classification.DataClass {
    return &.{ .mission_plan, .geolocation, .vehicle_identifier };
}

pub fn classesForVehicleState() []const data_classification.DataClass {
    return &.{ .vehicle_state, .geolocation, .vehicle_identifier };
}
