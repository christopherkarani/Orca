//! Optional local residual effect classifier (Phase D).
//!
//! Pure Zig prototype/token similarity over tool name (+ optional arg tokens for outbound only).
//! Runs only when catalog/structural/packs leave the tool under-classified.
//! Raise-only: residual may increase restriction only; never a cloud call.
//! Matchers use `classifier.local.*` prefixes.
//!
//! Prototype family scores use **name tokens only** so agent-controlled arg keys/values
//! cannot demote a residual family hit to `unknown.external` (fail-open under family denies).

const std = @import("std");
const builtin = @import("builtin");
const catalog = @import("catalog.zig");
const classify = @import("classify.zig");
const effect_eval = @import("evaluate.zig");
const ids = @import("ids.zig");
const packs_mod = @import("packs.zig");
const structural = @import("structural.zig");

const EffectHit = catalog.EffectHit;
const ToolArgsView = structural.ToolArgsView;
const PackSet = packs_mod.PackSet;
const EffectsRuleView = effect_eval.EffectsRuleView;
const EffectMatch = effect_eval.EffectMatch;

pub const residual_matcher_prefix = "classifier.local.";

/// Test inject: when true, residual classification is treated as unavailable.
/// Ignored outside `builtin.is_test` builds.
pub var testing_force_unavailable: bool = false;

const max_feature_tokens: usize = 32;
const max_token_bytes: usize = 48;
const score_threshold: i32 = 2;
const score_margin: i32 = 1;

const Prototype = struct {
    effect_id: []const u8,
    tokens: []const []const u8,
    matcher: []const u8,
};

const prototypes = [_]Prototype{
    .{
        .effect_id = "comms.message",
        .matcher = "classifier.local.prototype:comms.message",
        .tokens = &.{
            "mail",     "mailer",   "email",     "smtp",    "message",  "messaging",
            "sms",      "imessage", "slack",     "discord", "telegram", "whatsapp",
            "notify",   "notifier", "recipient", "inbox",   "outbox",   "postmark",
            "sendgrid", "mailgun",
        },
    },
    .{
        .effect_id = "comms.publish",
        .matcher = "classifier.local.prototype:comms.publish",
        .tokens = &.{
            "tweet",    "twitter", "publish",  "publisher", "bluesky", "mastodon",
            "linkedin", "social",  "timeline", "fediverse",
        },
    },
    .{
        .effect_id = "money.transfer",
        .matcher = "classifier.local.prototype:money.transfer",
        .tokens = &.{
            "payment", "pay",     "stripe",   "paypal", "charge", "transfer",
            "invoice", "billing", "checkout", "payout", "wire",
        },
    },
    .{
        .effect_id = "identity.auth",
        .matcher = "classifier.local.prototype:identity.auth",
        .tokens = &.{
            "oauth", "auth", "authorize", "token", "pat", "credential",
            "login", "sso",  "oidc",      "saml",
        },
    },
};

const outbound_tokens = [_][]const u8{
    "outbound", "webhook", "http",     "https",  "api",   "remote", "external",
    "fetch",    "request", "callback", "egress", "exfil", "upload",
};

/// Result of packs classify ± residual. Always includes usable hits (base at minimum).
pub const ToolClassifyResult = struct {
    hits: []EffectHit,
    /// Residual was enabled but the engine reported unavailable (fail-closed signal).
    unavailable: bool = false,

    pub fn deinit(self: ToolClassifyResult, allocator: std.mem.Allocator) void {
        allocator.free(self.hits);
    }
};

pub fn isResidualMatcher(matcher: []const u8) bool {
    return std.mem.startsWith(u8, matcher, residual_matcher_prefix);
}

/// Residual when A–C left no high/medium hit on a specific family
/// (anything other than `unknown.external`).
pub fn isResidual(existing_hits: []const EffectHit) bool {
    for (existing_hits) |hit| {
        if (hit.confidence == .high or hit.confidence == .medium) {
            if (!std.mem.eql(u8, hit.id, "unknown.external")) return false;
        }
    }
    return true;
}

