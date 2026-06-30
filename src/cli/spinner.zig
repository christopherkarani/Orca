const std = @import("std");
const tui_spinner = @import("../tui/spinner.zig");

pub const Spinner = tui_spinner.Spinner;

test "Spinner start and tick are no-ops in test environment (non-TTY)" {
    var buf: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    var spinner = Spinner(*std.Io.Writer){
        .label = "test",
        .io = std.testing.io,
        .stdout = &writer,
    };
    try spinner.start();
    try spinner.tick();
    // start and tick are no-ops in non-color mode
    try std.testing.expectEqualStrings("", writer.buffered());
}

test "Spinner stop prints static checkmark on non-color stdout" {
    var buf: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    var spinner = Spinner(*std.Io.Writer){
        .label = "test",
        .io = std.testing.io,
        .stdout = &writer,
    };
    try spinner.stop(true);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "✓") != null);
}

test "Spinner frames are array of single-codepoint strings" {
    var buf: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    const spinner = Spinner(*std.Io.Writer){
        .label = "test",
        .io = std.testing.io,
        .stdout = &writer,
    };
    try std.testing.expectEqual(@as(usize, 10), spinner.frames.len);
    for (spinner.frames) |frame| {
        try std.testing.expectEqual(@as(usize, 3), frame.len);
    }
}

test "Spinner stop prints static cross on failure in non-color mode" {
    var buf: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    var spinner = Spinner(*std.Io.Writer){
        .label = "test",
        .io = std.testing.io,
        .stdout = &writer,
    };
    try spinner.stop(false);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "✗") != null);
}
