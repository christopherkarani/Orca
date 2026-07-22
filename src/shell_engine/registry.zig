//! Oracle pack registry: embed all pack patterns and match via PCRE2.
const std = @import("std");
const regex_pcre = @import("regex_pcre.zig");
const Severity = @import("types.zig").Severity;

const packs_json = @embedFile("oracle_packs.json");

pub const Hit = struct {
    pack_id: []const u8,
    pattern_name: []const u8,
    severity: Severity,
    reason: []const u8,
};

const CompiledPattern = struct {
    name: []const u8,
    reason: []const u8,
    severity: Severity,
    regex: regex_pcre.Regex,
};

const CompiledPack = struct {
    id: []const u8,
    keywords: []const []const u8,
    safe: []CompiledPattern,
    destructive: []CompiledPattern,
    /// Whether this pack is active under the product default pack set
    /// (Rust `Config::default()`: category `core` + `system.disk`).
    default_enabled: bool,
};

var g_packs: []CompiledPack = &.{};
/// 0=uninit, 1=ok, 2=failed
var g_state: std.atomic.Value(u8) = .init(0);
var g_arena: std.heap.ArenaAllocator = undefined;

fn initOnce() !void {
    // Process-lifetime arena (not testing allocator — avoids leak noise).
    g_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const a = g_arena.allocator();

    const parsed = try std.json.parseFromSlice(std.json.Value, a, packs_json, .{});
    const root = parsed.value;
    if (root != .array) return error.BadPacksJson;

    var packs_list: std.ArrayList(CompiledPack) = .empty;
    for (root.array.items) |item| {
        const obj = item.object;
        const id = obj.get("id").?.string;
        if (std.mem.eql(u8, id, "test.deadline")) continue;

        var keywords: std.ArrayList([]const u8) = .empty;
        if (obj.get("keywords")) |kw| {
            if (kw == .array) {
                for (kw.array.items) |k| {
                    try keywords.append(a, try a.dupe(u8, k.string));
                }
            }
        }

        const safe = try compileList(a, obj.get("safe"));
        const destructive = try compileList(a, obj.get("destructive"));

        const default_enabled = isDefaultEnabled(id);
        try packs_list.append(a, .{
            .id = try a.dupe(u8, id),
            .keywords = try keywords.toOwnedSlice(a),
            .safe = safe,
            .destructive = destructive,
            .default_enabled = default_enabled,
        });
    }
    g_packs = try packs_list.toOwnedSlice(a);
}

/// Rust default: always enable category `core` (all `core.*`) and `system.disk`.
fn isDefaultEnabled(id: []const u8) bool {
    if (std.mem.startsWith(u8, id, "core.")) return true;
    if (std.mem.eql(u8, id, "system.disk")) return true;
    return false;
}

pub fn ensureInit() !void {
    const state = g_state.load(.acquire);
    if (state == 1) return;
    if (state == 2) return error.RegistryInitFailed;

    // Best-effort single init (evaluate path is typically single-threaded per process).
    if (g_state.cmpxchgStrong(0, 3, .acq_rel, .acquire)) |cur| {
        if (cur == 1) return;
        if (cur == 2) return error.RegistryInitFailed;
        // another thread is initializing (3) — spin briefly
        while (g_state.load(.acquire) == 3) {
            std.atomic.spinLoopHint();
        }
        if (g_state.load(.acquire) == 1) return;
        return error.RegistryInitFailed;
    }

    initOnce() catch {
        g_state.store(2, .release);
        return error.RegistryInitFailed;
    };
    if (g_packs.len == 0) {
        g_state.store(2, .release);
        return error.RegistryInitFailed;
    }
    g_state.store(1, .release);
}

pub fn packCount() usize {
    return g_packs.len;
}

fn mightMatch(pack: CompiledPack, cmd: []const u8) bool {
    if (pack.keywords.len == 0) return true;
    for (pack.keywords) |kw| {
        if (std.mem.indexOf(u8, cmd, kw) != null) return true;
    }
    return false;
}

pub const MatchResult = union(enum) {
    allow_safe,
    allow_miss,
    deny: Hit,
};

