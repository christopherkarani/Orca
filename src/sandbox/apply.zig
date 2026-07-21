//! Single ApplyBeforeExec boundary for production agent launch.
//!
//! Production path:
//!   cli/run → applyBeforeExec → supervisor.run → process.prepareChild
//!     → sandboxed spawn (apply_posix) or std.process.spawn
//!
//! Scaffold `backend.prepare` was removed. Production attach is exclusively
//! applyBeforeExec + apply_posix child apply; capability detect stays in backend.
//!
//! This module:
//! - compiles a pure FS profile (`profile.compileProfile`)
//! - scrubs loader/startup injection env (`env_scrub`)
//! - attempts platform OS prepare: Landlock on Linux; Seatbelt on macOS
//! - retains child-apply materials (`ChildMaterials` union) so spawn can box the *agent* process
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
const session_tmp = @import("session_tmp.zig");

/// Re-export session-tmp surface for callers that only import apply.
pub const workspace_session_tmp_name = session_tmp.workspace_session_tmp_name;
pub const classic_tmp_fallback = session_tmp.classic_tmp_fallback;
pub const workspaceSessionTmpPath = session_tmp.workspaceSessionTmpPath;
pub const ensureWorkspaceSessionTmp = session_tmp.ensureWorkspaceSessionTmp;

/// Re-export mode for callers that only touch apply.
pub const OsSandboxMode = posture.OsSandboxMode;
pub const AttachReceipt = posture.AttachReceipt;

/// Error when mode is `on` (required) and OS apply cannot attach.
pub const ApplyError = error{
    /// `--os-sandbox on` but backend unavailable / apply failed / profile invalid.
    RequireFailed,
    OutOfMemory,
};

/// Named public error set for `ApplyResult.spawnAgent`.
/// Prefer this over an inferred set that surfaces bare `Unexpected`.
/// Invariant failures (no child materials, missing SBPL/profile, proof mint fail)
/// map to `ApplyFailed` so CLI spawn classifiers stay honest.
pub const SpawnAgentError = apply_posix.SpawnError;

/// What the agent spawn path must do after `applyBeforeExec`.
/// Tag matches `ChildMaterials` so kind is derived from materials.
pub const ChildApplyKind = enum {
    none,
    landlock,
    seatbelt,
};

