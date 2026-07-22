//! Wrapper-prefix stripping and light command-word dequoting for pack matching.
const std = @import("std");

pub const NormalizeResult = struct {
    /// Heap-owned normalized command (always owned for simplicity).
    normalized: []u8,
    stripped_any: bool,

    pub fn deinit(self: *NormalizeResult, allocator: std.mem.Allocator) void {
        allocator.free(self.normalized);
        self.* = undefined;
    }
};

/// Strip common wrappers (`sudo`, `env`, `command`, `nice`, `nohup`, `time`,
/// leading `\`), join line continuations, unescape in-word backslashes
/// (`g\it` → `git`), dequote command/subcommand words, and detach shell
/// redirections glued to the command word (`git>/dev/null` → `git >/dev/null`).
pub fn normalizeCommand(allocator: std.mem.Allocator, command: []const u8) !NormalizeResult {
    const trimmed = std.mem.trim(u8, command, " \t\r\n");
    var current = try allocator.dupe(u8, trimmed);
    errdefer allocator.free(current);
    var stripped_any = false;

    // Line continuations first: `git re\<NL>set` → `git reset`
    if (try joinLineContinuations(allocator, &current)) {
        stripped_any = true;
    }

    var iter: usize = 0;
    while (iter < 32) : (iter += 1) {
        const before = current.len;
        if (try stripOne(allocator, &current)) {
            stripped_any = true;
        }
        if (current.len == before) break;
    }

    // Detach redirections before dequote so `"git">/dev/null` becomes `"git" >/dev/null`
    // then dequotes to `git >/dev/null` (oracle attached_redirection_index).
    if (try detachAttachedRedirections(allocator, &current)) {
        stripped_any = true;
    }

    // Dequote + internal escape unescaping on command words
    if (try dequoteCommandWords(allocator, &current)) {
        stripped_any = true;
    }

    // Second pass: redirections may remain glued after dequote (`git>/dev/null`).
    if (try detachAttachedRedirections(allocator, &current)) {
        stripped_any = true;
    }

    return .{ .normalized = current, .stripped_any = stripped_any };
}

/// Insert a space before the first shell redirection attached to a command word.
/// Examples: `git>/dev/null` → `git >/dev/null`, `"git"&>/dev/null` → `"git" &>/dev/null`.
/// Numeric fd redirects like `2>/dev/null` are left alone.
fn detachAttachedRedirections(allocator: std.mem.Allocator, current: *[]u8) !bool {
    const s = current.*;
    if (s.len < 2) return false;
    if (std.mem.indexOfScalar(u8, s, '>') == null and
        std.mem.indexOfScalar(u8, s, '<') == null and
        std.mem.indexOf(u8, s, "&>") == null)
    {
        return false;
    }

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var changed = false;
    var i: usize = 0;
    var in_single = false;
    var in_double = false;
    var escaped = false;

    while (i < s.len) {
        const c = s[i];
        if (escaped) {
            try out.append(allocator, c);
            escaped = false;
            i += 1;
            continue;
        }
        if (c == '\\' and !in_single) {
            try out.append(allocator, c);
            escaped = true;
            i += 1;
            continue;
        }
        if (c == '\'' and !in_double) {
            in_single = !in_single;
            try out.append(allocator, c);
            i += 1;
            continue;
        }
        if (c == '"' and !in_single) {
            in_double = !in_double;
            try out.append(allocator, c);
            i += 1;
            continue;
        }

        if (!in_single and !in_double) {
            // Find start of current unquoted shell word (scan back in `out` for last space).
            // Simpler: detect redirection operator with non-ws, non-digit-only prefix in current word.
            const is_amp_redirect = c == '&' and i + 1 < s.len and s[i + 1] == '>';
            const is_angle = c == '>' or c == '<';
            if (is_amp_redirect or is_angle) {
                // Prefix of this word = bytes since last whitespace written to out.
                var word_start: usize = out.items.len;
                while (word_start > 0 and !std.ascii.isWhitespace(out.items[word_start - 1])) : (word_start -= 1) {}
                const prefix = out.items[word_start..];
                if (prefix.len > 0 and
                    redirectionPrefixLooksLikeCommand(prefix) and
                    !std.ascii.isWhitespace(prefix[prefix.len - 1]))
                {
                    // Not pure digits (fd redirect): insert space before operator.
                    var all_digits = true;
                    for (prefix) |pb| {
                        if (!std.ascii.isDigit(pb)) {
                            all_digits = false;
                            break;
                        }
                    }
                    if (!all_digits) {
                        try out.append(allocator, ' ');
                        changed = true;
                    }
                }
            }
        }

        try out.append(allocator, c);
        i += 1;
    }

    if (!changed) {
        out.deinit(allocator);
        return false;
    }
    // Own the rebuilt slice before freeing `current` so OOM leaves current valid.
    const owned = try out.toOwnedSlice(allocator);
    allocator.free(current.*);
    current.* = owned;
    return true;
}

