//! POSIX fork → OS-FS apply → exec helper (U05).
//!
//! Parent Orca stays free. Child installs Landlock (Linux) then execs the agent.
//! FD scrub runs in the child after apply, before exec.
//!
//! Non-Linux: helpers return Unsupported (Seatbelt is U06).

const std = @import("std");
const builtin = @import("builtin");
const profile = @import("profile.zig");
const landlock = @import("landlock.zig");
const fd_scrub = @import("fd_scrub.zig");

pub const SpawnError = error{
    Unsupported,
    ForkFailed,
    ApplyFailed,
    ExecFailed,
    OutOfMemory,
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
) SpawnError!ChildPid {
    if (builtin.os.tag != .linux) return error.Unsupported;
    if (argv.len == 0) return error.ExecFailed;
    return forkApplyLandlockAndExecLinux(compiled, argv, env_map);
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
) SpawnError!ChildPid {
    const linux = std.os.linux;

    // Allocate argv/env pointers in the parent (no malloc after fork).
    // Allocate argv/env in the parent before fork. After a successful fork the
    // parent must not free them until the child has exec'd (munmap races).
    // For a one-shot agent launch we deliberately retain until process exit.
    const argv_z = try allocArgvZ(std.heap.page_allocator, argv);
    errdefer freeArgvZ(std.heap.page_allocator, argv_z);
    const envp_z = try allocEnvpZ(std.heap.page_allocator, env_map);
    errdefer freeEnvpZ(std.heap.page_allocator, envp_z);

    const pid_rc = linux.fork();
    if (linux.errno(pid_rc) != .SUCCESS) return error.ForkFailed;

    if (pid_rc == 0) {
        // Child path — apply, scrub, exec. On any failure exit non-zero.
        landlock.applySelf(compiled) catch {
            linux.exit(127);
        };
        fd_scrub.closeInheritedFdsDefault();

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
    allocator.free(@as([]?[*:0]const u8, @ptrCast(argv_z.ptr))[0 .. argv_z.len + 1]);
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
    allocator.free(@as([]?[*:0]const u8, @ptrCast(envp_z.ptr))[0 .. envp_z.len + 1]);
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
    ));
}
