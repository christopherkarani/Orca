const std = @import("std");
const core = @import("orca_core");

pub const audit_dir_name = ".edge";

pub fn createWriter(allocator: std.mem.Allocator, session: core.session.Session) !core.audit.writer.SessionWriter {
    return core.audit.writer.SessionWriter.initWithDirName(allocator, session, audit_dir_name);
}

pub fn openWriter(allocator: std.mem.Allocator, workspace_root: []const u8, session_id: []const u8) !core.audit.writer.SessionWriter {
    return core.audit.writer.SessionWriter.openExistingWithDirName(allocator, workspace_root, session_id, audit_dir_name);
}

pub fn sessionDirPath(allocator: std.mem.Allocator, workspace_root: []const u8, session_id: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ workspace_root, audit_dir_name, "sessions", session_id });
}

pub fn resolveSessionId(allocator: std.mem.Allocator, workspace_root: []const u8, requested: []const u8) ![]u8 {
    if (!std.mem.eql(u8, requested, "last")) return try allocator.dupe(u8, requested);
    const last_path = try std.fs.path.join(allocator, &.{ workspace_root, audit_dir_name, "last" });
    defer allocator.free(last_path);
    const text = try std.fs.cwd().readFileAlloc(allocator, last_path, core.limits.max_session_id_len + 2);
    defer allocator.free(text);
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.len == 0) return error.EdgeSessionMissing;
    return try allocator.dupe(u8, trimmed);
}

pub fn verifySession(allocator: std.mem.Allocator, workspace_root: []const u8, requested: []const u8) !core.api.VerifyResult {
    const session_id = try resolveSessionId(allocator, workspace_root, requested);
    defer allocator.free(session_id);
    const dir = try sessionDirPath(allocator, workspace_root, session_id);
    defer allocator.free(dir);
    return core.api.verifyReplay(allocator, dir);
}

pub fn loadReplay(allocator: std.mem.Allocator, workspace_root: []const u8, session: []const u8, verify: bool) !core.api.ReplaySession {
    return core.api.loadReplay(allocator, workspace_root, .{
        .session = session,
        .verify = verify,
        .audit_dir_name = audit_dir_name,
    });
}

test "edge session path uses .edge namespace" {
    const path = try sessionDirPath(std.testing.allocator, "/tmp/orca", "session-1");
    defer std.testing.allocator.free(path);
    try std.testing.expect(std.mem.indexOf(u8, path, ".edge") != null);
}
