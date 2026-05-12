const std = @import("std");

const domain = @import("../domain/mod.zig");
const policy_mod = @import("../policy/mod.zig");
const operator = @import("../operator/mod.zig");
const schema = @import("../schema/mod.zig");
const findings_mod = @import("findings.zig");
const core = @import("aegis_core");

pub const EvaluationContext = policy_mod.EvaluationContext;
pub const EvaluationMode = policy_mod.EvaluationMode;
pub const AuditEventPayload = policy_mod.AuditEventPayload;
pub const Finding = findings_mod.Finding;
pub const FindingCategory = findings_mod.FindingCategory;
pub const Severity = findings_mod.Severity;

pub const SafetyEvaluation = struct {
    allocator: std.mem.Allocator,
    inner: policy_mod.EdgeEvaluation,
    decision: core.decision.Decision,
    findings: []Finding = &.{},
    violated_constraints: []policy_mod.ViolatedConstraint = &.{},
    matched_rule: ?policy_mod.MatchedRule = null,
    risk_score: ?u8 = null,
    recommended_fallback: ?domain.commands.CommandAction = null,
    operator_approval_required: bool = false,
    approval_request: ?operator.ApprovalRequest = null,
    ci_may_proceed: bool = false,
    audit_events: []AuditEventPayload = &.{},
    explanation: []const u8,

    pub fn deinit(self: *SafetyEvaluation) void {
        for (self.findings) |finding| finding.deinit(self.allocator);
        self.allocator.free(self.findings);
        for (self.audit_events) |event| self.allocator.free(event.target_value);
        self.allocator.free(self.audit_events);
        if (self.approval_request) |*request| request.deinit(self.allocator);
        self.inner.deinit();
        self.* = undefined;
    }

    pub fn hasFindingCategory(self: SafetyEvaluation, category: FindingCategory) bool {
        for (self.findings) |finding| {
            if (finding.category == category) return true;
        }
        return false;
    }

    pub fn hasAuditEvent(self: SafetyEvaluation, event_type: []const u8) bool {
        for (self.audit_events) |event| {
            if (std.mem.eql(u8, event.event_type, event_type)) return true;
        }
        return false;
    }

    pub fn addSyntheticFinding(self: *SafetyEvaluation, input: findings_mod.FindingInput) !void {
        const next = try self.allocator.alloc(Finding, self.findings.len + 1);
        @memcpy(next[0..self.findings.len], self.findings);
        self.allocator.free(self.findings);
        next[next.len - 1] = try findings_mod.initFinding(self.allocator, next.len, input);
        self.findings = next;
        try self.addAuditEvent("safety.finding_created", .edge_safety_envelope, input.explanation, input.decision);
    }

    pub fn addAuditEvent(
        self: *SafetyEvaluation,
        event_type: []const u8,
        target_kind: core.types.TargetKind,
        target_value: []const u8,
        result: core.decision.DecisionResult,
    ) !void {
        const next = try self.allocator.alloc(AuditEventPayload, self.audit_events.len + 1);
        @memcpy(next[0..self.audit_events.len], self.audit_events);
        self.allocator.free(self.audit_events);
        next[next.len - 1] = .{
            .event_type = event_type,
            .target_kind = target_kind,
            .target_value = try self.allocator.dupe(u8, target_value),
            .decision = core.api.makeDecision(.{
                .result = result,
                .reason = target_value,
                .risk_score = null,
                .requires_user = result == .ask,
                .ci_may_proceed = result == .allow or result == .observe,
            }),
        };
        self.audit_events = next;
    }
};

pub fn evaluateSafetyWithApproval(
    allocator: std.mem.Allocator,
    selected_policy: *const schema.edge_policy_schema.EdgePolicyV1,
    vehicle_state: domain.state.VehicleState,
    command_request: domain.commands.CommandRequest,
    context: EvaluationContext,
    approval_decision: *operator.ApprovalDecision,
) !SafetyEvaluation {
    var evaluation = try evaluateSafety(allocator, selected_policy, vehicle_state, command_request, context);
    errdefer evaluation.deinit();

    var validation = try operator.validateApproval(allocator, approval_decision.*, .{
        .policy = selected_policy,
        .command = command_request,
        .state = vehicle_state,
        .evaluation = evaluation,
        .now_ms = context.now_ms,
    });
    defer validation.deinit(allocator);

    if (validation.isValid() and evaluation.decision.result == .ask) {
        const previous_used_count = approval_decision.used_count;
        approval_decision.used_count += 1;
        errdefer approval_decision.used_count = previous_used_count;
        evaluation.decision = core.api.makeDecision(.{
            .result = .allow,
            .rule_id = if (evaluation.matched_rule) |rule| rule.id else null,
            .reason = "allowed by bounded operator approval",
            .risk_score = evaluation.risk_score,
            .requires_user = false,
            .ci_may_proceed = true,
        });
        evaluation.operator_approval_required = false;
        evaluation.ci_may_proceed = true;
        try evaluation.addAuditEvent("operator.approval_used", .approval, approval_decision.approval_decision_id, .allow);
        try evaluation.addAuditEvent("vehicle.command_allowed_by_approval", .edge_vehicle_command, command_request.command_id, .allow);
    } else if (!validation.isValid()) {
        try evaluation.addAuditEvent(validation.audit_event, .approval, validation.audit_event, .deny);
        if (evaluation.decision.result != .deny) {
            evaluation.decision = core.api.makeDecision(.{
                .result = .deny,
                .rule_id = if (evaluation.matched_rule) |rule| rule.id else null,
                .reason = "invalid or missing operator approval",
                .risk_score = evaluation.risk_score,
                .requires_user = false,
                .ci_may_proceed = false,
            });
            evaluation.ci_may_proceed = false;
            try evaluation.addAuditEvent("vehicle.command_denied_missing_approval", .edge_vehicle_command, command_request.command_id, .deny);
        }
    }
    return evaluation;
}