fn redirectionPrefixLooksLikeCommand(prefix: []const u8) bool {
    // True if prefix is not only redirections/digits/quotes (oracle
    // redirection_prefix_looks_like_command). Letters inside quoted forms
    // like `"git"` still return true via the non-quote branch below.
    for (prefix) |b| {
        if (b != '&' and b != '<' and b != '>' and !std.ascii.isDigit(b) and b != '"' and b != '\'') {
            return true;
        }
    }
    return false;
}

/// Remove `\` + newline (and `\` + CR LF) so split tokens rejoin.
fn joinLineContinuations(allocator: std.mem.Allocator, current: *[]u8) !bool {
    const s = current.*;
    if (std.mem.indexOf(u8, s, "\\\n") == null and std.mem.indexOf(u8, s, "\\\r\n") == null) {
        return false;
    }
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '\\' and i + 1 < s.len and s[i + 1] == '\n') {
            i += 2;
            continue;
        }
        if (s[i] == '\\' and i + 2 < s.len and s[i + 1] == '\r' and s[i + 2] == '\n') {
            i += 3;
            continue;
        }
        try out.append(allocator, s[i]);
        i += 1;
    }
    // Own the rebuilt slice before freeing `current` so OOM leaves current valid.
    const owned = try out.toOwnedSlice(allocator);
    allocator.free(current.*);
    current.* = owned;
    return true;
}

fn stripOne(allocator: std.mem.Allocator, current: *[]u8) !bool {
    const s = std.mem.trim(u8, current.*, " \t");
    if (s.len == 0) return false;

    // Leading backslash alias bypass: `\git` → `git`
    if (s[0] == '\\' and s.len > 1) {
        const n = try allocator.dupe(u8, s[1..]);
        allocator.free(current.*);
        current.* = n;
        return true;
    }

    const wrappers = [_][]const u8{ "sudo", "doas", "command", "env", "nice", "nohup", "time", "builtin" };
    for (wrappers) |w| {
        if (try stripNamedWrapper(allocator, current, s, w)) return true;
    }

    // Path-prefixed wrappers: /usr/bin/sudo …
    if (std.mem.indexOfScalar(u8, s, '/')) |_| {
        const word = firstWord(s);
        const base = basename(word);
        for (wrappers) |w| {
            if (std.mem.eql(u8, base, w)) {
                if (try stripNamedWrapper(allocator, current, s, word)) return true;
            }
        }
    }
    return false;
}

