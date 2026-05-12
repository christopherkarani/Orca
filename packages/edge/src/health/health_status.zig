const std = @import("std");

pub const Severity = enum {
    info,
    warning,
    high,
    critical,

    pub fn toString(self: Severity) []const u8 {
        return @tagName(self);
    }
};

pub const HealthStatus = enum {
    healthy,
    degraded,
    critical,
    failed,
    unavailable,
    unknown,

    pub fn toString(self: HealthStatus) []const u8 {
        return @tagName(self);
    }

    pub fn rank(self: HealthStatus) u8 {
        return switch (self) {
            .healthy => 0,
            .degraded => 1,
            .unknown => 2,
            .unavailable => 3,
            .critical => 4,
            .failed => 5,
        };
    }

    pub fn worse(a: HealthStatus, b: HealthStatus) HealthStatus {
        return if (a.rank() >= b.rank()) a else b;
    }

    pub fn defaultSeverity(self: HealthStatus) Severity {
        return switch (self) {
            .healthy => .info,
            .degraded => .warning,
            .unknown, .unavailable => .high,
            .critical, .failed => .critical,
        };
    }
};

pub const HealthDomain = enum {
    runtime,
    agent,
    adapter,
    mavlink,
    px4_sitl,
    ardupilot_sitl,
    telemetry,
    vehicle_state,
    battery_state,
    gps_state,
    link_state,
    audit_writer,
    policy_engine,
    safety_engine,
    data_guard,
    redteam_runner,
    storage,
    resource_usage,
    clock,
    configuration,
    unknown,

    pub fn toString(self: HealthDomain) []const u8 {
        return @tagName(self);
    }
};

pub fn parseDomain(value: []const u8) ?HealthDomain {
    inline for (std.meta.fields(HealthDomain)) |field| {
        if (std.mem.eql(u8, field.name, value)) return @field(HealthDomain, field.name);
    }
    return null;
}
