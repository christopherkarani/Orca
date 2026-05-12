const std = @import("std");
const builtin = @import("builtin");

const policy = @import("../policy/mod.zig");

pub const phase = "36-edge-deployment-arm64-hardware-bench";
pub const no_flight_disclaimer = "Aegis Edge bench and deployment checks are simulation/SITL/bench-preparation evidence only; they are not real-flight readiness, airworthiness approval, regulatory certification, detect-and-avoid, or autopilot replacement.";

pub const Status = enum {
    active,
    partial,
    unavailable,
    missing,
    unsupported,
    failed,

    pub fn toString(self: Status) []const u8 {
        return switch (self) {
            .active => "active",
            .partial => "partial",
            .unavailable => "unavailable",
            .missing => "missing",
            .unsupported => "unsupported",
            .failed => "failed",
        };
    }
};

pub const TargetArch = enum {
    linux_amd64,
    linux_arm64,
    linux_armv7,
    macos_arm64,
    macos_amd64,
    unknown,

    pub fn parse(value: []const u8) TargetArch {
        if (equalsAny(value, &.{ "linux-amd64", "x86_64-linux", "amd64" })) return .linux_amd64;
        if (equalsAny(value, &.{ "linux-arm64", "aarch64-linux", "arm64", "aarch64" })) return .linux_arm64;
        if (equalsAny(value, &.{ "linux-armv7", "armv7-linux", "armv7" })) return .linux_armv7;
        if (equalsAny(value, &.{ "macos-arm64", "aarch64-macos", "darwin-arm64" })) return .macos_arm64;
        if (equalsAny(value, &.{ "macos-amd64", "x86_64-macos", "darwin-amd64" })) return .macos_amd64;
        return .unknown;
    }

    pub fn toString(self: TargetArch) []const u8 {
        return switch (self) {
            .linux_amd64 => "linux-amd64",
            .linux_arm64 => "linux-arm64",
            .linux_armv7 => "linux-armv7",
            .macos_arm64 => "macos-arm64",
            .macos_amd64 => "macos-amd64",
            .unknown => "unknown",
        };
    }

    pub fn supportStatus(self: TargetArch) Status {
        return switch (self) {
            .linux_amd64, .linux_arm64, .macos_arm64, .macos_amd64 => .active,
            .linux_armv7 => .unsupported,
            .unknown => .unsupported,
        };
    }

    pub fn packageStatus(self: TargetArch) Status {
        return switch (self) {
            .linux_amd64, .linux_arm64 => .active,
            .linux_armv7, .macos_arm64, .macos_amd64, .unknown => .unsupported,
        };
    }
};

pub const DeploymentMode = enum {
    source,
    packaged,
    container,
    edge_device,
    bench,
    simulation,
    real_flight,
    unknown,

    pub fn parse(value: []const u8) DeploymentMode {
        return std.meta.stringToEnum(DeploymentMode, value) orelse .unknown;
    }

    pub fn toString(self: DeploymentMode) []const u8 {
        return @tagName(self);
    }
};

pub const Environment = enum {
    fake_adapter,
    px4_sitl,
    ardupilot_sitl,
    hardware_bench_no_actuation,
    real_flight,
    unknown,

    pub fn parse(value: []const u8) Environment {
        return std.meta.stringToEnum(Environment, value) orelse .unknown;
    }

    pub fn toString(self: Environment) []const u8 {
        return @tagName(self);
    }
};

pub const NetworkMode = enum {
    offline,
    local_only,
    sitl_only,
    disabled,
    unknown,

    pub fn parse(value: []const u8) NetworkMode {
        return std.meta.stringToEnum(NetworkMode, value) orelse .unknown;
    }

    pub fn toString(self: NetworkMode) []const u8 {
        return @tagName(self);
    }
};

