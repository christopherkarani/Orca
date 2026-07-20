//! Pure OS-filesystem sandbox profile model (P1-U).
//!
//! Compiles a deterministic grant list: workspace RW (minus trusted Orca control
//! roots), system RO prefixes, optional explicit tmp — never a broad $HOME grant.
//! No Landlock/Seatbelt apply lives here; this is the portable grant model only.

const std = @import("std");
const builtin = @import("builtin");

/// Path access class for a grant entry.
pub const AccessMode = enum {
    /// Read-only (and typically execute at the apply layer for system roots).
    ro,
    /// Read-write agent workspace grant.
    rw,
    /// Execute-oriented grant (reserved for explicit binary paths).
    exec,

    pub fn toString(self: AccessMode) []const u8 {
        return @tagName(self);
    }
};

pub const PathGrant = struct {
    path: []const u8,
    mode: AccessMode,
};

pub const CompileOptions = struct {
    /// Absolute workspace root. Relative or empty → fail closed.
    workspace_root: []const u8,
    /// Extra trusted control roots (absolute, or relative to workspace).
    /// Always combined with `{workspace}/.orca`.
    control_roots: []const []const u8 = &.{},
    /// When true, add an explicit RW grant for `tmp_path` (default `/tmp`).
    include_tmp: bool = false,
    tmp_path: []const u8 = "/tmp",
    /// Override default system RO prefixes (tests / platforms). Null = use defaults.
    system_ro_prefixes: ?[]const []const u8 = null,
};

pub const CompiledProfile = struct {
    allocator: std.mem.Allocator,
    /// Absolute canonical workspace root used at compile time.
    workspace_root: []const u8,
    /// Positive path grants (owned paths).
    grants: []PathGrant,
    /// Absolute control roots that are NOT agent-writable (owned paths).
    control_roots: []const []const u8,
    /// Deterministic serialization used for hashing (owned).
    canonical_bytes: []const u8,
    /// Lowercase hex SHA-256 of `canonical_bytes`.
    hash_hex: [64]u8,

    pub fn deinit(self: *CompiledProfile) void {
        self.allocator.free(self.workspace_root);
        for (self.grants) |g| self.allocator.free(g.path);
        self.allocator.free(self.grants);
        for (self.control_roots) |p| self.allocator.free(p);
        self.allocator.free(self.control_roots);
        self.allocator.free(self.canonical_bytes);
        self.* = undefined;
    }

    pub fn hash(self: *const CompiledProfile) []const u8 {
        return self.hash_hex[0..];
    }

    /// True if any grant has the given absolute (or grant-listed) path and mode.
    pub fn hasGrant(self: *const CompiledProfile, path: []const u8, mode: AccessMode) bool {
        for (self.grants) |g| {
            if (g.mode == mode and pathEqual(g.path, path)) return true;
        }
        return false;
    }

    /// True if `path` is under a control root (not agent-writable).
    pub fn isControlPath(self: *const CompiledProfile, path: []const u8) bool {
        for (self.control_roots) |root| {
            if (isPathWithin(path, root)) return true;
        }
        return false;
    }

    /// Agent-writable only under an RW grant and outside all control roots.
    ///
    /// Pure grant model (Seatbelt-shaped). Linux Landlock expands RW parents that
    /// contain control roots into child RW + parent RO, so **create-at-workspace-root**
    /// may be denied by the OS even when this returns true for paths under the
    /// workspace (see landlock.addRwGrantExcludingControls). Prefer writing under
    /// existing workspace children for portable agent I/O.
    pub fn isAgentWritable(self: *const CompiledProfile, path: []const u8) bool {
        if (self.isControlPath(path)) return false;
        for (self.grants) |g| {
            if (g.mode == .rw and isPathWithin(path, g.path)) return true;
        }
        return false;
    }

    /// True if any grant is exactly `home` (broad HOME). Workspace *under* home is fine.
    pub fn grantsHome(self: *const CompiledProfile, home: []const u8) bool {
        if (home.len == 0) return false;
        for (self.grants) |g| {
            if (pathEqual(g.path, home)) return true;
        }
        return false;
    }
};

/// Default system read-only prefixes (no home, no /tmp).
/// Includes `/opt` on macOS so Homebrew-style agent binaries can exec under Seatbelt.
pub fn defaultSystemRoPrefixes() []const []const u8 {
    return switch (builtin.os.tag) {
        .macos => &[_][]const u8{ "/usr", "/bin", "/sbin", "/lib", "/System", "/Library", "/opt" },
        else => &[_][]const u8{ "/usr", "/bin", "/sbin", "/lib" },
    };
}

