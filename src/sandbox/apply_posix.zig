//! POSIX fork → OS-FS apply → exec helper (U05/U07).
//!
//! Parent Orca stays free. Child installs Landlock (Linux) or Seatbelt (macOS)
//! then execs the agent. Child order: setpgid → stdio → apply → chdir →
//! preflight → fd_scrub (keep `{0,1,2,status_w}`) → status_ok → close
//! status_w → execve. Scrub runs before the handshake so the parent never
//! promotes attach while inherited FDs are still open; after status_ok only
//! the write end is closed (no second full scrub).
//!
//! Honesty (S-GLO-01): a pre-exec status pipe proves child apply *and*
//! required pre-exec setup (chdir, preflight, FD scrub) succeeded before the
//! parent returns a live child pid. Session `active` is promoted only after
//! that handshake (not from probe alone or fork alone). Parent waits with a
//! poll deadline so a hung child cannot block forever. The subsequent execve
//! itself cannot be proven before the parent returns — only that setup through
//! status_ok completed.
//!
//! - Linux: `forkApplyLandlockAndExec` (parent builds landlock expand plan
//!   before fork so the child never opendir/readdir — Z-3)
//! - macOS: `forkApplySeatbeltAndExec` (sandbox_init in child only; SBPL
//!   pre-rendered in parent — Z-4 residual documented in macos_seatbelt.zig)
//! - Other: Unsupported

const std = @import("std");
const builtin = @import("builtin");
const profile = @import("profile.zig");
const landlock = @import("landlock.zig");
const fd_scrub = @import("fd_scrub.zig");
const macos_seatbelt = @import("macos_seatbelt.zig");

pub const SpawnError = error{
    Unsupported,
    ForkFailed,
    ApplyFailed,
    ExecFailed,
    OutOfMemory,
    FileNotFound,
    AccessDenied,
};

/// Match core.process.StdioBehavior without importing core (module boundary).
pub const StdioBehavior = enum {
    inherit,
    ignore,
};

/// Result of a successful parent-side fork after child apply handshake.
/// Prefer `SpawnLease` for ownership of retained argv/env buffers (M-17).
pub const ChildPid = struct {
    pid: i32,
};

/// Owns page_allocator buffers retained across fork until the child is reaped
/// or the parent process exits (Z-13 / M-17).
///
/// After a successful handshake the child is about to `execve`; free only after
/// `waitpid` has reaped the child (or on process exit). `ApplyResult.deinit`
/// frees the lease after the supervisor wait completes on the production path.
pub const SpawnLease = struct {
    pid: i32,
    allocator: std.mem.Allocator,
    argv_z: ?[:null]?[*:0]const u8 = null,
    envp: ?AllocatedEnvp = null,
    cwd_z: ?[:0]const u8 = null,
    expand_plan: ?landlock.ChildLandlockPlan = null,

    pub fn deinit(self: *SpawnLease) void {
        if (self.argv_z) |a| {
            freeArgvZ(self.allocator, a);
            self.argv_z = null;
        }
        if (self.envp) |e| {
            freeEnvpZ(self.allocator, e);
            self.envp = null;
        }
        if (self.cwd_z) |z| {
            self.allocator.free(z);
            self.cwd_z = null;
        }
        if (self.expand_plan) |*plan| {
            plan.deinit();
            self.expand_plan = null;
        }
        self.pid = -1;
    }
};

/// Single-byte status pipe protocol: child writes this after successful apply
/// *and* required pre-exec setup (chdir, preflight, FD scrub with status_w
/// kept). Parent must not promote session active until this byte is received.
const status_ok: u8 = 1;

/// Parent waits at most this long for the child apply handshake (ms).
/// Hung children must not block `orca run` forever (M-11).
const status_handshake_timeout_ms: i32 = 10_000;

const ChildOsApply = union(enum) {
    landlock: struct {
        compiled: *const profile.CompiledProfile,
        plan: *const landlock.ChildLandlockPlan,
    },
    seatbelt: struct {
        sbpl_z: [*:0]const u8,
    },
};

