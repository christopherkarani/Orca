const std = @import("std");
const builtin = @import("builtin");

const platform = @import("orca_core").platform;
const backend = @import("backend.zig");

pub const implemented = true;

const CLONE_NEWNS: usize = 0x00020000;
const CLONE_NEWUSER: usize = 0x10000000;
const LANDLOCK_CREATE_RULESET_VERSION: usize = 1;

pub fn detect() backend.ReportSet {
    var reports = backend.baseReports(.linux);
    backend.setReport(&reports, .process_supervision, .active, "Linux process-group supervision and best-effort descendant cleanup are enabled");

    const user_namespace = detectUserNamespace();
    backend.setReport(&reports, .user_namespaces, user_namespace.level, user_namespace.note);

    const mount_namespace = detectMountNamespace(user_namespace.level);
    backend.setReport(&reports, .mount_namespaces, mount_namespace.level, mount_namespace.note);

    const seccomp = detectSeccomp();
    backend.setReport(&reports, .seccomp, seccomp.level, seccomp.note);

    const landlock = detectLandlock();
    backend.setReport(&reports, .landlock, landlock.level, landlock.note);

    const cgroups = detectCgroups();
    backend.setReport(&reports, .cgroups, cgroups.level, cgroups.note);

    const strong_level: backend.Level = .unavailable;
    backend.setReport(&reports, .strong_sandbox, strong_level, "no namespace, seccomp, or Landlock restrictions are installed by this backend");

    return .{
        .os = .linux,
        .backend_name = "linux",
        .fallback_level = .partial,
        .fallback_note = "Linux backend is using honest partial mode with wrapper controls plus process supervision",
        .reports = reports,
    };
}

pub fn prepare(allocator: std.mem.Allocator, request: backend.PrepareRequest, report: backend.ReportSet) backend.PreparedSandbox {
    var prepared = backend.prepareFallback(allocator, request, report);
    if (builtin.os.tag == .linux) {
        prepared.child.pgid = 0;
        prepared.process_group_cleanup = true;
    }
    return prepared;
}

pub fn killProcessGroup(pgid: i32) void {
    if (builtin.os.tag != .linux) return;
    if (pgid <= 0) return;
    std.posix.kill(-pgid, std.os.linux.SIG.TERM) catch {};
    std.Thread.sleep(50 * std.time.ns_per_ms);
    std.posix.kill(-pgid, std.os.linux.SIG.KILL) catch {};
}

const Probe = struct {
    level: backend.Level,
    note: []const u8,
};

fn detectUserNamespace() Probe {
    if (builtin.os.tag != .linux) return .{ .level = .unsupported, .note = "not running on Linux" };
    if (!pathExists("/proc/self/ns/user")) {
        return .{ .level = .unavailable, .note = "kernel user namespace handle is absent" };
    }
    if (readProcToggle("/proc/sys/kernel/unprivileged_userns_clone")) |enabled| {
        if (!enabled) return .{ .level = .unavailable, .note = "unprivileged user namespaces are disabled by kernel policy" };
    }
    return .{ .level = .partial, .note = "kernel support detected; rootless namespace activation is not enabled by default in this backend" };
}

fn detectMountNamespace(user_namespace_level: backend.Level) Probe {
    if (builtin.os.tag != .linux) return .{ .level = .unsupported, .note = "not running on Linux" };
    if (!pathExists("/proc/self/ns/mnt")) {
        return .{ .level = .unavailable, .note = "kernel mount namespace handle is absent" };
    }
    if (!user_namespace_level.isUsable()) {
        return .{ .level = .unavailable, .note = "mount namespaces exist, but rootless setup depends on unavailable user namespaces" };
    }
    return .{ .level = .partial, .note = "kernel support detected; no bind-mount/chroot filesystem view is installed in this phase" };
}

fn detectSeccomp() Probe {
    if (builtin.os.tag != .linux) return .{ .level = .unsupported, .note = "not running on Linux" };
    const linux = std.os.linux;
    var action: u32 = linux.SECCOMP.RET.ALLOW;
    const rc = linux.seccomp(linux.SECCOMP.GET_ACTION_AVAIL, 0, &action);
    return switch (std.posix.errno(rc)) {
        .SUCCESS => .{ .level = .partial, .note = "seccomp-bpf API is available; no restrictive filter is installed by this backend" },
        .NOSYS => .{ .level = .unavailable, .note = "seccomp syscall is unavailable" },
        .OPNOTSUPP => .{ .level = .unavailable, .note = "seccomp action probing is unsupported by this kernel" },
        .ACCES, .PERM => .{ .level = .unavailable, .note = "seccomp probing denied by the current runtime" },
        else => .{ .level = .failed, .note = "seccomp probing failed" },
    };
}

