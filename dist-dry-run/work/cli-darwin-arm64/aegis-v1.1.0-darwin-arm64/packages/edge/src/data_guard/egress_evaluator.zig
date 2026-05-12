const std = @import("std");
const core = @import("aegis_core");

const data_classification = @import("data_classification.zig");
const endpoint_policy = @import("endpoint_policy.zig");
const link_guard = @import("link_guard.zig");
const network_audit = @import("network_audit.zig");
const network_finding = @import("network_finding.zig");
const payload_redaction = @import("payload_redaction.zig");
const telemetry_policy = @import("telemetry_policy.zig");

pub const EvaluationContext = struct {
    mode: telemetry_policy.EvaluationMode = .strict,
    now_ms: i128 = 0,
    ci: bool = false,
    non_interactive: bool = false,
    repeated_unknown_endpoint_attempts: usize = 0,
};

pub const EgressEvaluation = struct {
    allocator: std.mem.Allocator,
    decision: core.decision.Decision,
    data_classes: []data_classification.DataClass,
    sensitivity: data_classification.Sensitivity,
    endpoint_kind: endpoint_policy.EndpointKind,
    link_kind: link_guard.LinkKind,
    findings: []network_finding.NetworkFinding,
    matched_rules: []const []const u8,
    redactions_required: bool,
    approval_required: bool,
    explanation: []u8,
    audit_payloads: []network_audit.AuditPayload,
    redacted_payload: []u8,
    redacted_endpoint: []u8,
    fingerprint: [64]u8,

    pub fn deinit(self: *EgressEvaluation) void {
        self.allocator.free(self.data_classes);
        for (self.findings) |finding| finding.deinit(self.allocator);
        self.allocator.free(self.findings);
        for (self.matched_rules) |rule| self.allocator.free(rule);
        self.allocator.free(self.matched_rules);
        for (self.audit_payloads) |payload| payload.deinit(self.allocator);
        self.allocator.free(self.audit_payloads);
        self.allocator.free(self.explanation);
        self.allocator.free(self.redacted_payload);
        self.allocator.free(self.redacted_endpoint);
        self.* = undefined;
    }

    pub fn hasFindingCategory(self: EgressEvaluation, category: network_finding.FindingCategory) bool {
        for (self.findings) |finding| {
            if (finding.category == category) return true;
        }
        return false;
    }

    pub fn hasAuditEvent(self: EgressEvaluation, event_type: []const u8) bool {
        for (self.audit_payloads) |payload| {
            if (std.mem.eql(u8, payload.event_type, event_type)) return true;
        }
        return false;
    }
};

