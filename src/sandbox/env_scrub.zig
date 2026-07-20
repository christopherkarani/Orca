//! Child-environment scrub for agent launch (P0-I-05).
//!
//! Pure denylist filter for injection / library-preload vectors. Callers that
//! apply the OS sandbox (U04) should run this on the child env map before spawn.
//! Not wired into process.prepareChild here — handoff for U04-apply-seam.
//!
//! ## Scrub denylist (removed)
//! - Dynamic linker / preload: `LD_PRELOAD`, `LD_LIBRARY_PATH`, `DYLD_*`
//! - Shell startup injection: `BASH_ENV`, `ENV`, `ZDOTDIR`
//! - Interpreter / startup injection: `PYTHONSTARTUP`, `PYTHONPATH` (hostile
//!   path injection), `NODE_OPTIONS`, `RUBYOPT`, `PERL5OPT`
//!
//! ## Keep class (not scrubbed by this module)
//! - `PATH`, `HOME`, `LANG`, `TERM`
//! - `ORCA_*` session vars when present
//!
//! HOME grants may be restricted separately by callers; this scrub does not
//! strip HOME. Policy-level env filtering remains in `intercept/env.zig`.

const std = @import("std");

/// Exact env names removed for shell/interpreter/library injection.
pub const exact_scrub_keys = [_][]const u8{
    "LD_PRELOAD",
    "LD_LIBRARY_PATH",
    "BASH_ENV",
    "ENV",
    "ZDOTDIR",
    "PYTHONSTARTUP",
    "PYTHONPATH",
    "NODE_OPTIONS",
    "RUBYOPT",
    "PERL5OPT",
};

/// Prefixes removed (all matching keys). Case-sensitive.
pub const scrub_prefixes = [_][]const u8{
    "DYLD_",
};

/// Documented keepers: never scrubbed by this denylist (allow-through class).
pub const keep_keys = [_][]const u8{
    "PATH",
    "HOME",
    "LANG",
    "TERM",
};

/// True when `name` is in the scrub denylist (exact or prefix match).
pub fn shouldScrubKey(name: []const u8) bool {
    // Keep class always wins (defensive; denylist does not include these).
    if (isKeepClass(name)) return false;

    for (exact_scrub_keys) |key| {
        if (std.mem.eql(u8, name, key)) return true;
    }
    for (scrub_prefixes) |prefix| {
        if (std.mem.startsWith(u8, name, prefix)) return true;
    }
    return false;
}

/// True for documented keepers and `ORCA_*` session vars.
pub fn isKeepClass(name: []const u8) bool {
    for (keep_keys) |key| {
        if (std.mem.eql(u8, name, key)) return true;
    }
    if (std.mem.startsWith(u8, name, "ORCA_")) return true;
    return false;
}

/// Build a new map with scrubbed keys removed. Source is not modified.
/// Caller owns the returned map and must `deinit` it.
pub fn scrubEnvMap(allocator: std.mem.Allocator, source: *const std.process.Environ.Map) !std.process.Environ.Map {
    var out = std.process.Environ.Map.init(allocator);
    errdefer out.deinit();

    var it = source.iterator();
    while (it.next()) |entry| {
        const name = entry.key_ptr.*;
        if (shouldScrubKey(name)) continue;
        try out.put(name, entry.value_ptr.*);
    }
    return out;
}

/// Remove scrubbed keys from `env_map` in place. Returns count of removals.
pub fn scrubEnvMapInPlace(env_map: *std.process.Environ.Map) usize {
    // Owned key copies: swapRemove frees map-owned key storage.
    var to_remove: std.ArrayList([]u8) = .empty;
    defer {
        for (to_remove.items) |key| env_map.allocator.free(key);
        to_remove.deinit(env_map.allocator);
    }

    var it = env_map.iterator();
    while (it.next()) |entry| {
        const name = entry.key_ptr.*;
        if (!shouldScrubKey(name)) continue;
        const owned = env_map.allocator.dupe(u8, name) catch {
            // Best-effort: still scrub any keys already queued.
            break;
        };
        to_remove.append(env_map.allocator, owned) catch {
            env_map.allocator.free(owned);
            break;
        };
    }

    var removed: usize = 0;
    for (to_remove.items) |name| {
        if (env_map.swapRemove(name)) removed += 1;
    }
    return removed;
}

// ── tests ──────────────────────────────────────────────────────────────────

test "shouldScrubKey removes LD_PRELOAD LD_LIBRARY_PATH BASH_ENV ENV ZDOTDIR" {
    try std.testing.expect(shouldScrubKey("LD_PRELOAD"));
    try std.testing.expect(shouldScrubKey("LD_LIBRARY_PATH"));
    try std.testing.expect(shouldScrubKey("BASH_ENV"));
    try std.testing.expect(shouldScrubKey("ENV"));
    try std.testing.expect(shouldScrubKey("ZDOTDIR"));
}

test "shouldScrubKey removes all DYLD_ prefix vars" {
    try std.testing.expect(shouldScrubKey("DYLD_INSERT_LIBRARIES"));
    try std.testing.expect(shouldScrubKey("DYLD_LIBRARY_PATH"));
    try std.testing.expect(shouldScrubKey("DYLD_FALLBACK_LIBRARY_PATH"));
    try std.testing.expect(shouldScrubKey("DYLD_FRAMEWORK_PATH"));
}

test "shouldScrubKey removes interpreter startup injection class" {
    try std.testing.expect(shouldScrubKey("PYTHONSTARTUP"));
    try std.testing.expect(shouldScrubKey("PYTHONPATH"));
    try std.testing.expect(shouldScrubKey("NODE_OPTIONS"));
    try std.testing.expect(shouldScrubKey("RUBYOPT"));
    try std.testing.expect(shouldScrubKey("PERL5OPT"));
}

