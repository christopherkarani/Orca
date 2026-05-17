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
    try std.testing.expectEqualStrings("orca", cli_json.value.object.get("product").?.string);
    try std.testing.expectEqualStrings("stable", cli_json.value.object.get("release_channel").?.string);
    try std.testing.expect(cli_json.value.object.get("target_triple") != null);
    try std.testing.expect(cli_json.value.object.get("commit") != null);
    try std.testing.expect(cli_json.value.object.get("build_date") != null);

    stdout_stream.reset();
    stderr_stream.reset();
    try std.testing.expectEqual(@as(u8, 0), try aegis.cli.run(&.{"version"}, stdout_stream.writer(), stderr_stream.writer()));
    try expectContains(stdout_stream.getWritten(), "orca");
    try expectContains(stdout_stream.getWritten(), "stable");

    stdout_stream.reset();
    stderr_stream.reset();
    try std.testing.expectEqual(@as(u8, 0), try edge_main.run(&.{ "version", "--json" }, stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
    var edge_json = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, stdout_stream.getWritten(), .{});
    defer edge_json.deinit();
    try std.testing.expectEqualStrings("edge", edge_json.value.object.get("product").?.string);
    try std.testing.expectEqualStrings("stable", edge_json.value.object.get("release_channel").?.string);
    try std.testing.expectEqualStrings("simulation-sitl-customer-evaluation", edge_json.value.object.get("safety_boundary_version").?.string);
    try expectContains(edge_json.value.object.get("safety_boundary").?.string, "not real-flight readiness");

    stdout_stream.reset();
    stderr_stream.reset();
    try std.testing.expectEqual(@as(u8, 0), try edge_main.run(&.{"version"}, stdout_stream.writer(), stderr_stream.writer()));
    try expectContains(stdout_stream.getWritten(), "edge");
    try expectContains(stdout_stream.getWritten(), "simulation/SITL/customer-evaluation");
}

