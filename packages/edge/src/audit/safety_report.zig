const std = @import("std");
const core = @import("aegis_core");
const schema = @import("../schema/mod.zig");
const artifacts = @import("edge_artifacts.zig");

pub const non_certification_disclaimer = schema.safety_report_schema.non_certification_disclaimer;

pub const ScenarioResultStatus = enum {
    passed,
    failed,
    skipped,
    unsupported,
    inconclusive,

    pub fn toString(self: ScenarioResultStatus) []const u8 {
        return @tagName(self);
    }
};

pub const Provenance = enum {
    fake_adapter,
    fake_px4,
    fake_ardupilot,
    px4_sitl,
    ardupilot_sitl,
    bench,
    unknown,

    pub fn toString(self: Provenance) []const u8 {
        return @tagName(self);
    }

    pub fn testEnvironment(self: Provenance) []const u8 {
        return switch (self) {
            .px4_sitl => "PX4 SITL",
            .ardupilot_sitl => "ArduPilot SITL",
            .bench => "bench",
            .fake_adapter, .fake_px4, .fake_ardupilot => "fake adapter",
            .unknown => "other",
        };
    }

    pub fn simulatedStatus(self: Provenance) []const u8 {
        return switch (self) {
            .fake_adapter, .fake_px4, .fake_ardupilot => "fake/simulated",
            .px4_sitl, .ardupilot_sitl => "SITL simulation",
            .bench => "bench preparation",
            .unknown => "unknown",
        };
    }
};

pub const CommandRecord = struct {
    command: []const u8,
    decision: []const u8,
    reason: []const u8,
    rule: []const u8,
    finding: []const u8,
    event_id: []const u8,
};

pub const FindingRecord = struct {
    category: []const u8,
    severity: []const u8,
    observed: []const u8,
    limit: []const u8,
    decision: []const u8,
    event_id: []const u8,
    explanation: []const u8,
};

pub const ApprovalRecord = struct {
    approval_id: []const u8,
    command: []const u8,
    decision: []const u8,
    event_id: []const u8,
};

pub const EmergencyRecord = struct {
    command: []const u8,
    reason: []const u8,
    decision: []const u8,
    event_id: []const u8,
};

pub const TraceabilityRow = struct {
    policy_rule: []const u8,
    command: []const u8,
    finding: []const u8,
    decision: []const u8,
    event_id: []const u8,
    report_section: []const u8,
};

pub const Report = struct {
    report_id: []const u8,
    report_version: u32 = 1,
    generated_at: []const u8,
    generated_by: []const u8 = "Aegis Edge",
    scenario_id: []const u8,
    scenario_name: []const u8,
    scenario_source: []const u8,
    session_id: []const u8,
    policy_file: []const u8,
    policy_hash: []const u8,
    report_hash: []const u8,
    provenance: Provenance,
    vehicle_id: []const u8,
    vehicle_kind: []const u8,
    autopilot_kind: []const u8,
    adapter_kind: []const u8,
    vehicle_type: []const u8,
    tested_autopilot_version: []const u8,
    endpoint_config: []const u8,
    started_at: []const u8,
    ended_at: []const u8,
    result_status: ScenarioResultStatus,
    conclusion: []const u8,
    replay_verified: bool,
    final_hash: []const u8,
    commands: []const CommandRecord,
    findings: []const FindingRecord,
    approvals: []const ApprovalRecord = &.{},
    emergencies: []const EmergencyRecord = &.{},
    data_network_summary: []const u8 = "Phase 35 data/network guard classifies payloads/endpoints, evaluates local egress policy, redacts sensitive fields, and records simulation/SITL/customer-evaluation evidence without external network calls.",
    data_classes_observed: []const []const u8 = &.{ "vehicle_state", "mission_plan", "geolocation", "safety_finding", "audit_metadata" },
    endpoints_observed: []const []const u8 = &.{ "fake_adapter", "ground_control_station", "customer_endpoint" },
    data_redactions_applied: []const []const u8 = &.{ "query secrets redacted", "exact geolocation coarsened when configured", "mission plans minimized when policy requires", "raw image/video not persisted by default" },
    exfiltration_findings: []const []const u8 = &.{ "unknown endpoints are not safe", "webhook/paste/tunnel/direct IP destinations are suspicious", "mission/geolocation/video/image egress to unknown endpoints is denied" },
    traceability: []const TraceabilityRow,
    audit_event_references: []const []const u8,
    artifacts_generated: []const []const u8,
    limitations: []const []const u8,
};

