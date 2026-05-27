const std = @import("std");

const domain = @import("../domain/mod.zig");
const policy = @import("../policy/mod.zig");
const safety = @import("../safety/mod.zig");
const operator = @import("../operator/mod.zig");
const schema = @import("../schema/mod.zig");
const audit_mod = @import("audit.zig");
const classifier = @import("classifier.zig");
const data_guard = @import("../data_guard/mod.zig");
const framing = @import("framing.zig");
const mapping = @import("mapping.zig");
const messages = @import("messages.zig");
const mission = @import("mission.zig");
const signing = @import("signing.zig");
const core = @import("orca_core");

pub const GatewayMode = enum {
    observe,
    enforce,
    ci,
    redteam,
    simulation,
    bench,
    disabled,
};

pub const Direction = enum {
    ground_to_vehicle,
    vehicle_to_ground,
    companion_to_vehicle,
    vehicle_to_companion,
    unknown,
};

pub const EndpointPolicy = struct {
    allowed_source_sysid: ?u8 = null,
    allowed_source_compid: ?u8 = null,
    allowed_target_sysid: ?u8 = null,
    allowed_target_compid: ?u8 = null,
    allow_unknown_endpoint_in_observe: bool = true,
};

pub const ProcessOptions = struct {
    mode: GatewayMode = .observe,
    direction: Direction = .unknown,
    vehicle_id: []const u8 = "edge-vehicle-1",
    now_ms: i128,
    command_source: domain.state.StateProvenance = .fake_adapter,
    endpoint_policy: EndpointPolicy = .{},
    approval_decision: ?*operator.ApprovalDecision = null,
};

pub const ProcessResult = struct {
    allocator: std.mem.Allocator,
    forwarded: bool = false,
    blocked: bool = false,
    decision: ?core.decision.DecisionResult = null,
    classification: classifier.Classification,
    audit: audit_mod.AuditLog,
    explanation: []u8,

    pub fn deinit(self: *ProcessResult) void {
        self.audit.deinit();
        self.allocator.free(self.explanation);
        self.* = undefined;
    }
};

pub fn processFrame(
    allocator: std.mem.Allocator,
    options: ProcessOptions,
    selected_policy: *const schema.edge_policy_schema.EdgePolicyV1,
    state: domain.state.VehicleState,
    frame: framing.Frame,
) !ProcessResult {
    var tracker = mission.MissionTracker.init();
    return processFrameInternal(allocator, options, selected_policy, state, frame, &tracker, false);
}

pub fn processMissionFrame(
    allocator: std.mem.Allocator,
    options: ProcessOptions,
    selected_policy: *const schema.edge_policy_schema.EdgePolicyV1,
    state: domain.state.VehicleState,
    frame: framing.Frame,
    tracker: *mission.MissionTracker,
) !ProcessResult {
    return processFrameInternal(allocator, options, selected_policy, state, frame, tracker, true);
}

