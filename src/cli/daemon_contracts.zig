const std = @import("std");

pub const PackInfo = struct {
    id: []const u8,
    name: []const u8,
    category: []const u8,
    description: []const u8,
    enabled: bool,
    safe_pattern_count: u64,
    destructive_pattern_count: u64,
};

pub const PacksOutput = struct {
    packs: []const PackInfo,
    enabled_count: u64,
    total_count: u64,
};

pub const OutcomeStats = struct {
    allowed: u64,
    denied: u64,
    warned: u64,
    bypassed: u64,
};

pub const PerformanceStats = struct {
    p50_us: u64,
    p95_us: u64,
    p99_us: u64,
    max_us: u64,
};

pub const PatternStat = struct {
    name: []const u8,
    count: u64,
    pack_id: ?[]const u8 = null,
};

pub const ProjectStat = struct {
    path: []const u8,
    command_count: u64,
};

pub const AgentStat = struct {
    name: []const u8,
    count: u64,
};

pub const TopPatternChange = @Tuple(&.{ []const u8, i32 });

pub const StatsTrends = struct {
    commands_change: f64,
    block_rate_change: f64,
    top_pattern_change: []const TopPatternChange,
};

pub const HistoryStats = struct {
    period_days: u64,
    total_commands: u64,
    outcomes: OutcomeStats,
    block_rate: f64,
    top_patterns: []const PatternStat,
    top_projects: []const ProjectStat,
    agents: []const AgentStat,
    performance: PerformanceStats,
    trends: ?StatsTrends = null,
};

pub fn parsePacks(allocator: std.mem.Allocator, json: []const u8) !std.json.Parsed(PacksOutput) {
    return std.json.parseFromSlice(PacksOutput, allocator, json, .{ .ignore_unknown_fields = true });
}

pub fn parseHistoryStats(allocator: std.mem.Allocator, json: []const u8) !std.json.Parsed(HistoryStats) {
    return std.json.parseFromSlice(HistoryStats, allocator, json, .{ .ignore_unknown_fields = true });
}

/// Converts a Rust JSON count for APIs that require a platform-sized index.
pub fn countToUsize(count: u64) error{Overflow}!usize {
    return std.math.cast(usize, count) orelse error.Overflow;
}

test "packs contract requires current fields and ignores additive fields" {
    var parsed = try parsePacks(std.testing.allocator, @embedFile("test-fixtures/daemon-packs.json"));
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u64, 1), parsed.value.enabled_count);
    try std.testing.expectEqualStrings("core.git", parsed.value.packs[0].id);
    try std.testing.expectEqual(@as(u64, 7), parsed.value.packs[0].destructive_pattern_count);
}

test "history stats contract models optional pack ids and trends" {
    var parsed = try parseHistoryStats(std.testing.allocator, @embedFile("test-fixtures/daemon-history-stats.json"));
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u64, 42), parsed.value.total_commands);
    try std.testing.expectEqualStrings("core.git", parsed.value.top_patterns[0].pack_id.?);
    try std.testing.expect(parsed.value.top_patterns[1].pack_id == null);
    const trends = parsed.value.trends.?;
    try std.testing.expectEqual(@as(f64, 12.5), trends.commands_change);
    try std.testing.expectEqualStrings("force-push", trends.top_pattern_change[0][0]);
    try std.testing.expectEqual(@as(i32, 3), trends.top_pattern_change[0][1]);
}

test "history stats accepts omitted trends and rejects missing required fields" {
    var parsed = try parseHistoryStats(std.testing.allocator,
        \\{"period_days":1,"total_commands":0,"outcomes":{"allowed":0,"denied":0,"warned":0,"bypassed":0},"block_rate":0,"top_patterns":[],"top_projects":[],"agents":[],"performance":{"p50_us":0,"p95_us":0,"p99_us":0,"max_us":0}}
    );
    defer parsed.deinit();
    try std.testing.expect(parsed.value.trends == null);

    try std.testing.expectError(error.MissingField, parsePacks(std.testing.allocator,
        \\{"packs":[],"enabled_count":0}
    ));
}

test "count conversion is checked" {
    try std.testing.expectEqual(@as(usize, 42), try countToUsize(42));
    if (@bitSizeOf(usize) < @bitSizeOf(u64)) {
        try std.testing.expectError(error.Overflow, countToUsize(std.math.maxInt(u64)));
    }
}
