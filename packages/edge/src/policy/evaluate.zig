const std = @import("std");

const domain = @import("../domain/mod.zig");
const schema = @import("../schema/mod.zig");
const core = @import("aegis_core");

pub const EvaluationMode = enum {
    observe,
    ask,
    strict,
    ci,
    redteam,
    simulation,
    bench,
};

pub const EvaluationContext = struct {
    mode: EvaluationMode = .strict,
    now_ms: i128,
    non_interactive: bool = false,
};

pub const SafetyFindingKind = enum {
    command_policy,
    state_freshness,
    geofence,
    altitude,
    velocity,
    battery,
    mode,
    authority,
    provenance,
};

pub const SafetyConstraintKind = enum {
    command_policy,
    state_freshness,
    geofence,
    altitude,
    velocity,
    battery,
    mode,
    authority,
    provenance,
};

pub const SafetyFinding = struct {
    kind: SafetyFindingKind,
    message: []const u8,
};

pub const ViolatedConstraint = struct {
    kind: SafetyConstraintKind,
    message: []const u8,
};

pub const MatchedRule = struct {
    id: []const u8,
    description: []const u8,
};

pub const AuditEventPayload = struct {
    event_type: []const u8,
    target_kind: core.types.TargetKind,
    target_value: []const u8,
    decision: core.decision.Decision,
};

pub const EdgeEvaluation = struct {
    allocator: std.mem.Allocator,
    decision: core.decision.Decision,
    matched_rule: ?MatchedRule = null,
    safety_findings: []SafetyFinding = &.{},
    violated_constraints: []ViolatedConstraint = &.{},
    recommended_fallback: ?domain.commands.CommandAction = null,
    audit_events: []AuditEventPayload = &.{},
    explanation: []const u8,
    audit_context: []const u8,

    pub fn deinit(self: *EdgeEvaluation) void {
        if (self.decision.rule_id) |rule_id| self.allocator.free(rule_id);
        self.allocator.free(self.explanation);
        self.allocator.free(self.audit_context);
        if (self.matched_rule) |rule| self.allocator.free(rule.description);
        for (self.safety_findings) |finding| self.allocator.free(finding.message);
        self.allocator.free(self.safety_findings);
        for (self.violated_constraints) |constraint| self.allocator.free(constraint.message);
        self.allocator.free(self.violated_constraints);
        for (self.audit_events) |event| self.allocator.free(event.target_value);
        self.allocator.free(self.audit_events);
        self.* = undefined;
    }

    pub fn hasFinding(self: EdgeEvaluation, kind: SafetyFindingKind) bool {
        for (self.safety_findings) |finding| {
            if (finding.kind == kind) return true;
        }
        return false;
    }

    pub fn hasAuditEvent(self: EdgeEvaluation, event_type: []const u8) bool {
        for (self.audit_events) |event| {
            if (std.mem.eql(u8, event.event_type, event_type)) return true;
        }
        return false;
    }

    pub fn usesCoreDecisionModel(self: EdgeEvaluation) bool {
        return switch (self.decision.result) {
            .allow, .ask, .deny, .observe, .redact, .stage, .broker => true,
        };
    }
};

const EvaluationBuilder = struct {
    allocator: std.mem.Allocator,
    findings: std.ArrayList(SafetyFinding) = .empty,
    constraints: std.ArrayList(ViolatedConstraint) = .empty,
    audit_events: std.ArrayList(AuditEventPayload) = .empty,

    fn deinit(self: *EvaluationBuilder) void {
        for (self.findings.items) |finding| self.allocator.free(finding.message);
        self.findings.deinit(self.allocator);
        for (self.constraints.items) |constraint| self.allocator.free(constraint.message);
        self.constraints.deinit(self.allocator);
        for (self.audit_events.items) |event| self.allocator.free(event.target_value);
        self.audit_events.deinit(self.allocator);
    }

    fn addFinding(self: *EvaluationBuilder, kind: SafetyFindingKind, comptime fmt: []const u8, args: anytype) !void {
        try self.findings.append(self.allocator, .{
            .kind = kind,
            .message = try std.fmt.allocPrint(self.allocator, fmt, args),
        });
    }

    fn addViolation(self: *EvaluationBuilder, kind: SafetyConstraintKind, comptime fmt: []const u8, args: anytype) !void {
        try self.constraints.append(self.allocator, .{
            .kind = kind,
            .message = try std.fmt.allocPrint(self.allocator, fmt, args),
        });
    }

    fn addAuditEvent(
        self: *EvaluationBuilder,
        event_type: []const u8,
        target_kind: core.types.TargetKind,
        target_value: []const u8,
        decision: core.decision.Decision,
    ) !void {
        try self.audit_events.append(self.allocator, .{
            .event_type = event_type,
            .target_kind = target_kind,
            .target_value = try self.allocator.dupe(u8, target_value),
            .decision = decision,
        });
    }
};