pub fn evaluateEgress(
    allocator: std.mem.Allocator,
    policy: telemetry_policy.Policy,
    payload: data_classification.TelemetryPayload,
    endpoint: endpoint_policy.Endpoint,
    context: EvaluationContext,
) !EgressEvaluation {
    var classification = try data_classification.classifyPayload(allocator, payload.payload);
    defer classification.deinit();
    const classes = if (payload.declared_classes.len > 0)
        try allocator.dupe(data_classification.DataClass, payload.declared_classes)
    else
        try allocator.dupe(data_classification.DataClass, classification.classes);
    errdefer allocator.free(classes);

    const sensitivity = payload.declared_sensitivity orelse data_classification.sensitivityForClasses(classes);
    const channel = if (payload.channel_kind != .unknown) payload.channel_kind else data_classification.inferChannel(.{ .allocator = allocator, .classes = classes, .sensitivity = sensitivity, .size_bytes = payload.effectiveSize(), .fingerprint = classification.fingerprint });
    var endpoint_classification = try endpoint_policy.classifyEndpoint(allocator, endpoint);
    defer endpoint_classification.deinit();
    const link = link_guard.classifyLink(channel, endpoint_classification.kind, payload.provenance);

    var findings: std.ArrayList(network_finding.NetworkFinding) = .empty;
    errdefer {
        for (findings.items) |finding| finding.deinit(allocator);
        findings.deinit(allocator);
    }
    var rules: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (rules.items) |rule| allocator.free(rule);
        rules.deinit(allocator);
    }

    const channel_decision = normalizeDecision(policy.resolveChannel(channel).decision, policy.mode, context);
    try rules.append(allocator, try allocator.dupe(u8, policy.resolveChannel(channel).rule_id));
    const endpoint_decision = normalizeDecision(policy.resolveEndpoint(endpoint, endpoint_classification).decision, policy.mode, context);
    try rules.append(allocator, try allocator.dupe(u8, policy.resolveEndpoint(endpoint, endpoint_classification).rule_id));

    var data_decision: core.decision.DecisionResult = .allow;
    for (classes) |class| {
        const class_decision = normalizeDecision(policy.resolveDataClass(class).decision, policy.mode, context);
        try rules.append(allocator, try allocator.dupe(u8, policy.resolveDataClass(class).rule_id));
        data_decision = combine(data_decision, class_decision);
        if (class == .unknown) {
            try network_finding.appendFinding(allocator, &findings, .payload_classification, .high, class_decision, endpoint_classification.kind, class, "data.payload_classified", "unknown payload class is not safe", .{});
        }
    }

    var decision_result = combine(combine(channel_decision, endpoint_decision), data_decision);
    try addPolicyFindings(allocator, &findings, channel, classes, endpoint_classification, decision_result);
    try detectHeuristics(allocator, &findings, policy, payload, endpoint, endpoint_classification, classes, context);
    if (hasExfilFinding(findings.items) and (context.mode == .strict or context.mode == .ci or context.mode == .redteam or policy.mode == .strict or policy.mode == .ci or policy.mode == .redteam)) {
        decision_result = .deny;
    }
    if (link.spoofing_suspected) {
        try network_finding.appendFinding(allocator, &findings, .link_guard, .high, .deny, endpoint_classification.kind, null, "link.command_control_observed", "{s}", .{link.reason});
        decision_result = .deny;
    }
    if (hasCritical(classes)) decision_result = .deny;
    if (payload.effectiveSize() > policy.egress.max_payload_bytes) {
        try network_finding.appendFinding(allocator, &findings, .exfiltration, .high, .deny, endpoint_classification.kind, null, "data.exfiltration_suspected", "payload size {d} exceeds configured maximum {d}", .{ payload.effectiveSize(), policy.egress.max_payload_bytes });
        decision_result = .deny;
    }
    if (policy.mode == .observe or context.mode == .observe) decision_result = .observe;

    const coarse_geo = shouldCoarsen(policy, classes);
    var redacted = try payload_redaction.redactPayload(allocator, payload.payload, classes, coarse_geo);
    defer redacted.deinit();
    if (redacted.redaction_required and !redacted.safe_to_persist and (policy.mode == .strict or policy.mode == .ci or policy.mode == .redteam)) decision_result = .deny;
    const approval_required = decision_result == .ask;
    const explanation = try std.fmt.allocPrint(
        allocator,
        "data guard decision: channel={s} endpoint={s} sensitivity={s} link={s} result={s}",
        .{ channel.toString(), endpoint_classification.kind.toString(), sensitivity.toString(), link.kind.toString(), decision_result.toString() },
    );
    errdefer allocator.free(explanation);
    const decision = core.api.makeDecision(.{
        .result = decision_result,
        .rule_id = if (rules.items.len > 0) rules.items[0] else null,
        .reason = explanation,
        .risk_score = riskScore(sensitivity, endpoint_classification.suspicious),
        .requires_user = approval_required,
        .ci_may_proceed = decision_result == .allow or decision_result == .observe,
    });

    var audit_payloads: std.ArrayList(network_audit.AuditPayload) = .empty;
    errdefer {
        for (audit_payloads.items) |item| item.deinit(allocator);
        audit_payloads.deinit(allocator);
    }
    try audit_payloads.append(allocator, try network_audit.makePayload(allocator, "data.payload_classified", endpoint_classification, channel, decision));
    if (redacted.redaction_required) try audit_payloads.append(allocator, try network_audit.makePayload(allocator, "data.payload_redacted", endpoint_classification, channel, decision));
    try audit_payloads.append(allocator, try network_audit.makePayload(allocator, "data.egress_requested", endpoint_classification, channel, decision));
    const event_type = switch (decision_result) {
        .allow => "data.egress_allowed",
        .deny => "data.egress_denied",
        .observe => "data.egress_observed",
        .ask => "data.egress_denied",
        else => "data.egress_denied",
    };
    try audit_payloads.append(allocator, try network_audit.makePayload(allocator, event_type, endpoint_classification, channel, decision));
    if (hasExfilFinding(findings.items)) try audit_payloads.append(allocator, try network_audit.makePayload(allocator, "data.exfiltration_suspected", endpoint_classification, channel, decision));
    try audit_payloads.append(allocator, try network_audit.makePayload(allocator, "data.endpoint_classified", endpoint_classification, channel, decision));
    try audit_payloads.append(allocator, try network_audit.makePayload(allocator, telemetryEventForDecision(channel, decision_result), endpoint_classification, channel, decision));

    const endpoint_copy = try allocator.dupe(u8, endpoint_classification.redacted_endpoint);
    errdefer allocator.free(endpoint_copy);
    const redacted_payload = try allocator.dupe(u8, redacted.text);
    errdefer allocator.free(redacted_payload);

    return .{
        .allocator = allocator,
        .decision = decision,
        .data_classes = classes,
        .sensitivity = sensitivity,
        .endpoint_kind = endpoint_classification.kind,
        .link_kind = link.kind,
        .findings = try findings.toOwnedSlice(allocator),
        .matched_rules = try rules.toOwnedSlice(allocator),
        .redactions_required = redacted.redaction_required,
        .approval_required = approval_required,
        .explanation = explanation,
        .audit_payloads = try audit_payloads.toOwnedSlice(allocator),
        .redacted_payload = redacted_payload,
        .redacted_endpoint = endpoint_copy,
        .fingerprint = classification.fingerprint,
    };
}

