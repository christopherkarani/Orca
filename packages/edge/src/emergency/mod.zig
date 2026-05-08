const std = @import("std");

const domain = @import("../domain/mod.zig");
const policy_mod = @import("../policy/mod.zig");
const schema = @import("../schema/mod.zig");
const core = @import("aegis_core");

pub const EmergencyCommand = enum {
    land,
    return_to_home,
    return_to_launch,
    hold_position,
    stop_or_brake,
    disarm,
    unknown,
};

pub const EmergencyStatus = enum {
    normal,
    emergency_requested,
    emergency_allowed,
    emergency_denied,
    emergency_in_progress,
    emergency_completed,
    emergency_unavailable,
    unknown,
};

pub const EmergencyReason = enum {
    low_battery,
    critical_battery,
    geofence_violation,
    lost_link,
    stale_state,
    operator_requested,
    policy_violation,
    unknown,
};

pub const EvaluationOptions = struct {
    now_ms: i128,
    mode: policy_mod.EvaluationMode = .simulation,
};

pub const EmergencyAuditEvent = struct {
    event_type: []const u8,
    decision: core.decision.DecisionResult,
    note: []u8,

    fn deinit(self: EmergencyAuditEvent, allocator: std.mem.Allocator) void {
        allocator.free(self.note);
    }
};

pub const EmergencyDecision = struct {
    allocator: std.mem.Allocator,
    command: EmergencyCommand,
    reason: EmergencyReason,
    status: EmergencyStatus,
    policy_decision: core.decision.DecisionResult,
    safety_findings: []u8,
    fallback_order: []EmergencyCommand,
    matched_rule: ?[]u8 = null,
    audit_event_reference: []const u8,
    audit_events: []EmergencyAuditEvent,

    pub fn deinit(self: *EmergencyDecision, allocator: std.mem.Allocator) void {
        allocator.free(self.safety_findings);
        allocator.free(self.fallback_order);
        if (self.matched_rule) |rule| allocator.free(rule);
        for (self.audit_events) |event| event.deinit(allocator);
        allocator.free(self.audit_events);
        self.* = undefined;
    }

    pub fn hasAuditEvent(self: EmergencyDecision, event_type: []const u8) bool {
        for (self.audit_events) |event| {
            if (std.mem.eql(u8, event.event_type, event_type)) return true;
        }
        return false;
    }
};

pub fn evaluateFallback(
    allocator: std.mem.Allocator,
    policy: *const schema.edge_policy_schema.EdgePolicyV1,
    state: domain.state.VehicleState,
    reason: EmergencyReason,
    options: EvaluationOptions,
) !EmergencyDecision {
    var order = try fallbackOrder(allocator, policy);
    errdefer allocator.free(order);
    prioritizeReason(&order, reason);
    errdefer allocator.free(order);
    var last_denied: ?EmergencyDecision = null;
    for (order) |candidate| {
        var decision = try evaluateCommandWithOrder(allocator, policy, state, candidate, reason, options, order);
        if (decision.status == .emergency_allowed) {
            try prependAudit(allocator, &decision, "emergency.fallback_recommended", "fallback ladder selected first policy-valid command", .allow);
            allocator.free(order);
            return decision;
        }
        if (last_denied) |*previous| previous.deinit(allocator);
        last_denied = decision;
    }
    allocator.free(order);
    if (last_denied) |decision| return decision;
    return deniedDecision(allocator, .unknown, reason, "no emergency fallback configured", .deny, &.{}, null);
}

pub fn evaluateCommand(
    allocator: std.mem.Allocator,
    policy: *const schema.edge_policy_schema.EdgePolicyV1,
    state: domain.state.VehicleState,
    command: EmergencyCommand,
    reason: EmergencyReason,
    options: EvaluationOptions,
) !EmergencyDecision {
    const order = try fallbackOrder(allocator, policy);
    defer allocator.free(order);
    return evaluateCommandWithOrder(allocator, policy, state, command, reason, options, order);
}

pub fn evaluateUnsafeCommand(
    allocator: std.mem.Allocator,
    policy: *const schema.edge_policy_schema.EdgePolicyV1,
    state: domain.state.VehicleState,
    action: domain.commands.CommandAction,
    reason: EmergencyReason,
    options: EvaluationOptions,
) !EmergencyDecision {
    _ = policy;
    _ = state;
    _ = options;
    return deniedDecision(allocator, commandFromAction(action), reason, "emergency path cannot authorize unsafe command or policy bypass", .deny, &.{}, null);
}

