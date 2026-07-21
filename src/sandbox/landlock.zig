//! Linux Landlock FS apply (U05 / Slice 9).
//!
//! Sequence:
//!   **Parent (before fork):** `buildChildLandlockPlan` enumerates control-expand
//!   RW children (opendir/readdir/malloc OK — may run under a multi-threaded parent).
//!   **Child (after fork):** ABI detect → rights mask → create ruleset → PATH_BENEATH
//!   grants from the precomputed plan only (open + landlock syscalls; **no**
//!   opendir/readdir) → prctl(NO_NEW_PRIVS) → landlock_restrict_self → exec.
//!
//! Never box the parent Orca CLI. Network Landlock is **never** claimed (Phase 2).
//! Only filesystem PATH_BENEATH rules from `CompiledProfile` grants + expand plan.
//!
//! On non-Linux: compile-time stubs; probes return unavailable; apply errors.
//! Parent-side expand helpers still run for unit tests on any POSIX host.

const std = @import("std");
const builtin = @import("builtin");
const profile = @import("profile.zig");

/// Flag for landlock_create_ruleset to query highest supported ABI version.
pub const CREATE_RULESET_VERSION: u32 = 1 << 0;

/// landlock_add_rule type: filesystem path hierarchy.
pub const RULE_PATH_BENEATH: u32 = 1;

// LANDLOCK_ACCESS_FS_* (uapi/linux/landlock.h)
pub const ACCESS_FS_EXECUTE: u64 = 1 << 0;
pub const ACCESS_FS_WRITE_FILE: u64 = 1 << 1;
pub const ACCESS_FS_READ_FILE: u64 = 1 << 2;
pub const ACCESS_FS_READ_DIR: u64 = 1 << 3;
pub const ACCESS_FS_REMOVE_DIR: u64 = 1 << 4;
pub const ACCESS_FS_REMOVE_FILE: u64 = 1 << 5;
pub const ACCESS_FS_MAKE_CHAR: u64 = 1 << 6;
pub const ACCESS_FS_MAKE_DIR: u64 = 1 << 7;
pub const ACCESS_FS_MAKE_REG: u64 = 1 << 8;
pub const ACCESS_FS_MAKE_SOCK: u64 = 1 << 9;
pub const ACCESS_FS_MAKE_FIFO: u64 = 1 << 10;
pub const ACCESS_FS_MAKE_BLOCK: u64 = 1 << 11;
pub const ACCESS_FS_MAKE_SYM: u64 = 1 << 12;
/// ABI ≥ 2
pub const ACCESS_FS_REFER: u64 = 1 << 13;
/// ABI ≥ 3
pub const ACCESS_FS_TRUNCATE: u64 = 1 << 14;
/// ABI ≥ 5
pub const ACCESS_FS_IOCTL_DEV: u64 = 1 << 15;

/// Minimum ABI we require (kernel 5.13+).
pub const MIN_ABI: u32 = 1;

/// FS rights present in ABI 1.
pub const FS_RIGHTS_ABI1: u64 = ACCESS_FS_EXECUTE | ACCESS_FS_WRITE_FILE | ACCESS_FS_READ_FILE |
    ACCESS_FS_READ_DIR | ACCESS_FS_REMOVE_DIR | ACCESS_FS_REMOVE_FILE | ACCESS_FS_MAKE_CHAR |
    ACCESS_FS_MAKE_DIR | ACCESS_FS_MAKE_REG | ACCESS_FS_MAKE_SOCK | ACCESS_FS_MAKE_FIFO |
    ACCESS_FS_MAKE_BLOCK | ACCESS_FS_MAKE_SYM;

pub const ApplyError = error{
    /// Landlock syscalls missing or ABI too old.
    Unavailable,
    /// Syscall failed after ABI probe succeeded.
    ApplyFailed,
    /// Workspace / required path could not be opened for PATH_BENEATH.
    PathOpenFailed,
    /// Not running on Linux.
    Unsupported,
};

pub const AbiInfo = struct {
    /// Highest supported ABI version (1+).
    version: u32,
};

/// Pure: handled_access_fs mask for a given ABI. Never includes network rights.
pub fn handledFsRights(abi: u32) u64 {
    var rights: u64 = FS_RIGHTS_ABI1;
    if (abi >= 2) rights |= ACCESS_FS_REFER;
    if (abi >= 3) rights |= ACCESS_FS_TRUNCATE;
    if (abi >= 5) rights |= ACCESS_FS_IOCTL_DEV;
    // ABI 4+ adds network — intentionally omitted (no network Landlock claim).
    return rights;
}

