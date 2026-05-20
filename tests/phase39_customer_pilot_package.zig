const std = @import("std");
const edge_main = @import("orca_edge_main");

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("expected text not found: {s}\n", .{needle});
        return error.ExpectedTextMissing;
    }
}

fn expectNotContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) != null) {
        std.debug.print("forbidden text found: {s}\n", .{needle});
        return error.ForbiddenTextFound;
    }
}

fn expectMissing(path: []const u8) !void {
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().access(path, .{}));
}

test "phase 39 customer pilot materials are local-only public repo exclusions" {
    try expectMissing("customer_pilot/README.md");
    try expectMissing("customer_pilot/pilot-overview.md");
    try expectMissing("customer_pilot/templates/pilot-sow-template.md");
    try expectMissing("customer_pilot/examples/sample-pilot-report.md");
}

test "phase 39 public docs do not link to private customer pilot paths" {
    const allocator = std.testing.allocator;
    const files = [_][]const u8{
        "docs/edge/README.md",
        "packages/edge/README.md",
    };
    for (files) |path| {
        const text = try std.fs.cwd().readFileAlloc(allocator, path, 256 * 1024);
        defer allocator.free(text);
        try expectContains(text, "local-only");
        try expectNotContains(text, "customer_pilot/README.md");
    }
}

test "phase 39 pilot CLI helpers stay local only and bounded" {
    var stdout_buf: [65536]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const checklist_argv = [_][]const u8{ "pilot", "checklist" };
    try std.testing.expectEqual(@as(u8, 0), try edge_main.run(checklist_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try expectContains(stdout_stream.getWritten(), "local-only");
    try expectContains(stdout_stream.getWritten(), "private customer_pilot/");
    try expectContains(stdout_stream.getWritten(), "No real hardware");
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    stdout_stream.reset();
    stderr_stream.reset();
    const package_argv = [_][]const u8{ "pilot", "package" };
    try std.testing.expectEqual(@as(u8, 0), try edge_main.run(package_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try expectContains(stdout_stream.getWritten(), ".edge/pilot-package/index.md");
    try expectContains(stdout_stream.getWritten(), "not public repo files");
    try expectContains(stdout_stream.getWritten(), "no external network");
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    const package_index = try std.fs.cwd().readFileAlloc(std.testing.allocator, ".edge/pilot-package/index.md", 64 * 1024);
    defer std.testing.allocator.free(package_index);
    try expectContains(package_index, "local-only");
    try expectContains(package_index, "docs/edge/customer-proof/");
    try expectNotContains(package_index, "customer_pilot/README.md");

    stdout_stream.reset();
    stderr_stream.reset();
    const demo_argv = [_][]const u8{ "pilot", "demo" };
    try std.testing.expectEqual(@as(u8, 0), try edge_main.run(demo_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try expectContains(stdout_stream.getWritten(), "private customer_pilot/customer-demo-script.md");
    try expectContains(stdout_stream.getWritten(), "demo 1: geofence deny");
    try expectContains(stdout_stream.getWritten(), "not real flight");
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "phase 39 profile-scoped redteam rejects missing deployment profile before reporting success" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const argv = [_][]const u8{
        "redteam",
        "--deployment-profile",
        "/no/such/profile.yaml",
        "--category",
        "health",
        "--ci",
    };

    try std.testing.expectEqual(@as(u8, 65), try edge_main.run(argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expectEqualStrings("", stdout_stream.getWritten());
    try expectContains(stderr_stream.getWritten(), "deployment profile");
}

test "phase 39 profile-scoped redteam rejects deployment profile that is not active" {
    try std.fs.cwd().makePath(".zig-cache/phase39-customer-pilot");
    const profile_path = ".zig-cache/phase39-customer-pilot/inactive-profile.yaml";
    var file = try std.fs.cwd().createFile(profile_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(
        \\id: inactive-redteam-profile
        \\target_arch: linux-amd64
        \\os: linux
        \\mode: source
        \\environment: fake_adapter
        \\policy_path: examples/edge/no-such-policy.yaml
        \\scenario_path: examples/edge/safety/scenarios/geofence-deny.yaml
        \\network_mode: offline
        \\
    );

    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const argv = [_][]const u8{
        "redteam",
        "--deployment-profile",
        profile_path,
        "--category",
        "health",
        "--ci",
    };

    try std.testing.expectEqual(@as(u8, 65), try edge_main.run(argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expectEqualStrings("", stdout_stream.getWritten());
    try expectContains(stderr_stream.getWritten(), "deployment profile check did not return active");
}
