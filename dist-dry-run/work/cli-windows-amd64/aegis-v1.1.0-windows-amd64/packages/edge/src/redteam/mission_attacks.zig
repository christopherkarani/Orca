const fixture = @import("fixture.zig");

pub const faults = [_]fixture.FaultType{ .mission_item_outside_geofence, .mission_altitude_violation, .partial_mission_upload, .duplicate_mission_item, .missing_mission_item, .unsupported_mission_item, .mission_start_without_safe_mission };

test {
    _ = faults;
}
