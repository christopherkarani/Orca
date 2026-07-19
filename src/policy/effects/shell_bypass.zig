//! Minimal shell/command bypass classifiers for Zig command evaluation paths.
//! When `effects:` is active, these merge into command decisions.
//! Host shell PreToolUse still primarily uses the Rust daemon — document residual gap.

const std = @import("std");
const catalog = @import("catalog.zig");
const ids = @import("ids.zig");
const network_tags = @import("network_tags.zig");

/// Classify a command display string into effect hits (owned slice).
pub fn classifyCommand(allocator: std.mem.Allocator, command_text: []const u8) ![]catalog.EffectHit {
    var hits: std.ArrayList(catalog.EffectHit) = .empty;
    errdefer hits.deinit(allocator);

    const trimmed = std.mem.trim(u8, command_text, " \t\r\n");
    if (trimmed.len == 0) return try hits.toOwnedSlice(allocator);

    if (matchesMailtoOpen(trimmed)) {
        try hits.append(allocator, .{
            .id = "comms.message",
            .confidence = .medium,
            .matcher = "shell_bypass.comms.message.mailto",
        });
    }

    // Optional: curl/wget to tagged hosts
    if (extractCurlLikeUrl(trimmed)) |url| {
        const host = network_tags.hostFromUrlOrHost(url);
        if (network_tags.effectForHost(host)) |tag| {
            // Avoid duplicate effect ids
            var already = false;
            for (hits.items) |h| {
                if (std.mem.eql(u8, h.id, tag.effect_id)) {
                    already = true;
                    break;
                }
            }
            if (!already) {
                const matcher: []const u8 = if (std.mem.eql(u8, tag.effect_id, "comms.publish"))
                    "shell_bypass.comms.publish.curl_host"
                else if (std.mem.eql(u8, tag.effect_id, "comms.message"))
                    "shell_bypass.comms.message.curl_host"
                else
                    "shell_bypass.unknown.external.curl_host";
                try hits.append(allocator, .{
                    .id = tag.effect_id,
                    .confidence = .medium,
                    .matcher = matcher,
                });
            }
        }
    }

    // Optional: osascript Messages
    if (matchesOsascriptMessages(trimmed)) {
        var already = false;
        for (hits.items) |h| {
            if (std.mem.eql(u8, h.id, "comms.message")) {
                already = true;
                break;
            }
        }
        if (!already) {
            try hits.append(allocator, .{
                .id = "comms.message",
                .confidence = .medium,
                .matcher = "shell_bypass.comms.message.osascript_messages",
            });
        }
    }

    for (hits.items) |hit| {
        std.debug.assert(ids.isKnownEffectId(hit.id));
    }
    return try hits.toOwnedSlice(allocator);
}

/// `open mailto:…` / `open 'mailto:…'` / `open "mailto:…"` (case-insensitive open).
fn matchesMailtoOpen(command_text: []const u8) bool {
    // Must contain mailto: (case-insensitive)
    if (indexOfIgnoreCase(command_text, "mailto:") == null) return false;
    // And look like open … mailto
    // Accept: open mailto:, open 'mailto:, open "mailto:, /usr/bin/open mailto:
    if (indexOfIgnoreCase(command_text, "open") == null) return false;
    // Require open to appear before mailto in typical form
    const open_idx = indexOfIgnoreCase(command_text, "open") orelse return false;
    const mail_idx = indexOfIgnoreCase(command_text, "mailto:") orelse return false;
    return open_idx < mail_idx;
}

fn matchesOsascriptMessages(command_text: []const u8) bool {
    if (indexOfIgnoreCase(command_text, "osascript") == null) return false;
    // Messages app reference
    return indexOfIgnoreCase(command_text, "messages") != null;
}

fn indexOfIgnoreCase(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0 or haystack.len < needle.len) return null;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return i;
    }
    return null;
}

/// Best-effort first URL-looking token after curl/wget.
fn extractCurlLikeUrl(command_text: []const u8) ?[]const u8 {
    const lower_is_curl = indexOfIgnoreCase(command_text, "curl") != null or
        indexOfIgnoreCase(command_text, "wget") != null;
    if (!lower_is_curl) return null;

    // Scan for http(s):// token
    if (indexOfIgnoreCase(command_text, "https://")) |idx| {
        return urlTokenAt(command_text, idx);
    }
    if (indexOfIgnoreCase(command_text, "http://")) |idx| {
        return urlTokenAt(command_text, idx);
    }
    return null;
}

fn urlTokenAt(command_text: []const u8, start: usize) []const u8 {
    var end = start;
    while (end < command_text.len) : (end += 1) {
        const c = command_text[end];
        if (c == ' ' or c == '\t' or c == '\'' or c == '"' or c == ')' or c == ';') break;
    }
    return command_text[start..end];
}

test "open mailto classifies as comms.message" {
    const hits = try classifyCommand(std.testing.allocator, "open 'mailto:x@y.com'");
    defer std.testing.allocator.free(hits);
    try std.testing.expect(hits.len >= 1);
    try std.testing.expectEqualStrings("comms.message", hits[0].id);
    try std.testing.expectEqualStrings("shell_bypass.comms.message.mailto", hits[0].matcher);
}

test "open mailto without quotes" {
    const hits = try classifyCommand(std.testing.allocator, "open mailto:alice@example.com?subject=hi");
    defer std.testing.allocator.free(hits);
    try std.testing.expect(hits.len >= 1);
    try std.testing.expect(std.mem.startsWith(u8, hits[0].matcher, "shell_bypass."));
}

test "unrelated command has no shell bypass hits" {
    const hits = try classifyCommand(std.testing.allocator, "git status");
    defer std.testing.allocator.free(hits);
    try std.testing.expectEqual(@as(usize, 0), hits.len);
}

test "curl to twitter host is publish" {
    const hits = try classifyCommand(std.testing.allocator, "curl -X POST https://api.twitter.com/2/tweets");
    defer std.testing.allocator.free(hits);
    try std.testing.expect(hits.len >= 1);
    try std.testing.expectEqualStrings("comms.publish", hits[0].id);
    try std.testing.expect(std.mem.startsWith(u8, hits[0].matcher, "shell_bypass."));
}
