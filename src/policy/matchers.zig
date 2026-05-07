const std = @import("std");

pub fn matchesPattern(pattern: []const u8, value: []const u8) bool {
    if (std.mem.eql(u8, pattern, value)) return true;
    return globMatch(pattern, value);
}

pub fn matchesPath(pattern: []const u8, path: []const u8) bool {
    if (matchesPattern(pattern, path)) return true;
    if (std.mem.startsWith(u8, pattern, "~/") and std.mem.startsWith(u8, path, "~/")) {
        return globMatch(pattern, path);
    }
    if (std.mem.startsWith(u8, pattern, "~/")) {
        const home = std.process.getEnvVarOwned(std.heap.page_allocator, "HOME") catch return false;
        defer std.heap.page_allocator.free(home);
        if (std.mem.startsWith(u8, path, home)) {
            const suffix = path[home.len..];
            if (suffix.len == 0) return globMatch(pattern, "~");
            if (std.mem.startsWith(u8, suffix, "/")) {
                var stack_buf: [4096]u8 = undefined;
                if (suffix.len + 1 <= stack_buf.len) {
                    stack_buf[0] = '~';
                    @memcpy(stack_buf[1 .. suffix.len + 1], suffix);
                    return globMatch(pattern, stack_buf[0 .. suffix.len + 1]);
                }
            }
        }
    }
    return false;
}

pub fn matchesCommand(pattern: []const u8, command: []const u8) bool {
    return matchesPattern(pattern, command);
}

pub fn matchesDomain(pattern: []const u8, host: []const u8) bool {
    const normalized_pattern = trimTrailingDot(pattern);
    const normalized_host = trimTrailingDot(host);
    if (std.ascii.eqlIgnoreCase(normalized_pattern, normalized_host)) return true;
    if (std.mem.startsWith(u8, normalized_pattern, "*.")) {
        const suffix = normalized_pattern[1..];
        return normalized_host.len > suffix.len and
            std.ascii.endsWithIgnoreCase(normalized_host, suffix);
    }
    return globMatchAsciiCaseInsensitive(normalized_pattern, normalized_host);
}

pub fn matchesMcpSelector(pattern: []const u8, selector: []const u8) bool {
    return matchesPattern(pattern, selector);
}

fn trimTrailingDot(value: []const u8) []const u8 {
    if (value.len > 0 and value[value.len - 1] == '.') return value[0 .. value.len - 1];
    return value;
}

fn globMatch(pattern: []const u8, value: []const u8) bool {
    return globMatchAt(pattern, 0, value, 0);
}

fn globMatchAt(pattern: []const u8, pattern_index: usize, value: []const u8, value_index: usize) bool {
    var p = pattern_index;
    var v = value_index;
    while (p < pattern.len) {
        switch (pattern[p]) {
            '*' => {
                while (p + 1 < pattern.len and pattern[p + 1] == '*') p += 1;
                if (p + 1 == pattern.len) return true;
                var next = v;
                while (next <= value.len) : (next += 1) {
                    if (globMatchAt(pattern, p + 1, value, next)) return true;
                }
                return false;
            },
            '?' => {
                if (v >= value.len) return false;
                p += 1;
                v += 1;
            },
            else => |char| {
                if (v >= value.len or value[v] != char) return false;
                p += 1;
                v += 1;
            },
        }
    }
    return v == value.len;
}

fn globMatchAsciiCaseInsensitive(pattern: []const u8, value: []const u8) bool {
    return globMatchAsciiCaseInsensitiveAt(pattern, 0, value, 0);
}

fn globMatchAsciiCaseInsensitiveAt(pattern: []const u8, pattern_index: usize, value: []const u8, value_index: usize) bool {
    var p = pattern_index;
    var v = value_index;
    while (p < pattern.len) {
        switch (pattern[p]) {
            '*' => {
                while (p + 1 < pattern.len and pattern[p + 1] == '*') p += 1;
                if (p + 1 == pattern.len) return true;
                var next = v;
                while (next <= value.len) : (next += 1) {
                    if (globMatchAsciiCaseInsensitiveAt(pattern, p + 1, value, next)) return true;
                }
                return false;
            },
            '?' => {
                if (v >= value.len) return false;
                p += 1;
                v += 1;
            },
            else => |char| {
                if (v >= value.len or std.ascii.toLower(value[v]) != std.ascii.toLower(char)) return false;
                p += 1;
                v += 1;
            },
        }
    }
    return v == value.len;
}

test "glob matcher supports exact wildcard and path-ish rules" {
    try std.testing.expect(matchesPattern("git diff *", "git diff src/main.zig"));
    try std.testing.expect(matchesPath("./**", "./src/main.zig"));
    try std.testing.expect(matchesPath("~/.ssh/**", "~/.ssh/id_ed25519"));
    try std.testing.expect(!matchesPath("./.env", "./.env.local"));
}

test "domain and mcp selector matchers support wildcards" {
    try std.testing.expect(matchesDomain("*.github.com", "api.github.com"));
    try std.testing.expect(!matchesDomain("*.github.com", "github.com"));
    try std.testing.expect(matchesDomain("API.GITHUB.COM", "api.github.com"));
    try std.testing.expect(matchesMcpSelector("filesystem.*", "filesystem.read_file"));
}