pub fn evaluateEdgeAction(
    allocator: std.mem.Allocator,
    policy: *const schema.edge_policy_schema.EdgePolicyV1,
    request: domain.commands.CommandRequest,
    vehicle_state: domain.state.VehicleState,
    context: EvaluationContext,
) !EdgeEvaluation {
    try request.validate();
    try vehicle_state.validateForAudit();
    try policy.validate();
    if (!std.mem.eql(u8, request.vehicle_id.value, vehicle_state.vehicle_id.value)) return error.VehicleIdMismatch;

    var builder: EvaluationBuilder = .{ .allocator = allocator };
    errdefer builder.deinit();

    const risk = domain.risk.classifyCommand(request.action);
    const disposition = policy.commands.resolve(request.action);
    const matched_rule = try matchedRuleForDisposition(allocator, policy.commands, request.action, disposition);
    errdefer if (matched_rule) |rule| {
        allocator.free(rule.id);
        allocator.free(rule.description);
    };

    var result = commandPolicyResult(request.action, disposition, risk, context);
    var rule_reason = ruleReason(disposition, risk, context);
    var fallback: ?domain.commands.CommandAction = null;

    const rule_id_for_builder = if (matched_rule) |rule| rule.id else null;
    var decision = core.api.makeDecision(.{
        .result = result,
        .rule_id = rule_id_for_builder,
        .reason = "pending edge evaluation",
        .risk_score = riskScore(risk),
        .requires_user = result == .ask,
        .ci_may_proceed = result == .allow or result == .observe,
    });

    const requested_target = try auditTarget(allocator, request, vehicle_state);
    defer allocator.free(requested_target);
    try builder.addAuditEvent("vehicle.command_requested", .edge_vehicle_command, requested_target, decision);

    if (disposition == .deny or isNeverSafeDefault(request.action)) {
        result = .deny;
        rule_reason = if (disposition == .deny) "explicit command deny" else "critical command default deny";
    } else {
        if (policy.vehicle.adapter == .fake and vehicle_state.provenance != .fake_adapter) {
            try builder.addFinding(.provenance, "policy adapter is fake but state provenance is {s}", .{@tagName(vehicle_state.provenance)});
            try builder.addViolation(.provenance, "fake adapter state must remain labeled fake_adapter", .{});
            result = .deny;
            rule_reason = "fake adapter provenance mismatch";
        }

        if (result != .deny) {
            if (try evaluateFreshness(&builder, policy, request, vehicle_state, context)) |freshness_result| {
                result = freshness_result.result;
                rule_reason = freshness_result.reason;
            }
        }
        if (result != .deny) {
            if (try evaluateBattery(&builder, policy, request, vehicle_state)) |battery_result| {
                result = battery_result.result;
                rule_reason = battery_result.reason;
                fallback = battery_result.fallback;
            }
        }
        if (result != .deny) {
            if (try evaluateModeAndAuthority(&builder, request, vehicle_state, context)) |mode_result| {
                result = mode_result.result;
                rule_reason = mode_result.reason;
            }
        }
        if (result != .deny) {
            if (try evaluateGeofence(&builder, policy, request, vehicle_state, context)) |geo_result| {
                result = geo_result.result;
                rule_reason = geo_result.reason;
                fallback = geo_result.fallback orelse fallback;
            }
        }
        if (result != .deny) {
            if (try evaluateAltitude(&builder, policy, request)) |altitude_result| {
                result = altitude_result.result;
                rule_reason = altitude_result.reason;
            }
        }
        if (result != .deny) {
            if (try evaluateVelocity(&builder, policy, request)) |velocity_result| {
                result = velocity_result.result;
                rule_reason = velocity_result.reason;
            }
        }
    }

    decision = core.api.makeDecision(.{
        .result = result,
        .rule_id = if (matched_rule) |rule| rule.id else null,
        .reason = "pending edge evaluation",
        .risk_score = riskScore(risk),
        .requires_user = result == .ask,
        .ci_may_proceed = result == .allow or result == .observe,
    });

    const explanation = try std.fmt.allocPrint(
        allocator,
        "edge policy decision: command={s} result={s} reason={s}; state_age_ms={d}; timestamp_source={s}; provenance={s}",
        .{
            @tagName(request.action),
            result.toString(),
            rule_reason,
            stateAgeMs(vehicle_state, context),
            @tagName(vehicle_state.timestamp.source),
            @tagName(vehicle_state.provenance),
        },
    );
    errdefer allocator.free(explanation);
    decision.reason = explanation;

    const audit_context = try std.fmt.allocPrint(
        allocator,
        "fake_adapter={}; vehicle_id={s}; command={s}; result={s}",
        .{ vehicle_state.provenance == .fake_adapter, request.vehicle_id.value, @tagName(request.action), result.toString() },
    );
    errdefer allocator.free(audit_context);

    const final_event_type = switch (result) {
        .allow, .observe => "vehicle.command_allowed",
        .ask => "vehicle.command_approval_required",
        .deny => "vehicle.command_denied",
        else => "vehicle.command_denied",
    };
    try builder.addAuditEvent(final_event_type, .edge_vehicle_command, requested_target, decision);

    return .{
        .allocator = allocator,
        .decision = decision,
        .matched_rule = matched_rule,
        .safety_findings = try builder.findings.toOwnedSlice(allocator),
        .violated_constraints = try builder.constraints.toOwnedSlice(allocator),
        .recommended_fallback = fallback,
        .audit_events = try builder.audit_events.toOwnedSlice(allocator),
        .explanation = explanation,
        .audit_context = audit_context,
    };
}