pub fn evaluateSafety(
    allocator: std.mem.Allocator,
    selected_policy: *const schema.edge_policy_schema.EdgePolicyV1,
    vehicle_state: domain.state.VehicleState,
    command_request: domain.commands.CommandRequest,
    context: EvaluationContext,
) !SafetyEvaluation {
    var inner = try policy_mod.evaluateEdgeAction(allocator, selected_policy, command_request, vehicle_state, context);
    errdefer inner.deinit();

    var findings: std.ArrayList(Finding) = .empty;
    errdefer {
        for (findings.items) |finding| finding.deinit(allocator);
        findings.deinit(allocator);
    }
    for (inner.safety_findings) |finding| {
        try findings.append(allocator, try findingFromPolicyFinding(
            allocator,
            findings.items.len + 1,
            finding,
            command_request,
            vehicle_state,
            inner.decision.result,
        ));
    }

    if (needsCommandRiskFinding(selected_policy, command_request, inner)) {
        try findings.append(allocator, try findings_mod.initFinding(allocator, findings.items.len + 1, .{
            .category = .command_risk,
            .severity = severityForRisk(domain.risk.classifyCommand(command_request.action)),
            .command_id = command_request.command_id,
            .vehicle_id = command_request.vehicle_id.value,
            .constraint_id = "command.risk.default",
            .observed_value = @tagName(command_request.action),
            .limit_value = "critical and unsupported commands deny by default",
            .frame_reference_unit = "command",
            .decision = inner.decision.result,
            .explanation = inner.explanation,
            .timestamp_ms = command_request.timestamp.value,
            .provenance = vehicle_state.provenance,
            .audit_event_reference = "safety.finding_created",
        }));
    }

    var audit_events: std.ArrayList(AuditEventPayload) = .empty;
    errdefer {
        for (audit_events.items) |event| allocator.free(event.target_value);
        audit_events.deinit(allocator);
    }
    try appendAuditEventCopy(allocator, &audit_events, "safety.evaluation_started", .edge_safety_envelope, "safety evaluation started", .observe);
    for (findings.items) |finding| {
        try appendAuditEventCopy(allocator, &audit_events, "safety.finding_created", .edge_safety_envelope, finding.explanation, finding.decision);
    }
    for (inner.audit_events) |event| {
        try audit_events.append(allocator, .{
            .event_type = event.event_type,
            .target_kind = event.target_kind,
            .target_value = try allocator.dupe(u8, event.target_value),
            .decision = event.decision,
        });
    }
    try appendAuditEventCopy(allocator, &audit_events, "safety.evaluation_completed", .edge_safety_envelope, inner.explanation, inner.decision.result);

    const disposition = selected_policy.commands.resolve(command_request.action);
    var approval_request: ?operator.ApprovalRequest = null;
    errdefer if (approval_request) |*request| request.deinit(allocator);
    const approval_required = inner.decision.requires_user or disposition == .ask or disposition == .require_operator_approval;
    if (approval_required and (context.mode == .ci or context.mode == .redteam or context.non_interactive)) {
        try appendAuditEventCopy(allocator, &audit_events, "operator.ask_denied_noninteractive", .approval, "ask decision converted to deny in non-interactive mode", .deny);
    } else if (inner.decision.result == .ask and approval_required) {
        approval_request = try operator.createApprovalRequest(allocator, .{
            .policy = selected_policy,
            .command = command_request,
            .state = vehicle_state,
            .evaluation = .{
                .decision = inner.decision,
                .matched_rule = inner.matched_rule,
                .explanation = inner.explanation,
            },
            .requested_decision = .allow_once,
            .created_at_ms = context.now_ms,
            .expires_at_ms = context.now_ms + @as(i128, @intCast(selected_policy.safety.approval.approval_ttl_ms)),
            .actor_id = command_request.actor,
            .operator_id = null,
            .reason = inner.explanation,
        });
        try appendAuditEventCopy(allocator, &audit_events, "operator.approval_requested", .approval, approval_request.?.approval_request_id, .ask);
    }
    return .{
        .allocator = allocator,
        .inner = inner,
        .decision = inner.decision,
        .findings = try findings.toOwnedSlice(allocator),
        .violated_constraints = inner.violated_constraints,
        .matched_rule = inner.matched_rule,
        .risk_score = inner.decision.risk_score,
        .recommended_fallback = inner.recommended_fallback,
        .operator_approval_required = approval_required,
        .approval_request = approval_request,
        .ci_may_proceed = inner.decision.ci_may_proceed,
        .audit_events = try audit_events.toOwnedSlice(allocator),
        .explanation = inner.explanation,
    };
}

