//! Optional local residual effect classifier (Phase D).
//!
//! Pure Zig prototype/token similarity over tool name + arg keys/short string tokens.
//! Runs only when catalog/structural/packs leave the tool under-classified.
//! Raise-only: emits low-confidence hits that may increase restriction; never a cloud call.
//! Matchers use `classifier.local.*` prefixes.

const std = @import("std");
const catalog = @import("catalog.zig");
const classify = @import("classify.zig");
const ids = @import("ids.zig");
const structural = @import("structural.zig");

pub const EffectHit = catalog.EffectHit;
pub const Confidence = catalog.Confidence;
pub const ToolArgsView = structural.ToolArgsView;

pub const ClassifierError = error{
    /// Residual path enabled but engine unavailable (test inject or future asset failure).
    ClassifierUnavailable,
};

/// Test inject: when true, residual classification fails closed as unavailable.
pub var testing_force_unavailable: bool = false;

const max_feature_tokens: usize = 32;
const max_token_bytes: usize = 48;
/// Minimum prototype score to emit a family hit.
const score_threshold: i32 = 2;
/// Best must beat second by at least this margin (ambiguity guard).
const score_margin: i32 = 1;

const Prototype = struct {
    effect_id: []const u8,
    /// Curated tokens scored against the feature bag (ASCII lowercase).
    tokens: []const []const u8,
    matcher: []const u8,
};

/// Prototype token sets for residual similarity (deterministic, local tables).
const prototypes = [_]Prototype{
    .{
        .effect_id = "comms.message",
        .matcher = "classifier.local.prototype:comms.message",
        .tokens = &.{
            "mail",     "mailer",  "email",   "smtp",    "message", "messaging",
            "sms",      "imessage", "slack",  "discord", "telegram", "whatsapp",
            "notify",   "notifier", "recipient", "inbox", "outbox",  "postmark",
            "sendgrid", "mailgun",
        },
    },
    .{
        .effect_id = "comms.publish",
        .matcher = "classifier.local.prototype:comms.publish",
        .tokens = &.{
            "tweet", "twitter", "publish", "publisher", "bluesky", "mastodon",
            "linkedin", "social", "timeline", "fediverse",
        },
    },
    .{
        .effect_id = "money.transfer",
        .matcher = "classifier.local.prototype:money.transfer",
        .tokens = &.{
            "payment", "pay", "stripe", "paypal", "charge", "transfer",
            "invoice", "billing", "checkout", "payout", "wire",
        },
    },
    .{
        .effect_id = "identity.auth",
        .matcher = "classifier.local.prototype:identity.auth",
        .tokens = &.{
            "oauth", "auth", "authorize", "token", "pat", "credential",
            "login", "sso", "oidc", "saml",
        },
    },
};

/// Outbound-ish tokens → low-confidence unknown.external when no family wins.
const outbound_tokens = [_][]const u8{
    "outbound", "webhook", "http", "https", "api", "remote", "external",
    "fetch",    "request", "callback", "egress", "exfil", "upload",
};

/// Known host file/shell tool focuses — never residual-classify toward comms/money.
const hard_exclude_focus = [_][]const u8{
    "read",      "read_file",  "write",         "write_file", "edit",
    "file_write", "file_edit", "create_file",   "apply",      "bash",
    "shell",      "sh",        "zsh",           "exec",       "terminal",
    "powershell", "pwsh",      "run_shell_command", "run_terminal_cmd",
};

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

fn isHardExcluded(focus: []const u8, normalized: []const u8) bool {
    for (hard_exclude_focus) |ex| {
        if (std.mem.eql(u8, focus, ex) or std.mem.eql(u8, normalized, ex)) return true;
    }
    return false;
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
    // Also accept camelCase splits later if needed; tokens are already lowercased via normalize.
    try out.append(allocator, try allocator.dupe(u8, token));
}

fn buildFeatureBag(
    allocator: std.mem.Allocator,
    tool_name: []const u8,
    args: ?ToolArgsView,
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
        // Whole focus segment (last path-like piece) as a feature when multi-part.
        const focus = focusSegment(normalized);
        if (focus.len >= 2 and focus.len <= max_token_bytes) {
            try appendUniqueToken(allocator, &tokens, focus);
        }
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
            const nk = buf[0..key.len];
            try tokenizeName(allocator, nk, &tokens);
        }
        // Short string values only (bounded); never store full secrets in matchers.
        const n_vals = @min(view.string_values.len, structural.max_string_values);
        var vi: usize = 0;
        while (vi < n_vals and tokens.items.len < max_feature_tokens) : (vi += 1) {
            const raw = view.string_values[vi];
            if (raw.len < 2 or raw.len > max_token_bytes) continue;
            // Skip values that look like secrets / long opaque tokens.
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
    // Heuristic: long base64-ish or key= prefixes — avoid bag pollution / leakage.
    if (value.len >= 24) return true;
    if (std.mem.indexOf(u8, value, "sk-") != null) return true;
    if (std.mem.indexOf(u8, value, "Bearer") != null) return true;
    return false;
}

