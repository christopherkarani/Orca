//! Stable effect IDs for effect-class policy.
//! These strings are the user-facing vocabulary in policy YAML.

const std = @import("std");

/// Canonical effect identifiers. Policy authors use these strings (and `namespace.*` wildcards).
pub const known_ids = [_][]const u8{
    "shell.exec",
    "fs.read",
    "fs.write",
    "net.connect",
    "comms.message",
    "comms.publish",
    "comms.calendar",
    "identity.auth",
    "money.transfer",
    "code.mutate_remote",
    "secrets.read",
    "device.control",
    "unknown.external",
};

pub fn isKnownEffectId(id: []const u8) bool {
    for (known_ids) |known| {
        if (std.mem.eql(u8, known, id)) return true;
    }
    return false;
}

/// Valid policy patterns: a known effect id, or `prefix.*` that covers at least one known id.
pub fn isValidEffectPattern(pattern: []const u8) bool {
    if (pattern.len == 0) return false;
    if (isKnownEffectId(pattern)) return true;
    if (std.mem.endsWith(u8, pattern, ".*")) {
        const prefix = pattern[0 .. pattern.len - 1]; // keep trailing '.' for startsWith
        if (prefix.len == 0) return false;
        for (known_ids) |known| {
            if (std.mem.startsWith(u8, known, prefix)) return true;
        }
        return false;
    }
    return false;
}

/// Whether `effect_id` is matched by a policy pattern (exact or `namespace.*`).
pub fn matchesPolicyPattern(effect_id: []const u8, pattern: []const u8) bool {
    if (std.mem.eql(u8, effect_id, pattern)) return true;
    if (std.mem.endsWith(u8, pattern, ".*")) {
        const prefix = pattern[0 .. pattern.len - 1]; // e.g. "comms."
        return std.mem.startsWith(u8, effect_id, prefix);
    }
    return false;
}

test "known effect ids are recognized" {
    try std.testing.expect(isKnownEffectId("comms.message"));
    try std.testing.expect(isKnownEffectId("comms.publish"));
    try std.testing.expect(isKnownEffectId("money.transfer"));
    try std.testing.expect(!isKnownEffectId("comms"));
    try std.testing.expect(!isKnownEffectId(""));
    try std.testing.expect(!isKnownEffectId("comms.unknown"));
}

test "effect patterns accept wildcards that cover known ids" {
    try std.testing.expect(isValidEffectPattern("comms.message"));
    try std.testing.expect(isValidEffectPattern("comms.*"));
    try std.testing.expect(isValidEffectPattern("fs.*"));
    try std.testing.expect(!isValidEffectPattern("nope.*"));
    try std.testing.expect(!isValidEffectPattern(".*"));
    try std.testing.expect(!isValidEffectPattern(""));
    try std.testing.expect(!isValidEffectPattern("comms.messag"));
}

test "matchesPolicyPattern exact and wildcard" {
    try std.testing.expect(matchesPolicyPattern("comms.message", "comms.message"));
    try std.testing.expect(matchesPolicyPattern("comms.message", "comms.*"));
    try std.testing.expect(matchesPolicyPattern("comms.publish", "comms.*"));
    try std.testing.expect(!matchesPolicyPattern("money.transfer", "comms.*"));
    try std.testing.expect(!matchesPolicyPattern("comms.message", "comms.publish"));
}