pub fn appendPreparedAuditEvents(
    allocator: std.mem.Allocator,
    writer: *core.api.AuditWriter,
    evaluation: SafetyEvaluation,
    session_id: core.session.SessionId,
    timestamp: core.core.time.Timestamp,
) !void {
    _ = allocator;
    for (evaluation.audit_events) |payload| {
        const event = try core.api.createAuditEvent(.{
            .session_id = session_id,
            .event_id = try core.event.generateEventId(timestamp),
            .timestamp = timestamp,
            .event_type = try coreEventType(payload.event_type),
            .actor = .{ .kind = .aegis, .display = "aegis-edge" },
            .target = .{ .kind = payload.target_kind, .value = payload.target_value },
            .decision = payload.decision,
        });
        try core.api.appendAuditEvent(writer, event);
    }
}

fn appendAuditEventCopy(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(AuditEventPayload),
    event_type: []const u8,
    target_kind: core.types.TargetKind,
    target_value: []const u8,
    result: core.decision.DecisionResult,
) !void {
    try out.append(allocator, .{
        .event_type = event_type,
        .target_kind = target_kind,
        .target_value = try allocator.dupe(u8, target_value),
        .decision = core.api.makeDecision(.{
            .result = result,
            .reason = target_value,
            .risk_score = null,
            .requires_user = result == .ask,
            .ci_may_proceed = result == .allow or result == .observe,
        }),
    });
}

fn findingFromPolicyFinding(
    allocator: std.mem.Allocator,
    index: usize,
    finding: policy_mod.SafetyFinding,
    request: domain.commands.CommandRequest,
    state: domain.state.VehicleState,
    decision: core.decision.DecisionResult,
) !Finding {
    const category = categoryFromPolicyKind(finding.kind);
    return findings_mod.initFinding(allocator, index, .{
        .category = category,
        .severity = severityForCategory(category),
        .command_id = request.command_id,
        .vehicle_id = request.vehicle_id.value,
        .constraint_id = constraintId(category),
        .observed_value = finding.message,
        .limit_value = limitText(category),
        .frame_reference_unit = unitText(category),
        .decision = decision,
        .explanation = finding.message,
        .timestamp_ms = request.timestamp.value,
        .provenance = state.provenance,
        .audit_event_reference = auditReference(category),
    });
}

fn categoryFromPolicyKind(kind: policy_mod.SafetyFindingKind) FindingCategory {
    return switch (kind) {
        .command_policy => .command_risk,
        .state_freshness => .stale_state,
        .geofence => .geofence,
        .altitude => .altitude,
        .velocity => .velocity,
        .battery => .battery,
        .mode => .mode_constraint,
        .authority => .authority_constraint,
        .provenance => .unknown,
        .mission => .mission,
        .command_risk => .command_risk,
        .health => .health,
    };
}

fn severityForCategory(category: FindingCategory) Severity {
    return switch (category) {
        .geofence, .altitude, .velocity, .battery, .stale_state, .mode_constraint, .authority_constraint, .mission, .health => .high,
        .command_risk, .unsupported => .critical,
        .endpoint => .warning,
        .unknown => .warning,
    };
}

fn severityForRisk(risk: domain.commands.RiskCategory) Severity {
    return switch (risk) {
        .critical, .unknown => .critical,
        .high => .high,
        .medium, .emergency_safe => .warning,
        .low => .info,
    };
}

fn constraintId(category: FindingCategory) []const u8 {
    return switch (category) {
        .geofence => "geofence.circle",
        .altitude => "altitude.limits",
        .velocity => "velocity.limits",
        .battery => "battery.thresholds",
        .stale_state => "state.freshness",
        .mode_constraint => "mode.constraint",
        .authority_constraint => "authority.constraint",
        .command_risk => "command.risk.default",
        .mission => "mission.safety",
        .health => "runtime.health",
        .endpoint => "endpoint.policy",
        .unsupported => "unsupported.feature",
        .unknown => "unknown.safety",
    };
}

