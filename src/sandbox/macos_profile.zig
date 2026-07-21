//! CompiledProfile → SBPL (Seatbelt profile language) for macOS custom sandbox.
//!
//! Pure string generation — no syscalls. Policy shape:
//! - deny default
//! - workspace RW (minus control-root write carve-outs)
//! - system RO prefixes from grants
//! - no broad $HOME grant
//! - process/mach/network baseline so a sandboxed child can still exec

const std = @import("std");
const profile = @import("profile.zig");

/// Render a custom SBPL profile string from a compiled grant model.
/// Caller owns the returned slice.
pub fn renderSbpl(allocator: std.mem.Allocator, compiled: *const profile.CompiledProfile) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try out.appendSlice(allocator, "(version 1)\n");
    try out.appendSlice(allocator, "(deny default)\n");
    try out.appendSlice(allocator, "\n");

    // Baseline: process lifecycle, signals, sysctl, mach, and network (FS scope only).
    // Metadata is scoped to root literals + granted trees only (M-4) — never bare
    // (allow file-read-metadata) which enables host-wide path discovery.
    try out.appendSlice(allocator,
        \\;; process / IPC baseline (FS confinement is the product surface)
        \\(allow process*)
        \\(allow signal)
        \\(allow sysctl-read)
        \\(allow mach-lookup)
        \\(allow mach-register)
        \\(allow network*)
        \\
        \\;; dyld / device / root path components needed for exec (content + metadata)
        \\(allow file-read-metadata (literal "/"))
        \\(allow file-read-metadata (literal "/private"))
        \\(allow file-read* (literal "/"))
        \\(allow file-read* (literal "/private"))
        \\(allow file-read* (literal "/private/tmp"))
        \\(allow file-read* (literal "/private/var"))
        \\(allow file-read* (literal "/private/var/tmp"))
        \\(allow file-read-metadata (subpath "/dev"))
        \\(allow file-read* (subpath "/dev"))
        \\(allow file-ioctl (subpath "/dev"))
        \\(allow file-read-metadata (subpath "/private/var/db/dyld"))
        \\(allow file-read* (subpath "/private/var/db/dyld"))
        \\(allow file-write* (subpath "/dev"))
        \\
    );

    // Path grants from the portable profile model.
    try out.appendSlice(allocator, ";; compiled path grants\n");
    for (compiled.grants) |g| {
        // Metadata only under granted trees (M-4).
        try appendAllowSubpath(&out, allocator, "file-read-metadata", g.path);
        switch (g.mode) {
            .ro, .exec => {
                try appendAllowSubpath(&out, allocator, "file-read*", g.path);
                try appendAllowSubpath(&out, allocator, "process-exec", g.path);
            },
            .rw => {
                try appendAllowSubpath(&out, allocator, "file-read*", g.path);
                // RW with control-root write denies (require-not).
                try appendAllowWriteMinusControls(&out, allocator, g.path, compiled.control_roots);
            },
        }
    }

    // Explicit control write denies (defense in depth if a broader allow slips in).
    if (compiled.control_roots.len > 0) {
        try out.appendSlice(allocator, "\n;; control-root write carve-outs\n");
        for (compiled.control_roots) |root| {
            try appendDenySubpath(&out, allocator, "file-write*", root);
        }
    }

    // M-1 / R2-1: deny Data-volume firmlink surface (homes / host secrets).
    // Scope is `/System/Volumes/Data` only — not all of `/System/Volumes` (Preboot,
    // Update, etc. are not the secret-home surface). Deny is emitted *after* grants so
    // last-match blocks bare `/System` custom grants that would otherwise open Data.
    //
    // Critical: production workspaces often realpath to `/System/Volumes/Data/Users/…`.
    // A trailing deny alone would clobber those workspace grants under last-match.
    // Re-emit allows for every compiled grant under Data so workspace (and any other
    // intentional grant) wins last-match while non-workspace Data homes stay denied.
    try out.appendSlice(allocator,
        \\
        \\;; deny data-volume firmlink surface (homes / host secrets); re-allow grants below
        \\(deny file-read* (subpath "/System/Volumes/Data"))
        \\(deny file-read-metadata (subpath "/System/Volumes/Data"))
        \\(deny process-exec (subpath "/System/Volumes/Data"))
        \\
    );

    var reallowed = false;
    for (compiled.grants) |g| {
        if (!grantUnderDataVolume(g.path)) continue;
        if (!reallowed) {
            try out.appendSlice(allocator, ";; re-allow grants under /System/Volumes/Data (last-match after Data deny)\n");
            reallowed = true;
        }
        try appendAllowSubpath(&out, allocator, "file-read-metadata", g.path);
        switch (g.mode) {
            .ro, .exec => {
                try appendAllowSubpath(&out, allocator, "file-read*", g.path);
                try appendAllowSubpath(&out, allocator, "process-exec", g.path);
            },
            .rw => {
                try appendAllowSubpath(&out, allocator, "file-read*", g.path);
                try appendAllowWriteMinusControls(&out, allocator, g.path, compiled.control_roots);
            },
        }
    }

    // No broad HOME: assert via absence — never emit $HOME or ~ grants.
    return try out.toOwnedSlice(allocator);
}