fn processFrameInternal(
    allocator: std.mem.Allocator,
    options: ProcessOptions,
    selected_policy: *const schema.edge_policy_schema.EdgePolicyV1,
    state: domain.state.VehicleState,
    frame: framing.Frame,
    tracker: *mission.MissionTracker,
    track_mission: bool,
) !ProcessResult {
    var audit = audit_mod.AuditLog.init(allocator);
    errdefer audit.deinit();
    try audit.append(.frame_received, frame, .{ .note = provenanceNote(options), .decision = .observe });
    const class = try classifier.classifyFrame(frame);
    try audit.append(.message_classified, frame, .{ .note = class.message_name, .decision = .observe });
    if (frame.signature_present) {
        const inspection = signing.inspect(frame);
        try audit.append(.signing_detected, frame, .{ .note = inspection.note, .decision = .observe });
    }

    if (options.mode == .disabled) {
        try audit.append(.message_blocked, frame, .{ .note = "gateway disabled", .decision = .deny });
        return finish(allocator, audit, class, false, true, .deny, "gateway disabled");
    }

    if (endpointUnexpected(frame, options.endpoint_policy)) {
        try audit.append(.unexpected_endpoint, frame, .{ .note = "unexpected sysid/compid endpoint", .decision = .deny });
        if (strictLike(options.mode)) {
            try audit.append(.message_blocked, frame, .{ .note = "unexpected endpoint fail closed", .decision = .deny });
            return finish(allocator, audit, class, false, true, .deny, "unexpected endpoint");
        }
    }

    if (track_mission) {
        const decoded = try messages.decode(frame);
        try tracker.observe(decoded);
        switch (decoded) {
            .mission_count => try audit.append(.mission_upload_started, frame, .{ .note = "mission upload started", .decision = .observe }),
            .mission_item, .mission_item_int => try audit.append(.mission_item_observed, frame, .{ .note = "mission item observed", .decision = .observe }),
            .mission_ack => if (tracker.completed) try audit.append(.mission_upload_completed, frame, .{ .note = "mission upload completed", .decision = .allow }),
            else => {},
        }
    }

    var mapped = try mapping.mapFrameToCommand(allocator, frame, .{ .vehicle_id = options.vehicle_id, .now_ms = options.now_ms, .source = options.command_source });
    defer mapped.deinit();

    if (mapped.request) |request| {
        try audit.appendCommand(.command_mapped, frame, mapped.classification.command_id, .{ .note = @tagName(request.action), .decision = .observe });
        const context: safety.EvaluationContext = .{ .mode = policyMode(options.mode), .now_ms = options.now_ms, .non_interactive = options.mode == .ci or options.mode == .redteam };
        var evaluation = if (options.approval_decision) |approval|
            try safety.evaluateSafetyWithApproval(allocator, selected_policy, state, request, context, approval)
        else
            try safety.evaluateSafety(allocator, selected_policy, state, request, context);
        defer evaluation.deinit();

        const policy_decision = evaluation.decision.result;
        var gateway_decision = policy_decision;
        if (options.mode == .observe) gateway_decision = .observe;
        const should_forward = options.mode == .observe or gateway_decision == .allow or gateway_decision == .observe;
        const should_block = !should_forward;

        if (evaluation.hasAuditEvent("safety.geofence_violation")) try audit.append(.safety_geofence_violation, frame, .{ .note = evaluation.explanation, .decision = .deny });
        if (evaluation.hasAuditEvent("safety.altitude_violation")) try audit.append(.safety_altitude_violation, frame, .{ .note = evaluation.explanation, .decision = .deny });
        if (evaluation.hasAuditEvent("safety.velocity_violation")) try audit.append(.safety_velocity_violation, frame, .{ .note = evaluation.explanation, .decision = .deny });
        if (evaluation.hasAuditEvent("safety.stale_state_denied")) try audit.append(.safety_stale_state_denied, frame, .{ .note = evaluation.explanation, .decision = .deny });
        if (evaluation.hasAuditEvent("safety.battery_constraint")) try audit.append(.safety_battery_constraint, frame, .{ .note = evaluation.explanation, .decision = .deny });
        if (evaluation.hasAuditEvent("safety.mode_constraint")) try audit.append(.safety_mode_constraint, frame, .{ .note = evaluation.explanation, .decision = .deny });
        if (evaluation.hasAuditEvent("safety.authority_constraint")) try audit.append(.safety_authority_constraint, frame, .{ .note = evaluation.explanation, .decision = .deny });
        if (evaluation.hasAuditEvent("safety.mission_item_denied")) try audit.append(.safety_mission_item_denied, frame, .{ .note = evaluation.explanation, .decision = .deny });
        if (evaluation.hasAuditEvent("operator.approval_requested")) try audit.append(.operator_approval_required, frame, .{ .note = evaluation.explanation, .decision = .ask });
        if (evaluation.hasAuditEvent("operator.approval_used")) try audit.append(.operator_approval_used, frame, .{ .note = evaluation.explanation, .decision = .allow });
        if (evaluation.hasAuditEvent("operator.approval_invalid")) try audit.append(.operator_approval_invalid, frame, .{ .note = evaluation.explanation, .decision = .deny });
        if (should_block and track_mission and (frame.msgid == @import("dialect.zig").MISSION_ITEM or frame.msgid == @import("dialect.zig").MISSION_ITEM_INT)) {
            tracker.markDenied();
            try audit.appendCommand(.mission_item_denied, frame, mapped.classification.command_id, .{ .note = evaluation.explanation, .decision = .deny });
        }
        try appendDataGuardAudit(allocator, &audit, options, frame, if (track_mission) .mission_upload else .command_control, classesForFrame(frame, if (track_mission) .mission_upload else .command_control));
        switch (gateway_decision) {
            .allow => try audit.appendCommand(.command_allowed, frame, mapped.classification.command_id, .{ .note = evaluation.explanation, .decision = .allow }),
            .observe => try audit.appendCommand(.command_observed, frame, mapped.classification.command_id, .{ .note = evaluation.explanation, .decision = .observe }),
            .deny => try audit.appendCommand(.command_denied, frame, mapped.classification.command_id, .{ .note = evaluation.explanation, .decision = .deny }),
            .ask => try audit.appendCommand(.command_denied, frame, mapped.classification.command_id, .{ .note = "approval unavailable in gateway runtime", .decision = .deny }),
            else => try audit.appendCommand(.command_denied, frame, mapped.classification.command_id, .{ .note = "unsupported gateway decision", .decision = .deny }),
        }
        try audit.append(if (should_forward) .message_forwarded else .message_blocked, frame, .{ .note = evaluation.explanation, .decision = gateway_decision });
        return finish(allocator, audit, class, should_forward, should_block, gateway_decision, evaluation.explanation);
    }

    if (mapped.unsupported) |unsupported| {
        const forward = options.mode == .observe and (!class.safety_sensitive or options.endpoint_policy.allow_unknown_endpoint_in_observe);
        const decision: core.decision.DecisionResult = if (forward) .observe else .deny;
        try audit.appendCommand(.command_denied, frame, unsupported.command_id, .{ .note = unsupported.reason, .decision = decision });
        try appendDataGuardAudit(allocator, &audit, options, frame, .mavlink_telemetry, &.{ .vehicle_state, .vehicle_identifier });
        try audit.append(if (forward) .message_forwarded else .message_blocked, frame, .{ .note = unsupported.reason, .decision = decision });
        return finish(allocator, audit, class, forward, !forward, decision, unsupported.reason);
    }

    const forward_unknown = options.mode == .observe or !class.safety_sensitive;
    const decision: core.decision.DecisionResult = if (forward_unknown) .observe else .deny;
    try appendDataGuardAudit(allocator, &audit, options, frame, .mavlink_telemetry, &.{ .vehicle_state, .vehicle_identifier });
    try audit.append(if (forward_unknown) .message_forwarded else .message_blocked, frame, .{ .note = "unmapped MAVLink message", .decision = decision });
    return finish(allocator, audit, class, forward_unknown, !forward_unknown, decision, "unmapped MAVLink message");
}

