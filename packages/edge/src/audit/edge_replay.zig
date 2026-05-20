const std = @import("std");
const core = @import("orca_core");
const artifacts = @import("edge_artifacts.zig");
const edge_session = @import("edge_session.zig");

pub const ReplayOptions = struct {
    session: []const u8 = "last",
    verify: bool = false,
    json: bool = false,
    findings: bool = false,
    commands: bool = false,
    approvals: bool = false,
    safety_case: bool = false,
};

pub fn write(writer: anytype, allocator: std.mem.Allocator, workspace_root: []const u8, options: ReplayOptions) !void {
    const session_id = try edge_session.resolveSessionId(allocator, workspace_root, options.session);
    defer allocator.free(session_id);
    const session_dir = try edge_session.sessionDirPath(allocator, workspace_root, session_id);
    defer allocator.free(session_dir);

    if (options.findings) return writeEvidenceFile(writer, allocator, session_dir, "evidence/findings.json");
    if (options.commands) return writeEvidenceFile(writer, allocator, session_dir, "evidence/commands.json");
    if (options.approvals) return writeEvidenceFile(writer, allocator, session_dir, "evidence/approvals.jsonl");
    if (options.safety_case) return writeEvidenceFile(writer, allocator, session_dir, "safety-report.md");

    var replay = try edge_session.loadReplay(allocator, workspace_root, session_id, options.verify);
    defer replay.deinit();

    if (options.json) {
        try writer.writeAll("{\"session_id\":");
        try core.util.writeJsonString(writer, session_id);
        try writer.writeAll(",\"hash_chain_verified\":");
        try writer.print("{}", .{replay.verified});
        try writer.writeAll(",\"events\":");
        try core.api.writeReplayJson(writer, replay);
        try writer.writeAll("}\n");
        return;
    }

    const report_path = try std.fs.path.join(allocator, &.{ session_dir, "safety-report.json" });
    defer allocator.free(report_path);
    const report_text = std.fs.cwd().readFileAlloc(allocator, report_path, artifacts.max_artifact_bytes) catch null;
    defer if (report_text) |text| allocator.free(text);

    try writer.print("Edge session: {s}\n", .{session_id});
    if (report_text) |text| {
        try printJsonField(writer, "Scenario", text, "scenario_id");
        try printJsonField(writer, "Provenance", text, "environment_provenance");
        try printJsonField(writer, "Policy hash", text, "policy_hash");
        try printJsonField(writer, "Result", text, "scenario_result");
    }
    try core.api.writeReplayHuman(writer, replay, options.verify);
    try writer.writeAll("Limitations: simulation/SITL/bench-preparation/customer-evaluation evidence only; no real-flight or certification claim.\n");
}

fn writeEvidenceFile(writer: anytype, allocator: std.mem.Allocator, session_dir: []const u8, relative: []const u8) !void {
    const path = try std.fs.path.join(allocator, &.{ session_dir, relative });
    defer allocator.free(path);
    const text = try artifacts.readBounded(allocator, path);
    defer allocator.free(text);
    try writer.writeAll(text);
}

fn printJsonField(writer: anytype, label: []const u8, text: []const u8, field: []const u8) !void {
    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, text, .{}) catch return;
    defer parsed.deinit();
    if (findStringField(parsed.value, field)) |value| try writer.print("{s}: {s}\n", .{ label, value });
}

fn findStringField(value: std.json.Value, field: []const u8) ?[]const u8 {
    switch (value) {
        .object => |object| {
            if (object.get(field)) |candidate| {
                if (candidate == .string) return candidate.string;
            }
            var iterator = object.iterator();
            while (iterator.next()) |entry| {
                if (findStringField(entry.value_ptr.*, field)) |found| return found;
            }
        },
        else => {},
    }
    return null;
}