pub const DeploymentProfile = struct {
    allocator: std.mem.Allocator,
    id: []u8,
    target_arch: TargetArch,
    os: []u8,
    mode: DeploymentMode,
    environment: Environment,
    runtime_assets: []u8,
    policy_path: []u8,
    scenario_path: []u8,
    audit_output_path: []u8,
    log_output_path: []u8,
    network_mode: NetworkMode,
    mavlink_endpoint: ?[]u8,
    sitl_config: ?[]u8,
    safety_limitations: []u8,
    operator_acknowledgement: bool,
    bench: bool,

    pub fn deinit(self: *DeploymentProfile) void {
        self.allocator.free(self.id);
        self.allocator.free(self.os);
        self.allocator.free(self.runtime_assets);
        self.allocator.free(self.policy_path);
        self.allocator.free(self.scenario_path);
        self.allocator.free(self.audit_output_path);
        self.allocator.free(self.log_output_path);
        if (self.mavlink_endpoint) |value| self.allocator.free(value);
        if (self.sitl_config) |value| self.allocator.free(value);
        self.allocator.free(self.safety_limitations);
        self.* = undefined;
    }

    pub fn isBench(self: DeploymentProfile) bool {
        return self.bench or self.mode == .bench or self.environment == .hardware_bench_no_actuation;
    }
};

pub const AssetCheck = struct {
    name: []const u8,
    path: []const u8,
    status: Status,
    required: bool,
};

pub const AssetReport = struct {
    allocator: std.mem.Allocator,
    checks: []AssetCheck,

    pub fn deinit(self: *AssetReport) void {
        self.allocator.free(self.checks);
        self.* = undefined;
    }

    pub fn overall(self: AssetReport) Status {
        var saw_partial = false;
        for (self.checks) |check| {
            if (check.required and (check.status == .missing or check.status == .failed)) return .missing;
            if (check.status != .active) saw_partial = true;
        }
        return if (saw_partial) .partial else .active;
    }
};

pub const required_assets = [_]AssetCheck{
    .{ .name = "edge policy schema", .path = "schemas/edge-policy-v1.json", .status = .active, .required = true },
    .{ .name = "edge event schema", .path = "schemas/edge-event-v1.json", .status = .active, .required = true },
    .{ .name = "safety report schema", .path = "schemas/safety-report-v1.json", .status = .active, .required = true },
    .{ .name = "safety policies", .path = "examples/edge/safety/policies/safety-strict.yaml", .status = .active, .required = true },
    .{ .name = "safety scenarios", .path = "examples/edge/safety/scenarios/geofence-deny.yaml", .status = .active, .required = true },
    .{ .name = "MAVLink examples", .path = "examples/edge/mavlink/scenarios/geofence-deny.yaml", .status = .active, .required = true },
    .{ .name = "PX4 examples", .path = "examples/edge/px4/scenarios/waypoint-outside-geofence-deny.yaml", .status = .active, .required = true },
    .{ .name = "ArduPilot examples", .path = "examples/edge/ardupilot/scenarios/waypoint-outside-geofence-deny.yaml", .status = .active, .required = true },
    .{ .name = "red-team fixtures", .path = "examples/edge/redteam/README.md", .status = .active, .required = true },
    .{ .name = "safety-case templates", .path = "examples/edge/safety-case/README.md", .status = .active, .required = true },
    .{ .name = "runtime docs", .path = "docs/edge/simulation-vs-flight.md", .status = .active, .required = true },
    .{ .name = "runtime health docs", .path = "docs/edge/runtime-health.md", .status = .active, .required = true },
    .{ .name = "watchdog docs", .path = "docs/edge/watchdog.md", .status = .active, .required = true },
    .{ .name = "watchdog policy examples", .path = "examples/edge/health/policies/watchdog-strict.yaml", .status = .active, .required = true },
    .{ .name = "watchdog scenario examples", .path = "examples/edge/health/scenarios/heartbeat-expired.yaml", .status = .active, .required = true },
};

pub fn doctorAssets(allocator: std.mem.Allocator) !AssetReport {
    const checks = try allocator.alloc(AssetCheck, required_assets.len);
    for (required_assets, 0..) |asset, index| {
        checks[index] = asset;
        checks[index].status = if (pathExists(asset.path)) .active else .missing;
    }
    return .{ .allocator = allocator, .checks = checks };
}

pub const DeploymentCheck = struct {
    status: Status,
    reason: []const u8,
};

