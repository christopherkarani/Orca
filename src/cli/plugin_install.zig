const std = @import("std");
const core = @import("orca_core").core;
const supervisor = core.supervisor;

pub const MarketplaceHost = enum { codex, claude };

pub const MarketplaceHostInstall = struct {
    host_label: []const u8,
    plugin_dest: []const u8,
    marketplace_path: []const u8,
    marketplace_json: []const u8,
};

pub fn resolveWorkspaceInstallRoot(allocator: std.mem.Allocator) ![]u8 {
    return supervisor.resolveWorkspaceRoot(allocator, null, ".") catch try std.fs.cwd().realpathAlloc(allocator, ".");
}

pub fn marketplaceHostInstallSpec(
    allocator: std.mem.Allocator,
    workspace_root: []const u8,
    target: MarketplaceHost,
    marketplace_json: []const u8,
) !MarketplaceHostInstall {
    return switch (target) {
        .codex => .{
            .host_label = "Codex",
            .plugin_dest = try std.fs.path.join(allocator, &.{ workspace_root, ".agents", "plugins", "orca" }),
            .marketplace_path = try std.fs.path.join(allocator, &.{ workspace_root, ".agents", "plugins", "marketplace.json" }),
            .marketplace_json = marketplace_json,
        },
        .claude => .{
            .host_label = "Claude Code",
            .plugin_dest = try std.fs.path.join(allocator, &.{ workspace_root, ".claude", "plugins", "orca" }),
            .marketplace_path = try std.fs.path.join(allocator, &.{ workspace_root, ".claude-plugin", "marketplace.json" }),
            .marketplace_json = marketplace_json,
        },
    };
}

pub fn loadMarketplaceTemplate(
    allocator: std.mem.Allocator,
    template_path: []const u8,
    bundled_source_path: []const u8,
    install_source_path: []const u8,
) ![]u8 {
    const template = try std.fs.cwd().readFileAlloc(allocator, template_path, 64 * 1024);
    errdefer allocator.free(template);
    if (std.mem.indexOf(u8, template, bundled_source_path) == null) return error.TemplatePathMissing;
    const rewritten = try std.mem.replaceOwned(u8, allocator, template, bundled_source_path, install_source_path);
    allocator.free(template);
    return rewritten;
}

pub fn installTextIfSafe(allocator: std.mem.Allocator, content: []const u8, destination_path: []const u8, allow_upgrade: bool) !bool {
    if (fileExistsAbsolute(destination_path)) {
        const same = try filesEqualText(allocator, content, destination_path);
        if (same) return false;
        if (!allow_upgrade) return error.RefusingToOverwriteDifferentFile;
        try std.fs.cwd().deleteFile(destination_path);
    }
    const parent = std.fs.path.dirname(destination_path) orelse return error.InvalidPath;
    try std.fs.cwd().makePath(parent);
    try std.fs.cwd().writeFile(.{ .sub_path = destination_path, .data = content, .flags = .{ .exclusive = true } });
    return true;
}

pub fn filesEqualText(allocator: std.mem.Allocator, expected: []const u8, path: []const u8) !bool {
    const actual = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(actual);
    return std.mem.eql(u8, expected, actual);
}

pub fn installDirectoryIfSafe(allocator: std.mem.Allocator, source_dir: []const u8, destination_dir: []const u8, allow_upgrade: bool) !void {
    if (dirExists(destination_dir)) {
        const same = directoriesEquivalent(allocator, source_dir, destination_dir) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => false,
        };
        if (same) return;
        if (!allow_upgrade) return error.RefusingToOverwriteDifferentFile;
        try std.fs.cwd().deleteTree(destination_dir);
    }
    try copyDirectoryRecursive(allocator, source_dir, destination_dir);
}

pub fn copyDirectoryRecursive(allocator: std.mem.Allocator, source_dir: []const u8, destination_dir: []const u8) !void {
    try std.fs.cwd().makePath(destination_dir);
    var source = try std.fs.cwd().openDir(source_dir, .{ .iterate = true });
    defer source.close();
    var it = source.iterate();
    while (try it.next()) |entry| {
        const source_path = try std.fs.path.join(allocator, &.{ source_dir, entry.name });
        defer allocator.free(source_path);
        const dest_path = try std.fs.path.join(allocator, &.{ destination_dir, entry.name });
        defer allocator.free(dest_path);
        switch (entry.kind) {
            .directory => try copyDirectoryRecursive(allocator, source_path, dest_path),
            .file => {
                const bytes = try std.fs.cwd().readFileAlloc(allocator, source_path, 8 * 1024 * 1024);
                defer allocator.free(bytes);
                try std.fs.cwd().writeFile(.{ .sub_path = dest_path, .data = bytes, .flags = .{ .truncate = true } });
            },
            else => {},
        }
    }
}

pub fn directoriesEquivalent(allocator: std.mem.Allocator, lhs_dir: []const u8, rhs_dir: []const u8) !bool {
    if (!try directoryTreeEquivalent(allocator, lhs_dir, rhs_dir)) return false;
    return directoryTreeEquivalent(allocator, rhs_dir, lhs_dir);
}

