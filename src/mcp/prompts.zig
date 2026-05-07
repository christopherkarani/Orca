const std = @import("std");

const jsonrpc = @import("jsonrpc.zig");

pub const implemented = true;

pub fn getName(value: std.json.Value) ?[]const u8 {
    const params = jsonrpc.paramsOf(value) orelse return null;
    if (params != .object) return null;
    const name = params.object.get("name") orelse return null;
    if (name != .string or name.string.len == 0) return null;
    return name.string;
}

pub fn arguments(value: std.json.Value) ?std.json.Value {
    const params = jsonrpc.paramsOf(value) orelse return null;
    if (params != .object) return null;
    return params.object.get("arguments");
}

pub fn targetDisplay(allocator: std.mem.Allocator, server_name: []const u8, name: []const u8, args: ?std.json.Value) ![]u8 {
    if (args) |arguments_value| {
        const arg_text = jsonrpc.stringifyAlloc(allocator, arguments_value, 8 * 1024) catch
            return std.fmt.allocPrint(allocator, "{s}.{s} args=[arguments omitted]", .{ server_name, name });
        defer allocator.free(arg_text);
        return std.fmt.allocPrint(allocator, "{s}.{s} args={s}", .{ server_name, name, arg_text });
    }
    return std.fmt.allocPrint(allocator, "{s}.{s}", .{ server_name, name });
}

pub fn listTargetDisplay(allocator: std.mem.Allocator, server_name: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}: prompts/list", .{server_name});
}

test "prompt name extraction requires params.name" {
    var parsed = try jsonrpc.parseLine(std.testing.allocator, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"prompts/get\",\"params\":{\"name\":\"review\"}}");
    defer parsed.deinit();
    try std.testing.expectEqualStrings("review", getName(parsed.value()).?);
}