/// Compile a pure profile. Fail closed on empty/invalid workspace — never open grants.
pub fn compileProfile(allocator: std.mem.Allocator, options: CompileOptions) !CompiledProfile {
    const workspace_root = try canonicalizeAbsolute(allocator, options.workspace_root);
    errdefer allocator.free(workspace_root);

    var grants_list: std.ArrayList(PathGrant) = .empty;
    errdefer {
        for (grants_list.items) |g| allocator.free(g.path);
        grants_list.deinit(allocator);
    }

    // Workspace RW — never $HOME.
    {
        const ws_grant = try allocator.dupe(u8, workspace_root);
        grants_list.append(allocator, .{ .path = ws_grant, .mode = .rw }) catch |err| {
            allocator.free(ws_grant);
            return err;
        };
    }

    // System RO prefixes (explicit allowlist only).
    const system_prefixes = options.system_ro_prefixes orelse defaultSystemRoPrefixes();
    for (system_prefixes) |prefix| {
        const canon = try canonicalizeAbsolute(allocator, prefix);
        grants_list.append(allocator, .{ .path = canon, .mode = .ro }) catch |err| {
            allocator.free(canon);
            return err;
        };
    }

    // Optional explicit tmp (not ambient HOME).
    if (options.include_tmp) {
        const tmp = try canonicalizeAbsolute(allocator, options.tmp_path);
        grants_list.append(allocator, .{ .path = tmp, .mode = .rw }) catch |err| {
            allocator.free(tmp);
            return err;
        };
    }

    // Control roots: always workspace/.orca plus any listed roots.
    var control_list: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (control_list.items) |c| allocator.free(c);
        control_list.deinit(allocator);
    }

    {
        const default_control = try joinAbsolute(allocator, workspace_root, ".orca");
        control_list.append(allocator, default_control) catch |err| {
            allocator.free(default_control);
            return err;
        };
    }

    for (options.control_roots) |raw| {
        const resolved = try resolveControlRoot(allocator, workspace_root, raw);
        // Dedup exact matches.
        var exists = false;
        for (control_list.items) |existing| {
            if (pathEqual(existing, resolved)) {
                exists = true;
                break;
            }
        }
        if (exists) {
            allocator.free(resolved);
            continue;
        }
        control_list.append(allocator, resolved) catch |err| {
            allocator.free(resolved);
            return err;
        };
    }

    // Deterministic order: grants by path then mode; control roots by path.
    std.mem.sort(PathGrant, grants_list.items, {}, grantLessThan);
    std.mem.sort([]const u8, control_list.items, {}, pathLessThan);

    const grants = try grants_list.toOwnedSlice(allocator);
    errdefer {
        for (grants) |g| allocator.free(g.path);
        allocator.free(grants);
    }
    const control_roots = try control_list.toOwnedSlice(allocator);
    errdefer {
        for (control_roots) |c| allocator.free(c);
        allocator.free(control_roots);
    }

    const canonical_bytes = try serializeCanonical(allocator, grants, control_roots);
    errdefer allocator.free(canonical_bytes);

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(canonical_bytes, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    var hash_hex: [64]u8 = undefined;
    @memcpy(hash_hex[0..], hex[0..]);

    return .{
        .allocator = allocator,
        .workspace_root = workspace_root,
        .grants = grants,
        .control_roots = control_roots,
        .canonical_bytes = canonical_bytes,
        .hash_hex = hash_hex,
    };
}

// --- path helpers ----------------------------------------------------------------

fn pathEqual(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// True if `path` is exactly `root` or a strict descendant (`root/` prefix).
fn isPathWithin(path: []const u8, root: []const u8) bool {
    if (root.len == 0) return false;
    if (pathEqual(path, root)) return true;
    if (path.len <= root.len) return false;
    if (!std.mem.startsWith(u8, path, root)) return false;
    // Root "/" covers everything absolute.
    if (root.len == 1 and root[0] == '/') return path.len > 1 and path[0] == '/';
    return path[root.len] == '/';
}

fn pathLessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

fn grantLessThan(_: void, a: PathGrant, b: PathGrant) bool {
    const path_order = std.mem.order(u8, a.path, b.path);
    if (path_order != .eq) return path_order == .lt;
    return @intFromEnum(a.mode) < @intFromEnum(b.mode);
}

/// Lexically canonicalize an absolute Unix-style path. Fail closed if not absolute.
fn canonicalizeAbsolute(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    if (raw.len == 0) return error.InvalidWorkspace;
    // Reject null bytes.
    if (std.mem.indexOfScalar(u8, raw, 0) != null) return error.InvalidWorkspace;
    if (!std.fs.path.isAbsolute(raw)) return error.InvalidWorkspace;

    // Normalize separators and collapse . / ..
    var components: std.ArrayList([]const u8) = .empty;
    defer components.deinit(allocator);

    var it = std.mem.splitScalar(u8, raw, '/');
    while (it.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".")) continue;
        if (std.mem.eql(u8, part, "..")) {
            if (components.items.len > 0) _ = components.pop();
            continue;
        }
        try components.append(allocator, part);
    }

    if (components.items.len == 0) {
        // Path reduced to filesystem root.
        return try allocator.dupe(u8, "/");
    }

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    for (components.items) |part| {
        try out.append(allocator, '/');
        try out.appendSlice(allocator, part);
    }
    return try out.toOwnedSlice(allocator);
}