/// Pure: allowed_access for a single PATH_BENEATH grant under the given ABI.
pub fn allowedAccessForMode(mode: profile.AccessMode, abi: u32) u64 {
    const handled = handledFsRights(abi);
    const ro: u64 = ACCESS_FS_READ_FILE | ACCESS_FS_READ_DIR | ACCESS_FS_EXECUTE;
    const rw_base: u64 = ro | ACCESS_FS_WRITE_FILE | ACCESS_FS_REMOVE_DIR | ACCESS_FS_REMOVE_FILE |
        ACCESS_FS_MAKE_CHAR | ACCESS_FS_MAKE_DIR | ACCESS_FS_MAKE_REG | ACCESS_FS_MAKE_SOCK |
        ACCESS_FS_MAKE_FIFO | ACCESS_FS_MAKE_BLOCK | ACCESS_FS_MAKE_SYM;
    var want: u64 = switch (mode) {
        .ro => ro,
        .rw => rw_base,
        .exec => ACCESS_FS_EXECUTE | ACCESS_FS_READ_FILE | ACCESS_FS_READ_DIR,
    };
    if (abi >= 2 and mode == .rw) want |= ACCESS_FS_REFER;
    if (abi >= 3 and mode == .rw) want |= ACCESS_FS_TRUNCATE;
    if (abi >= 5 and mode == .rw) want |= ACCESS_FS_IOCTL_DEV;
    return want & handled;
}

/// Probe Landlock ABI version. Null when unavailable / non-Linux.
pub fn probeAbi() ?AbiInfo {
    if (builtin.os.tag != .linux) return null;
    return probeAbiLinux();
}

pub fn isAbiAvailable() bool {
    const info = probeAbi() orelse return false;
    return info.version >= MIN_ABI;
}

/// Parent-side surfaces for one RW grant that needs control expand (Z-3).
/// Built before fork; the child only installs PATH_BENEATH from these paths.
pub const ControlExpandSurfaces = struct {
    allocator: std.mem.Allocator,
    /// RO PATH_BENEATH with required=true (grant root + nested expand roots).
    expand_roots: []const []const u8,
    /// RO PATH_BENEATH with required=false (control roots under the grant tree).
    control_ro_paths: []const []const u8,
    /// RW PATH_BENEATH leaf targets (non-control, non-symlink children).
    rw_paths: []const []const u8,

    pub fn deinit(self: *ControlExpandSurfaces) void {
        freeOwnedPaths(self.allocator, self.expand_roots);
        freeOwnedPaths(self.allocator, self.control_ro_paths);
        freeOwnedPaths(self.allocator, self.rw_paths);
        self.* = undefined;
    }

    pub fn anyRw(self: *const ControlExpandSurfaces) bool {
        return self.rw_paths.len > 0;
    }
};

/// Owned multi-grant expand plan consumed by child `applySelf` (Z-3).
/// Parent builds this before fork; after fork the child must not re-enumerate.
pub const ChildLandlockPlan = struct {
    allocator: std.mem.Allocator,
    expands: []ExpandByGrant,

    pub const ExpandByGrant = struct {
        /// Borrowed from `CompiledProfile.grants` — not owned.
        grant_path: []const u8,
        surfaces: ControlExpandSurfaces,
    };

    pub fn deinit(self: *ChildLandlockPlan) void {
        for (self.expands) |*entry| {
            entry.surfaces.deinit();
        }
        self.allocator.free(self.expands);
        self.* = undefined;
    }

    pub fn surfacesFor(self: *const ChildLandlockPlan, grant_path: []const u8) ?*const ControlExpandSurfaces {
        for (self.expands) |*entry| {
            if (std.mem.eql(u8, entry.grant_path, grant_path)) return &entry.surfaces;
        }
        return null;
    }
};

fn freeOwnedPaths(allocator: std.mem.Allocator, paths: []const []const u8) void {
    for (paths) |p| allocator.free(p);
    allocator.free(paths);
}

fn appendOwnedPath(list: *std.ArrayList([]const u8), allocator: std.mem.Allocator, path: []const u8) !void {
    const owned = try allocator.dupe(u8, path);
    errdefer allocator.free(owned);
    try list.append(allocator, owned);
}

