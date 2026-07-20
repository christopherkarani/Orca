//! Single ApplyBeforeExec boundary for production agent launch (P0-A-03 / P1-PRE-03).
//!
//! Production path (U04–U07):
//!   cli/run → applyBeforeExec → supervisor.run → process.prepareChild
//!     → sandboxed spawn (apply_posix) or std.process.spawn
//!
//! This module:
//! - compiles a pure FS profile (`profile.compileProfile`)
//! - scrubs loader/startup injection env (`env_scrub`)
//! - documents the child-side FD scrub call site (`fd_scrub`)
//! - attempts platform OS prepare: Landlock on Linux (U05); Seatbelt on macOS (U06)
//! - retains child-apply materials so U07 can box the *agent* process
//!
//! Landlock restrict_self and Seatbelt sandbox_init run only in a **forked child**
//! so the parent Orca process stays free. Production agent exec must use
//! `apply_posix.forkApplyLandlockAndExec` / `forkApplySeatbeltAndExec`.
//!
//! Session `active` only after real OS apply is wired for the agent child.
//! NEVER claims network Landlock/Seatbelt.

const std = @import("std");
const builtin = @import("builtin");
const posture = @import("posture.zig");
const profile = @import("profile.zig");
const env_scrub = @import("env_scrub.zig");
const fd_scrub = @import("fd_scrub.zig");
const launch_authority = @import("launch_authority.zig");
const landlock = @import("landlock.zig");
const apply_posix = @import("apply_posix.zig");
const macos_seatbelt = @import("macos_seatbelt.zig");

/// Re-export mode for callers that only touch apply.
pub const OsSandboxMode = posture.OsSandboxMode;
pub const AttachReceipt = posture.AttachReceipt;

/// Error when mode is `on` (required) and OS apply cannot attach.
pub const ApplyError = error{
    /// `--os-sandbox on` but backend unavailable / apply failed / profile invalid.
    RequireFailed,
    OutOfMemory,
};

/// What the agent spawn path must do after `applyBeforeExec` (U07).
pub const ChildApplyKind = enum {
    none,
    landlock,
    seatbelt,
};

/// Inputs for the single apply-before-exec seam.
pub const ApplyBoundary = struct {
    allocator: std.mem.Allocator,
    mode: OsSandboxMode,
    /// Absolute workspace root (fail closed if relative when mode is on/auto).
    workspace_root: []const u8,
    /// Child env map mutated in place when scrub runs (on/auto).
    env_map: ?*std.process.Environ.Map = null,
    /// Extra profile options.
    include_tmp: bool = false,
    control_roots: []const []const u8 = &.{},
    /// When `error.RequireFailed` is returned, set to a static reason code if non-null.
    fail_reason_out: ?*[]const u8 = null,
};

pub const ApplyResult = struct {
    receipt: AttachReceipt,
    /// True when env_scrub ran against env_map.
    env_scrubbed: bool = false,
    /// Count of keys removed by env scrub (0 if not scrubbed).
    env_keys_removed: usize = 0,
    /// Profile was compiled.
    profile_compiled: bool = false,
    /// Owned hex hash of compiled profile when compile succeeded.
    profile_hash_hex: ?[64]u8 = null,
    /// Owned compiled profile for Linux Landlock agent-child apply (U07). Free with deinit.
    landlock_profile: ?profile.CompiledProfile = null,
    /// Owned NUL-terminated SBPL for child-side Seatbelt apply (macOS). Free with deinit.
    seatbelt_sbpl_z: ?[:0]u8 = null,
    allocator: ?std.mem.Allocator = null,

    pub fn deinit(self: *ApplyResult) void {
        if (self.landlock_profile) |*p| {
            p.deinit();
            self.landlock_profile = null;
        }
        if (self.seatbelt_sbpl_z) |p| {
            if (self.allocator) |a| a.free(p);
            self.seatbelt_sbpl_z = null;
        }
        self.* = undefined;
    }

    pub fn mayReportActive(self: ApplyResult) bool {
        return launch_authority.mayReportSessionActive(self.receipt);
    }

    /// Kind of child-side OS apply the spawn path must perform.
    pub fn childApplyKind(self: ApplyResult) ChildApplyKind {
        if (self.landlock_profile != null) return .landlock;
        if (self.seatbelt_sbpl_z != null) return .seatbelt;
        return .none;
    }

    /// True when spawn must use apply_posix (agent would otherwise be unboxed).
    pub fn requiresChildApply(self: ApplyResult) bool {
        return self.childApplyKind() != .none;
    }

    /// Promote Seatbelt-prepared results to active after the agent child applied SBPL.
    /// Landlock results are already active after verify (agent still landlocked via plan).
    pub fn promoteAfterChildSpawn(self: *ApplyResult) void {
        switch (self.childApplyKind()) {
            .none, .landlock => {},
            .seatbelt => {
                if (self.profile_hash_hex) |hash| {
                    self.receipt = posture.activeReceipt(.seatbelt, hash[0..], "workspace RW, system RO, no home");
                }
            },
        }
    }
};