fn directoryTreeEquivalent(allocator: std.mem.Allocator, lhs_dir: []const u8, rhs_dir: []const u8) !bool {
    var lhs = try std.fs.cwd().openDir(lhs_dir, .{ .iterate = true });
    defer lhs.close();
    var rhs = try std.fs.cwd().openDir(rhs_dir, .{ .iterate = true });
    defer rhs.close();

    var lhs_it = lhs.iterate();
    while (try lhs_it.next()) |entry| {
        const lhs_path = try std.fs.path.join(allocator, &.{ lhs_dir, entry.name });
        defer allocator.free(lhs_path);
        const rhs_path = try std.fs.path.join(allocator, &.{ rhs_dir, entry.name });
        defer allocator.free(rhs_path);
        switch (entry.kind) {
            .directory => {
                if (!dirExists(rhs_path)) return false;
                if (!try directoryTreeEquivalent(allocator, lhs_path, rhs_path)) return false;
            },
            .file => {
                if (!fileExistsAbsolute(rhs_path)) return false;
                if (!try filesEqual(allocator, lhs_path, rhs_path)) return false;
            },
            else => {},
        }
    }
    return true;
}

pub fn filesEqual(allocator: std.mem.Allocator, lhs_path: []const u8, rhs_path: []const u8) !bool {
    const lhs = try std.fs.cwd().readFileAlloc(allocator, lhs_path, 1024 * 1024);
    defer allocator.free(lhs);
    const rhs = try std.fs.cwd().readFileAlloc(allocator, rhs_path, 1024 * 1024);
    defer allocator.free(rhs);
    return std.mem.eql(u8, lhs, rhs);
}

pub fn installMarketplaceHostPlugin(allocator: std.mem.Allocator, plugin_dir: []const u8, spec: MarketplaceHostInstall, stdout: anytype) !void {
    try installDirectoryIfSafe(allocator, plugin_dir, spec.plugin_dest, true);
    const installed_marketplace = try installTextIfSafe(allocator, spec.marketplace_json, spec.marketplace_path, true);
    if (installed_marketplace) {
        try stdout.print("  marketplace: wrote {s}\n", .{spec.marketplace_path});
    } else {
        try stdout.print("  marketplace: already up-to-date at {s}\n", .{spec.marketplace_path});
    }
    try stdout.print("  plugin: installed to {s}\n", .{spec.plugin_dest});
}

pub fn installCodexPlugin(
    allocator: std.mem.Allocator,
    plugin_dir: []const u8,
    workspace_root: []const u8,
    marketplace_json: []const u8,
    stdout: anytype,
) !void {
    const spec = try marketplaceHostInstallSpec(allocator, workspace_root, .codex, marketplace_json);
    defer {
        allocator.free(spec.plugin_dest);
        allocator.free(spec.marketplace_path);
    }
    try installMarketplaceHostPlugin(allocator, plugin_dir, spec, stdout);
}

pub fn installClaudePlugin(
    allocator: std.mem.Allocator,
    plugin_dir: []const u8,
    workspace_root: []const u8,
    marketplace_json: []const u8,
    stdout: anytype,
) !void {
    const spec = try marketplaceHostInstallSpec(allocator, workspace_root, .claude, marketplace_json);
    defer {
        allocator.free(spec.plugin_dest);
        allocator.free(spec.marketplace_path);
    }
    try installMarketplaceHostPlugin(allocator, plugin_dir, spec, stdout);
}

pub fn printMarketplaceHostInstallPlan(stdout: anytype, spec: MarketplaceHostInstall, plugin_dir: []const u8) !void {
    try stdout.print("  install paths for {s}:\n", .{spec.host_label});
    try stdout.print("    plugin: {s}\n", .{spec.plugin_dest});
    try stdout.print("    marketplace: {s}\n", .{spec.marketplace_path});
    try stdout.print("  next step: copy {s} to {s} and write marketplace file\n", .{ plugin_dir, spec.plugin_dest });
}

fn fileExistsAbsolute(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn dirExists(path: []const u8) bool {
    var dir = std.fs.cwd().openDir(path, .{}) catch return false;
    dir.close();
    return true;
}

test "directoriesEquivalent rejects destination with extra stale file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("src");
    try tmp.dir.writeFile(.{ .sub_path = "src/a.txt", .data = "same" });
    try tmp.dir.makePath("dst");
    try tmp.dir.writeFile(.{ .sub_path = "dst/a.txt", .data = "same" });
    try tmp.dir.writeFile(.{ .sub_path = "dst/stale.txt", .data = "old" });

    const src = try tmp.dir.realpathAlloc(std.testing.allocator, "src");
    defer std.testing.allocator.free(src);
    const dst = try tmp.dir.realpathAlloc(std.testing.allocator, "dst");
    defer std.testing.allocator.free(dst);

    try std.testing.expect(!try directoriesEquivalent(std.testing.allocator, src, dst));
}

test "loadMarketplaceTemplate rewrites bundled source path" {
    const template_path = "integrations/codex-plugin/examples/marketplace.json";
    const json = try loadMarketplaceTemplate(
        std.testing.allocator,
        template_path,
        "./integrations/codex-plugin",
        "./orca",
    );
    defer std.testing.allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "./orca") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "./integrations/codex-plugin") == null);
}