/// True when a grant path is exactly Data volume or a strict descendant (realpath workspace).
fn grantUnderDataVolume(path: []const u8) bool {
    const data = "/System/Volumes/Data";
    return profile.isPathWithin(path, data);
}

fn appendAllowSubpath(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    op: []const u8,
    path: []const u8,
) !void {
    try out.appendSlice(allocator, "(allow ");
    try out.appendSlice(allocator, op);
    try out.appendSlice(allocator, " (subpath \"");
    try appendEscaped(out, allocator, path);
    try out.appendSlice(allocator, "\"))\n");
}

fn appendDenySubpath(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    op: []const u8,
    path: []const u8,
) !void {
    try out.appendSlice(allocator, "(deny ");
    try out.appendSlice(allocator, op);
    try out.appendSlice(allocator, " (subpath \"");
    try appendEscaped(out, allocator, path);
    try out.appendSlice(allocator, "\"))\n");
}

fn appendAllowWriteMinusControls(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    path: []const u8,
    control_roots: []const []const u8,
) !void {
    // (allow file-write* (require-all (subpath "ws") (require-not (subpath "ctrl")) ...))
    try out.appendSlice(allocator, "(allow file-write* (require-all (subpath \"");
    try appendEscaped(out, allocator, path);
    try out.appendSlice(allocator, "\")");
    for (control_roots) |root| {
        // Only carve controls that sit under this RW grant.
        if (!profile.isPathWithin(root, path) and !std.mem.eql(u8, root, path)) continue;
        try out.appendSlice(allocator, " (require-not (subpath \"");
        try appendEscaped(out, allocator, root);
        try out.appendSlice(allocator, "\"))");
    }
    try out.appendSlice(allocator, "))\n");
}

fn appendEscaped(out: *std.ArrayList(u8), allocator: std.mem.Allocator, path: []const u8) !void {
    for (path) |c| {
        switch (c) {
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '"' => try out.appendSlice(allocator, "\\\""),
            else => try out.append(allocator, c),
        }
    }
}

/// True if SBPL text grants a broad home directory (should always be false for Orca profiles).
pub fn sbplGrantsHome(sbpl: []const u8, home: []const u8) bool {
    if (home.len == 0) return false;
    // Match exact subpath "HOME" grant forms only (not workspace under home).
    var needle_buf: [512]u8 = undefined;
    if (home.len + 32 > needle_buf.len) return false;
    const needle = std.fmt.bufPrint(&needle_buf, "(subpath \"{s}\")", .{home}) catch return false;
    // Only count as broad HOME if the grant is exactly HOME, not a longer path.
    // Search for the needle and ensure the next char after home in the path is `"`.
    return std.mem.indexOf(u8, sbpl, needle) != null;
}

// ── tests ──────────────────────────────────────────────────────────────────

