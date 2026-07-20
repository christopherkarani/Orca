//! POSIX fork → OS-FS apply → exec helper (U05/U07).
//!
//! Parent Orca stays free. Child installs Landlock (Linux) or Seatbelt (macOS)
//! then execs the agent. FD scrub runs in the child after apply, before exec.
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

/// Result of a successful parent-side fork (child is applying/execing).
pub const ChildPid = struct {
    pid: i32,
};

/// Fork, apply Landlock in the child from `compiled`, scrub FDs, then execve.
///
/// On success the parent receives the child pid; the child never returns.
/// Pre-fork: argv[0] must be an absolute path or resolvable; env is raw envp.
///
/// Linux only. Does not apply network Landlock.
pub fn forkApplyLandlockAndExec(
    compiled: *const profile.CompiledProfile,
    argv: []const []const u8,
    env_map: ?*const std.process.Environ.Map,
    cwd: ?[]const u8,
) SpawnError!ChildPid {
    if (builtin.os.tag != .linux) return error.Unsupported;
    if (argv.len == 0) return error.ExecFailed;
    return forkApplyLandlockAndExecLinux(compiled, argv, env_map, cwd);
}

/// Fork, apply Seatbelt SBPL in the child, scrub FDs, then execve.
///
/// macOS only. `sbpl_z` must remain valid until the child has exec'd (parent
/// retains ownership — typically until process exit for a one-shot launch).
pub fn forkApplySeatbeltAndExec(
    sbpl_z: [*:0]const u8,
    argv: []const []const u8,
    env_map: ?*const std.process.Environ.Map,
    cwd: ?[]const u8,
) SpawnError!ChildPid {
    if (builtin.os.tag != .macos) return error.Unsupported;
    if (argv.len == 0) return error.ExecFailed;
    return forkApplySeatbeltAndExecMacOs(sbpl_z, argv, env_map, cwd);
}

/// Verify Landlock can apply for this profile without boxing the parent.
/// Thin wrapper over landlock.verifyApplyInChild for the apply seam.
pub fn verifyLandlockApplyInChild(compiled: *const profile.CompiledProfile) landlock.ApplyError!void {
    try landlock.verifyApplyInChild(compiled);
}

fn forkApplyLandlockAndExecLinux(
    compiled: *const profile.CompiledProfile,
    argv: []const []const u8,
    env_map: ?*const std.process.Environ.Map,
    cwd: ?[]const u8,
) SpawnError!ChildPid {
    const linux = std.os.linux;

    // Allocate argv/env in the parent before fork. After a successful fork the
    // parent must not free them until the child has exec'd (munmap races).
    // For a one-shot agent launch we deliberately retain until process exit.
    const argv_z = try allocArgvZ(std.heap.page_allocator, argv);
    errdefer freeArgvZ(std.heap.page_allocator, argv_z);
    const envp_z = try allocEnvpZ(std.heap.page_allocator, env_map);
    errdefer freeEnvpZ(std.heap.page_allocator, envp_z);
    const cwd_z: ?[:0]const u8 = if (cwd) |c|
        (std.heap.page_allocator.dupeZ(u8, c) catch return error.OutOfMemory)
    else
        null;
    errdefer if (cwd_z) |z| std.heap.page_allocator.free(z);

    const pid_rc = linux.fork();
    if (linux.errno(pid_rc) != .SUCCESS) return error.ForkFailed;

    if (pid_rc == 0) {
        // Child path — apply, scrub, exec. On any failure exit non-zero.
        landlock.applySelf(compiled) catch {
            linux.exit(127);
        };
        fd_scrub.closeInheritedFdsDefault();

        if (cwd_z) |z| {
            if (linux.chdir(z.ptr) != 0) linux.exit(127);
        }

        const path = argv_z[0] orelse {
            linux.exit(127);
        };
        _ = linux.execve(path, argv_z.ptr, envp_z.ptr);
        linux.exit(127);
    }

    // Successful fork: disarm errdefers by "forgetting" free (child still needs
    // the buffers until execve replaces the address space).
    return .{ .pid = @intCast(pid_rc) };
}

fn forkApplySeatbeltAndExecMacOs(
    sbpl_z: [*:0]const u8,
    argv: []const []const u8,
    env_map: ?*const std.process.Environ.Map,
    cwd: ?[]const u8,
) SpawnError!ChildPid {
    const argv_z = try allocArgvZ(std.heap.page_allocator, argv);
    errdefer freeArgvZ(std.heap.page_allocator, argv_z);
    const envp_z = try allocEnvpZ(std.heap.page_allocator, env_map);
    errdefer freeEnvpZ(std.heap.page_allocator, envp_z);
    const cwd_z: ?[:0]const u8 = if (cwd) |c|
        (std.heap.page_allocator.dupeZ(u8, c) catch return error.OutOfMemory)
    else
        null;
    errdefer if (cwd_z) |z| std.heap.page_allocator.free(z);

    const pid = std.c.fork();
    if (pid < 0) return error.ForkFailed;

    if (pid == 0) {
        macos_seatbelt.applyInChild(sbpl_z) catch {
            std.c._exit(127);
        };
        fd_scrub.closeInheritedFdsDefault();

        if (cwd_z) |z| {
            if (std.c.chdir(z.ptr) != 0) std.c._exit(127);
        }

        const path = argv_z[0] orelse {
            std.c._exit(127);
        };
        _ = std.c.execve(path, @ptrCast(argv_z.ptr), @ptrCast(envp_z.ptr));
        std.c._exit(127);
    }

    return .{ .pid = pid };
}

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

fn allocEnvpZ(allocator: std.mem.Allocator, env_map: ?*const std.process.Environ.Map) SpawnError![:null]?[*:0]const u8 {
    if (env_map == null) {
        // Inherit empty env block (caller usually passes scrubbed map).
        var list = allocator.alloc(?[*:0]const u8, 1) catch return error.OutOfMemory;
        list[0] = null;
        return list[0..0 :null];
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
    return list[0..count :null];
}

fn freeEnvpZ(allocator: std.mem.Allocator, envp_z: [:null]?[*:0]const u8) void {
    for (envp_z) |p| {
        if (p) |z| allocator.free(std.mem.span(z));
    }
    const base: [*]?[*:0]const u8 = @ptrCast(envp_z.ptr);
    allocator.free(base[0 .. envp_z.len + 1]);
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
    ));
}

test "forkApplySeatbeltAndExec is unsupported off macOS" {
    if (builtin.os.tag == .macos) return error.SkipZigTest;
    try std.testing.expectError(error.Unsupported, forkApplySeatbeltAndExec(
        "(version 1)\x00",
        &[_][]const u8{"/bin/true"},
        null,
        null,
    ));
}

test "forkApplySeatbeltAndExec applies then execs on macOS" {
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
    const child = try forkApplySeatbeltAndExec(sbpl_z.ptr, &[_][]const u8{"/usr/bin/true"}, null, null);
    var status: c_int = 0;
    _ = std.c.waitpid(child.pid, &status, 0);
    const exited = (status & 0x7f) == 0;
    try std.testing.expect(exited);
    const exit_code: u8 = @intCast((status >> 8) & 0xff);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
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
