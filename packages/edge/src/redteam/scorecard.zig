const std = @import("std");

const fixture = @import("fixture.zig");
const safety_report = @import("../audit/safety_report.zig");

pub const Status = safety_report.ScenarioResultStatus;

pub const CategoryTotal = struct {
    category: fixture.Category,
    fixtures: usize = 0,
    required: usize = 0,
    passed: usize = 0,
    failed: usize = 0,
    skipped: usize = 0,
    unsupported: usize = 0,
    inconclusive: usize = 0,
    points_possible: u32 = 0,
    points_earned: u32 = 0,
};

pub const Totals = struct {
    fixtures: usize = 0,
    required: usize = 0,
    passed: usize = 0,
    failed: usize = 0,
    skipped: usize = 0,
    unsupported: usize = 0,
    inconclusive: usize = 0,
    points_possible: u32 = 0,
    points_earned: u32 = 0,

    pub fn percent(self: Totals) u32 {
        if (self.points_possible == 0) return 0;
        return @intCast((@as(u64, self.points_earned) * 100) / self.points_possible);
    }
};

pub const ordered_categories = [_]fixture.Category{
    .geofence,
    .altitude,
    .velocity,
    .battery,
    .stale_state,
    .mission,
    .mavlink_parser,
    .mavlink_command,
    .endpoint_spoofing,
    .approval_bypass,
    .emergency_bypass,
    .mode_authority,
    .telemetry_fault,
    .data_guard,
    .health,
    .audit_redaction,
    .safety_case,
    .unsupported_feature,
    .px4_sitl,
    .ardupilot_sitl,
};

pub fn summarize(comptime Result: type, results: []const Result) Totals {
    var totals: Totals = .{};
    for (results) |result| {
        totals.fixtures += 1;
        if (result.required) totals.required += 1;
        if (countsForRequiredScore(result)) {
            totals.points_possible += result.points_possible;
            if (result.status == .passed) totals.points_earned += result.points_earned;
        }
        switch (result.status) {
            .passed => totals.passed += 1,
            .failed => totals.failed += 1,
            .skipped => totals.skipped += 1,
            .unsupported => totals.unsupported += 1,
            .inconclusive => totals.inconclusive += 1,
        }
    }
    return totals;
}

pub fn summarizeCategory(comptime Result: type, category: fixture.Category, results: []const Result) CategoryTotal {
    var total: CategoryTotal = .{ .category = category };
    for (results) |result| {
        if (result.category != category) continue;
        total.fixtures += 1;
        if (result.required) total.required += 1;
        if (countsForRequiredScore(result)) {
            total.points_possible += result.points_possible;
            if (result.status == .passed) total.points_earned += result.points_earned;
        }
        switch (result.status) {
            .passed => total.passed += 1,
            .failed => total.failed += 1,
            .skipped => total.skipped += 1,
            .unsupported => total.unsupported += 1,
            .inconclusive => total.inconclusive += 1,
        }
    }
    return total;
}

fn countsForRequiredScore(result: anytype) bool {
    if (!result.required) return false;
    if (result.status == .skipped or result.status == .unsupported) return false;
    return true;
}

test "edge redteam scorecard skips unsupported and skipped from pass math" {
    const Fake = struct {
        category: fixture.Category,
        status: Status,
        required: bool,
        points_possible: u32,
        points_earned: u32,
    };
    const results = [_]Fake{
        .{ .category = .geofence, .status = .passed, .required = true, .points_possible = 10, .points_earned = 10 },
        .{ .category = .geofence, .status = .skipped, .required = true, .points_possible = 10, .points_earned = 0 },
        .{ .category = .unsupported_feature, .status = .unsupported, .required = true, .points_possible = 10, .points_earned = 0 },
        .{ .category = .mission, .status = .failed, .required = true, .points_possible = 10, .points_earned = 0 },
    };
    const totals = summarize(Fake, &results);
    try std.testing.expectEqual(@as(usize, 1), totals.passed);
    try std.testing.expectEqual(@as(usize, 1), totals.skipped);
    try std.testing.expectEqual(@as(usize, 1), totals.unsupported);
    try std.testing.expectEqual(@as(u32, 20), totals.points_possible);
    try std.testing.expectEqual(@as(u32, 10), totals.points_earned);
}
