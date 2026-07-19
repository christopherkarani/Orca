//! Effect-class policy: classify tool calls into semantic effects and match policy rules.
//!
//! Phase A: deterministic catalog over tool names (host PreToolUse + MCP tools/call).
//! Structural args, network/shell cross-links, and optional classifiers come later.

pub const ids = @import("ids.zig");
pub const catalog = @import("catalog.zig");
pub const classify = catalog; // classifyToolName lives on catalog for a single table module
pub const evaluate = @import("evaluate.zig");

pub const Confidence = catalog.Confidence;
pub const EffectHit = catalog.EffectHit;
pub const classifyToolName = catalog.classifyToolName;
pub const normalizeToolName = catalog.normalizeToolName;

pub const isKnownEffectId = ids.isKnownEffectId;
pub const isValidEffectPattern = ids.isValidEffectPattern;
pub const matchesPolicyPattern = ids.matchesPolicyPattern;
pub const known_ids = ids.known_ids;

pub const EffectDecisionKind = evaluate.EffectDecisionKind;
pub const EffectMatch = evaluate.EffectMatch;
pub const EffectsRuleView = evaluate.EffectsRuleView;
pub const evaluateHits = evaluate.evaluateHits;

test {
    _ = ids;
    _ = catalog;
    _ = evaluate;
}
