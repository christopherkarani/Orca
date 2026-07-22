//! PCRE2 bindings for shell pack pattern matching.
const std = @import("std");
const c = @cImport({
    @cInclude("pcre2_shim.h");
});

pub const Regex = struct {
    ptr: *c.orca_regex,

    pub fn compile(pattern: []const u8) !Regex {
        var err_code: c_int = 0;
        var err_off: usize = 0;
        const p = c.orca_regex_compile(pattern.ptr, pattern.len, &err_code, &err_off);
        if (p == null) return error.CompileFailed;
        return .{ .ptr = p.? };
    }

    pub fn deinit(self: *Regex) void {
        c.orca_regex_free(self.ptr);
        self.* = undefined;
    }

    pub fn isMatch(self: *const Regex, text: []const u8) bool {
        return c.orca_regex_is_match(self.ptr, text.ptr, text.len) != 0;
    }
};

test "pcre2 matches git reset" {
    var re = try Regex.compile("(?:^|[^[:alnum:]_-])git\\s+(?:\\S+\\s+)*reset\\s+--hard");
    defer re.deinit();
    try std.testing.expect(re.isMatch("git reset --hard"));
    try std.testing.expect(re.isMatch("/usr/bin/git reset --hard"));
    try std.testing.expect(re.isMatch("sudo git reset --hard"));
}
