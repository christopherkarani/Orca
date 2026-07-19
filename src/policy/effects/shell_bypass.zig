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

    // curl/wget to tagged hosts (scheme or bare host operand)
    if (extractCurlLikeHost(trimmed)) |host| {
        if (network_tags.effectForHost(host)) |tag| {
            if (!hasEffectId(hits.items, tag.effect_id)) {
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

    if (matchesOsascriptMessages(trimmed)) {
        if (!hasEffectId(hits.items, "comms.message")) {
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

fn hasEffectId(hits: []const catalog.EffectHit, id: []const u8) bool {
    for (hits) |h| {
        if (std.mem.eql(u8, h.id, id)) return true;
    }
    return false;
}

/// `open` / `/usr/bin/open` as a command token with a following `mailto:` arg.
fn matchesMailtoOpen(command_text: []const u8) bool {
    var tokens: [32][]const u8 = undefined;
    const n = tokenizeSimple(command_text, &tokens);
    if (n < 2) return false;

    var i: usize = 0;
    while (i + 1 < n) : (i += 1) {
        if (!isOpenToken(tokens[i])) continue;
        // Next non-flag-like token should start with mailto:
        var j = i + 1;
        while (j < n) : (j += 1) {
            const t = tokens[j];
            if (t.len > 0 and t[0] == '-') continue; // skip -a Mail etc. loosely
            return startsWithIgnoreCase(t, "mailto:");
        }
    }
    return false;
}

fn isOpenToken(token: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(token, "open")) return true;
    // path form: .../open
    if (std.mem.lastIndexOfScalar(u8, token, '/')) |slash| {
        return std.ascii.eqlIgnoreCase(token[slash + 1 ..], "open");
    }
    return false;
}

fn startsWithIgnoreCase(haystack: []const u8, prefix: []const u8) bool {
    if (haystack.len < prefix.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[0..prefix.len], prefix);
}

fn matchesOsascriptMessages(command_text: []const u8) bool {
    var tokens: [32][]const u8 = undefined;
    const n = tokenizeSimple(command_text, &tokens);
    var has_osascript = false;
    var has_messages = false;
    for (tokens[0..n]) |t| {
        if (std.ascii.eqlIgnoreCase(t, "osascript") or endsWithIgnoreCase(t, "/osascript")) {
            has_osascript = true;
        }
        if (std.ascii.eqlIgnoreCase(t, "messages") or indexOfIgnoreCase(t, "messages") != null) {
            has_messages = true;
        }
    }
    return has_osascript and has_messages;
}

fn endsWithIgnoreCase(haystack: []const u8, suffix: []const u8) bool {
    if (haystack.len < suffix.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[haystack.len - suffix.len ..], suffix);
}

fn indexOfIgnoreCase(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0 or haystack.len < needle.len) return null;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return i;
    }
    return null;
}

/// Whitespace tokenizer with simple single/double quote stripping (no escapes).
fn tokenizeSimple(command_text: []const u8, out: [][]const u8) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i < command_text.len and count < out.len) {
        while (i < command_text.len and (command_text[i] == ' ' or command_text[i] == '\t' or command_text[i] == '\n' or command_text[i] == '\r')) : (i += 1) {}
        if (i >= command_text.len) break;

        if (command_text[i] == '\'' or command_text[i] == '"') {
            const quote = command_text[i];
            i += 1;
            const start = i;
            while (i < command_text.len and command_text[i] != quote) : (i += 1) {}
            out[count] = command_text[start..i];
            count += 1;
            if (i < command_text.len) i += 1;
            continue;
        }

        const start = i;
        while (i < command_text.len and command_text[i] != ' ' and command_text[i] != '\t' and command_text[i] != '\n' and command_text[i] != '\r') : (i += 1) {}
        out[count] = command_text[start..i];
        count += 1;
    }
    return count;
}

/// Best-effort host from curl/wget: first http(s) URL or bare host-looking operand.
fn extractCurlLikeHost(command_text: []const u8) ?[]const u8 {
    var tokens: [32][]const u8 = undefined;
    const n = tokenizeSimple(command_text, &tokens);
    if (n == 0) return null;

    var is_curl = false;
    for (tokens[0..n]) |t| {
        if (std.ascii.eqlIgnoreCase(t, "curl") or std.ascii.eqlIgnoreCase(t, "wget") or
            endsWithIgnoreCase(t, "/curl") or endsWithIgnoreCase(t, "/wget"))
        {
            is_curl = true;
            break;
        }
    }
    if (!is_curl) return null;

    // Prefer explicit http(s) URL token
    for (tokens[0..n]) |t| {
        if (startsWithIgnoreCase(t, "https://") or startsWithIgnoreCase(t, "http://")) {
            return network_tags.hostFromUrlOrHost(t);
        }
    }
    // --url value
    var i: usize = 0;
    while (i + 1 < n) : (i += 1) {
        if (std.mem.eql(u8, tokens[i], "--url") or std.mem.eql(u8, tokens[i], "-url")) {
            return network_tags.hostFromUrlOrHost(tokens[i + 1]);
        }
    }
    // Bare host-looking tokens (contain a dot, not a flag)
    for (tokens[0..n]) |t| {
        if (t.len == 0 or t[0] == '-') continue;
        if (std.ascii.eqlIgnoreCase(t, "curl") or std.ascii.eqlIgnoreCase(t, "wget")) continue;
        if (std.mem.indexOfScalar(u8, t, '.') == null) continue;
        const host = network_tags.hostFromUrlOrHost(t);
        if (network_tags.effectForHost(host) != null) return host;
    }
    return null;
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

test "incidental open in text is not mailto bypass" {
    const hits = try classifyCommand(std.testing.allocator, "echo 'please open mailto:x@y.com'");
    defer std.testing.allocator.free(hits);
    try std.testing.expectEqual(@as(usize, 0), hits.len);
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

test "curl bare tagged host is publish" {
    const hits = try classifyCommand(std.testing.allocator, "curl -X POST api.twitter.com/2/tweets");
    defer std.testing.allocator.free(hits);
    try std.testing.expect(hits.len >= 1);
    try std.testing.expectEqualStrings("comms.publish", hits[0].id);
}