fn stripNamedWrapper(allocator: std.mem.Allocator, current: *[]u8, s: []const u8, wrapper_word: []const u8) !bool {
    if (!std.mem.startsWith(u8, s, wrapper_word)) return false;
    const after_w = s[wrapper_word.len..];
    if (after_w.len > 0 and !std.ascii.isWhitespace(after_w[0]) and after_w[0] != '-') {
        // e.g. `sudoedit` — not a wrapper
        if (after_w[0] != '/') return false;
    }
    var rest = std.mem.trimStart(u8, after_w, " \t");

    // Skip wrapper flags (conservative).
    const is_sudo = std.mem.eql(u8, basename(wrapper_word), "sudo") or std.mem.eql(u8, basename(wrapper_word), "doas");
    const is_command = std.mem.eql(u8, basename(wrapper_word), "command");
    const is_env = std.mem.eql(u8, basename(wrapper_word), "env");
    const is_nice = std.mem.eql(u8, basename(wrapper_word), "nice");
    const is_time = std.mem.eql(u8, basename(wrapper_word), "time");

    while (rest.len > 0) {
        if (rest[0] != '-' and !(is_env and std.mem.indexOfScalar(u8, firstWord(rest), '=') != null)) {
            break;
        }
        const fw = firstWord(rest);
        if (is_command and (std.mem.eql(u8, fw, "-v") or std.mem.eql(u8, fw, "-V"))) {
            // query mode — do not strip
            return false;
        }
        if (std.mem.eql(u8, fw, "--")) {
            rest = std.mem.trimStart(u8, rest[fw.len..], " \t");
            break;
        }
        // Flags that take a value
        const takes_val = (is_sudo and (std.mem.eql(u8, fw, "-u") or std.mem.eql(u8, fw, "-g") or std.mem.eql(u8, fw, "-h") or
            std.mem.eql(u8, fw, "--user") or std.mem.eql(u8, fw, "--group"))) or
            (is_nice and (std.mem.eql(u8, fw, "-n") or std.mem.startsWith(u8, fw, "-n"))) or
            (is_env and (std.mem.eql(u8, fw, "-u") or std.mem.eql(u8, fw, "-C"))) or
            (is_time and std.mem.eql(u8, fw, "-p"));

        rest = std.mem.trimStart(u8, rest[fw.len..], " \t");
        if (takes_val and !std.mem.startsWith(u8, fw, "-n") and rest.len > 0 and rest[0] != '-') {
            const val = firstWord(rest);
            rest = std.mem.trimStart(u8, rest[val.len..], " \t");
        } else if (is_env and std.mem.indexOfScalar(u8, fw, '=') != null) {
            // already consumed ENV=val as firstWord
        }
        // env NAME=VALUE
        if (is_env and rest.len > 0) {
            const nw = firstWord(rest);
            if (std.mem.indexOfScalar(u8, nw, '=') != null) {
                rest = std.mem.trimStart(u8, rest[nw.len..], " \t");
                continue;
            }
        }
    }

    // Skip leading shell redirections after the wrapper (`command >>/dev/null git …`).
    rest = skipLeadingRedirections(rest);
    if (rest.len == 0) return false;
    const n = try allocator.dupe(u8, rest);
    allocator.free(current.*);
    current.* = n;
    return true;
}

/// Drop leading `>/path`, `>>/path`, `&>/path`, `2>/path`, etc. (and their targets).
fn skipLeadingRedirections(s: []const u8) []const u8 {
    var rest = std.mem.trimStart(u8, s, " \t");
    var guard: usize = 0;
    while (rest.len > 0 and guard < 8) : (guard += 1) {
        if (!startsWithShellRedirection(rest)) break;
        // consume operator
        var i: usize = 0;
        if (rest.len >= 3 and rest[0] == '&' and rest[1] == '>' and rest[2] == '>') {
            i = 3;
        } else if (rest.len >= 2 and rest[0] == '&' and rest[1] == '>') {
            i = 2;
        } else if (rest.len >= 2 and (rest[0] == '>' or rest[0] == '<') and rest[1] == rest[0]) {
            i = 2;
        } else if (rest[0] == '>' or rest[0] == '<') {
            i = 1;
        } else {
            // digit fd prefix: 2>/dev/null
            while (i < rest.len and std.ascii.isDigit(rest[i])) : (i += 1) {}
            if (i < rest.len and (rest[i] == '>' or rest[i] == '<')) {
                if (i + 1 < rest.len and rest[i + 1] == rest[i]) i += 2 else i += 1;
            } else break;
        }
        rest = std.mem.trimStart(u8, rest[i..], " \t");
        // consume target token if present
        if (rest.len == 0) break;
        if (startsWithShellRedirection(rest)) continue;
        const tgt = firstWord(rest);
        rest = std.mem.trimStart(u8, rest[tgt.len..], " \t");
    }
    return rest;
}

