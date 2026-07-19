//! Structural (argument key/value) effect classification.
//! Medium-confidence hits from arg shapes; never alone overrides surface deny → allow
//! (enforced by severity merge in evaluate.zig). Deterministic only.

const std = @import("std");
const catalog = @import("catalog.zig");
const ids = @import("ids.zig");
const network_tags = @import("network_tags.zig");

/// Borrowed view of tool-call arguments for classification.
/// Keys and string values must outlive the classify call (typically arena/JSON lifetime).
pub const ToolArgsView = struct {
    keys: []const []const u8 = &.{},
    string_values: []const []const u8 = &.{},
};

pub const max_keys: usize = 32;
pub const max_string_values: usize = 16;
pub const max_string_scan_bytes: usize = 4 * 1024;

const KeySet = struct {
    /// Required keys (normalized). All must be present.
    keys: []const []const u8,
    effect_id: []const u8,
    matcher: []const u8,
};

/// Required key sets: any one complete set triggers the effect.
const key_sets = [_]KeySet{
    // comms.message
    .{ .keys = &.{ "to", "body" }, .effect_id = "comms.message", .matcher = "structural.comms.message.keys:to+body" },
    .{ .keys = &.{ "to", "message" }, .effect_id = "comms.message", .matcher = "structural.comms.message.keys:to+message" },
    .{ .keys = &.{ "recipient", "body" }, .effect_id = "comms.message", .matcher = "structural.comms.message.keys:recipient+body" },
    .{ .keys = &.{ "recipient", "message" }, .effect_id = "comms.message", .matcher = "structural.comms.message.keys:recipient+message" },
    .{ .keys = &.{ "phone", "text" }, .effect_id = "comms.message", .matcher = "structural.comms.message.keys:phone+text" },
    .{ .keys = &.{ "phone", "message" }, .effect_id = "comms.message", .matcher = "structural.comms.message.keys:phone+message" },
    .{ .keys = &.{ "channel", "text" }, .effect_id = "comms.message", .matcher = "structural.comms.message.keys:channel+text" },
    .{ .keys = &.{ "email", "subject" }, .effect_id = "comms.message", .matcher = "structural.comms.message.keys:email+subject" },
    .{ .keys = &.{ "email", "body" }, .effect_id = "comms.message", .matcher = "structural.comms.message.keys:email+body" },
    // comms.publish — strong keys alone
    .{ .keys = &.{"tweet"}, .effect_id = "comms.publish", .matcher = "structural.comms.publish.keys:tweet" },
    .{ .keys = &.{"status"}, .effect_id = "comms.publish", .matcher = "structural.comms.publish.keys:status" },
    .{ .keys = &.{"post_text"}, .effect_id = "comms.publish", .matcher = "structural.comms.publish.keys:post_text" },
    // money.transfer
    .{ .keys = &.{ "amount", "currency" }, .effect_id = "money.transfer", .matcher = "structural.money.transfer.keys:amount+currency" },
    .{ .keys = &.{ "amount", "to" }, .effect_id = "money.transfer", .matcher = "structural.money.transfer.keys:amount+to" },
    .{ .keys = &.{ "price", "currency" }, .effect_id = "money.transfer", .matcher = "structural.money.transfer.keys:price+currency" },
    // unknown.external outbound-ish without family
    .{ .keys = &.{ "url", "payload" }, .effect_id = "unknown.external", .matcher = "structural.unknown.external.keys:url+payload" },
};

fn normalizeKey(allocator: std.mem.Allocator, key: []const u8) ![]u8 {
    var out = try allocator.alloc(u8, key.len);
    errdefer allocator.free(out);
    for (key, 0..) |byte, i| {
        const lower = std.ascii.toLower(byte);
        out[i] = if (lower == '-' or lower == '.') '_' else lower;
    }
    return out;
}

fn hasNormalizedKey(normalized_keys: []const []const u8, required: []const u8) bool {
    for (normalized_keys) |k| {
        if (std.mem.eql(u8, k, required)) return true;
    }
    return false;
}

