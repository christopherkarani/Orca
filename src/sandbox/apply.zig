//! Single ApplyBeforeExec boundary for production agent launch (P0-A-03 / P1-PRE-03).
//!
//! Production path (U04/U05):
//!   cli/run → applyBeforeExec → supervisor.run → process.prepareChild → std.process.spawn
//!
//! This module:
//! - compiles a pure FS profile (`profile.compileProfile`)
//! - scrubs loader/startup injection env (`env_scrub`)
//! - documents the child-side FD scrub call site (`fd_scrub`)
//! - attempts platform OS apply: Landlock on Linux (U05); Seatbelt on macOS (U06)
//!
//! Landlock restrict_self runs only in a **forked child** (verify path) so the
//! parent Orca process stays free. Production agent exec should use
//! `apply_posix.forkApplyLandlockAndExec` so the agent inherits the same box.
//!
//! Session `active` only after real Landlock apply succeeds in the child.
//! NEVER claims network Landlock.

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
    /// Owned NUL-terminated SBPL for child-side Seatbelt apply (macOS). Free with deinit.
    seatbelt_sbpl_z: ?[:0]u8 = null,
    allocator: ?std.mem.Allocator = null,

    pub fn deinit(self: *ApplyResult) void {
        if (self.seatbelt_sbpl_z) |p| {
            if (self.allocator) |a| a.free(p);
            self.seatbelt_sbpl_z = null;
        }
        self.* = undefined;
    }

    pub fn mayReportActive(self: ApplyResult) bool {
        return launch_authority.mayReportSessionActive(self.receipt);
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

/// Apply OS sandbox policy for the production launch path.
///
/// - `off` → disabled receipt; no profile/platform apply; no env scrub at this seam
/// - `on` / `auto` → compile profile, scrub env, attempt platform apply
/// - `on` + unavailable/failed → `error.RequireFailed` (fail closed; caller must not spawn)
/// - `auto` + unavailable → unavailable receipt; caller may still spawn (interactive degrade)
/// - `active` only when Linux Landlock child apply succeeds (U05)
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
        if (boundary.mode == .on) return error.RequireFailed;
        return .{
            .receipt = posture.unavailableReceipt("profile_compile_failed"),
            .env_scrubbed = false,
            .profile_compiled = false,
        };
    };
    defer compiled.deinit();

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

    // Platform OS apply — Linux Landlock (U05); macOS Seatbelt prepare (U06).
    const platform = tryPlatformApply(boundary.allocator, boundary.mode, &compiled);

    switch (platform.status) {
        .attached => {
            // N1: activeReceipt copies hash into owned [64]u8 — no UAF after compiled.deinit.
            const receipt = posture.activeReceipt(platform.mechanism, hash_copy[0..], "workspace RW, system RO, no home");
            if (!receipt.isActive()) {
                if (boundary.mode == .on) return error.RequireFailed;
                return .{
                    .receipt = posture.failedReceipt("attach_incomplete"),
                    .env_scrubbed = scrubbed,
                    .env_keys_removed = removed,
                    .profile_compiled = true,
                    .profile_hash_hex = hash_copy,
                };
            }
            return .{
                .receipt = receipt,
                .env_scrubbed = scrubbed,
                .env_keys_removed = removed,
                .profile_compiled = true,
                .profile_hash_hex = hash_copy,
            };
        },
        .prepared_child => {
            // macOS parent prepare only — not active until child applyInChild (U07 spawn wire).
            if (boundary.mode == .on) {
                if (platform.seatbelt_sbpl_z) |p| boundary.allocator.free(p);
                return error.RequireFailed;
            }
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
}

test "mode auto without Landlock returns unavailable and scrubs env" {
    var env_map = std.process.Environ.Map.init(std.testing.allocator);
    defer env_map.deinit();
    try env_map.put("LD_PRELOAD", "evil.so");
    try env_map.put("PATH", "/usr/bin");
    try env_map.put("ORCA_SESSION_ID", "s1");

    // Use a path that may not exist — on Linux Landlock path open fails → failed/unavailable;
    // on macOS always unavailable. Scrub must still run.
    const result = try applyBeforeExec(.{
        .allocator = std.testing.allocator,
        .mode = .auto,
        .workspace_root = "/tmp/orca-apply-ws-nonexistent-u05",
        .env_map = &env_map,
    });

    try std.testing.expect(result.receipt.posture != .active);
    try std.testing.expect(!result.receipt.isActive());
    try std.testing.expect(!result.mayReportActive());
    try std.testing.expect(result.env_scrubbed);
    try std.testing.expect(result.profile_compiled);
    try std.testing.expect(result.profile_hash_hex != null);
    try std.testing.expect(env_map.get("LD_PRELOAD") == null);
    try std.testing.expectEqualStrings("/usr/bin", env_map.get("PATH").?);
    try std.testing.expectEqualStrings("s1", env_map.get("ORCA_SESSION_ID").?);
    // Non-Linux: backend_not_implemented; Linux without ABI: landlock_unavailable;
    // Linux with ABI but missing path: landlock_path_open_failed / landlock_apply_failed.
    try std.testing.expect(result.receipt.posture == .unavailable or result.receipt.posture == .failed);
}

test "mode on without usable Landlock fails closed with RequireFailed" {
    var env_map = std.process.Environ.Map.init(std.testing.allocator);
    defer env_map.deinit();
    try env_map.put("PATH", "/bin");

    const err = applyBeforeExec(.{
        .allocator = std.testing.allocator,
        .mode = .on,
        .workspace_root = "/tmp/orca-apply-ws-nonexistent-u05",
        .env_map = &env_map,
    });
    try std.testing.expectError(error.RequireFailed, err);
}

test "mode on + invalid workspace fails closed" {
    const err = applyBeforeExec(.{
        .allocator = std.testing.allocator,
        .mode = .on,
        .workspace_root = "relative-not-allowed",
        .env_map = null,
    });
    try std.testing.expectError(error.RequireFailed, err);
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

test "non-Linux never yields active receipt from apply seam" {
    if (builtin.os.tag == .linux) return error.SkipZigTest;

    const modes = [_]OsSandboxMode{ .off, .auto };
    for (modes) |mode| {
        const result = try applyBeforeExec(.{
            .allocator = std.testing.allocator,
            .mode = mode,
            .workspace_root = "/tmp/orca-apply-ws",
            .env_map = null,
        });
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
    const result = try applyBeforeExec(.{
        .allocator = std.testing.allocator,
        .mode = .auto,
        .workspace_root = "/workspace",
        .env_map = null,
    });
    // On macOS / Landlock-missing Linux: not active. On Linux with Landlock + real
    // workspace path open: may be failed (path) not active for fictional /workspace.
    if (result.receipt.isActive()) {
        try std.testing.expect(launch_authority.mayReportSessionActive(result.receipt));
        try std.testing.expectEqual(posture.BackendMechanism.landlock, result.receipt.mechanism);
        try std.testing.expect(result.receipt.profile_hash_hex != null);
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

    const result = try applyBeforeExec(.{
        .allocator = std.testing.allocator,
        .mode = .auto,
        .workspace_root = root,
        .env_map = null,
        .include_tmp = false,
    });

    try std.testing.expect(result.receipt.isActive());
    try std.testing.expect(result.mayReportActive());
    try std.testing.expectEqual(posture.BackendMechanism.landlock, result.receipt.mechanism);
    try std.testing.expect(result.receipt.profile_hash_hex != null);
    // N1: hash still readable after apply returns (owned copy, not dangling).
    const hash_view = result.receipt.profileHashSlice().?;
    try std.testing.expectEqual(@as(usize, 64), hash_view.len);
    try std.testing.expectEqualStrings(result.profile_hash_hex.?[0..], hash_view);

    // mode on also succeeds when Landlock works.
    const on_result = try applyBeforeExec(.{
        .allocator = std.testing.allocator,
        .mode = .on,
        .workspace_root = root,
        .env_map = null,
    });
    try std.testing.expect(on_result.receipt.isActive());
}

test "never claims network in active landlock fs_scope" {
    const complete = posture.activeReceipt(.landlock, "abcd", "workspace RW, system RO, no home");
    try std.testing.expect(std.mem.indexOf(u8, complete.fs_scope, "network") == null);
}
