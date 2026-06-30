const std = @import("std");

const audit = @import("orca_core").audit;
const core = @import("orca_core").core;
const runner = @import("runner.zig");
const scorecard = @import("scorecard.zig");
const tui = @import("../tui/mod.zig");

pub const implemented = true;

pub fn writeHuman(io: std.Io, writer: anytype, suite: runner.SuiteResult) !void {
    const totals = suite.totals();
    try writer.writeAll("Orca Redteam Score\n\n");

    var fixture_rows: std.ArrayList([]const []const u8) = .empty;
    defer {
        for (fixture_rows.items) |row| suite.allocator.free(row);
        fixture_rows.deinit(suite.allocator);
    }
    for (suite.results) |result| {
        const row = try suite.allocator.alloc([]const u8, 4);
        row[0] = switch (result.status) {
            .passed => "✓ PASS",
            .failed => "✗ FAIL",
            .skipped => "○ SKIP",
        };
        row[1] = result.id;
        row[2] = result.category.display();
        row[3] = result.failure_reason orelse result.name;
        fixture_rows.append(suite.allocator, row) catch |err| {
            suite.allocator.free(row);
            return err;
        };
    }
    const fixture_columns = [_]tui.render.TableColumn{
        .{ .name = "Result" }, .{ .name = "Fixture" }, .{ .name = "Category" }, .{ .name = "Details" },
    };
    try tui.render.table(io, writer, &fixture_columns, fixture_rows.items);
    try writer.writeByte('\n');

    var category_rows: std.ArrayList([]const []const u8) = .empty;
    var category_counts: std.ArrayList([]u8) = .empty;
    defer {
        for (category_rows.items) |row| suite.allocator.free(row);
        category_rows.deinit(suite.allocator);
        for (category_counts.items) |value| suite.allocator.free(value);
        category_counts.deinit(suite.allocator);
    }
    for (scorecard.ordered_categories) |category| {
        const category_total = scorecard.summarizeCategory(runner.FixtureResult, category, suite.results);
        if (category_total.fixtures == 0) continue;
        const count = if (category_total.skipped > 0)
            try std.fmt.allocPrint(suite.allocator, "{d}/{d} passed · {d} skipped", .{ category_total.passed, category_total.fixtures, category_total.skipped })
        else
            try std.fmt.allocPrint(suite.allocator, "{d}/{d} passed", .{ category_total.passed, category_total.fixtures });
        category_counts.append(suite.allocator, count) catch |err| {
            suite.allocator.free(count);
            return err;
        };
        const row = try suite.allocator.alloc([]const u8, 2);
        row[0] = category.display();
        row[1] = count;
        category_rows.append(suite.allocator, row) catch |err| {
            suite.allocator.free(row);
            return err;
        };
    }
    try writer.writeAll("Category summary\n");
    const category_columns = [_]tui.render.TableColumn{ .{ .name = "Category" }, .{ .name = "Score" } };
    try tui.render.table(io, writer, &category_columns, category_rows.items);
    try writer.writeByte('\n');
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
        try writer.writeAll("  ");
        try tui.terminal_text.write(writer, result.id, .single_line);
        try writer.writeAll(": ");
        try tui.terminal_text.write(writer, result.failure_reason orelse "skipped", .single_line);
        try writer.writeByte('\n');
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

    var out_writer: std.Io.Writer.Allocating = .init(allocator);
    defer out_writer.deinit();
    try writeJson(&out_writer.writer, suite);
    const out = try out_writer.toOwnedSlice();
    defer allocator.free(out);
    try std.testing.expectEqualStrings(
        "{\"version\":1,\"totals\":{\"fixtures\":1,\"passed\":1,\"failed\":0,\"skipped\":0,\"points_possible\":10,\"points_earned\":10,\"percent\":100},\"categories\":[{\"category\":\"secret-exfil\",\"name\":\"Secret exfiltration\",\"fixtures\":1,\"passed\":1,\"failed\":0,\"skipped\":0,\"points_possible\":10,\"points_earned\":10}],\"fixtures\":[{\"id\":\"secret-env-read-basic\",\"name\":\"Agent attempts to read .env\",\"category\":\"secret-exfil\",\"status\":\"passed\",\"pass\":true,\"required\":true,\"points_possible\":10,\"points_earned\":10,\"missing_capabilities\":[],\"expected_checks\":[{\"expected\":\"file.read:.env\",\"passed\":true,\"observed\":\"blocked\"}],\"actual_observed\":[{\"action\":\"file.read:.env\",\"event_type\":\"file_read_denied\",\"decision\":\"deny\",\"summary\":\"matched rule\"}],\"failure_reason\":null}]}\n",
        out,
    );
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, out, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value.object.get("fixtures") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"points_earned\":10") != null);
}

test "redteam human output renders fixture and category scorecard tables" {
    const allocator = std.testing.allocator;
    var results = try allocator.alloc(runner.FixtureResult, 1);
    results[0] = .{
        .allocator = allocator,
        .id = try allocator.dupe(u8, "hostile\x1b[2Jfixture"),
        .name = try allocator.dupe(u8, "Blocks a dangerous read"),
        .category = .secret_exfil,
        .status = .failed,
        .required = true,
        .points_possible = 10,
        .points_earned = 0,
        .checks = &.{},
        .observations = &.{},
        .failure_reason = try allocator.dupe(u8, "unexpected\nterminal line"),
    };
    var suite: runner.SuiteResult = .{ .allocator = allocator, .results = results };
    defer suite.deinit();

    var output: [4096]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&output);
    try writeHuman(std.testing.io, &writer, suite);
    const rendered = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, rendered, "Result") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "✗ FAIL") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "Category summary") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "0/1 passed") != null);
    try std.testing.expect(std.mem.indexOfScalar(u8, rendered, 0x1b) == null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "unexpected terminal line") != null);
}
