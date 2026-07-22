//! In-process Zig shell command evaluator.
//!
//! Owns security decisions for `orca hook` / `orca run` / shims.
//! Pack patterns are the frozen orca-rs oracle set (embedded JSON + PCRE2).
//! Evaluator errors fail closed with deny.

const std = @import("std");

pub const types = @import("types.zig");
pub const tokenize = @import("tokenize.zig");
pub const packs = @import("packs.zig");
pub const allowlist = @import("allowlist.zig");
pub const registry = @import("registry.zig");
pub const segments = @import("segments.zig");
pub const normalize = @import("normalize.zig");
pub const sanitize = @import("sanitize.zig");

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
    allowlists: ?allowlist.Layered = null,
    /// When true (default), only core.* + system.disk (Rust Config::default).
    /// When false, evaluate the full 85-pack registry.
    default_packs_only: bool = true,
};

/// Evaluate a shell command line.
/// Empty command is a no-op allow (matches oracle). Registry init failure → deny.
pub fn evaluateCommand(allocator: std.mem.Allocator, command: []const u8, options: EvaluateOptions) !Evaluation {
    const trimmed = std.mem.trim(u8, command, " \t\r\n");
    if (trimmed.len == 0) {
        return allowStatic("Empty command is a no-op.");
    }

    if (options.allowlists) |lists| {
        if (lists.allows(trimmed)) {
            return allowStatic("Command allowed by allowlist.");
        }
    }

    registry.ensureInit() catch {
        return denyStatic("zig.shell:init", "zig.shell", "init-failure", .critical, "Shell pack registry failed to initialize (fail-closed).");
    };

    const match_opts = registry.MatchOptions{ .default_packs_only = options.default_packs_only };

    var candidates: std.ArrayList([]const u8) = .empty;
    defer candidates.deinit(allocator);

    // Non-executing heredocs (cat/tee/grep <<EOF …): mask bodies and do NOT
    // segment-split on newlines (body lines would otherwise be evaluated as
    // free-standing commands).
    const has_heredoc = std.mem.indexOf(u8, trimmed, "<<") != null;
    const is_herestring_only = std.mem.indexOf(u8, trimmed, "<<<") != null and
        std.mem.indexOf(u8, trimmed, "<<") == std.mem.indexOf(u8, trimmed, "<<<");
    var masked_storage: ?[]u8 = null;
    defer if (masked_storage) |m| allocator.free(m);
    // Embed buffers must outlive the candidate list (slices point into them).
    var embeds_owned: [][]const u8 = &.{};
    defer if (embeds_owned.len > 0) normalize.freeEmbeds(allocator, embeds_owned);

    // Non-executing heredocs: mask body only when a real terminator is found
    // (oracle `mask_non_executing_heredocs`). If the delimiter form cannot be
    // closed (e.g. `<<\EOF` vs terminator `EOF`), leave the body visible and
    // segment-split so free-standing destructive lines still deny (fail closed).
    if (has_heredoc and !is_herestring_only and !isExecutingContext(trimmed)) {
        masked_storage = try maskNonExecutingHeredoc(allocator, trimmed);
        const working = masked_storage.?;
        try candidates.append(allocator, working);
        try appendSegments(allocator, &candidates, working);
    } else {
        // Prefer per-segment evaluation so assignment values and safe prefixes
        // cannot poison a full-string regex match. Also keep the full command
        // for patterns that legitimately span segments (after sanitize).
        try appendSegments(allocator, &candidates, trimmed);
        if (candidates.items.len <= 1) {
            // No separators — evaluate the whole line.
            if (candidates.items.len == 0) try candidates.append(allocator, trimmed);
        } else {
            // Multi-segment: still include a sanitized full-string candidate for
            // spanning patterns, with assignment RHS masked.
            const masked_assign = try maskAssignmentValues(allocator, trimmed);
            if (masked_storage == null) {
                masked_storage = masked_assign;
                try candidates.append(allocator, masked_storage.?);
            } else {
                allocator.free(masked_assign);
            }
        }

        if (isExecutingContext(trimmed)) {
            embeds_owned = try normalize.extractEmbeds(allocator, trimmed);
            for (embeds_owned) |e| {
                try candidates.append(allocator, e);
                try appendSegments(allocator, &candidates, e);
            }
        }
    }

    for (candidates.items) |cand| {
        if (try evalOne(allocator, cand, match_opts)) |hit| {
            const rule_id = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ hit.pack_id, hit.pattern_name });
            errdefer allocator.free(rule_id);
            const pack_copy = try allocator.dupe(u8, hit.pack_id);
            errdefer allocator.free(pack_copy);
            const pattern_copy = try allocator.dupe(u8, hit.pattern_name);
            errdefer allocator.free(pattern_copy);
            const reason_copy = try allocator.dupe(u8, hit.reason);
            errdefer allocator.free(reason_copy);
            return .{
                .decision = .deny,
                .rule_id = rule_id,
                .pack_id = pack_copy,
                .pattern_name = pattern_copy,
                .severity = hit.severity,
                .reason = reason_copy,
                .explanation = null,
                .owned = true,
            };
        }
    }

    _ = options.cwd;
    return allowStatic("No destructive pack matched.");
}

