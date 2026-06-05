const std = @import("std");
const builtin = @import("builtin");

/// ANSI SGR codes for terminal styling. Only emitted when useColor() returns true.
pub const Style = struct {
    pub const bold = "\x1b[1m";
    pub const dim = "\x1b[2m";
    pub const red = "\x1b[31m";
    pub const green = "\x1b[32m";
    pub const yellow = "\x1b[33m";
    pub const blue = "\x1b[34m";
    pub const reset = "\x1b[0m";
};

/// Glyphs for status and celebration. Unicode is used unconditionally (modern
/// terminals, pipes, and files handle UTF-8). No ASCII fallbacks.
pub const Glyph = struct {
    pub const check = "✅";
    pub const cross = "❌";
    pub const arrow = "→";
    pub const bullet = "•";
    pub const shield = "🛡";
    pub const party = "🎉";
    pub const wave = "👋";
};

/// Pure decision logic (testable without env or global state).
pub fn shouldUseColor(is_tty: bool, no_color: bool, term_dumb: bool) bool {
    if (!is_tty) return false;
    if (no_color) return false;
    if (term_dumb) return false;
    return true;
}

/// Cached color decision. Populated explicitly early by cli.runWithCwd (primary path)
/// or lazily on first useColor call (fallback). Protected by builtin.is_test guard.
var global_color_enabled: ?bool = null;

pub fn useColor(io: std.Io, stdout: anytype) bool {
    if (builtin.is_test) return false;
    if (global_color_enabled) |cached| return cached;

    const result = detectColor(io, stdout);
    global_color_enabled = result;
    return result;
}

fn detectColor(io: std.Io, stdout: anytype) bool {
    const Writer = @TypeOf(stdout);
    const is_file = switch (@typeInfo(Writer)) {
        .pointer => |ptr| ptr.child == std.Io.File,
        else => Writer == std.Io.File,
    };
    const is_file_writer = switch (@typeInfo(Writer)) {
        .pointer => |ptr| @hasField(ptr.child, "file") and @hasField(ptr.child, "interface"),
        else => @hasField(Writer, "file") and @hasField(Writer, "interface"),
    };

    if (is_file) {
        const file = switch (@typeInfo(Writer)) {
            .pointer => stdout.*,
            else => stdout,
        };
        return detectFileColor(io, file);
    }

    if (is_file_writer) {
        const writer = switch (@typeInfo(Writer)) {
            .pointer => stdout.*,
            else => stdout,
        };
        return detectFileColor(io, writer.file);
    }

    return detectFileColor(io, std.Io.File.stdout());
}

fn detectFileColor(io: std.Io, file: std.Io.File) bool {
    const is_tty = file.isTty(io) catch false;
    const no_color = envSet("NO_COLOR");
    const term_dumb = blk: {
        const term = std.c.getenv("TERM") orelse break :blk false;
        break :blk std.mem.eql(u8, std.mem.sliceTo(term, 0), "dumb");
    };
    if (!shouldUseColor(is_tty, no_color, term_dumb)) return false;

    const clicolor_force = envSet("CLICOLOR_FORCE");
    const mode = std.Io.Terminal.Mode.detect(io, file, no_color, clicolor_force) catch return false;
    return switch (mode) {
        .no_color => false,
        .escape_codes, .windows_api => true,
    };
}

fn envSet(comptime name: [:0]const u8) bool {
    const value = std.c.getenv(name) orelse return false;
    return value[0] != 0;
}

pub fn maybeColor(io: std.Io, stdout: anytype, code: []const u8, text: []const u8) !void {
    if (useColor(io, stdout)) {
        try stdout.writeAll(code);
        try stdout.writeAll(text);
        try stdout.writeAll(Style.reset);
    } else {
        try stdout.writeAll(text);
    }
}

test "color codes are correct strings" {
    try std.testing.expectEqualStrings("\x1b[1m", Style.bold);
    try std.testing.expectEqualStrings("\x1b[2m", Style.dim);
    try std.testing.expectEqualStrings("\x1b[31m", Style.red);
    try std.testing.expectEqualStrings("\x1b[32m", Style.green);
    try std.testing.expectEqualStrings("\x1b[33m", Style.yellow);
    try std.testing.expectEqualStrings("\x1b[34m", Style.blue);
    try std.testing.expectEqualStrings("\x1b[0m", Style.reset);
}

test "NO_COLOR disables color (via pure decision)" {
    try std.testing.expect(!shouldUseColor(true, true, false));
    try std.testing.expect(shouldUseColor(true, false, false));
}

test "TERM=dumb disables color (via pure decision)" {
    try std.testing.expect(!shouldUseColor(true, false, true));
    try std.testing.expect(shouldUseColor(true, false, false));
}

test "useColor is conservative in test environment (fixedBuffer writers)" {
    var buf: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    try std.testing.expect(!useColor(std.testing.io, &writer));
}

test "maybeColor emits plain text when color disabled (test env)" {
    var buf: [128]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    const w = &writer;

    try maybeColor(std.testing.io, w, Style.green, "hello");
    try std.testing.expectEqualStrings("hello", writer.buffered());
}

test "glyphs are the expected unicode values" {
    try std.testing.expectEqualStrings("✅", Glyph.check);
    try std.testing.expectEqualStrings("❌", Glyph.cross);
    try std.testing.expectEqualStrings("🛡", Glyph.shield);
    try std.testing.expectEqualStrings("🎉", Glyph.party);
}

test "color decision cache populates after first non-bypass useColor path" {
    global_color_enabled = null;

    var buf: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    const result = detectColor(std.testing.io, &writer);

    global_color_enabled = result;

    try std.testing.expect(global_color_enabled != null);
    global_color_enabled = null;
}