fn tokenizeName(allocator: std.mem.Allocator, normalized: []const u8, out: *std.ArrayList([]const u8)) !void {
    var rest = normalized;
    while (rest.len > 0) {
        const sep = std.mem.indexOfAny(u8, rest, "_-/.");
        const segment = if (sep) |i| rest[0..i] else rest;
        if (segment.len >= 2 and segment.len <= max_token_bytes) {
            try appendUniqueToken(allocator, out, segment);
        }
        if (sep) |i| {
            rest = rest[i + 1 ..];
        } else break;
    }
}

fn appendUniqueToken(allocator: std.mem.Allocator, out: *std.ArrayList([]const u8), token: []const u8) !void {
    if (out.items.len >= max_feature_tokens) return;
    for (out.items) |existing| {
        if (std.mem.eql(u8, existing, token)) return;
    }
    const owned = try allocator.dupe(u8, token);
    errdefer allocator.free(owned);
    try out.append(allocator, owned);
}

/// Name-only feature bag for prototype family scoring (agent args must not vote).
fn buildNameFeatureBag(
    allocator: std.mem.Allocator,
    tool_name: []const u8,
) ![]const []const u8 {
    var tokens: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (tokens.items) |t| allocator.free(t);
        tokens.deinit(allocator);
    }

    const trimmed = std.mem.trim(u8, tool_name, " \t\r\n");
    if (trimmed.len > 0) {
        const normalized = try catalog.normalizeToolName(allocator, trimmed);
        defer allocator.free(normalized);
        try tokenizeName(allocator, normalized, &tokens);
        const focus = catalog.focusName(normalized);
        if (focus.len >= 2 and focus.len <= max_token_bytes) {
            try appendUniqueToken(allocator, &tokens, focus);
        }
    }

    return try tokens.toOwnedSlice(allocator);
}

/// Arg keys + short string values — used only for outbound/unknown scoring, never prototype ranking.
fn buildArgFeatureBag(
    allocator: std.mem.Allocator,
    args: ?ToolArgsView,
) ![]const []const u8 {
    var tokens: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (tokens.items) |t| allocator.free(t);
        tokens.deinit(allocator);
    }

    if (args) |view| {
        for (view.keys) |key| {
            if (tokens.items.len >= max_feature_tokens) break;
            var buf: [max_token_bytes]u8 = undefined;
            if (key.len == 0 or key.len > max_token_bytes) continue;
            for (key, 0..) |c, i| {
                const lower = std.ascii.toLower(c);
                buf[i] = if (lower == '-' or lower == '.') '_' else lower;
            }
            try tokenizeName(allocator, buf[0..key.len], &tokens);
        }
        const n_vals = @min(view.string_values.len, structural.max_string_values);
        var vi: usize = 0;
        while (vi < n_vals and tokens.items.len < max_feature_tokens) : (vi += 1) {
            const raw = view.string_values[vi];
            if (raw.len < 2 or raw.len > max_token_bytes) continue;
            if (looksLikeSecret(raw)) continue;
            var buf: [max_token_bytes]u8 = undefined;
            var all_alnum = true;
            for (raw, 0..) |c, i| {
                if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-') {
                    all_alnum = false;
                    break;
                }
                buf[i] = std.ascii.toLower(c);
            }
            if (!all_alnum) continue;
            try appendUniqueToken(allocator, &tokens, buf[0..raw.len]);
        }
    }

    return try tokens.toOwnedSlice(allocator);
}

fn freeFeatureBag(allocator: std.mem.Allocator, tokens: []const []const u8) void {
    for (tokens) |t| allocator.free(t);
    if (tokens.len > 0) allocator.free(tokens);
}

fn looksLikeSecret(value: []const u8) bool {
    if (value.len >= 24) return true;
    if (std.mem.indexOf(u8, value, "sk-") != null) return true;
    if (std.mem.indexOf(u8, value, "Bearer") != null) return true;
    return false;
}

fn featureContains(features: []const []const u8, token: []const u8) bool {
    for (features) |f| {
        if (std.mem.eql(u8, f, token)) return true;
        // Domain nouns as substrings (mail ⊂ mailer).
        if (token.len >= 4 and f.len >= token.len and std.mem.indexOf(u8, f, token) != null) return true;
        if (f.len >= 4 and token.len >= f.len and std.mem.indexOf(u8, token, f) != null) return true;
    }
    return false;
}