fn limitText(category: FindingCategory) ?[]const u8 {
    return switch (category) {
        .geofence => "configured circular geofence radius and explicit altitude reference",
        .altitude => "configured altitude floor and ceiling",
        .velocity => "configured horizontal and vertical velocity limits",
        .battery => "configured battery thresholds",
        .stale_state => "fresh state required",
        .mode_constraint => "known compatible mode required",
        .authority_constraint => "agent authority required and failsafe/manual control respected",
        .command_risk => "critical and unsupported commands deny by default",
        .mission => "all mission items must pass safety envelope",
        .health => "runtime health must permit command evaluation and forwarding",
        .endpoint => "configured endpoint policy",
        .unsupported => "unsupported safety features fail closed",
        .unknown => null,
    };
}

fn unitText(category: FindingCategory) ?[]const u8 {
    return switch (category) {
        .geofence, .altitude => "meters/wgs84/explicit_altitude_reference",
        .velocity => "meters_per_second/local_frame",
        .battery => "percent",
        .stale_state => "milliseconds",
        .health => "health_status",
        else => null,
    };
}

fn auditReference(category: FindingCategory) ?[]const u8 {
    return switch (category) {
        .geofence => "safety.geofence_violation",
        .altitude => "safety.altitude_violation",
        .velocity => "safety.velocity_violation",
        .battery => "safety.battery_constraint",
        .stale_state => "safety.stale_state_denied",
        .mode_constraint => "safety.mode_constraint",
        .authority_constraint => "safety.authority_constraint",
        .mission => "safety.mission_item_denied",
        .health => "health.watchdog.finding",
        else => "safety.finding_created",
    };
}

fn needsCommandRiskFinding(
    selected_policy: *const schema.edge_policy_schema.EdgePolicyV1,
    request: domain.commands.CommandRequest,
    evaluation: policy_mod.EdgeEvaluation,
) bool {
    if (evaluation.decision.result != .deny) return false;
    const risk = domain.risk.classifyCommand(request.action);
    if (risk == .critical or risk == .unknown) return true;
    const disposition = selected_policy.commands.resolve(request.action);
    return disposition == .deny;
}

fn coreEventType(event_type: []const u8) !core.event.EventType {
    if (std.mem.eql(u8, event_type, "vehicle.command_requested")) return .vehicle_command_requested;
    if (std.mem.eql(u8, event_type, "vehicle.command_allowed")) return .vehicle_command_allowed;
    if (std.mem.eql(u8, event_type, "vehicle.command_denied")) return .vehicle_command_denied;
    if (std.mem.eql(u8, event_type, "vehicle.command_approval_required")) return .vehicle_command_approval_required;
    if (std.mem.eql(u8, event_type, "vehicle.command_allowed_by_approval")) return .vehicle_command_allowed_by_approval;
    if (std.mem.eql(u8, event_type, "vehicle.command_denied_missing_approval")) return .vehicle_command_denied_missing_approval;
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
    if (std.mem.eql(u8, event_type, "safety.evaluation_started")) return .safety_evaluation_started;
    if (std.mem.eql(u8, event_type, "safety.evaluation_completed")) return .safety_evaluation_completed;
    if (std.mem.eql(u8, event_type, "safety.finding_created")) return .safety_finding_created;
    if (std.mem.eql(u8, event_type, "safety.command_risk_denied")) return .safety_command_risk_denied;
    if (std.mem.eql(u8, event_type, "safety.geofence_violation")) return .safety_geofence_violation;
    if (std.mem.eql(u8, event_type, "safety.altitude_violation")) return .safety_altitude_violation;
    if (std.mem.eql(u8, event_type, "safety.velocity_violation")) return .safety_velocity_violation;
    if (std.mem.eql(u8, event_type, "safety.stale_state_denied")) return .safety_stale_state_denied;
    if (std.mem.eql(u8, event_type, "safety.battery_constraint")) return .safety_battery_constraint;
    if (std.mem.eql(u8, event_type, "safety.mode_constraint")) return .safety_mode_constraint;
    if (std.mem.eql(u8, event_type, "safety.authority_constraint")) return .safety_authority_constraint;
    if (std.mem.eql(u8, event_type, "safety.mission_item_denied")) return .safety_mission_item_denied;
    if (std.mem.eql(u8, event_type, "health.watchdog.finding")) return .health_watchdog_finding;
    if (std.mem.eql(u8, event_type, "health.command_denied")) return .health_command_denied;
    if (std.mem.eql(u8, event_type, "health.audit.failure")) return .health_audit_failure;
    if (std.mem.eql(u8, event_type, "health.heartbeat.stale")) return .health_heartbeat_stale;
    return error.UnknownEdgeEventType;
}