fn detectLandlock() Probe {
    if (builtin.os.tag != .linux) return .{ .level = .unsupported, .note = "not running on Linux" };
    const linux = std.os.linux;
    const rc = linux.syscall3(.landlock_create_ruleset, 0, 0, LANDLOCK_CREATE_RULESET_VERSION);
    return switch (std.posix.errno(rc)) {
        .SUCCESS => .{ .level = .partial, .note = "Landlock ABI is available; no ruleset is installed by this backend" },
        .NOSYS => .{ .level = .unavailable, .note = "Landlock syscalls are unavailable" },
        .OPNOTSUPP, .INVAL => .{ .level = .unavailable, .note = "Landlock ABI probing is unsupported by this kernel" },
        .ACCES, .PERM => .{ .level = .unavailable, .note = "Landlock probing denied by the current runtime" },
        else => .{ .level = .failed, .note = "Landlock probing failed" },
    };
}

fn detectCgroups() Probe {
    if (builtin.os.tag != .linux) return .{ .level = .unsupported, .note = "not running on Linux" };
    if (!pathExists("/sys/fs/cgroup/cgroup.controllers")) {
        return .{ .level = .unavailable, .note = "cgroup v2 controllers file is absent" };
    }
    return .{ .level = .partial, .note = "cgroup v2 is visible; Orca does not create or manage a cleanup cgroup in this phase" };
}

fn pathExists(path: []const u8) bool {
    std.fs.accessAbsolute(path, .{}) catch return false;
    return true;
}

fn readProcToggle(path: []const u8) ?bool {
    var buf: [8]u8 = undefined;
    const file = std.fs.openFileAbsolute(path, .{}) catch return null;
    defer file.close();
    const len = file.readAll(&buf) catch return null;
    const trimmed = std.mem.trim(u8, buf[0..len], " \t\r\n");
    if (std.mem.eql(u8, trimmed, "1")) return true;
    if (std.mem.eql(u8, trimmed, "0")) return false;
    return null;
}

test "Linux capability detector is target-gated and honest" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const report = detect();
    try std.testing.expectEqual(platform.Os.linux, report.os);
    try std.testing.expectEqualStrings("linux", report.backend_name);
    try std.testing.expectEqual(backend.Level.active, report.get(.process_supervision).level);
    try std.testing.expect(report.get(.network_enforce).level != .active);
    try std.testing.expectEqual(backend.Level.unavailable, report.get(.strong_sandbox).level);
    try std.testing.expect(!report.featureAvailable(.strong_sandbox));
}

test "Linux fallback launch can run a simple command" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    var argv = [_][]const u8{ "true" };
    var prepared = prepare(std.testing.allocator, .{
        .argv = &argv,
        .workspace_root = ".",
        .stdio = .ignore,
    }, detect());
    try prepared.spawn();
    try prepared.waitForSpawn();
    const term = try prepared.wait();
    try std.testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, term);
}

test "Linux process supervision uses process group cleanup" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    var argv = [_][]const u8{ "true" };
    const prepared = prepare(std.testing.allocator, .{
        .argv = &argv,
        .workspace_root = ".",
        .stdio = .ignore,
    }, detect());
    try std.testing.expect(prepared.process_group_cleanup);
}

test "Linux process supervision cleans up same-process-group descendants" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    var argv = [_][]const u8{ "/bin/sh", "-c", "sleep 30 & echo $! > child.pid" };
    var prepared = prepare(std.testing.allocator, .{
        .argv = &argv,
        .workspace_root = root,
        .stdio = .ignore,
    }, detect());
    try prepared.spawn();
    try prepared.waitForSpawn();
    const term = try prepared.wait();
    try std.testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, term);

    const pid_text = try tmp.dir.readFileAlloc(std.testing.allocator, "child.pid", 64);
    defer std.testing.allocator.free(pid_text);
    const pid = try std.fmt.parseInt(std.posix.pid_t, std.mem.trim(u8, pid_text, " \t\r\n"), 10);
    std.Thread.sleep(100 * std.time.ns_per_ms);
    std.posix.kill(pid, 0) catch |err| switch (err) {
        error.ProcessNotFound => return,
        else => return err,
    };
    return error.ProcessTreeCleanupFailed;
}
