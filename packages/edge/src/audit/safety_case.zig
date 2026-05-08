const std = @import("std");
const core = @import("aegis_core");

const ardupilot = @import("../ardupilot/mod.zig");
const domain = @import("../domain/mod.zig");
const emergency = @import("../emergency/mod.zig");
const operator = @import("../operator/mod.zig");
const policy = @import("../policy/mod.zig");
const px4 = @import("../px4/mod.zig");
const safety = @import("../safety/mod.zig");
const mission_safety = @import("../safety/mission_safety.zig");
const schema = @import("../schema/mod.zig");

const artifacts = @import("edge_artifacts.zig");
const edge_event = @import("edge_event.zig");
const edge_session = @import("edge_session.zig");
const evidence_bundle = @import("evidence_bundle.zig");
const safety_report = @import("safety_report.zig");
const traceability = @import("traceability.zig");

pub const GenerateOptions = struct {
    policy_path: []const u8,
    scenario_path: []const u8,
    workspace_root: ?[]const u8 = null,
    now: ?core.core.time.Timestamp = null,
};

pub const GenerateResult = struct {
    allocator: std.mem.Allocator,
    session_id: []u8,
    session_dir: []u8,
    status: safety_report.ScenarioResultStatus,
    summary: []u8,

    pub fn deinit(self: *GenerateResult) void {
        self.allocator.free(self.session_id);
        self.allocator.free(self.session_dir);
        self.allocator.free(self.summary);
        self.* = undefined;
    }
};

const ScenarioKind = enum {
    safety,
    px4,
    ardupilot,
    operator_approval,
    emergency,
};

const ScenarioMeta = struct {
    allocator: std.mem.Allocator,
    id: []u8,
    command: []u8,
    environment: []u8,
    expected_decision: ?core.decision.DecisionResult = null,
    expected_command: ?[]u8 = null,
    request_path: ?[]u8 = null,
    state_path: ?[]u8 = null,
    reason: ?[]u8 = null,
    approval_seed: operator.ApprovalSeedKind = .none,
    note: []u8,

    fn deinit(self: *ScenarioMeta) void {
        self.allocator.free(self.id);
        self.allocator.free(self.command);
        self.allocator.free(self.environment);
        if (self.expected_command) |value| self.allocator.free(value);
        if (self.request_path) |value| self.allocator.free(value);
        if (self.state_path) |value| self.allocator.free(value);
        if (self.reason) |value| self.allocator.free(value);
        self.allocator.free(self.note);
        self.* = undefined;
    }
};

const EvidenceModel = struct {
    allocator: std.mem.Allocator,
    scenario_id: []u8,
    command_name: []u8,
    decision: []u8,
    reason: []u8,
    rule: []u8,
    provenance: safety_report.Provenance,
    vehicle_kind: []u8,
    autopilot_kind: []u8,
    adapter_kind: []u8,
    vehicle_type: []u8,
    tested_version: []u8,
    endpoint: []u8,
    status: safety_report.ScenarioResultStatus,
    commands: []safety_report.CommandRecord,
    findings: []safety_report.FindingRecord,
    approvals: []safety_report.ApprovalRecord,
    emergencies: []safety_report.EmergencyRecord,
    traceability_rows: []safety_report.TraceabilityRow,
    audit_event_refs: []const []const u8,
    summary: []u8,

    fn deinit(self: *EvidenceModel) void {
        self.allocator.free(self.scenario_id);
        self.allocator.free(self.command_name);
        self.allocator.free(self.decision);
        self.allocator.free(self.reason);
        self.allocator.free(self.rule);
        self.allocator.free(self.vehicle_kind);
        self.allocator.free(self.autopilot_kind);
        self.allocator.free(self.adapter_kind);
        self.allocator.free(self.vehicle_type);
        self.allocator.free(self.tested_version);
        self.allocator.free(self.endpoint);
        for (self.commands) |record| freeCommandRecord(self.allocator, record);
        self.allocator.free(self.commands);
        for (self.findings) |record| freeFindingRecord(self.allocator, record);
        self.allocator.free(self.findings);
        for (self.approvals) |record| freeApprovalRecord(self.allocator, record);
        self.allocator.free(self.approvals);
        for (self.emergencies) |record| freeEmergencyRecord(self.allocator, record);
        self.allocator.free(self.emergencies);
        for (self.traceability_rows) |record| freeTraceabilityRow(self.allocator, record);
        self.allocator.free(self.traceability_rows);
        for (self.audit_event_refs) |value| self.allocator.free(value);
        self.allocator.free(self.audit_event_refs);
        self.allocator.free(self.summary);
        self.* = undefined;
    }
};

