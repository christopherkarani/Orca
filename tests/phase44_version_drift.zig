const std = @import("std");

fn readFile(path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, std.testing.allocator, .limited(1024 * 1024));
}

fn trimVersion(text: []const u8) []const u8 {
    var end = text.len;
    while (end > 0 and (text[end - 1] == '\n' or text[end - 1] == '\r' or text[end - 1] == ' ' or text[end - 1] == '\t')) : (end -= 1) {}
    var start: usize = 0;
    while (start < end and (text[start] == ' ' or text[start] == '\t')) : (start += 1) {}
    return text[start..end];
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("expected text not found: {s}\n", .{needle});
        return error.ExpectedTextMissing;
    }
}

test "phase 44 VERSION matches install script defaults" {
    const version_text = try readFile("VERSION");
    defer std.testing.allocator.free(version_text);
    const canonical = trimVersion(version_text);
    try std.testing.expect(canonical.len > 0);

    const install_sh = try readFile("scripts/install.sh");
    defer std.testing.allocator.free(install_sh);
    try expectContains(install_sh, "../VERSION");
    try expectContains(install_sh, "ORCA_RESOURCE_ROOT");
    try expectContains(install_sh, "integrations");
    try expectContains(install_sh, "orca-daemon");

    const build_release = try readFile("scripts/build-release.sh");
    defer std.testing.allocator.free(build_release);
    try expectContains(build_release, "../VERSION");
    try expectContains(build_release, "orca-daemon");

    const render_manifests = try readFile("scripts/render-package-manifests.sh");
    defer std.testing.allocator.free(render_manifests);
    try expectContains(render_manifests, "../VERSION");

    const install_ps1 = try readFile("scripts/install.ps1");
    defer std.testing.allocator.free(install_ps1);
    try expectContains(install_ps1, "VERSION");
    try expectContains(install_ps1, "ORCA_RESOURCE_ROOT");
    try expectContains(install_ps1, "orca-daemon");

    const homebrew = try readFile("packaging/homebrew/Formula/orca.rb");
    defer std.testing.allocator.free(homebrew);
    const version_needle = try std.fmt.allocPrint(std.testing.allocator, "version \"{s}\"", .{canonical});
    defer std.testing.allocator.free(version_needle);
    try expectContains(homebrew, version_needle);
    try expectContains(homebrew, "bin.install \"bin/orca-daemon\"");
    try expectContains(homebrew, "pkgshare.install \"orca-dashboard-ui\"");

    const npm_launcher = try readFile("packaging/npm/bin/orca.js");
    defer std.testing.allocator.free(npm_launcher);
    try expectContains(npm_launcher, "\"orca-dashboard-ui\"");

    const dockerfile = try readFile("packaging/docker/Dockerfile");
    defer std.testing.allocator.free(dockerfile);
    try expectContains(dockerfile, "COPY orca /opt/orca");
    try expectContains(dockerfile, "ORCA_RESOURCE_ROOT=\"/opt/orca\"");
    try expectContains(dockerfile, "USER orca");
}
