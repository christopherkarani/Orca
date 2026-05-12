const std = @import("std");

const degraded = @import("degraded_mode.zig");
const status_mod = @import("health_status.zig");
const domain_mod = @import("../domain/mod.zig");

pub const DegradedBehavior = degraded.DegradedBehavior;
pub const EmergencyAllowance = degraded.EmergencyAllowance;
pub const HealthDomain = status_mod.HealthDomain;

pub const PolicyMode = enum {
    observe,
    ask,
    strict,
    ci,
    redteam,
    simulation,
    bench,
};

pub const HeartbeatPolicy = struct {
    agent_max_age_ms: u64 = 1000,
    adapter_max_age_ms: u64 = 1000,
    mavlink_max_age_ms: u64 = 1000,
    px4_sitl_max_age_ms: u64 = 1500,
    ardupilot_sitl_max_age_ms: u64 = 1500,
    runtime_max_age_ms: u64 = 1000,
    audit_writer_max_age_ms: u64 = 1000,
    safety_engine_max_age_ms: u64 = 1000,
};

pub const TelemetryPolicy = struct {
    vehicle_state_max_age_ms: u64 = 1000,
    position_max_age_ms: u64 = 1000,
    battery_max_age_ms: u64 = 2000,
    gps_max_age_ms: u64 = 2000,
    link_max_age_ms: u64 = 1000,
};

pub const AuditPolicy = struct {
    require_audit_writer: bool = false,
    fail_closed_on_audit_error: bool = true,
    max_event_append_latency_ms: u64 = 100,
};

pub const DegradedModePolicy = struct {
    on_agent_stale: DegradedBehavior = .deny_high_risk,
    on_adapter_stale: DegradedBehavior = .deny_high_risk,
    on_telemetry_stale: DegradedBehavior = .deny_movement,
    on_audit_failure: DegradedBehavior = .fail_closed,
    on_policy_error: DegradedBehavior = .fail_closed,
    on_data_guard_failure: DegradedBehavior = .deny_external_egress,
    allow_emergency_land: bool = true,
    allow_return_to_home: EmergencyAllowance = .policy,
    allow_hold: EmergencyAllowance = .policy,
};

pub const ResourcePolicy = struct {
    max_memory_mb: u64 = 512,
    max_cpu_percent: u8 = 90,
    max_event_queue_depth: u64 = 1000,
};

pub const WatchdogPolicy = struct {
    enabled: bool = true,
    heartbeat_timeout_ms: u64 = 2000,
    state_stale_after_ms: u64 = 1000,
    command_timeout_ms: u64 = 1500,
    max_command_queue_depth: u64 = 100,
    max_audit_queue_depth: u64 = 1000,
    fail_closed_on_policy_failure: bool = true,
    fail_closed_on_state_expiry: bool = true,
    recommended_fallback_order: [3]domain_mod.commands.CommandAction = .{ .land, .hold_position, .return_to_home },
    recommended_fallback_order_len: u8 = 3,
    heartbeat: HeartbeatPolicy = .{},
    telemetry: TelemetryPolicy = .{},
    audit: AuditPolicy = .{},
    degraded_mode: DegradedModePolicy = .{},
    resource: ResourcePolicy = .{},

    pub fn applyModeDefaults(self: *WatchdogPolicy, mode: PolicyMode) !void {
        switch (mode) {
            .strict, .ci, .redteam => {
                self.audit.require_audit_writer = true;
                self.audit.fail_closed_on_audit_error = true;
            },
            else => {},
        }
        try self.validate();
    }

    pub fn validate(self: WatchdogPolicy) !void {
        if (!self.enabled) return;
        try positive(self.heartbeat_timeout_ms);
        try positive(self.state_stale_after_ms);
        try positive(self.command_timeout_ms);
        try positive(self.max_command_queue_depth);
        try positive(self.max_audit_queue_depth);
        try positive(self.heartbeat.agent_max_age_ms);
        try positive(self.heartbeat.adapter_max_age_ms);
        try positive(self.heartbeat.mavlink_max_age_ms);
        try positive(self.heartbeat.px4_sitl_max_age_ms);
        try positive(self.heartbeat.ardupilot_sitl_max_age_ms);
        try positive(self.heartbeat.runtime_max_age_ms);
        try positive(self.heartbeat.audit_writer_max_age_ms);
        try positive(self.heartbeat.safety_engine_max_age_ms);
        try positive(self.telemetry.vehicle_state_max_age_ms);
        try positive(self.telemetry.position_max_age_ms);
        try positive(self.telemetry.battery_max_age_ms);
        try positive(self.telemetry.gps_max_age_ms);
        try positive(self.telemetry.link_max_age_ms);
        try positive(self.audit.max_event_append_latency_ms);
        try positive(self.resource.max_memory_mb);
        try positive(self.resource.max_event_queue_depth);
        if (self.resource.max_cpu_percent == 0 or self.resource.max_cpu_percent > 100) return error.InvalidWatchdogPolicy;
        if (self.recommended_fallback_order_len == 0 or self.recommended_fallback_order_len > self.recommended_fallback_order.len) return error.InvalidWatchdogPolicy;
        for (self.recommended_fallback_order[0..self.recommended_fallback_order_len]) |command| {
            if (!isValidFallbackCommand(command)) return error.InvalidWatchdogFallbackCommand;
        }
        if (self.degraded_mode.on_agent_stale == .unknown or
            self.degraded_mode.on_adapter_stale == .unknown or
            self.degraded_mode.on_telemetry_stale == .unknown or
            self.degraded_mode.on_audit_failure == .unknown or
            self.degraded_mode.on_policy_error == .unknown or
            self.degraded_mode.on_data_guard_failure == .unknown)
        {
            return error.UnknownDegradedBehavior;
        }
    }

    pub fn heartbeatMaxAge(self: WatchdogPolicy, domain: HealthDomain) u64 {
        return switch (domain) {
            .agent => self.heartbeat.agent_max_age_ms,
            .adapter => self.heartbeat.adapter_max_age_ms,
            .mavlink, .link_state => self.heartbeat.mavlink_max_age_ms,
            .px4_sitl => self.heartbeat.px4_sitl_max_age_ms,
            .ardupilot_sitl => self.heartbeat.ardupilot_sitl_max_age_ms,
            .runtime => self.heartbeat.runtime_max_age_ms,
            .audit_writer => self.heartbeat.audit_writer_max_age_ms,
            .safety_engine => self.heartbeat.safety_engine_max_age_ms,
            else => self.heartbeat.runtime_max_age_ms,
        };
    }
};

fn positive(value: u64) !void {
    if (value == 0) return error.InvalidWatchdogPolicy;
}

pub fn isValidFallbackCommand(command: domain_mod.commands.CommandAction) bool {
    return switch (command) {
        .land, .hold_position, .return_to_home => true,
        else => false,
    };
}
