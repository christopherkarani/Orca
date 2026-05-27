pub const edge_policy_schema = @import("edge_policy_schema.zig");
pub const edge_event_schema = @import("edge_event_schema.zig");
pub const safety_report_schema = @import("safety_report_schema.zig");

pub const SchemaDescriptor = struct {
    id: []const u8,
    version: u32,
    path: []const u8,
    title: []const u8,
};

pub const edge_policy_v1 = SchemaDescriptor{
    .id = "edge-policy-v1",
    .version = 1,
    .path = "schemas/edge-policy-v1.json",
    .title = "Edge policy schema v1",
};

pub const edge_event_v1 = SchemaDescriptor{
    .id = "edge-event-v1",
    .version = 1,
    .path = "schemas/edge-event-v1.json",
    .title = "Edge event schema v1",
};

pub const safety_report_v1 = SchemaDescriptor{
    .id = "safety-report-v1",
    .version = 1,
    .path = "schemas/safety-report-v1.json",
    .title = "Edge safety report schema v1",
};

pub const registry = [_]SchemaDescriptor{
    edge_policy_v1,
    edge_event_v1,
    safety_report_v1,
};

pub fn find(id: []const u8) ?SchemaDescriptor {
    const std = @import("std");
    for (registry) |descriptor| {
        if (std.mem.eql(u8, descriptor.id, id)) return descriptor;
    }
    return null;
}
