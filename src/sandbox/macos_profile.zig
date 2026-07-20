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
    try out.appendSlice(allocator,
        \\;; process / IPC baseline (FS confinement is the product surface)
        \\(allow process*)
        \\(allow signal)
        \\(allow sysctl-read)
        \\(allow mach-lookup)
        \\(allow mach-register)
        \\(allow network*)
        \\
        \\;; dyld / device / root metadata needed for exec
        \\(allow file-read-metadata)
        \\(allow file-read* (literal "/"))
        \\(allow file-read* (literal "/private"))
        \\(allow file-read* (literal "/private/tmp"))
        \\(allow file-read* (literal "/private/var"))
        \\(allow file-read* (literal "/private/var/tmp"))
        \\(allow file-read* (subpath "/dev"))
        \\(allow file-ioctl (subpath "/dev"))
        \\(allow file-read* (subpath "/private/var/db/dyld"))
        \\(allow file-write* (subpath "/dev"))
        \\
    );

    // Path grants from the portable profile model.
    try out.appendSlice(allocator, ";; compiled path grants\n");
    for (compiled.grants) |g| {
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

    // No broad HOME: assert via absence — never emit $HOME or ~ grants.
    return try out.toOwnedSlice(allocator);
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
        if (!isPathWithin(root, path) and !std.mem.eql(u8, root, path)) continue;
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

fn isPathWithin(path: []const u8, root: []const u8) bool {
    if (root.len == 0) return false;
    if (std.mem.eql(u8, path, root)) return true;
    if (path.len <= root.len) return false;
    if (!std.mem.startsWith(u8, path, root)) return false;
    if (root.len == 1 and root[0] == '/') return path.len > 1 and path[0] == '/';
    return path[root.len] == '/';
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