pub fn computeReportHash(report_id: []const u8, session_id: []const u8, scenario_id: []const u8, policy_hash: []const u8, status: ScenarioResultStatus) [64]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(report_id);
    hasher.update(session_id);
    hasher.update(scenario_id);
    hasher.update(policy_hash);
    hasher.update(status.toString());
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return std.fmt.bytesToHex(digest, .lower);
}

pub fn writeJson(writer: anytype, report: Report) !void {
    try writer.writeByte('{');
    try stringField(writer, "report_id", report.report_id, false);
    try writer.print(",\"report_version\":{d}", .{report.report_version});
    try stringField(writer, "generated_timestamp", report.generated_at, true);
    try stringField(writer, "generated_by", report.generated_by, true);
    try stringField(writer, "scenario_id", report.scenario_id, true);
    try stringField(writer, "scenario_name", report.scenario_name, true);
    try stringField(writer, "scenario_source", report.scenario_source, true);
    try stringField(writer, "session_id", report.session_id, true);
    try stringField(writer, "policy_hash", report.policy_hash, true);
    try stringField(writer, "report_hash", report.report_hash, true);
    try stringField(writer, "environment_provenance", report.provenance.toString(), true);
    try stringField(writer, "test_environment", report.provenance.testEnvironment(), true);
    try stringField(writer, "non_certification_disclaimer", non_certification_disclaimer, true);
    try writer.writeAll(",\"vehicle_profile\":{");
    try stringField(writer, "vehicle_id", report.vehicle_id, false);
    try stringField(writer, "vehicle_kind", report.vehicle_kind, true);
    try stringField(writer, "autopilot_kind", report.autopilot_kind, true);
    try stringField(writer, "adapter_kind", report.adapter_kind, true);
    try stringField(writer, "vehicle_type", report.vehicle_type, true);
    try stringField(writer, "simulated_status", report.provenance.simulatedStatus(), true);
    try writer.writeByte('}');
    try writer.writeAll(",\"adapter_profile\":{");
    try stringField(writer, "adapter_kind", report.adapter_kind, false);
    try stringField(writer, "environment_provenance", report.provenance.toString(), true);
    try stringField(writer, "endpoint_config", report.endpoint_config, true);
    try stringField(writer, "simulated_status", report.provenance.simulatedStatus(), true);
    try writer.writeByte('}');
    try writer.writeAll(",\"policy_profile\":{");
    try stringField(writer, "policy_file", report.policy_file, false);
    try stringField(writer, "policy_hash", report.policy_hash, true);
    try stringField(writer, "safety_envelope_summary", "geofence altitude velocity battery freshness mode authority and mission controls when configured", true);
    try stringField(writer, "command_policy_summary", "allowed denied observed and approval-gated commands are listed in evidence", true);
    try stringField(writer, "emergency_policy_summary", "policy-controlled LAND/RTH/HOLD fallback evidence only", true);
    try stringField(writer, "approval_policy_summary", "bounded local operator approvals when applicable", true);
    try stringField(writer, "network_telemetry_policy_summary", report.data_network_summary, true);
    try writer.writeByte('}');
    try writer.writeAll(",\"scenario_profile\":{");
    try stringField(writer, "scenario_name", report.scenario_name, false);
    try stringField(writer, "scenario_source", report.scenario_source, true);
    try stringField(writer, "scenario_environment", report.provenance.toString(), true);
    try stringField(writer, "tested_autopilot_version", report.tested_autopilot_version, true);
    try stringField(writer, "endpoint_config", report.endpoint_config, true);
    try stringField(writer, "start_timestamp", report.started_at, true);
    try stringField(writer, "end_timestamp", report.ended_at, true);
    try stringField(writer, "result_status", report.result_status.toString(), true);
    try writer.writeByte('}');
    try writer.writeAll(",\"evidence\":{");
    try commandsJson(writer, "commands", report.commands, false);
    try findingsJson(writer, "safety_findings", report.findings, true);
    try approvalsJson(writer, "approvals", report.approvals, true);
    try emergenciesJson(writer, "emergency_decisions", report.emergencies, true);
    try stringArrayField(writer, "data_classes_observed", report.data_classes_observed, true);
    try stringArrayField(writer, "endpoints_observed", report.endpoints_observed, true);
    try stringArrayField(writer, "redactions_applied", report.data_redactions_applied, true);
    try stringArrayField(writer, "exfiltration_findings", report.exfiltration_findings, true);
    try stringArrayField(writer, "audit_event_references", report.audit_event_references, true);
    try writer.print(",\"replay_hash_verified\":{}", .{report.replay_verified});
    try stringArrayField(writer, "artifacts_generated", report.artifacts_generated, true);
    try writer.writeByte('}');
    try traceabilityJson(writer, "traceability", report.traceability, true);
    try stringArrayField(writer, "limitations", report.limitations, true);
    try writer.writeAll(",\"conclusion\":{");
    try stringField(writer, "scenario_result", report.result_status.toString(), false);
    try stringField(writer, "policy_controls_demonstrated", report.conclusion, true);
    try stringField(writer, "customer_summary", report.conclusion, true);
    try stringField(writer, "next_recommended_validation_step", "Use the next validation phase for broader fault-injection, bench, or hardware evidence; this report does not approve real flight.", true);
    try writer.writeByte('}');
    try writer.writeAll("}\n");
}