pub fn appendPreparedAuditEvents(
    allocator: std.mem.Allocator,
    writer: *core.api.AuditWriter,
    evaluation: EdgeEvaluation,
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

const ConstraintDecision = struct {
    result: core.decision.DecisionResult,
    reason: []const u8,
    fallback: ?domain.commands.CommandAction = null,
};

fn evaluateFreshness(
    builder: *EvaluationBuilder,
    policy: *const schema.edge_policy_schema.EdgePolicyV1,
    request: domain.commands.CommandRequest,
    state: domain.state.VehicleState,
    context: EvaluationContext,
) !?ConstraintDecision {
    const freshness = policy.safety.state_freshness orelse return null;
    const age_ms = stateAgeMs(state, context);
    const stale_by_age = age_ms > freshness.max_state_age_ms;
    const not_fresh = state.state_freshness != .fresh or stale_by_age;
    if (!not_fresh) return null;

    if (request.action == .land and freshness.allow_emergency_land_on_stale_state and policy.commands.resolve(.land) != .deny) {
        try builder.addFinding(.state_freshness, "emergency land allowed on stale state age_ms={d}", .{age_ms});
        return null;
    }
    if (request.action == .return_to_home and freshness.allow_return_home_on_stale_state and state.home_position != null and policy.commands.resolve(.return_to_home) != .deny) {
        try builder.addFinding(.state_freshness, "return_to_home allowed on stale state with known home position age_ms={d}", .{age_ms});
        return null;
    }
    if (requiresFreshState(request.action)) {
        try builder.addFinding(.state_freshness, "state is not fresh: freshness={s} age_ms={d}", .{ @tagName(state.state_freshness), age_ms });
        try builder.addViolation(.state_freshness, "stale/expired/unknown state is unsafe for {s}", .{@tagName(request.action)});
        const deny_decision = core.api.makeDecision(.{ .result = .deny, .reason = "stale state denied", .risk_score = riskScore(domain.risk.classifyCommand(request.action)) });
        const target = try std.fmt.allocPrint(builder.allocator, "fake_adapter vehicle={s} command={s} state_age_ms={d}", .{ state.vehicle_id.value, @tagName(request.action), age_ms });
        defer builder.allocator.free(target);
        try builder.addAuditEvent("safety.stale_state_denied", .edge_safety_envelope, target, deny_decision);
        return .{ .result = .deny, .reason = "stale state denied" };
    }
    return null;
}

fn evaluateBattery(
    builder: *EvaluationBuilder,
    policy: *const schema.edge_policy_schema.EdgePolicyV1,
    request: domain.commands.CommandRequest,
    state: domain.state.VehicleState,
) !?ConstraintDecision {
    const battery_policy = policy.safety.battery orelse return null;
    const maybe_battery = state.battery_state;
    if (battery_policy.require_fresh_battery_state and maybe_battery == null and isHighRiskMovement(request.action)) {
        try builder.addFinding(.battery, "battery state is required but unavailable", .{});
        try builder.addViolation(.battery, "missing battery state for {s}", .{@tagName(request.action)});
        try addSafetyAudit(builder, "safety.battery_constraint", .edge_safety_envelope, "battery missing", .deny, request.action);
        return .{ .result = .deny, .reason = "required battery state missing" };
    }
    const battery = maybe_battery orelse return null;
    if (battery_policy.require_fresh_battery_state and battery.source == .unknown and isHighRiskMovement(request.action)) {
        try builder.addFinding(.battery, "battery state source is unknown", .{});
        try builder.addViolation(.battery, "unknown battery timestamp source", .{});
        try addSafetyAudit(builder, "safety.battery_constraint", .edge_safety_envelope, "battery source unknown", .deny, request.action);
        return .{ .result = .deny, .reason = "required battery state unknown" };
    }
    if (request.action == .takeoff and battery.percent_remaining < battery_policy.deny_takeoff_below_percent) {
        try builder.addFinding(.battery, "takeoff denied below threshold: observed={d:.2}% threshold={d:.2}%", .{ battery.percent_remaining, battery_policy.deny_takeoff_below_percent });
        try builder.addViolation(.battery, "takeoff battery threshold violated", .{});
        try addSafetyAudit(builder, "safety.battery_constraint", .edge_safety_envelope, "takeoff below battery threshold", .deny, request.action);
        return .{ .result = .deny, .reason = "battery below takeoff threshold", .fallback = if (battery.percent_remaining <= battery_policy.land_below_percent) .land else .return_to_home };
    }
    if (battery.percent_remaining <= battery_policy.land_below_percent and request.action != .land) {
        try builder.addFinding(.battery, "land recommended below threshold: observed={d:.2}% threshold={d:.2}%", .{ battery.percent_remaining, battery_policy.land_below_percent });
        try addSafetyAudit(builder, "safety.battery_constraint", .edge_safety_envelope, "land threshold reached", .deny, request.action);
        return .{ .result = .deny, .reason = "battery below land threshold", .fallback = .land };
    }
    if (battery.percent_remaining <= battery_policy.return_home_below_percent and isMovementCommand(request.action) and request.action != .return_to_home and request.action != .land) {
        try builder.addFinding(.battery, "return_to_home recommended below threshold: observed={d:.2}% threshold={d:.2}%", .{ battery.percent_remaining, battery_policy.return_home_below_percent });
        try addSafetyAudit(builder, "safety.battery_constraint", .edge_safety_envelope, "return_home threshold reached", .deny, request.action);
        return .{ .result = .deny, .reason = "battery below return_home threshold", .fallback = .return_to_home };
    }
    return null;
}

fn evaluateModeAndAuthority(
    builder: *EvaluationBuilder,
    request: domain.commands.CommandRequest,
    state: domain.state.VehicleState,
    context: EvaluationContext,
) !?ConstraintDecision {
    if (request.action == .override_operator) {
        try builder.addFinding(.authority, "override_operator is denied by default", .{});
        try builder.addViolation(.authority, "operator authority cannot be overridden by agent policy", .{});
        try addSafetyAudit(builder, "safety.authority_constraint", .edge_vehicle_command, "override_operator denied", .deny, request.action);
        return .{ .result = .deny, .reason = "operator override denied" };
    }
    if (!requiresAutonomousControl(request.action)) return null;
    if (state.control_authority == .failsafe) {
        try builder.addFinding(.authority, "failsafe authority is active", .{});
        try builder.addViolation(.authority, "agent policy cannot override failsafe authority", .{});
        try addSafetyAudit(builder, "safety.authority_constraint", .edge_vehicle_command, "failsafe authority active", .deny, request.action);
        return .{ .result = .deny, .reason = "failsafe authority active" };
    }
    if (state.control_authority == .human_operator or state.mode == .manual) {
        const result: core.decision.DecisionResult = if (context.mode == .ask or context.mode == .simulation or context.mode == .bench) .ask else .deny;
        try builder.addFinding(.authority, "manual or human control is active: mode={s} authority={s}", .{ @tagName(state.mode), @tagName(state.control_authority) });
        try builder.addViolation(.authority, "autonomous command incompatible with current control authority", .{});
        try addSafetyAudit(builder, "safety.authority_constraint", .edge_vehicle_command, "manual or human authority active", result, request.action);
        return .{ .result = result, .reason = "manual or human authority active" };
    }
    if (state.control_authority == .unknown or state.mode == .unknown) {
        try builder.addFinding(.mode, "mode or authority is unknown", .{});
        try builder.addViolation(.mode, "unknown mode/control authority is unsafe", .{});
        try addSafetyAudit(builder, "safety.mode_constraint", .edge_vehicle_command, "unknown mode or authority", .deny, request.action);
        return .{ .result = .deny, .reason = "unknown mode or authority" };
    }
    return null;
}

fn evaluateGeofence(
    builder: *EvaluationBuilder,
    policy: *const schema.edge_policy_schema.EdgePolicyV1,
    request: domain.commands.CommandRequest,
    state: domain.state.VehicleState,
    context: EvaluationContext,
) !?ConstraintDecision {
    const geofence = policy.safety.geofence orelse return null;
    switch (geofence.shape) {
        .circle => {},
        .allowed_polygon => return error.UnsupportedGeofenceShape,
    }

    if (state.position) |position| {
        if (position.altitude_reference != geofence.altitude_reference) {
            try builder.addFinding(.geofence, "current position altitude reference mismatch: state={s} policy={s}", .{ @tagName(position.altitude_reference), @tagName(geofence.altitude_reference) });
        } else if (!pointInsideCircle(position, geofence.shape.circle)) {
            try builder.addFinding(.geofence, "current position is outside configured geofence", .{});
        }
    } else if (requiresFreshPosition(request.action)) {
        try builder.addFinding(.geofence, "current position is unknown", .{});
        try builder.addViolation(.geofence, "movement command requires known current position", .{});
        try addSafetyAudit(builder, "safety.geofence_violation", .edge_geofence, "current position unknown", .deny, request.action);
        return .{ .result = .deny, .reason = "current position unknown" };
    }

    if (request.parameters != .waypoint) return null;
    const waypoint = request.parameters.waypoint;
    if (waypoint.altitude_reference != geofence.altitude_reference) {
        try builder.addFinding(.geofence, "waypoint altitude reference mismatch: waypoint={s} policy={s}", .{ @tagName(waypoint.altitude_reference), @tagName(geofence.altitude_reference) });
        try builder.addViolation(.geofence, "altitude reference conversion is unsupported", .{});
        try addSafetyAudit(builder, "safety.geofence_violation", .edge_geofence, "altitude reference mismatch", .deny, request.action);
        return .{ .result = .deny, .reason = "unsupported altitude reference conversion" };
    }
    if (!pointInsideCircle(waypoint, geofence.shape.circle)) {
        const result: core.decision.DecisionResult = switch (geofence.boundary_action) {
            .ask => if (context.mode == .ci or context.non_interactive) .deny else .ask,
            .return_to_home, .land, .hold, .deny => .deny,
        };
        try builder.addFinding(.geofence, "waypoint outside circular geofence radius_m={d:.2}", .{geofence.shape.circle.max_radius_m});
        try builder.addViolation(.geofence, "waypoint outside horizontal geofence", .{});
        try addSafetyAudit(builder, "safety.geofence_violation", .edge_geofence, "waypoint outside geofence", result, request.action);
        const fallback: ?domain.commands.CommandAction = switch (geofence.boundary_action) {
            .return_to_home => .return_to_home,
            .land => .land,
            else => null,
        };
        return .{ .result = result, .reason = "waypoint outside geofence", .fallback = fallback };
    }
    return null;
}

fn evaluateAltitude(
    builder: *EvaluationBuilder,
    policy: *const schema.edge_policy_schema.EdgePolicyV1,
    request: domain.commands.CommandRequest,
) !?ConstraintDecision {
    const limits = altitudeLimits(policy) orelse return null;
    const TargetAltitude = struct {
        value: f64,
        reference: domain.coordinates.AltitudeReference,
    };
    const target_altitude: ?TargetAltitude = switch (request.parameters) {
        .waypoint => |point| .{ .value = point.altitude_m, .reference = point.altitude_reference },
        .altitude => |alt| .{ .value = alt.altitude_m, .reference = alt.altitude_reference },
        else => null,
    };
    const actual_target = target_altitude orelse return null;
    if (actual_target.reference != limits.altitude_reference) {
        try builder.addFinding(.altitude, "target altitude reference mismatch: target={s} policy={s}", .{ @tagName(actual_target.reference), @tagName(limits.altitude_reference) });
        try builder.addViolation(.altitude, "altitude reference conversion is unsupported", .{});
        try addSafetyAudit(builder, "safety.altitude_violation", .edge_safety_envelope, "altitude reference mismatch", .deny, request.action);
        return .{ .result = .deny, .reason = "unsupported altitude reference conversion" };
    }
    if (actual_target.value > limits.max_altitude_m) {
        try builder.addFinding(.altitude, "target altitude above ceiling: observed={d:.2} ceiling={d:.2}", .{ actual_target.value, limits.max_altitude_m });
        try builder.addViolation(.altitude, "altitude ceiling violated", .{});
        try addSafetyAudit(builder, "safety.altitude_violation", .edge_safety_envelope, "altitude ceiling violated", .deny, request.action);
        return .{ .result = .deny, .reason = "altitude above ceiling" };
    }
    if (actual_target.value < limits.min_altitude_m and request.action != .land) {
        try builder.addFinding(.altitude, "target altitude below floor: observed={d:.2} floor={d:.2}", .{ actual_target.value, limits.min_altitude_m });
        try builder.addViolation(.altitude, "altitude floor violated", .{});
        try addSafetyAudit(builder, "safety.altitude_violation", .edge_safety_envelope, "altitude floor violated", .deny, request.action);
        return .{ .result = .deny, .reason = "altitude below floor" };
    }
    return null;
}

fn evaluateVelocity(
    builder: *EvaluationBuilder,
    policy: *const schema.edge_policy_schema.EdgePolicyV1,
    request: domain.commands.CommandRequest,
) !?ConstraintDecision {
    const limits = policy.safety.velocity orelse return null;
    if (request.parameters != .velocity) return null;
    const velocity = request.parameters.velocity;
    if (velocity.frame == .unknown or velocity.frame == .wgs84) {
        try builder.addFinding(.velocity, "velocity frame is invalid: {s}", .{@tagName(velocity.frame)});
        try builder.addViolation(.velocity, "unknown velocity frame is unsafe", .{});
        try addSafetyAudit(builder, "safety.velocity_violation", .edge_safety_envelope, "unknown velocity frame", .deny, request.action);
        return .{ .result = .deny, .reason = "unknown velocity frame" };
    }
    const horizontal = std.math.sqrt(velocity.vx_mps * velocity.vx_mps + velocity.vy_mps * velocity.vy_mps);
    const vertical = @abs(velocity.vz_mps);
    if (horizontal > limits.max_horizontal_mps) {
        try builder.addFinding(.velocity, "horizontal velocity above limit: observed={d:.2} limit={d:.2}", .{ horizontal, limits.max_horizontal_mps });
        try builder.addViolation(.velocity, "horizontal velocity limit violated", .{});
        try addSafetyAudit(builder, "safety.velocity_violation", .edge_safety_envelope, "horizontal velocity limit violated", .deny, request.action);
        return .{ .result = .deny, .reason = "horizontal velocity above limit" };
    }
    if (vertical > limits.max_vertical_mps) {
        try builder.addFinding(.velocity, "vertical velocity above limit: observed={d:.2} limit={d:.2}", .{ vertical, limits.max_vertical_mps });
        try builder.addViolation(.velocity, "vertical velocity limit violated", .{});
        try addSafetyAudit(builder, "safety.velocity_violation", .edge_safety_envelope, "vertical velocity limit violated", .deny, request.action);
        return .{ .result = .deny, .reason = "vertical velocity above limit" };
    }
    return null;
}

fn addSafetyAudit(
    builder: *EvaluationBuilder,
    event_type: []const u8,
    target_kind: core.types.TargetKind,
    target_value: []const u8,
    result: core.decision.DecisionResult,
    action: domain.commands.CommandAction,
) !void {
    const decision = core.api.makeDecision(.{
        .result = result,
        .reason = target_value,
        .risk_score = riskScore(domain.risk.classifyCommand(action)),
        .requires_user = result == .ask,
        .ci_may_proceed = result == .allow or result == .observe,
    });
    try builder.addAuditEvent(event_type, target_kind, target_value, decision);
}

fn matchedRuleForDisposition(
    allocator: std.mem.Allocator,
    commands: domain.safety_envelope.CommandPolicy,
    action: domain.commands.CommandAction,
    disposition: domain.safety_envelope.CommandDisposition,
) !?MatchedRule {
    const list: ?[]const domain.commands.CommandAction = switch (disposition) {
        .allow => commands.allow,
        .ask => commands.ask,
        .deny => commands.deny,
        .require_operator_approval => commands.require_operator_approval,
        .unspecified => null,
    };
    const actual = list orelse return null;
    for (actual, 0..) |candidate, index| {
        if (candidate == action) {
            const section = switch (disposition) {
                .allow => "commands.allow",
                .ask => "commands.ask",
                .deny => "commands.deny",
                .require_operator_approval => "commands.require_operator_approval",
                .unspecified => unreachable,
            };
            return .{
                .id = try std.fmt.allocPrint(allocator, "{s}[{d}]", .{ section, index }),
                .description = try std.fmt.allocPrint(allocator, "matched {s} for {s}", .{ section, @tagName(action) }),
            };
        }
    }
    return null;
}

fn commandPolicyResult(
    action: domain.commands.CommandAction,
    disposition: domain.safety_envelope.CommandDisposition,
    risk: domain.risk.RiskCategory,
    context: EvaluationContext,
) core.decision.DecisionResult {
    if (disposition == .deny) return .deny;
    if (isNeverSafeDefault(action)) return .deny;
    if (disposition == .allow) return .allow;
    if (disposition == .ask or disposition == .require_operator_approval) {
        return if (context.mode == .ci or context.non_interactive) .deny else .ask;
    }
    if (risk == .critical or risk == .unknown) return .deny;
    if (risk == .emergency_safe and (action == .land or action == .return_to_home)) return .allow;
    return switch (context.mode) {
        .observe => .observe,
        .ask, .simulation, .bench => .ask,
        .strict, .ci, .redteam => .deny,
    };
}

fn ruleReason(
    disposition: domain.safety_envelope.CommandDisposition,
    risk: domain.risk.RiskCategory,
    context: EvaluationContext,
) []const u8 {
    return switch (disposition) {
        .allow => "explicit command allow",
        .ask => if (context.mode == .ci or context.non_interactive) "ask converted to deny in non-interactive mode" else "explicit command ask",
        .deny => "explicit command deny",
        .require_operator_approval => if (context.mode == .ci or context.non_interactive) "operator approval converted to deny in non-interactive mode" else "operator approval required",
        .unspecified => switch (risk) {
            .critical, .unknown => "unconfigured critical or unknown command default deny",
            .emergency_safe => "emergency-safe default",
            else => "mode default",
        },
    };
}

fn isNeverSafeDefault(action: domain.commands.CommandAction) bool {
    return switch (action) {
        .disable_failsafe,
        .disable_geofence,
        .raw_actuator_output,
        .override_operator,
        .firmware_update,
        => true,
        else => false,
    };
}

fn riskScore(risk: domain.risk.RiskCategory) ?u8 {
    return switch (risk) {
        .low => 10,
        .medium => 45,
        .emergency_safe => 35,
        .high => 75,
        .critical => 95,
        .unknown => null,
    };
}

fn requiresFreshState(action: domain.commands.CommandAction) bool {
    return isHighRiskMovement(action) or domain.risk.classifyCommand(action) == .critical;
}

fn requiresFreshPosition(action: domain.commands.CommandAction) bool {
    return switch (action) {
        .takeoff,
        .set_waypoint,
        .set_velocity,
        .set_altitude,
        .start_mission,
        .upload_mission,
        .return_to_home,
        => true,
        else => false,
    };
}

fn isHighRiskMovement(action: domain.commands.CommandAction) bool {
    return switch (action) {
        .arm,
        .takeoff,
        .set_waypoint,
        .set_velocity,
        .set_altitude,
        .set_heading,
        .start_mission,
        .upload_mission,
        .set_mode,
        => true,
        else => false,
    };
}

fn isMovementCommand(action: domain.commands.CommandAction) bool {
    return isHighRiskMovement(action) or switch (action) {
        .land, .return_to_home, .hold_position => true,
        else => false,
    };
}

fn requiresAutonomousControl(action: domain.commands.CommandAction) bool {
    return switch (action) {
        .arm,
        .takeoff,
        .set_waypoint,
        .set_velocity,
        .set_altitude,
        .set_heading,
        .start_mission,
        .upload_mission,
        .set_mode,
        .override_operator,
        => true,
        else => false,
    };
}

fn stateAgeMs(state: domain.state.VehicleState, context: EvaluationContext) u64 {
    const age = context.now_ms - state.timestamp.value;
    if (age <= 0) return 0;
    return @intCast(age);
}

fn altitudeLimits(policy: *const schema.edge_policy_schema.EdgePolicyV1) ?domain.safety_envelope.AltitudeLimits {
    if (policy.safety.altitude) |limits| return limits;
    if (policy.safety.geofence) |geofence| {
        return .{
            .min_altitude_m = geofence.altitude_floor_m,
            .max_altitude_m = geofence.altitude_ceiling_m,
            .altitude_reference = geofence.altitude_reference,
        };
    }
    return null;
}

fn pointInsideCircle(point: domain.coordinates.GeoPoint, circle: domain.geofence.Circle) bool {
    return distanceMeters(point, circle.center) <= circle.max_radius_m;
}

fn distanceMeters(a: domain.coordinates.GeoPoint, b: domain.coordinates.GeoPoint) f64 {
    const earth_radius_m = 6_371_000.0;
    const lat1 = degreesToRadians(a.latitude_deg);
    const lat2 = degreesToRadians(b.latitude_deg);
    const dlat = degreesToRadians(b.latitude_deg - a.latitude_deg);
    const dlon = degreesToRadians(b.longitude_deg - a.longitude_deg);
    const sin_dlat = std.math.sin(dlat / 2.0);
    const sin_dlon = std.math.sin(dlon / 2.0);
    const h = sin_dlat * sin_dlat + std.math.cos(lat1) * std.math.cos(lat2) * sin_dlon * sin_dlon;
    return earth_radius_m * 2.0 * std.math.atan2(std.math.sqrt(h), std.math.sqrt(1.0 - h));
}

fn degreesToRadians(value: f64) f64 {
    return value * std.math.pi / 180.0;
}

fn auditTarget(allocator: std.mem.Allocator, request: domain.commands.CommandRequest, state: domain.state.VehicleState) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "fake_adapter={} vehicle={s} command={s} actor={s} provenance={s}",
        .{ state.provenance == .fake_adapter, request.vehicle_id.value, @tagName(request.action), request.actor, @tagName(state.provenance) },
    );
}