test "phase 41 release artifact contract includes CLI Edge manifest checksums SBOM and signing status" {
    var name_buf: [128]u8 = undefined;
    try std.testing.expectEqualStrings("orca-v1.1.0-darwin-amd64.tar.gz", try aegis.release.artifactName(&name_buf, "orca", "1.1.0", .{ .os = "darwin", .arch = "amd64", .extension = "tar.gz" }));
    try std.testing.expectEqualStrings("orca-v1.1.0-windows-amd64.zip", try aegis.release.artifactName(&name_buf, "orca", "1.1.0", .{ .os = "windows", .arch = "amd64", .extension = "zip" }));
    try std.testing.expectEqualStrings("edge-v1.1.0-linux-arm64.tar.gz", try aegis.release.artifactName(&name_buf, "edge", "1.1.0", .{ .os = "linux", .arch = "arm64", .extension = "tar.gz" }));

    const cli_names = [_][]const u8{
        "orca-v1.1.0-darwin-amd64.tar.gz",
        "orca-v1.1.0-darwin-arm64.tar.gz",
        "orca-v1.1.0-linux-amd64.tar.gz",
        "orca-v1.1.0-linux-arm64.tar.gz",
        "orca-v1.1.0-windows-amd64.zip",
    };
    const edge_names = [_][]const u8{
        "edge-v1.1.0-linux-amd64.tar.gz",
        "edge-v1.1.0-linux-arm64.tar.gz",
    };
    const scripts = [_][]const u8{
        "scripts/build-release.sh",
        "scripts/build-cli-release.sh",
        "scripts/build-edge-release.sh",
        "scripts/verify-release.sh",
        "scripts/release-dry-run.sh",
        "scripts/edge-release-smoke-test.sh",
        "scripts/update-homebrew-formula.sh",
        "scripts/render-package-manifests.sh",
        "scripts/generate-checksums.sh",
        "scripts/generate-sbom.sh",
    };
    for (scripts) |path| {
        const text = try readFile(path);
        defer std.testing.allocator.free(text);
        try expectContains(text, "set -");
        try std.testing.expect(std.mem.indexOf(u8, text, "checksum") != null or std.mem.indexOf(u8, text, "sha256") != null);
        try expectNotContains(text, "BEGIN PRIVATE KEY");
        try expectNotContains(text, "ghp_");
        try expectNotContains(text, "sk-");
    }
    const build_release = try readFile("scripts/build-release.sh");
    defer std.testing.allocator.free(build_release);
    for (cli_names) |name| try expectContains(build_release, name);
    for (edge_names) |name| try expectContains(build_release, name);
    try expectNotContains(build_release, "aegis-v");
    try expectNotContains(build_release, "aegis-edge-v");
    try expectNotContains(build_release, "orca-edge");
    try expectContains(build_release, "release-manifest.json");
    try expectContains(build_release, "README-release.md");
    try expectContains(build_release, "known-limitations.md");
    try expectContains(build_release, "ORCA_SIGNING_ENABLED");
    try expectContains(build_release, "signing_status");
    try expectContains(build_release, "simulation/SITL/bench-preparation only");
    try expectContains(build_release, "node_modules");
    try expectContains(build_release, "ORCA_DIST_DIR=\"$DIST_DIR\" ./scripts/render-package-manifests.sh");
    try expectContains(build_release, "zig build install-orca");
    try std.testing.expect(std.mem.indexOf(u8, build_release, "./scripts/generate-checksums.sh") != null);
    try std.testing.expect(std.mem.indexOf(u8, build_release, "ORCA_SIGNING_ENABLED") != null);
    try std.testing.expect(std.mem.indexOf(u8, build_release, "ORCA_DIST_DIR=\"$DIST_DIR\" ./scripts/render-package-manifests.sh") != null);
    try std.testing.expect(std.mem.indexOf(u8, build_release, "ORCA_SIGNING_ENABLED").? < std.mem.indexOf(u8, build_release, "./scripts/generate-checksums.sh").?);
    try std.testing.expect(std.mem.indexOf(u8, build_release, "./scripts/generate-checksums.sh").? < std.mem.indexOf(u8, build_release, "./scripts/render-package-manifests.sh").?);
    try expectContains(build_release, "rm -rf \"$DIST_DIR/work\"");

    const verify_release = try readFile("scripts/verify-release.sh");
    defer std.testing.allocator.free(verify_release);
    try expectContains(verify_release, "products_included");
    try expectContains(verify_release, "require_edge_artifacts");
    try expectContains(verify_release, "require_orca_archive_binary");
    try expectContains(verify_release, "require_orca_archive_excludes");
    try expectContains(verify_release, "disallowed_orca_archive_path");
    try expectContains(verify_release, "require_package_hashes");
    try expectContains(verify_release, "require_manifest_hash_for_artifact");
    try expectContains(verify_release, "artifact_package_key");
    try expectContains(verify_release, "missing bin/$binary");
    try expectContains(verify_release, "missing checksum entry");
    try expectContains(verify_release, "release-manifest.json");
    try expectContains(verify_release, "\\\"name\\\":\\\"");

    const build_release_ps1 = try readFile("scripts/build-release.ps1");
    defer std.testing.allocator.free(build_release_ps1);
    try expectContains(build_release_ps1, "orca-v$Version-$($target.Os)-$($target.Arch).$($target.Ext)");
    try expectContains(build_release_ps1, "ArchiveOnly");
    try expectContains(build_release_ps1, "does not produce release-manifest.json/package-manifests");
    try expectNotContains(build_release_ps1, "bin/$edgeBin");
    try expectNotContains(build_release_ps1, "Copy-Item docs, policies, schemas, fixtures, examples, packages, packaging, scripts");
    try std.testing.expect(std.mem.indexOf(u8, build_release_ps1, "ORCA_SIGNING_ENABLED").? < std.mem.indexOf(u8, build_release_ps1, "Get-FileHash -Algorithm SHA256").?);

    const checksums = try readFile("scripts/generate-checksums.sh");
    defer std.testing.allocator.free(checksums);
    try expectContains(checksums, "orca-v*");
    try expectContains(checksums, "edge-v*");
    try expectNotContains(checksums, "aegis-v*");
    try expectNotContains(checksums, "aegis-edge-v*");
    try expectNotContains(checksums, "orca-edge");
    try expectContains(checksums, "sha256sum -c");

    const sbom = try readFile("scripts/generate-sbom.sh");
    defer std.testing.allocator.free(sbom);
    try expectContains(sbom, "\"status\": \"hook-only\"");
    try expectContains(sbom, "\"runtime_assets\"");
    try expectContains(sbom, "\"build_targets\"");
    try expectContains(sbom, "ORCA_RELEASE_PRODUCT");
    try expectContains(sbom, "orca-core");
    try expectContains(sbom, "orca-core-edge");

    const package_manifests = try readFile("scripts/render-package-manifests.sh");
    defer std.testing.allocator.free(package_manifests);
    try expectContains(package_manifests, "package-manifests");
    try expectContains(package_manifests, "packaging/npm/package.json");
    try expectContains(package_manifests, "packaging/scoop/orca.json");
    try expectContains(package_manifests, "packaging/winget/orca.yaml");
    try expectContains(package_manifests, "packaging/homebrew/Formula/orca.rb");
    try expectContains(package_manifests, "checksums.txt");
    try expectContains(package_manifests, "missing windows amd64 checksum");
    try expectContains(package_manifests, "PLACEHOLDER");

    const build_zig = try readFile("build.zig");
    defer std.testing.allocator.free(build_zig);
    try expectContains(build_zig, "install-orca");
    try expectContains(build_zig, "Install Orca CLI only");

    const plugin_packager = try readFile("scripts/package-plugins.sh");
    defer std.testing.allocator.free(plugin_packager);
    try expectContains(plugin_packager, "Secret scan found ${SCAN_ISSUES} potential issues. Failing release packaging.");
    try expectContains(plugin_packager, "exit 1");

    const plugin_packager_ps1 = try readFile("scripts/package-plugins.ps1");
    defer std.testing.allocator.free(plugin_packager_ps1);
    try expectContains(plugin_packager_ps1, "$OPENCODE_PLUGIN_DIR");
    try expectContains(plugin_packager_ps1, "orca-opencode-plugin-v${VERSION}.zip");
    try expectContains(plugin_packager_ps1, "Secret scan found $SCAN_ISSUES potential issues. Failing release packaging.");
    try expectContains(plugin_packager_ps1, "throw \"Secret scan found");

    const npm_plugin_packager = try readFile("scripts/package-npm-plugins.sh");
    defer std.testing.allocator.free(npm_plugin_packager);
    try expectContains(npm_plugin_packager, "Total secret scan issues: ${TOTAL_ISSUES}. Failing release packaging.");
    try expectContains(npm_plugin_packager, "exit 1");

    const release_workflow = try readFile(".github/workflows/release.yml");
    defer std.testing.allocator.free(release_workflow);
    try expectContains(release_workflow, "orca-plugin-checksums.txt");
    try expectNotContains(release_workflow, "aegis-plugin-checksums.txt");
    try expectContains(release_workflow, "ORCA_SIGNING_ENABLED");
    try expectNotContains(release_workflow, "Optional signing hook");

    const homebrew_formula = try readFile("packaging/homebrew/Formula/orca.rb");
    defer std.testing.allocator.free(homebrew_formula);
    try expectContains(homebrew_formula, "manifest status: exists");
    try expectContains(homebrew_formula, "(exists)");
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
    try expectContains(release_notes, "Orca");
    try expectContains(release_notes, "Edge");
    try expectContains(release_notes, "simulation/SITL/customer-evaluation");
    try expectContains(release_notes, "Edge is not a flight controller");
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
    try expectContains(github, "Edge safety boundary");
    try expectContains(github, "Security disclosure");
    try expectContains(github, "Known limitations");
    try expectNotContains(github, "ready for real flight");
    try expectNotContains(github, "FAA approved");
}

