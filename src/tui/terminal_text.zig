const std = @import("std");

pub const Layout = enum { single_line, multiline };

/// Writes untrusted terminal text without allowing it to inject control
/// sequences. CSI/OSC escapes and C0 controls are removed; intentional line
/// breaks are preserved only in multiline mode.
pub fn write(writer: anytype, input: []const u8, layout: Layout) !void {
    var i: usize = 0;
    while (i < input.len) {
        const byte = input[i];
        if (byte == 0x1b) {
            i += 1;
            if (i >= input.len) break;
            if (input[i] == '[') {
                i += 1;
                while (i < input.len) : (i += 1) if (input[i] >= 0x40 and input[i] <= 0x7e) {
                    i += 1;
                    break;
                };
            } else if (input[i] == ']') {
                i += 1;
                while (i < input.len) : (i += 1) {
                    if (input[i] == 0x07) {
                        i += 1;
                        break;
                    }
                    if (input[i] == 0x1b and i + 1 < input.len and input[i + 1] == '\\') {
                        i += 2;
                        break;
                    }
                }
            } else i += 1;
            continue;
        }
        if (byte == '\n') {
            try writer.writeAll(if (layout == .multiline) "\n" else " ");
        } else if (byte == '\t') {
            try writer.writeAll("    ");
        } else if (byte == '\r' or byte == 0x08) {
            try writer.writeAll(" ");
        } else if (byte < 0x20 or byte == 0x7f) {
            // Drop remaining C0 controls and DEL.
        } else {
            try writer.writeByte(byte);
        }
        i += 1;
    }
}

/// Return an owned, terminal-safe copy for renderers that must measure text
/// before writing it (for example, fixed-width tables).
pub fn sanitizeAlloc(allocator: std.mem.Allocator, input: []const u8, layout: Layout) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    try write(&output.writer, input, layout);
    return output.toOwnedSlice();
}

test "sanitizer removes CSI OSC C0 and normalizes inline layout" {
    var buf: [256]u8 = undefined;
    var out: std.Io.Writer = .fixed(&buf);
    try write(&out, "ok\x1b[2Jbad\x1b]0;title\x07\rX\x08Y\tZ\nnext\x01", .single_line);
    try std.testing.expectEqualStrings("okbad X Y    Z next", out.buffered());
    try std.testing.expect(std.mem.indexOfScalar(u8, out.buffered(), 0x1b) == null);
}

test "sanitizer preserves intentional multiline breaks only" {
    var buf: [64]u8 = undefined;
    var out: std.Io.Writer = .fixed(&buf);
    try write(&out, "one\ntwo", .multiline);
    try std.testing.expectEqualStrings("one\ntwo", out.buffered());
}

test "sanitizeAlloc returns terminal-safe text suitable for width measurement" {
    const sanitized = try sanitizeAlloc(std.testing.allocator, "db.\x1b[2Jmysql\npack", .single_line);
    defer std.testing.allocator.free(sanitized);
    try std.testing.expectEqualStrings("db.mysql pack", sanitized);
}