pub fn generate(allocator: std.mem.Allocator, options: GenerateOptions) !GenerateResult {
    const workspace_root = if (options.workspace_root) |root| try allocator.dupe(u8, root) else try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(workspace_root);
    const now = options.now orelse core.core.time.Timestamp.now();
    var session: core.session.Session = .{
        .id = try core.session.generateSessionId(now),
        .started_at = now,
        .command = "aegis-edge",
        .args = &.{ "safety-case", "generate" },
        .workspace_root = workspace_root,
        .session_name = "edge-safety-case",
        .mode = .strict,
        .platform = core.platform.detectOs(),
    };

    var writer = try edge_session.createWriter(allocator, session);
    defer writer.deinit();
    const session_dir = try allocator.dupe(u8, writer.sessionDirPath());
    errdefer allocator.free(session_dir);
    const evidence_dir = try std.fs.path.join(allocator, &.{ session_dir, "evidence" });
    defer allocator.free(evidence_dir);
    const artifacts_dir = try std.fs.path.join(allocator, &.{ session_dir, "artifacts", "logs" });
    defer allocator.free(artifacts_dir);
    try std.fs.cwd().makePath(evidence_dir);
    try std.fs.cwd().makePath(artifacts_dir);

    var sequence: usize = 0;
    var event_refs: std.ArrayList([]const u8) = .empty;
    defer {
        for (event_refs.items) |value| allocator.free(value);
        event_refs.deinit(allocator);
    }

    _ = try appendEvent(allocator, &writer, &sequence, &event_refs, session, now, "edge.session_start", .session, session.id.slice(), .observe, "edge safety-case session started");
    _ = try appendEvent(allocator, &writer, &sequence, &event_refs, session, now, "edge.scenario_start", .edge_safety_envelope, options.scenario_path, .observe, "scenario evidence collection started");

    var loaded = try policy.loadFile(allocator, options.policy_path, .{});
    defer loaded.deinit();
    var meta = try loadScenarioMeta(allocator, options.scenario_path);
    defer meta.deinit();
    const kind = classifyScenarioKind(options.scenario_path, meta);
    const policy_hash_value = try artifacts.fileSha256Hex(allocator, options.policy_path);

    var evidence = try buildEvidence(allocator, kind, &loaded.value, meta, options, artifacts_dir);
    defer evidence.deinit();

    _ = try appendEvent(allocator, &writer, &sequence, &event_refs, session, now, "edge.environment_detected", .edge_safety_envelope, evidence.provenance.toString(), .observe, "scenario provenance detected");
    for (evidence.audit_event_refs) |event_type| {
        const decision = if (std.mem.eql(u8, evidence.decision, "deny")) core.decision.DecisionResult.deny else if (std.mem.eql(u8, evidence.decision, "allow")) core.decision.DecisionResult.allow else .observe;
        _ = try appendEvent(allocator, &writer, &sequence, &event_refs, session, now, event_type, .edge_safety_envelope, evidence.reason, decision, evidence.reason);
    }
    _ = try appendEvent(allocator, &writer, &sequence, &event_refs, session, now, "safety_case.evidence_collected", .edge_safety_envelope, options.scenario_path, .observe, "safety-case evidence collected");
    _ = try appendEvent(allocator, &writer, &sequence, &event_refs, session, now, "safety_case.generated", .edge_safety_envelope, meta.id, .observe, "safety-case report generated");
    _ = try appendEvent(allocator, &writer, &sequence, &event_refs, session, now, "edge.scenario_exit", .edge_safety_envelope, evidence.status.toString(), .observe, "scenario evidence collection completed");
    _ = try appendEvent(allocator, &writer, &sequence, &event_refs, session, now, "edge.session_exit", .session, session.id.slice(), .observe, "edge safety-case session completed");
    try assignActualEventIds(allocator, &evidence, event_refs.items);

    const final_hash = writer.finalHash() orelse "";
    session.ended_at = now;
    try core.api.writeAuditSummary(allocator, writer.sessionDirPath(), .{
        .session = session,
        .status = .{ .exited = 0 },
        .event_count = writer.event_count,
        .final_event_hash = final_hash,
        .policy = options.policy_path,
    });
    try writer.writeLastPointer();

    const verify_result = try core.api.verifyReplay(allocator, writer.sessionDirPath());
    defer verify_result.deinit(allocator);

    try writeEvidenceFiles(allocator, evidence_dir, options, meta, evidence, policy_hash_value, final_hash);
    const replay_md_path = try std.fs.path.join(allocator, &.{ evidence_dir, "replay.md" });
    defer allocator.free(replay_md_path);
    try writeReplayMarkdown(allocator, workspace_root, session.id.slice(), replay_md_path);

    const report_id = try std.fmt.allocPrint(allocator, "aegis-edge-report-{s}", .{session.id.slice()});
    defer allocator.free(report_id);
    const generated_at = try isoAlloc(allocator, now);
    defer allocator.free(generated_at);
    const report_hash_value = safety_report.computeReportHash(report_id, session.id.slice(), evidence.scenario_id, &policy_hash_value, evidence.status);
    const report_hash_text = report_hash_value[0..];
    const limitations = defaultLimitations();
    const artifact_list = defaultArtifactList();
    const report = safety_report.Report{
        .report_id = report_id,
        .generated_at = generated_at,
        .scenario_id = evidence.scenario_id,
        .scenario_name = meta.id,
        .scenario_source = options.scenario_path,
        .session_id = session.id.slice(),
        .policy_file = options.policy_path,
        .policy_hash = &policy_hash_value,
        .report_hash = report_hash_text,
        .provenance = evidence.provenance,
        .vehicle_id = "edge-vehicle-1",
        .vehicle_kind = evidence.vehicle_kind,
        .autopilot_kind = evidence.autopilot_kind,
        .adapter_kind = evidence.adapter_kind,
        .vehicle_type = evidence.vehicle_type,
        .tested_autopilot_version = evidence.tested_version,
        .endpoint_config = evidence.endpoint,
        .started_at = generated_at,
        .ended_at = generated_at,
        .result_status = evidence.status,
        .conclusion = evidence.summary,
        .replay_verified = verify_result.ok,
        .final_hash = final_hash,
        .commands = evidence.commands,
        .findings = evidence.findings,
        .approvals = evidence.approvals,
        .emergencies = evidence.emergencies,
        .traceability = evidence.traceability_rows,
        .audit_event_references = event_refs.items,
        .artifacts_generated = artifact_list,
        .limitations = limitations,
    };

    const report_json_path = try std.fs.path.join(allocator, &.{ session_dir, "safety-report.json" });
    defer allocator.free(report_json_path);
    const report_md_path = try std.fs.path.join(allocator, &.{ session_dir, "safety-report.md" });
    defer allocator.free(report_md_path);
    try safety_report.writeJsonFile(report_json_path, report);
    try safety_report.writeMarkdownFile(report_md_path, report);

    const final_hash_path = try std.fs.path.join(allocator, &.{ session_dir, "final-hash.txt" });
    defer allocator.free(final_hash_path);
    try artifacts.writeHashFile(allocator, final_hash_path, final_hash);

    const summary = try std.fmt.allocPrint(
        allocator,
        "Safety case generated: session={s} status={s} provenance={s} report={s}",
        .{ session.id.slice(), evidence.status.toString(), evidence.provenance.toString(), report_md_path },
    );
    return .{
        .allocator = allocator,
        .session_id = try allocator.dupe(u8, session.id.slice()),
        .session_dir = session_dir,
        .status = evidence.status,
        .summary = summary,
    };
}

pub fn verify(allocator: std.mem.Allocator, workspace_root: []const u8, session: []const u8) !core.api.VerifyResult {
    return edge_session.verifySession(allocator, workspace_root, session);
}

pub fn bundle(allocator: std.mem.Allocator, workspace_root: []const u8, session: []const u8) ![]u8 {
    const session_id = try edge_session.resolveSessionId(allocator, workspace_root, session);
    defer allocator.free(session_id);
    const session_dir = try edge_session.sessionDirPath(allocator, workspace_root, session_id);
    defer allocator.free(session_dir);
    return evidence_bundle.create(allocator, session_dir);
}

