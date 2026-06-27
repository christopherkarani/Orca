const std = @import("std");
const builtin = @import("builtin");

/// Orca CLI design system: palette, color-capability detection, and theme tokens.
///
/// This module is the single source of truth for visual styling. It degrades
/// gracefully: truecolor → 256 → 16-color → plain text. It always honours
/// `NO_COLOR`, `TERM=dumb`, and non-TTY output (piped/scripted).
///
/// Pure decision functions are separated from runtime detection so they can be
/// unit-tested with fixed inputs (mirrors the `style.zig` pattern).

// ────────────────────────────────────────────────────────────────────────────
// Capability detection (pure, testable)
// ────────────────────────────────────────────────────────────────────────────

/// Highest quality of color the output target can render.
pub const Capability = enum {
    none, // plain text
    basic_16, // standard ANSI 16-color
    c256, // 256-color palette
    truecolor, // 24-bit RGB

    /// True when any color at all is available.
    pub fn hasColor(self: Capability) bool {
        return self != .none;
    }
};

/// Detectable terminal background tone. Used to pick contrast-safe variant tokens.
pub const Background = enum { dark, light, unknown };

/// Inputs to the pure capability detector. All fields are environment-derived so
/// the function itself has no global state.
pub const DetectInput = struct {
    is_tty: bool,
    no_color: bool,
    term_dumb: bool,
    /// `COLORTERM` is `truecolor` or `24bit`.
    colorterm_truecolor: bool,
    /// `TERM` contains `256color`.
    term_256color: bool,
};

/// Pure decision: which capability should be used given environment signals.
pub fn detectCapability(d: DetectInput) Capability {
    if (!d.is_tty) return .none;
    if (d.no_color) return .none;
    if (d.term_dumb) return .none;
    if (d.colorterm_truecolor) return .truecolor;
    if (d.term_256color) return .c256;
    return .basic_16;
}

/// Parse the `COLORFGBG` convention (`foreground;background`) into a background tone.
/// Returns `unknown` when absent or malformed.
pub fn parseColorfgbg(value: []const u8) Background {
    var it = std.mem.splitScalar(u8, value, ';');
    _ = it.next() orelse return .unknown; // foreground
    const bg = it.next() orelse return .unknown;
    const n = std.fmt.parseInt(u8, std.mem.trim(u8, bg, " \t"), 10) catch return .unknown;
    // Convention: background 0-6 = dark, 7-15 (and the standard "light" default 15) = light.
    return if (n <= 6) .dark else .light;
}

// ────────────────────────────────────────────────────────────────────────────
// Palette
// ────────────────────────────────────────────────────────────────────────────

/// A semantic color token. Each renders to the best SGR sequence for the active
/// capability and background.
pub const Token = enum {
    brand, // Orca coral/orange — headers, brand mark
    success, // allow, pass, installed
    danger, // deny, fail, destructive
    warn, // limited, partial, ask
    info, // neutral emphasis
    muted, // secondary/dim text
    surface, // panel borders/fill
    text, // body
    text_bright, // emphasized body
};

pub const Rgb = struct { r: u8, g: u8, b: u8 };

/// Dark-theme truecolor RGB triples (Anthropic-grade, restrained).
const dark_rgb = struct {
    const brand = Rgb{ .r = 0xff, .g = 0x7a, .b = 0x45 };
    const success = Rgb{ .r = 0x3f, .g = 0xb9, .b = 0x50 };
    const danger = Rgb{ .r = 0xf8, .g = 0x51, .b = 0x49 };
    const warn = Rgb{ .r = 0xd2, .g = 0x99, .b = 0x22 };
    const info = Rgb{ .r = 0x58, .g = 0xa6, .b = 0xff };
    const muted = Rgb{ .r = 0x8b, .g = 0x94, .b = 0x9e };
    const surface = Rgb{ .r = 0x30, .g = 0x36, .b = 0x3d };
    const text = Rgb{ .r = 0xe6, .g = 0xed, .b = 0xf3 };
    const text_bright = Rgb{ .r = 0xff, .g = 0xff, .b = 0xff };
};