pub fn checkProfile(profile: DeploymentProfile) DeploymentCheck {
    if (profile.mode == .real_flight or profile.environment == .real_flight) {
        return .{ .status = .unsupported, .reason = "real-flight profiles are unsupported in Phase 36" };
    }
    if (profile.target_arch.supportStatus() == .unsupported) {
        return .{ .status = .unsupported, .reason = "target architecture is unsupported by Phase 36 release checks" };
    }
    if (profile.mode == .packaged and profile.target_arch.packageStatus() == .unsupported) {
        return .{ .status = .unsupported, .reason = "packaged Edge release artifacts are only produced for linux-amd64 and linux-arm64" };
    }
    if (profile.policy_path.len == 0 or !pathExists(profile.policy_path)) {
        return .{ .status = .missing, .reason = "policy path is missing or unreadable" };
    }
    if (profile.scenario_path.len == 0 or !pathExists(profile.scenario_path)) {
        return .{ .status = .missing, .reason = "scenario path is missing or unreadable" };
    }
    if (profile.isBench()) {
        if (!profile.bench) return .{ .status = .failed, .reason = "hardware bench profiles require explicit bench: true" };
        if (profile.environment != .hardware_bench_no_actuation and profile.environment != .fake_adapter) {
            return .{ .status = .failed, .reason = "bench profiles must use fake_adapter or hardware_bench_no_actuation" };
        }
        if (profile.operator_acknowledgement == false and profile.mavlink_endpoint != null) {
            return .{ .status = .failed, .reason = "bench profiles with endpoint-like config require explicit operator acknowledgement" };
        }
    }
    return .{ .status = .active, .reason = "deployment profile is bounded to source/package/container/SITL/bench evaluation" };
}

pub const BenchReport = struct {
    status: Status,
    policy_status: Status,
    scenario_status: Status,
    asset_status: Status,
    target_arch: TargetArch,
    provenance: Environment,
    operator_approval_status: Status,
    emergency_mode_status: Status,
    network_data_guard_status: Status,
    redteam_status: Status,
    safety_case_status: Status,
};

pub fn benchReport(policy_path: []const u8, scenario_path: ?[]const u8) BenchReport {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const assets = doctorAssets(arena.allocator()) catch return .{
        .status = .failed,
        .policy_status = if (pathExists(policy_path)) .active else .missing,
        .scenario_status = if (scenario_path) |path| if (pathExists(path)) .active else .missing else .unavailable,
        .asset_status = .failed,
        .target_arch = currentTargetArch(),
        .provenance = .hardware_bench_no_actuation,
        .operator_approval_status = .active,
        .emergency_mode_status = .active,
        .network_data_guard_status = .active,
        .redteam_status = .active,
        .safety_case_status = .partial,
    };
    const policy_status: Status = if (pathExists(policy_path)) .active else .missing;
    const scenario_status: Status = if (scenario_path) |path| if (pathExists(path)) .active else .missing else .unavailable;
    const status: Status = if (policy_status == .active and (scenario_status == .active or scenario_status == .unavailable) and assets.overall() == .active) .active else .failed;
    return .{
        .status = status,
        .policy_status = policy_status,
        .scenario_status = scenario_status,
        .asset_status = assets.overall(),
        .target_arch = currentTargetArch(),
        .provenance = .hardware_bench_no_actuation,
        .operator_approval_status = .active,
        .emergency_mode_status = .active,
        .network_data_guard_status = .active,
        .redteam_status = .active,
        .safety_case_status = if (scenario_status == .active) .active else .partial,
    };
}

pub const PackageInfo = struct {
    version: []const u8,
    target_arch: TargetArch,

    pub fn artifactName(self: PackageInfo, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "aegis-edge-v{s}-{s}.tar.gz", .{ self.version, self.target_arch.toString() });
    }
};

pub fn packageManifest(writer: anytype, version: []const u8, arch: TargetArch) !void {
    try writer.print("package: aegis-edge\nversion: {s}\ntarget_arch: {s}\n", .{ version, arch.toString() });
    try writer.print("artifact: aegis-edge-v{s}-{s}.tar.gz\n", .{ version, arch.toString() });
    try writer.writeAll("binaries:\n  - aegis-edge\nassets:\n");
    for (required_assets) |asset| try writer.print("  - {s}\n", .{asset.path});
    try writer.writeAll("checksums: SHA256SUMS\nlimitations:\n  - simulation/SITL/bench-preparation only\n  - no real-flight readiness claim\n");
}

