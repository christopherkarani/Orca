const std = @import("std");

pub const redacted_value = "[REDACTED]";

pub fn redactString(value: []const u8) []const u8 {
    if (looksSensitive(value)) return redacted_value;
    return value;
}

pub fn looksSensitive(value: []const u8) bool {
    const needles = [_][]const u8{
        "SECRET",
        "TOKEN",
        "PASSWORD",
        "PASSWD",
        "API_KEY",
        "PRIVATE_KEY",
        "BEGIN RSA PRIVATE KEY",
        "BEGIN OPENSSH PRIVATE KEY",
    };

    var upper_buf: [512]u8 = undefined;
    const scan = value[0..@min(value.len, upper_buf.len)];
    for (scan, 0..) |byte, index| {
        upper_buf[index] = std.ascii.toUpper(byte);
    }
    const upper = upper_buf[0..scan.len];

    for (needles) |needle| {
        if (std.mem.indexOf(u8, upper, needle) != null) return true;
    }
    if (std.mem.startsWith(u8, upper, "SK-")) return true;
    return false;
}

test "redaction hook catches common secret-shaped metadata" {
    try std.testing.expectEqualStrings(redacted_value, redactString("OPENAI_API_KEY=sk-test"));
    try std.testing.expectEqualStrings(redacted_value, redactString("token=abc"));
    try std.testing.expectEqualStrings("echo", redactString("echo"));
}