fn startsWithShellRedirection(s: []const u8) bool {
    const t = std.mem.trimStart(u8, s, " \t");
    if (t.len == 0) return false;
    if (t[0] == '>' or t[0] == '<') return true;
    if (t.len >= 2 and t[0] == '&' and t[1] == '>') return true;
    var i: usize = 0;
    while (i < t.len and std.ascii.isDigit(t[i])) : (i += 1) {}
    return i > 0 and i < t.len and (t[i] == '>' or t[i] == '<');
}

/// Dequote executed command words and subcommand-like tokens:
/// - `"git" reset --hard` → `git reset --hard`
/// - `git "reset" --hard` → `git reset --hard`
/// - `sudo "/usr/bin/git" "reset" --hard` → `sudo /usr/bin/git reset --hard`
/// Path-like quoted args (e.g. `rm "/tmp/foo"`) keep their quotes.
fn dequoteCommandWords(allocator: std.mem.Allocator, current: *[]u8) !bool {
    const s = current.*;
    if (s.len < 2) return false;
    // Fast path: no quotes, no backslash escapes, no .exe → nothing to do.
    const needs = std.mem.indexOfScalar(u8, s, '"') != null or
        std.mem.indexOfScalar(u8, s, '\'') != null or
        std.mem.indexOfScalar(u8, s, '\\') != null or
        std.ascii.indexOfIgnoreCase(s, ".exe") != null;
    if (!needs) return false;

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var changed = false;
    var i: usize = 0;
    var token_index: usize = 0; // 0 = argv0-ish, 1+ = later words (within a segment)

    while (i < s.len) {
        // preserve whitespace
        if (std.ascii.isWhitespace(s[i])) {
            try out.append(allocator, s[i]);
            // segment separators reset token index
            if (s[i] == '\n' or s[i] == ';') token_index = 0;
            i += 1;
            continue;
        }
        // shell separators as single/double chars
        if (s[i] == ';' or s[i] == '|' or s[i] == '&') {
            try out.append(allocator, s[i]);
            if (s[i] == '|' and i + 1 < s.len and s[i + 1] == '|') {
                try out.append(allocator, s[i + 1]);
                i += 2;
            } else if (s[i] == '&' and i + 1 < s.len and s[i + 1] == '&') {
                try out.append(allocator, s[i + 1]);
                i += 2;
            } else {
                i += 1;
            }
            token_index = 0;
            continue;
        }

        // quoted token
        if (s[i] == '"' or s[i] == '\'') {
            const q = s[i];
            const start = i + 1;
            var j = start;
            while (j < s.len and s[j] != q) : (j += 1) {}
            const inner = s[start..j];
            const end = if (j < s.len) j + 1 else j;

            const dequote = shouldDequoteToken(inner, token_index);
            if (dequote) {
                var word = inner;
                // strip trailing .exe (case-insensitive)
                if (word.len >= 4 and std.ascii.eqlIgnoreCase(word[word.len - 4 ..], ".exe")) {
                    word = word[0 .. word.len - 4];
                    changed = true;
                }
                try out.appendSlice(allocator, word);
                changed = true;
            } else {
                try out.appendSlice(allocator, s[i..end]);
            }
            i = end;
            token_index += 1;
            continue;
        }

        // Unquoted token, which may contain internal escapes (g\it) or mixed
        // quoting glued to bare chars (g'i't). Scan until whitespace/separator.
        const start = i;
        while (i < s.len and !std.ascii.isWhitespace(s[i]) and s[i] != ';' and s[i] != '|' and s[i] != '&') {
            // include mixed-quoted runs as part of the same shell word
            if (s[i] == '"' or s[i] == '\'') {
                const q = s[i];
                i += 1;
                while (i < s.len and s[i] != q) : (i += 1) {}
                if (i < s.len) i += 1;
                continue;
            }
            i += 1;
        }
        const raw_word = s[start..i];
        const norm_word = try normalizeShellWord(allocator, raw_word, token_index);
        defer if (norm_word.owned) allocator.free(norm_word.bytes);
        if (norm_word.changed) changed = true;
        try out.appendSlice(allocator, norm_word.bytes);
        token_index += 1;
    }

    if (!changed) {
        out.deinit(allocator);
        return false;
    }
    // Own the rebuilt slice before freeing `current` so OOM leaves current valid.
    const owned = try out.toOwnedSlice(allocator);
    allocator.free(current.*);
    current.* = owned;
    return true;
}

