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
        const pattern_ptr: [*]const u8 = if (pattern.len == 0) "".ptr else pattern.ptr;
        const p = c.orca_regex_compile(pattern_ptr, pattern.len, &err_code, &err_off);
        if (p == null) return error.CompileFailed;
        return .{ .ptr = p.? };
    }

    pub fn deinit(self: *Regex) void {
        c.orca_regex_free(self.ptr);
        self.* = undefined;
    }

    /// Returns true on match, false on no-match.
    /// Infrastructure / PCRE match errors return `error.MatchInfrastructure` (fail closed).
    pub fn isMatch(self: *const Regex, text: []const u8) !bool {
        const text_ptr: [*]const u8 = if (text.len == 0) "".ptr else text.ptr;
        const rc = c.orca_regex_is_match(self.ptr, text_ptr, text.len);
        if (rc > 0) return true;
        if (rc == 0) return false;
        return error.MatchInfrastructure;
    }
};

test "pcre2 matches git reset" {
    var re = try Regex.compile("(?:^|[^[:alnum:]_-])git\\s+(?:\\S+\\s+)*reset\\s+--hard");
    defer re.deinit();
    try std.testing.expect(try re.isMatch("git reset --hard"));
    try std.testing.expect(try re.isMatch("/usr/bin/git reset --hard"));
    try std.testing.expect(try re.isMatch("sudo git reset --hard"));
    try std.testing.expect(!(try re.isMatch("echo hello")));
}