/// Parent-side (or single-threaded): enumerate control-expand RO/RW PATH_BENEATH
/// surfaces for one RW grant. May allocate and call opendir/readdir — **never**
/// invoke after a multi-threaded fork (Z-3).
pub fn buildControlExpandSurfaces(
    allocator: std.mem.Allocator,
    grant_path: []const u8,
    control_roots: []const []const u8,
) !ControlExpandSurfaces {
    var expand_roots: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (expand_roots.items) |p| allocator.free(p);
        expand_roots.deinit(allocator);
    }
    var control_ro: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (control_ro.items) |p| allocator.free(p);
        control_ro.deinit(allocator);
    }
    var rw_paths: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (rw_paths.items) |p| allocator.free(p);
        rw_paths.deinit(allocator);
    }

    try collectExpandSurfaces(allocator, grant_path, control_roots, &expand_roots, &control_ro, &rw_paths);

    return .{
        .allocator = allocator,
        .expand_roots = try expand_roots.toOwnedSlice(allocator),
        .control_ro_paths = try control_ro.toOwnedSlice(allocator),
        .rw_paths = try rw_paths.toOwnedSlice(allocator),
    };
}

/// Recursive enumeration matching historical child-side expand semantics.
fn collectExpandSurfaces(
    allocator: std.mem.Allocator,
    grant_path: []const u8,
    control_roots: []const []const u8,
    expand_roots: *std.ArrayList([]const u8),
    control_ro: *std.ArrayList([]const u8),
    rw_paths: *std.ArrayList([]const u8),
) !void {
    try appendOwnedPath(expand_roots, allocator, grant_path);

    for (control_roots) |root| {
        if (!pathIsWithin(root, grant_path)) continue;
        try appendOwnedPath(control_ro, allocator, root);
    }

    // Grant path itself is a control root: RO only, no RW children.
    if (isControlPath(grant_path, control_roots)) return;

    // Parent-side enumeration only (malloc / libc dirents OK here).
    if (builtin.os.tag == .windows) return error.PathOpenFailed;

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    if (grant_path.len == 0 or grant_path.len >= path_buf.len) return error.PathOpenFailed;
    @memcpy(path_buf[0..grant_path.len], grant_path);
    path_buf[grant_path.len] = 0;
    const dir = std.c.opendir(path_buf[0..grant_path.len :0].ptr) orelse return error.PathOpenFailed;
    defer _ = std.c.closedir(dir);

    while (true) {
        const entry = std.c.readdir(dir) orelse break;
        const name = std.mem.sliceTo(entry.name[0..], 0);
        if (name.len == 0 or std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        // Skip symlink children (DT_LNK). DT_UNKNOWN still goes through O_NOFOLLOW open later.
        if (entry.type == std.c.DT.LNK) continue;

        const joined = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ grant_path, name });

        if (isControlPath(joined, control_roots)) {
            allocator.free(joined);
            continue;
        }
        if (grantCoversControlRoot(joined, control_roots)) {
            // Nested expand: recurse then drop the temporary joined path (recursion owns copies).
            defer allocator.free(joined);
            try collectExpandSurfaces(allocator, joined, control_roots, expand_roots, control_ro, rw_paths);
            continue;
        }
        // Leaf RW surface — transfer ownership into rw_paths.
        rw_paths.append(allocator, joined) catch |err| {
            allocator.free(joined);
            return err;
        };
    }
}

/// Parent-side: build expand surfaces for every RW grant that needs control expand.
pub fn buildChildLandlockPlan(
    allocator: std.mem.Allocator,
    compiled: *const profile.CompiledProfile,
) !ChildLandlockPlan {
    var expands: std.ArrayList(ChildLandlockPlan.ExpandByGrant) = .empty;
    errdefer {
        for (expands.items) |*e| e.surfaces.deinit();
        expands.deinit(allocator);
    }

    for (compiled.grants) |grant| {
        if (grant.mode != .rw) continue;
        if (!rwGrantNeedsControlExpand(grant.path, compiled.control_roots)) continue;
        var surfaces = try buildControlExpandSurfaces(allocator, grant.path, compiled.control_roots);
        errdefer surfaces.deinit();
        try expands.append(allocator, .{
            .grant_path = grant.path,
            .surfaces = surfaces,
        });
    }

    return .{
        .allocator = allocator,
        .expands = try expands.toOwnedSlice(allocator),
    };
}