fn joinAbsolute(allocator: std.mem.Allocator, root: []const u8, rel: []const u8) ![]u8 {
    if (rel.len == 0) return try allocator.dupe(u8, root);
    if (std.fs.path.isAbsolute(rel)) return try canonicalizeAbsolute(allocator, rel);
    // Trim leading ./ from relative.
    var clean = rel;
    while (std.mem.startsWith(u8, clean, "./")) clean = clean[2..];
    const joined = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ root, clean });
    defer allocator.free(joined);
    return try canonicalizeAbsolute(allocator, joined);
}

fn resolveControlRoot(allocator: std.mem.Allocator, workspace_root: []const u8, raw: []const u8) ![]u8 {
    if (raw.len == 0) return error.InvalidWorkspace;
    if (std.fs.path.isAbsolute(raw)) return try canonicalizeAbsolute(allocator, raw);
    return try joinAbsolute(allocator, workspace_root, raw);
}

/// Sorted newline list of `mode\\tpath` grants and `control\\tpath` carve-outs.
fn serializeCanonical(
    allocator: std.mem.Allocator,
    grants: []const PathGrant,
    control_roots: []const []const u8,
) ![]u8 {
    var lines: std.ArrayList([]u8) = .empty;
    defer {
        for (lines.items) |line| allocator.free(line);
        lines.deinit(allocator);
    }

    for (grants) |g| {
        const line = try std.fmt.allocPrint(allocator, "{s}\t{s}", .{ g.mode.toString(), g.path });
        lines.append(allocator, line) catch |err| {
            allocator.free(line);
            return err;
        };
    }
    for (control_roots) |root| {
        const line = try std.fmt.allocPrint(allocator, "control\t{s}", .{root});
        lines.append(allocator, line) catch |err| {
            allocator.free(line);
            return err;
        };
    }

    std.mem.sort([]u8, lines.items, {}, pathLessThan);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    for (lines.items, 0..) |line, i| {
        if (i > 0) try out.append(allocator, '\n');
        try out.appendSlice(allocator, line);
    }
    // Trailing newline for stable multi-line form (even for a single line).
    if (lines.items.len > 0) try out.append(allocator, '\n');
    return try out.toOwnedSlice(allocator);
}

// --- tests (P1-U) ----------------------------------------------------------------

test "P1-U-01 workspace grant is RW for absolute workspace" {
    const allocator = std.testing.allocator;
    const ws = "/tmp/orca-profile-ws-unit";
    var profile = try compileProfile(allocator, .{
        .workspace_root = ws,
        .system_ro_prefixes = &[_][]const u8{ "/usr", "/bin" },
    });
    defer profile.deinit();

    try std.testing.expect(profile.hasGrant(ws, .rw));
    try std.testing.expect(profile.isAgentWritable(ws));
    try std.testing.expect(profile.isAgentWritable("/tmp/orca-profile-ws-unit/src/main.zig"));
    try std.testing.expectEqualStrings(ws, profile.workspace_root);
}

test "P1-U-02 system prefixes are RO only" {
    const allocator = std.testing.allocator;
    const prefixes = [_][]const u8{ "/usr", "/bin", "/sbin", "/lib" };
    var profile = try compileProfile(allocator, .{
        .workspace_root = "/workspace/proj",
        .system_ro_prefixes = &prefixes,
    });
    defer profile.deinit();

    for (prefixes) |p| {
        try std.testing.expect(profile.hasGrant(p, .ro));
        try std.testing.expect(!profile.hasGrant(p, .rw));
        try std.testing.expect(!profile.isAgentWritable(p));
    }
    try std.testing.expect(!profile.isAgentWritable("/usr/bin/true"));
    try std.testing.expect(!profile.isAgentWritable("/bin/sh"));
}