/// Platform apply outcome from Landlock/Seatbelt.
const PlatformApplyStatus = enum {
    /// Real attach succeeded (child Landlock apply verified).
    attached,
    /// Backend not present / not implemented for this build.
    unavailable,
    /// Backend present but apply failed.
    failed,
    /// Profile prepared; child must apply before exec (macOS Seatbelt). Not active yet.
    prepared_child,
};

const PlatformApplyOutcome = struct {
    status: PlatformApplyStatus,
    mechanism: posture.BackendMechanism = .none,
    reason_code: []const u8,
    seatbelt_sbpl_z: ?[:0]u8 = null,
};

fn setFailReason(boundary: ApplyBoundary, reason: []const u8) void {
    if (boundary.fail_reason_out) |out| out.* = reason;
}

/// Apply OS sandbox policy for the production launch path.
///
/// - `off` → disabled receipt; no profile/platform apply; no env scrub at this seam
/// - `on` / `auto` → compile profile, scrub env, attempt platform apply
/// - `on` + unavailable/failed (no child plan) → `error.RequireFailed` (fail closed)
/// - `on` + prepared Seatbelt → returns with `seatbelt_sbpl_z` (child must apply; U07)
/// - `auto` + unavailable → unavailable receipt; caller may still spawn (interactive degrade)
/// - `active` when Linux Landlock child verify succeeds (U05); Seatbelt active after child spawn (U07)
pub fn applyBeforeExec(boundary: ApplyBoundary) ApplyError!ApplyResult {
    switch (boundary.mode) {
        .off => return .{
            .receipt = posture.disabledReceipt(),
            .env_scrubbed = false,
            .env_keys_removed = 0,
            .profile_compiled = false,
        },
        .on, .auto => {},
    }

    // Compile pure profile (grants model only — no syscalls).
    var compiled = profile.compileProfile(boundary.allocator, .{
        .workspace_root = boundary.workspace_root,
        .control_roots = boundary.control_roots,
        .include_tmp = boundary.include_tmp,
    }) catch {
        // Invalid workspace / OOM on compile: fail closed when required.
        setFailReason(boundary, "profile_compile_failed");
        if (boundary.mode == .on) return error.RequireFailed;
        return .{
            .receipt = posture.unavailableReceipt("profile_compile_failed"),
            .env_scrubbed = false,
            .profile_compiled = false,
        };
    };
    var transfer_landlock = false;
    defer if (!transfer_landlock) compiled.deinit();

    var hash_copy: [64]u8 = undefined;
    @memcpy(hash_copy[0..], compiled.hash());

    // Scrub loader/startup injection vectors on child env (in place).
    var removed: usize = 0;
    var scrubbed = false;
    if (boundary.env_map) |env_map| {
        removed = env_scrub.scrubEnvMapInPlace(env_map);
        scrubbed = true;
    }

    // Document FD scrub intent for child-side (do not run in parent).
    _ = fd_scrub.default_keep_fds;
    _ = apply_posix.verifyLandlockApplyInChild;

    // Platform OS apply — Linux Landlock child verify; macOS Seatbelt prepare.
    const platform = tryPlatformApply(boundary.allocator, boundary.mode, &compiled);

    switch (platform.status) {
        .attached => {
            // N1: activeReceipt copies hash into owned [64]u8 — no UAF after compiled.deinit.
            const receipt = posture.activeReceipt(platform.mechanism, hash_copy[0..], "workspace RW, system RO, no home");
            if (!receipt.isActive()) {
                setFailReason(boundary, "attach_incomplete");
                if (boundary.mode == .on) return error.RequireFailed;
                return .{
                    .receipt = posture.failedReceipt("attach_incomplete"),
                    .env_scrubbed = scrubbed,
                    .env_keys_removed = removed,
                    .profile_compiled = true,
                    .profile_hash_hex = hash_copy,
                };
            }
            // Transfer compiled profile so agent spawn can landlock the real child (U07).
            transfer_landlock = true;
            return .{
                .receipt = receipt,
                .env_scrubbed = scrubbed,
                .env_keys_removed = removed,
                .profile_compiled = true,
                .profile_hash_hex = hash_copy,
                .landlock_profile = compiled,
                .allocator = boundary.allocator,
            };
        },
        .prepared_child => {
            // macOS parent prepare only — not active until child applyInChild (U07).
            // Keep SBPL for both on and auto; spawn path applies then promotes.
            return .{
                .receipt = posture.unavailableReceipt(platform.reason_code),
                .env_scrubbed = scrubbed,
                .env_keys_removed = removed,
                .profile_compiled = true,
                .profile_hash_hex = hash_copy,
                .seatbelt_sbpl_z = platform.seatbelt_sbpl_z,
                .allocator = boundary.allocator,
            };
        },
        .unavailable => {
            if (platform.seatbelt_sbpl_z) |p| boundary.allocator.free(p);
            setFailReason(boundary, platform.reason_code);
            if (boundary.mode == .on) return error.RequireFailed;
            return .{
                .receipt = posture.unavailableReceipt(platform.reason_code),
                .env_scrubbed = scrubbed,
                .env_keys_removed = removed,
                .profile_compiled = true,
                .profile_hash_hex = hash_copy,
            };
        },
        .failed => {
            if (platform.seatbelt_sbpl_z) |p| boundary.allocator.free(p);
            setFailReason(boundary, platform.reason_code);
            if (boundary.mode == .on) return error.RequireFailed;
            return .{
                .receipt = posture.failedReceipt(platform.reason_code),
                .env_scrubbed = scrubbed,
                .env_keys_removed = removed,
                .profile_compiled = true,
                .profile_hash_hex = hash_copy,
            };
        },
    }
}