fn keySetPresent(normalized_keys: []const []const u8, required: []const []const u8) bool {
    for (required) |req| {
        if (!hasNormalizedKey(normalized_keys, req)) return false;
    }
    return true;
}

fn isFileOrShellToolName(tool_name: []const u8) bool {
    const blocked = [_][]const u8{
        "write",    "edit",     "read",      "bash",     "shell",
        "sh",       "zsh",      "exec",      "terminal", "powershell",
        "pwsh",     "apply",    "create_file", "file_write", "file_edit",
        "read_file", "write_file", "run_shell_command", "run_terminal_cmd",
    };
    // Normalize lightly for comparison
    var buf: [64]u8 = undefined;
    if (tool_name.len > buf.len) return false;
    for (tool_name, 0..) |byte, i| {
        const lower = std.ascii.toLower(byte);
        buf[i] = if (lower == '-' or lower == '.') '_' else lower;
    }
    const n = buf[0..tool_name.len];
    // focus last segment after __
    var focus = n;
    if (std.mem.lastIndexOf(u8, n, "__")) |idx| focus = n[idx + 2 ..];
    for (blocked) |b| {
        if (std.mem.eql(u8, focus, b)) return true;
    }
    return false;
}

fn nameHasPublishSignal(tool_name: []const u8) bool {
    const tokens = [_][]const u8{ "tweet", "twitter", "post", "publish", "linkedin", "mastodon", "bluesky", "status" };
    var buf: [128]u8 = undefined;
    if (tool_name.len > buf.len) return false;
    for (tool_name, 0..) |byte, i| {
        buf[i] = std.ascii.toLower(byte);
    }
    const n = buf[0..tool_name.len];
    for (tokens) |t| {
        if (std.mem.indexOf(u8, n, t) != null) return true;
    }
    return false;
}

/// Conservative email: local@domain.tld with simple character classes.
fn looksLikeEmail(value: []const u8) bool {
    if (value.len < 5 or value.len > 254) return false;
    const at = std.mem.indexOfScalar(u8, value, '@') orelse return false;
    if (at == 0 or at + 1 >= value.len) return false;
    const local = value[0..at];
    const domain = value[at + 1 ..];
    if (std.mem.indexOfScalar(u8, domain, '.') == null) return false;
    if (std.mem.indexOfScalar(u8, local, ' ') != null) return false;
    if (std.mem.indexOfScalar(u8, domain, ' ') != null) return false;
    // Require at least one alpha in domain TLD-ish tail
    var has_alpha = false;
    for (domain) |c| {
        if (std.ascii.isAlphabetic(c)) has_alpha = true;
        if (!(std.ascii.isAlphanumeric(c) or c == '.' or c == '-' or c == '_')) return false;
    }
    return has_alpha;
}

/// E.164-ish: optional +, then 8–15 digits.
fn looksLikePhone(value: []const u8) bool {
    var rest = value;
    if (rest.len > 0 and rest[0] == '+') rest = rest[1..];
    if (rest.len < 8 or rest.len > 15) return false;
    for (rest) |c| {
        if (!std.ascii.isDigit(c)) return false;
    }
    return true;
}

fn appendUniquePreferHigher(
    allocator: std.mem.Allocator,
    hits: *std.ArrayList(catalog.EffectHit),
    hit: catalog.EffectHit,
) !void {
    for (hits.items, 0..) |existing, i| {
        if (std.mem.eql(u8, existing.id, hit.id)) {
            // Prefer higher confidence (high > medium > low)
            if (@intFromEnum(hit.confidence) < @intFromEnum(existing.confidence)) {
                hits.items[i] = hit;
            }
            return;
        }
    }
    try hits.append(allocator, hit);
}

