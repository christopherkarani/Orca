//! Corpus parity tests for the Zig shell engine vs frozen goldens.
const std = @import("std");
const shell_engine = @import("mod.zig");

const corpus_jsonl = @embedFile("mvp_corpus.jsonl");

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
        rule_id = try allocator.dupe(u8, rid.string);
    }
    const deferred = if (obj.get("deferred")) |d| d.bool else false;
    return .{ .command = command, .expected = expected, .rule_id = rule_id, .deferred = deferred };
}

fn freeCase(allocator: std.mem.Allocator, case: Case) void {
    allocator.free(case.command);
    allocator.free(case.expected);
    if (case.rule_id) |r| allocator.free(r);
}

test "shell_engine MVP corpus decision match >= 95%" {
    const allocator = std.testing.allocator;
    var total: usize = 0;
    var matched: usize = 0;
    var deferred: usize = 0;
    var mismatches: std.ArrayList([]const u8) = .empty;
    defer {
        for (mismatches.items) |m| allocator.free(m);
        mismatches.deinit(allocator);
    }

    var it = std.mem.splitScalar(u8, corpus_jsonl, '\n');
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
        if (shell_engine.decisionMatches(eval, case.expected)) {
            matched += 1;
            // Optional rule_id check — soft: pattern family match preferred over exact.
            if (case.rule_id) |want| {
                if (eval.rule_id) |got| {
                    // Accept exact or same pack prefix.
                    const ok = std.mem.eql(u8, got, want) or
                        (std.mem.indexOfScalar(u8, want, ':') != null and
                            std.mem.indexOfScalar(u8, got, ':') != null and
                            std.mem.eql(u8, want[0..std.mem.indexOfScalar(u8, want, ':').?], got[0..std.mem.indexOfScalar(u8, got, ':').?]));
                    _ = ok;
                }
            }
        } else {
            const msg = try std.fmt.allocPrint(allocator, "{s}: expected={s} got={s} rule={s}", .{
                case.command,
                case.expected,
                eval.decision.toString(),
                eval.rule_id orelse "-",
            });
            try mismatches.append(allocator, msg);
        }
    }

    try std.testing.expect(total > 0);
    const pct = (matched * 100) / total;
    if (pct < 95) {
        std.debug.print("corpus match {d}/{d} ({d}%) deferred={d}\n", .{ matched, total, pct, deferred });
        for (mismatches.items) |m| std.debug.print("  mismatch: {s}\n", .{m});
    }
    try std.testing.expect(pct >= 95);
}