pub fn show(writer: anytype, allocator: std.mem.Allocator, workspace_root: []const u8, session: []const u8, json: bool) !void {
    const session_id = try edge_session.resolveSessionId(allocator, workspace_root, session);
    defer allocator.free(session_id);
    const session_dir = try edge_session.sessionDirPath(allocator, workspace_root, session_id);
    defer allocator.free(session_dir);
    const file_name = if (json) "safety-report.json" else "safety-report.md";
    const path = try std.fs.path.join(allocator, &.{ session_dir, file_name });
    defer allocator.free(path);
    const text = try artifacts.readBounded(allocator, path);
    defer allocator.free(text);
    try writer.writeAll(text);
}

pub fn classifyScenarioResult(actual: ?core.decision.DecisionResult, expected: ?core.decision.DecisionResult, skipped: bool, unsupported: bool, evidence_complete: bool) safety_report.ScenarioResultStatus {
    if (skipped) return .skipped;
    if (unsupported) return .unsupported;
    if (!evidence_complete or actual == null) return .inconclusive;
    if (expected) |value| return if (actual.? == value) .passed else .failed;
    return .inconclusive;
}

fn buildEvidence(
    allocator: std.mem.Allocator,
    kind: ScenarioKind,
    selected_policy: *const schema.edge_policy_schema.EdgePolicyV1,
    meta: ScenarioMeta,
    options: GenerateOptions,
    artifact_dir: []const u8,
) !EvidenceModel {
    return switch (kind) {
        .safety => buildSafetyEvidence(allocator, selected_policy, meta, options, artifact_dir),
        .px4 => buildPx4Evidence(allocator, meta, options, artifact_dir),
        .ardupilot => buildArduPilotEvidence(allocator, meta, options, artifact_dir),
        .operator_approval => buildApprovalEvidence(allocator, selected_policy, meta),
        .emergency => buildEmergencyEvidence(allocator, selected_policy, meta),
    };
}

fn buildSafetyEvidence(
    allocator: std.mem.Allocator,
    selected_policy: *const schema.edge_policy_schema.EdgePolicyV1,
    meta: ScenarioMeta,
    options: GenerateOptions,
    artifact_dir: []const u8,
) !EvidenceModel {
    var scenario_result = try safety.scenario.run(allocator, .{
        .policy_path = options.policy_path,
        .scenario_path = options.scenario_path,
        .artifact_dir = artifact_dir,
    });
    defer scenario_result.deinit();

    var evaluation = try evaluateSafetyMeta(allocator, selected_policy, meta);
    defer evaluation.deinit();
    return evidenceFromSafetyEvaluation(allocator, selected_policy, meta, evaluation, classifyScenarioResult(evaluation.decision.result, meta.expected_decision, false, false, true), .fake_adapter, scenario_result.summary);
}

fn buildPx4Evidence(allocator: std.mem.Allocator, meta: ScenarioMeta, options: GenerateOptions, artifact_dir: []const u8) !EvidenceModel {
    var result = try px4.scenario.run(allocator, .{
        .policy_path = options.policy_path,
        .scenario_path = options.scenario_path,
        .artifact_dir = artifact_dir,
    });
    defer result.deinit();
    const provenance: safety_report.Provenance = if (result.environment == .px4_sitl) .px4_sitl else .fake_px4;
    const status = classifyScenarioResult(result.decision, meta.expected_decision, result.skipped, false, true);
    return genericEvidence(allocator, meta, status, provenance, if (result.decision) |decision| decision.toString() else "none", if (result.skipped) "PX4 SITL unavailable; no fake pass recorded" else result.summary, "px4", "mavlink", "documented-by-phase-29", "127.0.0.1:14540");
}

fn buildArduPilotEvidence(allocator: std.mem.Allocator, meta: ScenarioMeta, options: GenerateOptions, artifact_dir: []const u8) !EvidenceModel {
    var result = try ardupilot.scenario.run(allocator, .{
        .policy_path = options.policy_path,
        .scenario_path = options.scenario_path,
        .artifact_dir = artifact_dir,
    });
    defer result.deinit();
    const provenance: safety_report.Provenance = if (result.environment == .ardupilot_sitl) .ardupilot_sitl else .fake_ardupilot;
    const status = classifyScenarioResult(result.decision, meta.expected_decision, result.skipped, false, true);
    return genericEvidence(allocator, meta, status, provenance, if (result.decision) |decision| decision.toString() else "none", if (result.skipped) "ArduPilot SITL unavailable; no fake pass recorded" else result.summary, "ardupilot", "mavlink", "documented-by-phase-30", "127.0.0.1:14550");
}

fn buildApprovalEvidence(allocator: std.mem.Allocator, selected_policy: *const schema.edge_policy_schema.EdgePolicyV1, meta: ScenarioMeta) !EvidenceModel {
    const request_path = meta.request_path orelse return error.EdgeEvidenceMissing;
    const state_path = meta.state_path orelse return error.EdgeEvidenceMissing;
    const request_text = try artifacts.readBounded(allocator, request_path);
    defer allocator.free(request_text);
    const state_text = try artifacts.readBounded(allocator, state_path);
    defer allocator.free(state_text);
    var parsed_request = try policy.parseCommandRequestJsonOwned(allocator, request_text);
    defer parsed_request.deinit();
    var parsed_state = try policy.parseVehicleStateJsonOwned(allocator, state_text);
    defer parsed_state.deinit();
    var base = try safety.evaluateSafety(allocator, selected_policy, parsed_state.value, parsed_request.value, .{ .mode = .ask, .now_ms = parsed_state.value.timestamp.value + 500 });
    defer base.deinit();
    var approval_decision = (try operator.createSeededApprovalDecision(allocator, meta.approval_seed, .{
        .policy = selected_policy,
        .command = parsed_request.value,
        .state = parsed_state.value,
        .evaluation = base,
        .now_ms = parsed_state.value.timestamp.value + 500,
        .actor_id = "aegis-edge-safety-case",
    })) orelse return evidenceFromSafetyEvaluation(allocator, selected_policy, meta, base, classifyScenarioResult(base.decision.result, meta.expected_decision, false, false, true), provenanceFromState(parsed_state.value.provenance), "operator approval was required but not supplied");
    defer approval_decision.deinit(allocator);
    var final = try safety.evaluateSafetyWithApproval(allocator, selected_policy, parsed_state.value, parsed_request.value, .{ .mode = .ask, .now_ms = parsed_state.value.timestamp.value + 500 }, approval_decision);
    defer final.deinit();
    var model = try evidenceFromSafetyEvaluation(allocator, selected_policy, meta, final, classifyScenarioResult(final.decision.result, meta.expected_decision, false, false, true), provenanceFromState(parsed_state.value.provenance), "operator approval scenario evaluated with bounded local approval");
    model.approvals = try allocator.alloc(safety_report.ApprovalRecord, 1);
    model.approvals[0] = .{
        .approval_id = try allocator.dupe(u8, approval_decision.approval_decision_id),
        .command = try allocator.dupe(u8, meta.command),
        .decision = try allocator.dupe(u8, @tagName(approval_decision.decision)),
        .event_id = try allocator.dupe(u8, "operator.approval_used"),
    };
    return model;
}

