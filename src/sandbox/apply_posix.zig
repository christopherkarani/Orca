//! POSIX fork → OS-FS apply → exec helper (U05/U07).
//!
//! Parent Orca stays free. Child installs Landlock (Linux) or Seatbelt (macOS)
//! then execs the agent. FD scrub runs in the child after apply, before exec.
//!
//! Honesty (S-GLO-01): a pre-exec status pipe proves child apply succeeded
//! before the parent returns a live child pid. Session `active` is promoted
//! only after that handshake (not from probe alone or fork alone).
//!
//! - Linux: `forkApplyLandlockAndExec`
//! - macOS: `forkApplySeatbeltAndExec` (sandbox_init in child only)
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
pub const ChildPid = struct {
    pid: i32,
};

/// Single-byte status pipe protocol: child writes this after successful apply.
const status_ok: u8 = 1;

/// Fork, apply Landlock in the child from `compiled`, scrub FDs, then execve.
///
/// Parent blocks on a status pipe until the child reports apply success (or dies).
/// On success the parent receives the child pid; the child never returns.
///
/// Linux only. Does not apply network Landlock.
pub fn forkApplyLandlockAndExec(
    compiled: *const profile.CompiledProfile,
    argv: []const []const u8,
    env_map: ?*const std.process.Environ.Map,
    cwd: ?[]const u8,
    stdio: StdioBehavior,
) SpawnError!ChildPid {
    if (builtin.os.tag != .linux) return error.Unsupported;
    if (argv.len == 0) return error.ExecFailed;
    return forkApplyLandlockAndExecLinux(compiled, argv, env_map, cwd, stdio);
}

/// Fork, apply Seatbelt SBPL in the child, scrub FDs, then execve.
///
/// Parent blocks on a status pipe until the child reports apply success (or dies).
/// macOS only. `sbpl_z` must remain valid until the child has exec'd (parent
/// retains ownership — typically until process exit for a one-shot launch).
pub fn forkApplySeatbeltAndExec(
    sbpl_z: [*:0]const u8,
    argv: []const []const u8,
    env_map: ?*const std.process.Environ.Map,
    cwd: ?[]const u8,
    stdio: StdioBehavior,
) SpawnError!ChildPid {
    if (builtin.os.tag != .macos) return error.Unsupported;
    if (argv.len == 0) return error.ExecFailed;
    return forkApplySeatbeltAndExecMacOs(sbpl_z, argv, env_map, cwd, stdio);
}

/// Verify Landlock can apply for this profile without boxing the parent.
/// Thin wrapper over landlock.verifyApplyInChild for the apply seam.
/// Probe only — never authorizes session `active`.
pub fn verifyLandlockApplyInChild(compiled: *const profile.CompiledProfile) landlock.ApplyError!void {
    try landlock.verifyApplyInChild(compiled);
}