fn evaluateCommandWithOrder(
    allocator: std.mem.Allocator,
    policy: *const schema.edge_policy_schema.EdgePolicyV1,
    state: domain.state.VehicleState,
    command: EmergencyCommand,
    reason: EmergencyReason,
    options: EvaluationOptions,
    order: []EmergencyCommand,
) !EmergencyDecision {
    if (command == .unknown) return deniedDecision(allocator, command, reason, "unknown emergency command is unsafe", .deny, order, null);
    if (!emergencyPolicyAllows(policy, command)) return deniedDecision(allocator, command, reason, "emergency command disabled by policy", .deny, order, null);
    if (command == .return_to_home or command == .return_to_launch) {
        if (state.home_position == null) return deniedDecision(allocator, command, reason, "return_to_home requires valid home position", .deny, order, null);
        if (state.state_freshness != .fresh and !allowReturnHomeOnStale(policy)) return deniedDecision(allocator, command, reason, "return_to_home denied on stale state by policy", .deny, order, null);
    }
    if (command == .hold_position) {
        if (state.local_position == null and state.position == null) return deniedDecision(allocator, command, reason, "hold_position requires valid local or global position context", .deny, order, null);
        if (state.state_freshness != .fresh) return deniedDecision(allocator, command, reason, "hold_position denied on stale state", .deny, order, null);
    }
    if (command == .land and state.state_freshness != .fresh and !allowLandOnStale(policy)) {
        return deniedDecision(allocator, command, reason, "land on stale state disabled by policy", .deny, order, null);
    }
    if (command == .disarm) return deniedDecision(allocator, command, reason, "disarm is not a default emergency-safe in-flight action", .deny, order, null);
    if (command == .stop_or_brake) return deniedDecision(allocator, command, reason, "stop_or_brake is unavailable in the current fake/SITL mediation path", .deny, order, null);

    const action = actionFromCommand(command) orelse return deniedDecision(allocator, command, reason, "emergency command has no supported Edge command mapping", .deny, order, null);
    var request = domain.commands.CommandRequest.init(.{
        .command_id = "emergency-evaluation-command",
        .vehicle_id = state.vehicle_id,
        .action = action,
        .actor = "aegis-edge-emergency",
        .timestamp = .{ .value = options.now_ms, .source = .monotonic },
        .source = state.provenance,
    });
    if (action == .return_to_home) request.parameters = .none;
    var evaluation = try policy_mod.evaluateEdgeAction(allocator, policy, request, state, .{
        .mode = options.mode,
        .now_ms = options.now_ms,
        .non_interactive = true,
    });
    defer evaluation.deinit();
    const allowed = evaluation.decision.result == .allow or evaluation.decision.result == .observe;
    var events: std.ArrayList(EmergencyAuditEvent) = .empty;
    errdefer {
        for (events.items) |event| event.deinit(allocator);
        events.deinit(allocator);
    }
    try appendEvent(allocator, &events, "emergency.evaluation_started", "emergency evaluation started", .observe);
    try appendEvent(allocator, &events, "emergency.evaluation_completed", evaluation.explanation, evaluation.decision.result);
    try appendEvent(allocator, &events, if (allowed) "emergency.command_allowed" else "emergency.command_denied", evaluation.explanation, evaluation.decision.result);
    return .{
        .allocator = allocator,
        .command = command,
        .reason = reason,
        .status = if (allowed) .emergency_allowed else .emergency_denied,
        .policy_decision = evaluation.decision.result,
        .safety_findings = try allocator.dupe(u8, evaluation.explanation),
        .fallback_order = try allocator.dupe(EmergencyCommand, order),
        .matched_rule = if (evaluation.matched_rule) |rule| try allocator.dupe(u8, rule.id) else null,
        .audit_event_reference = if (allowed) "emergency.command_allowed" else "emergency.command_denied",
        .audit_events = try events.toOwnedSlice(allocator),
    };
}