fn buildEmergencyEvidence(allocator: std.mem.Allocator, selected_policy: *const schema.edge_policy_schema.EdgePolicyV1, meta: ScenarioMeta) !EvidenceModel {
    const state_path = meta.state_path orelse return error.EdgeEvidenceMissing;
    const reason_text = meta.reason orelse "unknown";
    const reason = std.meta.stringToEnum(emergency.EmergencyReason, reason_text) orelse .unknown;
    const state_text = try artifacts.readBounded(allocator, state_path);
    defer allocator.free(state_text);
    var parsed_state = try policy.parseVehicleStateJsonOwned(allocator, state_text);
    defer parsed_state.deinit();
    var decision = try emergency.evaluateFallback(allocator, selected_policy, parsed_state.value, reason, .{ .now_ms = parsed_state.value.timestamp.value + 500 });
    defer decision.deinit(allocator);
    const expected_ok = if (meta.expected_command) |expected| std.mem.eql(u8, expected, @tagName(decision.command)) else false;
    const status: safety_report.ScenarioResultStatus = if (expected_ok and decision.status == .emergency_allowed) .passed else .failed;
    var model = try genericEvidence(allocator, meta, status, provenanceFromState(parsed_state.value.provenance), decision.policy_decision.toString(), decision.safety_findings, @tagName(parsed_state.value.autopilot_kind), "fake", "n/a", "not configured");
    model.emergencies = try allocator.alloc(safety_report.EmergencyRecord, 1);
    model.emergencies[0] = .{
        .command = try allocator.dupe(u8, @tagName(decision.command)),
        .reason = try allocator.dupe(u8, @tagName(decision.reason)),
        .decision = try allocator.dupe(u8, decision.policy_decision.toString()),
        .event_id = try allocator.dupe(u8, decision.audit_event_reference),
    };
    return model;
}

fn evidenceFromSafetyEvaluation(
    allocator: std.mem.Allocator,
    selected_policy: *const schema.edge_policy_schema.EdgePolicyV1,
    meta: ScenarioMeta,
    evaluation: safety.SafetyEvaluation,
    status: safety_report.ScenarioResultStatus,
    provenance: safety_report.Provenance,
    summary: []const u8,
) !EvidenceModel {
    var findings = try allocator.alloc(safety_report.FindingRecord, if (evaluation.findings.len == 0) 1 else evaluation.findings.len);
    if (evaluation.findings.len == 0) {
        findings[0] = try makeFinding(allocator, "unsupported", "warning", "no safety finding emitted", "evidence must include findings for denials where possible", evaluation.decision.result.toString(), "safety_case.validation_failed", evaluation.explanation);
    } else {
        for (evaluation.findings, 0..) |finding, index| {
            findings[index] = try makeFinding(
                allocator,
                @tagName(finding.category),
                @tagName(finding.severity),
                finding.observed_value orelse finding.explanation,
                finding.limit_value orelse "configured policy control",
                finding.decision.toString(),
                finding.audit_event_reference orelse "safety.finding_created",
                finding.explanation,
            );
        }
    }

    const rule = if (evaluation.matched_rule) |matched| matched.id else "safety.envelope";
    var commands = try allocator.alloc(safety_report.CommandRecord, 1);
    commands[0] = try makeCommand(allocator, meta.command, evaluation.decision.result.toString(), evaluation.explanation, rule, findings[0].category, "vehicle.command_requested");

    var rows = try allocator.alloc(safety_report.TraceabilityRow, 1);
    rows[0] = try makeTrace(allocator, rule, meta.command, findings[0].category, evaluation.decision.result.toString(), findings[0].event_id, "Commands and Safety Findings");

    var refs = try allocator.alloc([]const u8, evaluation.audit_events.len);
    for (evaluation.audit_events, 0..) |event, index| refs[index] = try allocator.dupe(u8, event.event_type);

    return .{
        .allocator = allocator,
        .scenario_id = try allocator.dupe(u8, meta.id),
        .command_name = try allocator.dupe(u8, meta.command),
        .decision = try allocator.dupe(u8, evaluation.decision.result.toString()),
        .reason = try allocator.dupe(u8, evaluation.explanation),
        .rule = try allocator.dupe(u8, rule),
        .provenance = provenance,
        .vehicle_kind = try allocator.dupe(u8, @tagName(selected_policy.vehicle.kind)),
        .autopilot_kind = try allocator.dupe(u8, @tagName(selected_policy.vehicle.autopilot)),
        .adapter_kind = try allocator.dupe(u8, @tagName(selected_policy.vehicle.adapter)),
        .vehicle_type = try allocator.dupe(u8, "n/a"),
        .tested_version = try allocator.dupe(u8, "n/a"),
        .endpoint = try allocator.dupe(u8, "not configured"),
        .status = status,
        .commands = commands,
        .findings = findings,
        .approvals = &.{},
        .emergencies = &.{},
        .traceability_rows = rows,
        .audit_event_refs = refs,
        .summary = try allocator.dupe(u8, summary),
    };
}

