const std = @import("std");
const edge = @import("aegis_edge");

const domain = edge.domain;
const operator = edge.operator;
const emergency = edge.emergency;
const safety = edge.safety;

const phase32_policy_yaml =
    \\version: 1
    \\
    \\vehicle:
    \\  kind: drone_multirotor
    \\  autopilot: px4
    \\  adapter: fake
    \\
    \\safety:
    \\  state_freshness:
    \\    max_state_age_ms: 1000
    \\    deny_commands_on_stale_state: true
    \\    allow_emergency_land_on_stale_state: true
    \\    allow_return_home_on_stale_state: false
    \\
    \\  geofence:
    \\    type: circle
    \\    center:
    \\      latitude_deg: 37.000000
    \\      longitude_deg: -122.000000
    \\      altitude_m: 0
    \\      altitude_reference: amsl
    \\    home_position:
    \\      latitude_deg: 37.000000
    \\      longitude_deg: -122.000000
    \\      altitude_m: 0
    \\      altitude_reference: amsl
    \\    max_radius_m: 500
    \\    altitude_floor_m: 2
    \\    altitude_ceiling_m: 120
    \\    altitude_reference: amsl
    \\    boundary_action: deny
    \\
    \\  altitude:
    \\    min_altitude_m: 2
    \\    max_altitude_m: 120
    \\    altitude_reference: amsl
    \\
    \\  velocity:
    \\    max_horizontal_mps: 8
    \\    max_vertical_mps: 2
    \\
    \\  battery:
    \\    deny_takeoff_below_percent: 35
    \\    return_home_below_percent: 25
    \\    land_below_percent: 15
    \\    require_fresh_battery_state: true
    \\
    \\  approval:
    \\    approval_ttl_ms: 60000
    \\    max_uses_default: 1
    \\    require_operator_identity: true
    \\    require_state_hash: true
    \\    allow_broad_scopes: false
    \\    allow_non_overridable_override: false
    \\
    \\  emergency:
    \\    allow_land: true
    \\    allow_return_to_home: true
    \\    allow_hold_position: true
    \\    allow_stop_or_brake: false
    \\    allow_disarm: false
    \\    fallback_order: land, hold_position, return_to_home
    \\
    \\commands:
    \\  allow:
    \\    - read_telemetry
    \\    - read_vehicle_state
    \\    - land
    \\    - return_to_home
    \\    - hold_position
    \\  ask:
    \\    - arm
    \\    - takeoff
    \\    - upload_mission
    \\    - set_waypoint
    \\  deny:
    \\    - disable_failsafe
    \\    - disable_geofence
    \\    - raw_actuator_output
    \\    - override_operator
    \\    - firmware_update
    \\
    \\network:
    \\  mode: allowlist
    \\
    \\audit:
    \\  level: full
    \\  redact_secrets: true
;

test "phase 32 approval model creates bounded exact-action requests and decisions" {
    var loaded = try edge.policy.loadFromSlice(std.testing.allocator, phase32_policy_yaml, "phase32.yaml", .{});
    defer loaded.deinit();
    const state = freshState(.fake_adapter, 80, .fresh);
    const arm = request("cmd-arm", .arm, .none);

    var evaluation = try safety.evaluateSafety(std.testing.allocator, &loaded.value, state, arm, context(.ask));
    defer evaluation.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.ask, evaluation.decision.result);
    try std.testing.expect(evaluation.operator_approval_required);
    try std.testing.expect(evaluation.approval_request != null);
    try std.testing.expect(evaluation.hasAuditEvent("operator.approval_requested"));

    var approval_request = try operator.createApprovalRequest(std.testing.allocator, .{
        .policy = &loaded.value,
        .command = arm,
        .state = state,
        .evaluation = evaluation,
        .requested_decision = .allow_once,
        .created_at_ms = 1_000_500,
        .expires_at_ms = 1_060_500,
        .actor_id = "phase32-agent",
        .operator_id = null,
        .reason = "operator approval required for arm",
    });
    defer approval_request.deinit(std.testing.allocator);

    try std.testing.expectEqual(operator.ApprovalScopeKind.exact_action_only, approval_request.scope.kind);
    try std.testing.expectEqual(@as(u32, 1), approval_request.scope.max_uses);
    try std.testing.expect(approval_request.expires_at_ms > approval_request.created_at_ms);
    try std.testing.expect(approval_request.policy_hash.len == 64);
    try std.testing.expect(approval_request.command_request_hash.len == 64);
    try std.testing.expect(approval_request.state_snapshot_hash.len == 64);

    var decision = try operator.ApprovalDecision.approve(std.testing.allocator, approval_request, .{
        .operator_id = "operator-1",
        .timestamp_ms = 1_000_600,
        .note = "approved for fake SITL evaluation only",
    });
    defer decision.deinit(std.testing.allocator);
    try std.testing.expectEqual(operator.OperatorDecision.approved, decision.decision);
    try std.testing.expectEqualStrings(approval_request.approval_request_id, decision.approval_request_id);
    try std.testing.expectEqual(operator.ApprovalScopeKind.exact_action_only, decision.approved_scope.kind);
}

