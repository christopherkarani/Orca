const std = @import("std");
const core = @import("aegis_core");

const runner = @import("runner.zig");
const scorecard = @import("scorecard.zig");
const safety_report = @import("../audit/safety_report.zig");

pub fn writeHuman(writer: anytype, suite: runner.SuiteResult) !void {
    const totals = suite.totals();
    try writer.writeAll("Aegis Edge Red-Team Score\n\n");
    for (scorecard.ordered_categories) |category| {
        const category_total = scorecard.summarizeCategory(runner.FixtureResult, category, suite.results);
        if (category_total.fixtures == 0) continue;
        try writer.print("{s}:\n", .{category.display()});
        try writer.print("  {d}/{d} passed", .{ category_total.passed, category_total.fixtures });
        if (category_total.skipped > 0) try writer.print(" ({d} skipped)", .{category_total.skipped});
        if (category_total.unsupported > 0) try writer.print(" ({d} unsupported)", .{category_total.unsupported});
        if (category_total.inconclusive > 0) try writer.print(" ({d} inconclusive)", .{category_total.inconclusive});
        if (category_total.failed > 0) try writer.print(" ({d} failed)", .{category_total.failed});
        try writer.writeAll("\n\n");
    }
    try writer.print(
        \\Overall:
        \\  {d}/{d} required fake/simulation fixtures passed
        \\  {d}%
        \\  skipped/unsupported/inconclusive are not counted as pass
        \\  run id: {s}
        \\  artifacts: {s}
        \\
    , .{ totals.passed, totals.required, totals.percent(), suite.run_id, suite.output_dir });
    try writer.writeAll("Limitations: simulation/SITL/bench-preparation/customer-evaluation evidence only; no real-flight readiness, certification, detect-and-avoid, or autopilot-replacement claim.\n");
}

pub fn writeJson(writer: anytype, suite: runner.SuiteResult) !void {
    const totals = suite.totals();
    try writer.writeAll("{\"version\":1");
    try stringFieldRaw(writer, "run_id", suite.run_id, true);
    try stringFieldRaw(writer, "timestamp", suite.run_id, true);
    try stringFieldRaw(writer, "audit_session_id", suite.session_id, true);
    try stringField(writer, "output_dir", suite.output_dir, true);
    try writer.writeAll(",\"totals\":");
    try writeTotals(writer, totals);
    try writer.writeAll(",\"fixtures\":[");
    for (suite.results, 0..) |result, index| {
        if (index > 0) try writer.writeByte(',');
        try writeFixture(writer, result);
    }
    try writer.writeAll("],\"limitations\":[");
    try jsonString(writer, "Aegis Edge red-team evidence is simulation, fake-adapter, SITL, bench-preparation, or customer-evaluation evidence only.");
    try writer.writeByte(',');
    try jsonString(writer, "Skipped, unsupported, and inconclusive fixtures are not counted as passed.");
    try writer.writeByte(',');
    try jsonString(writer, safety_report.non_certification_disclaimer);
    try writer.writeAll("]}\n");
}

pub fn writeArtifacts(allocator: std.mem.Allocator, suite: runner.SuiteResult, include_safety_case: bool) !void {
    try std.fs.cwd().makePath(suite.output_dir);
    const score_md = try std.fs.path.join(allocator, &.{ suite.output_dir, "scorecard.md" });
    defer allocator.free(score_md);
    const score_json = try std.fs.path.join(allocator, &.{ suite.output_dir, "scorecard.json" });
    defer allocator.free(score_json);
    try writeFile(score_md, suite, writeHuman);
    try writeFile(score_json, suite, writeJson);
    if (include_safety_case) {
        const report_md = try std.fs.path.join(allocator, &.{ suite.output_dir, "safety-report.md" });
        defer allocator.free(report_md);
        const report_json = try std.fs.path.join(allocator, &.{ suite.output_dir, "safety-report.json" });
        defer allocator.free(report_json);
        try writeSafetyCaseMarkdownFile(report_md, suite);
        try writeSafetyCaseJsonFile(report_json, suite);
    }
}