/// Fork, apply Landlock in the child from `compiled`, chdir, preflight, scrub
/// FDs (keep status_w), handshake, then execve.
///
/// Returns a `SpawnLease` owning retained argv/env/plan buffers. Caller must
/// `deinit` the lease after reaping the child (or process exit).
///
/// Linux only. Does not apply network Landlock.
pub fn forkApplyLandlockAndExec(
    compiled: *const profile.CompiledProfile,
    argv: []const []const u8,
    env_map: ?*const std.process.Environ.Map,
    cwd: ?[]const u8,
    stdio: StdioBehavior,
) SpawnError!SpawnLease {
    if (builtin.os.tag != .linux) return error.Unsupported;
    if (argv.len == 0) return error.ExecFailed;
    return forkApplyAndExecLandlock(compiled, argv, env_map, cwd, stdio);
}

/// Fork, apply Seatbelt SBPL in the child, chdir, preflight, scrub FDs (keep
/// status_w), handshake, then execve. macOS only.
///
/// **Caller ownership of `sbpl_z`:** must remain valid until the child has
/// exec'd (parent retains the SBPL — typically until process exit for a
/// one-shot launch).
///
/// Returns a `SpawnLease` — free after reaping the child.
pub fn forkApplySeatbeltAndExec(
    sbpl_z: [*:0]const u8,
    argv: []const []const u8,
    env_map: ?*const std.process.Environ.Map,
    cwd: ?[]const u8,
    stdio: StdioBehavior,
) SpawnError!SpawnLease {
    if (builtin.os.tag != .macos) return error.Unsupported;
    if (argv.len == 0) return error.ExecFailed;
    return forkApplyAndExecCommon(.{ .seatbelt = .{ .sbpl_z = sbpl_z } }, null, argv, env_map, cwd, stdio);
}

fn forkApplyAndExecLandlock(
    compiled: *const profile.CompiledProfile,
    argv: []const []const u8,
    env_map: ?*const std.process.Environ.Map,
    cwd: ?[]const u8,
    stdio: StdioBehavior,
) SpawnError!SpawnLease {
    const allocator = std.heap.page_allocator;

    // M-18: ensure `{workspace}/.orca-tmp` exists *before* expand enumeration.
    {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const name = ".orca-tmp";
        const needed = compiled.workspace_root.len + 1 + name.len;
        if (needed <= path_buf.len and compiled.workspace_root.len > 0) {
            @memcpy(path_buf[0..compiled.workspace_root.len], compiled.workspace_root);
            path_buf[compiled.workspace_root.len] = '/';
            @memcpy(path_buf[compiled.workspace_root.len + 1 ..][0..name.len], name);
            var io_rt: std.Io.Threaded = .init_single_threaded;
            const io = io_rt.io();
            std.Io.Dir.cwd().createDirPath(io, path_buf[0..needed]) catch {};
        }
    }

    // Z-3: enumerate control-expand paths in the parent before fork.
    // Ownership transfers into forkApplyAndExecCommon / SpawnLease (no local errdefer).
    const expand_plan = landlock.buildChildLandlockPlan(allocator, compiled) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.ApplyFailed,
    };

    return forkApplyAndExecCommon(
        .{ .landlock = .{ .compiled = compiled, .plan = undefined } },
        expand_plan,
        argv,
        env_map,
        cwd,
        stdio,
    );
}

