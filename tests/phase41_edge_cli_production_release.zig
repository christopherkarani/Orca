const std = @import("std");
const aegis = @import("aegis");
const edge_main = @import("aegis_edge_main");

fn readFile(path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(std.testing.allocator, path, 1024 * 1024);
}

fn expectFile(path: []const u8) !void {
    std.fs.cwd().access(path, .{}) catch |err| {
        std.debug.print("missing required Phase 41 file: {s}\n", .{path});
        return err;
    };
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("expected text not found: {s}\n", .{needle});
        return error.ExpectedTextMissing;
    }
}

fn expectNotContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) != null) {
        std.debug.print("forbidden text found: {s}\n", .{needle});
        return error.ForbiddenTextFound;
    }
}

test "phase 41 CLI and Edge version commands expose production release metadata" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    try std.testing.expectEqual(@as(u8, 0), try aegis.cli.run(&.{ "version", "--json" }, stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
    var cli_json = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, stdout_stream.getWritten(), .{});
    defer cli_json.deinit();
    try std.testing.expectEqualStrings("aegis-cli", cli_json.value.object.get("product").?.string);
    try std.testing.expectEqualStrings("stable", cli_json.value.object.get("release_channel").?.string);
    try std.testing.expect(cli_json.value.object.get("target_triple") != null);
    try std.testing.expect(cli_json.value.object.get("commit") != null);
    try std.testing.expect(cli_json.value.object.get("build_date") != null);

    stdout_stream.reset();
    stderr_stream.reset();
    try std.testing.expectEqual(@as(u8, 0), try aegis.cli.run(&.{"version"}, stdout_stream.writer(), stderr_stream.writer()));
    try expectContains(stdout_stream.getWritten(), "aegis-cli");
    try expectContains(stdout_stream.getWritten(), "stable");

    stdout_stream.reset();
    stderr_stream.reset();
    try std.testing.expectEqual(@as(u8, 0), try edge_main.run(&.{ "version", "--json" }, stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
    var edge_json = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, stdout_stream.getWritten(), .{});
    defer edge_json.deinit();
    try std.testing.expectEqualStrings("aegis-edge", edge_json.value.object.get("product").?.string);
    try std.testing.expectEqualStrings("stable", edge_json.value.object.get("release_channel").?.string);
    try std.testing.expectEqualStrings("simulation-sitl-customer-evaluation", edge_json.value.object.get("safety_boundary_version").?.string);
    try expectContains(edge_json.value.object.get("safety_boundary").?.string, "not real-flight readiness");

    stdout_stream.reset();
    stderr_stream.reset();
    try std.testing.expectEqual(@as(u8, 0), try edge_main.run(&.{"version"}, stdout_stream.writer(), stderr_stream.writer()));
    try expectContains(stdout_stream.getWritten(), "aegis-edge");
    try expectContains(stdout_stream.getWritten(), "simulation/SITL/customer-evaluation");
}

test "phase 41 release artifact contract includes CLI Edge manifest checksums SBOM and signing status" {
    var name_buf: [128]u8 = undefined;
    try std.testing.expectEqualStrings("aegis-v1.1.0-darwin-amd64.tar.gz", try aegis.release.artifactName(&name_buf, "aegis", "1.1.0", .{ .os = "darwin", .arch = "amd64", .extension = "tar.gz" }));
    try std.testing.expectEqualStrings("aegis-v1.1.0-windows-amd64.zip", try aegis.release.artifactName(&name_buf, "aegis", "1.1.0", .{ .os = "windows", .arch = "amd64", .extension = "zip" }));
    try std.testing.expectEqualStrings("aegis-edge-v1.1.0-linux-arm64.tar.gz", try aegis.release.artifactName(&name_buf, "aegis-edge", "1.1.0", .{ .os = "linux", .arch = "arm64", .extension = "tar.gz" }));

    const cli_names = [_][]const u8{
        "aegis-v1.1.0-darwin-amd64.tar.gz",
        "aegis-v1.1.0-darwin-arm64.tar.gz",
        "aegis-v1.1.0-linux-amd64.tar.gz",
        "aegis-v1.1.0-linux-arm64.tar.gz",
        "aegis-v1.1.0-windows-amd64.zip",
    };
    const edge_names = [_][]const u8{
        "aegis-edge-v1.1.0-linux-amd64.tar.gz",
        "aegis-edge-v1.1.0-linux-arm64.tar.gz",
    };
    const scripts = [_][]const u8{
        "scripts/build-release.sh",
        "scripts/build-cli-release.sh",
        "scripts/build-edge-release.sh",
        "scripts/verify-release.sh",
        "scripts/release-dry-run.sh",
        "scripts/edge-release-smoke-test.sh",
        "scripts/generate-checksums.sh",
        "scripts/generate-sbom.sh",
    };
    for (scripts) |path| {
        const text = try readFile(path);
        defer std.testing.allocator.free(text);
        try expectContains(text, "set -");
        try expectContains(text, "checksum");
        try expectNotContains(text, "BEGIN PRIVATE KEY");
        try expectNotContains(text, "ghp_");
        try expectNotContains(text, "sk-");
    }
    const build_release = try readFile("scripts/build-release.sh");
    defer std.testing.allocator.free(build_release);
    for (cli_names) |name| try expectContains(build_release, name);
    for (edge_names) |name| try expectContains(build_release, name);
    try expectContains(build_release, "release-manifest.json");
    try expectContains(build_release, "README-release.md");
    try expectContains(build_release, "known-limitations.md");
    try expectContains(build_release, "ORCA_SIGNING_ENABLED");
    try expectContains(build_release, "signing_status");
    try expectContains(build_release, "simulation/SITL/bench-preparation only");

    const checksums = try readFile("scripts/generate-checksums.sh");
    defer std.testing.allocator.free(checksums);
    try expectContains(checksums, "aegis-v*");
    try expectContains(checksums, "aegis-edge-v*");
    try expectContains(checksums, "sha256sum -c");

    const sbom = try readFile("scripts/generate-sbom.sh");
    defer std.testing.allocator.free(sbom);
    try expectContains(sbom, "\"status\": \"hook-only\"");
    try expectContains(sbom, "\"runtime_assets\"");
    try expectContains(sbom, "\"build_targets\"");
}

test "phase 41 release docs reports and GitHub draft exist with explicit safety boundary" {
    const required = [_][]const u8{
        "RELEASE_NOTES.md",
        "CHANGELOG.md",
        "GITHUB_RELEASE_DRAFT.md",
        "release-checklist.md",
        "docs/install.md",
        "docs/edge/install.md",
        "docs/edge/deployment.md",
        "docs/edge/arm64.md",
        "docs/edge/release-artifacts.md",
        "docs/edge/release-notes.md",
        "docs/edge/production-release-checklist.md",
        "docs/release-tagging.md",
        "reports/production-readiness-report.md",
        "docs/edge/known-limitations.md",
        "customer_pilot/README.md",
    };
    for (required) |path| try expectFile(path);

    const release_notes = try readFile("RELEASE_NOTES.md");
    defer std.testing.allocator.free(release_notes);
    try expectContains(release_notes, "Aegis CLI");
    try expectContains(release_notes, "Aegis Edge");
    try expectContains(release_notes, "simulation/SITL/customer-evaluation");
    try expectContains(release_notes, "Aegis Edge is not a flight controller");
    try expectContains(release_notes, "not detect-and-avoid");
    try expectContains(release_notes, "not regulatory approval or certification");

    const report = try readFile("reports/production-readiness-report.md");
    defer std.testing.allocator.free(report);
    try expectContains(report, "Recommendation:");
    try expectContains(report, "ready for release");
    try expectContains(report, "Release blockers");
    try expectContains(report, "PX4 SITL support status");
    try expectContains(report, "ArduPilot SITL support status");
    try expectContains(report, "not real-flight readiness");

    const github = try readFile("GITHUB_RELEASE_DRAFT.md");
    defer std.testing.allocator.free(github);
    try expectContains(github, "checksums.txt");
    try expectContains(github, "Aegis Edge safety boundary");
    try expectContains(github, "Security disclosure");
    try expectContains(github, "Known limitations");
    try expectNotContains(github, "ready for real flight");
    try expectNotContains(github, "FAA approved");
}

test "phase 41 package manifests and install scripts are checksum-first and hardware-safe" {
    const files = [_][]const u8{
        "packaging/homebrew/aegis.rb",
        "packaging/scoop/aegis.json",
        "packaging/winget/aegis.yaml",
        "packaging/npm/package.json",
        "packaging/npm/bin/aegis.js",
        "packaging/aegis-edge/MANIFEST.template.yaml",
        "packaging/aegis-edge/Dockerfile",
        "packaging/systemd/aegis-edge.example.service",
        "scripts/install.sh",
        "scripts/install.ps1",
        "scripts/install-aegis-edge.sh",
    };
    for (files) |path| {
        const text = try readFile(path);
        defer std.testing.allocator.free(text);
        try expectContains(text, "checksum");
        try expectNotContains(text, "BEGIN PRIVATE KEY");
        try expectNotContains(text, "ghp_");
        try expectNotContains(text, "sk-");
        try expectNotContains(text, "ENABLE_TELEMETRY=1");
        try expectNotContains(text, "systemctl enable aegis-edge");
        try expectNotContains(text, "udp://0.0.0.0");
    }
    const edge_install = try readFile("scripts/install-aegis-edge.sh");
    defer std.testing.allocator.free(edge_install);
    try expectContains(edge_install, "linux-amd64");
    try expectContains(edge_install, "linux-arm64");
    try expectContains(edge_install, "unsupported");
    try expectContains(edge_install, "simulation/SITL/bench-preparation");
    try expectContains(edge_install, "aegis-edge version");
}

test "phase 41 customer pilot bundle and docs overclaim scan remain safe to ship" {
    const customer_files = [_][]const u8{
        "customer_pilot/README.md",
        "customer_pilot/pilot-overview.md",
        "customer_pilot/pilot-boundaries.md",
        "customer_pilot/pilot-intake-questionnaire.md",
        "customer_pilot/technical-discovery-questionnaire.md",
        "customer_pilot/safety-questionnaire.md",
        "customer_pilot/demo-script.md",
        "customer_pilot/templates/sow-template.md",
        "customer_pilot/templates/mutual-nda-notes.md",
        "customer_pilot/examples/sample-safety-report.md",
    };
    for (customer_files) |path| {
        const text = try readFile(path);
        defer std.testing.allocator.free(text);
        try expectContains(text, "simulation");
        try expectNotContains(text, "Acme");
        try expectNotContains(text, "BEGIN PRIVATE KEY");
        try expectNotContains(text, "real-flight ready");
        try expectNotContains(text, "certified safe");
    }
    const sow = try readFile("customer_pilot/templates/sow-template.md");
    defer std.testing.allocator.free(sow);
    try expectContains(sow, "Legal review required");

    const scanned_docs = [_][]const u8{
        "RELEASE_NOTES.md",
        "GITHUB_RELEASE_DRAFT.md",
        "docs/edge/release-notes.md",
        "docs/edge/release-artifacts.md",
        "reports/production-readiness-report.md",
        "docs/edge/production-release-checklist.md",
    };
    const banned_positive = [_][]const u8{
        "certified safe",
        "FAA approved",
        "EASA approved",
        "flight certified",
        "guarantees safety",
        "replaces autopilot",
        "ready for real flight",
        "safe for BVLOS",
        "prevents all unsafe actions",
        "works with all MAVLink commands",
        "production flight-ready",
        "airworthy",
        "certified autonomy",
        "approved for flight",
    };
    for (scanned_docs) |path| {
        const text = try readFile(path);
        defer std.testing.allocator.free(text);
        for (banned_positive) |phrase| try expectNotContains(text, phrase);
        try expectContains(text, "not real-flight readiness");
    }
}