fn finish(
    allocator: std.mem.Allocator,
    audit: audit_mod.AuditLog,
    class: classifier.Classification,
    forwarded: bool,
    blocked: bool,
    decision: core.decision.DecisionResult,
    explanation: []const u8,
) !ProcessResult {
    return .{
        .allocator = allocator,
        .forwarded = forwarded,
        .blocked = blocked,
        .decision = decision,
        .classification = class,
        .audit = audit,
        .explanation = try allocator.dupe(u8, explanation),
    };
}

fn policyMode(mode: GatewayMode) policy.EvaluationMode {
    return switch (mode) {
        .observe => .observe,
        .enforce => .ask,
        .ci => .ci,
        .redteam => .redteam,
        .simulation => .simulation,
        .bench => .bench,
        .disabled => .ci,
    };
}

fn strictLike(mode: GatewayMode) bool {
    return switch (mode) {
        .enforce, .ci, .redteam, .disabled => true,
        else => false,
    };
}

fn endpointUnexpected(frame: framing.Frame, endpoint_policy: EndpointPolicy) bool {
    if (endpoint_policy.allowed_source_sysid) |expected| if (frame.sysid != expected) return true;
    if (endpoint_policy.allowed_source_compid) |expected| if (frame.compid != expected) return true;
    if (endpoint_policy.allowed_target_sysid) |expected| {
        const actual = frame.targetSystem() orelse return true;
        if (actual != expected) return true;
    }
    if (endpoint_policy.allowed_target_compid) |expected| {
        const actual = frame.targetComponent() orelse return true;
        if (actual != expected) return true;
    }
    return false;
}

