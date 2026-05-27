const std = @import("std");
const core = @import("orca_core");

pub const schema_version: u16 = 1;

pub const all_event_types = [_][]const u8{
    "edge.session_start",
    "edge.session_exit",
    "edge.scenario_start",
    "edge.scenario_exit",
    "edge.environment_detected",
    "edge.capability_reported",
    "data.payload_classified",
    "data.payload_redacted",
    "data.egress_requested",
    "data.egress_allowed",
    "data.egress_denied",
    "data.egress_observed",
    "data.exfiltration_suspected",
    "data.endpoint_classified",
    "telemetry.channel_observed",
    "telemetry.channel_allowed",
    "telemetry.channel_denied",
    "link.endpoint_unexpected",
    "link.command_control_observed",
    "link.telemetry_observed",
    "vehicle.state_observed",
    "vehicle.state_stale",
    "vehicle.state_invalid",
    "vehicle.mode_observed",
    "vehicle.battery_observed",
    "vehicle.position_observed",
    "vehicle.command_requested",
    "vehicle.command_mapped",
    "vehicle.command_allowed",
    "vehicle.command_denied",
    "vehicle.command_observed",
    "vehicle.command_forwarded",
    "vehicle.command_blocked",
    "vehicle.command_approval_required",
    "vehicle.command_allowed_by_approval",
    "vehicle.command_denied_missing_approval",
    "safety.evaluation_started",
    "safety.evaluation_completed",
    "safety.finding_created",
    "safety.geofence_violation",
    "safety.altitude_violation",
    "safety.velocity_violation",
    "safety.battery_constraint",
    "safety.stale_state_denied",
    "safety.mode_constraint",
    "safety.authority_constraint",
    "safety.mission_item_denied",
    "operator.approval_requested",
    "operator.approval_granted",
    "operator.approval_denied",
    "operator.approval_expired",
    "operator.approval_revoked",
    "operator.approval_invalid",
    "operator.approval_used",
    "operator.ask_denied_noninteractive",
    "emergency.evaluation_started",
    "emergency.evaluation_completed",
    "emergency.fallback_recommended",
    "emergency.command_allowed",
    "emergency.command_denied",
    "mavlink.frame_received",
    "mavlink.frame_invalid",
    "mavlink.message_classified",
    "mavlink.command_mapped",
    "mavlink.message_forwarded",
    "mavlink.message_blocked",
    "mavlink.mission_upload_started",
    "mavlink.mission_item_observed",
    "mavlink.mission_item_denied",
    "mavlink.mission_upload_completed",
    "mavlink.signing_detected",
    "mavlink.unexpected_endpoint",
    "px4.sitl_detected",
    "px4.scenario_started",
    "px4.scenario_completed",
    "ardupilot.sitl_detected",
    "ardupilot.scenario_started",
    "ardupilot.scenario_completed",
    "safety_case.generated",
    "safety_case.limitation_recorded",
    "safety_case.evidence_collected",
    "safety_case.validation_failed",
    "health.watchdog.finding",
    "health.check_started",
    "health.check_completed",
    "health.status_changed",
    "health.heartbeat_observed",
    "health.heartbeat_expired",
    "health.state_stale",
    "health.state_expired",
    "health.command_timeout",
    "health.command_queue_overflow",
    "health.adapter_degraded",
    "health.link_degraded",
    "health.heartbeat.stale",
    "health.audit.failure",
    "health.audit_writer_failed",
    "health.redaction_failed",
    "health.policy_reload_failed",
    "health.runtime_asset_missing",
    "health.fallback_recommended",
    "health.no_safe_fallback",
    "health.command_denied",
};

pub fn isKnown(event_type: []const u8) bool {
    for (all_event_types) |candidate| {
        if (std.mem.eql(u8, candidate, event_type)) return true;
    }
    return false;
}

pub fn toCoreEventType(event_type: []const u8) !core.event.EventType {
    if (isKnown(event_type)) return .extension_event;
    return error.UnknownEdgeEventType;
}

pub fn eventIdFromSequence(sequence: usize) !core.event.EventId {
    var id: core.event.EventId = .{ .value = undefined, .len = 0 };
    const text = try std.fmt.bufPrint(&id.value, "edge_evt_{d:0>6}", .{sequence});
    id.len = text.len;
    return id;
}

test "phase 33 event names map to Core event types" {
    inline for (all_event_types) |event_type| {
        _ = try toCoreEventType(event_type);
    }
}

test "invalid operator approval events map to Core replay event type" {
    try std.testing.expectEqual(core.event.EventType.extension_event, try toCoreEventType("operator.approval_invalid"));
}