const NormWord = struct {
    bytes: []const u8,
    owned: bool,
    changed: bool,
};

/// Normalize one shell word: strip surrounding quotes when appropriate,
/// collapse mixed quoting (`g'i't` → `git`), strip internal `\` before
/// alphanumerics (`g\it` → `git`), strip trailing `.exe`.
fn normalizeShellWord(allocator: std.mem.Allocator, raw: []const u8, token_index: usize) !NormWord {
    // Fully quoted single token already handled by quoted branch; this handles
    // bare / mixed / escaped words.
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);
    var changed = false;

    // Collapse mixed quoting and strip internal backslash-escapes of alphanumerics.
    var i: usize = 0;
    while (i < raw.len) {
        const c = raw[i];
        if (c == '\\' and i + 1 < raw.len) {
            const next = raw[i + 1];
            if (std.ascii.isAlphanumeric(next)) {
                // g\it → git (drop backslash)
                try buf.append(allocator, next);
                i += 2;
                changed = true;
                continue;
            }
            // keep other escapes as-is (e.g. \n is not line-cont here)
            try buf.append(allocator, c);
            i += 1;
            continue;
        }
        if (c == '\'' or c == '"') {
            // g'i't or "g"it — take interior of quotes
            const q = c;
            i += 1;
            const start = i;
            while (i < raw.len and raw[i] != q) : (i += 1) {}
            try buf.appendSlice(allocator, raw[start..i]);
            if (i < raw.len) i += 1; // closing quote
            changed = true;
            continue;
        }
        try buf.append(allocator, c);
        i += 1;
    }

    var word = try buf.toOwnedSlice(allocator);
    // After toOwnedSlice, buf is empty; free `word` on any later OOM (e.g. .exe shorten).
    errdefer allocator.free(word);

    // Strip trailing .exe
    if (word.len >= 4 and std.ascii.eqlIgnoreCase(word[word.len - 4 ..], ".exe")) {
        const shortened = try allocator.dupe(u8, word[0 .. word.len - 4]);
        allocator.free(word);
        word = shortened;
        changed = true;
    }

    // If this is a path-like argument (not argv0) that was fully produced from a
    // single quoted span originally, we already keep quotes in the quoted branch.
    // Here bare paths stay as-is.
    _ = token_index;

    if (!changed) {
        allocator.free(word);
        return .{ .bytes = raw, .owned = false, .changed = false };
    }
    return .{ .bytes = word, .owned = true, .changed = true };
}

fn shouldDequoteToken(inner: []const u8, token_index: usize) bool {
    if (inner.len == 0) return false;
    // Command word (argv0): always strip quotes, including path-prefixed binaries
    // (`"/usr/bin/git"` → `/usr/bin/git`) so pack regexes can match.
    if (token_index == 0) return true;
    // Arguments: never strip path-like tokens (rm "/tmp/foo", rm "$TMPDIR/x")
    if (looksPathLike(inner)) return false;
    // Later tokens: dequote subcommand-like words (identifiers / short flags)
    return looksSubcommandLike(inner);
}

fn looksPathLike(tok: []const u8) bool {
    if (tok.len == 0) return false;
    if (tok[0] == '/' or tok[0] == '~' or tok[0] == '.') return true;
    if (tok[0] == '$') return true; // $TMPDIR, ${HOME}, …
    if (std.mem.indexOfScalar(u8, tok, '/') != null) return true;
    if (std.mem.indexOfScalar(u8, tok, '\\') != null) return true;
    return false;
}

fn looksSubcommandLike(tok: []const u8) bool {
    // git subcommands, short/long flags without path semantics
    if (tok.len == 0) return false;
    if (tok[0] == '-') return true; // "--hard", "-f" as quoted flags
    for (tok) |c| {
        if (!(std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.')) return false;
    }
    return true;
}

fn firstWord(s: []const u8) []const u8 {
    var i: usize = 0;
    while (i < s.len and !std.ascii.isWhitespace(s[i])) : (i += 1) {}
    return s[0..i];
}

fn basename(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, path, '/')) |idx| {
        if (idx + 1 < path.len) return path[idx + 1 ..];
    }
    return path;
}

