const std = @import("std");
const style = @import("style.zig");

pub fn Spinner(comptime Writer: type) type {
    return struct {
        frames: []const u8 = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏",
        frame_index: usize = 0,
        label: []const u8,
        io: std.Io,
        stdout: Writer,

        pub fn start(self: *@This()) !void {
            if (!style.useColor(self.io, self.stdout)) return;
            try self.stdout.writeAll("\r\x1b[K");
            try self.tick();
        }

        pub fn tick(self: *@This()) !void {
            if (!style.useColor(self.io, self.stdout)) return;
            const frame = self.frames[self.frame_index % self.frames.len];
            try self.stdout.print("\r  {c} {s}...", .{ frame, self.label });
            try flush(self.stdout);
            self.frame_index += 1;
        }

        pub fn stop(self: *@This(), success: bool) !void {
            if (!style.useColor(self.io, self.stdout)) {
                if (success) {
                    try self.stdout.print("  ✓ {s}\n", .{self.label});
                } else {
                    try self.stdout.print("  ✗ {s}\n", .{self.label});
                }
                return;
            }
            try self.stdout.writeAll("\r\x1b[K");
            if (success) {
                try self.stdout.print("  ✓ {s}\n", .{self.label});
            } else {
                try self.stdout.print("  ✗ {s}\n", .{self.label});
            }
        }
    };
}

fn flush(writer: anytype) !void {
    const Writer = @TypeOf(writer);
    switch (@typeInfo(Writer)) {
        .pointer => |pointer| {
            if (@hasDecl(pointer.child, "flush")) try writer.flush();
        },
        else => {
            if (@hasDecl(Writer, "flush")) try writer.flush();
        },
    }
}

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
