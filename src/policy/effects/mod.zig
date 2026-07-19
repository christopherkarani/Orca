//! Effect-class policy: classify tool calls into semantic effects and match policy rules.
//!
//! Phase A: deterministic catalog over tool names (host PreToolUse + MCP tools/call).
//! Phase B: structural args, network host tags, shell command bypass (Zig path).

pub const ids = @import("ids.zig");
pub const catalog = @import("catalog.zig");
pub const structural = @import("structural.zig");
pub const classify = @import("classify.zig");
pub const network_tags = @import("network_tags.zig");
pub const shell_bypass = @import("shell_bypass.zig");
pub const evaluate = @import("evaluate.zig");

pub const Confidence = catalog.Confidence;
pub const EffectHit = catalog.EffectHit;
pub const ToolArgsView = structural.ToolArgsView;
pub const OwnedArgsView = structural.OwnedArgsView;

/// Name-only classification (Phase A). Prefer `classifyToolCall` when args are available.
pub const classifyToolName = classify.classifyToolName;
pub const classifyToolCall = classify.classifyToolCall;
pub const normalizeToolName = catalog.normalizeToolName;
pub const toolArgsViewFromJsonObject = structural.toolArgsViewFromJsonObject;

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
    _ = structural;
    _ = classify;
    _ = network_tags;
    _ = shell_bypass;
    _ = evaluate;
}