/// True when the outer command is an executing shell/interpreter (not cat/tee/grep data sinks).
fn isExecutingContext(cmd: []const u8) bool {
    const exec_markers = [_][]const u8{
        "bash ", "bash\t", "sh ", "sh\t", "zsh ", "zsh\t", "ksh ", "dash ",
        "python ", "python3 ", "ruby ", "perl ", "node ",
        "/bash ", "/sh ", "/zsh ",
    };
    // Also path forms ending with shell names before -c
    if (std.mem.indexOf(u8, cmd, " -c ") != null or std.mem.indexOf(u8, cmd, " -c'") != null or
        std.mem.indexOf(u8, cmd, " -c\"") != null or std.mem.indexOf(u8, cmd, " -e ") != null)
    {
        for (exec_markers) |m| {
            if (std.mem.indexOf(u8, cmd, m) != null) return true;
        }
        // /usr/bin/bash -c
        if (std.mem.indexOf(u8, cmd, "/bash") != null or std.mem.indexOf(u8, cmd, "/python") != null)
            return true;
    }
    // bash <<EOF (heredoc into shell)
    if (std.mem.indexOf(u8, cmd, "<<") != null) {
        const data_sinks = [_][]const u8{ "cat ", "tee ", "grep ", "sed ", "awk ", "wc ", "sort ", "head ", "tail ", "base64 ", "md5", "curl ", "less ", "more " };
        for (data_sinks) |d| {
            const t = std.mem.trim(u8, cmd, " \t");
            if (std.mem.startsWith(u8, t, d)) return false;
        }
        // bare shell heredoc
        for (exec_markers) |m| {
            if (std.mem.indexOf(u8, cmd, m) != null) return true;
        }
        // `bash <<EOF` without trailing space after bash in marker
        if (std.mem.startsWith(u8, std.mem.trim(u8, cmd, " \t"), "bash") or
            std.mem.startsWith(u8, std.mem.trim(u8, cmd, " \t"), "sh") or
            std.mem.startsWith(u8, std.mem.trim(u8, cmd, " \t"), "zsh"))
            return true;
        return false;
    }
    if (std.mem.indexOf(u8, cmd, "<<<") != null) {
        // here-string often on shell
        return true;
    }
    return false;
}

fn appendSegments(allocator: std.mem.Allocator, candidates: *std.ArrayList([]const u8), cmd: []const u8) !void {
    const segs = try segments.splitCommandSegments(cmd, allocator);
    defer segments.freeSegments(allocator, segs);
    for (segs) |s| {
        try candidates.append(allocator, s);
    }
}