test "phase 32 approval validation rejects stale mismatched broad and non-overridable approvals" {
    var loaded = try edge.policy.loadFromSlice(std.testing.allocator, phase32_policy_yaml, "phase32.yaml", .{});
    defer loaded.deinit();
    const state = freshState(.fake_adapter, 80, .fresh);
    const arm = request("cmd-arm", .arm, .none);
    var evaluation = try safety.evaluateSafety(std.testing.allocator, &loaded.value, state, arm, context(.ask));
    defer evaluation.deinit();

    var approval_request = try operator.createApprovalRequest(std.testing.allocator, .{
        .policy = &loaded.value,
        .command = arm,
        .state = state,
        .evaluation = evaluation,
        .requested_decision = .allow_once,
        .created_at_ms = 1_000_500,
        .expires_at_ms = 1_060_500,
        .actor_id = "phase32-agent",
        .operator_id = null,
        .reason = "arm approval",
    });
    defer approval_request.deinit(std.testing.allocator);
    var decision = try operator.ApprovalDecision.approve(std.testing.allocator, approval_request, .{
        .operator_id = "operator-1",
        .timestamp_ms = 1_000_600,
    });
    defer decision.deinit(std.testing.allocator);

    var valid = try operator.validateApproval(std.testing.allocator, decision, .{
        .policy = &loaded.value,
        .command = arm,
        .state = state,
        .evaluation = evaluation,
        .now_ms = 1_000_700,
    });
    defer valid.deinit(std.testing.allocator);
    try std.testing.expectEqual(operator.ApprovalValidationStatus.valid, valid.status);

    const takeoff = request("cmd-takeoff", .takeoff, .{ .altitude = .{ .altitude_m = 20, .altitude_reference = .amsl } });
    var mismatched = try operator.validateApproval(std.testing.allocator, decision, .{
        .policy = &loaded.value,
        .command = takeoff,
        .state = state,
        .evaluation = evaluation,
        .now_ms = 1_000_700,
    });
    defer mismatched.deinit(std.testing.allocator);
    try std.testing.expectEqual(operator.ApprovalValidationStatus.command_mismatch, mismatched.status);

    var expired = try operator.validateApproval(std.testing.allocator, decision, .{
        .policy = &loaded.value,
        .command = arm,
        .state = state,
        .evaluation = evaluation,
        .now_ms = 1_060_501,
    });
    defer expired.deinit(std.testing.allocator);
    try std.testing.expectEqual(operator.ApprovalValidationStatus.expired, expired.status);

    var reused = decision;
    reused.used_count = 1;
    var used = try operator.validateApproval(std.testing.allocator, reused, .{
        .policy = &loaded.value,
        .command = arm,
        .state = state,
        .evaluation = evaluation,
        .now_ms = 1_000_700,
    });
    defer used.deinit(std.testing.allocator);
    try std.testing.expectEqual(operator.ApprovalValidationStatus.max_uses_exceeded, used.status);

    var broad = decision;
    broad.approved_scope.kind = .command_type;
    var broad_result = try operator.validateApproval(std.testing.allocator, broad, .{
        .policy = &loaded.value,
        .command = arm,
        .state = state,
        .evaluation = evaluation,
        .now_ms = 1_000_700,
    });
    defer broad_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(operator.ApprovalValidationStatus.broad_scope_not_allowed, broad_result.status);

    const disable = request("cmd-disable", .disable_failsafe, .none);
    var critical = try operator.validateApproval(std.testing.allocator, decision, .{
        .policy = &loaded.value,
        .command = disable,
        .state = state,
        .evaluation = evaluation,
        .now_ms = 1_000_700,
    });
    defer critical.deinit(std.testing.allocator);
    try std.testing.expectEqual(operator.ApprovalValidationStatus.non_overridable_command, critical.status);
}

