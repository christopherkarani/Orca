const std = @import("std");

pub const DecisionResult = enum {
    allow,
    deny,
    ask,
    redact,
    stage,
    broker,
    observe,

    pub fn toString(self: DecisionResult) []const u8 {
        return @tagName(self);
    }
};

pub const Decision = struct {
    result: DecisionResult,
    rule_id: ?[]const u8 = null,
    reason: []const u8,
    risk_score: ?u8 = null,
    requires_user: bool = false,
    ci_may_proceed: bool = false,

    pub fn allowsExecution(self: Decision, ci_mode: bool) bool {
        if (ci_mode and !self.ci_may_proceed) return false;
        return self.result == .allow or self.result == .observe;
    }
};

test "decision result conversion is deterministic" {
    try std.testing.expectEqualStrings("allow", DecisionResult.allow.toString());
    try std.testing.expectEqualStrings("broker", DecisionResult.broker.toString());

    const ask: Decision = .{
        .result = .ask,
        .reason = "approval required",
        .requires_user = true,
    };
    try std.testing.expect(!ask.allowsExecution(false));
    try std.testing.expect(!ask.allowsExecution(true));

    const allow_ci: Decision = .{
        .result = .allow,
        .reason = "explicit allow",
        .ci_may_proceed = true,
    };
    try std.testing.expect(allow_ci.allowsExecution(true));
}