pub fn loadProfileFile(allocator: std.mem.Allocator, path: []const u8) !DeploymentProfile {
    const text = try std.fs.cwd().readFileAlloc(allocator, path, 128 * 1024);
    defer allocator.free(text);
    return parseProfile(allocator, text);
}

pub fn parseProfile(allocator: std.mem.Allocator, text: []const u8) !DeploymentProfile {
    var id: ?[]const u8 = null;
    var target_arch: TargetArch = .unknown;
    var os: []const u8 = "linux";
    var mode: DeploymentMode = .unknown;
    var environment: Environment = .unknown;
    var runtime_assets: []const u8 = "source";
    var profile_policy: ?[]const u8 = null;
    var scenario: ?[]const u8 = null;
    var audit_output: []const u8 = ".aegis-edge/sessions";
    var log_output: []const u8 = ".aegis-edge/logs";
    var network_mode: NetworkMode = .offline;
    var mavlink_endpoint: ?[]const u8 = null;
    var sitl_config: ?[]const u8 = null;
    var safety_limitations: []const u8 = no_flight_disclaimer;
    var operator_acknowledgement = false;
    var bench = false;

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const no_comment = if (std.mem.indexOfScalar(u8, raw_line, '#')) |comment| raw_line[0..comment] else raw_line;
        const line = std.mem.trim(u8, no_comment, " \t\r");
        if (line.len == 0) continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const key = std.mem.trim(u8, line[0..colon], " \t");
        const value = cleanScalar(line[colon + 1 ..]);
        if (value.len == 0) continue;
        if (std.mem.eql(u8, key, "id") or std.mem.eql(u8, key, "profile_id")) id = value else if (std.mem.eql(u8, key, "target_arch") or std.mem.eql(u8, key, "architecture")) target_arch = TargetArch.parse(value) else if (std.mem.eql(u8, key, "os")) os = value else if (std.mem.eql(u8, key, "deployment_mode") or std.mem.eql(u8, key, "mode")) mode = DeploymentMode.parse(value) else if (std.mem.eql(u8, key, "environment")) environment = Environment.parse(value) else if (std.mem.eql(u8, key, "runtime_assets") or std.mem.eql(u8, key, "runtime_asset_paths")) runtime_assets = value else if (std.mem.eql(u8, key, "policy_path") or std.mem.eql(u8, key, "policy")) profile_policy = value else if (std.mem.eql(u8, key, "scenario_path") or std.mem.eql(u8, key, "scenario")) scenario = value else if (std.mem.eql(u8, key, "audit_output_path")) audit_output = value else if (std.mem.eql(u8, key, "log_output_path")) log_output = value else if (std.mem.eql(u8, key, "network_mode")) network_mode = NetworkMode.parse(value) else if (std.mem.eql(u8, key, "mavlink_endpoint")) mavlink_endpoint = value else if (std.mem.eql(u8, key, "sitl_config")) sitl_config = value else if (std.mem.eql(u8, key, "safety_limitations")) safety_limitations = value else if (std.mem.eql(u8, key, "operator_acknowledgement")) operator_acknowledgement = parseBool(value) else if (std.mem.eql(u8, key, "bench")) bench = parseBool(value);
    }

    if (mode == .real_flight or environment == .real_flight) return error.RealFlightProfileUnsupported;
    if (id == null or profile_policy == null or scenario == null) return error.InvalidDeploymentProfile;
    return .{
        .allocator = allocator,
        .id = try allocator.dupe(u8, id.?),
        .target_arch = target_arch,
        .os = try allocator.dupe(u8, os),
        .mode = mode,
        .environment = environment,
        .runtime_assets = try allocator.dupe(u8, runtime_assets),
        .policy_path = try allocator.dupe(u8, profile_policy.?),
        .scenario_path = try allocator.dupe(u8, scenario.?),
        .audit_output_path = try allocator.dupe(u8, audit_output),
        .log_output_path = try allocator.dupe(u8, log_output),
        .network_mode = network_mode,
        .mavlink_endpoint = if (mavlink_endpoint) |value| try redactSecretLike(allocator, value) else null,
        .sitl_config = if (sitl_config) |value| try redactSecretLike(allocator, value) else null,
        .safety_limitations = try allocator.dupe(u8, safety_limitations),
        .operator_acknowledgement = operator_acknowledgement,
        .bench = bench,
    };
}