/// Extract embedded script bodies from `bash -c '…'`, `python -c "…"`, heredoc, here-string.
pub fn extractEmbeds(allocator: std.mem.Allocator, command: []const u8) ![][]const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (list.items) |x| allocator.free(x);
        list.deinit(allocator);
    }

    // bash/sh/zsh/ksh -c 'body' or -c"body"
    try extractDashC(allocator, command, &list);
    // python/python3/ruby -c / -e
    try extractInterpC(allocator, command, &list);
    // here-string: <<<'body'
    if (std.mem.indexOf(u8, command, "<<<")) |idx| {
        const rest = std.mem.trimStart(u8, command[idx + 3 ..], " \t");
        if (rest.len > 0) {
            const body = unquote(rest);
            try list.append(allocator, try allocator.dupe(u8, body));
        }
    }
    // heredoc: <<EOF ... EOF (simple)
    if (std.mem.indexOf(u8, command, "<<")) |idx| {
        // avoid <<< 
        if (!(idx + 2 < command.len and command[idx + 2] == '<')) {
            var p = idx + 2;
            if (p < command.len and command[p] == '-') p += 1;
            while (p < command.len and std.ascii.isWhitespace(command[p])) : (p += 1) {}
            const delim_start = p;
            while (p < command.len and !std.ascii.isWhitespace(command[p]) and command[p] != '\n') : (p += 1) {}
            var delim = command[delim_start..p];
            if (delim.len >= 2 and (delim[0] == '\'' or delim[0] == '"')) {
                delim = delim[1 .. delim.len - 1];
            }
            if (delim.len > 0) {
                if (std.mem.indexOfScalar(u8, command[p..], '\n')) |nl| {
                    const body_start = p + nl + 1;
                    // find closing delim line
                    var search = body_start;
                    while (search < command.len) {
                        if (std.mem.indexOfScalar(u8, command[search..], '\n')) |n2| {
                            const line = command[search .. search + n2];
                            if (std.mem.eql(u8, std.mem.trim(u8, line, " \t\r"), delim)) {
                                const body = command[body_start..search];
                                try list.append(allocator, try allocator.dupe(u8, body));
                                break;
                            }
                            search = search + n2 + 1;
                        } else {
                            const line = command[search..];
                            if (std.mem.eql(u8, std.mem.trim(u8, line, " \t\r"), delim)) {
                                const body = command[body_start..search];
                                try list.append(allocator, try allocator.dupe(u8, body));
                            }
                            break;
                        }
                    }
                }
            }
        }
    }

    return try list.toOwnedSlice(allocator);
}

pub fn freeEmbeds(allocator: std.mem.Allocator, embeds: [][]const u8) void {
    for (embeds) |e| allocator.free(e);
    allocator.free(embeds);
}

fn extractDashC(allocator: std.mem.Allocator, command: []const u8, list: *std.ArrayList([]const u8)) !void {
    const shells = [_][]const u8{ "bash", "sh", "zsh", "ksh", "dash" };
    for (shells) |sh| {
        var search_from: usize = 0;
        while (search_from < command.len) {
            const idx = std.mem.indexOfPos(u8, command, search_from, sh) orelse break;
            // word boundary-ish
            if (idx > 0 and (std.ascii.isAlphanumeric(command[idx - 1]) or command[idx - 1] == '_')) {
                search_from = idx + sh.len;
                continue;
            }
            var p = idx + sh.len;
            // optional path already included if we matched basename in path — also handle /bin/bash
            while (p < command.len and std.ascii.isWhitespace(command[p])) : (p += 1) {}
            // skip flags until -c
            while (p < command.len) {
                while (p < command.len and std.ascii.isWhitespace(command[p])) : (p += 1) {}
                if (p >= command.len) break;
                if (std.mem.startsWith(u8, command[p..], "-c")) {
                    p += 2;
                    while (p < command.len and std.ascii.isWhitespace(command[p])) : (p += 1) {}
                    if (p >= command.len) break;
                    const body = takeQuotedOrWord(command[p..]);
                    if (body.len > 0) try list.append(allocator, try allocator.dupe(u8, body));
                    break;
                }
                if (command[p] == '-') {
                    // skip flag
                    while (p < command.len and !std.ascii.isWhitespace(command[p])) : (p += 1) {}
                    continue;
                }
                break;
            }
            search_from = idx + sh.len;
        }
    }
    // Also match */bash -c
    if (std.mem.indexOf(u8, command, "/bash -c") != null or std.mem.indexOf(u8, command, "/sh -c") != null) {
        if (std.mem.indexOf(u8, command, " -c ")) |cidx| {
            const p = cidx + 4;
            const body = takeQuotedOrWord(std.mem.trimStart(u8, command[p..], " \t"));
            if (body.len > 0) try list.append(allocator, try allocator.dupe(u8, body));
        }
    }
}