/// Compile-time / doc marker: FD scrub is child-only.
pub const fd_scrub_call_site_is_child_only = true;

/// Platform apply: Linux → Landlock child verify; macOS → Seatbelt prepare (child apply U07).
fn tryPlatformApply(
    allocator: std.mem.Allocator,
    mode: OsSandboxMode,
    compiled: *const profile.CompiledProfile,
) PlatformApplyOutcome {
    _ = mode;
    return switch (builtin.os.tag) {
        .linux => tryPlatformApplyLinux(compiled),
        .macos => tryMacOsSeatbelt(allocator, compiled),
        else => .{
            .status = .unavailable,
            .mechanism = .none,
            .reason_code = "backend_not_implemented",
        },
    };
}

fn tryMacOsSeatbelt(
    allocator: std.mem.Allocator,
    compiled: *const profile.CompiledProfile,
) PlatformApplyOutcome {
    const prepared = macos_seatbelt.prepareForChildApply(allocator, compiled);
    return switch (prepared.status) {
        .unavailable => .{
            .status = .unavailable,
            .mechanism = .none,
            .reason_code = prepared.reason_code,
            .seatbelt_sbpl_z = null,
        },
        .failed => .{
            .status = .failed,
            .mechanism = .none,
            .reason_code = prepared.reason_code,
            .seatbelt_sbpl_z = null,
        },
        .prepared => .{
            .status = .prepared_child,
            .mechanism = .seatbelt,
            .reason_code = "seatbelt_child_apply_required",
            .seatbelt_sbpl_z = prepared.sbpl_z,
        },
    };
}