fn focusSegment(normalized: []const u8) []const u8 {
    // Last `__` or single `_`-separated-looking path: mirror catalog focus bias.
    if (std.mem.lastIndexOf(u8, normalized, "__")) |idx| {
        return normalized[idx + 2 ..];
    }
    if (std.mem.lastIndexOfScalar(u8, normalized, '/')) |idx| {
        return normalized[idx + 1 ..];
    }
    return normalized;
}

fn featureContains(features: []const []const u8, token: []const u8) bool {
    for (features) |f| {
        if (std.mem.eql(u8, f, token)) return true;
        // Longer domain nouns may appear as substrings of a feature token (mailer⊃mail).
        if (token.len >= 4 and f.len >= token.len and std.mem.indexOf(u8, f, token) != null) return true;
        if (f.len >= 4 and token.len >= f.len and std.mem.indexOf(u8, token, f) != null) return true;
    }
    return false;
}

fn scorePrototype(features: []const []const u8, proto: Prototype) i32 {
    var score: i32 = 0;
    for (proto.tokens) |t| {
        if (featureContains(features, t)) score += 1;
    }
    return score;
}

fn scoreOutbound(features: []const []const u8) i32 {
    var score: i32 = 0;
    for (outbound_tokens) |t| {
        if (featureContains(features, t)) score += 1;
    }
    return score;
}