fn coreEventType(event_type: []const u8) !core.event.EventType {
    if (std.mem.eql(u8, event_type, "vehicle.command_requested")) return .vehicle_command_requested;
    if (std.mem.eql(u8, event_type, "vehicle.command_allowed")) return .vehicle_command_allowed;
    if (std.mem.eql(u8, event_type, "vehicle.command_denied")) return .vehicle_command_denied;
    if (std.mem.eql(u8, event_type, "vehicle.command_approval_required")) return .vehicle_command_approval_required;
    if (std.mem.eql(u8, event_type, "safety.geofence_violation")) return .safety_geofence_violation;
    if (std.mem.eql(u8, event_type, "safety.altitude_violation")) return .safety_altitude_violation;
    if (std.mem.eql(u8, event_type, "safety.velocity_violation")) return .safety_velocity_violation;
    if (std.mem.eql(u8, event_type, "safety.stale_state_denied")) return .safety_stale_state_denied;
    if (std.mem.eql(u8, event_type, "safety.battery_constraint")) return .safety_battery_constraint;
    if (std.mem.eql(u8, event_type, "safety.mode_constraint")) return .safety_mode_constraint;
    if (std.mem.eql(u8, event_type, "safety.authority_constraint")) return .safety_authority_constraint;
    return error.UnknownEdgeEventType;
}
