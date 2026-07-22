//! In-process Zig shell command evaluator (MVP).
//!
//! Owns security decisions for `orca hook` / `orca run` / shims when
//! `ORCA_SHELL_EVAL=zig` (product default after Phase 4). Matching is
//! structured argv/token rules for core destructive packs — not a regex port.

const std = @import("std");

pub const types = @import("types.zig");
pub const tokenize = @import("tokenize.zig");
pub const packs = @import("packs.zig");
pub const allowlist = @import("allowlist.zig");

pub const Decision = types.Decision;
pub const Severity = types.Severity;

pub const Evaluation = struct {
    decision: Decision,
    rule_id: ?[]const u8 = null,
    pack_id: ?[]const u8 = null,
    pattern_name: ?[]const u8 = null,
    severity: Severity = .high,
    reason: []const u8,
    explanation: ?[]const u8 = null,
    /// Heap-owned copies freed by `deinit`.
    owned: bool = false,

    pub fn deinit(self: *Evaluation, allocator: std.mem.Allocator) void {
        if (!self.owned) return;
        if (self.rule_id) |s| allocator.free(s);
        if (self.pack_id) |s| allocator.free(s);
        if (self.pattern_name) |s| allocator.free(s);
        allocator.free(self.reason);
        if (self.explanation) |s| allocator.free(s);
        self.* = undefined;
    }
};

pub const EvaluateOptions = struct {
    cwd: ?[]const u8 = null,
    /// When set, matching allowlist entries force allow.
    allowlists: ?allowlist.Layered = null,
};

/// Evaluate a shell command line. Fail-closed: empty / unparseable → deny.
pub fn evaluateCommand(allocator: std.mem.Allocator, command: []const u8, options: EvaluateOptions) !Evaluation {
    const trimmed = std.mem.trim(u8, command, " \t\r\n");
    if (trimmed.len == 0) {
        return denyStatic("zig.shell:empty", "zig.shell", "empty", .critical, "Empty command blocked by Orca shell evaluator.");
    }

    if (options.allowlists) |lists| {
        if (lists.allows(trimmed)) {
            return allowStatic("Command allowed by allowlist.");
        }
    }

    // Safe-pattern short-circuit (inspection commands).
    if (packs.isSafeCommand(trimmed)) {
        return allowStatic("Matched a safe inspection pattern.");
    }

    if (packs.matchDestructive(trimmed)) |hit| {
        const rule_id = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ hit.pack_id, hit.pattern_name });
        errdefer allocator.free(rule_id);
        const pack_copy = try allocator.dupe(u8, hit.pack_id);
        errdefer allocator.free(pack_copy);
        const pattern_copy = try allocator.dupe(u8, hit.pattern_name);
        errdefer allocator.free(pattern_copy);
        const reason_copy = try allocator.dupe(u8, hit.reason);
        errdefer allocator.free(reason_copy);
        const explanation_copy = if (hit.explanation) |e| try allocator.dupe(u8, e) else null;
        return .{
            .decision = .deny,
            .rule_id = rule_id,
            .pack_id = pack_copy,
            .pattern_name = pattern_copy,
            .severity = hit.severity,
            .reason = reason_copy,
            .explanation = explanation_copy,
            .owned = true,
        };
    }

    _ = options.cwd;
    return allowStatic("No destructive pack matched.");
}

fn allowStatic(reason: []const u8) Evaluation {
    return .{
        .decision = .allow,
        .severity = .low,
        .reason = reason,
        .owned = false,
    };
}

fn denyStatic(
    rule_id: []const u8,
    pack_id: []const u8,
    pattern_name: []const u8,
    severity: Severity,
    reason: []const u8,
) Evaluation {
    return .{
        .decision = .deny,
        .rule_id = rule_id,
        .pack_id = pack_id,
        .pattern_name = pattern_name,
        .severity = severity,
        .reason = reason,
        .owned = false,
    };
}

/// Compare allow/deny against a golden corpus JSONL line shape.
pub const CorpusCase = struct {
    command: []const u8,
    expected: []const u8,
    rule_id: ?[]const u8 = null,
    deferred: bool = false,
};

pub fn decisionMatches(eval: Evaluation, expected: []const u8) bool {
    return std.mem.eql(u8, eval.decision.toString(), expected);
}

test "evaluateCommand denies rm -rf root" {
    var eval = try evaluateCommand(std.testing.allocator, "rm -rf /", .{});
    defer eval.deinit(std.testing.allocator);
    try std.testing.expect(eval.decision == .deny);
    try std.testing.expect(eval.rule_id != null);
    try std.testing.expect(std.mem.indexOf(u8, eval.rule_id.?, "rm-rf") != null);
}

test "evaluateCommand allows git status" {
    var eval = try evaluateCommand(std.testing.allocator, "git status", .{});
    defer eval.deinit(std.testing.allocator);
    try std.testing.expect(eval.decision == .allow);
}

test "evaluateCommand denies git reset --hard" {
    var eval = try evaluateCommand(std.testing.allocator, "git reset --hard", .{});
    defer eval.deinit(std.testing.allocator);
    try std.testing.expect(eval.decision == .deny);
    try std.testing.expectEqualStrings("core.git:reset-hard", eval.rule_id.?);
}

test "evaluateCommand denies mkfs" {
    var eval = try evaluateCommand(std.testing.allocator, "mkfs.ext4 /dev/sda1", .{});
    defer eval.deinit(std.testing.allocator);
    try std.testing.expect(eval.decision == .deny);
}

test "evaluateCommand empty denies" {
    var eval = try evaluateCommand(std.testing.allocator, "   ", .{});
    defer eval.deinit(std.testing.allocator);
    try std.testing.expect(eval.decision == .deny);
}

test {
    _ = tokenize;
    _ = packs;
    _ = allowlist;
    _ = @import("corpus_test.zig");
}