fn writeFile(path: []const u8, suite: runner.SuiteResult, comptime func: anytype) !void {
    try ensureParent(path);
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    var buffer: [8192]u8 = undefined;
    var writer = file.writer(&buffer);
    try func(&writer.interface, suite);
    try writer.interface.flush();
    try file.sync();
}

fn writeSafetyCaseMarkdownFile(path: []const u8, suite: runner.SuiteResult) !void {
    try ensureParent(path);
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    var buffer: [8192]u8 = undefined;
    var writer = file.writer(&buffer);
    try writer.interface.print(
        \\# Aegis Edge Red-Team Safety Evidence
        \\
        \\{s}
        \\
        \\## Summary
        \\
        \\| Field | Value |
        \\|---|---|
        \\| Run ID | `{s}` |
        \\| Audit session | `{s}` |
        \\| Result | `{d}/{d} required fixtures passed` |
        \\| Real flight | Not performed |
        \\| Certification | Not claimed |
        \\
        \\## Fixture Results
        \\
        \\| Fixture | Category | Environment | Result | Decision |
        \\|---|---|---|---|---|
    , .{ safety_report.non_certification_disclaimer, suite.run_id, suite.session_id, suite.totals().passed, suite.totals().required });
    for (suite.results) |result| {
        try writer.interface.print("| {s} | {s} | {s} | {s} | {s} |\n", .{
            result.id,
            result.category.slug(),
            result.environment.toString(),
            result.status.toString(),
            if (result.actual_decision) |decision| decision.toString() else "none",
        });
    }
    try writer.interface.writeAll(
        \\
        \\## Limitations
        \\
        \\- Aegis Edge is not a flight controller, autopilot replacement, detect-and-avoid system, regulatory approval, or safety certification.
        \\- Fake-adapter success is not PX4 or ArduPilot SITL success.
        \\- SITL success is not real-flight readiness.
        \\- Skipped, unsupported, and inconclusive fixtures are not counted as passed.
        \\- No real hardware or external network is required by normal red-team tests.
        \\
    );
    try writer.interface.flush();
    try file.sync();
}

fn writeSafetyCaseJsonFile(path: []const u8, suite: runner.SuiteResult) !void {
    try ensureParent(path);
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    var buffer: [8192]u8 = undefined;
    var writer = file.writer(&buffer);
    try writer.interface.writeAll("{\"version\":1");
    try stringFieldRaw(&writer.interface, "run_id", suite.run_id, true);
    try stringFieldRaw(&writer.interface, "audit_session_id", suite.session_id, true);
    try stringField(&writer.interface, "non_certification_disclaimer", safety_report.non_certification_disclaimer, true);
    try writer.interface.writeAll(",\"fixture_results\":[");
    for (suite.results, 0..) |result, index| {
        if (index > 0) try writer.interface.writeByte(',');
        try writeFixture(&writer.interface, result);
    }
    try writer.interface.writeAll("],\"limitations\":[");
    try jsonString(&writer.interface, "No real flight was performed or claimed.");
    try writer.interface.writeByte(',');
    try jsonString(&writer.interface, "Aegis Edge is not a flight controller, autopilot replacement, detect-and-avoid system, regulatory approval, or certification.");
    try writer.interface.writeByte(',');
    try jsonString(&writer.interface, "Skipped, unsupported, and inconclusive fixtures are not counted as passed.");
    try writer.interface.writeAll("]}\n");
    try writer.interface.flush();
    try file.sync();
}

fn writeTotals(writer: anytype, totals: scorecard.Totals) !void {
    try writer.print("{{\"fixtures\":{d},\"required\":{d},\"passed\":{d},\"failed\":{d},\"skipped\":{d},\"unsupported\":{d},\"inconclusive\":{d},\"points_possible\":{d},\"points_earned\":{d},\"percent\":{d}}}", .{
        totals.fixtures,
        totals.required,
        totals.passed,
        totals.failed,
        totals.skipped,
        totals.unsupported,
        totals.inconclusive,
        totals.points_possible,
        totals.points_earned,
        totals.percent(),
    });
}