/// Apply Landlock FS rules for `compiled` to the **current** process using a
/// parent-precomputed `plan` for control-expand grants.
/// Must only be called in a forked child (or a dedicated sandbox helper).
/// Does not exec — caller performs exec after success.
/// Child path never calls opendir/readdir (Z-3).
pub fn applySelf(compiled: *const profile.CompiledProfile, plan: *const ChildLandlockPlan) ApplyError!void {
    if (builtin.os.tag != .linux) return error.Unsupported;
    try applySelfLinux(compiled, plan);
}

/// Fork a child, apply Landlock, exit 0 on success / 1 on failure.
/// Parent builds the expand plan before fork (Z-3). Parent stays unrestricted.
pub fn verifyApplyInChild(compiled: *const profile.CompiledProfile) ApplyError!void {
    if (builtin.os.tag != .linux) return error.Unsupported;
    try verifyApplyInChildLinux(compiled);
}

// ── Linux implementation ───────────────────────────────────────────────────

const RulesetAttr = extern struct {
    handled_access_fs: u64,
};

const PathBeneathAttr = extern struct {
    allowed_access: u64,
    parent_fd: i32,
};

fn probeAbiLinux() ?AbiInfo {
    const linux = std.os.linux;
    const rc = linux.syscall3(.landlock_create_ruleset, 0, 0, CREATE_RULESET_VERSION);
    if (linux.errno(rc) != .SUCCESS) return null;
    // On success, return value is the ABI version (positive).
    if (rc > 0 and rc < 1024) {
        return .{ .version = @intCast(rc) };
    }
    return null;
}

/// True when `path` is `root` or a descendant of `root`.
/// Delegates to the portable profile helper so `/` and prefix-boundary rules match
/// profile/macos (M-5: bare `/` must cover control expand when workspace is `/`).
fn pathIsWithin(path: []const u8, root: []const u8) bool {
    return profile.isPathWithin(path, root);
}

/// True when any control root is under (or equal to) `path`.
fn grantCoversControlRoot(path: []const u8, control_roots: []const []const u8) bool {
    for (control_roots) |root| {
        if (pathIsWithin(root, path)) return true;
    }
    return false;
}

fn isControlPath(path: []const u8, control_roots: []const []const u8) bool {
    for (control_roots) |root| {
        if (pathIsWithin(path, root)) return true;
    }
    return false;
}

/// Pure: whether an RW grant should be expanded into children so control roots
/// are not covered by a single PATH_BENEATH RW rule (Landlock is allow-list only).
pub fn rwGrantNeedsControlExpand(path: []const u8, control_roots: []const []const u8) bool {
    return grantCoversControlRoot(path, control_roots);
}

fn addPathBeneathRule(
    ruleset_fd: i32,
    path: []const u8,
    allowed: u64,
    required: bool,
) ApplyError!bool {
    if (builtin.os.tag != .linux) return error.Unsupported;
    const linux = std.os.linux;
    if (allowed == 0) return false;
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    if (path.len == 0 or path.len >= path_buf.len) {
        if (required) return error.PathOpenFailed;
        return false;
    }
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;
    const path_z: [*:0]const u8 = path_buf[0..path.len :0].ptr;

    // O_NOFOLLOW: never PATH_BENEATH-follow a symlink to an outside target (M-3).
    const open_rc = linux.open(path_z, .{ .PATH = true, .CLOEXEC = true, .NOFOLLOW = true }, 0);
    if (linux.errno(open_rc) != .SUCCESS) {
        if (required) return error.PathOpenFailed;
        return false;
    }
    const path_fd: i32 = @intCast(open_rc);
    defer _ = linux.close(path_fd);

    var beneath = PathBeneathAttr{
        .allowed_access = allowed,
        .parent_fd = path_fd,
    };
    const add_rc = linux.syscall4(
        .landlock_add_rule,
        @as(usize, @intCast(ruleset_fd)),
        RULE_PATH_BENEATH,
        @intFromPtr(&beneath),
        0,
    );
    if (linux.errno(add_rc) != .SUCCESS) {
        if (required) return error.ApplyFailed;
        return false;
    }
    return true;
}