fn scoreTokenSet(features: []const []const u8, tokens: []const []const u8) i32 {
    var score: i32 = 0;
    for (tokens) |t| {
        if (featureContains(features, t)) score += 1;
    }
    return score;
}

/// Score residual tools. Empty when not residual / excluded / below threshold.
/// Matchers are static. Slice owned by `allocator`.
///
/// Family prototypes are scored from **name tokens only**. Arg features may contribute
/// only to `unknown.external` outbound detection — never to cross-family ranking.
pub fn classifyResidual(
    allocator: std.mem.Allocator,
    tool_name: []const u8,
    args: ?ToolArgsView,
    existing_hits: []const EffectHit,
) std.mem.Allocator.Error![]EffectHit {
    if (!isResidual(existing_hits)) return try allocator.alloc(EffectHit, 0);

    const trimmed = std.mem.trim(u8, tool_name, " \t\r\n");
    if (trimmed.len == 0) return try allocator.alloc(EffectHit, 0);

    if (structural.isFileOrShellToolName(trimmed)) return try allocator.alloc(EffectHit, 0);

    const name_features = try buildNameFeatureBag(allocator, tool_name);
    defer freeFeatureBag(allocator, name_features);
    if (name_features.len == 0) return try allocator.alloc(EffectHit, 0);

    var best_idx: ?usize = null;
    var best_score: i32 = 0;
    var second_score: i32 = 0;
    for (prototypes, 0..) |proto, i| {
        const s = scoreTokenSet(name_features, proto.tokens);
        if (s > best_score) {
            second_score = best_score;
            best_score = s;
            best_idx = i;
        } else if (s > second_score) {
            second_score = s;
        }
    }

    var hits: std.ArrayList(EffectHit) = .empty;
    errdefer hits.deinit(allocator);

    // Emit best family whenever it clears the score threshold. Margin is not required
    // to emit (avoids demoting to unknown-only); weak margin may also add unknown.external.
    if (best_idx) |idx| {
        if (best_score >= score_threshold) {
            const proto = prototypes[idx];
            std.debug.assert(ids.isKnownEffectId(proto.effect_id));
            try classify.appendUniquePreferHigher(allocator, &hits, .{
                .id = proto.effect_id,
                .confidence = .low,
                .matcher = proto.matcher,
            });
            if ((best_score - second_score) < score_margin) {
                try classify.appendUniquePreferHigher(allocator, &hits, .{
                    .id = "unknown.external",
                    .confidence = .low,
                    .matcher = "classifier.local.residual:unknown.external",
                });
            }
            return try hits.toOwnedSlice(allocator);
        }
    }

    const arg_features = try buildArgFeatureBag(allocator, args);
    defer freeFeatureBag(allocator, arg_features);
    const outbound_name = scoreTokenSet(name_features, &outbound_tokens);
    const outbound_args = scoreTokenSet(arg_features, &outbound_tokens);
    if (outbound_name + outbound_args >= 1 or best_score >= 1) {
        try classify.appendUniquePreferHigher(allocator, &hits, .{
            .id = "unknown.external",
            .confidence = .low,
            .matcher = "classifier.local.residual:unknown.external",
        });
    }

    return try hits.toOwnedSlice(allocator);
}