fn writeFixture(writer: anytype, result: runner.FixtureResult) !void {
    try writer.writeByte('{');
    try stringFieldRaw(writer, "fixture_id", result.id, false);
    try stringField(writer, "name", result.name, true);
    try stringFieldRaw(writer, "category", result.category.slug(), true);
    try stringFieldRaw(writer, "environment", result.environment.toString(), true);
    try stringFieldRaw(writer, "result", result.status.toString(), true);
    try writer.print(",\"required\":{},\"points_possible\":{d},\"points_earned\":{d}", .{ result.required, result.points_possible, result.points_earned });
    try stringFieldRaw(writer, "expected_decision", result.expected_decision.toString(), true);
    try writer.writeAll(",\"actual_decision\":");
    if (result.actual_decision) |decision| try jsonStringRaw(writer, decision.toString()) else try writer.writeAll("null");
    try stringArrayField(writer, "expected_findings", result.expected_findings, true);
    try stringArrayField(writer, "actual_findings", result.actual_findings, true);
    try stringArrayField(writer, "expected_events", result.expected_events, true);
    try stringArrayField(writer, "actual_events", result.actual_events, true);
    try writer.print(",\"forbidden_log_check_passed\":{}", .{result.forbidden_log_check_passed});
    try stringFieldRaw(writer, "audit_session_id", result.audit_session_id, true);
    try writer.writeAll(",\"safety_case_report_path\":");
    if (result.safety_case_report_path) |path| try jsonString(writer, path) else try writer.writeAll("null");
    try writer.writeAll(",\"skip_unsupported_reason\":");
    if (result.reason) |reason| try jsonString(writer, reason) else try writer.writeAll("null");
    try stringArrayField(writer, "limitations", result.limitations, true);
    try writer.writeByte('}');
}

fn stringField(writer: anytype, name: []const u8, value: []const u8, comma: bool) !void {
    if (comma) try writer.writeByte(',');
    try core.util.writeJsonString(writer, name);
    try writer.writeByte(':');
    try jsonString(writer, value);
}

fn stringFieldRaw(writer: anytype, name: []const u8, value: []const u8, comma: bool) !void {
    if (comma) try writer.writeByte(',');
    try core.util.writeJsonString(writer, name);
    try writer.writeByte(':');
    try jsonStringRaw(writer, value);
}

fn stringArrayField(writer: anytype, name: []const u8, values: []const []const u8, comma: bool) !void {
    if (comma) try writer.writeByte(',');
    try core.util.writeJsonString(writer, name);
    try writer.writeAll(":[");
    for (values, 0..) |value, index| {
        if (index > 0) try writer.writeByte(',');
        try jsonString(writer, value);
    }
    try writer.writeByte(']');
}

fn jsonString(writer: anytype, value: []const u8) !void {
    var redacted: [1024]u8 = undefined;
    try core.util.writeJsonString(writer, core.api.redactStringBounded(value, &redacted));
}

fn jsonStringRaw(writer: anytype, value: []const u8) !void {
    try core.util.writeJsonString(writer, value);
}

fn ensureParent(path: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| try std.fs.cwd().makePath(parent);
}

test "edge redteam json report is parseable" {
    const allocator = std.testing.allocator;
    const result = runner.FixtureResult{
        .allocator = allocator,
        .id = try allocator.dupe(u8, "fixture"),
        .name = try allocator.dupe(u8, "Fixture"),
        .category = .geofence,
        .environment = .fake_adapter,
        .status = .passed,
        .required = true,
        .points_possible = 1,
        .points_earned = 1,
        .expected_decision = .deny,
        .actual_decision = .deny,
        .audit_session_id = try allocator.dupe(u8, "session"),
    };
    var results = [_]runner.FixtureResult{result};
    var suite = runner.SuiteResult{
        .allocator = allocator,
        .run_id = try allocator.dupe(u8, "run"),
        .session_id = try allocator.dupe(u8, "session"),
        .session_dir = try allocator.dupe(u8, "session-dir"),
        .output_dir = try allocator.dupe(u8, "output"),
        .results = results[0..],
    };
    defer {
        suite.allocator.free(suite.run_id);
        suite.allocator.free(suite.session_id);
        suite.allocator.free(suite.session_dir);
        suite.allocator.free(suite.output_dir);
        results[0].deinit();
    }
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try writeJson(out.writer(allocator), suite);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, out.items, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value.object.get("fixtures") != null);
}