/// Light-theme truecolor RGB triples (higher contrast on light backgrounds).
const light_rgb = struct {
    const brand = Rgb{ .r = 0xd0, .g = 0x4a, .b = 0x1f };
    const success = Rgb{ .r = 0x1a, .g = 0x7f, .b = 0x37 };
    const danger = Rgb{ .r = 0xcf, .g = 0x22, .b = 0x2e };
    const warn = Rgb{ .r = 0x9a, .g = 0x6a, .b = 0x02 };
    const info = Rgb{ .r = 0x09, .g = 0x69, .b = 0xda };
    const muted = Rgb{ .r = 0x6e, .g = 0x77, .b = 0x81 };
    const surface = Rgb{ .r = 0xd0, .g = 0xd7, .b = 0xde };
    const text = Rgb{ .r = 0x24, .g = 0x29, .b = 0x2f };
    const text_bright = Rgb{ .r = 0x00, .g = 0x00, .b = 0x00 };
};

/// 16-color fallback mapping (matches the dark intent for the common dark default).
const basic16 = struct {
    const brand = "\x1b[33m"; // yellow
    const success = "\x1b[32m"; // green
    const danger = "\x1b[31m"; // red
    const warn = "\x1b[33m"; // yellow
    const info = "\x1b[34m"; // blue
    const muted = "\x1b[2m"; // dim
    const surface = "\x1b[2m"; // dim
    const text = "";
    const text_bright = "\x1b[1m"; // bold
};

fn rgbFor(token: Token, bg: Background) Rgb {
    const use_light = bg == .light;
    return switch (token) {
        .brand => if (use_light) light_rgb.brand else dark_rgb.brand,
        .success => if (use_light) light_rgb.success else dark_rgb.success,
        .danger => if (use_light) light_rgb.danger else dark_rgb.danger,
        .warn => if (use_light) light_rgb.warn else dark_rgb.warn,
        .info => if (use_light) light_rgb.info else dark_rgb.info,
        .muted => if (use_light) light_rgb.muted else dark_rgb.muted,
        .surface => if (use_light) light_rgb.surface else dark_rgb.surface,
        .text => if (use_light) light_rgb.text else dark_rgb.text,
        .text_bright => if (use_light) light_rgb.text_bright else dark_rgb.text_bright,
    };
}

/// Returns the SGR escape sequence for `token` under `cap`/`bg`, or an empty string
/// when no color is available. The caller owns the static-lifetime result.
pub fn sequence(token: Token, cap: Capability, bg: Background) []const u8 {
    return switch (cap) {
        .none => "",
        .basic_16 => switch (token) {
            .brand => basic16.brand,
            .success => basic16.success,
            .danger => basic16.danger,
            .warn => basic16.warn,
            .info => basic16.info,
            .muted => basic16.muted,
            .surface => basic16.surface,
            .text => basic16.text,
            .text_bright => basic16.text_bright,
        },
        .c256 => switch (token) {
            .brand => "\x1b[38;5;208m",
            .success => "\x1b[38;5;40m",
            .danger => "\x1b[38;5;196m",
            .warn => "\x1b[38;5;178m",
            .info => "\x1b[38;5;75m",
            .muted => "\x1b[38;5;245m",
            .surface => "\x1b[38;5;238m",
            .text => "\x1b[38;5;252m",
            .text_bright => "\x1b[38;5;255m",
        },
        .truecolor => blk: {
            const c = rgbFor(token, bg);
            break :blk sgrRgbBuf(c.r, c.g, c.b);
        },
    };
}

// A small static pool of formatted truecolor escapes keyed by (token,bg) is
// overkill; instead format into a module-local ring of static buffers so the
// returned slice is stable for the lifetime of the process.
var rgb_bufs: [16][20]u8 = undefined;
var rgb_idx: usize = 0;

fn sgrRgbBuf(r: u8, g: u8, b: u8) []const u8 {
    const slot = rgb_idx % rgb_bufs.len;
    rgb_idx += 1;
    const buf = &rgb_bufs[slot];
    return std.fmt.bufPrint(buf, "\x1b[38;2;{d};{d};{d}m", .{ r, g, b }) catch "";
}

pub const reset = "\x1b[0m";
pub const bold = "\x1b[1m";
pub const dim = "\x1b[2m";

// ────────────────────────────────────────────────────────────────────────────
// Runtime detection (env + TTY) — cached, guarded for tests
// ────────────────────────────────────────────────────────────────────────────

pub const Active = struct {
    capability: Capability,
    background: Background,
};

var cached: ?Active = null;
var rich_enabled = true;

pub fn setRichEnabled(enabled: bool) void {
    rich_enabled = enabled;
    resetCache();
}

/// Reset the cache. Used by tests; a no-op invoker hook keeps production stable.
pub fn resetCache() void {
    cached = null;
}

/// Pure decision wrapper used by tests and the public detector.
pub fn resolve(d: DetectInput, bg: Background) Active {
    return .{ .capability = detectCapability(d), .background = bg };
}

