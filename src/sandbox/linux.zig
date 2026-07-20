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

    // Strong sandbox: Landlock capability probe only. Session active only after child apply-before-exec attach.
    // Never claim "not wired" — production apply path is live; detect is not a live session claim (S-GLO-01).
    const strong_level: backend.Level = switch (landlock.level) {
        .partial, .active, .limited => .partial,
        .failed => .failed,
        .unavailable, .unsupported, .observe_only, .wrapper_only => .unavailable,
    };
    const strong_note: []const u8 = switch (landlock.level) {
        .partial, .active, .limited => "OS filesystem sandbox API present; session active only after apply-before-exec child attach and profile hash",
        .failed => "OS filesystem sandbox unavailable: Landlock probing failed; capability probes are not a live session claim",
        .unavailable, .unsupported, .observe_only, .wrapper_only => "OS filesystem sandbox unavailable; capability probes are not a live session claim",
    };
    backend.setReport(&reports, .strong_sandbox, strong_level, strong_note);

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
        prepared.use_process_group = true;
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
        .SUCCESS => .{ .level = .partial, .note = "Landlock ABI is available; session active only after child apply-before-exec" },
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
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    std.Io.Dir.accessAbsolute(io, path, .{}) catch return false;
    return true;
}

fn readProcToggle(path: []const u8) ?bool {
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    var buf: [8]u8 = undefined;
    const file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch return null;
    defer file.close(io);
    const len = std.Io.File.readStreaming(file, io, &.{buf[0..]}) catch return null;
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
    // strong_sandbox never active from detect (S-GLO-01); partial only when Landlock API present.
    try std.testing.expect(report.get(.strong_sandbox).level != .active);
    try std.testing.expect(!report.featureAvailable(.strong_sandbox));
    try std.testing.expect(std.mem.indexOf(u8, report.get(.strong_sandbox).note, "not wired") == null);
    switch (report.get(.landlock).level) {
        .partial, .active, .limited => try std.testing.expectEqual(backend.Level.partial, report.get(.strong_sandbox).level),
        .failed => try std.testing.expectEqual(backend.Level.failed, report.get(.strong_sandbox).level),
        else => try std.testing.expectEqual(backend.Level.unavailable, report.get(.strong_sandbox).level),
    }
}

test "Linux fallback launch can run a simple command" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    var argv = [_][]const u8{"true"};
    var prepared = prepare(std.testing.allocator, .{
        .io = std.testing.io,
        .argv = &argv,
        .workspace_root = ".",
        .stdio = .ignore,
    }, detect());
    try prepared.spawn();
    try prepared.waitForSpawn();
    const term = try prepared.wait();
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, term);
}

test "Linux process supervision uses process group cleanup" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    var argv = [_][]const u8{"true"};
    const prepared = prepare(std.testing.allocator, .{
        .io = std.testing.io,
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
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var argv = [_][]const u8{ "/bin/sh", "-c", "sleep 30 & echo $! > child.pid" };
    var prepared = prepare(std.testing.allocator, .{
        .io = std.testing.io,
        .argv = &argv,
        .workspace_root = root,
        .stdio = .ignore,
    }, detect());
    try prepared.spawn();
    try prepared.waitForSpawn();
    const term = try prepared.wait();
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, term);

    const pid_text = try tmp.dir.readFileAlloc(std.testing.io, "child.pid", std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(pid_text);
    const pid = try std.fmt.parseInt(std.posix.pid_t, std.mem.trim(u8, pid_text, " \t\r\n"), 10);
    std.Io.sleep(std.testing.io, std.Io.Duration.fromNanoseconds(100 * std.time.ns_per_ms), .awake) catch {};
    std.posix.kill(pid, @enumFromInt(0)) catch |err| switch (err) {
        error.ProcessNotFound => return,
        else => return err,
    };
    return error.ProcessTreeCleanupFailed;
}