fn forkApplyLandlockAndExecLinux(
    compiled: *const profile.CompiledProfile,
    argv: []const []const u8,
    env_map: ?*const std.process.Environ.Map,
    cwd: ?[]const u8,
    stdio: StdioBehavior,
) SpawnError!ChildPid {
    const linux = std.os.linux;

    // Allocate argv/env in the parent before fork. After a successful fork the
    // parent must not free them until the child has exec'd (munmap races).
    // For a one-shot agent launch we deliberately retain until process exit.
    const argv_z = try allocArgvZ(std.heap.page_allocator, argv);
    errdefer freeArgvZ(std.heap.page_allocator, argv_z);
    const envp = try allocEnvpZ(std.heap.page_allocator, env_map);
    errdefer freeEnvpZ(std.heap.page_allocator, envp);
    const cwd_z: ?[:0]const u8 = if (cwd) |c|
        (std.heap.page_allocator.dupeZ(u8, c) catch return error.OutOfMemory)
    else
        null;
    errdefer if (cwd_z) |z| std.heap.page_allocator.free(z);

    const pipe_fds = openStatusPipe() catch return error.ForkFailed;
    var status_r = pipe_fds[0];
    var status_w = pipe_fds[1];
    errdefer {
        closeFd(status_r);
        closeFd(status_w);
    }

    const pid_rc = linux.fork();
    if (linux.errno(pid_rc) != .SUCCESS) return error.ForkFailed;

    if (pid_rc == 0) {
        // Child path — never returns to parent logic.
        closeFd(status_r);
        status_r = -1;

        // Process-group leadership so parent kill(-pgid) reaps grandchildren.
        if (std.c.setpgid(0, 0) != 0) {
            closeFd(status_w);
            linux.exit(127);
        }

        // Stdio redirect before confinement: open(/dev/null) must not depend on
        // post-apply path grants (and must fail the handshake if it fails).
        applyStdioInChild(stdio) catch {
            closeFd(status_w);
            linux.exit(127);
        };

        landlock.applySelf(compiled) catch {
            closeFd(status_w);
            linux.exit(127);
        };

        // chdir + argv0 preflight under the box before handshake (F-4): parent must
        // not promote active if the agent binary is unreadable/unexecutable under grants.
        if (cwd_z) |z| {
            if (linux.chdir(z.ptr) != 0) {
                closeFd(status_w);
                linux.exit(127);
            }
        }

        const path = argv_z[0] orelse {
            closeFd(status_w);
            linux.exit(127);
        };
        if (!preflightExecTarget(path)) {
            closeFd(status_w);
            linux.exit(127);
        }

        // Prove apply + launch preflight to parent (S-GLO-01 handshake).
        if (!writeStatusOk(status_w)) {
            closeFd(status_w);
            linux.exit(127);
        }
        closeFd(status_w);
        status_w = -1;

        fd_scrub.closeInheritedFdsDefault();

        _ = linux.execve(path, argv_z.ptr, envp.ptr.ptr);
        linux.exit(127);
    }

    // Parent: wait for apply handshake (never promote from fork alone).
    closeFd(status_w);
    status_w = -1;
    const child_pid: i32 = @intCast(pid_rc);
    const ok = readStatusOk(status_r);
    closeFd(status_r);
    status_r = -1;
    if (!ok) {
        reapChild(child_pid);
        return error.ApplyFailed;
    }

    // Successful handshake: disarm errdefers by "forgetting" free (child still needs
    // the buffers until execve replaces the address space).
    return .{ .pid = child_pid };
}

