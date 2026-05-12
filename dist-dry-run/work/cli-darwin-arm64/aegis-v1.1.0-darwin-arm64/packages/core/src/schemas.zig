const std = @import("std");

pub const SchemaKind = enum {
    policy,
    event,
    mcp_manifest,
    edge_policy,
    edge_event,
    safety_report,
};

pub const SchemaDescriptor = struct {
    kind: SchemaKind,
    id: []const u8,
    version: u16,
    path: []const u8,
    status: []const u8,
    contents: []const u8,
};

const policy_schema_descriptor =
    \\{"id":"policy-v1","version":1,"path":"schemas/policy-v1.json","status":"stable-v1"}
;

const event_schema_descriptor =
    \\{"id":"event-v1","version":1,"path":"schemas/event-v1.json","status":"stable-v1"}
;

const mcp_manifest_schema_descriptor =
    \\{"id":"mcp-manifest-v1","version":1,"path":"schemas/mcp-manifest-v1.json","status":"stable-v1"}
;

const edge_policy_placeholder =
    \\{"id":"edge-policy-placeholder-v1","version":1,"status":"placeholder"}
;

const edge_event_placeholder =
    \\{"id":"edge-event-placeholder-v1","version":1,"status":"placeholder"}
;

const safety_report_placeholder =
    \\{"id":"safety-report-placeholder-v1","version":1,"status":"placeholder"}
;

pub const registry = [_]SchemaDescriptor{
    .{
        .kind = .policy,
        .id = "policy-v1",
        .version = 1,
        .path = "schemas/policy-v1.json",
        .status = "stable-v1",
        .contents = policy_schema_descriptor,
    },
    .{
        .kind = .event,
        .id = "event-v1",
        .version = 1,
        .path = "schemas/event-v1.json",
        .status = "stable-v1",
        .contents = event_schema_descriptor,
    },
    .{
        .kind = .mcp_manifest,
        .id = "mcp-manifest-v1",
        .version = 1,
        .path = "schemas/mcp-manifest-v1.json",
        .status = "stable-v1",
        .contents = mcp_manifest_schema_descriptor,
    },
    .{
        .kind = .edge_policy,
        .id = "edge-policy-placeholder-v1",
        .version = 1,
        .path = "schemas/edge-policy-placeholder-v1.json",
        .status = "reserved-placeholder",
        .contents = edge_policy_placeholder,
    },
    .{
        .kind = .edge_event,
        .id = "edge-event-placeholder-v1",
        .version = 1,
        .path = "schemas/edge-event-placeholder-v1.json",
        .status = "reserved-placeholder",
        .contents = edge_event_placeholder,
    },
    .{
        .kind = .safety_report,
        .id = "safety-report-placeholder-v1",
        .version = 1,
        .path = "schemas/safety-report-placeholder-v1.json",
        .status = "reserved-placeholder",
        .contents = safety_report_placeholder,
    },
};

pub fn lookup(kind: SchemaKind) ?SchemaDescriptor {
    for (registry) |descriptor| {
        if (descriptor.kind == kind) return descriptor;
    }
    return null;
}

pub fn lookupId(id: []const u8) ?SchemaDescriptor {
    for (registry) |descriptor| {
        if (std.mem.eql(u8, descriptor.id, id)) return descriptor;
    }
    return null;
}

test "schema registry exposes stable and placeholder descriptors" {
    try std.testing.expect(lookup(.policy) != null);
    try std.testing.expect(lookup(.edge_event) != null);
    try std.testing.expect(lookupId("mcp-manifest-v1") != null);
    try std.testing.expect(lookupId("missing") == null);
}
