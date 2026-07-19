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

    // curl/wget: inspect every URL / tagged host operand (not only the first).
    try appendCurlLikeHostEffects(allocator, trimmed, &hits);

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

fn appendCurlHostHit(
    allocator: std.mem.Allocator,
    hits: *std.ArrayList(catalog.EffectHit),
    host: []const u8,
) !void {
    const tag = network_tags.effectForHost(host) orelse return;
    if (hasEffectId(hits.items, tag.effect_id)) return;
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

/// `open` / `/usr/bin/open` in command position with a following `mailto:` operand.
fn matchesMailtoOpen(command_text: []const u8) bool {
    var tokens: [48][]const u8 = undefined;
    const n = tokenizeSimple(command_text, &tokens);
    if (n < 2) return false;

    var i: usize = 0;
    while (i + 1 < n) : (i += 1) {
        if (!isOpenToken(tokens[i])) continue;
        if (!isCommandPosition(tokens[0..n], i)) continue;

        // Walk past macOS `open` options (including value-taking flags like -a/-b).
        var j = i + 1;
        while (j < n) {
            if (isShellOperator(tokens[j])) break;
            const t = tokens[j];
            if (t.len > 0 and t[0] == '-') {
                if (openFlagConsumesNext(t)) {
                    j += 1; // flag
                    if (j < n and !isShellOperator(tokens[j]) and !(tokens[j].len > 0 and tokens[j][0] == '-')) {
                        j += 1; // option value (e.g. Mail)
                    }
                    continue;
                }
                j += 1; // boolean flag
                continue;
            }
            return startsWithIgnoreCase(t, "mailto:");
        }
    }
    return false;
}

/// macOS `open` flags that take a following value argument.
fn openFlagConsumesNext(token: []const u8) bool {
    return std.mem.eql(u8, token, "-a") or
        std.mem.eql(u8, token, "-b") or
        std.mem.eql(u8, token, "-s") or
        std.mem.eql(u8, token, "--args");
}

fn isOpenToken(token: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(token, "open")) return true;
    if (std.mem.lastIndexOfScalar(u8, token, '/')) |slash| {
        return std.ascii.eqlIgnoreCase(token[slash + 1 ..], "open");
    }
    return false;
}

fn isCurlLikeToken(token: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(token, "curl") or std.ascii.eqlIgnoreCase(token, "wget")) return true;
    if (endsWithIgnoreCase(token, "/curl") or endsWithIgnoreCase(token, "/wget")) return true;
    return false;
}

/// True when `index` is the first executable of a shell command segment:
/// start of segment, after `;`/`|`/`&&`/`||`/`&`, after env assignments, or after
/// common wrappers (`sudo`, `env`, `command`, `nohup`, `nice`, `time`).
fn isCommandPosition(tokens: []const []const u8, index: usize) bool {
    if (index == 0) return true;
    // Walk left through env assignments and wrapper prefixes.
    var i = index;
    while (i > 0) {
        const prev = tokens[i - 1];
        if (isShellOperator(prev)) return true;
        if (isEnvAssignment(prev) or isCommandWrapper(prev)) {
            i -= 1;
            continue;
        }
        return false;
    }
    return true;
}

fn isEnvAssignment(token: []const u8) bool {
    // FOO=bar (simple shell assignment; not PATH-style with /).
    if (token.len < 2) return false;
    const eq = std.mem.indexOfScalar(u8, token, '=') orelse return false;
    if (eq == 0) return false;
    for (token[0..eq]) |c| {
        if (!(std.ascii.isAlphanumeric(c) or c == '_')) return false;
    }
    return true;
}

fn isCommandWrapper(token: []const u8) bool {
    const wrappers = [_][]const u8{ "sudo", "env", "command", "nohup", "nice", "time", "builtin" };
    // Strip path prefix: /usr/bin/sudo
    var base = token;
    if (std.mem.lastIndexOfScalar(u8, token, '/')) |slash| base = token[slash + 1 ..];
    for (wrappers) |w| {
        if (std.ascii.eqlIgnoreCase(base, w)) return true;
    }
    return false;
}

fn isShellOperator(token: []const u8) bool {
    return std.mem.eql(u8, token, ";") or
        std.mem.eql(u8, token, "|") or
        std.mem.eql(u8, token, "&&") or
        std.mem.eql(u8, token, "||") or
        std.mem.eql(u8, token, "&");
}

fn startsWithIgnoreCase(haystack: []const u8, prefix: []const u8) bool {
    if (haystack.len < prefix.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[0..prefix.len], prefix);
}

fn matchesOsascriptMessages(command_text: []const u8) bool {
    var tokens: [48][]const u8 = undefined;
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

/// Whitespace tokenizer with quote stripping; also emits shell operators as tokens
/// and splits attached operators (e.g. `decoy;` → `decoy`, `;`).
fn tokenizeSimple(command_text: []const u8, out: [][]const u8) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i < command_text.len and count < out.len) {
        while (i < command_text.len and isSpace(command_text[i])) : (i += 1) {}
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

        // Shell operators as their own tokens (including && and ||).
        if (tryEmitOperator(command_text, &i, out, &count)) continue;

        const start = i;
        while (i < command_text.len and !isSpace(command_text[i]) and !isOperatorStart(command_text, i)) : (i += 1) {}
        if (i > start) {
            out[count] = command_text[start..i];
            count += 1;
        }
    }
    return count;
}

fn isSpace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

