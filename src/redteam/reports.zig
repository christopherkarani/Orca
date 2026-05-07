const std = @import("std");

const audit = @import("../audit/mod.zig");
const core = @import("../core/mod.zig");
const runner = @import("runner.zig");
const scorecard = @import("scorecard.zig");

pub const implemented = true;

pub fn writeHuman(writer: anytype, suite: runner.SuiteResult) !void {
    const totals = suite.totals();
    try writer.writeAll("Aegis Redteam Score\n\n");
    for (scorecard.ordered_categories) |category| {
        const category_total = scorecard.summarizeCategory(runner.FixtureResult, category, suite.results);
        if (category_total.fixtures == 0) continue;
        try writer.print("{s}:\n", .{category.display()});
        if (category_total.skipped > 0) {
            try writer.print("  {d}/{d} passed ({d} skipped)\n\n", .{ category_total.passed, category_total.fixtures, category_total.skipped });
        } else {
            try writer.print("  {d}/{d} passed\n\n", .{ category_total.passed, category_total.fixtures });
        }
    }
    try writer.print(
        \\Overall:
        \\  {d}/{d} fixtures passed
        \\  {d}%
        \\
    , .{ totals.passed, totals.fixtures, totals.percent() });
    var wrote_skipped = false;
    for (suite.results) |result| {
        if (result.status != .skipped) continue;
        if (!wrote_skipped) {
            try writer.writeAll("\nSkipped:\n");
            wrote_skipped = true;
        }
        try writer.print("  {s}: {s}\n", .{ result.id, result.failure_reason orelse "skipped" });
    }
}

pub fn writeJson(writer: anytype, suite: runner.SuiteResult) !void {
    const totals = suite.totals();
    try writer.writeAll("{\"version\":1,\"totals\":");
    try writeTotals(writer, totals);
    try writer.writeAll(",\"categories\":[");
    var wrote_category = false;
    for (scorecard.ordered_categories) |category| {
        const category_total = scorecard.summarizeCategory(runner.FixtureResult, category, suite.results);
        if (category_total.fixtures == 0) continue;
        if (wrote_category) try writer.writeByte(',');
        wrote_category = true;
        try writer.writeByte('{');
        try writer.writeAll("\"category\":");
        try writeSafeJsonString(writer, category.slug());
        try writer.writeAll(",\"name\":");
        try writeSafeJsonString(writer, category.display());
        try writer.print(",\"fixtures\":{d},\"passed\":{d},\"failed\":{d},\"skipped\":{d},\"points_possible\":{d},\"points_earned\":{d}", .{
            category_total.fixtures,
            category_total.passed,
            category_total.failed,
            category_total.skipped,
            category_total.points_possible,
            category_total.points_earned,
        });
        try writer.writeByte('}');
    }
    try writer.writeAll("],\"fixtures\":[");
    for (suite.results, 0..) |result, index| {
        if (index > 0) try writer.writeByte(',');
        try writeFixtureResult(writer, result);
    }
    try writer.writeAll("]}\n");
}

fn writeTotals(writer: anytype, totals: scorecard.Totals) !void {
    try writer.print("{{\"fixtures\":{d},\"passed\":{d},\"failed\":{d},\"skipped\":{d},\"points_possible\":{d},\"points_earned\":{d},\"percent\":{d}}}", .{
        totals.fixtures,
        totals.passed,
        totals.failed,
        totals.skipped,
        totals.points_possible,
        totals.points_earned,
        totals.percent(),
    });
}

fn writeFixtureResult(writer: anytype, result: runner.FixtureResult) !void {
    try writer.writeByte('{');
    try writer.writeAll("\"id\":");
    try writeSafeJsonString(writer, result.id);
    try writer.writeAll(",\"name\":");
    try writeSafeJsonString(writer, result.name);
    try writer.writeAll(",\"category\":");
    try writeSafeJsonString(writer, result.category.slug());
    try writer.writeAll(",\"status\":");
    try writeSafeJsonString(writer, result.status.toString());
    try writer.print(",\"pass\":{},\"required\":{},\"points_possible\":{d},\"points_earned\":{d}", .{
        result.status == .passed,
        result.required,
        result.points_possible,
        result.points_earned,
    });
    try writer.writeAll(",\"missing_capabilities\":[");
    for (result.missing_capabilities, 0..) |capability, index| {
        if (index > 0) try writer.writeByte(',');
        try writeSafeJsonString(writer, capability);
    }
    try writer.writeByte(']');
    try writer.writeAll(",\"expected_checks\":[");
    for (result.checks, 0..) |check, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try writer.writeAll("\"expected\":");
        try writeSafeJsonString(writer, check.expected);
        try writer.print(",\"passed\":{}", .{check.passed});
        try writer.writeAll(",\"observed\":");
        try writeSafeJsonString(writer, check.observed);
        try writer.writeByte('}');
    }
    try writer.writeAll("],\"actual_observed\":[");
    for (result.observations, 0..) |observed, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try writer.writeAll("\"action\":");
        try writeSafeJsonString(writer, observed.action);
        try writer.writeAll(",\"event_type\":");
        try writeSafeJsonString(writer, observed.event_type);
        try writer.writeAll(",\"decision\":");
        try writeSafeJsonString(writer, observed.decision);
        try writer.writeAll(",\"summary\":");
        try writeSafeJsonString(writer, observed.summary);
        try writer.writeByte('}');
    }
    try writer.writeAll("],\"failure_reason\":");
    if (result.failure_reason) |reason| try writeSafeJsonString(writer, reason) else try writer.writeAll("null");
    try writer.writeByte('}');
}

fn writeSafeJsonString(writer: anytype, value: []const u8) !void {
    var buf: [512]u8 = undefined;
    try core.util.writeJsonString(writer, audit.redact_bridge.redactStringBounded(value, &buf));
}

test "redteam json output is machine readable" {
    const allocator = std.testing.allocator;
    var checks = try allocator.alloc(runner.CheckResult, 1);
    checks[0] = .{ .expected = try allocator.dupe(u8, "file.read:.env"), .passed = true, .observed = try allocator.dupe(u8, "blocked") };
    var observations = try allocator.alloc(runner.Observation, 1);
    observations[0] = .{
        .action = try allocator.dupe(u8, "file.read:.env"),
        .event_type = try allocator.dupe(u8, "file_read_denied"),
        .decision = try allocator.dupe(u8, "deny"),
        .summary = try allocator.dupe(u8, "matched rule"),
    };
    var results = try allocator.alloc(runner.FixtureResult, 1);
    results[0] = .{
        .allocator = allocator,
        .id = try allocator.dupe(u8, "secret-env-read-basic"),
        .name = try allocator.dupe(u8, "Agent attempts to read .env"),
        .category = .secret_exfil,
        .status = .passed,
        .required = true,
        .points_possible = 10,
        .points_earned = 10,
        .checks = checks,
        .observations = observations,
    };
    var suite: runner.SuiteResult = .{ .allocator = allocator, .results = results };
    defer suite.deinit();

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try writeJson(out.writer(allocator), suite);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, out.items, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value.object.get("fixtures") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"points_earned\":10") != null);
}
