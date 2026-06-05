const std = @import("std");

/// Duplicate an environment variable from a map, or null if unset.
pub fn getOwned(map: *const std.process.Environ.Map, allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
    const value = map.get(key) orelse return null;
    return try allocator.dupe(u8, value);
}

/// Read the process environment block (POSIX libc `environ`).
pub fn processEnviron() std.process.Environ {
    return .{ .block = std.process.Environ.PosixBlock{
        .slice = @ptrCast(std.c.environ[0..countCEnviron() :null]),
    } };
}

fn countCEnviron() usize {
    var n: usize = 0;
    while (std.c.environ[n]) |entry| : (n += 1) {
        _ = entry;
    }
    return n;
}

/// Allocate a map of the current process environment.
pub fn createProcessMap(allocator: std.mem.Allocator) !std.process.Environ.Map {
    return try std.process.Environ.createMap(processEnviron(), allocator);
}