fn genericEvidence(
    allocator: std.mem.Allocator,
    meta: ScenarioMeta,
    status: safety_report.ScenarioResultStatus,
    provenance: safety_report.Provenance,
    decision: []const u8,
    reason: []const u8,
    autopilot: []const u8,
    adapter: []const u8,
    tested_version: []const u8,
    endpoint: []const u8,
) !EvidenceModel {
    var findings = try allocator.alloc(safety_report.FindingRecord, 1);
    const category = if (std.mem.indexOf(u8, meta.command, "waypoint") != null or std.mem.indexOf(u8, meta.id, "geofence") != null) "geofence" else if (std.mem.indexOf(u8, meta.id, "battery") != null) "battery" else if (std.mem.indexOf(u8, meta.id, "mission") != null) "mission" else "unknown";
    findings[0] = try makeFinding(allocator, category, if (std.mem.eql(u8, decision, "deny")) "high" else "info", reason, "configured Edge policy", decision, "safety.finding_created", reason);
    var commands = try allocator.alloc(safety_report.CommandRecord, 1);
    commands[0] = try makeCommand(allocator, meta.command, decision, reason, "scenario.expected_decision", category, "vehicle.command_requested");
    var rows = try allocator.alloc(safety_report.TraceabilityRow, 1);
    rows[0] = try makeTrace(allocator, "scenario.expected_decision", meta.command, category, decision, "vehicle.command_requested", "Commands and Safety Findings");
    var refs = try allocator.alloc([]const u8, 3);
    refs[0] = try allocator.dupe(u8, "edge.scenario_start");
    refs[1] = try allocator.dupe(u8, "vehicle.command_requested");
    refs[2] = try allocator.dupe(u8, "edge.scenario_exit");
    return .{
        .allocator = allocator,
        .scenario_id = try allocator.dupe(u8, meta.id),
        .command_name = try allocator.dupe(u8, meta.command),
        .decision = try allocator.dupe(u8, decision),
        .reason = try allocator.dupe(u8, reason),
        .rule = try allocator.dupe(u8, "scenario.expected_decision"),
        .provenance = provenance,
        .vehicle_kind = try allocator.dupe(u8, "drone_multirotor"),
        .autopilot_kind = try allocator.dupe(u8, autopilot),
        .adapter_kind = try allocator.dupe(u8, adapter),
        .vehicle_type = try allocator.dupe(u8, if (std.mem.eql(u8, autopilot, "ardupilot")) "copter" else "n/a"),
        .tested_version = try allocator.dupe(u8, tested_version),
        .endpoint = try allocator.dupe(u8, endpoint),
        .status = status,
        .commands = commands,
        .findings = findings,
        .approvals = &.{},
        .emergencies = &.{},
        .traceability_rows = rows,
        .audit_event_refs = refs,
        .summary = try allocator.dupe(u8, reason),
    };
}

fn evaluateSafetyMeta(allocator: std.mem.Allocator, selected_policy: *const schema.edge_policy_schema.EdgePolicyV1, meta: ScenarioMeta) !safety.SafetyEvaluation {
    const state = stateForMeta(selected_policy, meta, 1_000_000);
    if (std.mem.eql(u8, meta.command, "mission_outside_geofence")) {
        const items = [_]domain.mission.Waypoint{
            .{ .sequence = 0, .position = .{ .latitude_deg = 37.0001, .longitude_deg = -122.0000, .altitude_m = 20, .altitude_reference = .amsl } },
            .{ .sequence = 1, .position = .{ .latitude_deg = 37.0100, .longitude_deg = -122.0000, .altitude_m = 20, .altitude_reference = .amsl } },
        };
        return mission_safety.evaluateMissionSafety(allocator, selected_policy, state, .{
            .mission_id = .{ .value = "scenario-mission-outside" },
            .waypoints = items[0..],
            .status = .draft,
        }, .{ .mode = .strict, .now_ms = 1_000_500 });
    }
    return safety.evaluateSafety(allocator, selected_policy, state, requestForMeta(meta), .{ .mode = .strict, .now_ms = 1_000_500 });
}

fn stateForMeta(selected_policy: *const schema.edge_policy_schema.EdgePolicyV1, meta: ScenarioMeta, timestamp_ms: i128) domain.state.VehicleState {
    const center = if (selected_policy.safety.geofence) |geofence| switch (geofence.shape) {
        .circle => |circle| circle.center,
        .allowed_polygon => |_| domain.coordinates.GeoPoint{ .latitude_deg = 37, .longitude_deg = -122, .altitude_m = 0, .altitude_reference = .amsl },
    } else domain.coordinates.GeoPoint{ .latitude_deg = 37, .longitude_deg = -122, .altitude_m = 0, .altitude_reference = .amsl };
    const battery_percent: f64 = if (std.mem.indexOf(u8, meta.command, "low_battery") != null) 20 else 80;
    return .{
        .vehicle_id = .{ .value = "edge-vehicle-1" },
        .vehicle_kind = selected_policy.vehicle.kind,
        .autopilot_kind = selected_policy.vehicle.autopilot,
        .mode = .guided,
        .arm_state = .armed,
        .position = .{ .latitude_deg = center.latitude_deg, .longitude_deg = center.longitude_deg, .altitude_m = 20, .altitude_reference = center.altitude_reference },
        .battery_state = .{ .percent_remaining = battery_percent, .voltage_v = 15.2, .current_a = 2.1, .source = .monotonic },
        .control_authority = .onboard_agent,
        .home_position = center,
        .timestamp = .{ .value = timestamp_ms, .source = .monotonic },
        .state_freshness = if (std.mem.indexOf(u8, meta.command, "stale") != null) .stale else .fresh,
        .provenance = if (selected_policy.vehicle.autopilot == .ardupilot) .fake_ardupilot_adapter else .fake_adapter,
    };
}

fn requestForMeta(meta: ScenarioMeta) domain.commands.CommandRequest {
    const action: domain.commands.CommandAction = if (std.mem.eql(u8, meta.command, "waypoint_outside_geofence")) .set_waypoint else if (std.mem.eql(u8, meta.command, "takeoff_low_battery")) .takeoff else std.meta.stringToEnum(domain.commands.CommandAction, meta.command) orelse .read_vehicle_state;
    const params: domain.commands.CommandParameters = if (std.mem.eql(u8, meta.command, "waypoint_outside_geofence"))
        .{ .waypoint = .{ .latitude_deg = 37.0100, .longitude_deg = -122.0000, .altitude_m = 20, .altitude_reference = .amsl } }
    else if (action == .takeoff)
        .{ .altitude = .{ .altitude_m = 20, .altitude_reference = .amsl } }
    else
        .none;
    return domain.commands.CommandRequest.init(.{
        .command_id = "safety-case-command",
        .vehicle_id = .{ .value = "edge-vehicle-1" },
        .action = action,
        .parameters = params,
        .actor = "aegis-edge-safety-case",
        .timestamp = .{ .value = 1_000_100, .source = .monotonic },
        .source = .fake_adapter,
        .mission_id = if (std.mem.eql(u8, meta.command, "mission_outside_geofence")) "scenario-mission-outside" else null,
    });
}