test "phase 32 valid approval allows exact ask only when safety envelope passes" {
    var loaded = try edge.policy.loadFromSlice(std.testing.allocator, phase32_policy_yaml, "phase32.yaml", .{});
    defer loaded.deinit();
    const state = freshState(.fake_adapter, 80, .fresh);
    const takeoff = request("cmd-takeoff", .takeoff, .{ .altitude = .{ .altitude_m = 20, .altitude_reference = .amsl } });
    var base = try safety.evaluateSafety(std.testing.allocator, &loaded.value, state, takeoff, context(.ask));
    defer base.deinit();
    var approval_request = try operator.createApprovalRequest(std.testing.allocator, .{
        .policy = &loaded.value,
        .command = takeoff,
        .state = state,
        .evaluation = base,
        .requested_decision = .allow_once,
        .created_at_ms = 1_000_500,
        .expires_at_ms = 1_060_500,
        .actor_id = "phase32-agent",
        .reason = "takeoff approval",
    });
    defer approval_request.deinit(std.testing.allocator);
    var decision = try operator.ApprovalDecision.approve(std.testing.allocator, approval_request, .{ .operator_id = "operator-1", .timestamp_ms = 1_000_600 });
    defer decision.deinit(std.testing.allocator);

    var approved = try safety.evaluateSafetyWithApproval(std.testing.allocator, &loaded.value, state, takeoff, context(.ask), decision);
    defer approved.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.allow, approved.decision.result);
    try std.testing.expect(approved.hasAuditEvent("operator.approval_used"));
    try std.testing.expect(approved.hasAuditEvent("vehicle.command_allowed_by_approval"));

    const too_high = request("cmd-too-high", .takeoff, .{ .altitude = .{ .altitude_m = 121, .altitude_reference = .amsl } });
    var denied = try safety.evaluateSafetyWithApproval(std.testing.allocator, &loaded.value, state, too_high, context(.ask), decision);
    defer denied.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, denied.decision.result);
    try std.testing.expect(denied.hasFindingCategory(.altitude));
    try std.testing.expect(denied.hasAuditEvent("operator.approval_invalid"));
}

test "phase 32 CI non-interactive mode converts ask to deny without prompting" {
    var loaded = try edge.policy.loadFromSlice(std.testing.allocator, phase32_policy_yaml, "phase32.yaml", .{});
    defer loaded.deinit();
    const state = freshState(.fake_adapter, 80, .fresh);
    const arm = request("cmd-arm", .arm, .none);
    var result = try safety.evaluateSafety(std.testing.allocator, &loaded.value, state, arm, .{ .mode = .ci, .now_ms = 1_000_500, .non_interactive = true });
    defer result.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, result.decision.result);
    try std.testing.expect(result.operator_approval_required);
    try std.testing.expect(result.approval_request == null);
    try std.testing.expect(result.hasAuditEvent("operator.ask_denied_noninteractive"));
}