pub fn writeMarkdown(writer: anytype, report: Report) !void {
    try writer.print(
        \\# Aegis Edge Safety Case: {s}
        \\
        \\{s}
        \\
        \\## Summary
        \\
        \\| Field | Value |
        \\|---|---|
        \\| Report ID | `{s}` |
        \\| Session ID | `{s}` |
        \\| Scenario | `{s}` |
        \\| Result | `{s}` |
        \\| Provenance | `{s}` |
        \\| Policy hash | `{s}` |
        \\| Report hash | `{s}` |
        \\| Real flight | Not performed |
        \\| Certification | Not claimed |
        \\
    , .{
        report.scenario_id,
        non_certification_disclaimer,
        report.report_id,
        report.session_id,
        report.scenario_source,
        report.result_status.toString(),
        report.provenance.toString(),
        report.policy_hash,
        report.report_hash,
    });

    try writer.writeAll("## Commands\n\n| Command | Decision | Reason | Rule | Finding |\n|---|---|---|---|---|\n");
    for (report.commands) |command| {
        try tableRow5(writer, command.command, command.decision, command.reason, command.rule, command.finding);
    }

    try writer.writeAll("\n## Safety Findings\n\n| Category | Severity | Observed | Limit | Decision |\n|---|---|---|---|---|\n");
    for (report.findings) |finding| {
        try tableRow5(writer, finding.category, finding.severity, finding.observed, finding.limit, finding.decision);
    }

    try writer.writeAll("\n## Data/Network Guard\n\n| Evidence | Summary |\n|---|---|\n");
    try tableRow2(writer, "Policy summary", report.data_network_summary);
    try tableRowArray(writer, "Data classes observed", report.data_classes_observed);
    try tableRowArray(writer, "Endpoints observed", report.endpoints_observed);
    try tableRowArray(writer, "Redactions applied", report.data_redactions_applied);
    try tableRowArray(writer, "Exfiltration findings", report.exfiltration_findings);

    try writer.writeAll("\n## Evidence\n\n| Evidence | Status |\n|---|---|\n");
    try tableRow2(writer, "Audit hash chain", if (report.replay_verified) "Verified" else "Not verified");
    try tableRow2(writer, "Policy hash", report.policy_hash);
    try tableRow2(writer, "Scenario environment", report.provenance.toString());
    try tableRow2(writer, "Real flight", "Not performed");
    try tableRow2(writer, "Final event hash", report.final_hash);

    try writer.writeAll("\n## Traceability\n\n| Policy Rule | Command | Finding | Decision | Event ID |\n|---|---|---|---|---|\n");
    for (report.traceability) |row| {
        try tableRow5(writer, row.policy_rule, row.command, row.finding, row.decision, row.event_id);
    }

    try writer.writeAll("\n## Limitations\n\n");
    for (report.limitations) |limitation| try writer.print("- {s}\n", .{limitation});
    try writer.print("\n## Conclusion\n\n{s}\n", .{report.conclusion});
}

pub fn writeJsonFile(path: []const u8, report: Report) !void {
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    var buffer: [8192]u8 = undefined;
    var writer = file.writer(&buffer);
    try writeJson(&writer.interface, report);
    try writer.interface.flush();
    try file.sync();
}

pub fn writeMarkdownFile(path: []const u8, report: Report) !void {
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    var buffer: [8192]u8 = undefined;
    var writer = file.writer(&buffer);
    try writeMarkdown(&writer.interface, report);
    try writer.interface.flush();
    try file.sync();
}

fn stringField(writer: anytype, name: []const u8, value: []const u8, comma: bool) !void {
    if (comma) try writer.writeByte(',');
    try core.util.writeJsonString(writer, name);
    try writer.writeByte(':');
    var redacted_buf: [1024]u8 = undefined;
    try core.util.writeJsonString(writer, core.api.redactStringBounded(value, &redacted_buf));
}