test "P1-U-04 trusted Orca state carve-out is not agent-writable" {
    const allocator = std.testing.allocator;
    const ws = "/workspace/proj";
    var profile = try compileProfile(allocator, .{
        .workspace_root = ws,
        .system_ro_prefixes = &[_][]const u8{"/usr"},
        .control_roots = &[_][]const u8{".orca/extra-control"},
    });
    defer profile.deinit();

    // Default workspace/.orca is always a control root.
    try std.testing.expect(profile.isControlPath("/workspace/proj/.orca"));
    try std.testing.expect(profile.isControlPath("/workspace/proj/.orca/policy.yaml"));
    try std.testing.expect(profile.isControlPath("/workspace/proj/.orca/sessions/mode"));
    try std.testing.expect(!profile.isAgentWritable("/workspace/proj/.orca/policy.yaml"));
    try std.testing.expect(!profile.isAgentWritable("/workspace/proj/.orca/sessions/approvals"));

    // Extra control root (relative → under workspace).
    try std.testing.expect(profile.isControlPath("/workspace/proj/.orca/extra-control"));
    try std.testing.expect(!profile.isAgentWritable("/workspace/proj/.orca/extra-control/ipc.sock"));

    // Ordinary workspace file remains writable.
    try std.testing.expect(profile.isAgentWritable("/workspace/proj/src/app.zig"));
}

test "P1-U-03 no broad HOME grant" {
    const allocator = std.testing.allocator;
    const home = "/Users/dev";
    const ws = "/Users/dev/projects/app";
    var profile = try compileProfile(allocator, .{
        .workspace_root = ws,
        .system_ro_prefixes = &[_][]const u8{ "/usr", "/bin" },
    });
    defer profile.deinit();

    try std.testing.expect(!profile.hasGrant(home, .rw));
    try std.testing.expect(!profile.hasGrant(home, .ro));
    try std.testing.expect(!profile.grantsHome(home));
    // HOME itself must not be agent-writable via grants.
    try std.testing.expect(!profile.isAgentWritable(home));
    try std.testing.expect(!profile.isAgentWritable("/Users/dev/.ssh/id_rsa"));
    // Workspace under home is still granted (narrower than HOME).
    try std.testing.expect(profile.isAgentWritable(ws));
}

test "P1-U-06 empty and relative workspace fail closed" {
    const allocator = std.testing.allocator;

    try std.testing.expectError(error.InvalidWorkspace, compileProfile(allocator, .{
        .workspace_root = "",
    }));
    try std.testing.expectError(error.InvalidWorkspace, compileProfile(allocator, .{
        .workspace_root = "relative/path",
    }));
    try std.testing.expectError(error.InvalidWorkspace, compileProfile(allocator, .{
        .workspace_root = ".",
    }));
    try std.testing.expectError(error.InvalidWorkspace, compileProfile(allocator, .{
        .workspace_root = "workspace",
    }));
}

test "P1-U-07 determinism: same inputs yield same canonical bytes and hash" {
    const allocator = std.testing.allocator;
    const opts = CompileOptions{
        .workspace_root = "/workspace/same",
        .system_ro_prefixes = &[_][]const u8{ "/lib", "/usr", "/bin" },
        .include_tmp = true,
        .tmp_path = "/tmp",
        .control_roots = &[_][]const u8{"/var/orca-control"},
    };

    var a = try compileProfile(allocator, opts);
    defer a.deinit();
    var b = try compileProfile(allocator, opts);
    defer b.deinit();

    try std.testing.expectEqualStrings(a.canonical_bytes, b.canonical_bytes);
    try std.testing.expectEqualStrings(a.hash(), b.hash());
    try std.testing.expect(a.hash().len == 64);

    // Different workspace → different hash.
    var c = try compileProfile(allocator, .{
        .workspace_root = "/workspace/other",
        .system_ro_prefixes = opts.system_ro_prefixes,
        .include_tmp = true,
        .tmp_path = "/tmp",
        .control_roots = opts.control_roots,
    });
    defer c.deinit();
    try std.testing.expect(!std.mem.eql(u8, a.hash(), c.hash()));
}

test "optional tmp grant is RW only when requested" {
    const allocator = std.testing.allocator;

    var without = try compileProfile(allocator, .{
        .workspace_root = "/workspace/a",
        .system_ro_prefixes = &[_][]const u8{"/usr"},
        .include_tmp = false,
    });
    defer without.deinit();
    try std.testing.expect(!without.hasGrant("/tmp", .rw));

    var with_tmp = try compileProfile(allocator, .{
        .workspace_root = "/workspace/a",
        .system_ro_prefixes = &[_][]const u8{"/usr"},
        .include_tmp = true,
        .tmp_path = "/tmp",
    });
    defer with_tmp.deinit();
    try std.testing.expect(with_tmp.hasGrant("/tmp", .rw));
    try std.testing.expect(with_tmp.isAgentWritable("/tmp/orca-scratch"));
}
