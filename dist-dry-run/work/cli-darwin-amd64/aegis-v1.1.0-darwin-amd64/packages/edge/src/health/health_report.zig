const std = @import("std");

const degraded = @import("degraded_mode.zig");
const findings_mod = @import("health_findings.zig");
const status_mod = @import("health_status.zig");

pub const HealthStatus = status_mod.HealthStatus;
pub const HealthDomain = status_mod.HealthDomain;
pub const DegradedBehavior = degraded.DegradedBehavior;
pub const HealthFinding = findings_mod.HealthFinding;

pub const DomainStatus = struct {
    domain: HealthDomain,
    status: HealthStatus,
};

pub const HealthReportInit = struct {
    overall_status: HealthStatus = .healthy,
    domain_statuses: []const DomainStatus = &.{},
    findings: []const HealthFinding = &.{},
    recommended_behavior: DegradedBehavior = .observe_only,
    safe_to_evaluate_commands: bool = true,
    safe_to_forward_commands: bool = true,
    evidence_summary: []const u8 = "runtime health evaluated for fake/SITL/bench evidence only",
};

pub const HealthReport = struct {
    allocator: ?std.mem.Allocator = null,
    overall_status: HealthStatus,
    domain_statuses: []const DomainStatus = &.{},
    findings: []const HealthFinding = &.{},
    recommended_behavior: DegradedBehavior = .observe_only,
    safe_to_evaluate_commands: bool = true,
    safe_to_forward_commands: bool = true,
    evidence_summary: []const u8 = "runtime health evaluated for fake/SITL/bench evidence only",

    pub fn initStatic(args: HealthReportInit) HealthReport {
        return .{
            .overall_status = args.overall_status,
            .domain_statuses = args.domain_statuses,
            .findings = args.findings,
            .recommended_behavior = args.recommended_behavior,
            .safe_to_evaluate_commands = args.safe_to_evaluate_commands,
            .safe_to_forward_commands = args.safe_to_forward_commands,
            .evidence_summary = args.evidence_summary,
        };
    }

    pub fn deinit(self: *HealthReport) void {
        if (self.allocator) |allocator| {
            if (self.domain_statuses.len > 0) allocator.free(self.domain_statuses);
            if (self.findings.len > 0) allocator.free(self.findings);
        }
        self.* = undefined;
    }

    pub fn hasDomain(self: HealthReport, domain: HealthDomain) bool {
        for (self.domain_statuses) |status| {
            if (status.domain == domain) return true;
        }
        for (self.findings) |finding| {
            if (finding.domain == domain) return true;
        }
        return false;
    }

    pub fn hasFindingId(self: HealthReport, id: []const u8) bool {
        for (self.findings) |finding| {
            if (std.mem.eql(u8, finding.finding_id, id)) return true;
        }
        return false;
    }
};

pub const Builder = struct {
    allocator: std.mem.Allocator,
    domain_statuses: std.ArrayList(DomainStatus) = .empty,
    findings: std.ArrayList(HealthFinding) = .empty,
    overall: HealthStatus = .healthy,
    recommended: DegradedBehavior = .observe_only,

    pub fn deinit(self: *Builder) void {
        self.domain_statuses.deinit(self.allocator);
        self.findings.deinit(self.allocator);
    }

    pub fn addStatus(self: *Builder, domain: HealthDomain, status: HealthStatus) !void {
        try self.domain_statuses.append(self.allocator, .{ .domain = domain, .status = status });
        self.overall = HealthStatus.worse(self.overall, status);
    }

    pub fn addFinding(self: *Builder, finding: HealthFinding) !void {
        try self.findings.append(self.allocator, finding);
        self.overall = HealthStatus.worse(self.overall, finding.status);
        self.recommended = DegradedBehavior.stricter(self.recommended, finding.recommended_behavior);
        try self.addStatus(finding.domain, finding.status);
    }

    pub fn finish(self: *Builder, summary: []const u8) !HealthReport {
        return .{
            .allocator = self.allocator,
            .overall_status = self.overall,
            .domain_statuses = try self.domain_statuses.toOwnedSlice(self.allocator),
            .findings = try self.findings.toOwnedSlice(self.allocator),
            .recommended_behavior = self.recommended,
            .safe_to_evaluate_commands = self.overall.rank() < HealthStatus.critical.rank(),
            .safe_to_forward_commands = self.overall == .healthy,
            .evidence_summary = summary,
        };
    }
};
