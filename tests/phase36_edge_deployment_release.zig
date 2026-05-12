const std = @import("std");
const edge = @import("aegis_edge");

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(allocator, path, 512 * 1024);
}

test "phase 36 deployment profiles parse bounded fake SITL and bench profiles" {
    const allocator = std.testing.allocator;
    const profiles = [_]struct {
        path: []const u8,
        arch: edge.deployment.TargetArch,
        environment: edge.deployment.Environment,
        mode: edge.deployment.DeploymentMode,
    }{
        .{ .path = "examples/edge/deployment/profiles/source-local-fake.yaml", .arch = .linux_amd64, .environment = .fake_adapter, .mode = .source },
        .{ .path = "examples/edge/deployment/profiles/packaged-linux-arm64-fake.yaml", .arch = .linux_arm64, .environment = .fake_adapter, .mode = .packaged },
        .{ .path = "examples/edge/deployment/profiles/px4-sitl-local.yaml", .arch = .linux_amd64, .environment = .px4_sitl, .mode = .simulation },
        .{ .path = "examples/edge/deployment/profiles/ardupilot-sitl-local.yaml", .arch = .linux_amd64, .environment = .ardupilot_sitl, .mode = .simulation },
        .{ .path = "examples/edge/deployment/profiles/hardware-bench-no-actuation.yaml", .arch = .linux_arm64, .environment = .hardware_bench_no_actuation, .mode = .bench },
    };
    for (profiles) |case| {
        var profile = try edge.deployment.loadProfileFile(allocator, case.path);
        defer profile.deinit();
        try std.testing.expectEqual(case.arch, profile.target_arch);
        try std.testing.expectEqual(case.environment, profile.environment);
        try std.testing.expectEqual(case.mode, profile.mode);
        try std.testing.expectEqual(edge.deployment.Status.active, edge.deployment.checkProfile(profile).status);
    }

    try std.testing.expectError(error.RealFlightProfileUnsupported, edge.deployment.parseProfile(allocator,
        \\id: rejected-real-flight
        \\target_arch: linux-arm64
        \\os: linux
        \\deployment_mode: real_flight
        \\environment: real_flight
        \\policy_path: examples/edge/safety/policies/safety-strict.yaml
        \\scenario_path: examples/edge/safety/scenarios/geofence-deny.yaml
    ));
}

test "phase 36 runtime asset doctor covers required source and package assets" {
    var report = try edge.deployment.doctorAssets(std.testing.allocator);
    defer report.deinit();
    try std.testing.expectEqual(edge.deployment.Status.active, report.overall());
    try std.testing.expect(report.checks.len >= 10);
    try expectAsset(report, "schemas/edge-policy-v1.json");
    try expectAsset(report, "schemas/edge-event-v1.json");
    try expectAsset(report, "schemas/safety-report-v1.json");
    try expectAsset(report, "examples/edge/redteam/README.md");
    try expectAsset(report, "examples/edge/safety-case/README.md");
    try expectAsset(report, "docs/edge/simulation-vs-flight.md");
}

test "phase 36 package metadata names linux amd64 and arm64 artifacts with checksums" {
    const allocator = std.testing.allocator;
    const arm64_info: edge.deployment.PackageInfo = .{ .version = "1.1.0", .target_arch = .linux_arm64 };
    const arm64_artifact = try arm64_info.artifactName(allocator);
    defer allocator.free(arm64_artifact);
    try std.testing.expectEqualStrings("aegis-edge-v1.1.0-linux-arm64.tar.gz", arm64_artifact);

    var buf: [8192]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try edge.deployment.packageManifest(stream.writer(), "1.1.0", .linux_amd64);
    const manifest = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, manifest, "aegis-edge-v1.1.0-linux-amd64.tar.gz") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "binaries:\n  - aegis-edge") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "checksums: SHA256SUMS") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "examples/edge/redteam/README.md") != null);
    try std.testing.expectEqual(edge.deployment.Status.active, edge.deployment.TargetArch.linux_amd64.packageStatus());
    try std.testing.expectEqual(edge.deployment.Status.active, edge.deployment.TargetArch.linux_arm64.packageStatus());
    try std.testing.expectEqual(edge.deployment.Status.unsupported, edge.deployment.TargetArch.macos_arm64.packageStatus());
    try std.testing.expectEqual(edge.deployment.Status.unsupported, edge.deployment.TargetArch.macos_amd64.packageStatus());
}

test "phase 36 bench report includes no-flight and no-certification boundary" {
    const report = edge.deployment.benchReport(
        "examples/edge/safety/policies/safety-strict.yaml",
        "examples/edge/safety/scenarios/geofence-deny.yaml",
    );
    try std.testing.expectEqual(edge.deployment.Status.active, report.policy_status);
    try std.testing.expectEqual(edge.deployment.Status.active, report.scenario_status);
    try std.testing.expectEqual(edge.deployment.Environment.hardware_bench_no_actuation, report.provenance);
    try std.testing.expect(std.mem.indexOf(u8, edge.deployment.no_flight_disclaimer, "not real-flight readiness") != null);
    try std.testing.expect(std.mem.indexOf(u8, edge.deployment.no_flight_disclaimer, "regulatory certification") != null);
}