fn forkApplySeatbeltAndExecMacOs(
    sbpl_z: [*:0]const u8,
    argv: []const []const u8,
    env_map: ?*const std.process.Environ.Map,
    cwd: ?[]const u8,
    stdio: StdioBehavior,
) SpawnError!ChildPid {
    const argv_z = try allocArgvZ(std.heap.page_allocator, argv);
    errdefer freeArgvZ(std.heap.page_allocator, argv_z);
    const envp = try allocEnvpZ(std.heap.page_allocator, env_map);
    errdefer freeEnvpZ(std.heap.page_allocator, envp);
    const cwd_z: ?[:0]const u8 = if (cwd) |c|
        (std.heap.page_allocator.dupeZ(u8, c) catch return error.OutOfMemory)
    else
        null;
    errdefer if (cwd_z) |z| std.heap.page_allocator.free(z);

    const pipe_fds = openStatusPipe() catch return error.ForkFailed;
    var status_r = pipe_fds[0];
    var status_w = pipe_fds[1];
    errdefer {
        closeFd(status_r);
        closeFd(status_w);
    }

    const pid = std.c.fork();
    if (pid < 0) return error.ForkFailed;

    if (pid == 0) {
        closeFd(status_r);
        status_r = -1;

        if (std.c.setpgid(0, 0) != 0) {
            closeFd(status_w);
            std.c._exit(127);
        }

        // Stdio before Seatbelt: RDWR open of /dev/null must not require post-apply
        // write grants, and failures must fail the parent handshake (not exit 127 after ok).
        applyStdioInChild(stdio) catch {
            closeFd(status_w);
            std.c._exit(127);
        };

        macos_seatbelt.applyInChild(sbpl_z) catch {
            closeFd(status_w);
            std.c._exit(127);
        };

        // chdir + argv0 preflight under the box before handshake (F-4).
        if (cwd_z) |z| {
            if (std.c.chdir(z.ptr) != 0) {
                closeFd(status_w);
                std.c._exit(127);
            }
        }

        const path = argv_z[0] orelse {
            closeFd(status_w);
            std.c._exit(127);
        };
        if (!preflightExecTarget(path)) {
            closeFd(status_w);
            std.c._exit(127);
        }

        if (!writeStatusOk(status_w)) {
            closeFd(status_w);
            std.c._exit(127);
        }
        closeFd(status_w);
        status_w = -1;

        fd_scrub.closeInheritedFdsDefault();

        _ = std.c.execve(path, @ptrCast(argv_z.ptr), @ptrCast(envp.ptr.ptr));
        std.c._exit(127);
    }

    closeFd(status_w);
    status_w = -1;
    const ok = readStatusOk(status_r);
    closeFd(status_r);
    status_r = -1;
    if (!ok) {
        reapChild(pid);
        return error.ApplyFailed;
    }

    return .{ .pid = pid };
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
        _ = std.c.fcntl(fds[0], std.c.F.SETFD, @as(c_int, std.c.FD_CLOEXEC));
        _ = std.c.fcntl(fds[1], std.c.F.SETFD, @as(c_int, std.c.FD_CLOEXEC));
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

fn readStatusOk(read_fd: i32) bool {
    var buf: [1]u8 = undefined;
    const n = std.c.read(read_fd, &buf, 1);
    return n == 1 and buf[0] == status_ok;
}

fn reapChild(pid: i32) void {
    var status: c_int = 0;
    _ = std.c.waitpid(pid, &status, 0);
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

/// Resolve argv[0] to an absolute path using parent PATH (mirrors std.process.spawn).
/// Caller owns the returned slice when `owned` is true.
pub fn resolveArgv0(
    io: std.Io,
    allocator: std.mem.Allocator,
    argv0: []const u8,
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

test "forkApplySeatbeltAndExec applies then execs on macOS with handshake" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const sbpl =
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
    const sbpl_z = try std.testing.allocator.dupeZ(u8, sbpl);
    defer std.testing.allocator.free(sbpl_z);

    // Seatbelt apply works even outside product matrix for this low-level helper;
    // product gating is in macos_seatbelt.evaluateSupport / applyBeforeExec.
    // Parent only gets a pid after child apply status pipe succeeds.
    const child = try forkApplySeatbeltAndExec(sbpl_z.ptr, &[_][]const u8{"/usr/bin/true"}, null, null, .inherit);
    var status: c_int = 0;
    _ = std.c.waitpid(child.pid, &status, 0);
    const exited = (status & 0x7f) == 0;
    try std.testing.expect(exited);
    const exit_code: u8 = @intCast((status >> 8) & 0xff);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
}

test "forkApplySeatbeltAndExec honors stdio ignore on macOS" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const sbpl =
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
    const sbpl_z = try std.testing.allocator.dupeZ(u8, sbpl);
    defer std.testing.allocator.free(sbpl_z);

    const child = try forkApplySeatbeltAndExec(
        sbpl_z.ptr,
        &[_][]const u8{ "/bin/sh", "-c", "echo should-not-appear-on-parent-stdout" },
        null,
        null,
        .ignore,
    );
    var status: c_int = 0;
    _ = std.c.waitpid(child.pid, &status, 0);
    try std.testing.expect((status & 0x7f) == 0);
    try std.testing.expectEqual(@as(u8, 0), @as(u8, @intCast((status >> 8) & 0xff)));
}

test "forkApplySeatbeltAndExec establishes process group leadership on macOS" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const sbpl =
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
    const sbpl_z = try std.testing.allocator.dupeZ(u8, sbpl);
    defer std.testing.allocator.free(sbpl_z);

    // After setpgid(0,0) in child, parent getpgid(pid) must equal pid (group leader).
    const child = try forkApplySeatbeltAndExec(
        sbpl_z.ptr,
        &[_][]const u8{ "/bin/sh", "-c", "sleep 0.15" },
        null,
        null,
        .ignore,
    );
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

    const sbpl =
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
    const sbpl_z = try std.testing.allocator.dupeZ(u8, sbpl);
    defer std.testing.allocator.free(sbpl_z);

    // With null env_map, PATH from parent must still be present (inherit).
    const child = try forkApplySeatbeltAndExec(
        sbpl_z.ptr,
        &[_][]const u8{ "/bin/sh", "-c", "test -n \"$PATH\"" },
        null,
        null,
        .ignore,
    );
    var status: c_int = 0;
    _ = std.c.waitpid(child.pid, &status, 0);
    try std.testing.expect((status & 0x7f) == 0);
    try std.testing.expectEqual(@as(u8, 0), @as(u8, @intCast((status >> 8) & 0xff)));
}

test "resolveArgv0 finds absolute and PATH binaries" {
    const abs = try resolveArgv0(std.testing.io, std.testing.allocator, "/bin/sh");
    try std.testing.expect(!abs.owned);
    try std.testing.expectEqualStrings("/bin/sh", abs.path);

    const via_path = resolveArgv0(std.testing.io, std.testing.allocator, "true") catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };
    defer if (via_path.owned) std.testing.allocator.free(via_path.path);
    try std.testing.expect(via_path.path.len > 0);
}
