const std = @import("std");
const aegis = @import("aegis");

pub fn main() !void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    const code = try aegis.cli.run(argv[1..], std.fs.File.stdout(), std.fs.File.stderr());
    std.process.exit(code);
}

test {
    _ = aegis.cli;
}