test "phase 36 safety report bench provenance remains bench preparation only" {
    var buf: [8192]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try edge.audit.safety_report.writeJson(stream.writer(), .{
        .report_id = "bench-report",
        .generated_at = "2026-05-12T00:00:00Z",
        .scenario_id = "bench-no-actuation",
        .scenario_name = "bench-no-actuation",
        .scenario_source = "examples/edge/deployment/profiles/hardware-bench-no-actuation.yaml",
        .session_id = "session",
        .policy_file = "examples/edge/safety/policies/safety-strict.yaml",
        .policy_hash = "hash",
        .report_hash = "report-hash",
        .provenance = .bench,
        .vehicle_id = "edge-vehicle-1",
        .vehicle_kind = "drone_multirotor",
        .autopilot_kind = "none",
        .adapter_kind = "bench_no_actuation",
        .vehicle_type = "bench",
        .tested_autopilot_version = "not_applicable",
        .endpoint_config = "none",
        .started_at = "2026-05-12T00:00:00Z",
        .ended_at = "2026-05-12T00:00:00Z",
        .result_status = .passed,
        .conclusion = "bench readiness report is bounded to no-actuation preparation",
        .replay_verified = true,
        .final_hash = "final",
        .commands = &.{},
        .findings = &.{},
        .approvals = &.{},
        .emergencies = &.{},
        .traceability = &.{},
        .audit_event_references = &.{},
        .artifacts_generated = &.{ "safety-report.json", "deployment-profile.yaml" },
        .limitations = &.{edge.deployment.no_flight_disclaimer},
    });
    const json = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, json, "\"test_environment\":\"bench\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"simulated_status\":\"bench preparation\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"deployment_metadata\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"runtime_assets_status\":\"active\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"vehicle_profile\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"policy_profile\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "real-flight readiness") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "regulatory certification") != null);
}

test "phase 36 red-team output can carry deployment profile context" {
    const allocator = std.testing.allocator;
    var fixture_set = try edge.redteam.runner.discover(allocator, .{ .fixture_id = "geofence-waypoint-outside-circular-denied" });
    defer fixture_set.deinit();
    var suite = try edge.redteam.runner.runSuite(allocator, fixture_set, .{
        .output_dir = ".zig-cache/phase36-redteam-profile",
        .deployment_profile = "examples/edge/deployment/profiles/source-local-fake.yaml",
        .ci = true,
    });
    defer suite.deinit();

    var buf: [32 * 1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try edge.redteam.report.writeJson(stream.writer(), suite);
    const json = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, json, "\"deployment_profile\":\"examples/edge/deployment/profiles/source-local-fake.yaml\"") != null);
}

test "phase 36 scripts templates and docs avoid real hardware defaults" {
    const allocator = std.testing.allocator;
    const smoke = try readFile(allocator, "scripts/edge-smoke-test.sh");
    defer allocator.free(smoke);
    try std.testing.expect(std.mem.indexOf(u8, smoke, "deployment doctor") != null);
    try std.testing.expect(std.mem.indexOf(u8, smoke, "bench report") != null);
    try std.testing.expect(std.mem.indexOf(u8, smoke, "redteam --ci") != null);

    const dockerfile = try readFile(allocator, "packaging/aegis-edge/Dockerfile");
    defer allocator.free(dockerfile);
    try std.testing.expect(std.mem.indexOf(u8, dockerfile, "COPY bin/aegis-edge /usr/local/bin/aegis-edge") != null);
    try std.testing.expect(std.mem.indexOf(u8, dockerfile, "COPY aegis-edge /usr/local/bin/aegis-edge") == null);
    try std.testing.expect(std.mem.indexOf(u8, dockerfile, "USER aegis") != null);
    try std.testing.expect(std.mem.indexOf(u8, dockerfile, "privileged") == null);
    try std.testing.expect(std.mem.indexOf(u8, dockerfile, "host network") == null);

    const install_script = try readFile(allocator, "scripts/install-aegis-edge.sh");
    defer allocator.free(install_script);
    try std.testing.expect(std.mem.indexOf(u8, install_script, "tar -tzf") != null);
    try std.testing.expect(std.mem.indexOf(u8, install_script, "/bin/aegis-edge") != null);
    try std.testing.expect(std.mem.indexOf(u8, install_script, "${BIN_DIR}/aegis-edge") != null);
    try std.testing.expect(std.mem.indexOf(u8, install_script, "install -m 0755") != null);

    const service = try readFile(allocator, "packaging/systemd/aegis-edge-bench.example.service");
    defer allocator.free(service);
    try std.testing.expect(std.mem.indexOf(u8, service, "example only") != null);
    try std.testing.expect(std.mem.indexOf(u8, service, "WantedBy=") == null);
    try std.testing.expect(std.mem.indexOf(u8, service, "real-flight") != null);
    try std.testing.expect(std.mem.indexOf(u8, service, "secret") == null);

    const bench_doc = try readFile(allocator, "docs/edge/hardware-bench.md");
    defer allocator.free(bench_doc);
    try std.testing.expect(std.mem.indexOf(u8, bench_doc, "not flight mode") != null);
    try std.testing.expect(std.mem.indexOf(u8, bench_doc, "motor/propeller actuation procedures") != null);
    try std.testing.expect(std.mem.indexOf(u8, bench_doc, "real-flight readiness") != null);
}

fn expectAsset(report: edge.deployment.AssetReport, path: []const u8) !void {
    for (report.checks) |check| {
        if (std.mem.eql(u8, check.path, path)) {
            try std.testing.expectEqual(edge.deployment.Status.active, check.status);
            return;
        }
    }
    return error.MissingExpectedAsset;
}