/// Owned child-apply materials for agent spawn.
/// Invalid both-set states are unrepresentable: at most one backend payload.
pub const ChildMaterials = union(enum) {
    none,
    landlock: profile.CompiledProfile,
    seatbelt: struct {
        sbpl_z: [:0]u8,
        allocator: std.mem.Allocator,
        /// Precomputed at prepare from `CompiledProfile.effectiveFsScopeSummary(.seatbelt)`.
        /// Static string (not heap-owned). Used on activate so receipts cannot drift
        /// from a second hardcoded source of truth.
        fs_scope: []const u8,
    },

    pub fn deinit(self: *ChildMaterials) void {
        switch (self.*) {
            .none => {},
            .landlock => |*p| p.deinit(),
            .seatbelt => |*s| s.allocator.free(s.sbpl_z),
        }
        self.* = .none;
    }

    pub fn kind(self: ChildMaterials) ChildApplyKind {
        return switch (self) {
            .none => .none,
            .landlock => .landlock,
            .seatbelt => .seatbelt,
        };
    }
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
    /// True when denylist env scrub ran against env_map.
    env_scrubbed: bool = false,
    /// True when launch allowlist ran (only with child-apply materials).
    env_launch_allowlisted: bool = false,
    /// Count of keys removed by denylist + optional launch allowlist (0 if none).
    env_keys_removed: usize = 0,
    /// Profile was compiled.
    profile_compiled: bool = false,
    /// By-value 64-hex digest of the compiled profile when compile succeeded (not heap-owned).
    profile_hash_hex: ?[64]u8 = null,
    /// Owned child-apply materials. Free with deinit. Default `.none`.
    materials: ChildMaterials = .none,
    /// Retained fork buffers for the last successful sandboxed spawn.
    /// Freed in `deinit` after the supervisor has waited/reaped the child.
    spawn_lease: ?apply_posix.SpawnLease = null,

    pub fn deinit(self: *ApplyResult) void {
        if (self.spawn_lease) |*lease| {
            // Production path waits/reaps via PreparedChild before deinit.
            // Multi-spawn and error paths must killAndReap before free; deinit
            // does not kill (pid may already be reaped — SIGKILL would race reuse).
            lease.deinit();
            self.spawn_lease = null;
        }
        self.materials.deinit();
        self.* = undefined;
    }

    /// Kind of child-side OS apply the spawn path must perform (derived from materials tag).
    pub fn childApplyKind(self: ApplyResult) ChildApplyKind {
        return self.materials.kind();
    }

    /// True when spawn must use apply_posix (agent would otherwise be unboxed).
    pub fn requiresChildApply(self: ApplyResult) bool {
        return self.childApplyKind() != .none;
    }

    /// Proof that agent-child OS FS apply handshake succeeded.
    /// Only `activateAfterHandshake` (via `spawnAgent`) constructs this after a real
    /// fork status-pipe success. No cross-module mint — magic seal dropped (same-module).
    pub const ChildAttachProof = struct {
        mechanism: posture.BackendMechanism,

        pub fn isValid(self: ChildAttachProof) bool {
            return self.mechanism != .none;
        }
    };

    /// Result of a successful sandboxed agent spawn (pid + attach proof).
    pub const SpawnedAgent = struct {
        pid: i32,
        proof: ChildAttachProof,
    };

    /// Build active receipt from materials after proven child handshake.
    /// File-private: only `spawnAgent` calls this. Bare materials alone never
    /// authorize active (S-GLO-01). Hard-fails on missing materials/hash or
    /// activeReceipt construction failure — never soft-skips.
    fn activateAfterHandshake(self: *ApplyResult) error{ApplyFailed}!ChildAttachProof {
        const hash = self.profile_hash_hex orelse return error.ApplyFailed;
        switch (self.materials) {
            .none => return error.ApplyFailed,
            .landlock => |*p| {
                const scope = p.effectiveFsScopeSummary(.landlock);
                self.receipt = posture.activeReceipt(.landlock, hash[0..], scope) catch return error.ApplyFailed;
                return .{ .mechanism = .landlock };
            },
            .seatbelt => |*s| {
                // Scope was precomputed at prepare from the compiled profile (single source).
                const scope = s.fs_scope;
                self.receipt = posture.activeReceipt(.seatbelt, hash[0..], scope) catch return error.ApplyFailed;
                return .{ .mechanism = .seatbelt };
            },
        }
    }

    /// Spawn the agent with OS FS apply in the child (Landlock / Seatbelt).
    /// Parent stays unrestricted. Blocks until status-pipe proves apply.
    /// On success, mutates this result to active via `activateAfterHandshake`.
    /// After a successful child handshake, activate failure kills/reaps the child
    /// and returns `ApplyFailed` — never a live agent without an active receipt.
    /// Errors: `SpawnAgentError` (named; invariants → `ApplyFailed`, never bare `Unexpected`).
    pub fn spawnAgent(
        self: *ApplyResult,
        io: std.Io,
        allocator: std.mem.Allocator,
        argv: []const []const u8,
        env_map: ?*const std.process.Environ.Map,
        workspace_root: []const u8,
        stdio: apply_posix.StdioBehavior,
    ) SpawnAgentError!SpawnedAgent {
        // Match apply_posix empty-argv contract (ExecFailed, not FileNotFound).
        if (argv.len == 0) return error.ExecFailed;
        const resolved = try apply_posix.resolveArgv0(io, allocator, argv[0], env_map);
        defer if (resolved.owned) allocator.free(resolved.path);

        var argv_owned = try allocator.alloc([]const u8, argv.len);
        defer allocator.free(argv_owned);
        argv_owned[0] = resolved.path;
        @memcpy(argv_owned[1..], argv[1..]);

        // Drop any prior lease: kill+reap first. Freeing retained argv/env while
        // the prior child still runs is free-before-reap (fork COW UAF). One-shot
        // run never hits this; multi-spawn / retry paths must not free live buffers.
        if (self.spawn_lease) |*old| {
            if (old.pid > 0) apply_posix.killAndReapChild(old.pid);
            old.deinit();
            self.spawn_lease = null;
        }

        // Single switch on materials tag — invalid dual-backend state unrepresentable.
        var lease = switch (self.materials) {
            .none => return error.ApplyFailed,
            .landlock => |*profile_ptr| try apply_posix.forkApplyLandlockAndExec(
                profile_ptr,
                argv_owned,
                env_map,
                workspace_root,
                stdio,
            ),
            .seatbelt => |*sb| try apply_posix.forkApplySeatbeltAndExec(
                sb.sbpl_z.ptr,
                argv_owned,
                env_map,
                workspace_root,
                stdio,
            ),
        };

        // Handshake proven: activate receipt from materials. Hard-fail after fork —
        // kill/reap so we never return a live agent without an active session receipt.
        const proof = self.activateAfterHandshake() catch {
            apply_posix.killAndReapChild(lease.pid);
            lease.deinit();
            return error.ApplyFailed;
        };
        const pid = lease.pid;
        self.spawn_lease = lease;
        return .{ .pid = pid, .proof = proof };
    }
};

/// Platform prepare outcome from Landlock/Seatbelt (parent seam only).
/// Parent seam never returns a live-session attach: only prepared_child materials
/// (or unavailable/failed). Session `active` requires child status-pipe + activate.
const PlatformApplyStatus = enum {
    /// Backend not present / not implemented for this build.
    unavailable,
    /// Backend present but prepare failed.
    failed,
    /// Profile prepared; agent child must apply before exec. Not active yet.
    prepared_child,
};

const PlatformApplyOutcome = struct {
    status: PlatformApplyStatus,
    mechanism: posture.BackendMechanism = .none,
    reason_code: []const u8,
    /// Owned NUL-terminated SBPL when Seatbelt prepare succeeded. Free via `deinit`
    /// unless transferred with `takeSeatbeltSbpl`.
    seatbelt_sbpl_z: ?[:0]u8 = null,
    /// Allocator that owns `seatbelt_sbpl_z` when non-null.
    sbpl_allocator: ?std.mem.Allocator = null,

    pub fn deinit(self: *PlatformApplyOutcome) void {
        if (self.seatbelt_sbpl_z) |p| {
            if (self.sbpl_allocator) |a| a.free(p);
            self.seatbelt_sbpl_z = null;
            self.sbpl_allocator = null;
        }
    }

    /// Transfer SBPL ownership to the caller; `deinit` will not free it.
    pub fn takeSeatbeltSbpl(self: *PlatformApplyOutcome) ?[:0]u8 {
        const p = self.seatbelt_sbpl_z;
        self.seatbelt_sbpl_z = null;
        self.sbpl_allocator = null;
        return p;
    }
};