/// Classify tool args into structural effect hits (owned slice).
/// tool_name is used only for false-positive guards and weak publish signals.
pub fn classifyArgs(
    allocator: std.mem.Allocator,
    tool_name: []const u8,
    args: ToolArgsView,
) ![]catalog.EffectHit {
    var hits: std.ArrayList(catalog.EffectHit) = .empty;
    errdefer hits.deinit(allocator);

    // Normalize keys (owned temporary)
    var norm_list: std.ArrayList([]const u8) = .empty;
    defer {
        for (norm_list.items) |k| allocator.free(@constCast(k));
        norm_list.deinit(allocator);
    }

    const key_limit = @min(args.keys.len, max_keys);
    for (args.keys[0..key_limit]) |key| {
        const n = try normalizeKey(allocator, key);
        try norm_list.append(allocator, n);
    }
    const normalized_keys = norm_list.items;

    // Key sets
    for (key_sets) |set| {
        if (!keySetPresent(normalized_keys, set.keys)) continue;
        try appendUniquePreferHigher(allocator, &hits, .{
            .id = set.effect_id,
            .confidence = .medium,
            .matcher = set.matcher,
        });
    }

    // Bare {text} publish: only with publish-ish name or not file/shell tools + visibility/public
    const has_text = hasNormalizedKey(normalized_keys, "text");
    const has_visibility = hasNormalizedKey(normalized_keys, "visibility") or hasNormalizedKey(normalized_keys, "public");
    if (has_text and !isFileOrShellToolName(tool_name)) {
        if (nameHasPublishSignal(tool_name) or has_visibility) {
            try appendUniquePreferHigher(allocator, &hits, .{
                .id = "comms.publish",
                .confidence = .medium,
                .matcher = "structural.comms.publish.keys:text",
            });
        }
    }

    // Value shapes (bounded)
    var scanned: usize = 0;
    const val_limit = @min(args.string_values.len, max_string_values);
    for (args.string_values[0..val_limit]) |raw| {
        if (scanned >= max_string_scan_bytes) break;
        const value = if (raw.len > max_string_scan_bytes - scanned)
            raw[0 .. max_string_scan_bytes - scanned]
        else
            raw;
        scanned += value.len;

        if (looksLikeEmail(value)) {
            try appendUniquePreferHigher(allocator, &hits, .{
                .id = "comms.message",
                .confidence = .medium,
                .matcher = "structural.comms.message.value:email",
            });
        }
        if (looksLikePhone(value)) {
            try appendUniquePreferHigher(allocator, &hits, .{
                .id = "comms.message",
                .confidence = .medium,
                .matcher = "structural.comms.message.value:phone",
            });
        }

        // URL host tags
        if (std.mem.indexOf(u8, value, "://") != null or std.mem.indexOfScalar(u8, value, '.') != null) {
            const host = network_tags.hostFromUrlOrHost(value);
            if (host.len > 0) {
                if (network_tags.effectForHost(host)) |tag| {
                    const matcher: []const u8 = if (std.mem.eql(u8, tag.effect_id, "comms.publish"))
                        "structural.comms.publish.value:url_host"
                    else if (std.mem.eql(u8, tag.effect_id, "comms.message"))
                        "structural.comms.message.value:url_host"
                    else
                        "structural.unknown.external.value:url_host";
                    try appendUniquePreferHigher(allocator, &hits, .{
                        .id = tag.effect_id,
                        .confidence = .medium,
                        .matcher = matcher,
                    });
                }
            }
        }
    }

    for (hits.items) |hit| {
        std.debug.assert(ids.isKnownEffectId(hit.id));
    }
    return try hits.toOwnedSlice(allocator);
}

/// Build a ToolArgsView from a JSON object value (top-level keys + string values only).
/// Allocates key/value slices owned by `allocator`. Caller frees keys, string_values, and their contents.
pub const OwnedArgsView = struct {
    view: ToolArgsView,
    /// Free all owned buffers.
    pub fn deinit(self: *OwnedArgsView, allocator: std.mem.Allocator) void {
        for (self.view.keys) |k| allocator.free(@constCast(k));
        if (self.view.keys.len > 0) allocator.free(self.view.keys);
        for (self.view.string_values) |v| allocator.free(@constCast(v));
        if (self.view.string_values.len > 0) allocator.free(self.view.string_values);
        self.* = .{ .view = .{} };
    }
};