fn tryPlatformApplyLinux(compiled: *const profile.CompiledProfile) PlatformApplyOutcome {
    if (!landlock.isAbiAvailable()) {
        return .{
            .status = .unavailable,
            .mechanism = .none,
            .reason_code = "landlock_unavailable",
        };
    }

    // Real apply in a forked child so the parent Orca process is never restricted.
    landlock.verifyApplyInChild(compiled) catch |err| {
        return switch (err) {
            error.Unavailable, error.Unsupported => .{
                .status = .unavailable,
                .mechanism = .none,
                .reason_code = "landlock_unavailable",
            },
            error.PathOpenFailed => .{
                .status = .failed,
                .mechanism = .none,
                .reason_code = "landlock_path_open_failed",
            },
            error.ApplyFailed => .{
                .status = .failed,
                .mechanism = .none,
                .reason_code = "landlock_apply_failed",
            },
        };
    };

    return .{
        .status = .attached,
        .mechanism = .landlock,
        .reason_code = "landlock_attached",
    };
}

// ── tests ──────────────────────────────────────────────────────────────────

test "mode off returns disabled receipt without scrub or active claim" {
    var env_map = std.process.Environ.Map.init(std.testing.allocator);
    defer env_map.deinit();
    try env_map.put("LD_PRELOAD", "evil.so");
    try env_map.put("PATH", "/bin");

    const result = try applyBeforeExec(.{
        .allocator = std.testing.allocator,
        .mode = .off,
        .workspace_root = "/tmp/ws",
        .env_map = &env_map,
    });

    try std.testing.expectEqual(posture.SessionPosture.disabled, result.receipt.posture);
    try std.testing.expect(!result.receipt.isActive());
    try std.testing.expect(!result.mayReportActive());
    try std.testing.expect(!result.env_scrubbed);
    try std.testing.expect(!result.profile_compiled);
    // Off path does not scrub at this seam (policy env filter still applies upstream).
    try std.testing.expect(env_map.get("LD_PRELOAD") != null);
    try std.testing.expectEqualStrings("os_sandbox_off", result.receipt.reason_code.?);
    try std.testing.expectEqual(ChildApplyKind.none, result.childApplyKind());
}

test "mode auto without Landlock returns unavailable and scrubs env" {
    var env_map = std.process.Environ.Map.init(std.testing.allocator);
    defer env_map.deinit();
    try env_map.put("LD_PRELOAD", "evil.so");
    try env_map.put("PATH", "/usr/bin");
    try env_map.put("ORCA_SESSION_ID", "s1");

    // Use a path that may not exist — on Linux Landlock path open fails → failed/unavailable;
    // on macOS always unavailable (or prepared on matrix hosts). Scrub must still run.
    var result = try applyBeforeExec(.{
        .allocator = std.testing.allocator,
        .mode = .auto,
        .workspace_root = "/tmp/orca-apply-ws-nonexistent-u05",
        .env_map = &env_map,
    });
    defer result.deinit();

    try std.testing.expect(result.receipt.posture != .active);
    try std.testing.expect(!result.receipt.isActive());
    try std.testing.expect(!result.mayReportActive());
    try std.testing.expect(result.env_scrubbed);
    try std.testing.expect(result.profile_compiled);
    try std.testing.expect(result.profile_hash_hex != null);
    try std.testing.expect(env_map.get("LD_PRELOAD") == null);
    try std.testing.expectEqualStrings("/usr/bin", env_map.get("PATH").?);
    try std.testing.expectEqualStrings("s1", env_map.get("ORCA_SESSION_ID").?);
    // Non-Linux: backend_not_implemented / macos_version_unsupported / prepared;
    // Linux without ABI: landlock_unavailable;
    // Linux with ABI but missing path: landlock_path_open_failed / landlock_apply_failed.
    try std.testing.expect(result.receipt.posture == .unavailable or result.receipt.posture == .failed);
}