/// Unified parent protocol for Landlock and Seatbelt (M-7). Only the child
/// apply step differs. When `pending_plan` is non-null it is moved into the
/// returned lease on success (or freed via errdefer path on failure inside
/// the landlock wrapper).
fn forkApplyAndExecCommon(
    child_apply: ChildOsApply,
    pending_plan: ?landlock.ChildLandlockPlan,
    argv: []const []const u8,
    env_map: ?*const std.process.Environ.Map,
    cwd: ?[]const u8,
    stdio: StdioBehavior,
) SpawnError!SpawnLease {
    const allocator = std.heap.page_allocator;
    var plan_holder = pending_plan;
    errdefer if (plan_holder) |*p| p.deinit();

    // Re-bind landlock plan pointer to holder storage (stable for child).
    var apply = child_apply;
    if (plan_holder) |*p| {
        apply = .{ .landlock = .{
            .compiled = child_apply.landlock.compiled,
            .plan = p,
        } };
    }

    const argv_z = try allocArgvZ(allocator, argv);
    errdefer freeArgvZ(allocator, argv_z);
    const envp = try allocEnvpZ(allocator, env_map);
    errdefer freeEnvpZ(allocator, envp);
    const cwd_z: ?[:0]const u8 = if (cwd) |c|
        (allocator.dupeZ(u8, c) catch return error.OutOfMemory)
    else
        null;
    errdefer if (cwd_z) |z| allocator.free(z);

    const pipe_fds = openStatusPipe() catch return error.ForkFailed;
    var status_r = pipe_fds[0];
    var status_w = pipe_fds[1];
    errdefer {
        closeFd(status_r);
        closeFd(status_w);
    }

    const child_pid: i32 = switch (builtin.os.tag) {
        .linux => blk: {
            const linux = std.os.linux;
            const pid_rc = linux.fork();
            if (linux.errno(pid_rc) != .SUCCESS) return error.ForkFailed;
            if (pid_rc == 0) {
                runChildAfterFork(apply, argv_z, envp, cwd_z, stdio, status_r, status_w);
            }
            break :blk @intCast(pid_rc);
        },
        .macos => blk: {
            const pid = std.c.fork();
            if (pid < 0) return error.ForkFailed;
            if (pid == 0) {
                runChildAfterFork(apply, argv_z, envp, cwd_z, stdio, status_r, status_w);
            }
            break :blk pid;
        },
        else => return error.Unsupported,
    };

    closeFd(status_w);
    status_w = -1;
    const ok = readStatusOk(status_r, child_pid);
    closeFd(status_r);
    status_r = -1;
    if (!ok) {
        killAndReapChild(child_pid);
        return error.ApplyFailed;
    }

    // Transfer ownership into lease (disarm plan errdefer).
    const moved_plan = plan_holder;
    plan_holder = null;
    return .{
        .pid = child_pid,
        .allocator = allocator,
        .argv_z = argv_z,
        .envp = envp,
        .cwd_z = cwd_z,
        .expand_plan = moved_plan,
    };
}

/// Child-only path after fork. Never returns.
fn runChildAfterFork(
    child_apply: ChildOsApply,
    argv_z: [:null]?[*:0]const u8,
    envp: AllocatedEnvp,
    cwd_z: ?[:0]const u8,
    stdio: StdioBehavior,
    status_r: i32,
    status_w_in: i32,
) noreturn {
    const status_w = status_w_in;
    closeFd(status_r);

    const failExit = struct {
        fn call(status_w_fd: i32) noreturn {
            closeFd(status_w_fd);
            switch (builtin.os.tag) {
                .linux => std.os.linux.exit(127),
                else => std.c._exit(127),
            }
        }
    }.call;

    if (std.c.setpgid(0, 0) != 0) failExit(status_w);

    applyStdioInChild(stdio) catch failExit(status_w);

    switch (child_apply) {
        .landlock => |ll| landlock.applySelf(ll.compiled, ll.plan) catch failExit(status_w),
        .seatbelt => |sb| macos_seatbelt.applyInChild(sb.sbpl_z) catch failExit(status_w),
    }

    if (cwd_z) |z| {
        const chdir_rc: isize = switch (builtin.os.tag) {
            .linux => std.os.linux.chdir(z.ptr),
            else => std.c.chdir(z.ptr),
        };
        if (chdir_rc != 0) failExit(status_w);
    }

    const path = argv_z[0] orelse failExit(status_w);
    if (!preflightExecTarget(path)) failExit(status_w);

    const keep_fds = [_]i32{ 0, 1, 2, status_w };
    fd_scrub.closeInheritedFds(&keep_fds);

    if (!writeStatusOk(status_w)) failExit(status_w);
    closeFd(status_w);

    switch (builtin.os.tag) {
        .linux => {
            _ = std.os.linux.execve(path, argv_z.ptr, envp.ptr.ptr);
            std.os.linux.exit(127);
        },
        else => {
            _ = std.c.execve(path, @ptrCast(argv_z.ptr), @ptrCast(envp.ptr.ptr));
            std.c._exit(127);
        },
    }
}

