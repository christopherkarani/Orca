const findings_mod = @import("health_findings.zig");

pub fn policyFailureFinding(reason: []const u8, now_ms: i128, provenance: findings_mod.Provenance) findings_mod.HealthFinding {
    return findings_mod.HealthFinding.init(.{
        .finding_id = "health-policy-engine",
        .domain = .policy_engine,
        .status = .critical,
        .severity = .critical,
        .reason = reason,
        .observed_value = "policy engine error",
        .threshold = "valid loaded policy required",
        .timestamp_ms = now_ms,
        .provenance = provenance,
        .matched_rule = "watchdog.policy",
        .recommended_behavior = .fail_closed,
        .audit_event_reference = "health.watchdog.finding",
    });
}
