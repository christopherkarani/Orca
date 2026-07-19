//! Host/domain → effect tags for network evaluation and structural URL scans.
//! Deterministic static tables only (no LLM). Shared by structural value shapes
//! and evaluate.network merge when `effects:` is active.

const std = @import("std");
const catalog = @import("catalog.zig");
const ids = @import("ids.zig");

const HostTag = struct {
    /// Exact host or parent-domain match (e.g. `twitter.com` matches `api.twitter.com`).
    host: []const u8,
    effect_id: []const u8,
    matcher: []const u8,
};

/// Curated messaging / publish API hosts. Extend carefully to limit false positives.
const host_tags = [_]HostTag{
    // comms.publish
    .{ .host = "api.twitter.com", .effect_id = "comms.publish", .matcher = "network_tag.comms.publish:api.twitter.com" },
    .{ .host = "twitter.com", .effect_id = "comms.publish", .matcher = "network_tag.comms.publish:twitter.com" },
    .{ .host = "api.x.com", .effect_id = "comms.publish", .matcher = "network_tag.comms.publish:api.x.com" },
    .{ .host = "x.com", .effect_id = "comms.publish", .matcher = "network_tag.comms.publish:x.com" },
    .{ .host = "api.linkedin.com", .effect_id = "comms.publish", .matcher = "network_tag.comms.publish:api.linkedin.com" },
    .{ .host = "linkedin.com", .effect_id = "comms.publish", .matcher = "network_tag.comms.publish:linkedin.com" },
    // comms.message
    .{ .host = "api.sendgrid.com", .effect_id = "comms.message", .matcher = "network_tag.comms.message:api.sendgrid.com" },
    .{ .host = "api.mailgun.net", .effect_id = "comms.message", .matcher = "network_tag.comms.message:api.mailgun.net" },
    .{ .host = "api.postmarkapp.com", .effect_id = "comms.message", .matcher = "network_tag.comms.message:api.postmarkapp.com" },
    .{ .host = "smtp.gmail.com", .effect_id = "comms.message", .matcher = "network_tag.comms.message:smtp.gmail.com" },
    .{ .host = "smtp.sendgrid.net", .effect_id = "comms.message", .matcher = "network_tag.comms.message:smtp.sendgrid.net" },
};

fn trimTrailingDot(value: []const u8) []const u8 {
    if (value.len > 0 and value[value.len - 1] == '.') return value[0 .. value.len - 1];
    return value;
}

fn hostEquals(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(trimTrailingDot(a), trimTrailingDot(b));
}

/// Exact host match or parent-domain match (e.g. `twitter.com` matches `api.twitter.com`).
fn hostMatches(pattern: []const u8, host: []const u8) bool {
    const p = trimTrailingDot(pattern);
    const h = trimTrailingDot(host);
    if (std.ascii.eqlIgnoreCase(p, h)) return true;
    // Suffix: host ends with "." + pattern
    if (h.len > p.len + 1 and h[h.len - p.len - 1] == '.' and std.ascii.eqlIgnoreCase(h[h.len - p.len ..], p)) {
        return true;
    }
    return false;
}

/// Classify a destination host into zero or more effect hits (owned slice).
/// Matcher/id strings are static. Confidence is medium (host tag, not tool catalog).
pub fn classifyHost(allocator: std.mem.Allocator, host: []const u8) ![]catalog.EffectHit {
    var hits: std.ArrayList(catalog.EffectHit) = .empty;
    errdefer hits.deinit(allocator);

    const trimmed = std.mem.trim(u8, host, " \t\r\n");
    if (trimmed.len == 0) return try hits.toOwnedSlice(allocator);

    for (host_tags) |tag| {
        if (!hostMatches(tag.host, trimmed)) continue;
        // Prefer first (most specific exact-ish) hit per effect id.
        var already = false;
        for (hits.items) |existing| {
            if (std.mem.eql(u8, existing.id, tag.effect_id)) {
                already = true;
                break;
            }
        }
        if (already) continue;
        try hits.append(allocator, .{
            .id = tag.effect_id,
            .confidence = .medium,
            .matcher = tag.matcher,
        });
        std.debug.assert(ids.isKnownEffectId(tag.effect_id));
    }
    return try hits.toOwnedSlice(allocator);
}

/// Look up the first matching effect id for a host (for shell curl reuse).
pub fn effectForHost(host: []const u8) ?struct { effect_id: []const u8, matcher: []const u8 } {
    const trimmed = std.mem.trim(u8, host, " \t\r\n");
    if (trimmed.len == 0) return null;
    for (host_tags) |tag| {
        if (hostMatches(tag.host, trimmed)) {
            return .{ .effect_id = tag.effect_id, .matcher = tag.matcher };
        }
    }
    return null;
}

/// Extract host from a URL-ish string (`https://api.twitter.com/path` or bare host).
pub fn hostFromUrlOrHost(value: []const u8) []const u8 {
    var rest = std.mem.trim(u8, value, " \t\r\n");
    if (std.mem.indexOf(u8, rest, "://")) |scheme_end| {
        rest = rest[scheme_end + 3 ..];
    }
    const authority_end = std.mem.indexOfAny(u8, rest, "/?#") orelse rest.len;
    var authority = rest[0..authority_end];
    if (std.mem.lastIndexOfScalar(u8, authority, '@')) |at| authority = authority[at + 1 ..];
    var host = authority;
    if (authority.len > 0 and authority[0] == '[') {
        if (std.mem.indexOfScalar(u8, authority, ']')) |close| {
            host = authority[1..close];
        }
    } else if (std.mem.lastIndexOfScalar(u8, authority, ':')) |colon| {
        if (std.mem.indexOfScalar(u8, authority[0..colon], ':') == null) {
            host = authority[0..colon];
        }
    }
    return trimTrailingDot(std.mem.trim(u8, host, " \t\r\n"));
}

test "network tags classify twitter and sendgrid hosts" {
    const tw = try classifyHost(std.testing.allocator, "api.twitter.com");
    defer std.testing.allocator.free(tw);
    try std.testing.expect(tw.len >= 1);
    try std.testing.expectEqualStrings("comms.publish", tw[0].id);
    try std.testing.expect(std.mem.startsWith(u8, tw[0].matcher, "network_tag."));

    const sg = try classifyHost(std.testing.allocator, "API.SendGrid.COM");
    defer std.testing.allocator.free(sg);
    try std.testing.expect(sg.len >= 1);
    try std.testing.expectEqualStrings("comms.message", sg[0].id);
}

test "network tags ignore unrelated hosts" {
    const hits = try classifyHost(std.testing.allocator, "api.github.com");
    defer std.testing.allocator.free(hits);
    try std.testing.expectEqual(@as(usize, 0), hits.len);
}

test "hostFromUrlOrHost strips scheme and path" {
    try std.testing.expectEqualStrings("api.twitter.com", hostFromUrlOrHost("https://api.twitter.com/2/tweets"));
    try std.testing.expectEqualStrings("x.com", hostFromUrlOrHost("x.com"));
}

test "subdomain matches parent tag host" {
    // linkedin.com tag should match www.linkedin.com
    const hits = try classifyHost(std.testing.allocator, "www.linkedin.com");
    defer std.testing.allocator.free(hits);
    try std.testing.expect(hits.len >= 1);
    try std.testing.expectEqualStrings("comms.publish", hits[0].id);
}

test "hostEquals used for exact" {
    try std.testing.expect(hostEquals("X.COM", "x.com"));
}