// ── preflight ──────────────────────────────────────────────────────────────

/// Best-effort check that `path` is readable+executable under the current box.
/// Runs in the child after apply and optional chdir; failure fails the handshake
/// so the parent does not promote session `active` (F-4).
fn preflightExecTarget(path: [*:0]const u8) bool {
    switch (builtin.os.tag) {
        .windows, .wasi => return true,
        else => {
            // POSIX: R_OK=4, X_OK=1 (portable constants; libc access).
            const R_OK: c_int = 4;
            const X_OK: c_int = 1;
            return std.c.access(path, R_OK | X_OK) == 0;
        },
    }
}

// ── status pipe ────────────────────────────────────────────────────────────

fn openStatusPipe() error{PipeFailed}![2]i32 {
    var fds: [2]std.c.fd_t = undefined;
    // Prefer pipe2(CLOEXEC) so a missed close cannot leak into exec.
    // macOS has no libc pipe2; fall back to pipe + fcntl.
    if (@TypeOf(std.c.pipe2) != void) {
        if (std.c.pipe2(&fds, .{ .CLOEXEC = true }) != 0) return error.PipeFailed;
    } else {
        if (std.c.pipe(&fds) != 0) return error.PipeFailed;
        // Fail closed if CLOEXEC cannot be set — a non-CLOEXEC pipe end can leak
        // into a later exec if a close is missed (M-11).
        if (std.c.fcntl(fds[0], std.c.F.SETFD, @as(c_int, std.c.FD_CLOEXEC)) == -1 or
            std.c.fcntl(fds[1], std.c.F.SETFD, @as(c_int, std.c.FD_CLOEXEC)) == -1)
        {
            _ = std.c.close(fds[0]);
            _ = std.c.close(fds[1]);
            return error.PipeFailed;
        }
    }
    return .{ @intCast(fds[0]), @intCast(fds[1]) };
}

fn closeFd(fd: i32) void {
    if (fd < 0) return;
    _ = std.c.close(fd);
}

fn writeStatusOk(write_fd: i32) bool {
    var buf = [_]u8{status_ok};
    const n = std.c.write(write_fd, &buf, 1);
    return n == 1;
}

