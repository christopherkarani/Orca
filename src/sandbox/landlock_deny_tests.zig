//! Landlock real-FS deny and expand integration tests (M-8 extraction).
//! Imported from landlock.zig so production apply code stays scannable.

const std = @import("std");
const builtin = @import("builtin");
const profile = @import("profile.zig");
const landlock = @import("landlock.zig");

const applySelf = landlock.applySelf;
const buildChildLandlockPlan = landlock.buildChildLandlockPlan;
const probeAbi = landlock.probeAbi;
const verifyApplyInChild = landlock.verifyApplyInChild;

test "real FS deny: outside denied; neighbor RW; control root not writable" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    if (probeAbi() == null) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const linux = std.os.linux;

    var ws_tmp = std.testing.tmpDir(.{});
    defer ws_tmp.cleanup();
    try ws_tmp.dir.createDirPath(io, ".orca");
    try ws_tmp.dir.writeFile(io, .{ .sub_path = "neighbor.txt", .data = "WORKSPACE_NEIGHBOR_OK" });
    const ws_root = try ws_tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(ws_root);

    var out_tmp = std.testing.tmpDir(.{});
    defer out_tmp.cleanup();
    try out_tmp.dir.writeFile(io, .{ .sub_path = "canary.txt", .data = "OUTSIDE_SECRET" });
    const out_root = try out_tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(out_root);

    const canary_path = try std.fs.path.join(allocator, &.{ out_root, "canary.txt" });
    defer allocator.free(canary_path);
    const neighbor_path = try std.fs.path.join(allocator, &.{ ws_root, "neighbor.txt" });
    defer allocator.free(neighbor_path);
    const control_write = try std.fs.path.join(allocator, &.{ ws_root, ".orca", "policy.yaml" });
    defer allocator.free(control_write);

    // Production system RO defaults without temp RW (M-6; canaries live under tmpDir).
    var compiled = try profile.compileProfile(allocator, .{
        .workspace_root = ws_root,
        .system_ro_prefixes = profile.defaultSystemRoPrefixes(),
        .include_tmp = false,
    });
    defer compiled.deinit();
    try std.testing.expect(!compiled.isAgentWritable(canary_path));
    try std.testing.expect(compiled.isAgentWritable(neighbor_path));
    try std.testing.expect(!compiled.isAgentWritable(control_write));

    // Parent-side expand plan before fork (Z-3).
    var plan = try buildChildLandlockPlan(allocator, &compiled);
    defer plan.deinit();

    const pid_rc = linux.fork();
    if (linux.errno(pid_rc) != .SUCCESS) return error.SkipZigTest;
    if (pid_rc == 0) {
        applySelf(&compiled, &plan) catch linux.exit(2);

        // Outside canary must not be readable.
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        @memcpy(path_buf[0..canary_path.len], canary_path);
        path_buf[canary_path.len] = 0;
        const outside_fd = linux.open(path_buf[0..canary_path.len :0].ptr, .{ .CLOEXEC = true }, 0);
        if (linux.errno(outside_fd) == .SUCCESS) {
            _ = linux.close(@intCast(outside_fd));
            linux.exit(3);
        }

        // Neighbor readable.
        @memcpy(path_buf[0..neighbor_path.len], neighbor_path);
        path_buf[neighbor_path.len] = 0;
        const ws_fd = linux.open(path_buf[0..neighbor_path.len :0].ptr, .{ .CLOEXEC = true }, 0);
        if (linux.errno(ws_fd) != .SUCCESS) linux.exit(4);
        var buf: [64]u8 = undefined;
        const n = linux.read(@intCast(ws_fd), &buf, buf.len);
        _ = linux.close(@intCast(ws_fd));
        if (n != "WORKSPACE_NEIGHBOR_OK".len) linux.exit(4);

        // Neighbor write (PATH_BENEATH RW on the file).
        const wfd = linux.open(path_buf[0..neighbor_path.len :0].ptr, .{ .ACCMODE = .WRONLY, .CLOEXEC = true }, 0);
        if (linux.errno(wfd) != .SUCCESS) linux.exit(5);
        const wrote = linux.write(@intCast(wfd), "wrote!", 6);
        _ = linux.close(@intCast(wfd));
        if (wrote != 6) linux.exit(5);

        // Control root write must fail (M-1).
        @memcpy(path_buf[0..control_write.len], control_write);
        path_buf[control_write.len] = 0;
        const cfd = linux.open(
            path_buf[0..control_write.len :0].ptr,
            .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .CLOEXEC = true },
            0o600,
        );
        if (linux.errno(cfd) == .SUCCESS) {
            _ = linux.close(@intCast(cfd));
            linux.exit(6); // control write leak
        }

        // F-2: workspace root is listable (RO expand), but create-at-root is denied
        // (MAKE on parent would cover control trees).
        @memcpy(path_buf[0..ws_root.len], ws_root);
        path_buf[ws_root.len] = 0;
        const ws_dir_fd = linux.open(
            path_buf[0..ws_root.len :0].ptr,
            .{ .DIRECTORY = true, .CLOEXEC = true },
            0,
        );
        if (linux.errno(ws_dir_fd) != .SUCCESS) linux.exit(7);
        _ = linux.close(@intCast(ws_dir_fd));

        const suffix = "/new_at_root.txt";
        if (ws_root.len + suffix.len >= path_buf.len) linux.exit(8);
        @memcpy(path_buf[0..ws_root.len], ws_root);
        @memcpy(path_buf[ws_root.len..][0..suffix.len], suffix);
        const create_len = ws_root.len + suffix.len;
        path_buf[create_len] = 0;
        const new_fd = linux.open(
            path_buf[0..create_len :0].ptr,
            .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .CLOEXEC = true },
            0o600,
        );
        if (linux.errno(new_fd) == .SUCCESS) {
            _ = linux.close(@intCast(new_fd));
            linux.exit(8); // create-at-root should not gain MAKE on expanded parent
        }

        linux.exit(0);
    }

    const child_pid: i32 = @intCast(pid_rc);
    var status: u32 = 0;
    while (true) {
        const w = linux.waitpid(child_pid, &status, 0);
        if (linux.errno(w) == .INTR) continue;
        if (linux.errno(w) != .SUCCESS) return error.ApplyFailed;
        break;
    }
    if ((status & 0x7f) != 0) return error.ApplyFailed;
    const code = (status >> 8) & 0xff;
    switch (code) {
        0 => {},
        2 => return error.LandlockApplyFailedOnHost,
        3 => return error.OutsideCanaryReadableUnderSandbox,
        4 => return error.WorkspaceNeighborUnreadableUnderSandbox,
        5 => return error.WorkspaceWriteFailedUnderSandbox,
        6 => return error.ControlRootWritableUnderSandbox,
        7 => return error.WorkspaceRootUnlistableUnderExpand,
        8 => return error.CreateAtWorkspaceRootAllowedUnderExpand,
        else => return error.UnexpectedSandboxProbeExit,
    }
}

