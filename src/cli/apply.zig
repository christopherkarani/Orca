const std = @import("std");
const staged_mutation = @import("staged_mutation.zig");

pub fn command(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    return staged_mutation.command(io, argv, stdout, stderr, .apply);
}

test {
    _ = staged_mutation;
}