fn setFailReason(boundary: ApplyBoundary, reason: []const u8) void {
    if (boundary.fail_reason_out) |out| out.* = reason;
}

/// Pure: true when `path` is a macOS per-user `/var/folders/...` temp (not granted).
/// File-private — only used by attach rewrite tests in this module.
fn isUngrantedHostTmpdir(path: []const u8) bool {
    if (path.len == 0) return false;
    // macOS default TMPDIR shape: /var/folders/… or /private/var/folders/…
    if (std.mem.startsWith(u8, path, "/var/folders/")) return true;
    if (std.mem.startsWith(u8, path, "/private/var/folders/")) return true;
    return false;
}

/// Rewrite TMPDIR/TMP/TEMP into a granted tree for the attach path.
///
/// Host macOS TMPDIR under `/var/folders` is intentionally not granted (canary breadth).
/// Prefer `{workspace}/.orca-tmp` (workspace RW; mkdir so Landlock expand sees it).
/// Fall back to classic `/tmp` (production temp RW grant).
///
/// Mutates `env_map` in place. Returns the path written into TMPDIR (map-owned value).
pub fn rewriteTempEnvForAttach(
    allocator: std.mem.Allocator,
    env_map: *std.process.Environ.Map,
    workspace_root: []const u8,
) ![]const u8 {
    const preferred = try workspaceSessionTmpPath(allocator, workspace_root);
    defer allocator.free(preferred);

    // Create session surface first (shared with Landlock expand precreate).
    const use_path: []const u8 = if (ensureWorkspaceSessionTmp(workspace_root)) preferred else classic_tmp_fallback;

    // Map put duplicates via map allocator — preferred stack path is free'd after.
    try env_map.put("TMPDIR", use_path);
    try env_map.put("TMP", use_path);
    try env_map.put("TEMP", use_path);
    return env_map.get("TMPDIR") orelse classic_tmp_fallback;
}