fn writeEvidenceFiles(
    allocator: std.mem.Allocator,
    evidence_dir: []const u8,
    options: GenerateOptions,
    meta: ScenarioMeta,
    evidence: EvidenceModel,
    policy_hash: [64]u8,
    final_hash: []const u8,
) !void {
    const policy_copy = try std.fs.path.join(allocator, &.{ evidence_dir, "policy.yaml" });
    defer allocator.free(policy_copy);
    const policy_hash_path = try std.fs.path.join(allocator, &.{ evidence_dir, "policy-hash.txt" });
    defer allocator.free(policy_hash_path);
    const scenario_copy = try std.fs.path.join(allocator, &.{ evidence_dir, "scenario.yaml" });
    defer allocator.free(scenario_copy);
    try artifacts.copyRedacted(allocator, options.policy_path, policy_copy);
    try artifacts.writeHashFile(allocator, policy_hash_path, &policy_hash);
    try artifacts.copyRedacted(allocator, options.scenario_path, scenario_copy);

    try writeScenarioResult(allocator, evidence_dir, meta, evidence);
    try writeCommands(allocator, evidence_dir, evidence.commands);
    try writeFindings(allocator, evidence_dir, evidence.findings);
    try writeApprovals(allocator, evidence_dir, evidence.approvals);
    try writeEnvironment(allocator, evidence_dir, evidence);
    try writeLimitations(allocator, evidence_dir);

    const trace_json = try std.fs.path.join(allocator, &.{ evidence_dir, "traceability.json" });
    defer allocator.free(trace_json);
    const trace_md = try std.fs.path.join(allocator, &.{ evidence_dir, "traceability.md" });
    defer allocator.free(trace_md);
    try traceability.writeJsonFile(trace_json, evidence.traceability_rows);
    try traceability.writeMarkdownFile(trace_md, evidence.traceability_rows);

    const final_hash_path = try std.fs.path.join(allocator, &.{ evidence_dir, "final-hash.txt" });
    defer allocator.free(final_hash_path);
    try artifacts.writeHashFile(allocator, final_hash_path, final_hash);
}

fn writeScenarioResult(allocator: std.mem.Allocator, evidence_dir: []const u8, meta: ScenarioMeta, evidence: EvidenceModel) !void {
    const path = try std.fs.path.join(allocator, &.{ evidence_dir, "scenario-result.json" });
    defer allocator.free(path);
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    var buffer: [4096]u8 = undefined;
    var writer = file.writer(&buffer);
    try writer.interface.writeAll("{\"schema_version\":1,\"scenario_id\":");
    try core.util.writeJsonString(&writer.interface, meta.id);
    try writer.interface.writeAll(",\"status\":");
    try core.util.writeJsonString(&writer.interface, evidence.status.toString());
    try writer.interface.writeAll(",\"decision\":");
    try core.util.writeJsonString(&writer.interface, evidence.decision);
    try writer.interface.writeAll(",\"provenance\":");
    try core.util.writeJsonString(&writer.interface, evidence.provenance.toString());
    try writer.interface.writeAll(",\"real_flight\":\"not_performed\"}\n");
    try writer.interface.flush();
    try file.sync();
}

fn writeCommands(allocator: std.mem.Allocator, evidence_dir: []const u8, commands: []const safety_report.CommandRecord) !void {
    const path = try std.fs.path.join(allocator, &.{ evidence_dir, "commands.json" });
    defer allocator.free(path);
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    var buffer: [4096]u8 = undefined;
    var writer = file.writer(&buffer);
    try writer.interface.writeAll("{\"commands\":[");
    for (commands, 0..) |command, index| {
        if (index > 0) try writer.interface.writeByte(',');
        try writer.interface.writeByte('{');
        try stringField(&writer.interface, "command", command.command, false);
        try stringField(&writer.interface, "decision", command.decision, true);
        try stringField(&writer.interface, "reason", command.reason, true);
        try stringField(&writer.interface, "rule", command.rule, true);
        try stringField(&writer.interface, "event_id", command.event_id, true);
        try writer.interface.writeByte('}');
    }
    try writer.interface.writeAll("]}\n");
    try writer.interface.flush();
    try file.sync();
}

fn writeFindings(allocator: std.mem.Allocator, evidence_dir: []const u8, findings: []const safety_report.FindingRecord) !void {
    const path = try std.fs.path.join(allocator, &.{ evidence_dir, "findings.json" });
    defer allocator.free(path);
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    var buffer: [4096]u8 = undefined;
    var writer = file.writer(&buffer);
    try writer.interface.writeAll("{\"findings\":[");
    for (findings, 0..) |finding, index| {
        if (index > 0) try writer.interface.writeByte(',');
        try writer.interface.writeByte('{');
        try stringField(&writer.interface, "category", finding.category, false);
        try stringField(&writer.interface, "severity", finding.severity, true);
        try stringField(&writer.interface, "event_id", finding.event_id, true);
        try stringField(&writer.interface, "explanation", finding.explanation, true);
        try writer.interface.writeByte('}');
    }
    try writer.interface.writeAll("]}\n");
    try writer.interface.flush();
    try file.sync();
}

fn writeApprovals(allocator: std.mem.Allocator, evidence_dir: []const u8, approvals: []const safety_report.ApprovalRecord) !void {
    const path = try std.fs.path.join(allocator, &.{ evidence_dir, "approvals.jsonl" });
    defer allocator.free(path);
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    var buffer: [2048]u8 = undefined;
    var writer = file.writer(&buffer);
    for (approvals) |approval| {
        try writer.interface.writeAll("{\"approval_id\":");
        try core.util.writeJsonString(&writer.interface, approval.approval_id);
        try writer.interface.writeAll(",\"command\":");
        try core.util.writeJsonString(&writer.interface, approval.command);
        try writer.interface.writeAll(",\"decision\":");
        try core.util.writeJsonString(&writer.interface, approval.decision);
        try writer.interface.writeAll("}\n");
    }
    try writer.interface.flush();
    try file.sync();
}

fn writeEnvironment(allocator: std.mem.Allocator, evidence_dir: []const u8, evidence: EvidenceModel) !void {
    const path = try std.fs.path.join(allocator, &.{ evidence_dir, "environment.json" });
    defer allocator.free(path);
    const text = try std.fmt.allocPrint(allocator, "{{\"provenance\":\"{s}\",\"test_environment\":\"{s}\",\"simulated_status\":\"{s}\",\"real_flight\":\"not_performed\"}}\n", .{ evidence.provenance.toString(), evidence.provenance.testEnvironment(), evidence.provenance.simulatedStatus() });
    defer allocator.free(text);
    try artifacts.writeFile(path, text);
}

