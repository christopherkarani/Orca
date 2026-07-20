//! Single ApplyBeforeExec boundary for production agent launch (P0-A-03 / P1-PRE-03).
//!
//! Production path (U04):
//!   cli/run → applyBeforeExec → supervisor.run → process.prepareChild → std.process.spawn
//!
//! This module:
//! - compiles a pure FS profile (`profile.compileProfile`)
//! - scrubs loader/startup injection env (`env_scrub`)
//! - documents the child-side FD scrub call site (`fd_scrub`)
//! - attempts platform OS apply via a **stub** until U05 (Landlock) / U06 (Seatbelt)
//!
//! NEVER reports session `active` without a real backend attach (U05/U06).
//! Stubs return `unavailable` / `failed` only.
//!
//! ## FD scrub call site (child-side, not parent)
//! `fd_scrub.closeInheritedFdsDefault()` (or custom keep set) must run **after fork /
//! before exec**, or via posix_spawn file actions. The parent process must not call
//! default close — it would close Orca's own FDs. U04 documents the site; U05/U06
//! bind it when platform spawn supports pre-exec hooks.

const std = @import("std");
const posture = @import("posture.zig");
const profile = @import("profile.zig");
const env_scrub = @import("env_scrub.zig");
const fd_scrub = @import("fd_scrub.zig");
const launch_authority = @import("launch_authority.zig");

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
    /// Profile was compiled (owned hash lives only on receipt when active — never for stubs).
    profile_compiled: bool = false,
    /// Hex hash of compiled profile when compile succeeded (not attached; diagnostic).
    profile_hash_hex: ?[64]u8 = null,

    pub fn mayReportActive(self: ApplyResult) bool {
        return launch_authority.mayReportSessionActive(self.receipt);
    }
};

/// Platform apply outcome from Landlock/Seatbelt (stub until U05/U06).
const PlatformApplyStatus = enum {
    /// Real attach succeeded (not returned by stub).
    attached,
    /// Backend not present / not implemented for this build.
    unavailable,
    /// Backend present but apply failed.
    failed,
};

const PlatformApplyOutcome = struct {
    status: PlatformApplyStatus,
    mechanism: posture.BackendMechanism = .none,
    reason_code: []const u8,
};

/// Apply OS sandbox policy for the production launch path.
///
/// - `off` → disabled receipt; no profile/platform apply; no env scrub at this seam
/// - `on` / `auto` → compile profile, scrub env, attempt platform apply (stub → unavailable)
/// - `on` + unavailable/failed → `error.RequireFailed` (fail closed; caller must not spawn)
/// - `auto` + unavailable → unavailable receipt; caller may still spawn (interactive degrade)
///
/// Never returns a receipt with `posture == .active` from the stub path.
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
    // See module doc and `fd_scrub_call_site_is_child_only`.
    _ = fd_scrub.default_keep_fds;

    // Platform OS apply — stub returns unavailable (U05/U06 implement real attach).
    const platform = tryPlatformApplyStub(boundary.mode, &compiled);

    switch (platform.status) {
        .attached => {
            // Real backends only (U05/U06). Stub never reaches here.
            // Guard: still refuse active without mechanism + hash.
            const receipt = posture.activeReceipt(platform.mechanism, compiled.hash(), "workspace RW, system RO, no home");
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
        .unavailable => {
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

/// Stub platform apply. Real Landlock/Seatbelt land in U05/U06 and must never
/// claim attach from this function.
fn tryPlatformApplyStub(mode: OsSandboxMode, compiled: *const profile.CompiledProfile) PlatformApplyOutcome {
    _ = mode;
    _ = compiled;
    // Intentionally no Landlock/Seatbelt syscalls (U04).
    return .{
        .status = .unavailable,
        .mechanism = .none,
        .reason_code = "backend_not_implemented",
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

test "mode auto + stub backend returns unavailable and scrubs env (interactive degrade)" {
    var env_map = std.process.Environ.Map.init(std.testing.allocator);
    defer env_map.deinit();
    try env_map.put("LD_PRELOAD", "evil.so");
    try env_map.put("PATH", "/usr/bin");
    try env_map.put("ORCA_SESSION_ID", "s1");

    const result = try applyBeforeExec(.{
        .allocator = std.testing.allocator,
        .mode = .auto,
        .workspace_root = "/tmp/orca-apply-ws",
        .env_map = &env_map,
    });

    try std.testing.expectEqual(posture.SessionPosture.unavailable, result.receipt.posture);
    try std.testing.expect(!result.receipt.isActive());
    try std.testing.expect(!result.mayReportActive());
    try std.testing.expect(result.env_scrubbed);
    try std.testing.expect(result.profile_compiled);
    try std.testing.expect(result.profile_hash_hex != null);
    try std.testing.expect(env_map.get("LD_PRELOAD") == null);
    try std.testing.expectEqualStrings("/usr/bin", env_map.get("PATH").?);
    try std.testing.expectEqualStrings("s1", env_map.get("ORCA_SESSION_ID").?);
    try std.testing.expectEqualStrings("backend_not_implemented", result.receipt.reason_code.?);
}

test "mode on + stub backend fails closed with RequireFailed" {
    var env_map = std.process.Environ.Map.init(std.testing.allocator);
    defer env_map.deinit();
    try env_map.put("PATH", "/bin");

    const err = applyBeforeExec(.{
        .allocator = std.testing.allocator,
        .mode = .on,
        .workspace_root = "/tmp/orca-apply-ws",
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

test "stub path never yields active receipt or mayReportActive" {
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
    // Sanity: keep set is stdio only (0/1/2).
    try std.testing.expect(fd_scrub.isKeptFd(0, &fd_scrub.default_keep_fds));
    try std.testing.expect(fd_scrub.isKeptFd(1, &fd_scrub.default_keep_fds));
    try std.testing.expect(fd_scrub.isKeptFd(2, &fd_scrub.default_keep_fds));
    try std.testing.expect(fd_scrub.shouldCloseFd(3, &fd_scrub.default_keep_fds));
}

test "production apply seam is wired but stubs cannot satisfy active" {
    try std.testing.expect(launch_authority.production_apply_wired);
    const result = try applyBeforeExec(.{
        .allocator = std.testing.allocator,
        .mode = .auto,
        .workspace_root = "/workspace",
        .env_map = null,
    });
    try std.testing.expect(!launch_authority.mayReportSessionActive(result.receipt));
}