/// Apply OS sandbox policy for the production launch path.
///
/// - `off` → disabled receipt; no profile/platform apply; no env scrub at this seam
/// - `on` / `auto` → compile profile, denylist-scrub env, attempt platform apply
/// - `on` / `auto` + incomplete denylist scrub (OOM) → `error.RequireFailed` (fail closed; reason env_scrub_failed)
/// - allowlist / TMPDIR rewrite OOM → `error.OutOfMemory` (hard; not RequireFailed)
/// - launch allowlist runs only when prepare yields child-apply materials
/// - attach path rewrites TMPDIR/TMP/TEMP into a granted tree
/// - `on` + unavailable/failed (no child plan) → `error.RequireFailed` (fail closed)
/// - `on` + prepared child plan → returns materials; receipt stays non-active until promote
/// - `auto` + unavailable → unavailable receipt; denylist only (provider keys retained)
/// - Session `active` only after agent-child apply handshake + `activateAfterHandshake` (S-GLO-01)
pub fn applyBeforeExec(boundary: ApplyBoundary) ApplyError!ApplyResult {
    switch (boundary.mode) {
        .off => return .{
            .receipt = posture.disabledReceipt(),
            .env_scrubbed = false,
            .env_launch_allowlisted = false,
            .env_keys_removed = 0,
            .profile_compiled = false,
        },
        .on, .auto => {},
    }

    // Compile pure profile (grants model only — no syscalls).
    // OOM is never a soft grade-drop: propagate so callers fail closed hard.
    // InvalidWorkspace / other compile failures → profile_compile_failed (on→RequireFailed, auto→unavailable).
    var compiled = profile.compileProfile(boundary.allocator, .{
        .workspace_root = boundary.workspace_root,
        .control_roots = boundary.control_roots,
        .include_tmp = boundary.include_tmp,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            setFailReason(boundary, "profile_compile_failed");
            if (boundary.mode == .on) return error.RequireFailed;
            return .{
                .receipt = posture.unavailableReceipt("profile_compile_failed"),
                .env_scrubbed = false,
                .env_launch_allowlisted = false,
                .profile_compiled = false,
            };
        },
    };
    var transfer_landlock = false;
    defer if (!transfer_landlock) compiled.deinit();

    // F-1: reject symlink/non-dir control roots before platform prepare (path alias).
    var control_io_rt: std.Io.Threaded = .init_single_threaded;
    const control_io = control_io_rt.io();
    compiled.validateControlRootsOnDisk(control_io) catch {
        setFailReason(boundary, "control_root_unsafe");
        if (boundary.mode == .on) return error.RequireFailed;
        return .{
            .receipt = posture.unavailableReceipt("control_root_unsafe"),
            .env_scrubbed = false,
            .env_launch_allowlisted = false,
            .profile_compiled = true,
            .profile_hash_hex = blk: {
                var h: [64]u8 = undefined;
                @memcpy(h[0..], compiled.hash());
                break :blk h;
            },
        };
    };

    var hash_copy: [64]u8 = undefined;
    @memcpy(hash_copy[0..], compiled.hash());

    // Denylist scrub always on on/auto (injection fail-closed). Launch allowlist is
    // deferred until after prepare so pure grade-drop does not strip provider keys.
    var removed: usize = 0;
    var scrubbed = false;
    if (boundary.env_map) |env_map| {
        removed = env_scrub.scrubEnvMapInPlace(env_map) catch {
            setFailReason(boundary, "env_scrub_failed");
            return error.RequireFailed;
        };
        scrubbed = true;
    }

    // Platform OS prepare — Linux Landlock ABI probe; macOS Seatbelt prepare.
    // FD scrub / real attach run only in the forked agent child (`apply_posix`), never here.
    // OOM on Seatbelt prepare propagates as `error.OutOfMemory` (never soft .failed).
    var platform = try tryPlatformApply(boundary.allocator, &compiled);
    defer platform.deinit();

    // Launch allowlist only when child-apply materials will be used (prepared_child).
    // Unavailable/failed grade-drop keeps denylist-only env (provider credentials retained).
    // Attach path also rewrites TMPDIR into a granted tree (R2-2) — host /var/folders is not granted.
    var allowlisted = false;
    if (platform.status == .prepared_child) {
        // Create `{workspace}/.orca-tmp` before Landlock expand enumerates children,
        // even when env_map is null (rewriteTempEnvForAttach also ensures, when env is present).
        _ = ensureWorkspaceSessionTmp(boundary.workspace_root);
        if (boundary.env_map) |env_map| {
            // Allowlist/TMPDIR OOM must stay OutOfMemory (not lossy RequireFailed).
            const allow_removed = env_scrub.applyLaunchAllowlistInPlace(env_map) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
            };
            removed += allow_removed;
            allowlisted = true;
            // After allowlist keeps TMPDIR key, point it at a granted path.
            // rewriteTempEnvForAttach only fails with OutOfMemory (alloc / map put).
            _ = rewriteTempEnvForAttach(boundary.allocator, env_map, boundary.workspace_root) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
            };
        }
    }

    switch (platform.status) {
        .prepared_child => {
            // Parent prepare only — not active until proven agent-child apply (status pipe).
            // Posture is `prepared`, not grade-drop `unavailable`.
            // Linux: transfer landlock profile. macOS: keep SBPL. Spawn path applies then activates.
            if (platform.mechanism == .landlock) {
                transfer_landlock = true;
                return .{
                    .receipt = posture.preparedReceipt(.landlock, platform.reason_code),
                    .env_scrubbed = scrubbed,
                    .env_launch_allowlisted = allowlisted,
                    .env_keys_removed = removed,
                    .profile_compiled = true,
                    .profile_hash_hex = hash_copy,
                    .materials = .{ .landlock = compiled },
                };
            }
            const sbpl_z = platform.takeSeatbeltSbpl() orelse {
                // prepared_child + seatbelt without SBPL is a contract bug — fail closed.
                setFailReason(boundary, "seatbelt_sbpl_missing");
                if (boundary.mode == .on) return error.RequireFailed;
                return .{
                    .receipt = posture.failedReceipt("seatbelt_sbpl_missing"),
                    .env_scrubbed = scrubbed,
                    .env_launch_allowlisted = allowlisted,
                    .env_keys_removed = removed,
                    .profile_compiled = true,
                    .profile_hash_hex = hash_copy,
                };
            };
            // Precompute scope while `compiled` is still alive (static summary string).
            const seatbelt_scope = compiled.effectiveFsScopeSummary(.seatbelt);
            return .{
                .receipt = posture.preparedReceipt(.seatbelt, platform.reason_code),
                .env_scrubbed = scrubbed,
                .env_launch_allowlisted = allowlisted,
                .env_keys_removed = removed,
                .profile_compiled = true,
                .profile_hash_hex = hash_copy,
                .materials = .{ .seatbelt = .{
                    .sbpl_z = sbpl_z,
                    .allocator = boundary.allocator,
                    .fs_scope = seatbelt_scope,
                } },
            };
        },
        .unavailable => {
            setFailReason(boundary, platform.reason_code);
            if (boundary.mode == .on) return error.RequireFailed;
            return .{
                .receipt = posture.unavailableReceipt(platform.reason_code),
                .env_scrubbed = scrubbed,
                .env_launch_allowlisted = false,
                .env_keys_removed = removed,
                .profile_compiled = true,
                .profile_hash_hex = hash_copy,
            };
        },
        .failed => {
            setFailReason(boundary, platform.reason_code);
            if (boundary.mode == .on) return error.RequireFailed;
            return .{
                .receipt = posture.failedReceipt(platform.reason_code),
                .env_scrubbed = scrubbed,
                .env_launch_allowlisted = false,
                .env_keys_removed = removed,
                .profile_compiled = true,
                .profile_hash_hex = hash_copy,
            };
        },
    }
}