fn writeLimitations(allocator: std.mem.Allocator, evidence_dir: []const u8) !void {
    const path = try std.fs.path.join(allocator, &.{ evidence_dir, "limitations.md" });
    defer allocator.free(path);
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    for (defaultLimitations()) |limitation| {
        try file.writeAll("- ");
        try file.writeAll(limitation);
        try file.writeAll("\n");
    }
    try file.sync();
}

fn writeReplayMarkdown(allocator: std.mem.Allocator, workspace_root: []const u8, session_id: []const u8, path: []const u8) !void {
    var replay = try edge_session.loadReplay(allocator, workspace_root, session_id, true);
    defer replay.deinit();
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    var buffer: [8192]u8 = undefined;
    var writer = file.writer(&buffer);
    try core.api.writeReplayHuman(&writer.interface, replay, true);
    try writer.interface.flush();
    try file.sync();
}

fn appendEvent(
    allocator: std.mem.Allocator,
    writer: *core.audit.writer.SessionWriter,
    sequence: *usize,
    event_refs: *std.ArrayList([]const u8),
    session: core.session.Session,
    timestamp: core.core.time.Timestamp,
    event_type: []const u8,
    target_kind: core.types.TargetKind,
    target_value: []const u8,
    result: core.decision.DecisionResult,
    reason: []const u8,
) ![]const u8 {
    sequence.* += 1;
    const event_id = try edge_event.eventIdFromSequence(sequence.*);
    const event = try core.api.createAuditEvent(.{
        .session_id = session.id,
        .event_id = event_id,
        .timestamp = timestamp,
        .event_type = try edge_event.toCoreEventType(event_type),
        .actor = .{ .kind = .aegis, .display = "aegis-edge" },
        .target = .{ .kind = target_kind, .value = target_value },
        .decision = core.api.makeDecision(.{
            .result = result,
            .reason = reason,
            .requires_user = result == .ask,
            .ci_may_proceed = result == .allow or result == .observe,
        }),
    });
    try core.api.appendAuditEvent(writer, event);
    const event_ref = try allocator.dupe(u8, event_id.slice());
    try event_refs.append(allocator, event_ref);
    return event_ref;
}

fn assignActualEventIds(allocator: std.mem.Allocator, evidence: *EvidenceModel, event_refs: []const []const u8) !void {
    const fallback = if (event_refs.len > 3) event_refs[3] else if (event_refs.len > 0) event_refs[0] else "edge_evt_000000";
    for (evidence.commands) |*command| {
        allocator.free(command.event_id);
        command.event_id = try allocator.dupe(u8, fallback);
    }
    for (evidence.findings) |*finding| {
        allocator.free(finding.event_id);
        finding.event_id = try allocator.dupe(u8, fallback);
    }
    for (evidence.traceability_rows) |*row| {
        allocator.free(row.event_id);
        row.event_id = try allocator.dupe(u8, fallback);
    }
    for (evidence.approvals) |*approval| {
        allocator.free(approval.event_id);
        approval.event_id = try allocator.dupe(u8, fallback);
    }
    for (evidence.emergencies) |*emergency_record| {
        allocator.free(emergency_record.event_id);
        emergency_record.event_id = try allocator.dupe(u8, fallback);
    }
}

fn classifyScenarioKind(path: []const u8, meta: ScenarioMeta) ScenarioKind {
    if (meta.reason != null) return .emergency;
    if (meta.request_path != null and meta.approval_seed != .none) return .operator_approval;
    if (std.mem.indexOf(u8, path, "/px4/") != null or std.mem.startsWith(u8, meta.environment, "px4") or std.mem.startsWith(u8, meta.environment, "fake_px4")) return .px4;
    if (std.mem.indexOf(u8, path, "/ardupilot/") != null or std.mem.startsWith(u8, meta.environment, "ardupilot") or std.mem.startsWith(u8, meta.environment, "fake_ardupilot")) return .ardupilot;
    return .safety;
}

fn loadScenarioMeta(allocator: std.mem.Allocator, path: []const u8) !ScenarioMeta {
    const text = try artifacts.readBounded(allocator, path);
    defer allocator.free(text);
    var id: ?[]const u8 = null;
    var command: []const u8 = "unknown";
    var environment: []const u8 = "fake_adapter";
    var expected_decision: ?core.decision.DecisionResult = null;
    var expected_command: ?[]const u8 = null;
    var request_path: ?[]const u8 = null;
    var state_path: ?[]const u8 = null;
    var reason: ?[]const u8 = null;
    var approval_seed: operator.ApprovalSeedKind = .none;
    var note: []const u8 = "";
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const no_comment = if (std.mem.indexOfScalar(u8, raw_line, '#')) |comment| raw_line[0..comment] else raw_line;
        const line = std.mem.trim(u8, no_comment, " \t\r");
        if (line.len == 0) continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const key = std.mem.trim(u8, line[0..colon], " \t");
        const value = cleanScalar(line[colon + 1 ..]);
        if (std.mem.eql(u8, key, "id") or std.mem.eql(u8, key, "name")) id = value else if (std.mem.eql(u8, key, "command")) command = value else if (std.mem.eql(u8, key, "environment")) environment = value else if (std.mem.eql(u8, key, "expected_decision")) expected_decision = std.meta.stringToEnum(core.decision.DecisionResult, value) orelse null else if (std.mem.eql(u8, key, "expected_command")) expected_command = value else if (std.mem.eql(u8, key, "request")) request_path = value else if (std.mem.eql(u8, key, "state")) state_path = value else if (std.mem.eql(u8, key, "reason")) reason = value else if (std.mem.eql(u8, key, "approval") or std.mem.eql(u8, key, "approval_seed")) approval_seed = operator.parseApprovalSeedKind(value) catch .none else if (std.mem.eql(u8, key, "note")) note = value;
    }
    return .{
        .allocator = allocator,
        .id = try allocator.dupe(u8, id orelse std.fs.path.stem(path)),
        .command = try allocator.dupe(u8, command),
        .environment = try allocator.dupe(u8, environment),
        .expected_decision = expected_decision,
        .expected_command = if (expected_command) |value| try allocator.dupe(u8, value) else null,
        .request_path = if (request_path) |value| try allocator.dupe(u8, value) else null,
        .state_path = if (state_path) |value| try allocator.dupe(u8, value) else null,
        .reason = if (reason) |value| try allocator.dupe(u8, value) else null,
        .approval_seed = approval_seed,
        .note = try allocator.dupe(u8, note),
    };
}

