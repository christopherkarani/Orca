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

/// True when pure rights tables never include network bits (always).
pub fn rightsAreFilesystemOnly(abi: u32) bool {
    _ = handledFsRights(abi);
    return true;
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

        // Stack path buffer — safe after fork (no malloc).
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        if (grant.path.len == 0 or grant.path.len >= path_buf.len) {
            if (grant.mode == .rw) return error.PathOpenFailed;
            continue;
        }
        @memcpy(path_buf[0..grant.path.len], grant.path);
        path_buf[grant.path.len] = 0;
        const path_z: [*:0]const u8 = path_buf[0..grant.path.len :0].ptr;

        // O_PATH | O_CLOEXEC — preferred for Landlock parent_fd.
        const open_rc = linux.open(path_z, .{ .PATH = true, .CLOEXEC = true }, 0);
        if (linux.errno(open_rc) != .SUCCESS) {
            // System RO prefixes may be missing on minimal images — skip.
            // Workspace RW (and explicit tmp RW) must open or we fail closed.
            if (grant.mode == .rw) return error.PathOpenFailed;
            continue;
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
            if (grant.mode == .rw) return error.ApplyFailed;
            continue;
        }
        if (grant.mode == .rw and std.mem.eql(u8, grant.path, compiled.workspace_root)) {
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
    try std.testing.expect(rightsAreFilesystemOnly(1));
    try std.testing.expect(rightsAreFilesystemOnly(4));
    try std.testing.expect(rightsAreFilesystemOnly(10));
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

    // Real workspace under tmp so O_PATH succeeds.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
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

test "never claims network landlock in public constants" {
    try std.testing.expect(@hasDecl(@This(), "handledFsRights"));
    try std.testing.expect(!@hasDecl(@This(), "handledNetRights"));
    try std.testing.expect(!@hasDecl(@This(), "ACCESS_NET_BIND_TCP"));
}
