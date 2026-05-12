const std = @import("std");
const decision = @import("decision.zig");
const limits = @import("limits.zig");
const session = @import("session.zig");
const time = @import("time.zig");
const types = @import("types.zig");
const util = @import("util.zig");

pub const schema_version: u16 = 1;

pub const EventType = enum {
    edge_session_start,
    edge_session_exit,
    edge_scenario_start,
    edge_scenario_exit,
    edge_environment_detected,
    edge_capability_reported,
    session_start,
    session_exit,
    policy_loaded,
    backend_capability,
    process_launch,
    file_read_attempt,
    file_read_allowed,
    file_read_denied,
    file_write_attempt,
    file_write_staged,
    file_write_denied,
    file_apply,
    file_discard,
    command_attempt,
    command_approval_requested,
    command_allowed,
    command_denied,
    network_connect_attempt,
    network_connect_allowed,
    network_connect_denied,
    network_exfiltration_suspected,
    data_payload_classified,
    data_payload_redacted,
    data_egress_requested,
    data_egress_allowed,
    data_egress_denied,
    data_egress_observed,
    data_exfiltration_suspected,
    data_endpoint_classified,
    telemetry_channel_observed,
    telemetry_channel_allowed,
    telemetry_channel_denied,
    link_endpoint_unexpected,
    link_command_control_observed,
    link_telemetry_observed,
    mcp_initialize,
    mcp_tools_list,
    mcp_tool_metadata_flagged,
    mcp_tool_call,
    mcp_tool_call_allowed,
    mcp_tool_call_denied,
    mcp_tool_call_approval_requested,
    mcp_resources_list,
    mcp_resource_read,
    mcp_prompts_list,
    mcp_prompt_get,
    mcp_sampling_request,
    mcp_unknown_method,
    secret_redacted,
    user_approval,
    user_denial,
    operator_approval_requested,
    operator_approval_granted,
    operator_approval_denied,
    operator_approval_expired,
    operator_approval_revoked,
    operator_approval_invalid,
    operator_approval_used,
    operator_ask_denied_noninteractive,
    vehicle_command_requested,
    vehicle_command_allowed,
    vehicle_command_denied,
    vehicle_command_mapped,
    vehicle_command_observed,
    vehicle_command_forwarded,
    vehicle_command_blocked,
    vehicle_command_approval_required,
    vehicle_command_allowed_by_approval,
    vehicle_command_denied_missing_approval,
    vehicle_state_observed,
    vehicle_state_stale,
    vehicle_state_invalid,
    vehicle_mode_observed,
    vehicle_battery_observed,
    vehicle_position_observed,
    mavlink_frame_received,
    mavlink_frame_invalid,
    mavlink_message_classified,
    mavlink_command_mapped,
    mavlink_command_allowed,
    mavlink_command_denied,
    mavlink_command_observed,
    mavlink_message_forwarded,
    mavlink_message_blocked,
    mavlink_mission_upload_started,
    mavlink_mission_item_observed,
    mavlink_mission_item_denied,
    mavlink_mission_upload_completed,
    mavlink_signing_detected,
    mavlink_unexpected_endpoint,
    safety_geofence_violation,
    safety_altitude_violation,
    safety_velocity_violation,
    safety_stale_state_denied,
    safety_battery_constraint,
    safety_mode_constraint,
    safety_authority_constraint,
    safety_evaluation_started,
    safety_evaluation_completed,
    safety_finding_created,
    safety_command_risk_denied,
    safety_mission_item_denied,
    emergency_evaluation_started,
    emergency_evaluation_completed,
    emergency_fallback_recommended,
    emergency_command_allowed,
    emergency_command_denied,
    px4_sitl_detected,
    px4_scenario_started,
    px4_scenario_completed,
    ardupilot_sitl_detected,
    ardupilot_scenario_started,
    ardupilot_scenario_completed,
    safety_case_generated,
    safety_case_limitation_recorded,
    safety_case_evidence_collected,
    safety_case_validation_failed,
    health_watchdog_finding,
    health_heartbeat_stale,
    health_audit_failure,
    health_command_denied,

    pub fn toString(self: EventType) []const u8 {
        return switch (self) {
            .edge_session_start => "edge.session_start",
            .edge_session_exit => "edge.session_exit",
            .edge_scenario_start => "edge.scenario_start",
            .edge_scenario_exit => "edge.scenario_exit",
            .edge_environment_detected => "edge.environment_detected",
            .edge_capability_reported => "edge.capability_reported",
            .data_payload_classified => "data.payload_classified",
            .data_payload_redacted => "data.payload_redacted",
            .data_egress_requested => "data.egress_requested",
            .data_egress_allowed => "data.egress_allowed",
            .data_egress_denied => "data.egress_denied",
            .data_egress_observed => "data.egress_observed",
            .data_exfiltration_suspected => "data.exfiltration_suspected",
            .data_endpoint_classified => "data.endpoint_classified",
            .telemetry_channel_observed => "telemetry.channel_observed",
            .telemetry_channel_allowed => "telemetry.channel_allowed",
            .telemetry_channel_denied => "telemetry.channel_denied",
            .link_endpoint_unexpected => "link.endpoint_unexpected",
            .link_command_control_observed => "link.command_control_observed",
            .link_telemetry_observed => "link.telemetry_observed",
            .operator_approval_requested => "operator.approval_requested",
            .operator_approval_granted => "operator.approval_granted",
            .operator_approval_denied => "operator.approval_denied",
            .operator_approval_expired => "operator.approval_expired",
            .operator_approval_revoked => "operator.approval_revoked",
            .operator_approval_invalid => "operator.approval_invalid",
            .operator_approval_used => "operator.approval_used",
            .operator_ask_denied_noninteractive => "operator.ask_denied_noninteractive",
            .vehicle_command_requested => "vehicle.command_requested",
            .vehicle_command_allowed => "vehicle.command_allowed",
            .vehicle_command_denied => "vehicle.command_denied",
            .vehicle_command_mapped => "vehicle.command_mapped",
            .vehicle_command_observed => "vehicle.command_observed",
            .vehicle_command_forwarded => "vehicle.command_forwarded",
            .vehicle_command_blocked => "vehicle.command_blocked",
            .vehicle_command_approval_required => "vehicle.command_approval_required",
            .vehicle_command_allowed_by_approval => "vehicle.command_allowed_by_approval",
            .vehicle_command_denied_missing_approval => "vehicle.command_denied_missing_approval",
            .vehicle_state_observed => "vehicle.state_observed",
            .vehicle_state_stale => "vehicle.state_stale",
            .vehicle_state_invalid => "vehicle.state_invalid",
            .vehicle_mode_observed => "vehicle.mode_observed",
            .vehicle_battery_observed => "vehicle.battery_observed",
            .vehicle_position_observed => "vehicle.position_observed",
            .mavlink_frame_received => "mavlink.frame_received",
            .mavlink_frame_invalid => "mavlink.frame_invalid",
            .mavlink_message_classified => "mavlink.message_classified",
            .mavlink_command_mapped => "mavlink.command_mapped",
            .mavlink_command_allowed => "mavlink.command_allowed",
            .mavlink_command_denied => "mavlink.command_denied",
            .mavlink_command_observed => "mavlink.command_observed",
            .mavlink_message_forwarded => "mavlink.message_forwarded",
            .mavlink_message_blocked => "mavlink.message_blocked",
            .mavlink_mission_upload_started => "mavlink.mission_upload_started",
            .mavlink_mission_item_observed => "mavlink.mission_item_observed",
            .mavlink_mission_item_denied => "mavlink.mission_item_denied",
            .mavlink_mission_upload_completed => "mavlink.mission_upload_completed",
            .mavlink_signing_detected => "mavlink.signing_detected",
            .mavlink_unexpected_endpoint => "mavlink.unexpected_endpoint",
            .safety_geofence_violation => "safety.geofence_violation",
            .safety_altitude_violation => "safety.altitude_violation",
            .safety_velocity_violation => "safety.velocity_violation",
            .safety_stale_state_denied => "safety.stale_state_denied",
            .safety_battery_constraint => "safety.battery_constraint",
            .safety_mode_constraint => "safety.mode_constraint",
            .safety_authority_constraint => "safety.authority_constraint",
            .safety_evaluation_started => "safety.evaluation_started",
            .safety_evaluation_completed => "safety.evaluation_completed",
            .safety_finding_created => "safety.finding_created",
            .safety_command_risk_denied => "safety.command_risk_denied",
            .safety_mission_item_denied => "safety.mission_item_denied",
            .emergency_evaluation_started => "emergency.evaluation_started",
            .emergency_evaluation_completed => "emergency.evaluation_completed",
            .emergency_fallback_recommended => "emergency.fallback_recommended",
            .emergency_command_allowed => "emergency.command_allowed",
            .emergency_command_denied => "emergency.command_denied",
            .px4_sitl_detected => "px4.sitl_detected",
            .px4_scenario_started => "px4.scenario_started",
            .px4_scenario_completed => "px4.scenario_completed",
            .ardupilot_sitl_detected => "ardupilot.sitl_detected",
            .ardupilot_scenario_started => "ardupilot.scenario_started",
            .ardupilot_scenario_completed => "ardupilot.scenario_completed",
            .safety_case_generated => "safety_case.generated",
            .safety_case_limitation_recorded => "safety_case.limitation_recorded",
            .safety_case_evidence_collected => "safety_case.evidence_collected",
            .safety_case_validation_failed => "safety_case.validation_failed",
            .health_watchdog_finding => "health.watchdog.finding",
            .health_heartbeat_stale => "health.heartbeat.stale",
            .health_audit_failure => "health.audit.failure",
            .health_command_denied => "health.command_denied",
            else => @tagName(self),
        };
    }
};

