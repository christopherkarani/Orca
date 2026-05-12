const coordinates = @import("coordinates.zig");

pub const MissionId = struct {
    value: []const u8,

    pub fn validate(self: MissionId) !void {
        if (self.value.len == 0) return error.MissingMissionId;
    }
};

pub const MissionStatus = enum {
    unknown,
    draft,
    uploaded,
    active,
    paused,
    completed,
    aborted,
};

pub const Waypoint = struct {
    sequence: u32,
    position: coordinates.GeoPoint,

    pub fn validate(self: Waypoint) !void {
        try self.position.validate();
    }
};

pub const MissionPlan = struct {
    mission_id: MissionId,
    waypoints: []const Waypoint,
    status: MissionStatus = .unknown,

    pub fn validate(self: MissionPlan) !void {
        try self.mission_id.validate();
        if (self.waypoints.len == 0) return error.EmptyMissionPlan;
        for (self.waypoints) |waypoint| try waypoint.validate();
    }
};