/// Wait for the single-byte apply handshake with a deadline (M-11).
/// On timeout, kills the child process group so a hung child cannot hang orca.
/// Returns true only when the status_ok byte is received.
fn readStatusOk(read_fd: i32, child_pid: i32) bool {
    var fds = [_]std.posix.pollfd{.{
        .fd = read_fd,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};
    const ready = std.posix.poll(&fds, status_handshake_timeout_ms) catch {
        killProcessGroup(child_pid);
        return false;
    };
    if (ready == 0) {
        // Deadline exceeded — child never reported apply success.
        killProcessGroup(child_pid);
        return false;
    }
    // Readable, hung-up, or error: attempt the single-byte read.
    var buf: [1]u8 = undefined;
    const n = std.c.read(read_fd, &buf, 1);
    return n == 1 and buf[0] == status_ok;
}

/// Best-effort: signal the process group (negative pid) then the pid itself.
fn killProcessGroup(pid: i32) void {
    if (pid <= 0) return;
    std.posix.kill(-pid, std.posix.SIG.KILL) catch {};
    std.posix.kill(pid, std.posix.SIG.KILL) catch {};
}

/// Best-effort kill process group + pid and reap (public for post-handshake
/// promote hard-fail cleanup in `apply.spawnAgent` — M-3).
pub fn killAndReapChild(pid: i32) void {
    killProcessGroup(pid);
    var status: c_int = 0;
    // Retry waitpid on EINTR so parent does not free argv/env while the child
    // may still be alive (fork COW UAF). Other waitpid failures are best-effort
    // only (already reaped / ESRCH / etc.) — kill was already delivered.
    while (true) {
        const rc = std.c.waitpid(pid, &status, 0);
        if (rc >= 0) break;
        if (std.posix.errno(@as(isize, rc)) == .INTR) continue;
        break;
    }
}

// ── stdio ──────────────────────────────────────────────────────────────────

fn applyStdioInChild(stdio: StdioBehavior) error{StdioFailed}!void {
    switch (stdio) {
        .inherit => {},
        .ignore => try redirectStdioToDevNull(),
    }
}

fn redirectStdioToDevNull() error{StdioFailed}!void {
    // Keep 0/1/2 as the only stdio FDs; they stay in fd_scrub keep-set.
    const null_fd = std.c.open("/dev/null", .{ .ACCMODE = .RDWR });
    if (null_fd < 0) return error.StdioFailed;
    defer _ = std.c.close(null_fd);
    if (std.c.dup2(null_fd, 0) < 0) return error.StdioFailed;
    if (std.c.dup2(null_fd, 1) < 0) return error.StdioFailed;
    if (std.c.dup2(null_fd, 2) < 0) return error.StdioFailed;
}

// ── argv / env ─────────────────────────────────────────────────────────────

const AllocatedEnvp = struct {
    /// Null-terminated envp for execve.
    ptr: [:null]?[*:0]const u8,
    /// False when pointing at the current process `environ` (inherit).
    owned: bool,
};

fn allocArgvZ(allocator: std.mem.Allocator, argv: []const []const u8) SpawnError![:null]?[*:0]const u8 {
    var list = allocator.alloc(?[*:0]const u8, argv.len + 1) catch return error.OutOfMemory;
    // Null-init so errdefer free of optionals is safe on mid-loop OOM (M-7).
    @memset(list, null);
    errdefer {
        for (list[0..argv.len]) |p| {
            if (p) |z| allocator.free(std.mem.span(z));
        }
        allocator.free(list);
    }
    for (argv, 0..) |arg, i| {
        list[i] = (allocator.dupeZ(u8, arg) catch return error.OutOfMemory).ptr;
    }
    list[argv.len] = null;
    return list[0..argv.len :null];
}

fn freeArgvZ(allocator: std.mem.Allocator, argv_z: [:null]?[*:0]const u8) void {
    for (argv_z) |p| {
        if (p) |z| allocator.free(std.mem.span(z));
    }
    // Free the null-terminated pointer array (len + trailing null slot).
    const base: [*]?[*:0]const u8 = @ptrCast(argv_z.ptr);
    allocator.free(base[0 .. argv_z.len + 1]);
}

/// Build envp for execve. `null` env_map means inherit the current process
/// environment (same as `std.process.spawn` with a null environ_map). Never
/// invents an empty environment under the name of inherit.
fn allocEnvpZ(allocator: std.mem.Allocator, env_map: ?*const std.process.Environ.Map) SpawnError!AllocatedEnvp {
    if (env_map == null) {
        // Borrow process environ — not owned, not empty.
        const raw: [*:null]?[*:0]u8 = std.c.environ;
        var n: usize = 0;
        while (raw[n] != null) : (n += 1) {}
        const as_const: [*:null]?[*:0]const u8 = @ptrCast(raw);
        return .{ .ptr = as_const[0..n :null], .owned = false };
    }
    const map = env_map.?;
    // Count keys.
    var count: usize = 0;
    var it = map.iterator();
    while (it.next()) |_| count += 1;

    var list = allocator.alloc(?[*:0]const u8, count + 1) catch return error.OutOfMemory;
    // Null-init so errdefer free of optionals is safe on mid-loop OOM (M-7).
    @memset(list, null);
    errdefer {
        var i: usize = 0;
        while (i < count) : (i += 1) {
            if (list[i]) |z| allocator.free(std.mem.span(z));
        }
        allocator.free(list);
    }
    var idx: usize = 0;
    var it2 = map.iterator();
    while (it2.next()) |entry| {
        const line = std.fmt.allocPrint(allocator, "{s}={s}", .{ entry.key_ptr.*, entry.value_ptr.* }) catch return error.OutOfMemory;
        defer allocator.free(line);
        list[idx] = (allocator.dupeZ(u8, line) catch return error.OutOfMemory).ptr;
        idx += 1;
    }
    list[count] = null;
    return .{ .ptr = list[0..count :null], .owned = true };
}

fn freeEnvpZ(allocator: std.mem.Allocator, envp: AllocatedEnvp) void {
    if (!envp.owned) return;
    for (envp.ptr) |p| {
        if (p) |z| allocator.free(std.mem.span(z));
    }
    const base: [*]?[*:0]const u8 = @ptrCast(envp.ptr.ptr);
    allocator.free(base[0 .. envp.ptr.len + 1]);
}

/// Resolve argv[0] to an absolute path for exec.
/// When `env_map` is provided and contains PATH, that PATH is used (child env);
/// otherwise falls back to the process getenv PATH (M-8).
/// Caller owns the returned slice when `owned` is true.
pub fn resolveArgv0(
    io: std.Io,
    allocator: std.mem.Allocator,
    argv0: []const u8,
    env_map: ?*const std.process.Environ.Map,
) SpawnError!struct { path: []const u8, owned: bool } {
    if (argv0.len == 0) return error.FileNotFound;
    if (std.fs.path.isAbsolute(argv0)) {
        return .{ .path = argv0, .owned = false };
    }
    // Relative with a separator: resolve against cwd.
    if (std.mem.indexOfScalar(u8, argv0, '/') != null) {
        return .{ .path = argv0, .owned = false };
    }
    const path_env = blk: {
        if (env_map) |map| {
            if (map.get("PATH")) |p| break :blk p;
        }
        if (std.c.getenv("PATH")) |p| break :blk std.mem.span(p);
        break :blk "/usr/local/bin:/usr/bin:/bin";
    };
    var it = std.mem.splitScalar(u8, path_env, ':');
    while (it.next()) |dir| {
        if (dir.len == 0) continue;
        const candidate = std.fs.path.join(allocator, &.{ dir, argv0 }) catch return error.OutOfMemory;
        errdefer allocator.free(candidate);
        std.Io.Dir.cwd().access(io, candidate, .{}) catch {
            allocator.free(candidate);
            continue;
        };
        return .{ .path = candidate, .owned = true };
    }
    return error.FileNotFound;
}

// ── tests ──────────────────────────────────────────────────────────────────

test "forkApplyLandlockAndExec is unsupported off Linux" {
    if (builtin.os.tag == .linux) return error.SkipZigTest;
    try std.testing.expectError(error.Unsupported, forkApplyLandlockAndExec(
        &.{
            .allocator = std.testing.allocator,
            .workspace_root = "/",
            .grants = &.{},
            .control_roots = &.{},
            .canonical_bytes = "",
            .hash_hex = .{'0'} ** 64,
        },
        &[_][]const u8{"/bin/true"},
        null,
        null,
        .inherit,
    ));
}

test "forkApplyLandlockAndExec applies then execs on Linux with handshake" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    if (landlock.probeAbi() == null) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var ws_tmp = std.testing.tmpDir(.{});
    defer ws_tmp.cleanup();
    try ws_tmp.dir.createDirPath(io, ".orca");
    const ws_root = try ws_tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(ws_root);

    var compiled = try profile.compileProfile(allocator, .{
        .workspace_root = ws_root,
        // Cover true binary + dynamic linker paths on common distros.
        .system_ro_prefixes = &[_][]const u8{ "/usr", "/bin", "/sbin", "/lib", "/lib64" },
        .include_tmp = false,
    });
    defer compiled.deinit();

    const true_path = blk: {
        std.Io.Dir.cwd().access(io, "/usr/bin/true", .{}) catch {
            std.Io.Dir.cwd().access(io, "/bin/true", .{}) catch return error.SkipZigTest;
            break :blk "/bin/true";
        };
        break :blk "/usr/bin/true";
    };

    // Parent only gets a pid after child apply+chdir status pipe succeeds.
    var child = try forkApplyLandlockAndExec(
        &compiled,
        &[_][]const u8{true_path},
        null,
        ws_root,
        .inherit,
    );
    defer child.deinit();
    var status: c_int = 0;
    while (true) {
        const rc = std.c.waitpid(child.pid, &status, 0);
        if (rc >= 0) break;
        if (std.posix.errno(@as(isize, rc)) == .INTR) continue;
        return error.TestUnexpectedResult;
    }
    const exited = (status & 0x7f) == 0;
    try std.testing.expect(exited);
    const exit_code: u8 = @intCast((status >> 8) & 0xff);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
}

