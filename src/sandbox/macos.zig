const std = @import("std");
const builtin = @import("builtin");

const backend = @import("backend.zig");
const platform = @import("orca_core").platform;

pub const implemented = true;

pub fn detect() backend.ReportSet {
    var reports = backend.baseReports(.macos);
    backend.setReport(&reports, .process_supervision, .active, "macOS child process-group supervision and best-effort descendant cleanup are enabled");
    backend.setReport(&reports, .shell_wrapping, .wrapper_only, "sh, bash, and zsh are wrapped when resolved through the Orca shim PATH");
    backend.setReport(&reports, .path_shims, .wrapper_only, "Orca prepends session shims to PATH for wrapper-mediated command checks");
    backend.setReport(&reports, .network_observe, .observe_only, "network policy decisions are audited for Orca-mediated actions");
    backend.setReport(&reports, .network_enforce, .limited, "transparent macOS network enforcement is not installed; only wrapper/proxy-mediated hooks are available");
    backend.setReport(&reports, .user_namespaces, .unsupported, "Linux user namespaces are not a macOS feature");
    backend.setReport(&reports, .mount_namespaces, .unsupported, "Linux mount namespaces are not a macOS feature");
    backend.setReport(&reports, .seccomp, .unsupported, "Linux seccomp-bpf is not a macOS feature");
    backend.setReport(&reports, .landlock, .unsupported, "Linux Landlock is not a macOS feature");
    backend.setReport(&reports, .cgroups, .unsupported, "Linux cgroup cleanup is not a macOS feature");
    backend.setReport(&reports, .strong_sandbox, .unavailable, "OS filesystem sandbox not active: apply-before-exec is not wired on the production launch path; capability probes are not a live session claim");

    return .{
        .os = .macos,
        .backend_name = "macos",
        .fallback_level = .partial,
        .fallback_note = "macOS backend uses practical local wrapper controls, staging, env filtering, MCP proxying, audit, and process supervision",
        .reports = reports,
    };
}

pub fn prepare(allocator: std.mem.Allocator, request: backend.PrepareRequest, report: backend.ReportSet) backend.PreparedSandbox {
    var prepared = backend.prepareFallback(allocator, request, report);
    if (builtin.os.tag == .macos) {
        prepared.use_process_group = true;
        prepared.process_group_cleanup = true;
    }
    return prepared;
}

test "macOS capability detector is honest about wrapper and unavailable protections" {
    const report = detect();
    try std.testing.expectEqual(platform.Os.macos, report.os);
    try std.testing.expectEqualStrings("macos", report.backend_name);
    try std.testing.expectEqual(backend.Level.active, report.get(.env_filtering).level);
    try std.testing.expectEqual(backend.Level.active, report.get(.path_staging).level);
    try std.testing.expectEqual(backend.Level.wrapper_only, report.get(.shell_wrapping).level);
    try std.testing.expectEqual(backend.Level.wrapper_only, report.get(.path_shims).level);
    try std.testing.expectEqual(backend.Level.active, report.get(.process_supervision).level);
    try std.testing.expectEqual(backend.Level.limited, report.get(.network_enforce).level);
    try std.testing.expectEqual(backend.Level.unavailable, report.get(.strong_sandbox).level);
    try std.testing.expect(!report.featureAvailable(.strong_sandbox));
}

test "macOS launch can run a simple command" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

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

test "macOS process supervision uses process group cleanup" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    var argv = [_][]const u8{"true"};
    const prepared = prepare(std.testing.allocator, .{
        .io = std.testing.io,
        .argv = &argv,
        .workspace_root = ".",
        .stdio = .ignore,
    }, detect());
    try std.testing.expect(prepared.process_group_cleanup);
}

test "macOS process supervision cleans up same-process-group descendants" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

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
    var attempts: usize = 0;
    while (attempts < 20) : (attempts += 1) {
        std.Io.sleep(std.testing.io, std.Io.Duration.fromNanoseconds(50 * std.time.ns_per_ms), .awake) catch {};
        std.posix.kill(pid, @enumFromInt(0)) catch |err| switch (err) {
            error.ProcessNotFound => return,
            else => return err,
        };
    }
    return error.ProcessTreeCleanupFailed;
}
