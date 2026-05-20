const std = @import("std");
const core = @import("orca_core");
const data_classification = @import("data_classification.zig");
const endpoint_policy = @import("endpoint_policy.zig");

pub const AuditPayload = struct {
    event_type: []const u8,
    target_value: []u8,
    decision: core.decision.Decision,

    pub fn deinit(self: AuditPayload, allocator: std.mem.Allocator) void {
        allocator.free(self.target_value);
    }
};

pub fn makePayload(
    allocator: std.mem.Allocator,
    event_type: []const u8,
    endpoint: endpoint_policy.Classification,
    channel: data_classification.ChannelKind,
    decision: core.decision.Decision,
) !AuditPayload {
    return .{
        .event_type = event_type,
        .target_value = try std.fmt.allocPrint(allocator, "{s} channel={s}", .{ endpoint.redacted_endpoint, channel.toString() }),
        .decision = decision,
    };
}
