const std = @import("std");
const theme = @import("theme.zig");
const terminal_text = @import("terminal_text.zig");
const vaxis = @import("vaxis");

/// Inline spinner using libvaxis synchronized-output control sequences so each
/// frame update is atomic. Timing remains caller-driven; plain output is static.
pub fn Spinner(comptime Writer: type) type {
    return struct {
        frames: []const []const u8 = &.{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
        frame_index: usize = 0,
        label: []const u8,
        io: std.Io,
        stdout: Writer,

        pub fn start(self: *@This()) !void {
            if (!theme.active(self.io, self.stdout).capability.hasColor()) return;
            try self.tick();
        }

        pub fn tick(self: *@This()) !void {
            if (!theme.active(self.io, self.stdout).capability.hasColor()) return;
            const frame = self.frames[self.frame_index % self.frames.len];
            try self.stdout.writeAll(vaxis.ctlseqs.sync_set);
            try self.stdout.print("\r\x1b[2K\r  {s} ", .{frame});
            try terminal_text.write(self.stdout, self.label, .single_line);
            try self.stdout.writeAll("...");
            try self.stdout.writeAll(vaxis.ctlseqs.sync_reset);
            try flush(self.stdout);
            self.frame_index += 1;
        }

        pub fn stop(self: *@This(), success: bool) !void {
            if (theme.active(self.io, self.stdout).capability.hasColor()) try self.stdout.writeAll("\r\x1b[2K\r");
            try self.stdout.print("  {s} ", .{if (success) "✓" else "✗"});
            try terminal_text.write(self.stdout, self.label, .single_line);
            try self.stdout.writeAll("\n");
        }
    };
}

fn flush(writer: anytype) !void {
    const Writer = @TypeOf(writer);
    switch (@typeInfo(Writer)) {
        .pointer => |pointer| if (@hasDecl(pointer.child, "flush")) try writer.flush(),
        else => if (@hasDecl(Writer, "flush")) try writer.flush(),
    }
}

test "spinner plain fallback contains no cursor controls" {
    var buf: [128]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    var spinner = Spinner(*std.Io.Writer){ .label = "Checking", .io = std.testing.io, .stdout = &writer };
    try spinner.start();
    try spinner.stop(true);
    try std.testing.expect(std.mem.indexOfScalar(u8, writer.buffered(), '\x1b') == null);
}

test "spinner rich frames are atomically bracketed by libvaxis sync controls" {
    theme.setTestActive(.{ .capability = .c256, .background = .dark });
    defer theme.setTestActive(null);
    var buf: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    var spinner = Spinner(*std.Io.Writer){ .label = "Checking\x1b[2J", .io = std.testing.io, .stdout = &writer };
    try spinner.start();
    try spinner.stop(true);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), vaxis.ctlseqs.sync_set) != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), vaxis.ctlseqs.sync_reset) != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "\r\x1b[2K\r") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "[2J") == null);
}
