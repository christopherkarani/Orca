const std = @import("std");
const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");

pub fn command(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    return placeholder("policy", argv, stdout, stderr);
}

fn placeholder(name: []const u8, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len > 0 and (std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h"))) {
        _ = try help.writeCommand(stdout, name);
        return exit_codes.success;
    }
    if (argv.len > 0) {
        try stderr.print("aegis {s}: unknown option '{s}'.\n", .{ name, argv[0] });
        return exit_codes.usage;
    }
    try stderr.print("aegis {s}: not implemented yet\n", .{name});
    return exit_codes.unsupported;
}