test "forkApplyLandlockAndExec fails handshake on bad chdir" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    if (landlock.probeAbi() == null) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var ws_tmp = std.testing.tmpDir(.{});
    defer ws_tmp.cleanup();
    try ws_tmp.dir.createDirPath(io, ".orca");
    const ws_root = try ws_tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(ws_root);

    var compiled = try profile.compileProfile(allocator, .{
        .workspace_root = ws_root,
        .system_ro_prefixes = &[_][]const u8{ "/usr", "/bin", "/sbin", "/lib", "/lib64" },
        .include_tmp = false,
    });
    defer compiled.deinit();

    const true_path = blk: {
        std.Io.Dir.cwd().access(io, "/usr/bin/true", .{}) catch {
            std.Io.Dir.cwd().access(io, "/bin/true", .{}) catch return error.SkipZigTest;
            break :blk "/bin/true";
        };
        break :blk "/usr/bin/true";
    };

    // chdir failure must not write status_ok — parent sees ApplyFailed.
    try std.testing.expectError(error.ApplyFailed, forkApplyLandlockAndExec(
        &compiled,
        &[_][]const u8{true_path},
        null,
        "/no/such/orca/cwd/for/handshake/test",
        .inherit,
    ));
}

test "forkApplySeatbeltAndExec is unsupported off macOS" {
    if (builtin.os.tag == .macos) return error.SkipZigTest;
    try std.testing.expectError(error.Unsupported, forkApplySeatbeltAndExec(
        "(version 1)\x00",
        &[_][]const u8{"/bin/true"},
        null,
        null,
        .inherit,
    ));
}

