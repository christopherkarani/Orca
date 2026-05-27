const std = @import("std");

const domain = @import("../domain/mod.zig");
const schema = @import("../schema/mod.zig");
const evaluator = @import("evaluator.zig");
const findings = @import("findings.zig");

pub fn evaluateMissionSafety(
    allocator: std.mem.Allocator,
    selected_policy: *const schema.edge_policy_schema.EdgePolicyV1,
    vehicle_state: domain.state.VehicleState,
    mission: domain.mission.MissionPlan,
    context: evaluator.EvaluationContext,
) !evaluator.SafetyEvaluation {
    try mission.validate();

    var upload = try evaluator.evaluateSafety(
        allocator,
        selected_policy,
        vehicle_state,
        domain.commands.CommandRequest.init(.{
            .command_id = mission.mission_id.value,
            .vehicle_id = vehicle_state.vehicle_id,
            .action = .upload_mission,
            .actor = "mission-safety",
            .timestamp = .{ .value = context.now_ms, .source = .monotonic },
            .source = vehicle_state.provenance,
            .mission_id = mission.mission_id.value,
        }),
        context,
    );
    errdefer upload.deinit();

    var seen = [_]bool{false} ** 256;
    var denied = upload.decision.result == .deny;
    for (mission.waypoints, 0..) |waypoint, index| {
        if (waypoint.sequence >= seen.len) {
            denied = true;
            try upload.addSyntheticFinding(.{
                .category = .mission,
                .severity = .high,
                .command_id = mission.mission_id.value,
                .vehicle_id = vehicle_state.vehicle_id.value,
                .constraint_id = "mission.sequence",
                .observed_value = "mission item sequence exceeds deterministic limit",
                .limit_value = "0..255",
                .frame_reference_unit = "mission_item_sequence",
                .decision = .deny,
                .explanation = "mission item sequence exceeds deterministic safety limit",
                .timestamp_ms = context.now_ms,
                .provenance = vehicle_state.provenance,
                .audit_event_reference = "safety.mission_item_denied",
            });
            continue;
        }
        if (seen[waypoint.sequence]) {
            denied = true;
            try upload.addSyntheticFinding(.{
                .category = .mission,
                .severity = .high,
                .command_id = mission.mission_id.value,
                .vehicle_id = vehicle_state.vehicle_id.value,
                .constraint_id = "mission.duplicate_sequence",
                .observed_value = "duplicate mission item sequence",
                .limit_value = "unique sequence numbers required",
                .frame_reference_unit = "mission_item_sequence",
                .decision = .deny,
                .explanation = "duplicate mission item handled deterministically as unsafe",
                .timestamp_ms = context.now_ms,
                .provenance = vehicle_state.provenance,
                .audit_event_reference = "safety.mission_item_denied",
            });
        }
        seen[waypoint.sequence] = true;
        if (waypoint.sequence != index) {
            denied = true;
            try upload.addSyntheticFinding(.{
                .category = .mission,
                .severity = .warning,
                .command_id = mission.mission_id.value,
                .vehicle_id = vehicle_state.vehicle_id.value,
                .constraint_id = "mission.missing_or_reordered_sequence",
                .observed_value = "mission item sequence does not match deterministic order",
                .limit_value = "complete ordered mission upload required",
                .frame_reference_unit = "mission_item_sequence",
                .decision = .deny,
                .explanation = "missing or reordered mission items are not treated as safe",
                .timestamp_ms = context.now_ms,
                .provenance = vehicle_state.provenance,
                .audit_event_reference = "safety.mission_item_denied",
            });
        }

        const item_command_id = try std.fmt.allocPrint(allocator, "{s}-item-{d}", .{ mission.mission_id.value, waypoint.sequence });
        defer allocator.free(item_command_id);
        var item_eval = try evaluator.evaluateSafety(
            allocator,
            selected_policy,
            vehicle_state,
            domain.commands.CommandRequest.init(.{
                .command_id = item_command_id,
                .vehicle_id = vehicle_state.vehicle_id,
                .action = .set_waypoint,
                .parameters = .{ .waypoint = waypoint.position },
                .actor = "mission-safety",
                .timestamp = .{ .value = context.now_ms, .source = .monotonic },
                .source = vehicle_state.provenance,
                .mission_id = mission.mission_id.value,
            }),
            context,
        );
        defer item_eval.deinit();
        if (item_eval.decision.result == .deny) {
            denied = true;
            try upload.addSyntheticFinding(.{
                .category = .mission,
                .severity = .high,
                .command_id = mission.mission_id.value,
                .vehicle_id = vehicle_state.vehicle_id.value,
                .constraint_id = "mission.item.envelope",
                .observed_value = item_eval.explanation,
                .limit_value = "every mission item must pass geofence and altitude limits",
                .frame_reference_unit = "mission_item/wgs84/altitude_reference",
                .decision = .deny,
                .explanation = "mission item denied by safety envelope",
                .timestamp_ms = context.now_ms,
                .provenance = vehicle_state.provenance,
                .audit_event_reference = "safety.mission_item_denied",
            });
        }
    }

    if (denied) {
        upload.decision.result = .deny;
        upload.decision.reason = "mission safety denied";
        upload.decision.ci_may_proceed = false;
        upload.ci_may_proceed = false;
        try upload.addAuditEvent("safety.mission_item_denied", .extension_target, mission.mission_id.value, .deny);
        try upload.addAuditEvent("vehicle.command_denied", .extension_target, mission.mission_id.value, .deny);
    }
    return upload;
}

test {
    _ = findings;
}