/// Platform prepare: Linux → Landlock ABI probe + prepared child plan; macOS → Seatbelt prepare.
/// Neither path returns session-active from the parent seam alone.
/// Mode on/auto fail-closed is enforced by the caller (`applyBeforeExec`), not here.
/// Seatbelt OOM surfaces as `error.OutOfMemory` (never soft `.failed`).
fn tryPlatformApply(
    allocator: std.mem.Allocator,
    compiled: *const profile.CompiledProfile,
) ApplyError!PlatformApplyOutcome {
    return switch (builtin.os.tag) {
        .linux => tryPlatformApplyLinux(),
        .macos => try tryMacOsSeatbelt(allocator, compiled),
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
) ApplyError!PlatformApplyOutcome {
    const prepared = macos_seatbelt.prepareForChildApply(allocator, compiled);
    return switch (prepared.status) {
        .unavailable => .{
            .status = .unavailable,
            .mechanism = .none,
            .reason_code = prepared.reason_code,
            .seatbelt_sbpl_z = null,
            .sbpl_allocator = null,
        },
        .failed => {
            // Match profile-compile policy: OOM is hard fail, not soft grade-drop.
            if (std.mem.eql(u8, prepared.reason_code, "seatbelt_profile_oom")) {
                return error.OutOfMemory;
            }
            return .{
                .status = .failed,
                .mechanism = .none,
                .reason_code = prepared.reason_code,
                .seatbelt_sbpl_z = null,
                .sbpl_allocator = null,
            };
        },
        .prepared => .{
            .status = .prepared_child,
            .mechanism = .seatbelt,
            .reason_code = "seatbelt_child_apply_required",
            .seatbelt_sbpl_z = prepared.sbpl_z,
            .sbpl_allocator = allocator,
        },
    };
}

/// Map Seatbelt prepare fail reason codes: OOM → hard `OutOfMemory`, else soft failed.
/// Exposed for unit tests of the OOM fail-closed contract (M-15).
fn mapSeatbeltPrepareFailure(reason_code: []const u8) ApplyError!PlatformApplyOutcome {
    if (std.mem.eql(u8, reason_code, "seatbelt_profile_oom")) return error.OutOfMemory;
    return .{
        .status = .failed,
        .mechanism = .none,
        .reason_code = reason_code,
        .seatbelt_sbpl_z = null,
        .sbpl_allocator = null,
    };
}

/// Linux prepare: ABI probe only. Do not double-apply via verifyApplyInChild
/// on the production hot path — real Landlock attach is the agent child in apply_posix.
/// `landlock.verifyApplyInChild` remains available for unit tests in landlock.zig.
fn tryPlatformApplyLinux() PlatformApplyOutcome {
    if (!landlock.isAbiAvailable()) {
        return .{
            .status = .unavailable,
            .mechanism = .none,
            .reason_code = "landlock_unavailable",
        };
    }

    return .{
        .status = .prepared_child,
        .mechanism = .landlock,
        .reason_code = "landlock_child_apply_required",
    };
}

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

    // Parent prepare is ABI/backend probe only — missing path is not a parent failure.
    // Denylist scrub must still run; session stays non-active until agent-child apply + promote.
    var result = try applyBeforeExec(.{
        .allocator = std.testing.allocator,
        .mode = .auto,
        .workspace_root = "/tmp/orca-apply-ws-nonexistent-u05",
        .env_map = &env_map,
    });
    defer result.deinit();

    try std.testing.expect(result.receipt.posture != .active);
    try std.testing.expect(!result.receipt.isActive());
    try std.testing.expect(result.env_scrubbed);
    try std.testing.expect(result.profile_compiled);
    try std.testing.expect(result.profile_hash_hex != null);
    try std.testing.expect(env_map.get("LD_PRELOAD") == null);
    try std.testing.expectEqualStrings("/usr/bin", env_map.get("PATH").?);
    try std.testing.expectEqualStrings("s1", env_map.get("ORCA_SESSION_ID").?);
    // Non-Linux: backend_not_implemented / macos_version_unsupported / prepared;
    // Linux without ABI: landlock_unavailable;
    // Linux with ABI: prepared (landlock_child_apply_required) — attach is spawn path.
    try std.testing.expect(result.receipt.posture == .unavailable or result.receipt.posture == .failed or result.receipt.posture == .prepared);
    // Allowlist only with child-apply materials.
    try std.testing.expectEqual(result.requiresChildApply(), result.env_launch_allowlisted);
}

