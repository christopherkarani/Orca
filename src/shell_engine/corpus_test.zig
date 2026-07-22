//! Corpus parity tests for the Zig shell engine vs frozen oracle goldens.
const std = @import("std");
const shell_engine = @import("mod.zig");

const parity_corpus = @embedFile("parity_corpus.jsonl");
const mvp_corpus = @embedFile("mvp_corpus.jsonl");
const security_regressions = @embedFile("security_regressions.jsonl");

const Case = struct {
    command: []const u8,
    expected: []const u8,
    rule_id: ?[]const u8 = null,
    deferred: bool = false,
};

fn parseLine(allocator: std.mem.Allocator, line: []const u8) !Case {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, line, .{});
    defer parsed.deinit();
    const obj = parsed.value.object;
    const command = try allocator.dupe(u8, obj.get("command").?.string);
    errdefer allocator.free(command);
    const expected = try allocator.dupe(u8, obj.get("expected").?.string);
    errdefer allocator.free(expected);
    var rule_id: ?[]const u8 = null;
    if (obj.get("rule_id")) |rid| {
        if (rid == .string) rule_id = try allocator.dupe(u8, rid.string);
    }
    const deferred = if (obj.get("deferred")) |d| d.bool else false;
    return .{ .command = command, .expected = expected, .rule_id = rule_id, .deferred = deferred };
}

fn freeCase(allocator: std.mem.Allocator, case: Case) void {
    allocator.free(case.command);
    allocator.free(case.expected);
    if (case.rule_id) |r| allocator.free(r);
}

/// Accept exact rule_id match, same pack+pattern family, or documented aliases.
/// Oracle heredoc.* virtual rule_ids map to core pack patterns when the body
/// is evaluated as an embed (decision parity first; attribution family second).
fn ruleIdMatches(got: []const u8, want: []const u8) bool {
    if (std.mem.eql(u8, got, want)) return true;
    const want_colon = std.mem.indexOfScalar(u8, want, ':');
    const got_colon = std.mem.indexOfScalar(u8, got, ':');
    if (want_colon == null or got_colon == null) return false;
    const want_pack = want[0..want_colon.?];
    const got_pack = got[0..got_colon.?];
    const want_pat = want[want_colon.? + 1 ..];
    const got_pat = got[got_colon.? + 1 ..];

    if (std.mem.eql(u8, want_pack, got_pack)) {
        if (std.mem.eql(u8, want_pat, got_pat)) return true;
        if (std.mem.startsWith(u8, got_pat, "rm-") and std.mem.startsWith(u8, want_pat, "rm-")) return true;
        if (std.mem.startsWith(u8, got_pat, "push-force") and std.mem.startsWith(u8, want_pat, "push-force")) return true;
        if (std.mem.startsWith(u8, got_pat, "find-delete") and std.mem.startsWith(u8, want_pat, "find-delete")) return true;
        return false;
    }

    // Documented aliases: oracle heredoc/inline-code attribution → pack patterns.
    if (std.mem.startsWith(u8, want_pack, "heredoc.")) {
        if (std.mem.eql(u8, got_pack, "core.filesystem") and
            (std.mem.startsWith(u8, got_pat, "rm-") or std.mem.indexOf(u8, got_pat, "delete") != null))
            return true;
        if (std.mem.eql(u8, got_pack, "core.git") and std.mem.indexOf(u8, want_pat, "git") != null)
            return true;
    }
    return false;
}

fn runCorpus(allocator: std.mem.Allocator, corpus: []const u8, require_100: bool, enforce_rule_id: bool) !void {
    var total: usize = 0;
    var matched: usize = 0;
    var deferred: usize = 0;
    var rule_checked: usize = 0;
    var mismatches: std.ArrayList([]const u8) = .empty;
    defer {
        for (mismatches.items) |m| allocator.free(m);
        mismatches.deinit(allocator);
    }

    var it = std.mem.splitScalar(u8, corpus, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        const case = try parseLine(allocator, line);
        defer freeCase(allocator, case);
        if (case.deferred) {
            deferred += 1;
            continue;
        }
        total += 1;
        var eval = try shell_engine.evaluateCommand(allocator, case.command, .{});
        defer eval.deinit(allocator);
        var ok = shell_engine.decisionMatches(eval, case.expected);
        if (ok and enforce_rule_id) {
            if (case.rule_id) |want| {
                rule_checked += 1;
                if (std.mem.eql(u8, case.expected, "deny")) {
                    if (eval.rule_id) |got| {
                        if (!ruleIdMatches(got, want)) {
                            ok = false;
                        }
                    } else {
                        ok = false;
                    }
                }
            }
        }
        if (ok) {
            matched += 1;
        } else {
            const msg = try std.fmt.allocPrint(allocator, "{s}: expected={s} got={s} rule_got={s} rule_want={s}", .{
                case.command,
                case.expected,
                eval.decision.toString(),
                eval.rule_id orelse "-",
                case.rule_id orelse "-",
            });
            try mismatches.append(allocator, msg);
        }
    }

    try std.testing.expect(total > 0);
    const pct = (matched * 100) / total;
    if (pct < 100 or mismatches.items.len > 0) {
        std.debug.print("corpus match {d}/{d} ({d}%) deferred={d} rule_id_checked={d}\n", .{ matched, total, pct, deferred, rule_checked });
        const limit = @min(mismatches.items.len, 40);
        for (mismatches.items[0..limit]) |m| std.debug.print("  mismatch: {s}\n", .{m});
    }
    if (require_100) {
        try std.testing.expect(matched == total);
        try std.testing.expect(total >= 350 or !enforce_rule_id); // security set is smaller
    } else {
        try std.testing.expect(pct >= 95);
    }
}

test "shell_engine parity corpus decision+rule_id match 100%" {
    try runCorpus(std.testing.allocator, parity_corpus, true, true);
}

test "shell_engine MVP corpus still green" {
    try runCorpus(std.testing.allocator, mvp_corpus, false, false);
}

test "shell_engine security regressions allow/deny 100%" {
    try runCorpus(std.testing.allocator, security_regressions, true, false);
}
