const std = @import("std");
const core = @import("orca_core");

pub const max_artifact_bytes: usize = 128 * 1024;

pub fn ensureDir(path: []const u8) !void {
    try std.fs.cwd().makePath(path);
}

pub fn readBounded(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(allocator, path, max_artifact_bytes);
}

pub fn writeFile(path: []const u8, bytes: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
    try file.sync();
}

pub fn writeRedactedTextFile(allocator: std.mem.Allocator, path: []const u8, text: []const u8) !void {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        var buffer: [1024]u8 = undefined;
        const redacted = core.api.redactStringBounded(line, &buffer);
        try out.appendSlice(allocator, redacted);
        try out.append(allocator, '\n');
        if (out.items.len > max_artifact_bytes) return error.ArtifactTooLarge;
    }
    try writeFile(path, out.items);
}

pub fn copyRedacted(allocator: std.mem.Allocator, source_path: []const u8, dest_path: []const u8) !void {
    const text = try readBounded(allocator, source_path);
    defer allocator.free(text);
    try writeRedactedTextFile(allocator, dest_path, text);
}

pub fn sha256Hex(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

pub fn fileSha256Hex(allocator: std.mem.Allocator, path: []const u8) ![64]u8 {
    const bytes = try readBounded(allocator, path);
    defer allocator.free(bytes);
    return sha256Hex(bytes);
}

pub fn writeHashFile(allocator: std.mem.Allocator, path: []const u8, hash: []const u8) !void {
    const text = try std.fmt.allocPrint(allocator, "{s}\n", .{hash});
    defer allocator.free(text);
    try writeFile(path, text);
}

pub fn basename(path: []const u8) []const u8 {
    return std.fs.path.basename(path);
}
