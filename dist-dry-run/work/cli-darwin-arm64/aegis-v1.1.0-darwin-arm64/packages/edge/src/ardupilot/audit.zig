const std = @import("std");
const core = @import("aegis_core");

const mavlink = @import("../mavlink/mod.zig");
const connection = @import("connection.zig");
const sitl_adapter = @import("sitl_adapter.zig");
const vehicle_kind = @import("vehicle_kind.zig");

pub const ArtifactContext = struct {
    scenario_id: []const u8,
    environment: connection.Environment,
    tested_version: []const u8,
    vehicle: vehicle_kind.VehicleKind,
    endpoint: []const u8,
    limitation: []const u8 = "simulation evidence only; not real-flight readiness",
};

pub fn writeArtifacts(
    allocator: std.mem.Allocator,
    artifact_dir: []const u8,
    context: ArtifactContext,
    result: mavlink.gateway.ProcessResult,
    scenario_note: []const u8,
) !void {
    try std.fs.cwd().makePath(artifact_dir);
    const events_path = try std.fs.path.join(allocator, &.{ artifact_dir, "events.jsonl" });
    defer allocator.free(events_path);
    const replay_path = try std.fs.path.join(allocator, &.{ artifact_dir, "replay.json" });
    defer allocator.free(replay_path);

    {
        const file = try std.fs.cwd().createFile(events_path, .{ .truncate = true });
        defer file.close();
        var buffer: [4096]u8 = undefined;
        var writer = file.writer(&buffer);
        for (result.audit.records.items) |record| {
            try writeEventJson(&writer.interface, context, record, scenario_note);
            try writer.interface.writeByte('\n');
        }
        try writer.interface.flush();
        try file.sync();
    }

    {
        const file = try std.fs.cwd().createFile(replay_path, .{ .truncate = true });
        defer file.close();
        var buffer: [4096]u8 = undefined;
        var writer = file.writer(&buffer);
        try writer.interface.writeByte('{');
        try writer.interface.writeAll("\"scenario_id\":");
        try writeRedactedJsonString(&writer.interface, context.scenario_id);
        try writer.interface.writeAll(",\"environment\":");
        try writeRedactedJsonString(&writer.interface, context.environment.toString());
        try writer.interface.writeAll(",\"provenance\":");
        try writeRedactedJsonString(&writer.interface, @tagName(sitl_adapter.provenanceFor(context.environment)));
        try writer.interface.writeAll(",\"tested_ardupilot_version\":");
        try writeRedactedJsonString(&writer.interface, context.tested_version);
        try writer.interface.writeAll(",\"vehicle_type\":");
        try writeRedactedJsonString(&writer.interface, context.vehicle.toString());
        try writer.interface.writeAll(",\"decision\":");
        try writeRedactedJsonString(&writer.interface, if (result.decision) |decision| decision.toString() else "none");
        try writer.interface.writeAll(",\"forwarded\":");
        try writer.interface.print("{}", .{result.forwarded});
        try writer.interface.writeAll(",\"blocked\":");
        try writer.interface.print("{}", .{result.blocked});
        try writer.interface.writeAll(",\"limitations\":");
        try writeRedactedJsonString(&writer.interface, context.limitation);
        try writer.interface.writeAll("}\n");
        try writer.interface.flush();
        try file.sync();
    }
}

fn writeEventJson(writer: anytype, context: ArtifactContext, record: mavlink.audit.Record, scenario_note: []const u8) !void {
    try writer.writeByte('{');
    try writer.writeAll("\"scenario_id\":");
    try writeRedactedJsonString(writer, context.scenario_id);
    try writer.writeAll(",\"environment\":");
    try writeRedactedJsonString(writer, context.environment.toString());
    try writer.writeAll(",\"provenance\":");
    try writeRedactedJsonString(writer, @tagName(sitl_adapter.provenanceFor(context.environment)));
    try writer.writeAll(",\"tested_ardupilot_version\":");
    try writeRedactedJsonString(writer, context.tested_version);
    try writer.writeAll(",\"vehicle_type\":");
    try writeRedactedJsonString(writer, context.vehicle.toString());
    try writer.writeAll(",\"endpoint\":");
    try writeRedactedJsonString(writer, context.endpoint);
    try writer.writeAll(",\"event_type\":");
    try writeRedactedJsonString(writer, record.event_type);
    try writer.writeAll(",\"decision\":");
    try writeRedactedJsonString(writer, record.decision.toString());
    try writer.print(",\"source_sysid\":{d},\"source_compid\":{d},\"message_id\":{d}", .{ record.source_sysid, record.source_compid, record.message_id });
    if (record.command_id) |command_id| try writer.print(",\"command_id\":{d}", .{command_id});
    try writer.writeAll(",\"note\":");
    try writeRedactedJsonString(writer, record.note);
    try writer.writeAll(",\"scenario_note\":");
    try writeRedactedJsonString(writer, scenario_note);
    try writer.writeAll(",\"limitations\":");
    try writeRedactedJsonString(writer, context.limitation);
    try writer.writeByte('}');
}

fn writeRedactedJsonString(writer: anytype, value: []const u8) !void {
    var buffer: [512]u8 = undefined;
    const redacted = core.api.redactStringBounded(value, &buffer);
    try core.core.util.writeJsonString(writer, redacted);
}