test "mode on without usable Landlock fails closed with RequireFailed" {
    var env_map = std.process.Environ.Map.init(std.testing.allocator);
    defer env_map.deinit();
    try env_map.put("PATH", "/bin");

    var fail_reason: []const u8 = "unset";
    const err = applyBeforeExec(.{
        .allocator = std.testing.allocator,
        .mode = .on,
        .workspace_root = "/tmp/orca-apply-ws-nonexistent-u05",
        .env_map = &env_map,
        .fail_reason_out = &fail_reason,
    });
    try std.testing.expectError(error.RequireFailed, err);
    try std.testing.expect(!std.mem.eql(u8, fail_reason, "unset"));
    try std.testing.expect(!std.mem.eql(u8, fail_reason, "backend_not_implemented") or builtin.os.tag != .macos);
}

test "mode on + invalid workspace fails closed" {
    var fail_reason: []const u8 = "unset";
    const err = applyBeforeExec(.{
        .allocator = std.testing.allocator,
        .mode = .on,
        .workspace_root = "relative-not-allowed",
        .env_map = null,
        .fail_reason_out = &fail_reason,
    });
    try std.testing.expectError(error.RequireFailed, err);
    try std.testing.expectEqualStrings("profile_compile_failed", fail_reason);
}

test "mode auto + invalid workspace degrades to unavailable" {
    const result = try applyBeforeExec(.{
        .allocator = std.testing.allocator,
        .mode = .auto,
        .workspace_root = "",
        .env_map = null,
    });
    try std.testing.expectEqual(posture.SessionPosture.unavailable, result.receipt.posture);
    try std.testing.expect(!result.receipt.isActive());
    try std.testing.expectEqualStrings("profile_compile_failed", result.receipt.reason_code.?);
}

test "non-Linux never yields active receipt from apply seam without child spawn" {
    if (builtin.os.tag == .linux) return error.SkipZigTest;

    const modes = [_]OsSandboxMode{ .off, .auto };
    for (modes) |mode| {
        var result = try applyBeforeExec(.{
            .allocator = std.testing.allocator,
            .mode = mode,
            .workspace_root = "/tmp/orca-apply-ws",
            .env_map = null,
        });
        defer result.deinit();
        try std.testing.expect(result.receipt.posture != .active);
        try std.testing.expect(!result.receipt.isActive());
        try std.testing.expect(!result.mayReportActive());
        try std.testing.expect(!result.receipt.posture.isOsEnforced());
    }
}

test "fd scrub call site is documented as child-only" {
    try std.testing.expect(fd_scrub_call_site_is_child_only);
    try std.testing.expect(fd_scrub.isKeptFd(0, &fd_scrub.default_keep_fds));
    try std.testing.expect(fd_scrub.isKeptFd(1, &fd_scrub.default_keep_fds));
    try std.testing.expect(fd_scrub.isKeptFd(2, &fd_scrub.default_keep_fds));
    try std.testing.expect(fd_scrub.shouldCloseFd(3, &fd_scrub.default_keep_fds));
}

test "production apply seam is wired; active only with complete receipt" {
    try std.testing.expect(launch_authority.production_apply_wired);
    var result = try applyBeforeExec(.{
        .allocator = std.testing.allocator,
        .mode = .auto,
        .workspace_root = "/workspace",
        .env_map = null,
    });
    defer result.deinit();
    // On macOS / Landlock-missing Linux: not active. On Linux with Landlock + real
    // workspace path open: may be failed (path) not active for fictional /workspace.
    if (result.receipt.isActive()) {
        try std.testing.expect(launch_authority.mayReportSessionActive(result.receipt));
        try std.testing.expectEqual(posture.BackendMechanism.landlock, result.receipt.mechanism);
        try std.testing.expect(result.receipt.profile_hash_hex != null);
        try std.testing.expectEqual(ChildApplyKind.landlock, result.childApplyKind());
    } else {
        try std.testing.expect(!launch_authority.mayReportSessionActive(result.receipt));
    }
}

