const std = @import("std");
const core = @import("aegis_core");

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
    "health.heartbeat.stale",
    "health.audit.failure",
    "health.command_denied",
};

pub fn isKnown(event_type: []const u8) bool {
    for (all_event_types) |candidate| {
        if (std.mem.eql(u8, candidate, event_type)) return true;
    }
    return false;
}

pub fn toCoreEventType(event_type: []const u8) !core.event.EventType {
    if (std.mem.eql(u8, event_type, "edge.session_start")) return .edge_session_start;
    if (std.mem.eql(u8, event_type, "edge.session_exit")) return .edge_session_exit;
    if (std.mem.eql(u8, event_type, "edge.scenario_start")) return .edge_scenario_start;
    if (std.mem.eql(u8, event_type, "edge.scenario_exit")) return .edge_scenario_exit;
    if (std.mem.eql(u8, event_type, "edge.environment_detected")) return .edge_environment_detected;
    if (std.mem.eql(u8, event_type, "edge.capability_reported")) return .edge_capability_reported;
    if (std.mem.eql(u8, event_type, "data.payload_classified")) return .data_payload_classified;
    if (std.mem.eql(u8, event_type, "data.payload_redacted")) return .data_payload_redacted;
    if (std.mem.eql(u8, event_type, "data.egress_requested")) return .data_egress_requested;
    if (std.mem.eql(u8, event_type, "data.egress_allowed")) return .data_egress_allowed;
    if (std.mem.eql(u8, event_type, "data.egress_denied")) return .data_egress_denied;
    if (std.mem.eql(u8, event_type, "data.egress_observed")) return .data_egress_observed;
    if (std.mem.eql(u8, event_type, "data.exfiltration_suspected")) return .data_exfiltration_suspected;
    if (std.mem.eql(u8, event_type, "data.endpoint_classified")) return .data_endpoint_classified;
    if (std.mem.eql(u8, event_type, "telemetry.channel_observed")) return .telemetry_channel_observed;
    if (std.mem.eql(u8, event_type, "telemetry.channel_allowed")) return .telemetry_channel_allowed;
    if (std.mem.eql(u8, event_type, "telemetry.channel_denied")) return .telemetry_channel_denied;
    if (std.mem.eql(u8, event_type, "link.endpoint_unexpected")) return .link_endpoint_unexpected;
    if (std.mem.eql(u8, event_type, "link.command_control_observed")) return .link_command_control_observed;
    if (std.mem.eql(u8, event_type, "link.telemetry_observed")) return .link_telemetry_observed;
    if (std.mem.eql(u8, event_type, "vehicle.state_observed")) return .vehicle_state_observed;
    if (std.mem.eql(u8, event_type, "vehicle.state_stale")) return .vehicle_state_stale;
    if (std.mem.eql(u8, event_type, "vehicle.state_invalid")) return .vehicle_state_invalid;
    if (std.mem.eql(u8, event_type, "vehicle.mode_observed")) return .vehicle_mode_observed;
    if (std.mem.eql(u8, event_type, "vehicle.battery_observed")) return .vehicle_battery_observed;
    if (std.mem.eql(u8, event_type, "vehicle.position_observed")) return .vehicle_position_observed;
    if (std.mem.eql(u8, event_type, "vehicle.command_requested")) return .vehicle_command_requested;
    if (std.mem.eql(u8, event_type, "vehicle.command_mapped")) return .vehicle_command_mapped;
    if (std.mem.eql(u8, event_type, "vehicle.command_allowed")) return .vehicle_command_allowed;
    if (std.mem.eql(u8, event_type, "vehicle.command_denied")) return .vehicle_command_denied;
    if (std.mem.eql(u8, event_type, "vehicle.command_observed")) return .vehicle_command_observed;
    if (std.mem.eql(u8, event_type, "vehicle.command_forwarded")) return .vehicle_command_forwarded;
    if (std.mem.eql(u8, event_type, "vehicle.command_blocked")) return .vehicle_command_blocked;
    if (std.mem.eql(u8, event_type, "vehicle.command_approval_required")) return .vehicle_command_approval_required;
    if (std.mem.eql(u8, event_type, "vehicle.command_allowed_by_approval")) return .vehicle_command_allowed_by_approval;
    if (std.mem.eql(u8, event_type, "vehicle.command_denied_missing_approval")) return .vehicle_command_denied_missing_approval;
    if (std.mem.eql(u8, event_type, "safety.evaluation_started")) return .safety_evaluation_started;
    if (std.mem.eql(u8, event_type, "safety.evaluation_completed")) return .safety_evaluation_completed;
    if (std.mem.eql(u8, event_type, "safety.finding_created")) return .safety_finding_created;
    if (std.mem.eql(u8, event_type, "safety.geofence_violation")) return .safety_geofence_violation;
    if (std.mem.eql(u8, event_type, "safety.altitude_violation")) return .safety_altitude_violation;
    if (std.mem.eql(u8, event_type, "safety.velocity_violation")) return .safety_velocity_violation;
    if (std.mem.eql(u8, event_type, "safety.battery_constraint")) return .safety_battery_constraint;
    if (std.mem.eql(u8, event_type, "safety.stale_state_denied")) return .safety_stale_state_denied;
    if (std.mem.eql(u8, event_type, "safety.mode_constraint")) return .safety_mode_constraint;
    if (std.mem.eql(u8, event_type, "safety.authority_constraint")) return .safety_authority_constraint;
    if (std.mem.eql(u8, event_type, "safety.mission_item_denied")) return .safety_mission_item_denied;
    if (std.mem.eql(u8, event_type, "operator.approval_requested")) return .operator_approval_requested;
    if (std.mem.eql(u8, event_type, "operator.approval_granted")) return .operator_approval_granted;
    if (std.mem.eql(u8, event_type, "operator.approval_denied")) return .operator_approval_denied;
    if (std.mem.eql(u8, event_type, "operator.approval_expired")) return .operator_approval_expired;
    if (std.mem.eql(u8, event_type, "operator.approval_revoked")) return .operator_approval_revoked;
    if (std.mem.eql(u8, event_type, "operator.approval_invalid")) return .operator_approval_invalid;
    if (std.mem.eql(u8, event_type, "operator.approval_used")) return .operator_approval_used;
    if (std.mem.eql(u8, event_type, "operator.ask_denied_noninteractive")) return .operator_ask_denied_noninteractive;
    if (std.mem.eql(u8, event_type, "emergency.evaluation_started")) return .emergency_evaluation_started;
    if (std.mem.eql(u8, event_type, "emergency.evaluation_completed")) return .emergency_evaluation_completed;
    if (std.mem.eql(u8, event_type, "emergency.fallback_recommended")) return .emergency_fallback_recommended;
    if (std.mem.eql(u8, event_type, "emergency.command_allowed")) return .emergency_command_allowed;
    if (std.mem.eql(u8, event_type, "emergency.command_denied")) return .emergency_command_denied;
    if (std.mem.eql(u8, event_type, "mavlink.frame_received")) return .mavlink_frame_received;
    if (std.mem.eql(u8, event_type, "mavlink.frame_invalid")) return .mavlink_frame_invalid;
    if (std.mem.eql(u8, event_type, "mavlink.message_classified")) return .mavlink_message_classified;
    if (std.mem.eql(u8, event_type, "mavlink.command_mapped")) return .mavlink_command_mapped;
    if (std.mem.eql(u8, event_type, "mavlink.message_forwarded")) return .mavlink_message_forwarded;
    if (std.mem.eql(u8, event_type, "mavlink.message_blocked")) return .mavlink_message_blocked;
    if (std.mem.eql(u8, event_type, "mavlink.mission_upload_started")) return .mavlink_mission_upload_started;
    if (std.mem.eql(u8, event_type, "mavlink.mission_item_observed")) return .mavlink_mission_item_observed;
    if (std.mem.eql(u8, event_type, "mavlink.mission_item_denied")) return .mavlink_mission_item_denied;
    if (std.mem.eql(u8, event_type, "mavlink.mission_upload_completed")) return .mavlink_mission_upload_completed;
    if (std.mem.eql(u8, event_type, "mavlink.signing_detected")) return .mavlink_signing_detected;
    if (std.mem.eql(u8, event_type, "mavlink.unexpected_endpoint")) return .mavlink_unexpected_endpoint;
    if (std.mem.eql(u8, event_type, "px4.sitl_detected")) return .px4_sitl_detected;
    if (std.mem.eql(u8, event_type, "px4.scenario_started")) return .px4_scenario_started;
    if (std.mem.eql(u8, event_type, "px4.scenario_completed")) return .px4_scenario_completed;
    if (std.mem.eql(u8, event_type, "ardupilot.sitl_detected")) return .ardupilot_sitl_detected;
    if (std.mem.eql(u8, event_type, "ardupilot.scenario_started")) return .ardupilot_scenario_started;
    if (std.mem.eql(u8, event_type, "ardupilot.scenario_completed")) return .ardupilot_scenario_completed;
    if (std.mem.eql(u8, event_type, "safety_case.generated")) return .safety_case_generated;
    if (std.mem.eql(u8, event_type, "safety_case.limitation_recorded")) return .safety_case_limitation_recorded;
    if (std.mem.eql(u8, event_type, "safety_case.evidence_collected")) return .safety_case_evidence_collected;
    if (std.mem.eql(u8, event_type, "safety_case.validation_failed")) return .safety_case_validation_failed;
    if (std.mem.eql(u8, event_type, "health.watchdog.finding")) return .health_watchdog_finding;
    if (std.mem.eql(u8, event_type, "health.heartbeat.stale")) return .health_heartbeat_stale;
    if (std.mem.eql(u8, event_type, "health.audit.failure")) return .health_audit_failure;
    if (std.mem.eql(u8, event_type, "health.command_denied")) return .health_command_denied;
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
    try std.testing.expectEqual(core.event.EventType.operator_approval_invalid, try toCoreEventType("operator.approval_invalid"));
}