fn provenanceNote(options: ProcessOptions) []const u8 {
    return switch (options.command_source) {
        .fake_adapter => if (options.mode == .simulation) "provenance=fake_adapter/simulation" else "provenance=fake_adapter",
        .fake_ardupilot_adapter => if (options.mode == .simulation) "provenance=fake_ardupilot_adapter/simulation" else "provenance=fake_ardupilot_adapter",
        .sitl_px4 => "provenance=sitl_px4",
        .sitl_ardupilot => "provenance=sitl_ardupilot",
        .bench => "provenance=bench",
        .customer_adapter => "provenance=customer_adapter",
        .unknown => "provenance=unknown",
    };
}

fn appendDataGuardAudit(
    allocator: std.mem.Allocator,
    audit: *audit_mod.AuditLog,
    options: ProcessOptions,
    frame: framing.Frame,
    channel: data_guard.ChannelKind,
    classes: []const data_guard.DataClass,
) !void {
    var payload_buffer: [256]u8 = undefined;
    const payload_text = try std.fmt.bufPrint(
        &payload_buffer,
        "mavlink telemetry msgid={d} sysid={d} compid={d} vehicle_id={s}",
        .{ frame.msgid, frame.sysid, frame.compid, options.vehicle_id },
    );
    var evaluation = try data_guard.evaluateWithDefaultPolicy(allocator, .{
        .channel_kind = channel,
        .direction = if (options.direction == .vehicle_to_ground or options.direction == .vehicle_to_companion) .vehicle_to_agent else .agent_to_vehicle,
        .source = @tagName(options.command_source),
        .destination = endpointLabelForProvenance(options.command_source),
        .vehicle_id = options.vehicle_id,
        .provenance = @tagName(options.command_source),
        .payload = payload_text,
        .declared_classes = classes,
        .size_bytes = frame.payload.len,
        .timestamp_ms = options.now_ms,
    }, .{
        .host = "127.0.0.1",
        .port = endpointPortForProvenance(options.command_source),
        .protocol = "udp",
        .scheme = "udp",
        .label = endpointLabelForProvenance(options.command_source),
        .provenance = @tagName(options.command_source),
        .environment = endpointLabelForProvenance(options.command_source),
    }, .{
        .mode = dataGuardMode(options.mode),
        .ci = options.mode == .ci,
        .non_interactive = options.mode == .ci or options.mode == .redteam,
    });
    defer evaluation.deinit();
    for (evaluation.audit_payloads) |payload| {
        if (eventKindFromDataGuard(payload.event_type)) |kind| {
            try audit.append(kind, frame, .{ .note = evaluation.explanation, .decision = payload.decision.result });
        }
    }
}

fn classesForFrame(frame: framing.Frame, channel: data_guard.ChannelKind) []const data_guard.DataClass {
    _ = frame;
    return switch (channel) {
        .mission_upload, .mission_download => &.{ .mission_plan, .geolocation, .vehicle_identifier },
        .command_control => &.{ .operational, .vehicle_identifier },
        else => &.{ .vehicle_state, .vehicle_identifier },
    };
}

fn endpointLabelForProvenance(provenance: domain.state.StateProvenance) []const u8 {
    return switch (provenance) {
        .sitl_px4 => "px4_sitl",
        .sitl_ardupilot => "ardupilot_sitl",
        .fake_ardupilot_adapter => "fake_adapter",
        else => "fake_adapter",
    };
}

fn endpointPortForProvenance(provenance: domain.state.StateProvenance) ?u16 {
    return switch (provenance) {
        .sitl_px4 => 14540,
        .sitl_ardupilot, .fake_ardupilot_adapter => 14550,
        else => 14550,
    };
}

fn dataGuardMode(mode: GatewayMode) data_guard.telemetry_policy.EvaluationMode {
    return switch (mode) {
        .observe => .observe,
        .ci => .ci,
        .redteam => .redteam,
        .simulation => .simulation,
        .bench => .bench,
        .enforce, .disabled => .strict,
    };
}

fn eventKindFromDataGuard(event_type: []const u8) ?audit_mod.EventKind {
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
    return null;
}
