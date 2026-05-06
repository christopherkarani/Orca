const std = @import("std");

const fixtures = @import("fixtures.zig");

pub const Status = enum {
    passed,
    failed,
    skipped,

    pub fn toString(self: Status) []const u8 {
        return @tagName(self);
    }
};

pub const CategoryTotal = struct {
    category: fixtures.Category,
    fixtures: usize = 0,
    passed: usize = 0,
    failed: usize = 0,
    skipped: usize = 0,
    points_possible: u32 = 0,
    points_earned: u32 = 0,
};

pub const Totals = struct {
    fixtures: usize = 0,
    passed: usize = 0,
    failed: usize = 0,
    skipped: usize = 0,
    points_possible: u32 = 0,
    points_earned: u32 = 0,

    pub fn percent(self: Totals) u32 {
        if (self.points_possible == 0) return 0;
        return @intCast((@as(u64, self.points_earned) * 100) / self.points_possible);
    }

    pub fn allRequiredPassed(self: Totals) bool {
        return self.failed == 0 and self.skipped == 0;
    }
};

pub fn summarize(comptime Result: type, results: []const Result) Totals {
    var totals: Totals = .{};
    for (results) |result| {
        totals.fixtures += 1;
        totals.points_possible += result.points_possible;
        switch (result.status) {
            .passed => {
                totals.passed += 1;
                totals.points_earned += result.points_earned;
            },
            .failed => totals.failed += 1,
            .skipped => totals.skipped += 1,
        }
    }
    return totals;
}

pub fn summarizeCategory(comptime Result: type, category: fixtures.Category, results: []const Result) CategoryTotal {
    var total: CategoryTotal = .{ .category = category };
    for (results) |result| {
        if (result.category != category) continue;
        total.fixtures += 1;
        total.points_possible += result.points_possible;
        switch (result.status) {
            .passed => {
                total.passed += 1;
                total.points_earned += result.points_earned;
            },
            .failed => total.failed += 1,
            .skipped => total.skipped += 1,
        }
    }
    return total;
}

pub const ordered_categories = [_]fixtures.Category{
    .prompt_injection,
    .secret_exfil,
    .network_exfil,
    .mcp_tool_poisoning,
    .shell_abuse,
    .filesystem_bypass,
};

test "redteam score calculation and category grouping" {
    const Fake = struct {
        category: fixtures.Category,
        status: Status,
        points_possible: u32,
        points_earned: u32,
    };
    const results = [_]Fake{
        .{ .category = .secret_exfil, .status = .passed, .points_possible = 10, .points_earned = 10 },
        .{ .category = .secret_exfil, .status = .failed, .points_possible = 5, .points_earned = 0 },
        .{ .category = .network_exfil, .status = .skipped, .points_possible = 2, .points_earned = 0 },
    };
    const totals = summarize(Fake, &results);
    try std.testing.expectEqual(@as(usize, 3), totals.fixtures);
    try std.testing.expectEqual(@as(usize, 1), totals.passed);
    try std.testing.expectEqual(@as(u32, 10), totals.points_earned);
    try std.testing.expectEqual(@as(u32, 17), totals.points_possible);

    const secret = summarizeCategory(Fake, .secret_exfil, &results);
    try std.testing.expectEqual(@as(usize, 2), secret.fixtures);
    try std.testing.expectEqual(@as(usize, 1), secret.failed);
}
