const std = @import("std");
const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");

pub fn command(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len > 0 and (std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h"))) {
        _ = try help.writeCommand(stdout, "discard");
        return exit_codes.success;
    }
    if (argv.len > 0) {
        try stderr.print("aegis discard: unknown option '{s}'.\n", .{argv[0]});
        return exit_codes.usage;
    }
    try stderr.writeAll("aegis discard: not implemented yet\n");
    return exit_codes.unsupported;
}