test "phase 32 safety PX4 and ArduPilot scenarios consume seeded approvals" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "policy.yaml", .data = phase32_policy_yaml });
    try tmp.dir.writeFile(.{
        .sub_path = "safety-valid.yaml",
        .data =
            \\id: safety-valid-approval
            \\command: takeoff
            \\mode: simulation
            \\approval: valid_once
            \\expected_decision: allow
            \\note: exact approval allows only the seeded takeoff scenario
        ,
    });
    try tmp.dir.writeFile(.{
        .sub_path = "safety-expired.yaml",
        .data =
            \\id: safety-expired-approval
            \\command: arm
            \\mode: simulation
            \\approval: expired
            \\expected_decision: deny
            \\note: expired approval remains denied
        ,
    });
    try tmp.dir.writeFile(.{
        .sub_path = "px4-valid.yaml",
        .data =
            \\id: px4-valid-approval
            \\environment: fake_px4
            \\mode: enforce
            \\command: arm
            \\approval: valid_once
            \\expected_decision: allow
            \\expected_forwarded: true
            \\note: fake PX4 scenario consumes an exact approval
        ,
    });
    try tmp.dir.writeFile(.{
        .sub_path = "ardupilot-expired.yaml",
        .data =
            \\id: ardupilot-expired-approval
            \\environment: fake_ardupilot
            \\vehicle: copter
            \\mode: enforce
            \\command: arm
            \\approval: expired
            \\expected_decision: deny
            \\expected_forwarded: false
            \\note: fake ArduPilot scenario rejects an expired approval
        ,
    });

    const root = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root);
    const policy_path = try std.fs.path.join(allocator, &.{ root, "policy.yaml" });
    defer allocator.free(policy_path);
    const safety_valid = try std.fs.path.join(allocator, &.{ root, "safety-valid.yaml" });
    defer allocator.free(safety_valid);
    const safety_expired = try std.fs.path.join(allocator, &.{ root, "safety-expired.yaml" });
    defer allocator.free(safety_expired);
    const px4_valid = try std.fs.path.join(allocator, &.{ root, "px4-valid.yaml" });
    defer allocator.free(px4_valid);
    const ardupilot_expired = try std.fs.path.join(allocator, &.{ root, "ardupilot-expired.yaml" });
    defer allocator.free(ardupilot_expired);
    const safety_artifacts = try std.fs.path.join(allocator, &.{ root, "artifacts-safety" });
    defer allocator.free(safety_artifacts);
    const safety_expired_artifacts = try std.fs.path.join(allocator, &.{ root, "artifacts-safety-expired" });
    defer allocator.free(safety_expired_artifacts);
    const px4_artifacts = try std.fs.path.join(allocator, &.{ root, "artifacts-px4" });
    defer allocator.free(px4_artifacts);
    const ardupilot_artifacts = try std.fs.path.join(allocator, &.{ root, "artifacts-ardupilot" });
    defer allocator.free(ardupilot_artifacts);

    var valid = try edge.safety.scenario.run(allocator, .{ .policy_path = policy_path, .scenario_path = safety_valid, .artifact_dir = safety_artifacts });
    defer valid.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.allow, valid.decision);

    var expired = try edge.safety.scenario.run(allocator, .{ .policy_path = policy_path, .scenario_path = safety_expired, .artifact_dir = safety_expired_artifacts });
    defer expired.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, expired.decision);

    var px4_result = try edge.px4.scenario.run(allocator, .{ .policy_path = policy_path, .scenario_path = px4_valid, .artifact_dir = px4_artifacts });
    defer px4_result.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.allow, px4_result.decision.?);
    try std.testing.expect(px4_result.forwarded);

    var ardupilot_result = try edge.ardupilot.scenario.run(allocator, .{ .policy_path = policy_path, .scenario_path = ardupilot_expired, .artifact_dir = ardupilot_artifacts });
    defer ardupilot_result.deinit();
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, ardupilot_result.decision.?);
    try std.testing.expect(!ardupilot_result.forwarded);
}

test "phase 32 emergency fallback ladder selects first policy-valid safe command" {
    var loaded = try edge.policy.loadFromSlice(std.testing.allocator, phase32_policy_yaml, "phase32.yaml", .{});
    defer loaded.deinit();
    const critical = freshState(.fake_adapter, 10, .fresh);

    var decision = try emergency.evaluateFallback(std.testing.allocator, &loaded.value, critical, .critical_battery, .{ .now_ms = 1_000_500 });
    defer decision.deinit(std.testing.allocator);
    try std.testing.expectEqual(emergency.EmergencyStatus.emergency_allowed, decision.status);
    try std.testing.expectEqual(emergency.EmergencyCommand.land, decision.command);
    try std.testing.expectEqual(edge.core.decision.DecisionResult.allow, decision.policy_decision);
    try std.testing.expect(decision.hasAuditEvent("emergency.fallback_recommended"));
    try std.testing.expect(decision.hasAuditEvent("emergency.command_allowed"));
}