/// Cached runtime detection against real env/stdout. In `builtin.is_test` this
/// returns a plain-text theme so fixed-buffer writers never emit escapes.
pub fn active(io: std.Io, stdout: anytype) Active {
    if (!rich_enabled) return .{ .capability = .none, .background = .unknown };
    if (builtin.is_test) return .{ .capability = .none, .background = .unknown };
    if (cached) |a| return a;

    const is_tty = detectIsTty(io, stdout);
    const no_color = envPresent("NO_COLOR");
    const term_dumb = envTermDumb();
    const colorterm_truecolor = envColortermTruecolor();
    const term_256color = envTerm256color();
    const bg = detectBackground();

    const a = resolve(.{
        .is_tty = is_tty,
        .no_color = no_color,
        .term_dumb = term_dumb,
        .colorterm_truecolor = colorterm_truecolor,
        .term_256color = term_256color,
    }, bg);
    cached = a;
    return a;
}

fn detectIsTty(io: std.Io, stdout: anytype) bool {
    const Writer = @TypeOf(stdout);
    const is_file = switch (@typeInfo(Writer)) {
        .pointer => |ptr| ptr.child == std.Io.File,
        else => Writer == std.Io.File,
    };
    if (is_file) {
        const file = switch (@typeInfo(Writer)) {
            .pointer => stdout.*,
            else => stdout,
        };
        return file.isTty(io) catch false;
    }
    const is_file_writer = switch (@typeInfo(Writer)) {
        .pointer => |ptr| @hasField(ptr.child, "file") and @hasField(ptr.child, "interface"),
        else => @hasField(Writer, "file") and @hasField(Writer, "interface"),
    };
    if (is_file_writer) {
        const w = switch (@typeInfo(Writer)) {
            .pointer => stdout.*,
            else => stdout,
        };
        return w.file.isTty(io) catch false;
    }
    return std.Io.File.stdout().isTty(io) catch false;
}

fn envPresent(comptime name: [:0]const u8) bool {
    const v = std.c.getenv(name) orelse return false;
    return v[0] != 0;
}

fn envTermDumb() bool {
    const term = std.c.getenv("TERM") orelse return false;
    return std.mem.eql(u8, std.mem.sliceTo(term, 0), "dumb");
}

fn envColortermTruecolor() bool {
    const ct = std.c.getenv("COLORTERM") orelse return false;
    const s = std.mem.sliceTo(ct, 0);
    return std.mem.eql(u8, s, "truecolor") or std.mem.eql(u8, s, "24bit");
}

fn envTerm256color() bool {
    const term = std.c.getenv("TERM") orelse return false;
    const s = std.mem.sliceTo(term, 0);
    return std.mem.indexOf(u8, s, "256color") != null;
}

fn detectBackground() Background {
    const colorfgbg = std.c.getenv("COLORFGBG") orelse return .dark;
    return parseColorfgbg(std.mem.sliceTo(colorfgbg, 0));
}

// ────────────────────────────────────────────────────────────────────────────
// Painting helper: write token + text + reset (only when capable)
// ────────────────────────────────────────────────────────────────────────────

/// Write `text` coloured with `token` followed by a reset, when color is active.
/// When colourless, writes `text` verbatim.
pub fn paint(io: std.Io, stdout: anytype, token: Token, text: []const u8) !void {
    const a = active(io, stdout);
    if (!a.capability.hasColor()) {
        try stdout.writeAll(text);
        return;
    }
    const seq = sequence(token, a.capability, a.background);
    if (seq.len > 0) try stdout.writeAll(seq);
    try stdout.writeAll(text);
    try stdout.writeAll(reset);
}

/// Like `paint` but applies an extra emphasis (`bold`) before the colour.
pub fn paintBold(io: std.Io, stdout: anytype, token: Token, text: []const u8) !void {
    const a = active(io, stdout);
    if (!a.capability.hasColor()) {
        try stdout.writeAll(text);
        return;
    }
    try stdout.writeAll(bold);
    const seq = sequence(token, a.capability, a.background);
    if (seq.len > 0) try stdout.writeAll(seq);
    try stdout.writeAll(text);
    try stdout.writeAll(reset);
}

// ────────────────────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────────────────────

test "detectCapability: non-TTY is none" {
    try std.testing.expectEqual(Capability.none, detectCapability(.{
        .is_tty = false,
        .no_color = false,
        .term_dumb = false,
        .colorterm_truecolor = false,
        .term_256color = false,
    }));
}