/// Install PATH_BENEATH rules from parent-precomputed expand surfaces.
/// Child-only: open + landlock_add_rule — **no** opendir/readdir (Z-3).
///
/// Semantics (unchanged from historical in-child expand):
/// - RO on expand roots (chdir/list/walk; no MAKE/WRITE)
/// - RO on control roots (readable, not writable)
/// - RW on leaf non-control children
///
/// Landlock cannot deny a subpath of a granted PATH_BENEATH, so we never install
/// a single RW (or MAKE) rule on a directory that contains a control root (M-1).
/// Returns true only when at least one usable RW child surface was installed.
fn addRwGrantFromSurfaces(
    ruleset_fd: i32,
    surfaces: *const ControlExpandSurfaces,
    abi: u32,
) ApplyError!bool {
    if (builtin.os.tag != .linux) return error.Unsupported;
    const ro = allowedAccessForMode(.ro, abi);
    const rw = allowedAccessForMode(.rw, abi);
    var any_rw = false;

    for (surfaces.expand_roots) |root| {
        // RO on expand roots so chdir/list/search works (M-1); WRITE/MAKE off (M-6).
        _ = try addPathBeneathRule(ruleset_fd, root, ro, true);
    }
    for (surfaces.control_ro_paths) |root| {
        _ = try addPathBeneathRule(ruleset_fd, root, ro, false);
    }
    for (surfaces.rw_paths) |path| {
        if (try addPathBeneathRule(ruleset_fd, path, rw, false)) {
            any_rw = true;
        }
    }
    return any_rw;
}

fn applySelfLinux(compiled: *const profile.CompiledProfile, plan: *const ChildLandlockPlan) ApplyError!void {
    const linux = std.os.linux;
    const abi_info = probeAbiLinux() orelse return error.Unavailable;
    const abi = abi_info.version;
    if (abi < MIN_ABI) return error.Unavailable;

    const handled = handledFsRights(abi);
    var attr = RulesetAttr{ .handled_access_fs = handled };

    const ruleset_rc = linux.syscall3(
        .landlock_create_ruleset,
        @intFromPtr(&attr),
        @sizeOf(RulesetAttr),
        0,
    );
    switch (linux.errno(ruleset_rc)) {
        .SUCCESS => {},
        .NOSYS, .OPNOTSUPP, .INVAL => return error.Unavailable,
        else => return error.ApplyFailed,
    }
    const ruleset_fd: i32 = @intCast(ruleset_rc);
    defer _ = linux.close(ruleset_fd);

    var workspace_granted = false;
    for (compiled.grants) |grant| {
        const allowed = allowedAccessForMode(grant.mode, abi);
        if (allowed == 0) continue;

        if (grant.mode == .rw and rwGrantNeedsControlExpand(grant.path, compiled.control_roots)) {
            // Parent must have precomputed surfaces; child never re-enumerates (Z-3).
            const surfaces = plan.surfacesFor(grant.path) orelse return error.ApplyFailed;
            if (try addRwGrantFromSurfaces(ruleset_fd, surfaces, abi)) {
                if (std.mem.eql(u8, grant.path, compiled.workspace_root) or
                    pathIsWithin(grant.path, compiled.workspace_root) or
                    pathIsWithin(compiled.workspace_root, grant.path))
                {
                    workspace_granted = true;
                }
            }
            continue;
        }

        const required = grant.mode == .rw;
        const installed = try addPathBeneathRule(ruleset_fd, grant.path, allowed, required);
        if (installed and grant.mode == .rw and std.mem.eql(u8, grant.path, compiled.workspace_root)) {
            workspace_granted = true;
        }
        // Explicit tmp RW or other RW under workspace also counts as a usable box.
        if (installed and grant.mode == .rw and pathIsWithin(grant.path, compiled.workspace_root)) {
            workspace_granted = true;
        }
    }

    if (!workspace_granted) {
        // No RW workspace rule installed — fail closed (empty box or missing root).
        return error.PathOpenFailed;
    }

    // NO_NEW_PRIVS is required before landlock_restrict_self.
    const pr_rc = linux.prctl(@intFromEnum(linux.PR.SET_NO_NEW_PRIVS), 1, 0, 0, 0);
    if (linux.errno(pr_rc) != .SUCCESS) return error.ApplyFailed;

    const restrict_rc = linux.syscall2(
        .landlock_restrict_self,
        @as(usize, @intCast(ruleset_fd)),
        0,
    );
    if (linux.errno(restrict_rc) != .SUCCESS) return error.ApplyFailed;
}

