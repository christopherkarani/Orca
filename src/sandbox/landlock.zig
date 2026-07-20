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
fn pathIsWithin(path: []const u8, root: []const u8) bool {
    if (std.mem.eql(u8, path, root)) return true;
    if (root.len == 0 or path.len <= root.len) return false;
    if (!std.mem.startsWith(u8, path, root)) return false;
    return path[root.len] == '/';
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

    const open_rc = linux.open(path_z, .{ .PATH = true, .CLOEXEC = true }, 0);
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
/// - RO PATH_BENEATH on each control root under the grant (readable, not writable)
/// - RW PATH_BENEATH on each immediate child that is not a control path
///
/// Landlock cannot deny a subpath of a granted PATH_BENEATH, so we never install
/// a single RW rule on a directory that contains a control root (M-1 / P1-U-04).
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

    // RO on control roots under this grant (match Seatbelt: readable, not writable).
    for (control_roots) |root| {
        if (!pathIsWithin(root, grant_path)) continue;
        _ = try addPathBeneathRule(ruleset_fd, root, ro, false);
    }

    // If the grant path itself is a control root, do not grant RW at all.
    if (isControlPath(grant_path, control_roots)) {
        return false;
    }

    // Enumerate immediate children; grant RW only outside control trees.
    var dir = std.fs.openDirAbsolute(grant_path, .{ .iterate = true }) catch {
        // Missing dir on RW grant → fail closed.
        return error.PathOpenFailed;
    };
    defer dir.close();

    var it = dir.iterate();
    while (it.next() catch return error.PathOpenFailed) |entry| {
        // Join grant_path / name without allocating when possible.
        var child_buf: [std.fs.max_path_bytes]u8 = undefined;
        const joined = std.fmt.bufPrint(&child_buf, "{s}/{s}", .{ grant_path, entry.name }) catch {
            return error.PathOpenFailed;
        };
        if (isControlPath(joined, control_roots)) {
            // Already RO-granted above when control root matches; skip RW.
            continue;
        }
        if (grantCoversControlRoot(joined, control_roots)) {
            // Nested control under a child directory: expand that child further.
            if (try addRwGrantExcludingControls(ruleset_fd, joined, control_roots, abi)) {
                any_rw = true;
            }
            continue;
        }
        if (try addPathBeneathRule(ruleset_fd, joined, rw, true)) {
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
    try tmp.dir.makePath(std.testing.io, ".orca");
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var compiled = try profile.compileProfile(std.testing.allocator, .{
        .workspace_root = root,
        .system_ro_prefixes = &[_][]const u8{ "/usr", "/bin" },
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

test "real FS deny: outside denied; neighbor RW; control root not writable" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    if (probeAbi() == null) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const linux = std.os.linux;

    var ws_tmp = std.testing.tmpDir(.{});
    defer ws_tmp.cleanup();
    try ws_tmp.dir.makePath(io, ".orca");
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

    var compiled = try profile.compileProfile(allocator, .{
        .workspace_root = ws_root,
        .system_ro_prefixes = &[_][]const u8{ "/usr", "/bin", "/lib" },
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
        else => return error.UnexpectedSandboxProbeExit,
    }
}

test "never claims network landlock in public constants" {
    try std.testing.expect(@hasDecl(@This(), "handledFsRights"));
    try std.testing.expect(!@hasDecl(@This(), "handledNetRights"));
    try std.testing.expect(!@hasDecl(@This(), "ACCESS_NET_BIND_TCP"));
}
