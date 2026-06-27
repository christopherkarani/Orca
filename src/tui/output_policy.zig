const std = @import("std");

pub const Policy = struct { rich: bool };

pub fn resolve(no_rich_env: bool, no_rich_flag: bool, machine_output: bool) Policy {
    return .{ .rich = !no_rich_env and !no_rich_flag and !machine_output };
}

pub fn envDisablesRich(value: ?[]const u8) bool {
    const raw = value orelse return false;
    if (raw.len == 0) return false;
    return !std.mem.eql(u8, raw, "0") and !std.ascii.eqlIgnoreCase(raw, "false");
}

test "rich output escape hatches are fail-safe" {
    try std.testing.expect(resolve(false, false, false).rich);
    try std.testing.expect(!resolve(true, false, false).rich);
    try std.testing.expect(!resolve(false, true, false).rich);
    try std.testing.expect(!resolve(false, false, true).rich);
    try std.testing.expect(!envDisablesRich("0"));
    try std.testing.expect(envDisablesRich("1"));
}
