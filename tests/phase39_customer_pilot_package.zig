const std = @import("std");
const edge_main = @import("aegis_edge_main");

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
}

fn expectFile(path: []const u8) !void {
    std.fs.cwd().access(path, .{}) catch |err| {
        std.debug.print("missing required Phase 39 file: {s}\n", .{path});
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

const required_docs = [_][]const u8{
    "customer_pilot/README.md",
    "customer_pilot/pilot-overview.md",
    "customer_pilot/pilot-boundaries.md",
    "customer_pilot/pilot-success-criteria.md",
    "customer_pilot/pilot-timeline.md",
    "customer_pilot/pilot-deliverables.md",
    "customer_pilot/pilot-intake-questionnaire.md",
    "customer_pilot/technical-discovery-questionnaire.md",
    "customer_pilot/safety-review-questionnaire.md",
    "customer_pilot/integration-readiness-checklist.md",
    "customer_pilot/simulation-sitl-evaluation-plan.md",
    "customer_pilot/customer-demo-script.md",
    "customer_pilot/safety-report-template.md",
    "customer_pilot/evidence-bundle-template.md",
    "customer_pilot/redteam-report-template.md",
    "customer_pilot/pilot-final-report-template.md",
    "customer_pilot/known-limitations.md",
    "customer_pilot/faq.md",
};

const required_templates = [_][]const u8{
    "customer_pilot/templates/pilot-sow-template.md",
    "customer_pilot/templates/mutual-nda-notes.md",
    "customer_pilot/templates/security-review-response-template.md",
    "customer_pilot/templates/customer-email-followup.md",
    "customer_pilot/templates/design-partner-proposal.md",
};

const required_examples = [_][]const u8{
    "customer_pilot/examples/sample-pilot-report.md",
    "customer_pilot/examples/sample-safety-report.md",
    "customer_pilot/examples/sample-redteam-report.md",
    "customer_pilot/examples/sample-evidence-bundle-index.md",
};

test "phase 39 customer pilot docs templates and sample reports exist" {
    for (required_docs) |path| try expectFile(path);
    for (required_templates) |path| try expectFile(path);
    for (required_examples) |path| try expectFile(path);
}

test "phase 39 customer pilot materials keep strong safety and legal boundaries" {
    const allocator = std.testing.allocator;

    const overview = try readFile(allocator, "customer_pilot/pilot-overview.md");
    defer allocator.free(overview);
    try expectContains(overview, "simulation/SITL/bench-preparation safety-policy runtime");
    try expectContains(overview, "fake adapter");
    try expectContains(overview, "PX4 SITL");
    try expectContains(overview, "ArduPilot SITL");
    try expectContains(overview, "real flight");
    try expectContains(overview, "limitations are documented");

    const boundaries = try readFile(allocator, "customer_pilot/pilot-boundaries.md");
    defer allocator.free(boundaries);
    try expectContains(boundaries, "No real-flight deployment");
    try expectContains(boundaries, "No live aircraft control");
    try expectContains(boundaries, "No certification claim");
    try expectContains(boundaries, "No detect-and-avoid claim");
    try expectContains(boundaries, "No autopilot replacement claim");
    try expectContains(boundaries, "No safety guarantee");
    try expectContains(boundaries, "No real secrets required");
    try expectContains(boundaries, "Fake adapter evidence means");
    try expectContains(boundaries, "SITL evidence means");
    try expectContains(boundaries, "Bench-preparation evidence means");

    const success = try readFile(allocator, "customer_pilot/pilot-success-criteria.md");
    defer allocator.free(success);
    try expectContains(success, "at least one unsafe command is denied");
    try expectContains(success, "audit/replay hash verification succeeds");
    try expectContains(success, "Non-success criteria");
    try expectContains(success, "full detect-and-avoid");

    const demo = try readFile(allocator, "customer_pilot/customer-demo-script.md");
    defer allocator.free(demo);
    try expectContains(demo, "What not to say");
    try expectContains(demo, "demo 1: geofence deny");
    try expectContains(demo, "demo 8: red-team scorecard");
    try expectContains(demo, "Artifact generated");

    const sow = try readFile(allocator, "customer_pilot/templates/pilot-sow-template.md");
    defer allocator.free(sow);
    try expectContains(sow, "DRAFT TEMPLATE ONLY");
    try expectContains(sow, "NOT LEGAL ADVICE");
    try expectContains(sow, "REQUIRES LEGAL REVIEW");
    try expectContains(sow, "no real-flight clause");
    try expectContains(sow, "no certification clause");

    const security = try readFile(allocator, "customer_pilot/templates/security-review-response-template.md");
    defer allocator.free(security);
    try expectContains(security, "Does Edge require cloud connectivity?");
    try expectContains(security, "Does it send telemetry externally?");
    try expectContains(security, "How are secrets redacted?");
    try expectContains(security, "How are vulnerability reports handled?");

    const safety_template = try readFile(allocator, "customer_pilot/safety-report-template.md");
    defer allocator.free(safety_template);
    try expectContains(safety_template, "Non-certification disclaimer");
    try expectContains(safety_template, "audit/replay verification");
}

test "phase 39 examples use fake data limitations and no secret or overclaim patterns" {
    const allocator = std.testing.allocator;
    const all_files = required_docs ++ required_templates ++ required_examples;
    const forbidden = [_][]const u8{
        "certified safe",
        "FAA approved",
        "flight certified",
        "guarantees safety",
        "ready for real flight",
        "safe for BVLOS",
        "prevents all unsafe actions",
        "works with all MAVLink commands",
        "AKIA",
        "BEGIN PRIVATE KEY",
        "ghp_",
        "xoxb-",
        "sk_live",
        "fake_secret_value_phase35",
    };

    for (all_files) |path| {
        const text = try readFile(allocator, path);
        defer allocator.free(text);
        for (forbidden) |phrase| try expectNotContains(text, phrase);
    }

    for (required_examples) |path| {
        const text = try readFile(allocator, path);
        defer allocator.free(text);
        try expectContains(text, "Example data only");
        try expectContains(text, "Limitations");
        try expectContains(text, "non-certification");
        try expectContains(text, "not real flight");
        try expectContains(text, "fake adapter");
    }
}

test "phase 39 docs are linked from edge readmes" {
    const allocator = std.testing.allocator;

    const docs_readme = try readFile(allocator, "docs/edge/README.md");
    defer allocator.free(docs_readme);
    try expectContains(docs_readme, "For design-partner evaluation, see");
    try expectContains(docs_readme, "customer_pilot/README.md");
    try expectContains(docs_readme, "no real-flight");

    const package_readme = try readFile(allocator, "packages/edge/README.md");
    defer allocator.free(package_readme);
    try expectContains(package_readme, "For design-partner evaluation, see");
    try expectContains(package_readme, "customer_pilot/README.md");
    try expectContains(package_readme, "no real-flight");
}

test "phase 39 pilot CLI helpers are local only and bounded" {
    var stdout_buf: [65536]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const checklist_argv = [_][]const u8{ "pilot", "checklist" };
    try std.testing.expectEqual(@as(u8, 0), try edge_main.run(checklist_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try expectContains(stdout_stream.getWritten(), "customer_pilot/integration-readiness-checklist.md");
    try expectContains(stdout_stream.getWritten(), "No real hardware");
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    stdout_stream.reset();
    stderr_stream.reset();
    const package_argv = [_][]const u8{ "pilot", "package" };
    try std.testing.expectEqual(@as(u8, 0), try edge_main.run(package_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try expectContains(stdout_stream.getWritten(), ".edge/pilot-package/index.md");
    try expectContains(stdout_stream.getWritten(), "local customer-evaluation package");
    try expectContains(stdout_stream.getWritten(), "no external network");
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
    try expectFile(".edge/pilot-package/index.md");

    stdout_stream.reset();
    stderr_stream.reset();
    const demo_argv = [_][]const u8{ "pilot", "demo" };
    try std.testing.expectEqual(@as(u8, 0), try edge_main.run(demo_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try expectContains(stdout_stream.getWritten(), "demo 1: geofence deny");
    try expectContains(stdout_stream.getWritten(), "What not to say");
    try expectContains(stdout_stream.getWritten(), "not real flight");
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "phase 39 profile-scoped redteam rejects missing deployment profile before reporting success" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const argv = [_][]const u8{
        "redteam",
        "--deployment-profile",
        "/no/such/profile.yaml",
        "--category",
        "health",
        "--ci",
    };

    try std.testing.expectEqual(@as(u8, 65), try edge_main.run(argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expectEqualStrings("", stdout_stream.getWritten());
    try expectContains(stderr_stream.getWritten(), "deployment profile");
}

test "phase 39 profile-scoped redteam rejects deployment profile that is not active" {
    try std.fs.cwd().makePath(".zig-cache/phase39-customer-pilot");
    const profile_path = ".zig-cache/phase39-customer-pilot/inactive-profile.yaml";
    var file = try std.fs.cwd().createFile(profile_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(
        \\id: inactive-redteam-profile
        \\target_arch: linux-amd64
        \\os: linux
        \\mode: source
        \\environment: fake_adapter
        \\policy_path: examples/edge/no-such-policy.yaml
        \\scenario_path: examples/edge/safety/scenarios/geofence-deny.yaml
        \\network_mode: offline
        \\
    );

    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const argv = [_][]const u8{
        "redteam",
        "--deployment-profile",
        profile_path,
        "--category",
        "health",
        "--ci",
    };

    try std.testing.expectEqual(@as(u8, 65), try edge_main.run(argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expectEqualStrings("", stdout_stream.getWritten());
    try expectContains(stderr_stream.getWritten(), "deployment profile check did not return active");
}