/// Packs classify ± residual. On unavailability, returns base hits + `unavailable=true`
/// (never drops A–C hits; caller fail-closes or continues).
pub fn classifyToolCallWithResidual(
    allocator: std.mem.Allocator,
    pack_set: ?*const PackSet,
    tool_name: []const u8,
    args: ?ToolArgsView,
    classifier_enabled: bool,
) std.mem.Allocator.Error!ToolClassifyResult {
    const base = try packs_mod.classifyToolCallWithPacks(allocator, pack_set, tool_name, args);
    var free_base = true;
    errdefer if (free_base) allocator.free(base);

    if (!classifier_enabled) {
        free_base = false;
        return .{ .hits = base };
    }

    if (builtin.is_test and testing_force_unavailable) {
        free_base = false;
        return .{ .hits = base, .unavailable = true };
    }

    const residual = try classifyResidual(allocator, tool_name, args, base);
    defer allocator.free(residual);
    if (residual.len == 0) {
        free_base = false;
        return .{ .hits = base };
    }

    var hits: std.ArrayList(EffectHit) = .empty;
    errdefer hits.deinit(allocator);
    for (base) |h| try classify.appendUniquePreferHigher(allocator, &hits, h);
    allocator.free(base);
    free_base = false;
    for (residual) |h| try classify.appendUniquePreferHigher(allocator, &hits, h);
    for (hits.items) |hit| {
        std.debug.assert(ids.isKnownEffectId(hit.id));
    }
    return .{ .hits = try hits.toOwnedSlice(allocator) };
}

fn hasResidualHit(hits: []const EffectHit) bool {
    for (hits) |h| {
        if (isResidualMatcher(h.matcher)) return true;
    }
    return false;
}

/// Raise-only match: residual must not reduce severity vs A–C-only evaluation.
/// Partitions residual matchers from `hits` (no re-classification).
pub fn evaluateHitsRaiseOnly(
    allocator: std.mem.Allocator,
    hits: []const EffectHit,
    rules: EffectsRuleView,
) std.mem.Allocator.Error!EffectMatch {
    const combined = effect_eval.evaluateHits(hits, rules);
    if (!hasResidualHit(hits)) return combined;

    var base_list: std.ArrayList(EffectHit) = .empty;
    defer base_list.deinit(allocator);
    for (hits) |h| {
        if (!isResidualMatcher(h.matcher)) try base_list.append(allocator, h);
    }
    const base = effect_eval.evaluateHits(base_list.items, rules);
    if (combined.kind.severity() >= base.kind.severity()) return combined;
    return base;
}

// ── Tests ──────────────────────────────────────────────────────────────────

test "isResidual true for empty and unknown-only" {
    try std.testing.expect(isResidual(&.{}));
    const low_unknown = [_]EffectHit{
        .{ .id = "unknown.external", .confidence = .low, .matcher = "x" },
    };
    try std.testing.expect(isResidual(&low_unknown));
}

test "isResidual false when catalog high specific family" {
    const hits = [_]EffectHit{
        .{ .id = "comms.message", .confidence = .high, .matcher = "catalog" },
    };
    try std.testing.expect(!isResidual(&hits));
}

test "isResidual false for structural medium" {
    const hits = [_]EffectHit{
        .{ .id = "comms.message", .confidence = .medium, .matcher = "structural" },
    };
    try std.testing.expect(!isResidual(&hits));
}

test "classifier off path via classifyToolCallWithResidual disabled" {
    const result = try classifyToolCallWithResidual(std.testing.allocator, null, "acme_mailer_job", null, false);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(!result.unavailable);
    for (result.hits) |h| {
        try std.testing.expect(!isResidualMatcher(h.matcher));
    }
}

test "residual name acme_mailer_job can hit comms.message low" {
    const result = try classifyToolCallWithResidual(std.testing.allocator, null, "acme_mailer_job", null, true);
    defer result.deinit(std.testing.allocator);
    var found = false;
    for (result.hits) |h| {
        if (std.mem.eql(u8, h.id, "comms.message") and isResidualMatcher(h.matcher)) {
            found = true;
            try std.testing.expect(h.confidence == .low);
        }
    }
    try std.testing.expect(found);
}

test "send_email remains catalog high; residual does not replace" {
    const result = try classifyToolCallWithResidual(std.testing.allocator, null, "send_email", null, true);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.hits.len >= 1);
    try std.testing.expectEqualStrings("comms.message", result.hits[0].id);
    try std.testing.expect(result.hits[0].confidence == .high);
    try std.testing.expect(std.mem.startsWith(u8, result.hits[0].matcher, "catalog."));
    for (result.hits) |h| {
        try std.testing.expect(!isResidualMatcher(h.matcher));
    }
}