fn isOperatorStart(text: []const u8, i: usize) bool {
    const c = text[i];
    return c == ';' or c == '|' or c == '&';
}

fn tryEmitOperator(text: []const u8, i: *usize, out: [][]const u8, count: *usize) bool {
    if (count.* >= out.len or i.* >= text.len) return false;
    const c = text[i.*];
    if (c == ';') {
        out[count.*] = text[i.* .. i.* + 1];
        count.* += 1;
        i.* += 1;
        return true;
    }
    if (c == '|' or c == '&') {
        if (i.* + 1 < text.len and text[i.* + 1] == c) {
            out[count.*] = text[i.* .. i.* + 2];
            count.* += 1;
            i.* += 2;
            return true;
        }
        out[count.*] = text[i.* .. i.* + 1];
        count.* += 1;
        i.* += 1;
        return true;
    }
    return false;
}

/// Append effect hits for every curl/wget URL / tagged host operand in command position.
fn appendCurlLikeHostEffects(
    allocator: std.mem.Allocator,
    command_text: []const u8,
    hits: *std.ArrayList(catalog.EffectHit),
) !void {
    var tokens: [48][]const u8 = undefined;
    const n = tokenizeSimple(command_text, &tokens);
    if (n == 0) return;

    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (!isCurlLikeToken(tokens[i])) continue;
        if (!isCommandPosition(tokens[0..n], i)) continue;

        // Scan operands until next shell operator.
        var j = i + 1;
        while (j < n) : (j += 1) {
            if (isShellOperator(tokens[j])) break;
            const t = tokens[j];
            if (t.len == 0) continue;

            // --url / -url VALUE
            if ((std.mem.eql(u8, t, "--url") or std.mem.eql(u8, t, "-url")) and j + 1 < n) {
                const host = network_tags.hostFromUrlOrHost(tokens[j + 1]);
                try appendCurlHostHit(allocator, hits, host);
                j += 1;
                continue;
            }

            if (t[0] == '-') continue; // other flags (value args may look host-like; skip flags only)

            if (startsWithIgnoreCase(t, "https://") or startsWithIgnoreCase(t, "http://")) {
                const host = network_tags.hostFromUrlOrHost(t);
                try appendCurlHostHit(allocator, hits, host);
                continue;
            }

            // Bare host-looking tokens that match a curated tag.
            if (std.mem.indexOfScalar(u8, t, '.') != null) {
                const host = network_tags.hostFromUrlOrHost(t);
                try appendCurlHostHit(allocator, hits, host);
            }
        }
    }
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

test "open -a Mail mailto still classifies" {
    const hits = try classifyCommand(std.testing.allocator, "open -a Mail mailto:x@y.com");
    defer std.testing.allocator.free(hits);
    try std.testing.expect(hits.len >= 1);
    try std.testing.expectEqualStrings("comms.message", hits[0].id);
}

test "open -b bundle mailto still classifies" {
    const hits = try classifyCommand(std.testing.allocator, "open -b com.apple.mail mailto:x@y.com");
    defer std.testing.allocator.free(hits);
    try std.testing.expect(hits.len >= 1);
    try std.testing.expectEqualStrings("comms.message", hits[0].id);
}

test "decoy mailto before real open still classifies" {
    const hits = try classifyCommand(std.testing.allocator, "echo mailto:decoy; open mailto:x@y.com");
    defer std.testing.allocator.free(hits);
    try std.testing.expect(hits.len >= 1);
    try std.testing.expectEqualStrings("comms.message", hits[0].id);
}

test "incidental open in text is not mailto bypass" {
    const hits = try classifyCommand(std.testing.allocator, "echo 'please open mailto:x@y.com'");
    defer std.testing.allocator.free(hits);
    try std.testing.expectEqual(@as(usize, 0), hits.len);
}

test "printf open mailto args is not mailto bypass" {
    // open/mailto appear as data operands, not as a command launch.
    const hits = try classifyCommand(std.testing.allocator, "printf '%s %s' open mailto:x@y.com");
    defer std.testing.allocator.free(hits);
    try std.testing.expectEqual(@as(usize, 0), hits.len);
}

test "sudo open mailto still classifies" {
    const hits = try classifyCommand(std.testing.allocator, "sudo open mailto:x@y.com");
    defer std.testing.allocator.free(hits);
    try std.testing.expect(hits.len >= 1);
    try std.testing.expectEqualStrings("comms.message", hits[0].id);
}

test "env assignment before open mailto still classifies" {
    const hits = try classifyCommand(std.testing.allocator, "FOO=1 open mailto:x@y.com");
    defer std.testing.allocator.free(hits);
    try std.testing.expect(hits.len >= 1);
    try std.testing.expectEqualStrings("comms.message", hits[0].id);
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

test "curl multi-URL second tagged host still hits" {
    // First URL is untagged; second is a publish host — must still classify.
    const hits = try classifyCommand(
        std.testing.allocator,
        "curl https://example.com https://api.twitter.com/2/tweets",
    );
    defer std.testing.allocator.free(hits);
    try std.testing.expect(hits.len >= 1);
    try std.testing.expectEqualStrings("comms.publish", hits[0].id);
}

test "curl --url tagged host hits" {
    const hits = try classifyCommand(std.testing.allocator, "curl --url https://api.twitter.com/2/tweets");
    defer std.testing.allocator.free(hits);
    try std.testing.expect(hits.len >= 1);
    try std.testing.expectEqualStrings("comms.publish", hits[0].id);
}