// M-1 / M-6: control expand installs RO on workspace root so chdir/list work,
// while MAKE/WRITE stay off the root. Create-at-workspace-root is therefore
// denied under Landlock (MAKE not on RO). Seatbelt may still allow create-at-root
// under full-subpath RW minus controls — intentional cross-platform semantic drift.
// Banner "workspace RW" remains honest when a child RW surface exists.
test "control expand: chdir workspace root works; create at root denied; control not writable" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    if (probeAbi() == null) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const linux = std.os.linux;

    var ws_tmp = std.testing.tmpDir(.{});
    defer ws_tmp.cleanup();
    try ws_tmp.dir.createDirPath(io, ".orca");
    try ws_tmp.dir.writeFile(io, .{ .sub_path = "neighbor.txt", .data = "NEIGHBOR" });
    const ws_root = try ws_tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(ws_root);

    const neighbor_path = try std.fs.path.join(allocator, &.{ ws_root, "neighbor.txt" });
    defer allocator.free(neighbor_path);
    const at_root_path = try std.fs.path.join(allocator, &.{ ws_root, "created_at_root.txt" });
    defer allocator.free(at_root_path);
    const control_write = try std.fs.path.join(allocator, &.{ ws_root, ".orca", "policy.yaml" });
    defer allocator.free(control_write);

    // Production system RO defaults without temp RW (M-6).
    var compiled = try profile.compileProfile(allocator, .{
        .workspace_root = ws_root,
        .system_ro_prefixes = profile.defaultSystemRoPrefixes(),
        .include_tmp = false,
    });
    defer compiled.deinit();

    var plan = try buildChildLandlockPlan(allocator, &compiled);
    defer plan.deinit();

    const pid_rc = linux.fork();
    if (linux.errno(pid_rc) != .SUCCESS) return error.SkipZigTest;
    if (pid_rc == 0) {
        applySelf(&compiled, &plan) catch linux.exit(2);

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        @memcpy(path_buf[0..ws_root.len], ws_root);
        path_buf[ws_root.len] = 0;
        // Root RO must allow search/chdir into the workspace (M-1).
        if (linux.chdir(path_buf[0..ws_root.len :0].ptr) != 0) linux.exit(7);

        // Create-at-root denied: root is RO (MAKE not granted). M-6 honesty.
        @memcpy(path_buf[0..at_root_path.len], at_root_path);
        path_buf[at_root_path.len] = 0;
        const create_fd = linux.open(
            path_buf[0..at_root_path.len :0].ptr,
            .{ .ACCMODE = .WRONLY, .CREAT = true, .EXCL = true, .CLOEXEC = true },
            0o600,
        );
        if (linux.errno(create_fd) == .SUCCESS) {
            _ = linux.close(@intCast(create_fd));
            linux.exit(8); // create-at-root leak vs documented Landlock model
        }

        // Child RW surface still works.
        @memcpy(path_buf[0..neighbor_path.len], neighbor_path);
        path_buf[neighbor_path.len] = 0;
        const wfd = linux.open(path_buf[0..neighbor_path.len :0].ptr, .{ .ACCMODE = .WRONLY, .CLOEXEC = true }, 0);
        if (linux.errno(wfd) != .SUCCESS) linux.exit(5);
        const wrote = linux.write(@intCast(wfd), "ok", 2);
        _ = linux.close(@intCast(wfd));
        if (wrote != 2) linux.exit(5);

        // Control root still not writable.
        @memcpy(path_buf[0..control_write.len], control_write);
        path_buf[control_write.len] = 0;
        const cfd = linux.open(
            path_buf[0..control_write.len :0].ptr,
            .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .CLOEXEC = true },
            0o600,
        );
        if (linux.errno(cfd) == .SUCCESS) {
            _ = linux.close(@intCast(cfd));
            linux.exit(6);
        }

        linux.exit(0);
    }

    const child_pid: i32 = @intCast(pid_rc);
    var status: u32 = 0;
    while (true) {
        const w = linux.waitpid(child_pid, &status, 0);
        if (linux.errno(w) == .INTR) continue;
        if (linux.errno(w) != .SUCCESS) return error.ApplyFailed;
        break;
    }
    if ((status & 0x7f) != 0) return error.ApplyFailed;
    const code = (status >> 8) & 0xff;
    switch (code) {
        0 => {},
        2 => return error.LandlockApplyFailedOnHost,
        5 => return error.WorkspaceWriteFailedUnderSandbox,
        6 => return error.ControlRootWritableUnderSandbox,
        7 => return error.WorkspaceChdirFailedUnderSandbox,
        8 => return error.CreateAtWorkspaceRootUnexpectedlyAllowed,
        else => return error.UnexpectedSandboxProbeExit,
    }
}

