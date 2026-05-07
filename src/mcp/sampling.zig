const std = @import("std");

const jsonrpc = @import("jsonrpc.zig");

pub const implemented = true;

pub fn isSamplingMethod(method: []const u8) bool {
    return std.mem.eql(u8, method, "sampling/createMessage") or
        std.mem.eql(u8, method, "sampling/create_message") or
        std.mem.eql(u8, method, "sampling/request");
}

pub fn model(value: std.json.Value) ?[]const u8 {
    const request_params = jsonrpc.paramsOf(value) orelse return null;
    if (request_params != .object) return null;
    if (request_params.object.get("model")) |model_value| {
        if (model_value == .string and model_value.string.len > 0) return model_value.string;
    }
    if (request_params.object.get("modelPreferences")) |prefs| {
        if (prefs == .object) {
            if (prefs.object.get("hints")) |hints| {
                if (hints == .array and hints.array.items.len > 0 and hints.array.items[0] == .object) {
                    if (hints.array.items[0].object.get("name")) |name| {
                        if (name == .string and name.string.len > 0) return name.string;
                    }
                }
            }
        }
    }
    return null;
}

pub fn params(value: std.json.Value) ?std.json.Value {
    return jsonrpc.paramsOf(value);
}

pub fn targetDisplay(allocator: std.mem.Allocator, server_name: []const u8, model_name: ?[]const u8, args: ?std.json.Value) ![]u8 {
    const model_text = model_name orelse "sampling";
    if (args) |arguments_value| {
        const arg_text = jsonrpc.stringifyAlloc(allocator, arguments_value, 8 * 1024) catch
            return std.fmt.allocPrint(allocator, "{s}.{s} args=[sampling arguments omitted]", .{ server_name, model_text });
        defer allocator.free(arg_text);
        return std.fmt.allocPrint(allocator, "{s}.{s} args={s}", .{ server_name, model_text, arg_text });
    }
    return std.fmt.allocPrint(allocator, "{s}.{s}", .{ server_name, model_text });
}

test "sampling method and model extraction are recognized" {
    try std.testing.expect(isSamplingMethod("sampling/createMessage"));
    var parsed = try jsonrpc.parseLine(std.testing.allocator, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"sampling/createMessage\",\"params\":{\"model\":\"local-test\"}}");
    defer parsed.deinit();
    try std.testing.expectEqualStrings("local-test", model(parsed.value()).?);
}