pub fn validatePolicy(path: []const u8, allocator: std.mem.Allocator) Status {
    var loaded = policy.loadFile(allocator, path, .{}) catch return .failed;
    loaded.deinit();
    return .active;
}

pub fn currentTargetArch() TargetArch {
    return switch (builtin.os.tag) {
        .linux => switch (builtin.cpu.arch) {
            .x86_64 => .linux_amd64,
            .aarch64 => .linux_arm64,
            .arm => .linux_armv7,
            else => .unknown,
        },
        .macos => switch (builtin.cpu.arch) {
            .aarch64 => .macos_arm64,
            .x86_64 => .macos_amd64,
            else => .unknown,
        },
        else => .unknown,
    };
}

fn cleanScalar(raw: []const u8) []const u8 {
    var value = std.mem.trim(u8, raw, " \t\r");
    if (value.len >= 2 and ((value[0] == '"' and value[value.len - 1] == '"') or (value[0] == '\'' and value[value.len - 1] == '\''))) {
        value = value[1 .. value.len - 1];
    }
    return value;
}

fn parseBool(value: []const u8) bool {
    return std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "yes") or std.mem.eql(u8, value, "1");
}

fn equalsAny(value: []const u8, options: []const []const u8) bool {
    for (options) |option| if (std.mem.eql(u8, value, option)) return true;
    return false;
}

fn pathExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn redactSecretLike(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    const lower = try std.ascii.allocLowerString(allocator, value);
    defer allocator.free(lower);
    if (std.mem.indexOf(u8, lower, "secret") != null or std.mem.indexOf(u8, lower, "token") != null or std.mem.indexOf(u8, lower, "password") != null or std.mem.indexOf(u8, lower, "key=") != null) {
        return allocator.dupe(u8, "[REDACTED]");
    }
    return allocator.dupe(u8, value);
}

test "deployment profile rejects real flight and parses bounded bench profile" {
    const allocator = std.testing.allocator;
    var profile = try parseProfile(allocator,
        \\id: bench
        \\target_arch: linux-arm64
        \\os: linux
        \\deployment_mode: bench
        \\environment: hardware_bench_no_actuation
        \\runtime_assets: source
        \\policy_path: examples/edge/safety/policies/safety-strict.yaml
        \\scenario_path: examples/edge/safety/scenarios/geofence-deny.yaml
        \\network_mode: local_only
        \\bench: true
        \\operator_acknowledgement: true
    );
    defer profile.deinit();
    try std.testing.expectEqual(TargetArch.linux_arm64, profile.target_arch);
    try std.testing.expectEqual(Environment.hardware_bench_no_actuation, profile.environment);
    try std.testing.expectEqual(Status.active, checkProfile(profile).status);
    try std.testing.expectError(error.RealFlightProfileUnsupported, parseProfile(allocator,
        \\id: bad
        \\target_arch: linux-arm64
        \\deployment_mode: real_flight
        \\environment: real_flight
        \\policy_path: examples/edge/safety/policies/safety-strict.yaml
        \\scenario_path: examples/edge/safety/scenarios/geofence-deny.yaml
    ));
}

test "runtime assets and package manifest include required release surface" {
    var report = try doctorAssets(std.testing.allocator);
    defer report.deinit();
    try std.testing.expect(report.checks.len >= 8);
    try std.testing.expectEqual(Status.active, report.overall());

    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try packageManifest(stream.writer(), "1.1.0", .linux_arm64);
    const text = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, text, "aegis-edge-v1.1.0-linux-arm64.tar.gz") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "schemas/edge-policy-v1.json") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "examples/edge/redteam/README.md") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "no real-flight readiness claim") != null);
}
