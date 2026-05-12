const std = @import("std");
const edge_main = @import("aegis_edge_main");

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
}

fn expectFile(path: []const u8) !void {
    std.fs.cwd().access(path, .{}) catch |err| {
        std.debug.print("missing required Phase 38 file: {s}\n", .{path});
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

test "phase 38 customer-facing docs and proof files exist with bounded claims" {
    const allocator = std.testing.allocator;
    const required = [_][]const u8{
        "packages/edge/README.md",
        "docs/edge/README.md",
        "docs/edge/quickstart.md",
        "docs/edge/troubleshooting.md",
        "docs/edge/architecture.md",
        "docs/edge/capability-matrix.md",
        "docs/edge/customer-proof/README.md",
        "docs/edge/customer-proof/what-aegis-edge-proves.md",
        "docs/edge/customer-proof/what-aegis-edge-does-not-prove.md",
        "docs/edge/customer-proof/demo-script.md",
        "docs/edge/customer-proof/evidence-package.md",
        "docs/edge/customer-proof/safety-case-example.md",
        "docs/edge/customer-proof/redteam-example.md",
        "docs/edge/customer-proof/sitl-vs-flight.md",
        "docs/edge/customer-proof/buyer-faq.md",
        "docs/edge/customer-proof/technical-faq.md",
        "docs/edge/customer-proof/aegis-edge-technical-brief.md",
        "docs/edge/customer-proof/demo-recording-script.md",
        "docs/edge/customer-proof/redteam-summary.md",
    };
    for (required) |path| try expectFile(path);

    const readme = try readFile(allocator, "packages/edge/README.md");
    defer allocator.free(readme);
    try expectContains(readme, "Aegis Edge is not a flight controller");
    try expectContains(readme, "simulation/SITL/bench-preparation");
    try expectContains(readme, "fake adapter");
    try expectContains(readme, "PX4 SITL");
    try expectContains(readme, "ArduPilot SITL");
    try expectContains(readme, "customer-proof");
    try expectContains(readme, "aegis-edge demo run geofence-deny");
    try expectContains(readme, "aegis-edge docs check");

    const does_not = try readFile(allocator, "docs/edge/customer-proof/what-aegis-edge-does-not-prove.md");
    defer allocator.free(does_not);
    try expectContains(does_not, "does not prove the aircraft is safe for flight");
    try expectContains(does_not, "does not prove compliance with FAA/EASA/CAA rules");
    try expectContains(does_not, "does not prove detect-and-avoid capability");
    try expectContains(does_not, "does not prove all MAVLink commands are covered");

    const buyer_faq = try readFile(allocator, "docs/edge/customer-proof/buyer-faq.md");
    defer allocator.free(buyer_faq);
    try expectContains(buyer_faq, "Is this a flight controller?");
    try expectContains(buyer_faq, "Does this replace PX4 or ArduPilot?");
    try expectContains(buyer_faq, "Does it require sending data to a cloud service?");
    try expectNotContains(buyer_faq, "pricing");
}

test "phase 38 demo suite and customer proof artifacts exist" {
    const demos = [_]struct { dir: []const u8, marker: []const u8 }{
        .{ .dir = "01-geofence-deny", .marker = "geofence" },
        .{ .dir = "02-disable-failsafe-deny", .marker = "disable_failsafe" },
        .{ .dir = "03-emergency-land", .marker = "land" },
        .{ .dir = "04-stale-telemetry-deny", .marker = "stale" },
        .{ .dir = "05-mission-outside-geofence", .marker = "mission" },
        .{ .dir = "06-approval-expired-deny", .marker = "approval" },
        .{ .dir = "07-data-exfil-deny", .marker = "data" },
        .{ .dir = "08-health-watchdog-degraded", .marker = "health" },
        .{ .dir = "09-px4-fake-sitl-proof", .marker = "PX4" },
        .{ .dir = "10-ardupilot-fake-sitl-proof", .marker = "ArduPilot" },
    };
    for (demos) |demo| {
        const base = try std.fmt.allocPrint(std.testing.allocator, "examples/edge/demos/{s}", .{demo.dir});
        defer std.testing.allocator.free(base);
        inline for (.{ "README.md", "policy.yaml", "scenario.yaml", "expected-output.md", "run.sh", "run.ps1", "sample-safety-report.md", "sample-replay-output.md", "limitations.md" }) |name| {
            const path = try std.fs.path.join(std.testing.allocator, &.{ base, name });
            defer std.testing.allocator.free(path);
            try expectFile(path);
        }
        const readme_path = try std.fs.path.join(std.testing.allocator, &.{ base, "README.md" });
        defer std.testing.allocator.free(readme_path);
        const readme = try readFile(std.testing.allocator, readme_path);
        defer std.testing.allocator.free(readme);
        try expectContains(readme, demo.marker);
        try expectContains(readme, "No real hardware");
        try expectContains(readme, "not real-flight readiness");
    }

    const proof_files = [_][]const u8{
        "examples/edge/customer-proof/geofence-deny-safety-report.md",
        "examples/edge/customer-proof/geofence-deny-safety-report.json",
        "examples/edge/customer-proof/disable-failsafe-deny-report.md",
        "examples/edge/customer-proof/mission-outside-geofence-report.md",
        "examples/edge/customer-proof/data-exfil-deny-report.md",
        "examples/edge/customer-proof/redteam-scorecard.md",
        "examples/edge/customer-proof/redteam-scorecard.json",
        "examples/edge/customer-proof/audit-replay-example.md",
        "examples/edge/customer-proof/traceability-matrix-example.md",
        "examples/edge/customer-proof/capability-matrix.md",
        "examples/edge/customer-proof/known-limitations.md",
        "examples/edge/demos/run-all.sh",
        "scripts/edge-demo.sh",
    };
    for (proof_files) |path| try expectFile(path);
}

test "phase 38 docs check rejects overclaims and fake secret persistence" {
    var stdout_buf: [16384]u8 = undefined;
    var stderr_buf: [2048]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    const argv = [_][]const u8{ "docs", "check" };

    const code = try edge_main.run(argv[0..], stdout_stream.writer(), stderr_stream.writer());

    try std.testing.expectEqual(@as(u8, 0), code);
    try expectContains(stdout_stream.getWritten(), "Phase 38 docs check: passed");
    try expectContains(stdout_stream.getWritten(), "manual review context");
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "phase 38 demo and proof commands are deterministic and customer-safe" {
    var stdout_buf: [65536]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const list_argv = [_][]const u8{ "demo", "list" };
    try std.testing.expectEqual(@as(u8, 0), try edge_main.run(list_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try expectContains(stdout_stream.getWritten(), "geofence-deny");
    try expectContains(stdout_stream.getWritten(), "disable-failsafe-deny");
    try expectContains(stdout_stream.getWritten(), "data-exfil-deny");
    try expectContains(stdout_stream.getWritten(), "fake_adapter");
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    stdout_stream.reset();
    stderr_stream.reset();
    const geofence_argv = [_][]const u8{ "demo", "run", "geofence-deny" };
    try std.testing.expectEqual(@as(u8, 0), try edge_main.run(geofence_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try expectContains(stdout_stream.getWritten(), "Expected result: deny");
    try expectContains(stdout_stream.getWritten(), "Summary result: deny");
    try expectContains(stdout_stream.getWritten(), "Safety report:");
    try expectContains(stdout_stream.getWritten(), "Replay:");
    try expectContains(stdout_stream.getWritten(), "not real-flight readiness");
    try expectNotContains(stdout_stream.getWritten(), "fake_secret_value_phase35");
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    stdout_stream.reset();
    stderr_stream.reset();
    const all_argv = [_][]const u8{ "demo", "run", "all" };
    try std.testing.expectEqual(@as(u8, 0), try edge_main.run(all_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try expectContains(stdout_stream.getWritten(), "Agent requests waypoint outside geofence");
    try expectContains(stdout_stream.getWritten(), "Agent requests disable_failsafe");
    try expectContains(stdout_stream.getWritten(), "Agent requests LAND");
    try expectContains(stdout_stream.getWritten(), "Runtime health scenario shows stale telemetry");
    try expectContains(stdout_stream.getWritten(), "Replay verifies hash chain");
    try expectNotContains(stdout_stream.getWritten(), "fake_secret_value_phase35");
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    stdout_stream.reset();
    stderr_stream.reset();
    const proof_argv = [_][]const u8{ "proof", "generate", "--demo", "geofence-deny" };
    try std.testing.expectEqual(@as(u8, 0), try edge_main.run(proof_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try expectContains(stdout_stream.getWritten(), "Customer proof generated");
    try expectContains(stdout_stream.getWritten(), "geofence-deny-safety-report.md");
    try expectContains(stdout_stream.getWritten(), "non-certification");
    try expectNotContains(stdout_stream.getWritten(), "flight ready");
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    stdout_stream.reset();
    stderr_stream.reset();
    const data_proof_argv = [_][]const u8{ "proof", "generate", "--demo", "data-exfil-deny" };
    try std.testing.expectEqual(@as(u8, 64), try edge_main.run(data_proof_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expectEqualStrings("", stdout_stream.getWritten());
    try expectContains(stderr_stream.getWritten(), "Phase 38 CLI proof generation is only supported for 'geofence-deny'");
    try expectContains(stderr_stream.getWritten(), "data-exfil-deny-report.md");
}

test "phase 38 checked-in proof examples include provenance limitations hashes and no raw fake secrets" {
    const allocator = std.testing.allocator;
    const files = [_][]const u8{
        "examples/edge/customer-proof/geofence-deny-safety-report.md",
        "examples/edge/customer-proof/geofence-deny-safety-report.json",
        "examples/edge/customer-proof/data-exfil-deny-report.md",
        "examples/edge/customer-proof/redteam-scorecard.md",
        "examples/edge/customer-proof/audit-replay-example.md",
        "examples/edge/customer-proof/traceability-matrix-example.md",
    };
    for (files) |path| {
        const text = try readFile(allocator, path);
        defer allocator.free(text);
        try expectContains(text, "Limitations");
        try expectContains(text, "non-certification");
        try expectContains(text, "Provenance");
        try expectContains(text, "policy_hash");
        try expectNotContains(text, "fake_secret_value_phase35");
        try expectNotContains(text, "ready for real flight");
        try expectNotContains(text, "replaces autopilot");
    }
}