fn evalOne(allocator: std.mem.Allocator, cand: []const u8, match_opts: registry.MatchOptions) !?registry.Hit {
    const trimmed = std.mem.trim(u8, cand, " \t\r\n");
    if (trimmed.len == 0) return null;

    // Pure assignment segment (VAR=value) — not executed as a command word.
    if (isAssignmentOnly(trimmed)) return null;

    // Mask non-executing heredoc bodies (cat/tee/grep <<EOF …) so data cannot trigger packs.
    const masked_hd = try maskNonExecutingHeredoc(allocator, trimmed);
    defer allocator.free(masked_hd);

    const sanitized = try sanitize.sanitizeForMatching(allocator, masked_hd);
    defer allocator.free(sanitized);

    // Language-runtime destructive APIs inside -c/-e bodies (no pack regex covers these).
    if (matchLangDestruct(sanitized)) |h| return h;

    // ${TMPDIR:-/tmp}/… is a temp-family path (bash default expansion).
    const for_match = try rewriteTempDefault(allocator, sanitized);
    defer allocator.free(for_match);

    if (matchDeny(for_match, match_opts)) |h| return h;

    // Wrapper strip only on the sanitized form so false-positive data stays masked.
    var norm = try normalize.normalizeCommand(allocator, for_match);
    defer norm.deinit(allocator);
    if (matchDeny(norm.normalized, match_opts)) |h| return h;

    return null;
}

fn isAssignmentOnly(cmd: []const u8) bool {
    // NAME=VALUE with no leading command word.
    if (cmd.len == 0 or std.ascii.isDigit(cmd[0])) return false;
    var i: usize = 0;
    while (i < cmd.len and (std.ascii.isAlphanumeric(cmd[i]) or cmd[i] == '_')) : (i += 1) {}
    if (i == 0 or i >= cmd.len or cmd[i] != '=') return false;
    // Reject if there is another word that looks like a command after the value.
    // Simple: if the line is a single assignment token (possibly quoted value), treat as assignment.
    // `VAR=x cmd` is not assignment-only.
    var j = i + 1;
    if (j < cmd.len and (cmd[j] == '\'' or cmd[j] == '"')) {
        const q = cmd[j];
        j += 1;
        while (j < cmd.len and cmd[j] != q) : (j += 1) {}
        if (j < cmd.len) j += 1;
    } else {
        while (j < cmd.len and !std.ascii.isWhitespace(cmd[j])) : (j += 1) {}
    }
    while (j < cmd.len and std.ascii.isWhitespace(cmd[j])) : (j += 1) {}
    return j >= cmd.len;
}

fn matchLangDestruct(cmd: []const u8) ?registry.Hit {
    // shutil.rmtree / os.remove / FileUtils.rm_rf on sensitive paths.
    const apis = [_][]const u8{ "rmtree(", "os.remove(", "os.unlink(", "FileUtils.rm_rf(", "FileUtils.rm_r(", "Path.rmtree(" };
    var hit_api = false;
    for (apis) |a| {
        if (std.mem.indexOf(u8, cmd, a) != null) {
            hit_api = true;
            break;
        }
    }
    if (!hit_api) return null;
    // Any path-like argument or bare call → treat as destructive filesystem op.
    const sensitive = [_][]const u8{ "/home", "/etc", "/usr", "/var", "/root", "/tmp", "~", "$HOME", "'/'", "\"/\"" };
    for (sensitive) |s| {
        if (std.mem.indexOf(u8, cmd, s) != null) {
            return .{
                .pack_id = "core.filesystem",
                .pattern_name = "rm-rf-general",
                .severity = .high,
                .reason = "Language-runtime recursive delete (rmtree/remove) is destructive and requires human approval.",
            };
        }
    }
    // Even without sensitive path literal, rmtree/rm_rf is high risk.
    return .{
        .pack_id = "core.filesystem",
        .pattern_name = "rm-rf-general",
        .severity = .high,
        .reason = "Language-runtime recursive delete is destructive and requires human approval.",
    };
}