test "phase 41 package manifests and install scripts are checksum-first and hardware-safe" {
    const files = [_][]const u8{
        "packaging/homebrew/Formula/orca.rb",
        "packaging/homebrew/README.md",
        "packaging/scoop/orca.json",
        "packaging/winget/orca.yaml",
        "packaging/npm/package.json",
        "packaging/npm/bin/orca.js",
        "packaging/edge/MANIFEST.template.yaml",
        "packaging/edge/Dockerfile",
        "packaging/systemd/edge.example.service",
        "scripts/install.sh",
        "scripts/install.ps1",
        "scripts/install-edge.sh",
    };
    for (files) |path| {
        const text = try readFile(path);
        defer std.testing.allocator.free(text);
        try std.testing.expect(std.mem.indexOf(u8, text, "checksum") != null or std.mem.indexOf(u8, text, "sha256") != null);
        try expectNotContains(text, "BEGIN PRIVATE KEY");
        try expectNotContains(text, "ghp_");
        try expectNotContains(text, "sk-");
        try expectNotContains(text, "ENABLE_TELEMETRY=1");
        try expectNotContains(text, "systemctl enable edge");
        try expectNotContains(text, "udp://0.0.0.0");
    }
    const edge_install = try readFile("scripts/install-edge.sh");
    defer std.testing.allocator.free(edge_install);
    try expectContains(edge_install, "linux-amd64");
    try expectContains(edge_install, "linux-arm64");
    try expectContains(edge_install, "unsupported");
    try expectContains(edge_install, "simulation/SITL/bench-preparation");
    try expectContains(edge_install, "edge version");

    const homebrew_formula = try readFile("packaging/homebrew/Formula/orca.rb");
    defer std.testing.allocator.free(homebrew_formula);
    try expectContains(homebrew_formula, "class Orca < Formula");
    try expectContains(homebrew_formula, "christopherkarani/Orca");
    try expectContains(homebrew_formula, "orca-v#{version}-darwin-arm64.tar.gz");
    try expectContains(homebrew_formula, "orca-v#{version}-linux-amd64.tar.gz");
    try expectContains(homebrew_formula, "sha256");
    try expectContains(homebrew_formula, "ORCA_RESOURCE_ROOT");
    try expectContains(homebrew_formula, "plugin manifest hermes");
    try expectNotContains(homebrew_formula, "BEGIN PRIVATE KEY");
    try expectNotContains(homebrew_formula, "ghp_");
    try expectNotContains(homebrew_formula, "sk-");

    const npm_launcher = try readFile("packaging/npm/bin/orca.js");
    defer std.testing.allocator.free(npm_launcher);
    const npm_package = try readFile("packaging/npm/package.json");
    defer std.testing.allocator.free(npm_package);
    try expectContains(npm_package, "\"supportedTargets\"");
    try expectContains(npm_package, "\"windows-amd64\"");
    try expectNotContains(npm_package, "\"windows-arm64\"");
    try expectContains(npm_launcher, "https.get");
    try expectContains(npm_launcher, "sha256");
    try expectContains(npm_launcher, "tar");
    try expectContains(npm_launcher, "Expand-Archive");
    try expectContains(npm_launcher, "orca.checksums");
    try expectContains(npm_launcher, "supported Orca npm targets");
    try expectContains(npm_launcher, "unsupported Orca npm target");
    try expectContains(npm_launcher, "resourceDir");
    try expectContains(npm_launcher, "ORCA_RESOURCE_ROOT");
    try expectContains(npm_launcher, "env");
    try expectNotContains(npm_launcher, "Binary download is intentionally disabled");

    const install_sh = try readFile("scripts/install.sh");
    defer std.testing.allocator.free(install_sh);
    try expectContains(install_sh, "mktemp -d");
    try expectContains(install_sh, "is_existing_orca");
    try expectContains(install_sh, "grep -Eqi");
    try expectContains(install_sh, "\"product\"[[:space:]]*:[[:space:]]*\"orca\"|^orca([[:space:]]|$)");
    try expectNotContains(install_sh, "orca-install-$$");
    try expectNotContains(install_sh, "if \"$destination\" version >/dev/null 2>&1; then");

    const install_ps1 = try readFile("scripts/install.ps1");
    defer std.testing.allocator.free(install_ps1);
    try expectContains(install_ps1, "[System.Guid]::NewGuid()");
    try expectContains(install_ps1, "Test-ExistingOrca");
    try expectContains(install_ps1, "-match");
    try expectContains(install_ps1, "\"product\"\\s*:\\s*\"orca\"|^orca(\\s|$)");
    try expectNotContains(install_ps1, "orca-install-$PID");
    try expectNotContains(install_ps1, "New-Item -ItemType Directory -Force -Path $tempDir");
    try expectNotContains(install_ps1, "& $destination version *> $null");
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