test "detectCapability: NO_COLOR forces none even on TTY" {
    try std.testing.expectEqual(Capability.none, detectCapability(.{
        .is_tty = true,
        .no_color = true,
        .term_dumb = false,
        .colorterm_truecolor = true,
        .term_256color = true,
    }));
}

test "detectCapability: TERM=dumb is none" {
    try std.testing.expectEqual(Capability.none, detectCapability(.{
        .is_tty = true,
        .no_color = false,
        .term_dumb = true,
        .colorterm_truecolor = false,
        .term_256color = true,
    }));
}

test "detectCapability: COLORTERM=truecolor wins" {
    try std.testing.expectEqual(Capability.truecolor, detectCapability(.{
        .is_tty = true,
        .no_color = false,
        .term_dumb = false,
        .colorterm_truecolor = true,
        .term_256color = true,
    }));
}

test "detectCapability: 256color TERM" {
    try std.testing.expectEqual(Capability.c256, detectCapability(.{
        .is_tty = true,
        .no_color = false,
        .term_dumb = false,
        .colorterm_truecolor = false,
        .term_256color = true,
    }));
}

test "detectCapability: plain TTY falls back to 16-colour" {
    try std.testing.expectEqual(Capability.basic_16, detectCapability(.{
        .is_tty = true,
        .no_color = false,
        .term_dumb = false,
        .colorterm_truecolor = false,
        .term_256color = false,
    }));
}

test "parseColorfgbg: dark backgrounds" {
    try std.testing.expectEqual(Background.dark, parseColorfgbg("0;0"));
    try std.testing.expectEqual(Background.dark, parseColorfgbg("7;6"));
}

test "parseColorfgbg: light backgrounds" {
    try std.testing.expectEqual(Background.light, parseColorfgbg("0;7"));
    try std.testing.expectEqual(Background.light, parseColorfgbg("15;15"));
}

test "parseColorfgbg: malformed is unknown" {
    try std.testing.expectEqual(Background.unknown, parseColorfgbg("garbage"));
    try std.testing.expectEqual(Background.unknown, parseColorfgbg("0"));
    try std.testing.expectEqual(Background.unknown, parseColorfgbg("0;abc"));
}

test "sequence: none capability emits empty string for every token" {
    inline for (@typeInfo(Token).@"enum".decls) |d| {
        const t = @field(Token, d.name);
        try std.testing.expectEqualStrings("", sequence(t, .none, .dark));
    }
}

test "sequence: 16-colour uses standard escapes" {
    try std.testing.expectEqualStrings("\x1b[31m", sequence(.danger, .basic_16, .dark));
    try std.testing.expectEqualStrings("\x1b[32m", sequence(.success, .basic_16, .dark));
    try std.testing.expectEqualStrings("", sequence(.text, .basic_16, .dark));
}

test "sequence: truecolor emits 38;2;r;g;b" {
    const s = sequence(.brand, .truecolor, .dark);
    try std.testing.expect(std.mem.startsWith(u8, s, "\x1b[38;2;255;122;69m"));
    try std.testing.expect(std.mem.endsWith(u8, s, "m"));
}

test "sequence: 256-color never emits truecolor" {
    const seq = sequence(.brand, .c256, .dark);
    try std.testing.expect(std.mem.indexOf(u8, seq, "38;2;") == null);
    try std.testing.expect(std.mem.indexOf(u8, seq, "38;5;") != null);
}

test "sequence: truecolor light variant differs from dark for brand" {
    const dark = sequence(.brand, .truecolor, .dark);
    const light = sequence(.brand, .truecolor, .light);
    try std.testing.expect(!std.mem.eql(u8, dark, light));
}

test "paint: plain text when capability none" {
    resetCache();
    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try paint(std.testing.io, &w, .danger, "denied");
    try std.testing.expectEqualStrings("denied", w.buffered());
}

test "paintBold: plain text when capability none" {
    resetCache();
    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try paintBold(std.testing.io, &w, .success, "ok");
    try std.testing.expectEqualStrings("ok", w.buffered());
}

test "resolve: composes capability and background (pure)" {
    const a = resolve(.{
        .is_tty = true,
        .no_color = false,
        .term_dumb = false,
        .colorterm_truecolor = true,
        .term_256color = true,
    }, .light);
    try std.testing.expectEqual(Capability.truecolor, a.capability);
    try std.testing.expectEqual(Background.light, a.background);
}

test "Capability.hasColor" {
    try std.testing.expect(!Capability.none.hasColor());
    try std.testing.expect(Capability.basic_16.hasColor());
    try std.testing.expect(Capability.truecolor.hasColor());
}