/// Mask `NAME=value` / `NAME='...'` / `NAME="..."` RHS so assignment text cannot
/// trigger pack regexes when evaluating a multi-segment full command.
fn maskAssignmentValues(allocator: std.mem.Allocator, cmd: []const u8) ![]u8 {
    const out = try allocator.dupe(u8, cmd);
    var i: usize = 0;
    while (i < out.len) {
        // start of potential NAME=
        if (i == 0 or out[i - 1] == ';' or out[i - 1] == '\n' or std.ascii.isWhitespace(out[i - 1]) or out[i - 1] == '&' or out[i - 1] == '|') {
            var j = i;
            if (j < out.len and (std.ascii.isAlphabetic(out[j]) or out[j] == '_')) {
                while (j < out.len and (std.ascii.isAlphanumeric(out[j]) or out[j] == '_')) : (j += 1) {}
                if (j < out.len and out[j] == '=') {
                    j += 1;
                    if (j < out.len and (out[j] == '\'' or out[j] == '"')) {
                        const q = out[j];
                        j += 1;
                        while (j < out.len and out[j] != q) : (j += 1) {
                            if (!std.ascii.isWhitespace(out[j])) out[j] = 'x';
                        }
                        i = if (j < out.len) j + 1 else j;
                        continue;
                    } else {
                        while (j < out.len and !std.ascii.isWhitespace(out[j]) and out[j] != ';' and out[j] != '&' and out[j] != '|') : (j += 1) {
                            out[j] = 'x';
                        }
                        i = j;
                        continue;
                    }
                }
            }
        }
        i += 1;
    }
    return out;
}

fn rewriteTempDefault(allocator: std.mem.Allocator, cmd: []const u8) ![]u8 {
    // Map ${TMPDIR:-/tmp} and ${TMPDIR:=/tmp} to $TMPDIR for safe-pattern matching.
    var out = try allocator.dupe(u8, cmd);
    const needles = [_][]const u8{ "${TMPDIR:-/tmp}", "${TMPDIR:=/tmp}", "${TMPDIR-:/tmp}" };
    for (needles) |n| {
        while (std.mem.indexOf(u8, out, n)) |idx| {
            // replace with $TMPDIR (shorter) — rebuild
            const new_len = out.len - n.len + "$TMPDIR".len;
            const rebuilt = try allocator.alloc(u8, new_len);
            @memcpy(rebuilt[0..idx], out[0..idx]);
            @memcpy(rebuilt[idx .. idx + 7], "$TMPDIR");
            @memcpy(rebuilt[idx + 7 ..], out[idx + n.len ..]);
            allocator.free(out);
            out = rebuilt;
        }
    }
    return out;
}

/// True when a non-executing heredoc was present but its body was not blanked
/// (missing/mismatched terminator). Used to enable fail-closed segment split.
fn heredocBodyLikelyUnmasked(masked: []const u8, original: []const u8) bool {
    // If masking blanked body bytes to 'x', non-ws content length drops.
    // Unmasked: original and masked share the same non-trivial payload.
    if (masked.len != original.len) return true;
    return std.mem.eql(u8, masked, original);
}

