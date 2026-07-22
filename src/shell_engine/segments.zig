//! Split shell commands into evaluation segments (`;`, `&&`, `||`, `|`, …)
//! and extract command substitutions / backticks so safe outer commands
//! cannot hide destructive inner ones.
const std = @import("std");

/// Append trimmed non-empty segments of `cmd` into `out`.
/// Caller owns items only if they are allocator-duped; here we return slices into `cmd`.
pub fn splitCommandSegments(cmd: []const u8, allocator: std.mem.Allocator) ![][]const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    errdefer list.deinit(allocator);
    try collect(cmd, 0, cmd.len, 0, true, allocator, &list);
    if (list.items.len == 0) {
        const t = std.mem.trim(u8, cmd, " \t\r\n");
        if (t.len > 0) try list.append(allocator, t);
    }
    return try list.toOwnedSlice(allocator);
}

pub fn freeSegments(allocator: std.mem.Allocator, segs: [][]const u8) void {
    allocator.free(segs);
}

const MAX_RECURSION: usize = 64;

fn collect(
    cmd: []const u8,
    start: usize,
    end: usize,
    depth: usize,
    emit_plain: bool,
    allocator: std.mem.Allocator,
    out: *std.ArrayList([]const u8),
) !void {
    if (depth > MAX_RECURSION) {
        if (emit_plain) try pushTrimmed(cmd, start, end, allocator, out);
        return;
    }
    var segment_start = start;
    var i = start;
    var in_single = false;
    var in_double = false;

    while (i < end) {
        const b = cmd[i];
        if (b == '\\' and !in_single and i + 1 < end) {
            i += 2;
            continue;
        }
        if (b == '\'' and !in_double) {
            in_single = !in_single;
            i += 1;
            continue;
        }
        if (b == '"' and !in_single) {
            in_double = !in_double;
            i += 1;
            continue;
        }

        if (!in_single and b == '$' and i + 2 < end and cmd[i + 1] == '(' and cmd[i + 2] == '(') {
            if (findMatching(cmd, i + 3, end, '(', ')')) |close| {
                try collect(cmd, i + 3, close, depth + 1, false, allocator, out);
                i = close + 2;
                continue;
            }
        }
        if (!in_single and b == '$' and i + 1 < end and cmd[i + 1] == '(') {
            if (findMatching(cmd, i + 2, end, '(', ')')) |close| {
                try collect(cmd, i + 2, close, depth + 1, true, allocator, out);
                i = close + 1;
                continue;
            }
        }
        if (!in_single and !in_double and (b == '<' or b == '>') and i + 1 < end and cmd[i + 1] == '(') {
            if (findMatching(cmd, i + 2, end, '(', ')')) |close| {
                try collect(cmd, i + 2, close, depth + 1, true, allocator, out);
                i = close + 1;
                continue;
            }
        }
        if (!in_single and b == '`') {
            if (findBacktick(cmd, i + 1, end)) |close| {
                try collect(cmd, i + 1, close, depth + 1, true, allocator, out);
                i = close + 1;
                continue;
            }
        }

        if (in_single or in_double) {
            i += 1;
            continue;
        }

        // Unquoted shell comments: rest of line is not active syntax.
        if (b == '#') {
            while (i < end and cmd[i] != '\n') : (i += 1) {}
            continue;
        }

        const split_w: ?usize = blk: {
            if (b == ';' or b == '\n') break :blk 1;
            if (b == '&') {
                if (isRedirAmp(cmd, i)) break :blk null;
                if (i + 1 < end and cmd[i + 1] == '&') break :blk 2;
                break :blk 1;
            }
            if (b == '|') {
                if (i + 1 < end and (cmd[i + 1] == '|' or cmd[i + 1] == '&')) break :blk 2;
                break :blk 1;
            }
            break :blk null;
        };

        if (split_w) |w| {
            if (emit_plain) try pushTrimmed(cmd, segment_start, i, allocator, out);
            i += w;
            segment_start = i;
            continue;
        }
        i += 1;
    }
    if (emit_plain) try pushTrimmed(cmd, segment_start, end, allocator, out);
}

fn pushTrimmed(cmd: []const u8, start: usize, end: usize, allocator: std.mem.Allocator, out: *std.ArrayList([]const u8)) !void {
    if (start >= end) return;
    const t = std.mem.trim(u8, cmd[start..end], " \t\r\n");
    if (t.len == 0) return;
    try out.append(allocator, t);
}

fn findMatching(cmd: []const u8, start: usize, end: usize, open: u8, close: u8) ?usize {
    var depth: usize = 1;
    var i = start;
    var in_single = false;
    var in_double = false;
    while (i < end) {
        const b = cmd[i];
        if (b == '\\' and !in_single and i + 1 < end) {
            i += 2;
            continue;
        }
        if (b == '\'' and !in_double) {
            in_single = !in_single;
            i += 1;
            continue;
        }
        if (b == '"' and !in_single) {
            in_double = !in_double;
            i += 1;
            continue;
        }
        if (!in_single and !in_double) {
            if (b == open) depth += 1;
            if (b == close) {
                depth -= 1;
                if (depth == 0) return i;
            }
        }
        i += 1;
    }
    return null;
}

fn findBacktick(cmd: []const u8, start: usize, end: usize) ?usize {
    var i = start;
    while (i < end) {
        if (cmd[i] == '\\' and i + 1 < end) {
            i += 2;
            continue;
        }
        if (cmd[i] == '`') return i;
        i += 1;
    }
    return null;
}

fn isRedirAmp(cmd: []const u8, i: usize) bool {
    // `>&` or `&>` or `n>&`
    if (i > 0 and cmd[i - 1] == '>') return true;
    if (i + 1 < cmd.len and cmd[i + 1] == '>') return true;
    return false;
}

test "split multi-segment" {
    const segs = try splitCommandSegments("git status; rm -rf /", std.testing.allocator);
    defer freeSegments(std.testing.allocator, segs);
    try std.testing.expectEqual(@as(usize, 2), segs.len);
    try std.testing.expectEqualStrings("git status", segs[0]);
    try std.testing.expectEqualStrings("rm -rf /", segs[1]);
}

test "split extracts command substitution" {
    const segs = try splitCommandSegments("echo $(git reset --hard)", std.testing.allocator);
    defer freeSegments(std.testing.allocator, segs);
    try std.testing.expect(segs.len >= 1);
    var found = false;
    for (segs) |s| {
        if (std.mem.indexOf(u8, s, "git reset") != null) found = true;
    }
    try std.testing.expect(found);
}
