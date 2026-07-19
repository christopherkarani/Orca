//! Match classified effect hits against effect policy patterns.

const std = @import("std");
const catalog = @import("catalog.zig");
const ids = @import("ids.zig");

pub const EffectDecisionKind = enum {
    allow,
    deny,
    ask,
    observe,
    /// No effect pattern matched and no default applied.
    none,

    pub fn toString(self: EffectDecisionKind) []const u8 {
        return @tagName(self);
    }

    pub fn severity(self: EffectDecisionKind) u8 {
        return switch (self) {
            .deny => 4,
            .ask => 3,
            .allow => 2,
            .observe => 1,
            .none => 0,
        };
    }
};

pub const EffectMatch = struct {
    kind: EffectDecisionKind,
    effect_id: []const u8,
    pattern: []const u8,
    matcher: []const u8,
    confidence: catalog.Confidence,
};

pub const EffectsRuleView = struct {
    allow: []const []const u8 = &.{},
    deny: []const []const u8 = &.{},
    ask: []const []const u8 = &.{},
    /// When set, used for hits that do not match allow/deny/ask.
    default: ?EffectDecisionKind = null,
};

fn findPattern(effect_id: []const u8, patterns: []const []const u8) ?[]const u8 {
    for (patterns) |pattern| {
        if (ids.matchesPolicyPattern(effect_id, pattern)) return pattern;
    }
    return null;
}

/// Evaluate hits against effect rules. Deny beats ask beats allow.
/// Returns `.none` when there are no hits, or hits exist but no rule/default applies.
pub fn evaluateHits(hits: []const catalog.EffectHit, rules: EffectsRuleView) EffectMatch {
    var best: EffectMatch = .{
        .kind = .none,
        .effect_id = "",
        .pattern = "",
        .matcher = "",
        .confidence = .low,
    };

    for (hits) |hit| {
        if (findPattern(hit.id, rules.deny)) |pattern| {
            const candidate: EffectMatch = .{
                .kind = .deny,
                .effect_id = hit.id,
                .pattern = pattern,
                .matcher = hit.matcher,
                .confidence = hit.confidence,
            };
            if (candidate.kind.severity() > best.kind.severity()) best = candidate;
            continue;
        }
        if (findPattern(hit.id, rules.ask)) |pattern| {
            const candidate: EffectMatch = .{
                .kind = .ask,
                .effect_id = hit.id,
                .pattern = pattern,
                .matcher = hit.matcher,
                .confidence = hit.confidence,
            };
            if (candidate.kind.severity() > best.kind.severity()) best = candidate;
            continue;
        }
        if (findPattern(hit.id, rules.allow)) |pattern| {
            const candidate: EffectMatch = .{
                .kind = .allow,
                .effect_id = hit.id,
                .pattern = pattern,
                .matcher = hit.matcher,
                .confidence = hit.confidence,
            };
            if (candidate.kind.severity() > best.kind.severity()) best = candidate;
            continue;
        }
        if (rules.default) |default_kind| {
            if (default_kind == .none) continue;
            const candidate: EffectMatch = .{
                .kind = default_kind,
                .effect_id = hit.id,
                .pattern = "effects.default",
                .matcher = hit.matcher,
                .confidence = hit.confidence,
            };
            if (candidate.kind.severity() > best.kind.severity()) best = candidate;
        }
    }

    return best;
}

test "deny beats allow when multiple effects hit" {
    const hits = [_]catalog.EffectHit{
        .{ .id = "fs.read", .confidence = .high, .matcher = "m1" },
        .{ .id = "comms.message", .confidence = .high, .matcher = "m2" },
    };
    const result = evaluateHits(&hits, .{
        .allow = &.{"fs.read"},
        .deny = &.{"comms.message"},
    });
    try std.testing.expect(result.kind == .deny);
    try std.testing.expectEqualStrings("comms.message", result.effect_id);
    try std.testing.expectEqualStrings("comms.message", result.pattern);
}

test "wildcard deny covers family" {
    const hits = [_]catalog.EffectHit{
        .{ .id = "comms.publish", .confidence = .high, .matcher = "m" },
    };
    const result = evaluateHits(&hits, .{
        .deny = &.{"comms.*"},
    });
    try std.testing.expect(result.kind == .deny);
    try std.testing.expectEqualStrings("comms.*", result.pattern);
}

test "default applies when no explicit rule" {
    const hits = [_]catalog.EffectHit{
        .{ .id = "unknown.external", .confidence = .low, .matcher = "h" },
    };
    const result = evaluateHits(&hits, .{
        .default = .ask,
    });
    try std.testing.expect(result.kind == .ask);
    try std.testing.expectEqualStrings("effects.default", result.pattern);
}

test "no hits yields none" {
    const result = evaluateHits(&.{}, .{
        .deny = &.{"comms.*"},
        .default = .deny,
    });
    try std.testing.expect(result.kind == .none);
}

test "explicit allow without deny" {
    const hits = [_]catalog.EffectHit{
        .{ .id = "shell.exec", .confidence = .high, .matcher = "m" },
    };
    const result = evaluateHits(&hits, .{
        .allow = &.{"shell.exec"},
        .deny = &.{"comms.*"},
    });
    try std.testing.expect(result.kind == .allow);
}