test "auto grade-drop retains provider keys; attach path allowlists" {
    // Inherit-like env: provider credentials + injection key.
    // Denylist always strips injection. Launch allowlist only when materials require child apply.
    var env_map = std.process.Environ.Map.init(std.testing.allocator);
    defer env_map.deinit();
    try env_map.put("PATH", "/usr/bin:/bin");
    try env_map.put("HOME", "/tmp");
    try env_map.put("OPENAI_API_KEY", "sk-retain-on-grade-drop");
    try env_map.put("AWS_SECRET_ACCESS_KEY", "aws-secret-retain");
    try env_map.put("LD_PRELOAD", "evil.so");
    try env_map.put("SSL_CERT_FILE", "/etc/ssl/cert.pem");
    try env_map.put("SSH_AUTH_SOCK", "/tmp/ssh-agent.sock");

    var result = try applyBeforeExec(.{
        .allocator = std.testing.allocator,
        .mode = .auto,
        .workspace_root = "/tmp/orca-apply-ws-m2-allowlist",
        .env_map = &env_map,
    });
    defer result.deinit();

    // Injection denylist always runs on auto.
    try std.testing.expect(result.env_scrubbed);
    try std.testing.expect(env_map.get("LD_PRELOAD") == null);
    try std.testing.expectEqualStrings("/usr/bin:/bin", env_map.get("PATH").?);

    if (result.requiresChildApply()) {
        // Attach path: launch allowlist strips secrets and SSH_AUTH_SOCK; TLS trust kept.
        try std.testing.expect(result.env_launch_allowlisted);
        try std.testing.expect(env_map.get("OPENAI_API_KEY") == null);
        try std.testing.expect(env_map.get("AWS_SECRET_ACCESS_KEY") == null);
        try std.testing.expectEqualStrings("/etc/ssl/cert.pem", env_map.get("SSL_CERT_FILE").?);
        try std.testing.expect(env_map.get("SSH_AUTH_SOCK") == null);
    } else {
        // Pure grade-drop unavailable/failed: provider keys retained (no allowlist).
        try std.testing.expect(!result.env_launch_allowlisted);
        try std.testing.expectEqualStrings("sk-retain-on-grade-drop", env_map.get("OPENAI_API_KEY").?);
        try std.testing.expectEqualStrings("aws-secret-retain", env_map.get("AWS_SECRET_ACCESS_KEY").?);
        try std.testing.expectEqualStrings("/etc/ssl/cert.pem", env_map.get("SSL_CERT_FILE").?);
        try std.testing.expectEqualStrings("/tmp/ssh-agent.sock", env_map.get("SSH_AUTH_SOCK").?);
        try std.testing.expect(result.receipt.posture == .unavailable or result.receipt.posture == .failed);
    }
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
    // Linux without Landlock ABI → RequireFailed; with ABI → prepared_child (path open is spawn).
    // macOS matrix Seatbelt prepare succeeds (child apply still required; not active yet).
    if (result) |*ok| {
        defer ok.deinit();
        if (builtin.os.tag == .macos) {
            try std.testing.expect(ok.requiresChildApply());
            try std.testing.expectEqual(ChildApplyKind.seatbelt, ok.childApplyKind());
            try std.testing.expect(!ok.receipt.isActive());
        } else {
            // Parent seam never active: prepared child plan only if ABI available.
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

test "profile compile OutOfMemory propagates (never soft unavailable)" {
    // OOM on compile is hard failure for both on and auto — not grade-drop.
    const modes = [_]OsSandboxMode{ .on, .auto };
    for (modes) |mode| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
        const err = applyBeforeExec(.{
            .allocator = failing.allocator(),
            .mode = mode,
            .workspace_root = "/tmp/orca-apply-ws-compile-oom",
            .env_map = null,
        });
        try std.testing.expectError(error.OutOfMemory, err);
        try std.testing.expect(failing.has_induced_failure);
    }
}

test "seatbelt prepare OOM maps to OutOfMemory not soft failed" {
    // seatbelt_profile_oom must hard-fail like profile compile OOM (M-15).
    try std.testing.expectError(error.OutOfMemory, mapSeatbeltPrepareFailure("seatbelt_profile_oom"));
    var soft = try mapSeatbeltPrepareFailure("seatbelt_profile_render_failed");
    defer soft.deinit();
    try std.testing.expectEqual(PlatformApplyStatus.failed, soft.status);
    try std.testing.expectEqualStrings("seatbelt_profile_render_failed", soft.reason_code);
}

test "PlatformApplyOutcome deinit frees owned SBPL" {
    const sbpl = try std.testing.allocator.dupeZ(u8, "(version 1)\n(deny default)\n");
    var outcome: PlatformApplyOutcome = .{
        .status = .prepared_child,
        .mechanism = .seatbelt,
        .reason_code = "seatbelt_child_apply_required",
        .seatbelt_sbpl_z = sbpl,
        .sbpl_allocator = std.testing.allocator,
    };
    // take transfers ownership — deinit must not double-free.
    const taken = outcome.takeSeatbeltSbpl();
    try std.testing.expect(taken != null);
    outcome.deinit();
    std.testing.allocator.free(taken.?);

    const sbpl2 = try std.testing.allocator.dupeZ(u8, "(version 1)\n");
    var outcome2: PlatformApplyOutcome = .{
        .status = .prepared_child,
        .mechanism = .seatbelt,
        .reason_code = "seatbelt_child_apply_required",
        .seatbelt_sbpl_z = sbpl2,
        .sbpl_allocator = std.testing.allocator,
    };
    outcome2.deinit(); // frees sbpl2
    try std.testing.expect(outcome2.seatbelt_sbpl_z == null);
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

    // ABI available → prepared plan without parent-side Landlock apply; not session active.
    try std.testing.expect(!result.receipt.isActive());
    try std.testing.expectEqual(posture.SessionPosture.prepared, result.receipt.posture);
    try std.testing.expectEqual(ChildApplyKind.landlock, result.childApplyKind());
    try std.testing.expectEqual(std.meta.Tag(ChildMaterials).landlock, std.meta.activeTag(result.materials));
    try std.testing.expect(result.profile_hash_hex != null);
    try std.testing.expectEqualStrings("landlock_child_apply_required", result.receipt.reason_code.?);

    // S-GLO-01: bare materials never authorize active until activateAfterHandshake.
    try std.testing.expect(!result.receipt.isActive());
    // Same-module activate after (simulated) handshake builds active receipt.
    const proof = try result.activateAfterHandshake();
    try std.testing.expect(proof.isValid());
    try std.testing.expectEqual(posture.BackendMechanism.landlock, proof.mechanism);
    try std.testing.expect(result.receipt.isActive());
    try std.testing.expectEqual(posture.BackendMechanism.landlock, result.receipt.mechanism);
    try std.testing.expect(std.mem.indexOf(u8, result.receipt.fs_scope, "workspace child RW") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.receipt.fs_scope, "root RO") != null);
    // Default include_tmp=false → no classic platform tmp RW claim.
    try std.testing.expect(std.mem.indexOf(u8, result.receipt.fs_scope, "platform tmp RW") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.receipt.fs_scope, "no home") != null);
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
    const hash64 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    const complete = try posture.activeReceipt(.landlock, hash64, "workspace child RW, root RO, system RO, platform tmp RW, no home");
    try std.testing.expect(std.mem.indexOf(u8, complete.fs_scope, "network") == null);
    try std.testing.expect(std.mem.indexOf(u8, complete.fs_scope, "root RO") != null);
    try std.testing.expect(std.mem.indexOf(u8, complete.fs_scope, "platform tmp RW") != null);
}

