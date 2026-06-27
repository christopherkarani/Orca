const std = @import("std");
const theme = @import("theme.zig");
const terminal_text = @import("terminal_text.zig");
const vaxis = @import("vaxis");

/// Inline spinner with a static plain-output fallback. Cursor controls are
/// emitted only when the active output target supports rich rendering.
pub fn Spinner(comptime Writer: type) type {
    return struct {
        frames: []const []const u8 = &.{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
        frame_index: usize = 0,
        label: []const u8,
        io: std.Io,
        stdout: Writer,
        backend: ?vaxis.vxfw.Spinner = null,

        pub fn start(self: *@This()) !void {
            if (!theme.active(self.io, self.stdout).capability.hasColor()) return;
            self.backend = .{ .io = self.io };
            _ = self.backend.?.start();
            try self.tick();
        }

        pub fn tick(self: *@This()) !void {
            if (!theme.active(self.io, self.stdout).capability.hasColor()) return;
            const frame = self.frames[self.frame_index % self.frames.len];
            try self.stdout.print("\r\x1b[2K\r  {s} ", .{frame});
            try terminal_text.write(self.stdout, self.label, .single_line);
            try self.stdout.writeAll("...");
            try flush(self.stdout);
            self.frame_index += 1;
        }

        pub fn stop(self: *@This(), success: bool) !void {
            if (theme.active(self.io, self.stdout).capability.hasColor()) try self.stdout.writeAll("\r\x1b[2K\r");
            if (self.backend) |*backend| backend.stop();
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

test "spinner rich path initializes libvaxis backend and emits cursor controls" {
    theme.setTestActive(.{ .capability = .c256, .background = .dark });
    defer theme.setTestActive(null);
    var buf: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    var spinner = Spinner(*std.Io.Writer){ .label = "Checking\x1b[2J", .io = std.testing.io, .stdout = &writer };
    try spinner.start();
    try std.testing.expect(spinner.backend != null);
    try std.testing.expectEqual(@as(u16, 1), spinner.backend.?.count.load(.unordered));
    try spinner.stop(true);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "\r\x1b[2K\r") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "[2J") == null);
}