fn deniedDecision(
    allocator: std.mem.Allocator,
    command: EmergencyCommand,
    reason: EmergencyReason,
    note: []const u8,
    policy_decision: core.decision.DecisionResult,
    order: []const EmergencyCommand,
    matched_rule: ?[]const u8,
) !EmergencyDecision {
    var events: std.ArrayList(EmergencyAuditEvent) = .empty;
    errdefer {
        for (events.items) |event| event.deinit(allocator);
        events.deinit(allocator);
    }
    try appendEvent(allocator, &events, "emergency.evaluation_started", "emergency evaluation started", .observe);
    try appendEvent(allocator, &events, "emergency.command_denied", note, .deny);
    try appendEvent(allocator, &events, "emergency.evaluation_completed", note, .deny);
    return .{
        .allocator = allocator,
        .command = command,
        .reason = reason,
        .status = .emergency_denied,
        .policy_decision = policy_decision,
        .safety_findings = try allocator.dupe(u8, note),
        .fallback_order = try allocator.dupe(EmergencyCommand, order),
        .matched_rule = if (matched_rule) |rule| try allocator.dupe(u8, rule) else null,
        .audit_event_reference = "emergency.command_denied",
        .audit_events = try events.toOwnedSlice(allocator),
    };
}

fn prependAudit(allocator: std.mem.Allocator, decision: *EmergencyDecision, event_type: []const u8, note: []const u8, result: core.decision.DecisionResult) !void {
    const next = try allocator.alloc(EmergencyAuditEvent, decision.audit_events.len + 1);
    errdefer allocator.free(next);
    next[0] = .{ .event_type = event_type, .decision = result, .note = try allocator.dupe(u8, note) };
    @memcpy(next[1..], decision.audit_events);
    allocator.free(decision.audit_events);
    decision.audit_events = next;
    decision.audit_event_reference = event_type;
}

fn appendEvent(allocator: std.mem.Allocator, out: *std.ArrayList(EmergencyAuditEvent), event_type: []const u8, note: []const u8, result: core.decision.DecisionResult) !void {
    try out.append(allocator, .{
        .event_type = event_type,
        .decision = result,
        .note = try allocator.dupe(u8, note),
    });
}

fn fallbackOrder(allocator: std.mem.Allocator, policy: *const schema.edge_policy_schema.EdgePolicyV1) ![]EmergencyCommand {
    const order = try allocator.alloc(EmergencyCommand, policy.safety.emergency.fallback_order.len);
    for (policy.safety.emergency.fallback_order, 0..) |action, index| order[index] = commandFromAction(action);
    return order;
}

fn prioritizeReason(order: *[]EmergencyCommand, reason: EmergencyReason) void {
    switch (reason) {
        .critical_battery => moveToFront(order.*, .land),
        .low_battery => moveToFront(order.*, .return_to_home),
        else => {},
    }
}

fn moveToFront(order: []EmergencyCommand, command: EmergencyCommand) void {
    var found: ?usize = null;
    for (order, 0..) |candidate, index| {
        if (candidate == command) {
            found = index;
            break;
        }
    }
    const index = found orelse return;
    if (index == 0) return;
    const value = order[index];
    var cursor = index;
    while (cursor > 0) : (cursor -= 1) order[cursor] = order[cursor - 1];
    order[0] = value;
}

fn emergencyPolicyAllows(policy: *const schema.edge_policy_schema.EdgePolicyV1, command: EmergencyCommand) bool {
    return switch (command) {
        .land => policy.safety.emergency.allow_land,
        .return_to_home, .return_to_launch => policy.safety.emergency.allow_return_to_home,
        .hold_position => policy.safety.emergency.allow_hold_position,
        .stop_or_brake => policy.safety.emergency.allow_stop_or_brake,
        .disarm => policy.safety.emergency.allow_disarm,
        .unknown => false,
    };
}

fn allowLandOnStale(policy: *const schema.edge_policy_schema.EdgePolicyV1) bool {
    const freshness = policy.safety.state_freshness orelse return false;
    return freshness.allow_emergency_land_on_stale_state and policy.safety.emergency.allow_land;
}

fn allowReturnHomeOnStale(policy: *const schema.edge_policy_schema.EdgePolicyV1) bool {
    const freshness = policy.safety.state_freshness orelse return false;
    return freshness.allow_return_home_on_stale_state and policy.safety.emergency.allow_return_to_home;
}

fn actionFromCommand(command: EmergencyCommand) ?domain.commands.CommandAction {
    return switch (command) {
        .land => .land,
        .return_to_home, .return_to_launch => .return_to_home,
        .hold_position => .hold_position,
        .disarm => .disarm,
        else => null,
    };
}

fn commandFromAction(action: domain.commands.CommandAction) EmergencyCommand {
    return switch (action) {
        .land => .land,
        .return_to_home => .return_to_home,
        .hold_position => .hold_position,
        .disarm => .disarm,
        else => .unknown,
    };
}

test {
    _ = EmergencyDecision;
}
