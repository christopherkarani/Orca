const std = @import("std");
const theme = @import("theme.zig");

/// Inline spinner with a static plain-output fallback. Cursor controls are
/// emitted only when the active output target supports rich rendering.
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
            try self.stdout.print("\r\x1b[2K\r  {s} {s}...", .{ frame, self.label });
            try flush(self.stdout);
            self.frame_index += 1;
        }

        pub fn stop(self: *@This(), success: bool) !void {
            if (theme.active(self.io, self.stdout).capability.hasColor()) try self.stdout.writeAll("\r\x1b[2K\r");
            try self.stdout.print("  {s} {s}\n", .{ if (success) "✓" else "✗", self.label });
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