/// Blank out heredoc bodies when the receiver is a data sink (cat/tee/…), matching
/// Rust `mask_non_executing_heredocs` intent.
///
/// Only masks when a matching terminator line is found for the delimiter token
/// as written (including a leading `\` in unquoted forms). That matches the
/// oracle mask path: `<<\EOF` uses delimiter `\EOF` which does not match a
/// closing `EOF` line, so the body stays visible and pack matching fails closed.
fn maskNonExecutingHeredoc(allocator: std.mem.Allocator, cmd: []const u8) ![]u8 {
    const out = try allocator.dupe(u8, cmd);
    if (std.mem.indexOf(u8, cmd, "<<") == null) return out;
    if (isExecutingContext(cmd)) return out;

    // Find first << (not <<<)
    var i: usize = 0;
    while (i + 1 < out.len) : (i += 1) {
        if (out[i] == '<' and out[i + 1] == '<' and !(i + 2 < out.len and out[i + 2] == '<')) {
            var p = i + 2;
            // optional <<- / <<~ marker adjacent to <<
            if (p < out.len and (out[p] == '-' or out[p] == '~')) p += 1;
            while (p < out.len and (out[p] == ' ' or out[p] == '\t')) : (p += 1) {}

            // Parse delimiter token (quoted or bare, including leading `\`).
            var delim: []const u8 = "";
            if (p < out.len and (out[p] == '\'' or out[p] == '"')) {
                const q = out[p];
                p += 1;
                const start = p;
                while (p < out.len and out[p] != q) : (p += 1) {}
                delim = out[start..p];
                if (p < out.len) p += 1; // closing quote
            } else {
                const start = p;
                while (p < out.len and out[p] != ' ' and out[p] != '\t' and out[p] != '\n' and out[p] != '\r' and
                    out[p] != ';' and out[p] != '&' and out[p] != '|') : (p += 1)
                {}
                delim = out[start..p];
            }
            if (delim.len == 0) break;

            // Body starts after the newline following the delimiter token.
            while (p < out.len and out[p] != '\n') : (p += 1) {}
            if (p >= out.len) break;
            const body_start = p + 1;

            // Find terminator line equal to delim (oracle: exact line match).
            var search = body_start;
            var found_end: ?usize = null;
            while (search <= out.len) {
                const line_end = if (std.mem.indexOfScalar(u8, out[search..], '\n')) |n|
                    search + n
                else
                    out.len;
                const line = out[search..line_end];
                const line_trim = std.mem.trim(u8, line, " \t\r");
                if (std.mem.eql(u8, line_trim, delim)) {
                    found_end = search;
                    break;
                }
                if (line_end >= out.len) break;
                search = line_end + 1;
            }

            if (found_end) |body_end| {
                // Mask body only (preserve newlines / whitespace structure).
                var q = body_start;
                while (q < body_end) : (q += 1) {
                    if (out[q] != '\n' and out[q] != '\r' and !std.ascii.isWhitespace(out[q])) {
                        out[q] = 'x';
                    }
                }
            }
            // If terminator not found, leave body unmasked (fail closed).
            break;
        }
    }
    return out;
}

fn matchDeny(cmd: []const u8, match_opts: registry.MatchOptions) ?registry.Hit {
    return switch (registry.matchCommandDetailedOpts(cmd, match_opts)) {
        .deny => |h| h,
        .allow_safe, .allow_miss => null,
    };
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
    try std.testing.expect(std.mem.indexOf(u8, eval.rule_id.?, "reset-hard") != null);
}

test "evaluateCommand denies compound safe then destructive" {
    var eval = try evaluateCommand(std.testing.allocator, "git status; rm -rf /", .{});
    defer eval.deinit(std.testing.allocator);
    try std.testing.expect(eval.decision == .deny);
}

test "evaluateCommand denies sudo wrapper" {
    var eval = try evaluateCommand(std.testing.allocator, "sudo git reset --hard", .{});
    defer eval.deinit(std.testing.allocator);
    try std.testing.expect(eval.decision == .deny);
}

test "evaluateCommand denies quoted subcommand git \"reset\"" {
    var eval = try evaluateCommand(std.testing.allocator, "git \"reset\" --hard", .{});
    defer eval.deinit(std.testing.allocator);
    try std.testing.expect(eval.decision == .deny);
    try std.testing.expect(std.mem.indexOf(u8, eval.rule_id.?, "reset-hard") != null);
}

test "evaluateCommand denies complex quoted sudo git" {
    var eval = try evaluateCommand(std.testing.allocator, "sudo \"/usr/bin/git\" \"reset\" --hard", .{});
    defer eval.deinit(std.testing.allocator);
    try std.testing.expect(eval.decision == .deny);
    try std.testing.expect(std.mem.indexOf(u8, eval.rule_id.?, "reset-hard") != null);
}

test "evaluateCommand denies internal backslash g\\it reset" {
    var eval = try evaluateCommand(std.testing.allocator, "g\\it reset --hard", .{});
    defer eval.deinit(std.testing.allocator);
    try std.testing.expect(eval.decision == .deny);
}

test "evaluateCommand denies mixed quoting g'i't reset" {
    var eval = try evaluateCommand(std.testing.allocator, "g'i't reset --hard", .{});
    defer eval.deinit(std.testing.allocator);
    try std.testing.expect(eval.decision == .deny);
}