fn verifyApplyInChildLinux(compiled: *const profile.CompiledProfile) ApplyError!void {
    const linux = std.os.linux;

    // Parent-side expand plan before fork (Z-3). Child only installs from plan.
    var plan = buildChildLandlockPlan(std.heap.page_allocator, compiled) catch return error.ApplyFailed;
    defer plan.deinit();

    const pid_rc = linux.fork();
    if (linux.errno(pid_rc) != .SUCCESS) return error.ApplyFailed;

    if (pid_rc == 0) {
        // Child: apply then exit. Never return to parent address space logic.
        applySelfLinux(compiled, &plan) catch {
            linux.exit(1);
        };
        linux.exit(0);
    }

    // Parent: wait for child status.
    const child_pid: i32 = @intCast(pid_rc);
    var status: u32 = 0;
    while (true) {
        const w = linux.waitpid(child_pid, &status, 0);
        if (linux.errno(w) == .INTR) continue;
        if (linux.errno(w) != .SUCCESS) return error.ApplyFailed;
        break;
    }

    // Decode wait status: signalled if low 7 bits set; else exit code in bits 8..15.
    if ((status & 0x7f) != 0) return error.ApplyFailed;
    const code = (status >> 8) & 0xff;
    if (code != 0) return error.ApplyFailed;
}

// ── tests ──────────────────────────────────────────────────────────────────

test "pure ABI rights masks are filesystem-only and grow with ABI" {
    const a1 = handledFsRights(1);
    const a2 = handledFsRights(2);
    const a3 = handledFsRights(3);
    const a5 = handledFsRights(5);

    try std.testing.expectEqual(FS_RIGHTS_ABI1, a1);
    try std.testing.expect((a2 & ACCESS_FS_REFER) != 0);
    try std.testing.expect((a1 & ACCESS_FS_REFER) == 0);
    try std.testing.expect((a3 & ACCESS_FS_TRUNCATE) != 0);
    try std.testing.expect((a2 & ACCESS_FS_TRUNCATE) == 0);
    try std.testing.expect((a5 & ACCESS_FS_IOCTL_DEV) != 0);
}

test "pure allowedAccessForMode RO is subset of RW and of handled mask" {
    inline for (.{ @as(u32, 1), 2, 3, 5 }) |abi| {
        const handled = handledFsRights(abi);
        const ro = allowedAccessForMode(.ro, abi);
        const rw = allowedAccessForMode(.rw, abi);
        const ex = allowedAccessForMode(.exec, abi);
        try std.testing.expect((ro & handled) == ro);
        try std.testing.expect((rw & handled) == rw);
        try std.testing.expect((ex & handled) == ex);
        try std.testing.expect((ro & ACCESS_FS_WRITE_FILE) == 0);
        try std.testing.expect((rw & ACCESS_FS_WRITE_FILE) != 0);
        try std.testing.expect((ro & ACCESS_FS_READ_FILE) != 0);
        try std.testing.expect((ex & ACCESS_FS_EXECUTE) != 0);
    }
}

test "probeAbi is null on non-Linux; applySelf unsupported off Linux" {
    if (builtin.os.tag != .linux) {
        try std.testing.expect(probeAbi() == null);
        try std.testing.expect(!isAbiAvailable());
        var empty_plan: ChildLandlockPlan = .{
            .allocator = std.testing.allocator,
            .expands = try std.testing.allocator.alloc(ChildLandlockPlan.ExpandByGrant, 0),
        };
        defer empty_plan.deinit();
        try std.testing.expectError(error.Unsupported, applySelf(&.{
            .allocator = std.testing.allocator,
            .workspace_root = "/",
            .grants = &.{},
            .control_roots = &.{},
            .canonical_bytes = "",
            .hash_hex = .{'0'} ** 64,
        }, &empty_plan));
    }
}

