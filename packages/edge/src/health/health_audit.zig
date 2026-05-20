const std = @import("std");

const core = @import("orca_core");
const findings_mod = @import("health_findings.zig");

pub fn eventDecision(finding: findings_mod.HealthFinding) core.decision.Decision {
    const result: core.decision.DecisionResult = switch (finding.recommended_behavior) {
        .observe_only => .observe,
        else => .deny,
    };
    return core.api.makeDecision(.{
        .result = result,
        .reason = finding.reason,
        .risk_score = if (finding.severity == .critical) 95 else if (finding.severity == .high) 75 else null,
        .requires_user = false,
        .ci_may_proceed = result == .allow or result == .observe,
    });
}

pub fn writeJsonFinding(writer: anytype, finding: findings_mod.HealthFinding) !void {
    try writer.writeByte('{');
    try stringField(writer, "finding_id", finding.finding_id, false);
    try stringField(writer, "domain", finding.domain.toString(), true);
    try stringField(writer, "status", finding.status.toString(), true);
    try stringField(writer, "severity", finding.severity.toString(), true);
    try stringField(writer, "reason", finding.reason, true);
    try stringField(writer, "observed_value", finding.observed_value, true);
    try stringField(writer, "threshold", finding.threshold, true);
    try stringField(writer, "provenance", finding.provenance.toString(), true);
    if (finding.scenario_id) |value| try stringField(writer, "scenario_id", value, true);
    if (finding.vehicle_id) |value| try stringField(writer, "vehicle_id", value, true);
    if (finding.matched_rule) |value| try stringField(writer, "matched_rule", value, true);
    try stringField(writer, "recommended_degraded_behavior", finding.recommended_behavior.toString(), true);
    if (finding.audit_event_reference) |value| try stringField(writer, "audit_event_reference", value, true);
    try writer.writeByte('}');
}

fn stringField(writer: anytype, name: []const u8, value: []const u8, comma: bool) !void {
    if (comma) try writer.writeByte(',');
    try writer.writeByte('"');
    try writer.writeAll(name);
    try writer.writeAll("\":");
    try core.util.writeJsonString(writer, value);
}