/// Classify residual tools with local prototype similarity.
/// Returns empty slice when not residual or below threshold.
/// Matchers/id strings are static. Returned slice owned by `allocator`.
pub fn classifyResidual(
    allocator: std.mem.Allocator,
    tool_name: []const u8,
    args: ?ToolArgsView,
    existing_hits: []const EffectHit,
) (ClassifierError || std.mem.Allocator.Error)![]EffectHit {
    if (!isResidual(existing_hits)) {
        return try allocator.alloc(EffectHit, 0);
    }
    if (testing_force_unavailable) return error.ClassifierUnavailable;

    const trimmed = std.mem.trim(u8, tool_name, " \t\r\n");
    if (trimmed.len == 0) return try allocator.alloc(EffectHit, 0);

    const normalized = try catalog.normalizeToolName(allocator, trimmed);
    defer allocator.free(normalized);
    const focus = focusSegment(normalized);
    if (isHardExcluded(focus, normalized)) {
        return try allocator.alloc(EffectHit, 0);
    }

    const features = try buildFeatureBag(allocator, tool_name, args);
    defer freeFeatureBag(allocator, features);
    if (features.len == 0) return try allocator.alloc(EffectHit, 0);

    var best_idx: ?usize = null;
    var best_score: i32 = 0;
    var second_score: i32 = 0;
    for (prototypes, 0..) |proto, i| {
        const s = scorePrototype(features, proto);
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

    if (best_idx) |idx| {
        if (best_score >= score_threshold and (best_score - second_score) >= score_margin) {
            const proto = prototypes[idx];
            std.debug.assert(ids.isKnownEffectId(proto.effect_id));
            try classify.appendUniquePreferHigher(allocator, &hits, .{
                .id = proto.effect_id,
                .confidence = .low,
                .matcher = proto.matcher,
            });
            return try hits.toOwnedSlice(allocator);
        }
    }

    // Ambiguous or weak family signal but outbound-ish → unknown.external.
    if (scoreOutbound(features) >= 1 or best_score >= 1) {
        try classify.appendUniquePreferHigher(allocator, &hits, .{
            .id = "unknown.external",
            .confidence = .low,
            .matcher = "classifier.local.residual:unknown.external",
        });
    }

    return try hits.toOwnedSlice(allocator);
}

/// Built-in + packs classify, then optional residual classifier when enabled.
/// `classifier_enabled` is true for `effects.classifier: local` (and aliases).
/// May return `error.ClassifierUnavailable` when enabled but broken.
pub fn classifyToolCallWithResidual(
    allocator: std.mem.Allocator,
    pack_set: ?*const @import("packs.zig").PackSet,
    tool_name: []const u8,
    args: ?ToolArgsView,
    classifier_enabled: bool,
) (ClassifierError || std.mem.Allocator.Error)![]EffectHit {
    const packs = @import("packs.zig");
    const base = try packs.classifyToolCallWithPacks(allocator, pack_set, tool_name, args);
    if (!classifier_enabled) return base;

    const residual = classifyResidual(allocator, tool_name, args, base) catch |err| {
        allocator.free(base);
        return err;
    };
    defer allocator.free(residual);
    if (residual.len == 0) return base;

    // Merge residual into base (prefer higher confidence; residual is low).
    var hits: std.ArrayList(EffectHit) = .empty;
    errdefer hits.deinit(allocator);
    for (base) |h| try classify.appendUniquePreferHigher(allocator, &hits, h);
    allocator.free(base);
    for (residual) |h| try classify.appendUniquePreferHigher(allocator, &hits, h);
    for (hits.items) |hit| {
        std.debug.assert(ids.isKnownEffectId(hit.id));
    }
    return try hits.toOwnedSlice(allocator);
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
    const hits = try classifyToolCallWithResidual(std.testing.allocator, null, "acme_mailer_job", null, false);
    defer std.testing.allocator.free(hits);
    for (hits) |h| {
        try std.testing.expect(!std.mem.startsWith(u8, h.matcher, "classifier.local."));
    }
}

test "residual name acme_mailer_job can hit comms.message low" {
    const hits = try classifyToolCallWithResidual(std.testing.allocator, null, "acme_mailer_job", null, true);
    defer std.testing.allocator.free(hits);
    var found = false;
    for (hits) |h| {
        if (std.mem.eql(u8, h.id, "comms.message") and std.mem.startsWith(u8, h.matcher, "classifier.local.")) {
            found = true;
            try std.testing.expect(h.confidence == .low);
        }
    }
    try std.testing.expect(found);
}

test "send_email remains catalog high; residual does not replace" {
    const hits = try classifyToolCallWithResidual(std.testing.allocator, null, "send_email", null, true);
    defer std.testing.allocator.free(hits);
    try std.testing.expect(hits.len >= 1);
    try std.testing.expectEqualStrings("comms.message", hits[0].id);
    try std.testing.expect(hits[0].confidence == .high);
    try std.testing.expect(std.mem.startsWith(u8, hits[0].matcher, "catalog."));
    for (hits) |h| {
        try std.testing.expect(!std.mem.startsWith(u8, h.matcher, "classifier.local."));
    }
}

test "notify with to+body stays structural medium; residual does not replace" {
    const keys = [_][]const u8{ "to", "body" };
    const hits = try classifyToolCallWithResidual(std.testing.allocator, null, "notify", .{ .keys = &keys }, true);
    defer std.testing.allocator.free(hits);
    var found = false;
    for (hits) |h| {
        if (std.mem.eql(u8, h.id, "comms.message") and std.mem.startsWith(u8, h.matcher, "structural.")) {
            found = true;
            try std.testing.expect(h.confidence == .medium);
        }
        try std.testing.expect(!std.mem.startsWith(u8, h.matcher, "classifier.local."));
    }
    try std.testing.expect(found);
}

test "forced unavailable returns ClassifierUnavailable" {
    testing_force_unavailable = true;
    defer testing_force_unavailable = false;
    try std.testing.expectError(
        error.ClassifierUnavailable,
        classifyToolCallWithResidual(std.testing.allocator, null, "acme_mailer_job", null, true),
    );
}

test "hard-excluded shell tools do not residual to comms" {
    // Bash is catalog high shell.exec so residual gate already skips; double-check no classifier matchers.
    const hits = try classifyToolCallWithResidual(std.testing.allocator, null, "Bash", null, true);
    defer std.testing.allocator.free(hits);
    for (hits) |h| {
        try std.testing.expect(!std.mem.startsWith(u8, h.matcher, "classifier.local."));
        try std.testing.expect(!std.mem.eql(u8, h.id, "comms.message"));
    }
}

test "outbound residual name can emit unknown.external" {
    const hits = try classifyToolCallWithResidual(std.testing.allocator, null, "weird_outbound_helper", null, true);
    defer std.testing.allocator.free(hits);
    var found = false;
    for (hits) |h| {
        if (std.mem.eql(u8, h.id, "unknown.external") and std.mem.startsWith(u8, h.matcher, "classifier.local.")) {
            found = true;
            try std.testing.expect(h.confidence == .low);
        }
    }
    try std.testing.expect(found);
}

test "EffectsClassifier parse aliases" {
    const schema = @import("../schema.zig");
    try std.testing.expect(schema.EffectsClassifier.parse("off").? == .off);
    try std.testing.expect(schema.EffectsClassifier.parse("local").? == .local);
    try std.testing.expect(schema.EffectsClassifier.parse("local-embed").? == .local);
    try std.testing.expect(schema.EffectsClassifier.parse("local_embed").? == .local);
    try std.testing.expect(schema.EffectsClassifier.parse("cloud") == null);
}