// Z-3: parent-side expand helper builds child path lists from a temp dir layout.
test "buildControlExpandSurfaces enumerates RW children and skips control + symlinks" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var ws_tmp = std.testing.tmpDir(.{});
    defer ws_tmp.cleanup();
    try ws_tmp.dir.createDirPath(io, ".orca");
    try ws_tmp.dir.createDirPath(io, "src");
    try ws_tmp.dir.writeFile(io, .{ .sub_path = "neighbor.txt", .data = "ok" });
    try ws_tmp.dir.writeFile(io, .{ .sub_path = "src/main.zig", .data = "fn" });
    const ws_root = try ws_tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(ws_root);

    const control = try std.fs.path.join(allocator, &.{ ws_root, ".orca" });
    defer allocator.free(control);

    // Plant a symlink child that must not become an RW surface (M-3 parity).
    const link_path = try std.fs.path.join(allocator, &.{ ws_root, "escape_link" });
    defer allocator.free(link_path);
    std.Io.Dir.cwd().symLink(io, control, link_path, .{}) catch |err| switch (err) {
        error.PermissionDenied => {}, // still assert other surfaces
        else => return err,
    };

    var surfaces = try buildControlExpandSurfaces(allocator, ws_root, &[_][]const u8{control});
    defer surfaces.deinit();

    try std.testing.expect(surfaces.anyRw());
    try std.testing.expect(surfaces.expand_roots.len >= 1);
    try std.testing.expectEqualStrings(ws_root, surfaces.expand_roots[0]);

    // Control root is RO, not RW.
    var control_ro_found = false;
    for (surfaces.control_ro_paths) |p| {
        if (std.mem.eql(u8, p, control)) control_ro_found = true;
    }
    try std.testing.expect(control_ro_found);

    const neighbor = try std.fmt.allocPrint(allocator, "{s}/neighbor.txt", .{ws_root});
    defer allocator.free(neighbor);
    const src_dir = try std.fmt.allocPrint(allocator, "{s}/src", .{ws_root});
    defer allocator.free(src_dir);
    const link_joined = try std.fmt.allocPrint(allocator, "{s}/escape_link", .{ws_root});
    defer allocator.free(link_joined);
    const control_joined = try std.fmt.allocPrint(allocator, "{s}/.orca", .{ws_root});
    defer allocator.free(control_joined);

    var saw_neighbor = false;
    var saw_src = false;
    for (surfaces.rw_paths) |p| {
        if (std.mem.eql(u8, p, neighbor)) saw_neighbor = true;
        if (std.mem.eql(u8, p, src_dir)) saw_src = true;
        try std.testing.expect(!std.mem.eql(u8, p, control_joined));
        try std.testing.expect(!std.mem.eql(u8, p, link_joined));
    }
    try std.testing.expect(saw_neighbor);
    try std.testing.expect(saw_src);
}

test "buildControlExpandSurfaces recurses when child covers nested control root" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var ws_tmp = std.testing.tmpDir(.{});
    defer ws_tmp.cleanup();
    // Nested control: ws/pkg/.orca — pkg must be expand-root RO, not leaf RW.
    try ws_tmp.dir.createDirPath(io, "pkg/.orca");
    try ws_tmp.dir.writeFile(io, .{ .sub_path = "pkg/code.txt", .data = "c" });
    try ws_tmp.dir.writeFile(io, .{ .sub_path = "top.txt", .data = "t" });
    const ws_root = try ws_tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(ws_root);

    const nested_control = try std.fs.path.join(allocator, &.{ ws_root, "pkg", ".orca" });
    defer allocator.free(nested_control);

    var surfaces = try buildControlExpandSurfaces(allocator, ws_root, &[_][]const u8{nested_control});
    defer surfaces.deinit();

    const pkg = try std.fmt.allocPrint(allocator, "{s}/pkg", .{ws_root});
    defer allocator.free(pkg);
    const top = try std.fmt.allocPrint(allocator, "{s}/top.txt", .{ws_root});
    defer allocator.free(top);
    const code = try std.fmt.allocPrint(allocator, "{s}/pkg/code.txt", .{ws_root});
    defer allocator.free(code);

    // pkg is an expand root (covers control), not a leaf RW path.
    var pkg_is_expand = false;
    for (surfaces.expand_roots) |p| {
        if (std.mem.eql(u8, p, pkg)) pkg_is_expand = true;
    }
    try std.testing.expect(pkg_is_expand);

    var saw_top = false;
    var saw_code = false;
    for (surfaces.rw_paths) |p| {
        if (std.mem.eql(u8, p, top)) saw_top = true;
        if (std.mem.eql(u8, p, code)) saw_code = true;
        try std.testing.expect(!std.mem.eql(u8, p, pkg));
        try std.testing.expect(!std.mem.eql(u8, p, nested_control));
    }
    try std.testing.expect(saw_top);
    try std.testing.expect(saw_code);
}