fn extractInterpC(allocator: std.mem.Allocator, command: []const u8, list: *std.ArrayList([]const u8)) !void {
    // Longer names first so `python3` wins over `python` inside `python3.11.exe`.
    const interps = [_]struct { name: []const u8, flag: []const u8 }{
        .{ .name = "python3", .flag = "-c" },
        .{ .name = "python", .flag = "-c" },
        .{ .name = "ruby", .flag = "-e" },
        .{ .name = "node", .flag = "-e" },
        .{ .name = "perl", .flag = "-e" },
    };
    for (interps) |ip| {
        var search: usize = 0;
        while (std.mem.indexOfPos(u8, command, search, ip.name)) |idx| {
            if (idx > 0 and (std.ascii.isAlphanumeric(command[idx - 1]) or command[idx - 1] == '_' or command[idx - 1] == '.')) {
                search = idx + ip.name.len;
                continue;
            }
            // Skip version + Windows .exe: python.exe, python3.11.exe, python3.exe
            var p = skipInterpBinarySuffix(command, idx + ip.name.len);
            // Require a boundary after the binary token (space, EOL, or flag).
            if (p < command.len and !std.ascii.isWhitespace(command[p]) and command[p] != '-') {
                search = idx + ip.name.len;
                continue;
            }
            while (p < command.len) {
                while (p < command.len and std.ascii.isWhitespace(command[p])) : (p += 1) {}
                if (p >= command.len) break;
                if (std.mem.startsWith(u8, command[p..], ip.flag)) {
                    p += ip.flag.len;
                    while (p < command.len and std.ascii.isWhitespace(command[p])) : (p += 1) {}
                    const body = takeQuotedOrWord(command[p..]);
                    if (body.len > 0) try list.append(allocator, try allocator.dupe(u8, body));
                    break;
                }
                if (command[p] == '-') {
                    while (p < command.len and !std.ascii.isWhitespace(command[p])) : (p += 1) {}
                    continue;
                }
                break;
            }
            search = idx + ip.name.len;
        }
    }
}

/// After an interpreter name (`python` / `python3`), consume optional version
/// (`.11`, `.11.2`) and optional Windows `.exe` so `python3.11.exe -c` works.
/// Does not swallow the `.` of `.exe` into the version segment.
fn skipInterpBinarySuffix(command: []const u8, start: usize) usize {
    var p = start;
    // Version: one or more ( '.' DIGITS+ ) — stop before `.exe` (no digits after `.`)
    while (p < command.len and command[p] == '.') {
        var r = p + 1;
        if (r >= command.len or !std.ascii.isDigit(command[r])) break;
        while (r < command.len and std.ascii.isDigit(command[r])) : (r += 1) {}
        p = r;
    }
    if (p + 4 <= command.len and std.ascii.eqlIgnoreCase(command[p .. p + 4], ".exe")) {
        p += 4;
    }
    return p;
}

fn takeQuotedOrWord(s: []const u8) []const u8 {
    if (s.len == 0) return s;
    if (s[0] == '\'' or s[0] == '"') {
        const q = s[0];
        var i: usize = 1;
        while (i < s.len and s[i] != q) : (i += 1) {}
        return s[1..i];
    }
    return firstWord(s);
}