pub fn evaluateWithDefaultPolicy(
    allocator: std.mem.Allocator,
    payload: data_classification.TelemetryPayload,
    endpoint: endpoint_policy.Endpoint,
    context: EvaluationContext,
) !EgressEvaluation {
    return evaluateEgress(allocator, telemetry_policy.defaultSimulationPolicy(), payload, endpoint, context);
}

fn normalizeDecision(decision: core.decision.DecisionResult, mode: telemetry_policy.EvaluationMode, context: EvaluationContext) core.decision.DecisionResult {
    if (mode == .observe or context.mode == .observe) return .observe;
    if (decision == .ask and (mode == .ci or context.ci or context.non_interactive)) return .deny;
    return decision;
}

fn combine(left: core.decision.DecisionResult, right: core.decision.DecisionResult) core.decision.DecisionResult {
    if (left == .deny or right == .deny) return .deny;
    if (left == .ask or right == .ask) return .ask;
    if (left == .observe or right == .observe) return .observe;
    return .allow;
}

fn shouldCoarsen(policy: telemetry_policy.Policy, classes: []const data_classification.DataClass) bool {
    for (classes) |class| {
        if (class == .geolocation and policy.precisionForClass(class) == .coarse) return true;
    }
    return false;
}

fn hasCritical(classes: []const data_classification.DataClass) bool {
    return payload_redaction.hasClass(classes, .secret) or payload_redaction.hasClass(classes, .credential);
}

