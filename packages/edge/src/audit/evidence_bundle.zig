const std = @import("std");
const core = @import("orca_core");
const artifacts = @import("edge_artifacts.zig");

pub const required_files = [_][]const u8{
    "events.jsonl",
    "summary.json",
    "summary.md",
    "safety-report.json",
    "safety-report.md",
    "final-hash.txt",
    "evidence/policy.yaml",
    "evidence/policy-hash.txt",
    "evidence/scenario.yaml",
    "evidence/scenario-result.json",
    "evidence/replay.md",
    "evidence/findings.json",
    "evidence/data-network-guard.json",
    "evidence/commands.json",
    "evidence/environment.json",
    "evidence/limitations.md",
    "evidence/traceability.json",
    "evidence/traceability.md",
};

pub fn create(allocator: std.mem.Allocator, session_dir: []const u8) ![]u8 {
    for (required_files) |relative| {
        const path = try std.fs.path.join(allocator, &.{ session_dir, relative });
        defer allocator.free(path);
        std.fs.cwd().access(path, .{}) catch return error.EdgeEvidenceMissing;
    }

    const bundle_dir = try std.fs.path.join(allocator, &.{ session_dir, "evidence-bundle" });
    errdefer allocator.free(bundle_dir);
    try std.fs.cwd().makePath(bundle_dir);

    const manifest_path = try std.fs.path.join(allocator, &.{ bundle_dir, "manifest.json" });
    defer allocator.free(manifest_path);
    const file = try std.fs.cwd().createFile(manifest_path, .{ .truncate = true });
    defer file.close();
    var buffer: [8192]u8 = undefined;
    var writer = file.writer(&buffer);
    try writer.interface.writeAll("{\"schema_version\":1,\"bundle_kind\":\"directory\",\"non_certification_disclaimer\":");
    try core.util.writeJsonString(&writer.interface, "Edge evidence bundles are engineering audit artifacts only, not regulatory approval, certification, airworthiness approval, or real-flight readiness claims.");
    try writer.interface.writeAll(",\"files\":[");
    for (required_files, 0..) |relative, index| {
        if (index > 0) try writer.interface.writeByte(',');
        const source = try std.fs.path.join(allocator, &.{ session_dir, relative });
        defer allocator.free(source);
        const hash = try artifacts.fileSha256Hex(allocator, source);
        try writer.interface.writeByte('{');
        try writer.interface.writeAll("\"path\":");
        try core.util.writeJsonString(&writer.interface, relative);
        try writer.interface.writeAll(",\"sha256\":");
        try core.util.writeJsonString(&writer.interface, &hash);
        try writer.interface.writeByte('}');
    }
    try writer.interface.writeAll("]}\n");
    try writer.interface.flush();
    try file.sync();
    return bundle_dir;
}
