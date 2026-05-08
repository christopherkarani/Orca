const std = @import("std");
const core = @import("aegis_core");
const safety_report = @import("safety_report.zig");

pub fn writeJsonFile(path: []const u8, rows: []const safety_report.TraceabilityRow) !void {
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    var buffer: [4096]u8 = undefined;
    var writer = file.writer(&buffer);
    try writer.interface.writeAll("{\"schema_version\":1,\"rows\":[");
    for (rows, 0..) |row, index| {
        if (index > 0) try writer.interface.writeByte(',');
        try writer.interface.writeByte('{');
        try stringField(&writer.interface, "policy_rule", row.policy_rule, false);
        try stringField(&writer.interface, "command", row.command, true);
        try stringField(&writer.interface, "finding", row.finding, true);
        try stringField(&writer.interface, "decision", row.decision, true);
        try stringField(&writer.interface, "event_id", row.event_id, true);
        try stringField(&writer.interface, "report_section", row.report_section, true);
        try writer.interface.writeByte('}');
    }
    try writer.interface.writeAll("]}\n");
    try writer.interface.flush();
    try file.sync();
}

pub fn writeMarkdownFile(path: []const u8, rows: []const safety_report.TraceabilityRow) !void {
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    var buffer: [4096]u8 = undefined;
    var writer = file.writer(&buffer);
    try writer.interface.writeAll("# Edge Traceability Matrix\n\n| Policy Rule | Command | Finding | Decision | Event ID |\n|---|---|---|---|---|\n");
    for (rows) |row| {
        try writer.interface.print("| {s} | {s} | {s} | {s} | {s} |\n", .{ row.policy_rule, row.command, row.finding, row.decision, row.event_id });
    }
    try writer.interface.flush();
    try file.sync();
}

fn stringField(writer: anytype, name: []const u8, value: []const u8, comma: bool) !void {
    if (comma) try writer.writeByte(',');
    try core.util.writeJsonString(writer, name);
    try writer.writeByte(':');
    var redacted_buf: [512]u8 = undefined;
    try core.util.writeJsonString(writer, core.api.redactStringBounded(value, &redacted_buf));
}