fn addPolicyFindings(
    allocator: std.mem.Allocator,
    findings: *std.ArrayList(network_finding.NetworkFinding),
    channel: data_classification.ChannelKind,
    classes: []const data_classification.DataClass,
    endpoint_classification: endpoint_policy.Classification,
    decision: core.decision.DecisionResult,
) !void {
    if (endpoint_classification.suspicious) {
        try network_finding.appendFinding(allocator, findings, .endpoint_policy, .high, decision, endpoint_classification.kind, null, "data.endpoint_classified", "{s}", .{endpoint_classification.reason});
    }
    for (classes) |class| {
        const severity: network_finding.Severity = switch (data_classification.defaultSensitivity(class)) {
            .critical => .critical,
            .high => .high,
            .medium => .medium,
            else => .info,
        };
        if (severity != .info) try network_finding.appendFinding(allocator, findings, .data_policy, severity, decision, endpoint_classification.kind, class, "data.payload_classified", "sensitive data class {s} observed on channel {s}", .{ class.toString(), channel.toString() });
    }
}

fn detectHeuristics(
    allocator: std.mem.Allocator,
    findings: *std.ArrayList(network_finding.NetworkFinding),
    policy: telemetry_policy.Policy,
    payload: data_classification.TelemetryPayload,
    endpoint: endpoint_policy.Endpoint,
    endpoint_classification: endpoint_policy.Classification,
    classes: []const data_classification.DataClass,
    context: EvaluationContext,
) !void {
    if (policy.egress.detect_long_query_strings and endpoint.query.len > 256) {
        try network_finding.appendFinding(allocator, findings, .exfiltration, .high, .deny, endpoint_classification.kind, null, "data.exfiltration_suspected", "long query string detected", .{});
    }
    if (policy.egress.detect_high_entropy_labels and endpoint_policy.looksHighEntropyLabel(endpoint.host)) {
        try network_finding.appendFinding(allocator, findings, .exfiltration, .high, .deny, endpoint_classification.kind, null, "data.exfiltration_suspected", "high-entropy endpoint label detected", .{});
    }
    if (endpoint_policy.isIpLiteral(endpoint.host) and endpoint_classification.kind == .direct_ip) {
        try network_finding.appendFinding(allocator, findings, .exfiltration, .medium, .deny, endpoint_classification.kind, null, "data.exfiltration_suspected", "direct IP egress detected", .{});
    }
    if (endpoint_classification.kind == .webhook or endpoint_classification.kind == .tunnel_service or endpoint_classification.kind == .paste_site) {
        try network_finding.appendFinding(allocator, findings, .exfiltration, .high, .deny, endpoint_classification.kind, null, "data.exfiltration_suspected", "suspicious endpoint kind {s}", .{endpoint_classification.kind.toString()});
    }
    if (context.repeated_unknown_endpoint_attempts >= 3 and endpoint_classification.kind == .unknown) {
        try network_finding.appendFinding(allocator, findings, .exfiltration, .medium, .deny, endpoint_classification.kind, null, "data.exfiltration_suspected", "repeated unknown endpoint attempts detected", .{});
    }
    if (policy.egress.detect_secret_patterns and data_classification.containsAny(payload.payload, &.{ "fake_secret", "api_key", "authorization", "bearer ", "private_key" })) {
        try network_finding.appendFinding(allocator, findings, .exfiltration, .critical, .deny, endpoint_classification.kind, .secret, "data.exfiltration_suspected", "secret-like payload pattern detected", .{});
    }
    if (looksBase64Fragment(payload.payload)) {
        try network_finding.appendFinding(allocator, findings, .exfiltration, .medium, .deny, endpoint_classification.kind, null, "data.exfiltration_suspected", "base64-like payload fragment detected", .{});
    }
    if ((payload_redaction.hasClass(classes, .mission_plan) or payload_redaction.hasClass(classes, .geolocation) or payload_redaction.hasClass(classes, .video_stream) or payload_redaction.hasClass(classes, .image_frame)) and (endpoint_classification.kind == .unknown or endpoint_classification.suspicious)) {
        try network_finding.appendFinding(allocator, findings, .exfiltration, .high, .deny, endpoint_classification.kind, null, "data.exfiltration_suspected", "sensitive vehicle data sent to unknown or suspicious endpoint", .{});
    }
    if (data_classification.containsAny(payload.payload, &.{ "mavlink", "sysid", "compid", "MISSION_ITEM", "COMMAND_LONG" }) and endpoint_classification.kind != .ground_control_station and endpoint_classification.kind != .px4_sitl and endpoint_classification.kind != .ardupilot_sitl and endpoint_classification.kind != .fake_adapter) {
        try network_finding.appendFinding(allocator, findings, .exfiltration, .medium, .deny, endpoint_classification.kind, null, "data.exfiltration_suspected", "MAVLink-like payload sent outside allowlisted simulation/control endpoint", .{});
    }
}