pub const MatchOptions = struct {
    /// When true (default), only packs enabled under Rust `Config::default()`.
    /// Set false to evaluate the full 85-pack set.
    default_packs_only: bool = true,
};

/// Match packs on a single (already normalized/sanitized) command.
/// Mirrors Rust `check_command_single`: any safe → allow; else first destructive → deny.
pub fn matchCommandDetailed(cmd: []const u8) MatchResult {
    return matchCommandDetailedOpts(cmd, .{});
}

pub fn matchCommandDetailedOpts(cmd: []const u8, opts: MatchOptions) MatchResult {
    if (g_packs.len == 0) return .allow_miss;

    for (g_packs) |pack| {
        if (opts.default_packs_only and !pack.default_enabled) continue;
        if (!mightMatch(pack, cmd)) continue;
        for (pack.safe) |pat| {
            if (pat.regex.isMatch(cmd)) return .allow_safe;
        }
    }
    for (g_packs) |pack| {
        if (opts.default_packs_only and !pack.default_enabled) continue;
        if (!mightMatch(pack, cmd)) continue;
        for (pack.destructive) |pat| {
            if (pat.regex.isMatch(cmd)) {
                return .{ .deny = .{
                    .pack_id = pack.id,
                    .pattern_name = pat.name,
                    .severity = pat.severity,
                    .reason = if (pat.reason.len > 0)
                        pat.reason
                    else
                        "Destructive command blocked by Orca pack.",
                } };
            }
        }
    }
    return .allow_miss;
}

pub fn defaultEnabledPackCount() usize {
    var n: usize = 0;
    for (g_packs) |p| {
        if (p.default_enabled) n += 1;
    }
    return n;
}

/// Embedded oracle pattern totals (must match extract from frozen orca-rs packs).
pub const expected_destructive_patterns: usize = 792;
pub const expected_safe_patterns: usize = 830;

fn compileList(a: std.mem.Allocator, val: ?std.json.Value) ![]CompiledPattern {
    var list: std.ArrayList(CompiledPattern) = .empty;
    const arr = if (val) |v| (if (v == .array) v.array.items else &[_]std.json.Value{}) else &[_]std.json.Value{};
    for (arr) |pat| {
        const o = pat.object;
        const name = if (o.get("name")) |n| (if (n == .string) n.string else "unnamed") else "unnamed";
        const regex_s = o.get("regex").?.string;
        const reason = if (o.get("reason")) |r| (if (r == .string) r.string else "") else "";
        const sev_s = if (o.get("severity")) |s| (if (s == .string) s.string else "high") else "high";
        const severity: Severity = if (std.mem.eql(u8, sev_s, "critical"))
            .critical
        else if (std.mem.eql(u8, sev_s, "medium"))
            .medium
        else if (std.mem.eql(u8, sev_s, "low"))
            .low
        else
            .high;

        // Fail closed: do not silently drop patterns (would shrink the guard).
        const cre = regex_pcre.Regex.compile(regex_s) catch return error.PatternCompileFailed;
        try list.append(a, .{
            .name = try a.dupe(u8, name),
            .reason = try a.dupe(u8, reason),
            .severity = severity,
            .regex = cre,
        });
    }
    return try list.toOwnedSlice(a);
}

/// Count compiled patterns across all loaded packs (post-init).
pub fn compiledPatternCounts() struct { destructive: usize, safe: usize } {
    var d: usize = 0;
    var s: usize = 0;
    for (g_packs) |p| {
        d += p.destructive.len;
        s += p.safe.len;
    }
    return .{ .destructive = d, .safe = s };
}

test "registry loads packs and matches git reset" {
    try ensureInit();
    try std.testing.expect(packCount() >= 85);
    const r = matchCommandDetailed("git reset --hard");
    try std.testing.expect(r == .deny);
    try std.testing.expectEqualStrings("core.git", r.deny.pack_id);
}

test "registry compiled pattern counts match embedded oracle totals" {
    try ensureInit();
    const counts = compiledPatternCounts();
    try std.testing.expectEqual(@as(usize, expected_destructive_patterns), counts.destructive);
    try std.testing.expectEqual(@as(usize, expected_safe_patterns), counts.safe);
}