fn unquote(s: []const u8) []const u8 {
    if (s.len >= 2 and (s[0] == '\'' or s[0] == '"') and s[s.len - 1] == s[0]) {
        return s[1 .. s.len - 1];
    }
    return firstWord(s);
}

test "normalize strips sudo" {
    var n = try normalizeCommand(std.testing.allocator, "sudo git reset --hard");
    defer n.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("git reset --hard", n.normalized);
}

test "normalize strips command and time" {
    var n = try normalizeCommand(std.testing.allocator, "time nice git reset --hard");
    defer n.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("git reset --hard", n.normalized);
}

test "normalize dequotes subcommand git \"reset\"" {
    var n = try normalizeCommand(std.testing.allocator, "git \"reset\" --hard");
    defer n.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("git reset --hard", n.normalized);
}

test "normalize dequotes quoted binary" {
    var n = try normalizeCommand(std.testing.allocator, "\"git\" reset --hard");
    defer n.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("git reset --hard", n.normalized);
}

test "normalize complex quoting after sudo" {
    var n = try normalizeCommand(std.testing.allocator, "sudo \"/usr/bin/git\" \"reset\" --hard");
    defer n.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("/usr/bin/git reset --hard", n.normalized);
}

test "normalize keeps quoted path args" {
    var n = try normalizeCommand(std.testing.allocator, "rm -rf \"/tmp/foo\"");
    defer n.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("rm -rf \"/tmp/foo\"", n.normalized);
}

test "normalize internal backslash g\\it" {
    var n = try normalizeCommand(std.testing.allocator, "g\\it reset --hard");
    defer n.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("git reset --hard", n.normalized);
}

test "normalize mixed quoting g'i't" {
    var n = try normalizeCommand(std.testing.allocator, "g'i't reset --hard");
    defer n.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("git reset --hard", n.normalized);
}

test "normalize line continuation git re\\\\nset" {
    var n = try normalizeCommand(std.testing.allocator, "git re\\\nset --hard");
    defer n.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("git reset --hard", n.normalized);
}

test "normalize detaches attached redirection git>/dev/null" {
    var n = try normalizeCommand(std.testing.allocator, "git>/dev/null reset --hard");
    defer n.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("git >/dev/null reset --hard", n.normalized);
}

test "normalize detaches quoted argv0 redirection" {
    var n = try normalizeCommand(std.testing.allocator, "\"git\">/dev/null reset --hard");
    defer n.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("git >/dev/null reset --hard", n.normalized);
}

test "normalize detaches amp redirection" {
    var n = try normalizeCommand(std.testing.allocator, "\"git\"&>/dev/null reset --hard");
    defer n.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("git &>/dev/null reset --hard", n.normalized);
}

test "normalize strips command wrapper with leading redirect" {
    var n = try normalizeCommand(std.testing.allocator, "command >>/dev/null git reset --hard");
    defer n.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("git reset --hard", n.normalized);
}

test "extractInterpC extracts python.exe -c body" {
    const embeds = try extractEmbeds(std.testing.allocator, "python.exe -c \"import shutil; shutil.rmtree('/')\"");
    defer freeEmbeds(std.testing.allocator, embeds);
    try std.testing.expect(embeds.len >= 1);
    try std.testing.expect(std.mem.indexOf(u8, embeds[0], "rmtree") != null);
}

test "extractInterpC extracts python3.11.exe -c body" {
    const embeds = try extractEmbeds(std.testing.allocator, "python3.11.exe -c \"import shutil; shutil.rmtree('/')\"");
    defer freeEmbeds(std.testing.allocator, embeds);
    try std.testing.expect(embeds.len >= 1);
    try std.testing.expect(std.mem.indexOf(u8, embeds[0], "rmtree") != null);
}

test "extract bash -c embed" {
    const embeds = try extractEmbeds(std.testing.allocator, "bash -c 'git reset --hard'");
    defer freeEmbeds(std.testing.allocator, embeds);
    try std.testing.expect(embeds.len >= 1);
    try std.testing.expectEqualStrings("git reset --hard", embeds[0]);
}