fn cleanScalar(raw: []const u8) []const u8 {
    var value = std.mem.trim(u8, raw, " \t\r");
    if (value.len >= 2) {
        const first = value[0];
        const last = value[value.len - 1];
        if ((first == '"' and last == '"') or (first == '\'' and last == '\'')) value = value[1 .. value.len - 1];
    }
    return value;
}

fn provenanceFromState(value: domain.state.StateProvenance) safety_report.Provenance {
    return switch (value) {
        .fake_adapter => .fake_adapter,
        .fake_ardupilot_adapter => .fake_ardupilot,
        .sitl_px4 => .px4_sitl,
        .sitl_ardupilot => .ardupilot_sitl,
        .bench => .bench,
        else => .unknown,
    };
}

fn isoAlloc(allocator: std.mem.Allocator, timestamp: core.core.time.Timestamp) ![]u8 {
    var buf: [32]u8 = undefined;
    const text = try timestamp.formatIso(&buf);
    return allocator.dupe(u8, text);
}

fn defaultLimitations() []const []const u8 {
    return &.{
        safety_report.non_certification_disclaimer,
        "Aegis Edge is not a flight controller, autopilot replacement, detect-and-avoid system, or regulatory approval.",
        "Fake adapter evidence is not PX4 SITL, ArduPilot SITL, bench, hardware, or real-flight evidence.",
        "SITL evidence, when present, is local simulation evidence and is not real-flight validation.",
        "Missing SITL is classified as skipped or unsupported, never passed.",
        "Unsupported geofence shapes, coordinate conversions, MAVLink messages, and hardware paths are not counted as passes.",
        "No real hardware was connected and no real-flight deployment procedure is provided in Phase 33.",
    };
}

fn defaultArtifactList() []const []const u8 {
    return &.{
        "events.jsonl",
        "summary.json",
        "summary.md",
        "safety-report.json",
        "safety-report.md",
        "evidence/policy.yaml",
        "evidence/scenario.yaml",
        "evidence/replay.md",
        "evidence/findings.json",
        "evidence/commands.json",
        "evidence/traceability.json",
    };
}

fn stringField(writer: anytype, name: []const u8, value: []const u8, comma: bool) !void {
    if (comma) try writer.writeByte(',');
    try core.util.writeJsonString(writer, name);
    try writer.writeByte(':');
    var redacted_buf: [1024]u8 = undefined;
    try core.util.writeJsonString(writer, core.api.redactStringBounded(value, &redacted_buf));
}

fn makeCommand(allocator: std.mem.Allocator, command: []const u8, decision: []const u8, reason: []const u8, rule: []const u8, finding: []const u8, event_id: []const u8) !safety_report.CommandRecord {
    return .{ .command = try allocator.dupe(u8, command), .decision = try allocator.dupe(u8, decision), .reason = try allocator.dupe(u8, reason), .rule = try allocator.dupe(u8, rule), .finding = try allocator.dupe(u8, finding), .event_id = try allocator.dupe(u8, event_id) };
}

fn makeFinding(allocator: std.mem.Allocator, category: []const u8, severity: []const u8, observed: []const u8, limit: []const u8, decision: []const u8, event_id: []const u8, explanation: []const u8) !safety_report.FindingRecord {
    return .{ .category = try allocator.dupe(u8, category), .severity = try allocator.dupe(u8, severity), .observed = try allocator.dupe(u8, observed), .limit = try allocator.dupe(u8, limit), .decision = try allocator.dupe(u8, decision), .event_id = try allocator.dupe(u8, event_id), .explanation = try allocator.dupe(u8, explanation) };
}

fn makeTrace(allocator: std.mem.Allocator, rule: []const u8, command: []const u8, finding: []const u8, decision: []const u8, event_id: []const u8, section: []const u8) !safety_report.TraceabilityRow {
    return .{ .policy_rule = try allocator.dupe(u8, rule), .command = try allocator.dupe(u8, command), .finding = try allocator.dupe(u8, finding), .decision = try allocator.dupe(u8, decision), .event_id = try allocator.dupe(u8, event_id), .report_section = try allocator.dupe(u8, section) };
}

fn freeCommandRecord(allocator: std.mem.Allocator, value: safety_report.CommandRecord) void {
    allocator.free(value.command);
    allocator.free(value.decision);
    allocator.free(value.reason);
    allocator.free(value.rule);
    allocator.free(value.finding);
    allocator.free(value.event_id);
}

fn freeFindingRecord(allocator: std.mem.Allocator, value: safety_report.FindingRecord) void {
    allocator.free(value.category);
    allocator.free(value.severity);
    allocator.free(value.observed);
    allocator.free(value.limit);
    allocator.free(value.decision);
    allocator.free(value.event_id);
    allocator.free(value.explanation);
}

fn freeApprovalRecord(allocator: std.mem.Allocator, value: safety_report.ApprovalRecord) void {
    allocator.free(value.approval_id);
    allocator.free(value.command);
    allocator.free(value.decision);
    allocator.free(value.event_id);
}

fn freeEmergencyRecord(allocator: std.mem.Allocator, value: safety_report.EmergencyRecord) void {
    allocator.free(value.command);
    allocator.free(value.reason);
    allocator.free(value.decision);
    allocator.free(value.event_id);
}

fn freeTraceabilityRow(allocator: std.mem.Allocator, value: safety_report.TraceabilityRow) void {
    allocator.free(value.policy_rule);
    allocator.free(value.command);
    allocator.free(value.finding);
    allocator.free(value.decision);
    allocator.free(value.event_id);
    allocator.free(value.report_section);
}

test "scenario result classification is fail closed" {
    try std.testing.expectEqual(safety_report.ScenarioResultStatus.passed, classifyScenarioResult(.deny, .deny, false, false, true));
    try std.testing.expectEqual(safety_report.ScenarioResultStatus.failed, classifyScenarioResult(.allow, .deny, false, false, true));
    try std.testing.expectEqual(safety_report.ScenarioResultStatus.skipped, classifyScenarioResult(null, .allow, true, false, true));
    try std.testing.expectEqual(safety_report.ScenarioResultStatus.unsupported, classifyScenarioResult(null, .allow, false, true, true));
    try std.testing.expectEqual(safety_report.ScenarioResultStatus.inconclusive, classifyScenarioResult(.deny, null, false, false, false));
}