test "activateAfterHandshake activates from materials; materials alone stay inactive" {
    const hash: [64]u8 = .{'a'} ** 64;
    const sbpl = try std.testing.allocator.dupeZ(u8, "(version 1)\n");
    // Precomputed scope with classic tmp (opt-in) — activate must use this verbatim.
    const scope_with_tmp = "workspace RW, system RO, platform tmp RW, no home, control write-deny (readable), mach-lookup residual";
    var result: ApplyResult = .{
        .receipt = posture.preparedReceipt(.seatbelt, "seatbelt_child_apply_required"),
        .profile_compiled = true,
        .profile_hash_hex = hash,
        .materials = .{ .seatbelt = .{
            .sbpl_z = sbpl,
            .allocator = std.testing.allocator,
            .fs_scope = scope_with_tmp,
        } },
    };
    defer result.deinit();

    try std.testing.expectEqual(ChildApplyKind.seatbelt, result.childApplyKind());
    // S-GLO-01: materials alone never yield isActive.
    try std.testing.expect(!result.receipt.isActive());
    const proof = try result.activateAfterHandshake();
    try std.testing.expect(proof.isValid());
    try std.testing.expectEqual(posture.BackendMechanism.seatbelt, proof.mechanism);
    try std.testing.expect(result.receipt.isActive());
    try std.testing.expectEqual(posture.BackendMechanism.seatbelt, result.receipt.mechanism);
    try std.testing.expectEqualStrings(scope_with_tmp, result.receipt.fs_scope);
    try std.testing.expect(std.mem.indexOf(u8, result.receipt.fs_scope, "network") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.receipt.fs_scope, "platform tmp RW") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.receipt.fs_scope, "no home") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.receipt.fs_scope, "mach-lookup residual") != null);
}

test "seatbelt activate uses precomputed fs_scope without platform tmp by default" {
    const hash: [64]u8 = .{'c'} ** 64;
    const sbpl = try std.testing.allocator.dupeZ(u8, "(version 1)\n");
    // Production default (include_tmp=false) summary from profile.effectiveFsScopeSummary(.seatbelt).
    const no_tmp_scope = "workspace RW, system RO, no home, control write-deny (readable), mach-lookup residual";
    var result: ApplyResult = .{
        .receipt = posture.preparedReceipt(.seatbelt, "seatbelt_child_apply_required"),
        .profile_compiled = true,
        .profile_hash_hex = hash,
        .materials = .{ .seatbelt = .{
            .sbpl_z = sbpl,
            .allocator = std.testing.allocator,
            .fs_scope = no_tmp_scope,
        } },
    };
    defer result.deinit();

    _ = try result.activateAfterHandshake();
    try std.testing.expect(result.receipt.isActive());
    try std.testing.expectEqualStrings(no_tmp_scope, result.receipt.fs_scope);
    try std.testing.expect(std.mem.indexOf(u8, result.receipt.fs_scope, "platform tmp") == null);
}

test "activateAfterHandshake hard-fails on missing profile hash" {
    const sbpl = try std.testing.allocator.dupeZ(u8, "(version 1)\n");
    var result: ApplyResult = .{
        .receipt = posture.preparedReceipt(.seatbelt, "seatbelt_child_apply_required"),
        .profile_compiled = true,
        .profile_hash_hex = null,
        .materials = .{ .seatbelt = .{
            .sbpl_z = sbpl,
            .allocator = std.testing.allocator,
            .fs_scope = "workspace RW, system RO, no home, control write-deny (readable), mach-lookup residual",
        } },
    };
    defer result.deinit();

    try std.testing.expectError(error.ApplyFailed, result.activateAfterHandshake());
    try std.testing.expect(!result.receipt.isActive());
}

test "activateAfterHandshake hard-fails without materials" {
    const hash: [64]u8 = .{'b'} ** 64;
    var result: ApplyResult = .{
        .receipt = posture.preparedReceipt(.landlock, "landlock_child_apply_required"),
        .profile_compiled = true,
        .profile_hash_hex = hash,
        .materials = .none,
    };
    defer result.deinit();
    try std.testing.expectError(error.ApplyFailed, result.activateAfterHandshake());
    try std.testing.expect(!result.receipt.isActive());
}

test "spawnAgent without child materials returns ApplyFailed not Unexpected" {
    var result: ApplyResult = .{
        .receipt = posture.disabledReceipt(),
        .profile_compiled = false,
        .profile_hash_hex = null,
        .materials = .none,
    };
    defer result.deinit();
    try std.testing.expectEqual(ChildApplyKind.none, result.childApplyKind());
    try std.testing.expectError(error.ApplyFailed, result.spawnAgent(
        std.testing.io,
        std.testing.allocator,
        &[_][]const u8{"/usr/bin/true"},
        null,
        "/tmp",
        .ignore,
    ));
}