pub fn toolArgsViewFromJsonObject(allocator: std.mem.Allocator, value: std.json.Value) !OwnedArgsView {
    if (value != .object) return .{ .view = .{} };

    var keys: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (keys.items) |k| allocator.free(k);
        keys.deinit(allocator);
    }
    var strings: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (strings.items) |s| allocator.free(s);
        strings.deinit(allocator);
    }

    var it = value.object.iterator();
    var key_count: usize = 0;
    var string_bytes: usize = 0;
    while (it.next()) |entry| {
        if (key_count >= max_keys) break;
        const key_copy = try allocator.dupe(u8, entry.key_ptr.*);
        try keys.append(allocator, key_copy);
        key_count += 1;

        if (strings.items.len >= max_string_values) continue;
        if (entry.value_ptr.* == .string) {
            const s = entry.value_ptr.*.string;
            if (string_bytes >= max_string_scan_bytes) continue;
            const take = @min(s.len, max_string_scan_bytes - string_bytes);
            const s_copy = try allocator.dupe(u8, s[0..take]);
            try strings.append(allocator, s_copy);
            string_bytes += take;
        }
    }

    return .{
        .view = .{
            .keys = try keys.toOwnedSlice(allocator),
            .string_values = try strings.toOwnedSlice(allocator),
        },
    };
}

test "notify with to+body is comms.message structural" {
    const keys = [_][]const u8{ "to", "body" };
    const hits = try classifyArgs(std.testing.allocator, "notify", .{ .keys = &keys });
    defer std.testing.allocator.free(hits);
    try std.testing.expect(hits.len >= 1);
    try std.testing.expectEqualStrings("comms.message", hits[0].id);
    try std.testing.expect(hits[0].confidence == .medium);
    try std.testing.expect(std.mem.startsWith(u8, hits[0].matcher, "structural."));
}

test "helper with tweet key is comms.publish" {
    const keys = [_][]const u8{"tweet"};
    const hits = try classifyArgs(std.testing.allocator, "helper", .{ .keys = &keys });
    defer std.testing.allocator.free(hits);
    try std.testing.expect(hits.len >= 1);
    try std.testing.expectEqualStrings("comms.publish", hits[0].id);
}

test "pay with amount+currency is money.transfer" {
    const keys = [_][]const u8{ "amount", "currency" };
    const hits = try classifyArgs(std.testing.allocator, "pay", .{ .keys = &keys });
    defer std.testing.allocator.free(hits);
    try std.testing.expect(hits.len >= 1);
    try std.testing.expectEqualStrings("money.transfer", hits[0].id);
}

test "Write with path content is not comms" {
    const keys = [_][]const u8{ "path", "content" };
    const hits = try classifyArgs(std.testing.allocator, "Write", .{ .keys = &keys });
    defer std.testing.allocator.free(hits);
    for (hits) |h| {
        try std.testing.expect(!std.mem.startsWith(u8, h.id, "comms."));
    }
}

test "Write with bare text key is not publish" {
    const keys = [_][]const u8{"text"};
    const hits = try classifyArgs(std.testing.allocator, "Write", .{ .keys = &keys });
    defer std.testing.allocator.free(hits);
    for (hits) |h| {
        try std.testing.expect(!std.mem.eql(u8, h.id, "comms.publish"));
    }
}

test "empty args yields no structural hits" {
    const hits = try classifyArgs(std.testing.allocator, "notify", .{});
    defer std.testing.allocator.free(hits);
    try std.testing.expectEqual(@as(usize, 0), hits.len);
}

test "email value shape" {
    const vals = [_][]const u8{"user@example.com"};
    const hits = try classifyArgs(std.testing.allocator, "helper", .{ .string_values = &vals });
    defer std.testing.allocator.free(hits);
    try std.testing.expect(hits.len >= 1);
    try std.testing.expectEqualStrings("comms.message", hits[0].id);
    try std.testing.expect(std.mem.indexOf(u8, hits[0].matcher, "email") != null);
}

test "case and dash insensitive keys" {
    const keys = [_][]const u8{ "To", "Body" };
    const hits = try classifyArgs(std.testing.allocator, "notify", .{ .keys = &keys });
    defer std.testing.allocator.free(hits);
    try std.testing.expect(hits.len >= 1);
    try std.testing.expectEqualStrings("comms.message", hits[0].id);
}
