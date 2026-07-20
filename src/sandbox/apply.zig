//! Single ApplyBeforeExec boundary for production agent launch (P0-A-03 / P1-PRE-03).
//!
//! Production path (U04–U07):
//!   cli/run → applyBeforeExec → supervisor.run → process.prepareChild
//!     → sandboxed spawn (apply_posix) or std.process.spawn
//!
//! `sandbox.backend.prepare` / PreparedSandbox is capability scaffolding and
//! unit-test surface only (M-15) — it must never alone authorize session `active`.
//! Production attach is exclusively applyBeforeExec + apply_posix child apply.
//!
//! This module:
//! - compiles a pure FS profile (`profile.compileProfile`)
//! - scrubs loader/startup injection env (`env_scrub`)
//! - attempts platform OS prepare: Landlock on Linux (U05); Seatbelt on macOS (U06)
//! - retains child-apply materials so U07 can box the *agent* process
//!
//! Landlock restrict_self and Seatbelt sandbox_init run only in a **forked child**
//! so the parent Orca process stays free. Production agent exec must use
//! `apply_posix.forkApplyLandlockAndExec` / `forkApplySeatbeltAndExec` (FD scrub
//! runs in that child before exec).
//!
//! Session `active` only via `receipt.isActive()` after real OS apply for the agent child.
//! NEVER claims network Landlock/Seatbelt.