// M-3: planted workspace symlink to an outside path must not become a PATH_BENEATH
// RW/RO grant on the outside target (O_NOFOLLOW + skip .sym_link during expand).
test "symlink to outside is not granted by control expand" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    if (probeAbi() == null) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const linux = std.os.linux;

    var ws_tmp = std.testing.tmpDir(.{});
    defer ws_tmp.cleanup();
    try ws_tmp.dir.createDirPath(io, ".orca");
    try ws_tmp.dir.writeFile(io, .{ .sub_path = "neighbor.txt", .data = "NEIGHBOR" });
    const ws_root = try ws_tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(ws_root);

    var out_tmp = std.testing.tmpDir(.{});
    defer out_tmp.cleanup();
    try out_tmp.dir.writeFile(io, .{ .sub_path = "secret.txt", .data = "OUTSIDE_SECRET" });
    const out_root = try out_tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(out_root);

    const secret_path = try std.fs.path.join(allocator, &.{ out_root, "secret.txt" });
    defer allocator.free(secret_path);
    const link_path = try std.fs.path.join(allocator, &.{ ws_root, "escape_link" });
    defer allocator.free(link_path);

    // Plant ws/escape_link → outside secret (or outside dir).
    std.Io.Dir.cwd().symLink(io, secret_path, link_path, .{}) catch |err| switch (err) {
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };

    const neighbor_path = try std.fs.path.join(allocator, &.{ ws_root, "neighbor.txt" });
    defer allocator.free(neighbor_path);

    // Production system RO defaults without temp RW (M-6).
    var compiled = try profile.compileProfile(allocator, .{
        .workspace_root = ws_root,
        .system_ro_prefixes = profile.defaultSystemRoPrefixes(),
        .include_tmp = false,
    });
    defer compiled.deinit();

    var plan = try buildChildLandlockPlan(allocator, &compiled);
    defer plan.deinit();

    const pid_rc = linux.fork();
    if (linux.errno(pid_rc) != .SUCCESS) return error.SkipZigTest;
    if (pid_rc == 0) {
        applySelf(&compiled, &plan) catch linux.exit(2);

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;

        // Outside real path must not be readable under Landlock.
        @memcpy(path_buf[0..secret_path.len], secret_path);
        path_buf[secret_path.len] = 0;
        const out_fd = linux.open(path_buf[0..secret_path.len :0].ptr, .{ .CLOEXEC = true }, 0);
        if (linux.errno(out_fd) == .SUCCESS) {
            _ = linux.close(@intCast(out_fd));
            linux.exit(3);
        }

        // Via the workspace symlink: also must not grant outside target.
        @memcpy(path_buf[0..link_path.len], link_path);
        path_buf[link_path.len] = 0;
        const link_fd = linux.open(path_buf[0..link_path.len :0].ptr, .{ .CLOEXEC = true }, 0);
        if (linux.errno(link_fd) == .SUCCESS) {
            _ = linux.close(@intCast(link_fd));
            linux.exit(9); // symlink escape: outside readable via planted link
        }
        // Write via link must fail too.
        const link_w = linux.open(
            path_buf[0..link_path.len :0].ptr,
            .{ .ACCMODE = .WRONLY, .CLOEXEC = true },
            0,
        );
        if (linux.errno(link_w) == .SUCCESS) {
            _ = linux.close(@intCast(link_w));
            linux.exit(10);
        }

        // Usable child RW still present (neighbor).
        @memcpy(path_buf[0..neighbor_path.len], neighbor_path);
        path_buf[neighbor_path.len] = 0;
        const nfd = linux.open(path_buf[0..neighbor_path.len :0].ptr, .{ .CLOEXEC = true }, 0);
        if (linux.errno(nfd) != .SUCCESS) linux.exit(4);
        _ = linux.close(@intCast(nfd));

        linux.exit(0);
    }

    const child_pid: i32 = @intCast(pid_rc);
    var status: u32 = 0;
    while (true) {
        const w = linux.waitpid(child_pid, &status, 0);
        if (linux.errno(w) == .INTR) continue;
        if (linux.errno(w) != .SUCCESS) return error.ApplyFailed;
        break;
    }
    if ((status & 0x7f) != 0) return error.ApplyFailed;
    const code = (status >> 8) & 0xff;
    switch (code) {
        0 => {},
        2 => return error.LandlockApplyFailedOnHost,
        3 => return error.OutsideCanaryReadableUnderSandbox,
        4 => return error.WorkspaceNeighborUnreadableUnderSandbox,
        9 => return error.SymlinkEscapeReadableUnderSandbox,
        10 => return error.SymlinkEscapeWritableUnderSandbox,
        else => return error.UnexpectedSandboxProbeExit,
    }
}

test "never claims network landlock in public constants" {
    try std.testing.expect(@hasDecl(landlock, "handledFsRights"));
    try std.testing.expect(!@hasDecl(landlock, "handledNetRights"));
    try std.testing.expect(!@hasDecl(landlock, "ACCESS_NET_BIND_TCP"));
}
