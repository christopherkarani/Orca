const std = @import("std");

pub const ArtifactTarget = struct {
    os: []const u8,
    arch: []const u8,
    extension: []const u8,
};

pub const targets = [_]ArtifactTarget{
    .{ .os = "darwin", .arch = "amd64", .extension = "tar.gz" },
    .{ .os = "darwin", .arch = "arm64", .extension = "tar.gz" },
    .{ .os = "linux", .arch = "amd64", .extension = "tar.gz" },
    .{ .os = "linux", .arch = "arm64", .extension = "tar.gz" },
    .{ .os = "windows", .arch = "amd64", .extension = "zip" },
};

pub fn artifactName(buffer: []u8, version: []const u8, target: ArtifactTarget) ![]const u8 {
    return std.fmt.bufPrint(buffer, "aegis-v{s}-{s}-{s}.{s}", .{
        version,
        target.os,
        target.arch,
        target.extension,
    });
}

test "phase 19 artifact names match release contract" {
    var names: [targets.len][96]u8 = undefined;
    const expected = [_][]const u8{
        "aegis-v0.19.0-darwin-amd64.tar.gz",
        "aegis-v0.19.0-darwin-arm64.tar.gz",
        "aegis-v0.19.0-linux-amd64.tar.gz",
        "aegis-v0.19.0-linux-arm64.tar.gz",
        "aegis-v0.19.0-windows-amd64.zip",
    };

    for (targets, 0..) |target, index| {
        const actual = try artifactName(&names[index], "0.19.0", target);
        try std.testing.expectEqualStrings(expected[index], actual);
    }
}

test "phase 19 package and workflow files are present" {
    const required_files = [_][]const u8{
        "scripts/install.sh",
        "scripts/install.ps1",
        "scripts/build-release.sh",
        "scripts/build-release.ps1",
        "scripts/generate-checksums.sh",
        "scripts/generate-sbom.sh",
        "packaging/homebrew/aegis.rb",
        "packaging/scoop/aegis.json",
        "packaging/winget/aegis.yaml",
        "packaging/npm/package.json",
        "packaging/npm/bin/aegis.js",
        "packaging/docker/Dockerfile",
        ".github/workflows/build.yml",
        ".github/workflows/test.yml",
        ".github/workflows/release.yml",
        "docs/release/checklist.md",
    };

    for (required_files) |path| {
        var file = try std.fs.cwd().openFile(path, .{});
        file.close();
    }
}

test "phase 19 release files include integrity checks without obvious credentials" {
    const checked_files = [_][]const u8{
        "scripts/install.sh",
        "scripts/install.ps1",
        "packaging/homebrew/aegis.rb",
        "packaging/scoop/aegis.json",
        "packaging/winget/aegis.yaml",
        "packaging/npm/package.json",
        "packaging/npm/bin/aegis.js",
        "packaging/docker/Dockerfile",
        ".github/workflows/build.yml",
        ".github/workflows/test.yml",
        ".github/workflows/release.yml",
        "docs/release/checklist.md",
    };

    for (checked_files) |path| {
        const text = try std.fs.cwd().readFileAlloc(std.testing.allocator, path, 256 * 1024);
        defer std.testing.allocator.free(text);
        try std.testing.expect(std.mem.indexOf(u8, text, "checksum") != null or std.mem.indexOf(u8, text, "Checksum") != null or std.mem.indexOf(u8, text, "sha256") != null);
        try std.testing.expect(std.mem.indexOf(u8, text, "BEGIN PRIVATE KEY") == null);
        try std.testing.expect(std.mem.indexOf(u8, text, "ghp_") == null);
        try std.testing.expect(std.mem.indexOf(u8, text, "sk-") == null);
        try std.testing.expect(std.mem.indexOf(u8, text, "AKIA") == null);
    }
}

test "phase 19 Dockerfile references installed Orca binary" {
    const text = try std.fs.cwd().readFileAlloc(std.testing.allocator, "packaging/docker/Dockerfile", 64 * 1024);
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "COPY orca") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "/usr/local/bin/orca") != null);
}

test "GitHub composite action does not shell-interpolate command input before Orca" {
    const text = try std.fs.cwd().readFileAlloc(std.testing.allocator, ".github/actions/orca-run/action.yml", 64 * 1024);
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "orca run --mode ci -- ${{ inputs.command }}") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "ORCA_ACTION_COMMAND: ${{ inputs.command }}") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "orca run --mode ci -- bash -c \"$ORCA_ACTION_COMMAND\"") != null);
}