test "Linux Landlock can attach active when workspace exists" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    if (!landlock.isAbiAvailable()) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var result = try applyBeforeExec(.{
        .allocator = std.testing.allocator,
        .mode = .auto,
        .workspace_root = root,
        .env_map = null,
        .include_tmp = false,
    });
    defer result.deinit();

    try std.testing.expect(result.receipt.isActive());
    try std.testing.expect(result.mayReportActive());
    try std.testing.expectEqual(posture.BackendMechanism.landlock, result.receipt.mechanism);
    try std.testing.expect(result.receipt.profile_hash_hex != null);
    try std.testing.expectEqual(ChildApplyKind.landlock, result.childApplyKind());
    try std.testing.expect(result.landlock_profile != null);
    // N1: hash still readable after apply returns (owned copy, not dangling).
    const hash_view = result.receipt.profileHashSlice().?;
    try std.testing.expectEqual(@as(usize, 64), hash_view.len);
    try std.testing.expectEqualStrings(result.profile_hash_hex.?[0..], hash_view);

    // mode on also succeeds when Landlock works.
    var on_result = try applyBeforeExec(.{
        .allocator = std.testing.allocator,
        .mode = .on,
        .workspace_root = root,
        .env_map = null,
    });
    defer on_result.deinit();
    try std.testing.expect(on_result.receipt.isActive());
    try std.testing.expectEqual(ChildApplyKind.landlock, on_result.childApplyKind());
}

test "never claims network in active landlock fs_scope" {
    const complete = posture.activeReceipt(.landlock, "abcd", "workspace RW, system RO, no home");
    try std.testing.expect(std.mem.indexOf(u8, complete.fs_scope, "network") == null);
}

test "promoteAfterChildSpawn activates seatbelt when SBPL prepared" {
    const hash: [64]u8 = .{'a'} ** 64;
    var result: ApplyResult = .{
        .receipt = posture.unavailableReceipt("seatbelt_child_apply_required"),
        .profile_compiled = true,
        .profile_hash_hex = hash,
        .seatbelt_sbpl_z = null, // no owned string — kind uses null unless set
        .allocator = std.testing.allocator,
    };
    // Manually mark as seatbelt plan via a non-null empty-owned placeholder.
    result.seatbelt_sbpl_z = try std.testing.allocator.dupeZ(u8, "(version 1)\n");
    defer result.deinit();

    try std.testing.expectEqual(ChildApplyKind.seatbelt, result.childApplyKind());
    try std.testing.expect(!result.receipt.isActive());
    result.promoteAfterChildSpawn();
    try std.testing.expect(result.receipt.isActive());
    try std.testing.expectEqual(posture.BackendMechanism.seatbelt, result.receipt.mechanism);
    try std.testing.expect(std.mem.indexOf(u8, result.receipt.fs_scope, "network") == null);
}

test "mode on surfaces real reason_code via fail_reason_out on this host" {
    var fail_reason: []const u8 = "unset";
    var result = applyBeforeExec(.{
        .allocator = std.testing.allocator,
        .mode = .on,
        .workspace_root = "/tmp/orca-apply-ws-u07-reason",
        .env_map = null,
        .fail_reason_out = &fail_reason,
    });
    // On hosts without a usable backend, RequireFailed with a real reason (not placeholder).
    if (result) |*ok| {
        defer ok.deinit();
        // Linux Landlock with openable path, or macOS matrix Seatbelt prepare, may succeed.
        try std.testing.expect(ok.receipt.isActive() or ok.requiresChildApply());
    } else |e| {
        try std.testing.expectEqual(error.RequireFailed, e);
        try std.testing.expect(!std.mem.eql(u8, fail_reason, "unset"));
        if (builtin.os.tag == .macos) {
            // macOS outside matrix (e.g. 26) must surface version gate, not U04 placeholder.
            try std.testing.expectEqualStrings("macos_version_unsupported", fail_reason);
        }
    }
}

test "session banner helper remains mechanism-neutral for apply receipts" {
    var buf: [256]u8 = undefined;
    const active = posture.activeReceipt(.seatbelt, "deadbeef", "workspace RW, system RO, no home");
    const line = try posture.formatSessionBanner(&buf, active);
    try std.testing.expect(std.mem.indexOf(u8, line, "OS sandbox: active") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "Seatbelt") == null);
    try std.testing.expect(std.mem.indexOf(u8, line, "Landlock") == null);
}
