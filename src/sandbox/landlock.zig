//! Linux Landlock FS apply (U05 / Slice 9).
//!
//! Sequence (child process only — never box the parent Orca CLI):
//!   ABI detect → rights mask → create ruleset → PATH_BENEATH grants
//!   → prctl(NO_NEW_PRIVS) → landlock_restrict_self → (caller execs)
//!
//! Network Landlock is **never** claimed here (Phase 2). Only filesystem
//! PATH_BENEATH rules from `CompiledProfile` grants.
//!
//! On non-Linux: compile-time stubs; probes return unavailable; apply errors.

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

/// Apply Landlock FS rules for `compiled` to the **current** process.
/// Must only be called in a forked child (or a dedicated sandbox helper).
/// Does not exec — caller performs exec after success.
pub fn applySelf(compiled: *const profile.CompiledProfile) ApplyError!void {
    if (builtin.os.tag != .linux) return error.Unsupported;
    try applySelfLinux(compiled);
}

/// Fork a child, apply Landlock, exit 0 on success / 1 on failure.
/// Parent stays unrestricted. Used for attach verification and tests.
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

/// Expand an RW grant that contains control roots into:
/// - RO PATH_BENEATH on the grant path itself (chdir/list/walk only — no MAKE/WRITE)
/// - RO PATH_BENEATH on each control root under the grant (readable, not writable)
/// - RW PATH_BENEATH on each immediate non-symlink child that is not a control path
///
/// Landlock cannot deny a subpath of a granted PATH_BENEATH, so we never install
/// a single RW (or MAKE) rule on a directory that contains a control root (M-1).
/// Create-at-grant-root is intentionally not granted: MAKE_* on the parent would
/// also allow creating under control roots. Seatbelt uses require-not; Landlock
/// approximates with child RW + root RO (F-2 parity residual: no create-at-root).
///
/// Returns true only when at least one usable RW child surface was installed.
/// Empty workspace (only control roots / symlinks) fails closed at applySelf.
fn addRwGrantExcludingControls(
    ruleset_fd: i32,
    grant_path: []const u8,
    control_roots: []const []const u8,
    abi: u32,
) ApplyError!bool {
    if (builtin.os.tag != .linux) return error.Unsupported;
    const ro = allowedAccessForMode(.ro, abi);
    const rw = allowedAccessForMode(.rw, abi);
    var any_rw = false;

    // RO on the grant root so chdir/list/search on workspace works (M-1).
    // WRITE/MAKE stay off the root — create-at-root is still denied (M-6).
    _ = try addPathBeneathRule(ruleset_fd, grant_path, ro, true);

    // RO on control roots under this grant (match Seatbelt: readable, not writable).
    for (control_roots) |root| {
        if (!pathIsWithin(root, grant_path)) continue;
        _ = try addPathBeneathRule(ruleset_fd, root, ro, false);
    }

    // If the grant path itself is a control root, do not grant RW at all.
    if (isControlPath(grant_path, control_roots)) {
        return false;
    }

    // Enumerate immediate children with libc opendir/readdir only (M-7).
    // applySelf runs post-fork in a multi-threaded parent (proxy may already be
    // live); Zig Io.Dir.iterate may allocate and is not async-signal-safe.
    // O_NOFOLLOW on grant open is handled by addPathBeneathRule for each child.
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    if (grant_path.len == 0 or grant_path.len >= path_buf.len) return error.PathOpenFailed;
    @memcpy(path_buf[0..grant_path.len], grant_path);
    path_buf[grant_path.len] = 0;
    const dir = std.c.opendir(path_buf[0..grant_path.len :0].ptr) orelse return error.PathOpenFailed;
    defer _ = std.c.closedir(dir);

    while (true) {
        // readdir: null means EOF (or rare error); best-effort fail-closed on open later.
        const entry = std.c.readdir(dir) orelse break;
        const name = std.mem.sliceTo(entry.name[0..], 0);
        if (name.len == 0 or std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;

        // Skip symlink children (DT_LNK). DT_UNKNOWN still goes through O_NOFOLLOW open.
        if (entry.type == std.c.DT.LNK) continue;

        var child_buf: [std.fs.max_path_bytes]u8 = undefined;
        const joined = std.fmt.bufPrint(&child_buf, "{s}/{s}", .{ grant_path, name }) catch {
            return error.PathOpenFailed;
        };
        if (isControlPath(joined, control_roots)) {
            continue;
        }
        if (grantCoversControlRoot(joined, control_roots)) {
            if (try addRwGrantExcludingControls(ruleset_fd, joined, control_roots, abi)) {
                any_rw = true;
            }
            continue;
        }
        if (try addPathBeneathRule(ruleset_fd, joined, rw, false)) {
            any_rw = true;
        }
    }

    return any_rw;
}

fn applySelfLinux(compiled: *const profile.CompiledProfile) ApplyError!void {
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
            // Split RW so control roots are never under a single PATH_BENEATH RW rule.
            if (try addRwGrantExcludingControls(ruleset_fd, grant.path, compiled.control_roots, abi)) {
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
    const pid_rc = linux.fork();
    if (linux.errno(pid_rc) != .SUCCESS) return error.ApplyFailed;

    if (pid_rc == 0) {
        // Child: apply then exit. Never return to parent address space logic.
        applySelfLinux(compiled) catch {
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
        try std.testing.expectError(error.Unsupported, applySelf(&.{
            .allocator = std.testing.allocator,
            .workspace_root = "/",
            .grants = &.{},
            .control_roots = &.{},
            .canonical_bytes = "",
            .hash_hex = .{'0'} ** 64,
        }));
    }
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

test "real FS deny: outside denied; neighbor RW; control root not writable" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    if (probeAbi() == null) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const linux = std.os.linux;

    var ws_tmp = std.testing.tmpDir(.{});
    defer ws_tmp.cleanup();
    try ws_tmp.dir.createDirPath(io, ".orca");
    try ws_tmp.dir.writeFile(io, .{ .sub_path = "neighbor.txt", .data = "WORKSPACE_NEIGHBOR_OK" });
    const ws_root = try ws_tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(ws_root);

    var out_tmp = std.testing.tmpDir(.{});
    defer out_tmp.cleanup();
    try out_tmp.dir.writeFile(io, .{ .sub_path = "canary.txt", .data = "OUTSIDE_SECRET" });
    const out_root = try out_tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(out_root);

    const canary_path = try std.fs.path.join(allocator, &.{ out_root, "canary.txt" });
    defer allocator.free(canary_path);
    const neighbor_path = try std.fs.path.join(allocator, &.{ ws_root, "neighbor.txt" });
    defer allocator.free(neighbor_path);
    const control_write = try std.fs.path.join(allocator, &.{ ws_root, ".orca", "policy.yaml" });
    defer allocator.free(control_write);

    // Production system RO defaults without temp RW (M-6; canaries live under tmpDir).
    var compiled = try profile.compileProfile(allocator, .{
        .workspace_root = ws_root,
        .system_ro_prefixes = profile.defaultSystemRoPrefixes(),
        .include_tmp = false,
    });
    defer compiled.deinit();
    try std.testing.expect(!compiled.isAgentWritable(canary_path));
    try std.testing.expect(compiled.isAgentWritable(neighbor_path));
    try std.testing.expect(!compiled.isAgentWritable(control_write));

    const pid_rc = linux.fork();
    if (linux.errno(pid_rc) != .SUCCESS) return error.SkipZigTest;
    if (pid_rc == 0) {
        applySelf(&compiled) catch linux.exit(2);

        // Outside canary must not be readable.
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        @memcpy(path_buf[0..canary_path.len], canary_path);
        path_buf[canary_path.len] = 0;
        const outside_fd = linux.open(path_buf[0..canary_path.len :0].ptr, .{ .CLOEXEC = true }, 0);
        if (linux.errno(outside_fd) == .SUCCESS) {
            _ = linux.close(@intCast(outside_fd));
            linux.exit(3);
        }

        // Neighbor readable.
        @memcpy(path_buf[0..neighbor_path.len], neighbor_path);
        path_buf[neighbor_path.len] = 0;
        const ws_fd = linux.open(path_buf[0..neighbor_path.len :0].ptr, .{ .CLOEXEC = true }, 0);
        if (linux.errno(ws_fd) != .SUCCESS) linux.exit(4);
        var buf: [64]u8 = undefined;
        const n = linux.read(@intCast(ws_fd), &buf, buf.len);
        _ = linux.close(@intCast(ws_fd));
        if (n != "WORKSPACE_NEIGHBOR_OK".len) linux.exit(4);

        // Neighbor write (PATH_BENEATH RW on the file).
        const wfd = linux.open(path_buf[0..neighbor_path.len :0].ptr, .{ .ACCMODE = .WRONLY, .CLOEXEC = true }, 0);
        if (linux.errno(wfd) != .SUCCESS) linux.exit(5);
        const wrote = linux.write(@intCast(wfd), "wrote!", 6);
        _ = linux.close(@intCast(wfd));
        if (wrote != 6) linux.exit(5);

        // Control root write must fail (M-1).
        @memcpy(path_buf[0..control_write.len], control_write);
        path_buf[control_write.len] = 0;
        const cfd = linux.open(
            path_buf[0..control_write.len :0].ptr,
            .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .CLOEXEC = true },
            0o600,
        );
        if (linux.errno(cfd) == .SUCCESS) {
            _ = linux.close(@intCast(cfd));
            linux.exit(6); // control write leak
        }

        // F-2: workspace root is listable (RO expand), but create-at-root is denied
        // (MAKE on parent would cover control trees).
        @memcpy(path_buf[0..ws_root.len], ws_root);
        path_buf[ws_root.len] = 0;
        const ws_dir_fd = linux.open(
            path_buf[0..ws_root.len :0].ptr,
            .{ .DIRECTORY = true, .CLOEXEC = true },
            0,
        );
        if (linux.errno(ws_dir_fd) != .SUCCESS) linux.exit(7);
        _ = linux.close(@intCast(ws_dir_fd));

        const suffix = "/new_at_root.txt";
        if (ws_root.len + suffix.len >= path_buf.len) linux.exit(8);
        @memcpy(path_buf[0..ws_root.len], ws_root);
        @memcpy(path_buf[ws_root.len..][0..suffix.len], suffix);
        const create_len = ws_root.len + suffix.len;
        path_buf[create_len] = 0;
        const new_fd = linux.open(
            path_buf[0..create_len :0].ptr,
            .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .CLOEXEC = true },
            0o600,
        );
        if (linux.errno(new_fd) == .SUCCESS) {
            _ = linux.close(@intCast(new_fd));
            linux.exit(8); // create-at-root should not gain MAKE on expanded parent
        }

        linux.exit(0);
    }

    const child_pid: i32 = @intCast(pid_rc);
    var status: u32 = 0;
    while (true) {
        const w = linux.waitpid(child_pid, &status, 0);
        if (linux.errno(w) == .INTR) continue;
        if (linux.errno(w) != .SUCCESS) return error.ApplyFailed;
        break;
    }
    if ((status & 0x7f) != 0) return error.ApplyFailed;
    const code = (status >> 8) & 0xff;
    switch (code) {
        0 => {},
        2 => return error.LandlockApplyFailedOnHost,
        3 => return error.OutsideCanaryReadableUnderSandbox,
        4 => return error.WorkspaceNeighborUnreadableUnderSandbox,
        5 => return error.WorkspaceWriteFailedUnderSandbox,
        6 => return error.ControlRootWritableUnderSandbox,
        7 => return error.WorkspaceRootUnlistableUnderExpand,
        8 => return error.CreateAtWorkspaceRootAllowedUnderExpand,
        else => return error.UnexpectedSandboxProbeExit,
    }
}

// M-1 / M-6: control expand installs RO on workspace root so chdir/list work,
// while MAKE/WRITE stay off the root. Create-at-workspace-root is therefore
// denied under Landlock (MAKE not on RO). Seatbelt may still allow create-at-root
// under full-subpath RW minus controls — intentional cross-platform semantic drift.
// Banner "workspace RW" remains honest when a child RW surface exists.
test "control expand: chdir workspace root works; create at root denied; control not writable" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    if (probeAbi() == null) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const linux = std.os.linux;

    var ws_tmp = std.testing.tmpDir(.{});
    defer ws_tmp.cleanup();
    try ws_tmp.dir.createDirPath(io, ".orca");
    try ws_tmp.dir.writeFile(io, .{ .sub_path = "neighbor.txt", .data = "NEIGHBOR" });
    const ws_root = try ws_tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(ws_root);

    const neighbor_path = try std.fs.path.join(allocator, &.{ ws_root, "neighbor.txt" });
    defer allocator.free(neighbor_path);
    const at_root_path = try std.fs.path.join(allocator, &.{ ws_root, "created_at_root.txt" });
    defer allocator.free(at_root_path);
    const control_write = try std.fs.path.join(allocator, &.{ ws_root, ".orca", "policy.yaml" });
    defer allocator.free(control_write);

    // Production system RO defaults without temp RW (M-6).
    var compiled = try profile.compileProfile(allocator, .{
        .workspace_root = ws_root,
        .system_ro_prefixes = profile.defaultSystemRoPrefixes(),
        .include_tmp = false,
    });
    defer compiled.deinit();

    const pid_rc = linux.fork();
    if (linux.errno(pid_rc) != .SUCCESS) return error.SkipZigTest;
    if (pid_rc == 0) {
        applySelf(&compiled) catch linux.exit(2);

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        @memcpy(path_buf[0..ws_root.len], ws_root);
        path_buf[ws_root.len] = 0;
        // Root RO must allow search/chdir into the workspace (M-1).
        if (linux.chdir(path_buf[0..ws_root.len :0].ptr) != 0) linux.exit(7);

        // Create-at-root denied: root is RO (MAKE not granted). M-6 honesty.
        @memcpy(path_buf[0..at_root_path.len], at_root_path);
        path_buf[at_root_path.len] = 0;
        const create_fd = linux.open(
            path_buf[0..at_root_path.len :0].ptr,
            .{ .ACCMODE = .WRONLY, .CREAT = true, .EXCL = true, .CLOEXEC = true },
            0o600,
        );
        if (linux.errno(create_fd) == .SUCCESS) {
            _ = linux.close(@intCast(create_fd));
            linux.exit(8); // create-at-root leak vs documented Landlock model
        }

        // Child RW surface still works.
        @memcpy(path_buf[0..neighbor_path.len], neighbor_path);
        path_buf[neighbor_path.len] = 0;
        const wfd = linux.open(path_buf[0..neighbor_path.len :0].ptr, .{ .ACCMODE = .WRONLY, .CLOEXEC = true }, 0);
        if (linux.errno(wfd) != .SUCCESS) linux.exit(5);
        const wrote = linux.write(@intCast(wfd), "ok", 2);
        _ = linux.close(@intCast(wfd));
        if (wrote != 2) linux.exit(5);

        // Control root still not writable.
        @memcpy(path_buf[0..control_write.len], control_write);
        path_buf[control_write.len] = 0;
        const cfd = linux.open(
            path_buf[0..control_write.len :0].ptr,
            .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .CLOEXEC = true },
            0o600,
        );
        if (linux.errno(cfd) == .SUCCESS) {
            _ = linux.close(@intCast(cfd));
            linux.exit(6);
        }

        linux.exit(0);
    }

    const child_pid: i32 = @intCast(pid_rc);
    var status: u32 = 0;
    while (true) {
        const w = linux.waitpid(child_pid, &status, 0);
        if (linux.errno(w) == .INTR) continue;
        if (linux.errno(w) != .SUCCESS) return error.ApplyFailed;
        break;
    }
    if ((status & 0x7f) != 0) return error.ApplyFailed;
    const code = (status >> 8) & 0xff;
    switch (code) {
        0 => {},
        2 => return error.LandlockApplyFailedOnHost,
        5 => return error.WorkspaceWriteFailedUnderSandbox,
        6 => return error.ControlRootWritableUnderSandbox,
        7 => return error.WorkspaceChdirFailedUnderSandbox,
        8 => return error.CreateAtWorkspaceRootUnexpectedlyAllowed,
        else => return error.UnexpectedSandboxProbeExit,
    }
}