fn hasExfilFinding(findings: []const network_finding.NetworkFinding) bool {
    for (findings) |finding| {
        if (finding.category == .exfiltration) return true;
    }
    return false;
}

fn telemetryEventForDecision(channel: data_classification.ChannelKind, decision: core.decision.DecisionResult) []const u8 {
    _ = channel;
    return switch (decision) {
        .allow => "telemetry.channel_allowed",
        .deny => "telemetry.channel_denied",
        else => "telemetry.channel_observed",
    };
}

fn riskScore(sensitivity: data_classification.Sensitivity, suspicious_endpoint: bool) u8 {
    const base: u8 = switch (sensitivity) {
        .low => 10,
        .medium => 35,
        .high => 70,
        .critical, .unknown => 95,
    };
    return if (suspicious_endpoint and base < 85) base + 15 else base;
}

fn looksBase64Fragment(payload: []const u8) bool {
    var tokens = std.mem.tokenizeAny(u8, payload, " \t\r\n,{}[]:\"'");
    while (tokens.next()) |token| {
        if (token.len < 48) continue;
        var ok = true;
        var padding: usize = 0;
        for (token) |char| {
            if (char == '=') padding += 1 else if (!(std.ascii.isAlphanumeric(char) or char == '+' or char == '/' or char == '-' or char == '_')) {
                ok = false;
                break;
            }
        }
        if (ok and padding <= 2) return true;
    }
    return false;
}

test "mission plan to webhook is denied and audited" {
    var eval = try evaluateEgress(std.testing.allocator, telemetry_policy.defaultSimulationPolicy(), .{
        .channel_kind = .mission_upload,
        .direction = .outbound,
        .payload = "{\"mission_plan\":{\"waypoints\":[{\"latitude\":37.0,\"longitude\":-122.0}]}}",
        .provenance = "fake_adapter",
    }, .{ .host = "abc.webhook.site", .scheme = "https", .label = "webhook" }, .{ .mode = .strict });
    defer eval.deinit();
    try std.testing.expectEqual(core.decision.DecisionResult.deny, eval.decision.result);
    try std.testing.expect(eval.hasFindingCategory(.exfiltration));
    try std.testing.expect(eval.hasAuditEvent("data.egress_denied"));
}

test "safety report to explicit customer endpoint is allowed" {
    const policy: telemetry_policy.Policy = .{
        .mode = .strict,
        .default_decision = .deny,
        .telemetry_rules = &.{.{ .channel = .safety_case_report, .decision = .allow, .id = "telemetry.allow.safety_case_report" }},
        .endpoint_rules = &.{.{ .label = "customer_endpoint", .host_pattern = "reports.customer.internal", .decision = .allow, .id = "endpoint.allow.customer" }},
        .data_class_rules = &.{ .{ .class = .safety_finding, .default_decision = .allow, .id = "data_class.allow.safety" }, .{ .class = .audit_metadata, .default_decision = .allow, .id = "data_class.allow.audit" } },
    };
    var eval = try evaluateEgress(std.testing.allocator, policy, .{
        .channel_kind = .safety_case_report,
        .direction = .edge_to_customer_endpoint,
        .payload = "{\"safety_case\":{\"finding\":\"deny proof\"},\"audit\":\"hash\"}",
        .provenance = "fake_adapter",
    }, .{ .host = "reports.customer.internal", .scheme = "https", .label = "customer_endpoint" }, .{ .mode = .strict });
    defer eval.deinit();
    try std.testing.expectEqual(core.decision.DecisionResult.allow, eval.decision.result);
}