fn stringArrayField(writer: anytype, name: []const u8, values: []const []const u8, comma: bool) !void {
    if (comma) try writer.writeByte(',');
    try core.util.writeJsonString(writer, name);
    try writer.writeAll(":[");
    for (values, 0..) |value, index| {
        if (index > 0) try writer.writeByte(',');
        var redacted_buf: [1024]u8 = undefined;
        try core.util.writeJsonString(writer, core.api.redactStringBounded(value, &redacted_buf));
    }
    try writer.writeByte(']');
}

fn commandsJson(writer: anytype, name: []const u8, commands: []const CommandRecord, comma: bool) !void {
    if (comma) try writer.writeByte(',');
    try core.util.writeJsonString(writer, name);
    try writer.writeAll(":[");
    for (commands, 0..) |command, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try stringField(writer, "command", command.command, false);
        try stringField(writer, "decision", command.decision, true);
        try stringField(writer, "reason", command.reason, true);
        try stringField(writer, "rule", command.rule, true);
        try stringField(writer, "finding", command.finding, true);
        try stringField(writer, "event_id", command.event_id, true);
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
}

fn findingsJson(writer: anytype, name: []const u8, findings: []const FindingRecord, comma: bool) !void {
    if (comma) try writer.writeByte(',');
    try core.util.writeJsonString(writer, name);
    try writer.writeAll(":[");
    for (findings, 0..) |finding, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try stringField(writer, "category", finding.category, false);
        try stringField(writer, "severity", finding.severity, true);
        try stringField(writer, "observed", finding.observed, true);
        try stringField(writer, "limit", finding.limit, true);
        try stringField(writer, "decision", finding.decision, true);
        try stringField(writer, "event_id", finding.event_id, true);
        try stringField(writer, "explanation", finding.explanation, true);
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
}

fn approvalsJson(writer: anytype, name: []const u8, approvals: []const ApprovalRecord, comma: bool) !void {
    if (comma) try writer.writeByte(',');
    try core.util.writeJsonString(writer, name);
    try writer.writeAll(":[");
    for (approvals, 0..) |approval, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try stringField(writer, "approval_id", approval.approval_id, false);
        try stringField(writer, "command", approval.command, true);
        try stringField(writer, "decision", approval.decision, true);
        try stringField(writer, "event_id", approval.event_id, true);
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
}

fn emergenciesJson(writer: anytype, name: []const u8, emergencies: []const EmergencyRecord, comma: bool) !void {
    if (comma) try writer.writeByte(',');
    try core.util.writeJsonString(writer, name);
    try writer.writeAll(":[");
    for (emergencies, 0..) |emergency, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try stringField(writer, "command", emergency.command, false);
        try stringField(writer, "reason", emergency.reason, true);
        try stringField(writer, "decision", emergency.decision, true);
        try stringField(writer, "event_id", emergency.event_id, true);
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
}

fn traceabilityJson(writer: anytype, name: []const u8, rows: []const TraceabilityRow, comma: bool) !void {
    if (comma) try writer.writeByte(',');
    try core.util.writeJsonString(writer, name);
    try writer.writeAll(":[");
    for (rows, 0..) |row, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try stringField(writer, "policy_rule", row.policy_rule, false);
        try stringField(writer, "command", row.command, true);
        try stringField(writer, "finding", row.finding, true);
        try stringField(writer, "decision", row.decision, true);
        try stringField(writer, "event_id", row.event_id, true);
        try stringField(writer, "report_section", row.report_section, true);
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
}

fn tableRow2(writer: anytype, a: []const u8, b: []const u8) !void {
    try writer.print("| {s} | {s} |\n", .{ a, b });
}

fn tableRowArray(writer: anytype, label: []const u8, values: []const []const u8) !void {
    try writer.print("| {s} | ", .{label});
    if (values.len == 0) {
        try writer.writeAll("none");
    } else {
        for (values, 0..) |value, index| {
            if (index > 0) try writer.writeAll(", ");
            var redacted_buf: [512]u8 = undefined;
            try writer.writeAll(core.api.redactStringBounded(value, &redacted_buf));
        }
    }
    try writer.writeAll(" |\n");
}

fn tableRow5(writer: anytype, a: []const u8, b: []const u8, c: []const u8, d: []const u8, e: []const u8) !void {
    try writer.print("| {s} | {s} | {s} | {s} | {s} |\n", .{ a, b, c, d, e });
}

test "scenario result status names are stable" {
    try std.testing.expectEqualStrings("passed", ScenarioResultStatus.passed.toString());
    try std.testing.expectEqualStrings("PX4 SITL", Provenance.px4_sitl.testEnvironment());
    const hash = artifacts.sha256Hex("report");
    try std.testing.expectEqual(@as(usize, 64), hash.len);
}