/// Permissive Seatbelt profile shared by low-level fork/exec handshake tests.
/// Product grants are narrower; this only proves apply → exec plumbing on matrix macOS.
const permissive_test_sbpl =
    \\(version 1)
    \\(deny default)
    \\(allow process*)
    \\(allow signal)
    \\(allow sysctl-read)
    \\(allow mach-lookup)
    \\(allow file-read-metadata)
    \\(allow file-read* (literal "/"))
    \\(allow file-read* (subpath "/usr"))
    \\(allow file-read* (subpath "/bin"))
    \\(allow file-read* (subpath "/System"))
    \\(allow file-read* (subpath "/Library"))
    \\(allow file-read* (subpath "/dev"))
    \\(allow file-read* (subpath "/private/var/db/dyld"))
    \\(allow file-ioctl (subpath "/dev"))
    \\
;

test "forkApplySeatbeltAndExec applies then execs on macOS with handshake" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const sbpl_z = try std.testing.allocator.dupeZ(u8, permissive_test_sbpl);
    defer std.testing.allocator.free(sbpl_z);

    // Seatbelt apply works even outside product matrix for this low-level helper;
    // product gating is in macos_seatbelt.evaluateSupport / applyBeforeExec.
    // Parent only gets a pid after child apply status pipe succeeds.
    var child = try forkApplySeatbeltAndExec(sbpl_z.ptr, &[_][]const u8{"/usr/bin/true"}, null, null, .inherit);
    defer child.deinit();
    var status: c_int = 0;
    _ = std.c.waitpid(child.pid, &status, 0);
    const exited = (status & 0x7f) == 0;
    try std.testing.expect(exited);
    const exit_code: u8 = @intCast((status >> 8) & 0xff);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
}

test "forkApplySeatbeltAndExec honors stdio ignore on macOS" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const sbpl_z = try std.testing.allocator.dupeZ(u8, permissive_test_sbpl);
    defer std.testing.allocator.free(sbpl_z);

    var child = try forkApplySeatbeltAndExec(
        sbpl_z.ptr,
        &[_][]const u8{ "/bin/sh", "-c", "echo should-not-appear-on-parent-stdout" },
        null,
        null,
        .ignore,
    );
    defer child.deinit();
    var status: c_int = 0;
    _ = std.c.waitpid(child.pid, &status, 0);
    try std.testing.expect((status & 0x7f) == 0);
    try std.testing.expectEqual(@as(u8, 0), @as(u8, @intCast((status >> 8) & 0xff)));
}

