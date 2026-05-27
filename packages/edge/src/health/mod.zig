const std = @import("std");

pub const health_status = @import("health_status.zig");
pub const watchdog = @import("watchdog.zig");
pub const degraded_mode = @import("degraded_mode.zig");
pub const health_findings = @import("health_findings.zig");
pub const health_report = @import("health_report.zig");
pub const heartbeat = @import("heartbeat.zig");
pub const telemetry_freshness = @import("telemetry_freshness.zig");
pub const audit_health = @import("audit_health.zig");
pub const resource_health = @import("resource_health.zig");
pub const adapter_health = @import("adapter_health.zig");
pub const policy_health = @import("policy_health.zig");
pub const health_audit = @import("health_audit.zig");
pub const runtime_state = @import("runtime_state.zig");
pub const queue_health = @import("queue_health.zig");
pub const timeout = @import("timeout.zig");
pub const fallback = @import("fallback.zig");

const domain = @import("../domain/mod.zig");
const schema = @import("../schema/mod.zig");
const core = @import("orca_core");

pub const HealthStatus = health_status.HealthStatus;
pub const HealthDomain = health_status.HealthDomain;
pub const RuntimeStatus = health_status.RuntimeStatus;
pub const Severity = health_status.Severity;
pub const HealthFinding = health_findings.HealthFinding;
pub const Provenance = health_findings.Provenance;
pub const WatchdogPolicy = watchdog.WatchdogPolicy;
pub const DegradedBehavior = degraded_mode.DegradedBehavior;
pub const EmergencyAllowance = degraded_mode.EmergencyAllowance;
pub const HealthReport = health_report.HealthReport;
pub const Heartbeat = heartbeat.Heartbeat;
pub const HeartbeatSource = heartbeat.HeartbeatSource;
pub const TimestampSource = heartbeat.TimestampSource;
pub const HeartbeatStatus = heartbeat.HeartbeatStatus;
pub const Decision = degraded_mode.Decision;
pub const CommandLifecycle = queue_health.CommandLifecycle;
pub const CommandQueueSample = queue_health.CommandQueueSample;
pub const CommandTimeoutStatus = timeout.CommandTimeoutStatus;
pub const FallbackRecommendation = fallback.Recommendation;

pub const evaluateHeartbeat = heartbeat.evaluateHeartbeat;
pub const evaluateMissingHeartbeat = heartbeat.evaluateMissingHeartbeat;
pub const heartbeatFromMavlinkFrame = heartbeat.heartbeatFromMavlinkFrame;
pub const evaluateTelemetryFreshness = telemetry_freshness.evaluateTelemetryFreshness;
pub const evaluateCommandQueue = queue_health.evaluateCommandQueue;
pub const evaluateCommandTimeout = timeout.evaluateCommandTimeout;

pub fn decideForCommand(
    policy: *const schema.edge_policy_schema.EdgePolicyV1,
    report: HealthReport,
    request: domain.commands.CommandRequest,
    state: domain.state.VehicleState,
    context: anytype,
) Decision {
    _ = context;
    if (!policy.watchdog.enabled) return .{ .decision = .observe, .behavior = .observe_only, .reason = "watchdog disabled" };
    if (degraded_mode.isNeverSafe(request.action)) {
        return .{ .decision = .deny, .behavior = .fail_closed, .reason = "critical command remains denied under watchdog" };
    }
    if (policy.watchdog.fail_closed_on_state_expiry and state.state_freshness == .expired) {
        return .{ .decision = .deny, .behavior = .fail_closed, .reason = "watchdog fail-closed on expired vehicle state" };
    }
    if (report.recommended_behavior == .fail_closed or report.recommended_behavior == .no_safe_action or report.recommended_behavior == .unknown) {
        return .{ .decision = .deny, .behavior = .fail_closed, .reason = "watchdog fail-closed" };
    }
    if (!report.safe_to_evaluate_commands and
        report.recommended_behavior != .allow_policy_emergency_only and
        report.recommended_behavior != .allow_emergency_land_only)
    {
        return .{ .decision = .deny, .behavior = report.recommended_behavior, .reason = "runtime health is unsafe for command evaluation" };
    }
    if (degraded_mode.emergencyDecision(policy, request.action, state)) |emergency| {
        return emergency;
    }
    const behavior = report.recommended_behavior;
    if (report.overall_status == .healthy) {
        return .{ .decision = .observe, .behavior = .observe_only, .reason = "runtime health healthy" };
    }
    if (report.overall_status == .unknown or report.overall_status == .unavailable) {
        if (degraded_mode.isHighRisk(request.action)) return .{ .decision = .deny, .behavior = .fail_closed, .reason = "runtime health unknown or unavailable" };
    }
    switch (behavior) {
        .observe_only => return .{ .decision = .observe, .behavior = .observe_only, .reason = "degraded health observed only" },
        .deny_high_risk => if (degraded_mode.isHighRisk(request.action)) return .{ .decision = .deny, .behavior = .deny_high_risk, .reason = "degraded health denies high-risk command" },
        .deny_movement => if (degraded_mode.isMovement(request.action) or degraded_mode.isHighRisk(request.action)) return .{ .decision = .deny, .behavior = .deny_movement, .reason = "degraded telemetry denies movement/high-risk command" },
        .deny_external_egress => if (request.action == .telemetry_stream_external) return .{ .decision = .deny, .behavior = .deny_external_egress, .reason = "degraded data guard denies external egress" },
        .fail_closed, .no_safe_action, .unknown => return .{ .decision = .deny, .behavior = .fail_closed, .reason = "watchdog fail-closed" },
        .allow_emergency_land_only => return .{ .decision = .deny, .behavior = .allow_emergency_land_only, .reason = "only emergency LAND can be considered under degraded health" },
        .allow_policy_emergency_only => return .{ .decision = .deny, .behavior = .allow_policy_emergency_only, .reason = "only policy emergency actions can be considered under degraded health" },
    }
    return .{ .decision = .observe, .behavior = behavior, .reason = "health does not alter this command" };
}

pub fn writeDoctor(writer: anytype) !void {
    try writer.writeAll("Edge runtime health/watchdog: active for fake-adapter, PX4 SITL, ArduPilot SITL, and bench-preparation evidence only.\n");
    try writer.writeAll("No real hardware endpoint, external network, hosted telemetry, or real-flight operation is opened.\n");
    try writer.writeAll("Health status domains: runtime, agent, adapter, mavlink, px4_sitl, ardupilot_sitl, telemetry, audit_writer, policy_engine, safety_engine, data_guard, resource_usage.\n");
    try writer.writeAll("Limitations: watchdog checks do not replace autopilot failsafes, are not detect-and-avoid, and are not regulatory certification.\n");
}

pub fn writeJsonStatus(writer: anytype) !void {
    try writer.writeAll("{\"runtime_health\":\"healthy\",\"provenance\":\"fake_adapter\",\"scope\":\"simulation/SITL/bench-preparation only\",\"real_flight_ready\":false,\"certification_claimed\":false}\n");
}

test {
    _ = health_status;
    _ = watchdog;
    _ = degraded_mode;
    _ = health_findings;
    _ = health_report;
    _ = heartbeat;
    _ = telemetry_freshness;
    _ = audit_health;
    _ = resource_health;
    _ = adapter_health;
    _ = policy_health;
    _ = health_audit;
    _ = runtime_state;
    _ = queue_health;
    _ = timeout;
    _ = fallback;
}
