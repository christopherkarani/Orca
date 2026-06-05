const std = @import("std");

pub const Timestamp = struct {
    unix_seconds: i64,

    pub fn now(io: std.Io) Timestamp {
        const ts = std.Io.Timestamp.now(io, .real);
        return .{ .unix_seconds = ts.toSeconds() };
    }

    pub fn fromUnixSeconds(seconds: i64) Timestamp {
        return .{ .unix_seconds = seconds };
    }

    pub fn formatIso(self: Timestamp, out: []u8) ![]const u8 {
        const parts = epochParts(self.unix_seconds);
        return std.fmt.bufPrint(out, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
            parts.year,
            parts.month,
            parts.day,
            parts.hour,
            parts.minute,
            parts.second,
        });
    }

    pub fn formatFilenameSafe(self: Timestamp, out: []u8) ![]const u8 {
        const parts = epochParts(self.unix_seconds);
        return std.fmt.bufPrint(out, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}-{d:0>2}-{d:0>2}Z", .{
            parts.year,
            parts.month,
            parts.day,
            parts.hour,
            parts.minute,
            parts.second,
        });
    }
};

const EpochParts = struct {
    year: u16,
    month: u4,
    day: u5,
    hour: u5,
    minute: u6,
    second: u6,
};

fn epochParts(seconds: i64) EpochParts {
    std.debug.assert(seconds >= 0);
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(seconds) };
    const year_day = epoch_seconds.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();
    return .{
        .year = year_day.year,
        .month = @intFromEnum(month_day.month),
        .day = month_day.day_index + 1,
        .hour = day_seconds.getHoursIntoDay(),
        .minute = day_seconds.getMinutesIntoHour(),
        .second = day_seconds.getSecondsIntoMinute(),
    };
}

test "timestamp formatting is stable and filename safe" {
    const ts = Timestamp.fromUnixSeconds(1_777_983_130);

    var iso_buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("2026-05-05T12:12:10Z", try ts.formatIso(&iso_buf));

    var filename_buf: [32]u8 = undefined;
    const filename = try ts.formatFilenameSafe(&filename_buf);
    try std.testing.expectEqualStrings("2026-05-05T12-12-10Z", filename);
    try std.testing.expect(std.mem.indexOfAny(u8, filename, ":/\\") == null);
}