// M-3: planted workspace symlink to an outside path must not become a PATH_BENEATH
// RW/RO grant on the outside target (O_NOFOLLOW + skip .sym_link during expand).
test "symlink to outside is not granted by control expand" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    if (probeAbi() == null) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const linux = std.os.linux;

    var ws_tmp = std.testing.tmpDir(.{});
    defer ws_tmp.cleanup();
    try ws_tmp.dir.createDirPath(io, ".orca");
    try ws_tmp.dir.writeFile(io, .{ .sub_path = "neighbor.txt", .data = "NEIGHBOR" });
    const ws_root = try ws_tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(ws_root);

    var out_tmp = std.testing.tmpDir(.{});
    defer out_tmp.cleanup();
    try out_tmp.dir.writeFile(io, .{ .sub_path = "secret.txt", .data = "OUTSIDE_SECRET" });
    const out_root = try out_tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(out_root);

    const secret_path = try std.fs.path.join(allocator, &.{ out_root, "secret.txt" });
    defer allocator.free(secret_path);
    const link_path = try std.fs.path.join(allocator, &.{ ws_root, "escape_link" });
    defer allocator.free(link_path);

    // Plant ws/escape_link → outside secret (or outside dir).
    std.Io.Dir.cwd().symLink(io, secret_path, link_path, .{}) catch |err| switch (err) {
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };

    const neighbor_path = try std.fs.path.join(allocator, &.{ ws_root, "neighbor.txt" });
    defer allocator.free(neighbor_path);

    // Production system RO defaults without temp RW (M-6).
    var compiled = try profile.compileProfile(allocator, .{
        .workspace_root = ws_root,
        .system_ro_prefixes = profile.defaultSystemRoPrefixes(),
        .include_tmp = false,
    });
    defer compiled.deinit();

    const pid_rc = linux.fork();
    if (linux.errno(pid_rc) != .SUCCESS) return error.SkipZigTest;
    if (pid_rc == 0) {
        applySelf(&compiled) catch linux.exit(2);

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;

        // Outside real path must not be readable under Landlock.
        @memcpy(path_buf[0..secret_path.len], secret_path);
        path_buf[secret_path.len] = 0;
        const out_fd = linux.open(path_buf[0..secret_path.len :0].ptr, .{ .CLOEXEC = true }, 0);
        if (linux.errno(out_fd) == .SUCCESS) {
            _ = linux.close(@intCast(out_fd));
            linux.exit(3);
        }

        // Via the workspace symlink: also must not grant outside target.
        @memcpy(path_buf[0..link_path.len], link_path);
        path_buf[link_path.len] = 0;
        const link_fd = linux.open(path_buf[0..link_path.len :0].ptr, .{ .CLOEXEC = true }, 0);
        if (linux.errno(link_fd) == .SUCCESS) {
            _ = linux.close(@intCast(link_fd));
            linux.exit(9); // symlink escape: outside readable via planted link
        }
        // Write via link must fail too.
        const link_w = linux.open(
            path_buf[0..link_path.len :0].ptr,
            .{ .ACCMODE = .WRONLY, .CLOEXEC = true },
            0,
        );
        if (linux.errno(link_w) == .SUCCESS) {
            _ = linux.close(@intCast(link_w));
            linux.exit(10);
        }

        // Usable child RW still present (neighbor).
        @memcpy(path_buf[0..neighbor_path.len], neighbor_path);
        path_buf[neighbor_path.len] = 0;
        const nfd = linux.open(path_buf[0..neighbor_path.len :0].ptr, .{ .CLOEXEC = true }, 0);
        if (linux.errno(nfd) != .SUCCESS) linux.exit(4);
        _ = linux.close(@intCast(nfd));

        linux.exit(0);
    }

    const child_pid: i32 = @intCast(pid_rc);
    var status: u32 = 0;
    while (true) {
        const w = linux.waitpid(child_pid, &status, 0);
        if (linux.errno(w) == .INTR) continue;
        if (linux.errno(w) != .SUCCESS) return error.ApplyFailed;
        break;
    }
    if ((status & 0x7f) != 0) return error.ApplyFailed;
    const code = (status >> 8) & 0xff;
    switch (code) {
        0 => {},
        2 => return error.LandlockApplyFailedOnHost,
        3 => return error.OutsideCanaryReadableUnderSandbox,
        4 => return error.WorkspaceNeighborUnreadableUnderSandbox,
        9 => return error.SymlinkEscapeReadableUnderSandbox,
        10 => return error.SymlinkEscapeWritableUnderSandbox,
        else => return error.UnexpectedSandboxProbeExit,
    }
}

test "never claims network landlock in public constants" {
    try std.testing.expect(@hasDecl(@This(), "handledFsRights"));
    try std.testing.expect(!@hasDecl(@This(), "handledNetRights"));
    try std.testing.expect(!@hasDecl(@This(), "ACCESS_NET_BIND_TCP"));
}
