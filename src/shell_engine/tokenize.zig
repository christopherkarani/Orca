//! Lightweight shell tokenization for structured MVP matching.
//! Splits on whitespace; strips simple quotes; does not expand variables.

const std = @import("std");

pub fn splitArgs(allocator: std.mem.Allocator, command: []const u8) ![][]const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (list.items) |item| allocator.free(item);
        list.deinit(allocator);
    }

    var i: usize = 0;
    while (i < command.len) {
        while (i < command.len and std.ascii.isWhitespace(command[i])) : (i += 1) {}
        if (i >= command.len) break;

        const start_quote = command[i] == '\'' or command[i] == '"';
        const quote = if (start_quote) command[i] else 0;
        if (start_quote) i += 1;

        const start = i;
        if (start_quote) {
            while (i < command.len and command[i] != quote) : (i += 1) {}
            try list.append(allocator, try allocator.dupe(u8, command[start..i]));
            if (i < command.len) i += 1;
        } else {
            while (i < command.len and !std.ascii.isWhitespace(command[i])) : (i += 1) {}
            try list.append(allocator, try allocator.dupe(u8, command[start..i]));
        }
    }
    return try list.toOwnedSlice(allocator);
}

pub fn freeArgs(allocator: std.mem.Allocator, args: [][]const u8) void {
    for (args) |a| allocator.free(a);
    allocator.free(args);
}

pub fn basename(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, path, '/')) |idx| {
        if (idx + 1 < path.len) return path[idx + 1 ..];
    }
    return path;
}

test "splitArgs basic" {
    const args = try splitArgs(std.testing.allocator, "git reset --hard HEAD~1");
    defer freeArgs(std.testing.allocator, args);
    try std.testing.expectEqual(@as(usize, 4), args.len);
    try std.testing.expectEqualStrings("git", args[0]);
    try std.testing.expectEqualStrings("reset", args[1]);
}

test "splitArgs quotes" {
    const args = try splitArgs(std.testing.allocator, "rm -rf '/tmp/foo bar'");
    defer freeArgs(std.testing.allocator, args);
    try std.testing.expectEqual(@as(usize, 3), args.len);
    try std.testing.expectEqualStrings("/tmp/foo bar", args[2]);
}
