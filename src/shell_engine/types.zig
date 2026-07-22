//! Shared shell-engine types (avoid circular imports between mod and packs).

pub const Decision = enum {
    allow,
    deny,

    pub fn toString(self: Decision) []const u8 {
        return @tagName(self);
    }
};

pub const Severity = enum {
    critical,
    high,
    medium,
    low,

    pub fn toString(self: Severity) []const u8 {
        return @tagName(self);
    }
};
