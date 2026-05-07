const std = @import("std");

pub const non_certification_disclaimer =
    "Aegis Edge safety reports are engineering audit artifacts only. They are not regulatory approval, certification, airworthiness approval, or real-flight readiness claims.";

pub const environments = [_][]const u8{
    "fake adapter",
    "PX4 SITL",
    "ArduPilot SITL",
    "bench",
    "other",
};

pub const SafetyReportV1 = struct {
    report_id: []const u8,
    report_version: u32 = 1,
    vehicle_profile: []const u8,
    adapter_profile: []const u8,
    policy_hash: []const u8,
    scenario_name: []const u8,
    scenario_source: []const u8,
    test_environment: []const u8,
    safety_checks_run: []const []const u8 = &.{},
    commands_allowed: []const []const u8 = &.{},
    commands_denied: []const []const u8 = &.{},
    violations_detected: []const []const u8 = &.{},
    audit_event_references: []const []const u8 = &.{},
    limitations: []const []const u8 = &.{non_certification_disclaimer},

    pub fn validate(self: SafetyReportV1) !void {
        if (self.report_id.len == 0) return error.MissingReportId;
        if (self.report_version != 1) return error.UnsupportedSchemaVersion;
        if (!hasEnvironment(self.test_environment)) return error.UnknownTestEnvironment;
        if (!hasLimitation(non_certification_disclaimer)) return error.MissingNonCertificationDisclaimer;
    }
};

pub fn hasEnvironment(value: []const u8) bool {
    for (environments) |environment| {
        if (std.mem.eql(u8, environment, value)) return true;
    }
    return false;
}

pub fn hasLimitation(value: []const u8) bool {
    return std.mem.eql(u8, value, non_certification_disclaimer);
}