test "spawnAgent promotes with typed proof on macOS Seatbelt" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    if (!macos_seatbelt.sandboxInitAvailable()) return error.SkipZigTest;
    const ver = macos_seatbelt.detectProductVersion() catch return error.SkipZigTest;
    if (!macos_seatbelt.isMatrixMajor(ver.major)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, ".orca");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "neighbor.txt", .data = "ok" });
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var result = try applyBeforeExec(.{
        .allocator = std.testing.allocator,
        .mode = .on,
        .workspace_root = root,
        .env_map = null,
    });
    defer result.deinit();
    try std.testing.expectEqual(ChildApplyKind.seatbelt, result.childApplyKind());
    try std.testing.expect(!result.receipt.isActive());

    const spawned = try result.spawnAgent(
        std.testing.io,
        std.testing.allocator,
        &[_][]const u8{"/usr/bin/true"},
        null,
        root,
        .ignore,
    );
    try std.testing.expect(spawned.proof.isValid());
    try std.testing.expectEqual(posture.BackendMechanism.seatbelt, spawned.proof.mechanism);
    try std.testing.expect(result.receipt.isActive());
    try std.testing.expectEqual(posture.BackendMechanism.seatbelt, result.receipt.mechanism);

    var status: c_int = 0;
    _ = std.c.waitpid(spawned.pid, &status, 0);
    try std.testing.expect((status & 0x7f) == 0);
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
        // Real reason codes only — never the backend_not_implemented placeholder on Darwin.
        if (builtin.os.tag == .macos) {
            try std.testing.expect(std.mem.indexOf(u8, fail_reason, "backend_not_implemented") == null);
        }
    }
}

test "session banner helper remains mechanism-neutral for apply receipts" {
    var buf: [320]u8 = undefined;
    const hash64 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    const active = try posture.activeReceipt(.seatbelt, hash64, "workspace RW, system RO, platform tmp RW, no home");
    const line = try posture.formatSessionBanner(&buf, active);
    try std.testing.expect(std.mem.indexOf(u8, line, "OS sandbox: active") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "Seatbelt") == null);
    try std.testing.expect(std.mem.indexOf(u8, line, "Landlock") == null);
}

test "isUngrantedHostTmpdir detects macOS var/folders shapes" {
    try std.testing.expect(isUngrantedHostTmpdir("/var/folders/xx/yy/T/"));
    try std.testing.expect(isUngrantedHostTmpdir("/private/var/folders/xx/yy/T"));
    try std.testing.expect(!isUngrantedHostTmpdir("/tmp"));
    try std.testing.expect(!isUngrantedHostTmpdir("/private/tmp"));
    try std.testing.expect(!isUngrantedHostTmpdir("/workspace/.orca-tmp"));
}

test "rewriteTempEnvForAttach points TMPDIR at workspace session temp" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var env_map = std.process.Environ.Map.init(std.testing.allocator);
    defer env_map.deinit();
    // Simulate macOS host TMPDIR (ungranted under Seatbelt defaults).
    try env_map.put("TMPDIR", "/var/folders/ns/xmz0/T/");
    try env_map.put("TMP", "/var/folders/ns/xmz0/T/");
    try env_map.put("TEMP", "/var/folders/ns/xmz0/T/");

    const rewritten = try rewriteTempEnvForAttach(std.testing.allocator, &env_map, root);
    try std.testing.expect(!isUngrantedHostTmpdir(rewritten));
    try std.testing.expect(std.mem.endsWith(u8, rewritten, "/.orca-tmp") or std.mem.eql(u8, rewritten, classic_tmp_fallback));
    try std.testing.expectEqualStrings(rewritten, env_map.get("TMPDIR").?);
    try std.testing.expectEqualStrings(rewritten, env_map.get("TMP").?);
    try std.testing.expectEqualStrings(rewritten, env_map.get("TEMP").?);

    // Preferred path should exist when workspace is real and writable.
    if (std.mem.endsWith(u8, rewritten, "/.orca-tmp")) {
        var io_rt: std.Io.Threaded = .init_single_threaded;
        const io = io_rt.io();
        var dir = try std.Io.Dir.openDirAbsolute(io, rewritten, .{});
        dir.close(io);
    }
}

test "attach path rewrites host TMPDIR out of var/folders (R2-2)" {
    // Only meaningful when prepare yields child-apply materials (macOS Seatbelt / Linux Landlock).
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, ".orca");
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var env_map = std.process.Environ.Map.init(std.testing.allocator);
    defer env_map.deinit();
    try env_map.put("PATH", "/usr/bin:/bin");
    try env_map.put("HOME", "/tmp");
    try env_map.put("TMPDIR", "/var/folders/xx/yy/T/");
    try env_map.put("LD_PRELOAD", "evil.so");

    var result = try applyBeforeExec(.{
        .allocator = std.testing.allocator,
        .mode = .auto,
        .workspace_root = root,
        .env_map = &env_map,
    });
    defer result.deinit();

    try std.testing.expect(env_map.get("LD_PRELOAD") == null);
    if (result.requiresChildApply()) {
        const td = env_map.get("TMPDIR") orelse "";
        try std.testing.expect(td.len > 0);
        try std.testing.expect(!isUngrantedHostTmpdir(td));
        try std.testing.expect(std.mem.endsWith(u8, td, "/.orca-tmp") or std.mem.eql(u8, td, classic_tmp_fallback));
        // Pure grants: rewritten path must be agent-writable under production model.
        switch (result.materials) {
            .landlock => |*p| {
                try std.testing.expect(p.isAgentWritable(td) or std.mem.eql(u8, td, classic_tmp_fallback));
            },
            else => {
                var compiled = try profile.compileProfile(std.testing.allocator, .{
                    .workspace_root = root,
                });
                defer compiled.deinit();
                try std.testing.expect(compiled.isAgentWritable(td));
            },
        }
    } else {
        // Grade-drop: no rewrite (attach-only contract).
        try std.testing.expectEqualStrings("/var/folders/xx/yy/T/", env_map.get("TMPDIR").?);
    }
}