test "shouldScrubKey keeps PATH HOME LANG TERM and ORCA_ session vars" {
    try std.testing.expect(!shouldScrubKey("PATH"));
    try std.testing.expect(!shouldScrubKey("HOME"));
    try std.testing.expect(!shouldScrubKey("LANG"));
    try std.testing.expect(!shouldScrubKey("TERM"));
    try std.testing.expect(!shouldScrubKey("ORCA_SESSION_ID"));
    try std.testing.expect(!shouldScrubKey("ORCA_MODE"));
    try std.testing.expect(isKeepClass("PATH"));
    try std.testing.expect(isKeepClass("HOME"));
    try std.testing.expect(isKeepClass("LANG"));
    try std.testing.expect(isKeepClass("TERM"));
    try std.testing.expect(isKeepClass("ORCA_SESSION_ID"));
    try std.testing.expect(isKeepClass("ORCA_MODE"));
}

test "shouldScrubKey does not scrub unrelated vars" {
    try std.testing.expect(!shouldScrubKey("USER"));
    try std.testing.expect(!shouldScrubKey("SHELL"));
    try std.testing.expect(!shouldScrubKey("OPENAI_API_KEY"));
    try std.testing.expect(!shouldScrubKey("MY_DYLD_NOT_PREFIX")); // not DYLD_ prefix
}

test "scrubEnvMap filters denylist and preserves keepers" {
    var source = std.process.Environ.Map.init(std.testing.allocator);
    defer source.deinit();
    try source.put("PATH", "/usr/bin");
    try source.put("HOME", "/home/agent");
    try source.put("LANG", "C");
    try source.put("TERM", "xterm");
    try source.put("ORCA_SESSION_ID", "sess-1");
    try source.put("LD_PRELOAD", "evil.so");
    try source.put("LD_LIBRARY_PATH", "/evil");
    try source.put("DYLD_INSERT_LIBRARIES", "evil.dylib");
    try source.put("BASH_ENV", "/tmp/evil.sh");
    try source.put("ENV", "/tmp/evil.sh");
    try source.put("ZDOTDIR", "/tmp");
    try source.put("PYTHONSTARTUP", "/tmp/sitecustomize.py");
    try source.put("PYTHONPATH", "/tmp/hostile");
    try source.put("NODE_OPTIONS", "--require /tmp/x.js");
    try source.put("RUBYOPT", "-r/tmp/x");
    try source.put("PERL5OPT", "-Mevil");
    try source.put("SAFE_CUSTOM", "ok");

    var scrubbed = try scrubEnvMap(std.testing.allocator, &source);
    defer scrubbed.deinit();

    try std.testing.expectEqualStrings("/usr/bin", scrubbed.get("PATH").?);
    try std.testing.expectEqualStrings("/home/agent", scrubbed.get("HOME").?);
    try std.testing.expectEqualStrings("C", scrubbed.get("LANG").?);
    try std.testing.expectEqualStrings("xterm", scrubbed.get("TERM").?);
    try std.testing.expectEqualStrings("sess-1", scrubbed.get("ORCA_SESSION_ID").?);
    try std.testing.expectEqualStrings("ok", scrubbed.get("SAFE_CUSTOM").?);

    try std.testing.expect(scrubbed.get("LD_PRELOAD") == null);
    try std.testing.expect(scrubbed.get("LD_LIBRARY_PATH") == null);
    try std.testing.expect(scrubbed.get("DYLD_INSERT_LIBRARIES") == null);
    try std.testing.expect(scrubbed.get("BASH_ENV") == null);
    try std.testing.expect(scrubbed.get("ENV") == null);
    try std.testing.expect(scrubbed.get("ZDOTDIR") == null);
    try std.testing.expect(scrubbed.get("PYTHONSTARTUP") == null);
    try std.testing.expect(scrubbed.get("PYTHONPATH") == null);
    try std.testing.expect(scrubbed.get("NODE_OPTIONS") == null);
    try std.testing.expect(scrubbed.get("RUBYOPT") == null);
    try std.testing.expect(scrubbed.get("PERL5OPT") == null);

    // Source unchanged
    try std.testing.expect(source.get("LD_PRELOAD") != null);
}

test "scrubEnvMapInPlace removes denylist keys" {
    var env_map = std.process.Environ.Map.init(std.testing.allocator);
    defer env_map.deinit();
    try env_map.put("PATH", "/bin");
    try env_map.put("LD_PRELOAD", "x");
    try env_map.put("NODE_OPTIONS", "--require x");
    try env_map.put("ORCA_FOO", "bar");

    const removed = scrubEnvMapInPlace(&env_map);
    try std.testing.expectEqual(@as(usize, 2), removed);
    try std.testing.expectEqualStrings("/bin", env_map.get("PATH").?);
    try std.testing.expectEqualStrings("bar", env_map.get("ORCA_FOO").?);
    try std.testing.expect(env_map.get("LD_PRELOAD") == null);
    try std.testing.expect(env_map.get("NODE_OPTIONS") == null);
}

test "keep class and scrub class are disjoint for documented names" {
    for (exact_scrub_keys) |key| {
        try std.testing.expect(shouldScrubKey(key));
        try std.testing.expect(!isKeepClass(key));
    }
    for (keep_keys) |key| {
        try std.testing.expect(!shouldScrubKey(key));
        try std.testing.expect(isKeepClass(key));
    }
}
