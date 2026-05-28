const std = @import("std");

pub const ResolveOptions = struct {
    workspace_root: []const u8,
    resource_root_override: ?[]const u8 = null,
};

pub fn resolveResourcePath(allocator: std.mem.Allocator, options: ResolveOptions, relative_path: []const u8) ![]u8 {
    const workspace_candidate = try std.fs.path.join(allocator, &.{ options.workspace_root, relative_path });
    if (pathExists(workspace_candidate)) return workspace_candidate;
    allocator.free(workspace_candidate);

    if (options.resource_root_override) |resource_root| {
        const candidate = try std.fs.path.join(allocator, &.{ resource_root, relative_path });
        if (pathExists(candidate)) return candidate;
        allocator.free(candidate);
    } else if (std.process.getEnvVarOwned(allocator, "ORCA_RESOURCE_ROOT")) |resource_root| {
        defer allocator.free(resource_root);
        const candidate = try std.fs.path.join(allocator, &.{ resource_root, relative_path });
        if (pathExists(candidate)) return candidate;
        allocator.free(candidate);
    } else |err| switch (err) {
        error.EnvironmentVariableNotFound => {},
        else => return err,
    }

    const exe_path = std.fs.selfExePathAlloc(allocator) catch |err| switch (err) {
        error.FileNotFound, error.NameTooLong, error.AccessDenied => return error.ResourceNotFound,
        else => return err,
    };
    defer allocator.free(exe_path);
    if (std.fs.path.dirname(exe_path)) |exe_dir| {
        const candidate = try std.fs.path.join(allocator, &.{ exe_dir, "..", relative_path });
        if (pathExists(candidate)) return candidate;
        allocator.free(candidate);

        const source_build_candidate = try std.fs.path.join(allocator, &.{ exe_dir, "..", "..", relative_path });
        if (pathExists(source_build_candidate)) return source_build_candidate;
        allocator.free(source_build_candidate);

        // Strong improvement for non-interactive / container / CI usage:
        // The standard layout produced by our curl|sh installer (and recommended
        // by doctor/Homebrew) places the binary at $PREFIX/bin/orca and assets at
        // $PREFIX/share/orca/current. Auto-discover this when no explicit
        // ORCA_RESOURCE_ROOT is set. This makes `sh -c 'orca redteam --ci'` work
        // out of the box after a fresh install in many environments.
        if (std.fs.path.dirname(exe_dir)) |prefix_dir| {
            const packaged = try std.fs.path.join(allocator, &.{ prefix_dir, "share", "orca", "current", relative_path });
            if (pathExists(packaged)) return packaged;
            allocator.free(packaged);
        }
    }

    return error.ResourceNotFound;
}

pub fn resourcePathExists(allocator: std.mem.Allocator, options: ResolveOptions, relative_path: []const u8) bool {
    const resolved = resolveResourcePath(allocator, options, relative_path) catch return false;
    allocator.free(resolved);
    return true;
}

fn pathExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

test "resource resolver falls back to explicit resource root" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("workspace");
    try tmp.dir.makePath("resources/fixtures");

    const workspace_root = try tmp.dir.realpathAlloc(std.testing.allocator, "workspace");
    defer std.testing.allocator.free(workspace_root);
    const resource_root = try tmp.dir.realpathAlloc(std.testing.allocator, "resources");
    defer std.testing.allocator.free(resource_root);

    const resolved = try resolveResourcePath(std.testing.allocator, .{
        .workspace_root = workspace_root,
        .resource_root_override = resource_root,
    }, "fixtures");
    defer std.testing.allocator.free(resolved);

    try std.testing.expect(std.mem.endsWith(u8, resolved, "resources/fixtures"));
}

test "resource resolver prefers workspace resources" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("workspace/fixtures");
    try tmp.dir.makePath("resources/fixtures");

    const workspace_root = try tmp.dir.realpathAlloc(std.testing.allocator, "workspace");
    defer std.testing.allocator.free(workspace_root);
    const resource_root = try tmp.dir.realpathAlloc(std.testing.allocator, "resources");
    defer std.testing.allocator.free(resource_root);

    const resolved = try resolveResourcePath(std.testing.allocator, .{
        .workspace_root = workspace_root,
        .resource_root_override = resource_root,
    }, "fixtures");
    defer std.testing.allocator.free(resolved);

    try std.testing.expect(std.mem.indexOf(u8, resolved, "workspace") != null);
}