test "evaluateCommand denies line-continued reset" {
    var eval = try evaluateCommand(std.testing.allocator, "git re\\\nset --hard", .{});
    defer eval.deinit(std.testing.allocator);
    try std.testing.expect(eval.decision == .deny);
}

test "evaluateCommand denies mkfs" {
    var eval = try evaluateCommand(std.testing.allocator, "mkfs.ext4 /dev/sda1", .{});
    defer eval.deinit(std.testing.allocator);
    try std.testing.expect(eval.decision == .deny);
}

test "evaluateCommand empty allows (no-op)" {
    var eval = try evaluateCommand(std.testing.allocator, "   ", .{});
    defer eval.deinit(std.testing.allocator);
    try std.testing.expect(eval.decision == .allow);
}

test "evaluateCommand allows git add under default packs" {
    var eval = try evaluateCommand(std.testing.allocator, "git add .", .{});
    defer eval.deinit(std.testing.allocator);
    try std.testing.expect(eval.decision == .allow);
}

test "evaluateCommand allows destructive text in shell comment" {
    var eval = try evaluateCommand(std.testing.allocator, "ls -la # rm -rf /", .{});
    defer eval.deinit(std.testing.allocator);
    try std.testing.expect(eval.decision == .allow);
}

test "evaluateCommand allows echo unquoted rm -rf data" {
    var eval = try evaluateCommand(std.testing.allocator, "echo rm -rf /", .{});
    defer eval.deinit(std.testing.allocator);
    try std.testing.expect(eval.decision == .allow);
}

test "evaluateCommand denies rm after newline following git commit -m" {
    var eval = try evaluateCommand(std.testing.allocator, "git commit -m\nrm -rf /", .{});
    defer eval.deinit(std.testing.allocator);
    try std.testing.expect(eval.decision == .deny);
}

test "evaluateCommand denies multi-arg rm with sensitive target" {
    var eval = try evaluateCommand(std.testing.allocator, "rm -rf /tmp/safe /etc/passwd", .{});
    defer eval.deinit(std.testing.allocator);
    try std.testing.expect(eval.decision == .deny);
}

test "evaluateCommand denies cat heredoc with backslash-escaped delimiter" {
    const cmd =
        \\
        \\cat <<\EOF
        \\rm -rf /
        \\EOF
        \\
    ;
    var eval = try evaluateCommand(std.testing.allocator, cmd, .{});
    defer eval.deinit(std.testing.allocator);
    try std.testing.expect(eval.decision == .deny);
}

test "evaluateCommand denies attached redirection git>/dev/null reset" {
    const cases = [_][]const u8{
        "\"git\">/dev/null reset --hard",
        "\"git\"&>/dev/null reset --hard",
        "\"git\"&>>/dev/null reset --hard",
        "git>/dev/null reset --hard",
        "git>>/dev/null reset --hard",
        "git&>/dev/null reset --hard",
        "git&>>/dev/null reset --hard",
        "git >/dev/null reset --hard",
        "command >>/dev/null git reset --hard",
    };
    for (cases) |cmd| {
        var eval = try evaluateCommand(std.testing.allocator, cmd, .{});
        defer eval.deinit(std.testing.allocator);
        try std.testing.expect(eval.decision == .deny);
    }
}

test "evaluateCommand allows command builtin pure append redirect" {
    var eval = try evaluateCommand(std.testing.allocator, "command >> /usr/local/log", .{});
    defer eval.deinit(std.testing.allocator);
    try std.testing.expect(eval.decision == .allow);
}

test "evaluateCommand denies git add with full packs" {
    var eval = try evaluateCommand(std.testing.allocator, "git add .", .{ .default_packs_only = false });
    defer eval.deinit(std.testing.allocator);
    try std.testing.expect(eval.decision == .deny);
}

test {
    _ = tokenize;
    _ = packs;
    _ = allowlist;
    _ = registry;
    _ = segments;
    _ = normalize;
    _ = sanitize;
    _ = @import("corpus_test.zig");
    _ = @import("regex_pcre.zig");
}