test "forkApplySeatbeltAndExec establishes process group leadership on macOS" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const sbpl_z = try std.testing.allocator.dupeZ(u8, permissive_test_sbpl);
    defer std.testing.allocator.free(sbpl_z);

    // After setpgid(0,0) in child, parent getpgid(pid) must equal pid (group leader).
    var child = try forkApplySeatbeltAndExec(
        sbpl_z.ptr,
        &[_][]const u8{ "/bin/sh", "-c", "sleep 0.15" },
        null,
        null,
        .ignore,
    );
    defer child.deinit();
    const getpgid = struct {
        extern "c" fn getpgid(pid: std.c.pid_t) std.c.pid_t;
    }.getpgid;
    const pgid = getpgid(child.pid);
    try std.testing.expect(pgid > 0);
    try std.testing.expectEqual(child.pid, pgid);
    var status: c_int = 0;
    _ = std.c.waitpid(child.pid, &status, 0);
    try std.testing.expect((status & 0x7f) == 0);
    try std.testing.expectEqual(@as(u8, 0), @as(u8, @intCast((status >> 8) & 0xff)));
}

test "null env_map inherits process environ (not empty)" {
    // allocEnvpZ is private; exercise via a short child that checks PATH is set.
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const sbpl_z = try std.testing.allocator.dupeZ(u8, permissive_test_sbpl);
    defer std.testing.allocator.free(sbpl_z);

    // With null env_map, PATH from parent must still be present (inherit).
    var child = try forkApplySeatbeltAndExec(
        sbpl_z.ptr,
        &[_][]const u8{ "/bin/sh", "-c", "test -n \"$PATH\"" },
        null,
        null,
        .ignore,
    );
    defer child.deinit();
    var status: c_int = 0;
    _ = std.c.waitpid(child.pid, &status, 0);
    try std.testing.expect((status & 0x7f) == 0);
    try std.testing.expectEqual(@as(u8, 0), @as(u8, @intCast((status >> 8) & 0xff)));
}

test "resolveArgv0 finds absolute and PATH binaries" {
    const abs = try resolveArgv0(std.testing.io, std.testing.allocator, "/bin/sh", null);
    try std.testing.expect(!abs.owned);
    try std.testing.expectEqualStrings("/bin/sh", abs.path);

    const via_path = resolveArgv0(std.testing.io, std.testing.allocator, "true", null) catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };
    defer if (via_path.owned) std.testing.allocator.free(via_path.path);
    try std.testing.expect(via_path.path.len > 0);
}

test "resolveArgv0 prefers PATH from env_map over process" {
    // Point PATH at an empty directory so a bare name cannot resolve via env_map.
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("PATH", "/no/such/orca/path/for/resolve/test");

    const missing = resolveArgv0(std.testing.io, std.testing.allocator, "true", &map);
    try std.testing.expectError(error.FileNotFound, missing);

    // Absolute still works regardless of env_map PATH.
    const abs = try resolveArgv0(std.testing.io, std.testing.allocator, "/bin/sh", &map);
    try std.testing.expect(!abs.owned);
    try std.testing.expectEqualStrings("/bin/sh", abs.path);
}

test "forkApplySeatbeltAndExec fails handshake on bad chdir" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const sbpl_z = try std.testing.allocator.dupeZ(u8, permissive_test_sbpl);
    defer std.testing.allocator.free(sbpl_z);

    // chdir failure must not write status_ok — parent sees ApplyFailed (M-2).
    try std.testing.expectError(error.ApplyFailed, forkApplySeatbeltAndExec(
        sbpl_z.ptr,
        &[_][]const u8{"/usr/bin/true"},
        null,
        "/no/such/orca/cwd/for/handshake/test",
        .inherit,
    ));
}