test "verifyApplyInChild and applySelf skip or run on Linux only" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    if (probeAbi() == null) return error.SkipZigTest;

    // Real workspace under tmp so O_PATH succeeds. Need a non-control child so
    // control-root expand can install an RW PATH_BENEATH (M-1).
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "neighbor.txt", .data = "ok" });
    try tmp.dir.createDirPath(std.testing.io, ".orca");
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    // Production system RO defaults without temp trees (M-6). include_tmp stays
    // false so test tmpDirs under /tmp are not swallowed by the M-8 temp grant.
    var compiled = try profile.compileProfile(std.testing.allocator, .{
        .workspace_root = root,
        .system_ro_prefixes = profile.defaultSystemRoPrefixes(),
        .include_tmp = false,
    });
    defer compiled.deinit();

    try verifyApplyInChild(&compiled);
}

// M-18: empty workspace with only the default control root has no RW leaf until
// attach pre-creates `{workspace}/.orca-tmp`. Production apply/apply_posix do that
// before buildChildLandlockPlan; this test asserts the expand contract.
test "empty workspace only control root gains RW after session tmp precreate" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    if (probeAbi() == null) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, ".orca");
    // No neighbor files — only control root.
    const root = try tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(root);

    var compiled = try profile.compileProfile(allocator, .{
        .workspace_root = root,
        .system_ro_prefixes = profile.defaultSystemRoPrefixes(),
        .include_tmp = false,
    });
    defer compiled.deinit();

    {
        var empty_plan = try buildChildLandlockPlan(allocator, &compiled);
        defer empty_plan.deinit();
        const surfaces = empty_plan.surfacesFor(root) orelse return error.TestUnexpectedResult;
        try std.testing.expect(!surfaces.anyRw());
    }

    // Production attach precreate (apply.ensureWorkspaceSessionTmp / apply_posix).
    try tmp.dir.createDirPath(io, ".orca-tmp");

    var plan = try buildChildLandlockPlan(allocator, &compiled);
    defer plan.deinit();
    const surfaces = plan.surfacesFor(root) orelse return error.TestUnexpectedResult;
    try std.testing.expect(surfaces.anyRw());
    var saw_session_tmp = false;
    for (surfaces.rw_paths) |p| {
        if (std.mem.endsWith(u8, p, "/.orca-tmp") or std.mem.eql(u8, p, ".orca-tmp")) {
            saw_session_tmp = true;
        }
    }
    try std.testing.expect(saw_session_tmp);

    try verifyApplyInChild(&compiled);
}

test "rwGrantNeedsControlExpand when workspace contains control roots" {
    try std.testing.expect(rwGrantNeedsControlExpand("/ws", &[_][]const u8{"/ws/.orca"}));
    try std.testing.expect(rwGrantNeedsControlExpand("/ws", &[_][]const u8{"/ws"}));
    try std.testing.expect(!rwGrantNeedsControlExpand("/ws/src", &[_][]const u8{"/ws/.orca"}));
    try std.testing.expect(!rwGrantNeedsControlExpand("/tmp", &[_][]const u8{"/ws/.orca"}));
}

test "M-5 pathIsWithin and control expand treat filesystem root correctly" {
    // Without the `/` special-case, pathIsWithin("/etc", "/") is false and
    // rwGrantNeedsControlExpand("/", &.{"/.orca"}) skips expand → full RW on `/`.
    try std.testing.expect(pathIsWithin("/", "/"));
    try std.testing.expect(pathIsWithin("/etc", "/"));
    try std.testing.expect(pathIsWithin("/tmp/ws/.orca", "/"));
    try std.testing.expect(pathIsWithin("/.orca", "/"));
    try std.testing.expect(rwGrantNeedsControlExpand("/", &[_][]const u8{"/.orca"}));
    try std.testing.expect(rwGrantNeedsControlExpand("/", &[_][]const u8{"/tmp/.orca"}));
    try std.testing.expect(!pathIsWithin("relative", "/"));
}

// Real-FS deny / expand integration tests live in landlock_deny_tests.zig (M-8).
test {
    _ = @import("landlock_deny_tests.zig");
}
