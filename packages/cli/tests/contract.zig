const std = @import("std");
const aegis_cli = @import("aegis_cli");

test "cli package exposes existing command surface without becoming edge" {
    try std.testing.expectEqualStrings("23-product-split-cli-contract", aegis_cli.phase);
    try std.testing.expect(aegis_cli.cli.help.findCommand("run") != null);
    try std.testing.expect(aegis_cli.cli.help.findCommand("doctor") != null);
    try std.testing.expect(aegis_cli.cli.help.findCommand("redteam") != null);
    try std.testing.expect(aegis_cli.cli.help.findCommand("edge") == null);
}

test "cli package help still renders Aegis CLI command summary" {
    var buffer: [8192]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    try aegis_cli.cli.help.write(stream.writer());
    const written = stream.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, written, "Aegis") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "Commands:") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "redteam") != null);
}