test "SBPL denies default and grants workspace RW" {
    const allocator = std.testing.allocator;
    var compiled = try profile.compileProfile(allocator, .{
        .workspace_root = "/tmp/orca-sbpl-ws",
        .system_ro_prefixes = &[_][]const u8{ "/usr", "/bin" },
    });
    defer compiled.deinit();

    const sbpl = try renderSbpl(allocator, &compiled);
    defer allocator.free(sbpl);

    try std.testing.expect(std.mem.indexOf(u8, sbpl, "(deny default)") != null);
    try std.testing.expect(std.mem.indexOf(u8, sbpl, "(version 1)") != null);
    try std.testing.expect(std.mem.indexOf(u8, sbpl, "(subpath \"/tmp/orca-sbpl-ws\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, sbpl, "file-write*") != null);
}

test "SBPL system prefixes are read-only not write" {
    const allocator = std.testing.allocator;
    var compiled = try profile.compileProfile(allocator, .{
        .workspace_root = "/workspace/proj",
        .system_ro_prefixes = &[_][]const u8{ "/usr", "/bin" },
    });
    defer compiled.deinit();

    const sbpl = try renderSbpl(allocator, &compiled);
    defer allocator.free(sbpl);

    try std.testing.expect(std.mem.indexOf(u8, sbpl, "(allow file-read* (subpath \"/usr\"))") != null);
    try std.testing.expect(std.mem.indexOf(u8, sbpl, "(allow file-read* (subpath \"/bin\"))") != null);
    // No bare write grant for system prefixes.
    try std.testing.expect(std.mem.indexOf(u8, sbpl, "(allow file-write* (subpath \"/usr\"))") == null);
    try std.testing.expect(std.mem.indexOf(u8, sbpl, "(allow file-write* (subpath \"/bin\"))") == null);
}

test "SBPL control roots deny write under workspace" {
    const allocator = std.testing.allocator;
    var compiled = try profile.compileProfile(allocator, .{
        .workspace_root = "/workspace/proj",
        .system_ro_prefixes = &[_][]const u8{"/usr"},
    });
    defer compiled.deinit();

    const sbpl = try renderSbpl(allocator, &compiled);
    defer allocator.free(sbpl);

    try std.testing.expect(std.mem.indexOf(u8, sbpl, "(require-not (subpath \"/workspace/proj/.orca\"))") != null);
    try std.testing.expect(std.mem.indexOf(u8, sbpl, "(deny file-write* (subpath \"/workspace/proj/.orca\"))") != null);
}

test "SBPL never grants broad HOME" {
    const allocator = std.testing.allocator;
    const home = "/Users/dev";
    const ws = "/Users/dev/projects/app";
    var compiled = try profile.compileProfile(allocator, .{
        .workspace_root = ws,
        .system_ro_prefixes = &[_][]const u8{ "/usr", "/bin" },
    });
    defer compiled.deinit();

    const sbpl = try renderSbpl(allocator, &compiled);
    defer allocator.free(sbpl);

    try std.testing.expect(!sbplGrantsHome(sbpl, home));
    try std.testing.expect(std.mem.indexOf(u8, sbpl, home) != null); // workspace path contains home prefix
    // Exact HOME subpath grant must not appear.
    var exact: [128]u8 = undefined;
    const needle = try std.fmt.bufPrint(&exact, "(subpath \"{s}\")", .{home});
    // Workspace grant is longer: (subpath "/Users/dev/projects/app") — allowed.
    // Count only exact HOME: path ends with home then quote.
    try std.testing.expect(std.mem.indexOf(u8, sbpl, needle) == null);
    try std.testing.expect(!compiled.grantsHome(home));
}

test "SBPL escapes quotes and backslashes in paths" {
    const allocator = std.testing.allocator;
    const nasty = "/tmp/x\"y\\z";
    var compiled = try profile.compileProfile(allocator, .{
        .workspace_root = nasty,
        .system_ro_prefixes = &[_][]const u8{"/usr"},
    });
    defer compiled.deinit();

    const sbpl = try renderSbpl(allocator, &compiled);
    defer allocator.free(sbpl);

    const escaped_grant = "(subpath \"/tmp/x\\\"y\\\\z\")";
    try std.testing.expect(std.mem.indexOf(u8, sbpl, escaped_grant) != null);
    const escaped_control = "(deny file-write* (subpath \"/tmp/x\\\"y\\\\z/.orca\"))";
    try std.testing.expect(std.mem.indexOf(u8, sbpl, escaped_control) != null);
}

test "SBPL never emits bare unrestricted file-read-metadata (M-4)" {
    const allocator = std.testing.allocator;
    var compiled = try profile.compileProfile(allocator, .{
        .workspace_root = "/tmp/orca-sbpl-meta",
        .system_ro_prefixes = &[_][]const u8{ "/usr", "/bin" },
    });
    defer compiled.deinit();

    const sbpl = try renderSbpl(allocator, &compiled);
    defer allocator.free(sbpl);

    // Bare form must not appear; only path-filtered metadata allows.
    try std.testing.expect(std.mem.indexOf(u8, sbpl, "(allow file-read-metadata)\n") == null);
    try std.testing.expect(std.mem.indexOf(u8, sbpl, "(allow file-read-metadata (literal \"/\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, sbpl, "(allow file-read-metadata (subpath \"/tmp/orca-sbpl-meta\"))") != null);
    try std.testing.expect(std.mem.indexOf(u8, sbpl, "(allow file-read-metadata (subpath \"/usr\"))") != null);
}

test "SBPL denies /System/Volumes/Data even if bare /System is granted (M-1)" {
    const allocator = std.testing.allocator;
    var compiled = try profile.compileProfile(allocator, .{
        .workspace_root = "/tmp/orca-sbpl-sys",
        // Adversarial: custom bare /System must still not open Data volume homes.
        .system_ro_prefixes = &[_][]const u8{ "/usr", "/System" },
    });
    defer compiled.deinit();

    const sbpl = try renderSbpl(allocator, &compiled);
    defer allocator.free(sbpl);

    try std.testing.expect(std.mem.indexOf(u8, sbpl, "(deny file-read* (subpath \"/System/Volumes/Data\"))") != null);
    try std.testing.expect(std.mem.indexOf(u8, sbpl, "(deny file-read-metadata (subpath \"/System/Volumes/Data\"))") != null);
    try std.testing.expect(std.mem.indexOf(u8, sbpl, "(deny process-exec (subpath \"/System/Volumes/Data\"))") != null);
    // Blanket deny of all Volumes is too broad (Preboot) and clobbers realpath workspaces.
    try std.testing.expect(std.mem.indexOf(u8, sbpl, "(deny file-read* (subpath \"/System/Volumes\"))") == null);
}

test "SBPL re-allows Data-volume realpath workspace after Data deny (R2-1)" {
    const allocator = std.testing.allocator;
    // Model macOS firmlink realpath: /Users/… → /System/Volumes/Data/Users/…
    const ws = "/System/Volumes/Data/Users/dev/projects/app";
    var compiled = try profile.compileProfile(allocator, .{
        .workspace_root = ws,
        .system_ro_prefixes = &[_][]const u8{ "/usr", "/bin" },
        .include_tmp = false,
    });
    defer compiled.deinit();

    // Pure model: workspace under Data remains granted; sibling home secrets are not.
    try std.testing.expect(compiled.isGrantedReadable(ws));
    try std.testing.expect(compiled.isAgentWritable(ws));
    try std.testing.expect(compiled.isGrantedReadable("/System/Volumes/Data/Users/dev/projects/app/src/main.zig"));
    try std.testing.expect(!compiled.isGrantedReadable("/System/Volumes/Data/Users/dev/.ssh/id_rsa"));
    try std.testing.expect(!compiled.isGrantedReadable("/System/Volumes/Data/Users/other/secret"));

    const sbpl = try renderSbpl(allocator, &compiled);
    defer allocator.free(sbpl);

    const deny_read = "(deny file-read* (subpath \"/System/Volumes/Data\"))";
    const allow_ws = "(allow file-read* (subpath \"/System/Volumes/Data/Users/dev/projects/app\"))";
    const deny_pos = std.mem.indexOf(u8, sbpl, deny_read) orelse {
        try std.testing.expect(false);
        return;
    };
    // Last re-allow for this workspace path must appear *after* the Data deny.
    const after_deny = sbpl[deny_pos..];
    try std.testing.expect(std.mem.indexOf(u8, after_deny, allow_ws) != null);
    try std.testing.expect(std.mem.indexOf(u8, after_deny, "(allow file-write*") != null);
    // Non-workspace Data home must not appear as a grant.
    try std.testing.expect(std.mem.indexOf(u8, sbpl, "(subpath \"/System/Volumes/Data/Users/dev/.ssh\")") == null);
}

test "SBPL production defaults omit bare /System and /Library grants (M-1 M-7)" {
    if (@import("builtin").os.tag != .macos) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var compiled = try profile.compileProfile(allocator, .{
        .workspace_root = "/tmp/orca-sbpl-defaults",
    });
    defer compiled.deinit();

    const sbpl = try renderSbpl(allocator, &compiled);
    defer allocator.free(sbpl);

    // Exact bare /System and /Library grant forms must not appear (trailing ")).
    try std.testing.expect(std.mem.indexOf(u8, sbpl, "(subpath \"/System\"))") == null);
    try std.testing.expect(std.mem.indexOf(u8, sbpl, "(subpath \"/Library\"))") == null);
    try std.testing.expect(std.mem.indexOf(u8, sbpl, "(subpath \"/System/Library\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, sbpl, "(subpath \"/Library/Frameworks\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, sbpl, "(deny file-read* (subpath \"/System/Volumes/Data\"))") != null);
}