test "notify with to+body stays structural medium; residual does not replace" {
    const keys = [_][]const u8{ "to", "body" };
    const result = try classifyToolCallWithResidual(std.testing.allocator, null, "notify", .{ .keys = &keys }, true);
    defer result.deinit(std.testing.allocator);
    var found = false;
    for (result.hits) |h| {
        if (std.mem.eql(u8, h.id, "comms.message") and std.mem.startsWith(u8, h.matcher, "structural.")) {
            found = true;
            try std.testing.expect(h.confidence == .medium);
        }
        try std.testing.expect(!isResidualMatcher(h.matcher));
    }
    try std.testing.expect(found);
}

test "forced unavailable returns base hits with unavailable flag" {
    testing_force_unavailable = true;
    defer testing_force_unavailable = false;
    const result = try classifyToolCallWithResidual(std.testing.allocator, null, "acme_mailer_job", null, true);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.unavailable);
    for (result.hits) |h| {
        try std.testing.expect(!isResidualMatcher(h.matcher));
    }
}

test "hard-excluded shell tools do not residual to comms" {
    const result = try classifyToolCallWithResidual(std.testing.allocator, null, "Bash", null, true);
    defer result.deinit(std.testing.allocator);
    for (result.hits) |h| {
        try std.testing.expect(!isResidualMatcher(h.matcher));
        try std.testing.expect(!std.mem.eql(u8, h.id, "comms.message"));
    }
}

test "outbound residual name can emit unknown.external" {
    const result = try classifyToolCallWithResidual(std.testing.allocator, null, "weird_outbound_helper", null, true);
    defer result.deinit(std.testing.allocator);
    var found = false;
    for (result.hits) |h| {
        if (std.mem.eql(u8, h.id, "unknown.external") and isResidualMatcher(h.matcher)) {
            found = true;
            try std.testing.expect(h.confidence == .low);
        }
    }
    try std.testing.expect(found);
}

test "arg decoys cannot demote residual family deny for acme_mailer_job" {
    // Agent-controlled keys/values that boost competing prototypes must not
    // replace comms.message with unknown.external-only (family deny would fail open).
    // Keys avoid structural complete sets (e.g. bare `tweet`) so residual still runs.
    const keys = [_][]const u8{ "publisher", "payment", "social", "billing" };
    const vals = [_][]const u8{ "twitter", "stripe", "linkedin", "paypal", "mastodon", "publish" };
    const result = try classifyToolCallWithResidual(
        std.testing.allocator,
        null,
        "acme_mailer_job",
        .{ .keys = &keys, .string_values = &vals },
        true,
    );
    defer result.deinit(std.testing.allocator);

    var found_msg = false;
    for (result.hits) |h| {
        if (std.mem.eql(u8, h.id, "comms.message") and isResidualMatcher(h.matcher)) {
            found_msg = true;
            try std.testing.expect(h.confidence == .low);
        }
    }
    try std.testing.expect(found_msg);

    const match = effect_eval.evaluateHits(result.hits, .{
        .deny = &.{"comms.message"},
        .default = .allow,
    });
    try std.testing.expect(match.kind == .deny);
}

test "evaluateHitsRaiseOnly does not let residual allow beat base deny default" {
    const hits = [_]EffectHit{
        .{ .id = "comms.message", .confidence = .low, .matcher = "classifier.local.prototype:comms.message" },
    };
    // Empty base (only residual) with default deny vs residual matching allow.
    const match = try evaluateHitsRaiseOnly(std.testing.allocator, &hits, .{
        .allow = &.{"comms.message"},
        .default = .deny,
    });
    // Base = no residual matchers → empty → default deny.
    // Combined = allow. Raise-only keeps deny.
    try std.testing.expect(match.kind == .deny);
}

test "EffectsClassifier parse aliases" {
    const schema = @import("../schema.zig");
    try std.testing.expect(schema.EffectsClassifier.parse("off").? == .off);
    try std.testing.expect(schema.EffectsClassifier.parse("local").? == .local);
    try std.testing.expect(schema.EffectsClassifier.parse("local-embed").? == .local);
    try std.testing.expect(schema.EffectsClassifier.parse("local_embed").? == .local);
    try std.testing.expect(schema.EffectsClassifier.parse("cloud") == null);
}