const std = @import("std");
const builtin = @import("builtin");
const posture = @import("posture.zig");
const profile = @import("profile.zig");
const env_scrub = @import("env_scrub.zig");
const landlock = @import("landlock.zig");
const macos_seatbelt = @import("macos_seatbelt.zig");
const apply_posix = @import("apply_posix.zig");

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
        return self.receipt.isActive();
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

    /// Promote prepared results to active only after proven agent-child apply
    /// (status-pipe handshake in apply_posix). Never promote from fork or probe alone.
    pub fn promoteAfterChildSpawn(self: *ApplyResult) void {
        switch (self.childApplyKind()) {
            .none => {},
            .landlock => {
                if (self.profile_hash_hex) |hash| {
                    self.receipt = posture.activeReceipt(.landlock, hash[0..], "workspace RW, system RO, no home");
                }
            },
            .seatbelt => {
                if (self.profile_hash_hex) |hash| {
                    self.receipt = posture.activeReceipt(.seatbelt, hash[0..], "workspace RW, system RO, no home");
                }
            },
        }
    }

    /// Spawn the agent with OS FS apply in the child (Landlock / Seatbelt).
    /// Parent stays unrestricted. Blocks until status-pipe proves apply (M-2).
    /// Returns the child pid on success.
    pub fn spawnAgent(
        self: *const ApplyResult,
        io: std.Io,
        allocator: std.mem.Allocator,
        argv: []const []const u8,
        env_map: ?*const std.process.Environ.Map,
        workspace_root: []const u8,
        stdio: apply_posix.StdioBehavior,
    ) !i32 {
        if (argv.len == 0) return error.FileNotFound;
        const resolved = try apply_posix.resolveArgv0(io, allocator, argv[0]);
        defer if (resolved.owned) allocator.free(resolved.path);

        var argv_owned = try allocator.alloc([]const u8, argv.len);
        defer allocator.free(argv_owned);
        argv_owned[0] = resolved.path;
        @memcpy(argv_owned[1..], argv[1..]);

        const child = switch (self.childApplyKind()) {
            .none => return error.Unexpected,
            .landlock => blk: {
                const profile_ptr = &(self.landlock_profile orelse return error.Unexpected);
                break :blk try apply_posix.forkApplyLandlockAndExec(
                    profile_ptr,
                    argv_owned,
                    env_map,
                    workspace_root,
                    stdio,
                );
            },
            .seatbelt => blk: {
                const sbpl = self.seatbelt_sbpl_z orelse return error.Unexpected;
                break :blk try apply_posix.forkApplySeatbeltAndExec(
                    sbpl.ptr,
                    argv_owned,
                    env_map,
                    workspace_root,
                    stdio,
                );
            },
        };
        return child.pid;
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
    /// Profile prepared; agent child must apply before exec. Not active yet.
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
/// - `on` / `auto` + incomplete env scrub (OOM) → `error.RequireFailed` (fail closed; M-3)
/// - `on` + unavailable/failed (no child plan) → `error.RequireFailed` (fail closed)
/// - `on` + prepared child plan → returns materials; receipt stays non-active until promote
/// - `auto` + unavailable → unavailable receipt; caller may still spawn (interactive degrade)
/// - Session `active` only after agent-child apply handshake + `promoteAfterChildSpawn` (S-GLO-01)
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
    // Fail closed on incomplete scrub (OOM mid-scan): never launch with residual
    // LD_PRELOAD-class keys when mode is on/auto (M-3).
    var removed: usize = 0;
    var scrubbed = false;
    if (boundary.env_map) |env_map| {
        removed = env_scrub.scrubEnvMapInPlace(env_map) catch {
            setFailReason(boundary, "env_scrub_failed");
            // Both on and auto: incomplete denylist scrub is a hard security failure,
            // not a grade drop — residual injection keys must not reach the agent.
            return error.RequireFailed;
        };
        scrubbed = true;
    }

    // Platform OS apply — Linux Landlock child verify; macOS Seatbelt prepare.
    // FD scrub runs only in the forked agent child (`apply_posix`), never here.
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
            // Parent prepare only — not active until proven agent-child apply (U07 / status pipe).
            // Linux: transfer landlock profile. macOS: keep SBPL. Spawn path applies then promotes.
            if (platform.mechanism == .landlock) {
                transfer_landlock = true;
                return .{
                    .receipt = posture.unavailableReceipt(platform.reason_code),
                    .env_scrubbed = scrubbed,
                    .env_keys_removed = removed,
                    .profile_compiled = true,
                    .profile_hash_hex = hash_copy,
                    .landlock_profile = compiled,
                    .allocator = boundary.allocator,
                };
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

/// Platform apply: Linux → Landlock probe + prepared child plan; macOS → Seatbelt prepare.
/// Neither path returns session-active from the parent seam alone.
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

    // Capability preflight in a throwaway child. Parent is never restricted.
    // Success proves Landlock *can* apply — not that the agent child has applied.
    // Session active is deferred until agent-child status-pipe handshake + promote.
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
        .status = .prepared_child,
        .mechanism = .landlock,
        .reason_code = "landlock_child_apply_required",
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
    var result = applyBeforeExec(.{
        .allocator = std.testing.allocator,
        .mode = .on,
        .workspace_root = "/tmp/orca-apply-ws-nonexistent-u05",
        .env_map = &env_map,
        .fail_reason_out = &fail_reason,
    });
    // Linux without Landlock / path open → RequireFailed.
    // macOS matrix Seatbelt prepare succeeds (child apply still required; not active yet).
    if (result) |*ok| {
        defer ok.deinit();
        if (builtin.os.tag == .macos) {
            try std.testing.expect(ok.requiresChildApply());
            try std.testing.expectEqual(ChildApplyKind.seatbelt, ok.childApplyKind());
            try std.testing.expect(!ok.receipt.isActive());
        } else {
            // Parent seam never active: prepared child plan only if backend usable.
            try std.testing.expect(ok.requiresChildApply());
            try std.testing.expect(!ok.receipt.isActive());
        }
    } else |e| {
        try std.testing.expectEqual(error.RequireFailed, e);
        try std.testing.expect(!std.mem.eql(u8, fail_reason, "unset"));
        try std.testing.expect(!std.mem.eql(u8, fail_reason, "backend_not_implemented") or builtin.os.tag != .macos);
    }
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

test "mode on and auto fail closed when env scrub is incomplete" {
    // Absolute workspace so profile compile succeeds; inject OOM on env scrub only.
    const modes = [_]OsSandboxMode{ .on, .auto };
    for (modes) |mode| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = std.math.maxInt(usize) });
        const alloc = failing.allocator();

        var env_map = std.process.Environ.Map.init(alloc);
        defer env_map.deinit();
        try env_map.put("PATH", "/bin");
        try env_map.put("LD_PRELOAD", "evil.so");
        try env_map.put("LD_AUDIT", "evil_audit.so");

        // Allow profile compile allocations; trip on the first scrub key dupe.
        // Profile compile uses boundary.allocator (testing allocator), env map uses failing.
        // Scrub uses env_map.allocator → failing. Force fail before scrub starts collecting.
        failing.fail_index = failing.alloc_index;

        var fail_reason: []const u8 = "unset";
        const err = applyBeforeExec(.{
            .allocator = std.testing.allocator,
            .mode = mode,
            .workspace_root = "/tmp/orca-apply-ws-scrub-fail",
            .env_map = &env_map,
            .fail_reason_out = &fail_reason,
        });
        try std.testing.expectError(error.RequireFailed, err);
        try std.testing.expectEqualStrings("env_scrub_failed", fail_reason);
        try std.testing.expect(failing.has_induced_failure);
    }
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