test "phase 32 emergency RTH requires home and emergency does not bypass policy" {
    var loaded = try edge.policy.loadFromSlice(std.testing.allocator, phase32_policy_yaml, "phase32.yaml", .{});
    defer loaded.deinit();

    var no_home = freshState(.fake_adapter, 20, .fresh);
    no_home.home_position = null;
    var rth = try emergency.evaluateCommand(std.testing.allocator, &loaded.value, no_home, .return_to_home, .low_battery, .{ .now_ms = 1_000_500 });
    defer rth.deinit(std.testing.allocator);
    try std.testing.expectEqual(emergency.EmergencyStatus.emergency_denied, rth.status);
    try std.testing.expect(rth.hasAuditEvent("emergency.command_denied"));

    var unsafe = try emergency.evaluateUnsafeCommand(std.testing.allocator, &loaded.value, freshState(.fake_adapter, 80, .fresh), .disable_failsafe, .policy_violation, .{ .now_ms = 1_000_500 });
    defer unsafe.deinit(std.testing.allocator);
    try std.testing.expectEqual(emergency.EmergencyStatus.emergency_denied, unsafe.status);
    try std.testing.expectEqual(edge.core.decision.DecisionResult.deny, unsafe.policy_decision);
}

test "phase 32 approval store persists bounded redacted local-only audit records" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    var loaded = try edge.policy.loadFromSlice(std.testing.allocator, phase32_policy_yaml, "phase32.yaml", .{});
    defer loaded.deinit();
    const state = freshState(.fake_adapter, 80, .fresh);
    const arm = request("cmd-arm", .arm, .none);
    var evaluation = try safety.evaluateSafety(std.testing.allocator, &loaded.value, state, arm, context(.ask));
    defer evaluation.deinit();
    var approval_request = try operator.createApprovalRequest(std.testing.allocator, .{
        .policy = &loaded.value,
        .command = arm,
        .state = state,
        .evaluation = evaluation,
        .requested_decision = .allow_once,
        .created_at_ms = 1_000_500,
        .expires_at_ms = 1_060_500,
        .actor_id = "phase32-agent",
        .reason = "TOKEN=fake_secret_value_phase32",
    });
    defer approval_request.deinit(std.testing.allocator);

    var store = try operator.ApprovalStore.init(std.testing.allocator, root, "phase32-session");
    defer store.deinit();
    try store.appendRequest(approval_request);
    try store.revoke(approval_request.approval_request_id, "operator-1", 1_000_700);

    const events = try std.fs.cwd().readFileAlloc(std.testing.allocator, store.approvals_path, 64 * 1024);
    defer std.testing.allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "operator.approval_requested") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "operator.approval_revoked") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "fake_secret_value_phase32") == null);
    try std.testing.expect(std.mem.indexOf(u8, events, "[REDACTED:") != null);
}

fn context(mode: edge.policy.EvaluationMode) safety.EvaluationContext {
    return .{ .mode = mode, .now_ms = 1_000_500, .non_interactive = mode == .ci or mode == .redteam };
}

fn request(command_id: []const u8, action: domain.commands.CommandAction, params: domain.commands.CommandParameters) domain.commands.CommandRequest {
    return domain.commands.CommandRequest.init(.{
        .command_id = command_id,
        .vehicle_id = .{ .value = "edge-vehicle-1" },
        .action = action,
        .parameters = params,
        .actor = "phase32-test-agent",
        .timestamp = .{ .value = 1_000_100, .source = .monotonic },
        .source = .fake_adapter,
    });
}

fn freshState(provenance: domain.state.StateProvenance, percent: f64, freshness: domain.state.StateFreshness) domain.state.VehicleState {
    return .{
        .vehicle_id = .{ .value = "edge-vehicle-1" },
        .vehicle_kind = .drone_multirotor,
        .autopilot_kind = .px4,
        .mode = .guided,
        .arm_state = .armed,
        .position = .{ .latitude_deg = 37.0000, .longitude_deg = -122.0000, .altitude_m = 20, .altitude_reference = .amsl },
        .local_position = .{ .x_m = 0, .y_m = 0, .z_m = -20, .frame = .local_ned },
        .battery_state = .{ .percent_remaining = percent, .voltage_v = 15.2, .current_a = 2.1, .source = .monotonic },
        .control_authority = .onboard_agent,
        .home_position = .{ .latitude_deg = 37.0000, .longitude_deg = -122.0000, .altitude_m = 0, .altitude_reference = .amsl },
        .timestamp = .{ .value = 1_000_000, .source = .monotonic },
        .state_freshness = freshness,
        .provenance = provenance,
    };
}
