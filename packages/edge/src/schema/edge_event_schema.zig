const std = @import("std");

pub const event_types = [_][]const u8{
    "edge.session_start",
    "edge.session_exit",
    "vehicle.state_observed",
    "vehicle.command_requested",
    "vehicle.command_allowed",
    "vehicle.command_denied",
    "vehicle.command_approval_required",
    "safety.geofence_violation",
    "safety.altitude_violation",
    "safety.velocity_violation",
    "safety.stale_state_denied",
    "safety.battery_constraint",
    "safety.mode_constraint",
    "safety.authority_constraint",
    "safety.evaluation_started",
    "safety.evaluation_completed",
    "safety.finding_created",
    "safety.command_risk_denied",
    "safety.mission_item_denied",
    "emergency.land_allowed",
    "emergency.return_home_allowed",
    "adapter.message_received",
    "adapter.message_forwarded",
    "adapter.message_denied",
    "mavlink.frame_received",
    "mavlink.frame_invalid",
    "mavlink.message_classified",
    "mavlink.command_mapped",
    "mavlink.command_allowed",
    "mavlink.command_denied",
    "mavlink.command_observed",
    "mavlink.message_forwarded",
    "mavlink.message_blocked",
    "mavlink.mission_upload_started",
    "mavlink.mission_item_observed",
    "mavlink.mission_item_denied",
    "mavlink.mission_upload_completed",
    "mavlink.signing_detected",
    "mavlink.unexpected_endpoint",
};

pub const EdgeEventV1 = struct {
    version: u32 = 1,
    event_type: []const u8,
    timestamp_ms: i128,
    vehicle_id: ?[]const u8 = null,
    correlation_id: ?[]const u8 = null,

    pub fn validate(self: EdgeEventV1) !void {
        if (self.version != 1) return error.UnsupportedSchemaVersion;
        if (!hasEventType(self.event_type)) return error.UnknownEdgeEventType;
        if (self.timestamp_ms == 0) return error.MissingTimestamp;
    }
};

pub fn hasEventType(value: []const u8) bool {
    for (event_types) |event_type| {
        if (std.mem.eql(u8, event_type, value)) return true;
    }
    return false;
}