test "parent apply seam never claims active (probe/prepare only)" {
    var result = try applyBeforeExec(.{
        .allocator = std.testing.allocator,
        .mode = .auto,
        .workspace_root = "/workspace",
        .env_map = null,
    });
    defer result.deinit();
    // S-GLO-01: applyBeforeExec must not authorize session active from probe alone.
    try std.testing.expect(!result.receipt.isActive());
    try std.testing.expect(!result.mayReportActive());
    try std.testing.expectEqual(result.receipt.isActive(), result.mayReportActive());
    if (result.requiresChildApply()) {
        try std.testing.expect(result.childApplyKind() == .landlock or result.childApplyKind() == .seatbelt);
    }
}

test "Linux Landlock prepares child plan without claiming active" {
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

    // Probe success → prepared plan, not session active.
    try std.testing.expect(!result.receipt.isActive());
    try std.testing.expect(!result.mayReportActive());
    try std.testing.expectEqual(ChildApplyKind.landlock, result.childApplyKind());
    try std.testing.expect(result.landlock_profile != null);
    try std.testing.expect(result.profile_hash_hex != null);
    try std.testing.expectEqualStrings("landlock_child_apply_required", result.receipt.reason_code.?);

    // Promote only after proven agent-child apply (status pipe / spawn path).
    result.promoteAfterChildSpawn();
    try std.testing.expect(result.receipt.isActive());
    try std.testing.expect(result.mayReportActive());
    try std.testing.expectEqual(posture.BackendMechanism.landlock, result.receipt.mechanism);
    // N1: hash still readable after promote (owned copy, not dangling).
    const hash_view = result.receipt.profileHashSlice().?;
    try std.testing.expectEqual(@as(usize, 64), hash_view.len);
    try std.testing.expectEqualStrings(result.profile_hash_hex.?[0..], hash_view);

    // mode on also prepares (not active) when Landlock works.
    var on_result = try applyBeforeExec(.{
        .allocator = std.testing.allocator,
        .mode = .on,
        .workspace_root = root,
        .env_map = null,
    });
    defer on_result.deinit();
    try std.testing.expect(!on_result.receipt.isActive());
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

test "promoteAfterChildSpawn activates landlock when profile prepared" {
    const hash: [64]u8 = .{'b'} ** 64;
    const compiled = try profile.compileProfile(std.testing.allocator, .{
        .workspace_root = "/tmp",
        .control_roots = &.{},
        .include_tmp = false,
    });
    var result: ApplyResult = .{
        .receipt = posture.unavailableReceipt("landlock_child_apply_required"),
        .profile_compiled = true,
        .profile_hash_hex = hash,
        .landlock_profile = compiled,
        .allocator = std.testing.allocator,
    };
    defer result.deinit();

    try std.testing.expectEqual(ChildApplyKind.landlock, result.childApplyKind());
    try std.testing.expect(!result.receipt.isActive());
    result.promoteAfterChildSpawn();
    try std.testing.expect(result.receipt.isActive());
    try std.testing.expectEqual(posture.BackendMechanism.landlock, result.receipt.mechanism);
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
        // Prepared child plan only — never session-active from the parent seam.
        try std.testing.expect(ok.requiresChildApply());
        try std.testing.expect(!ok.receipt.isActive());
    } else |e| {
        try std.testing.expectEqual(error.RequireFailed, e);
        try std.testing.expect(!std.mem.eql(u8, fail_reason, "unset"));
        // Real reason codes only — never the U04 backend_not_implemented placeholder on Darwin.
        if (builtin.os.tag == .macos) {
            try std.testing.expect(std.mem.indexOf(u8, fail_reason, "backend_not_implemented") == null);
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