pub const EventId = struct {
    value: [limits.max_event_id_len]u8,
    len: usize,

    pub fn slice(self: *const EventId) []const u8 {
        return self.value[0..self.len];
    }
};

pub const EventHash = struct {
    value: []const u8,
};

pub const RedactionSummary = struct {
    count: u32 = 0,
    labels: []const []const u8 = &.{},
};

pub const Event = struct {
    schema_version: u16 = schema_version,
    session_id: session.SessionId,
    event_id: EventId,
    timestamp: time.Timestamp,
    event_type: EventType,
    actor: types.Actor,
    target: types.Target,
    decision: ?decision.Decision = null,
    redactions: RedactionSummary = .{},
    previous_hash: ?EventHash = null,
    event_hash: ?EventHash = null,
};

pub fn generateEventId(now: time.Timestamp) !EventId {
    var id: EventId = .{
        .value = undefined,
        .len = 0,
    };
    var timestamp_buf: [32]u8 = undefined;
    const timestamp = try now.formatFilenameSafe(&timestamp_buf);
    var suffix_buf: [8]u8 = undefined;
    const suffix = try util.randomHexSuffix(&suffix_buf);
    const written = try std.fmt.bufPrint(&id.value, "evt_{s}_{s}", .{ timestamp, suffix });
    id.len = written.len;
    return id;
}

test "event type string conversion works" {
    try std.testing.expectEqualStrings("session_start", EventType.session_start.toString());
    try std.testing.expectEqualStrings("mcp_sampling_request", EventType.mcp_sampling_request.toString());
}

test "event ids and model can be created deterministically enough for core tests" {
    const ts = time.Timestamp.fromUnixSeconds(1_777_983_130);
    const sid = try session.generateSessionId(ts);
    const eid = try generateEventId(ts);

    try std.testing.expect(std.mem.startsWith(u8, eid.slice(), "evt_2026-05-05T12-12-10Z_"));

    const ev: Event = .{
        .session_id = sid,
        .event_id = eid,
        .timestamp = ts,
        .event_type = .command_attempt,
        .actor = .{ .kind = .agent, .id = "agent-1" },
        .target = .{ .kind = .command, .value = "zig build" },
        .decision = .{
            .result = .observe,
            .reason = "phase 03 model only",
            .ci_may_proceed = true,
        },
    };

    try std.testing.expectEqual(schema_version, ev.schema_version);
    try std.testing.expectEqual(EventType.command_attempt, ev.event_type);
    try std.testing.expectEqual(types.TargetKind.command, ev.target.kind);
}
