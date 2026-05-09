const std = @import("std");
const data_classification = @import("data_classification.zig");
const endpoint_policy = @import("endpoint_policy.zig");

pub const LinkKind = enum {
    command_control,
    telemetry,
    audit_report,
    customer_endpoint,
    sitl_fake_adapter,
    unknown,

    pub fn toString(self: LinkKind) []const u8 {
        return @tagName(self);
    }
};

pub const LinkClassification = struct {
    kind: LinkKind,
    spoofing_suspected: bool = false,
    reason: []const u8,
};

pub fn classifyLink(channel: data_classification.ChannelKind, endpoint_kind: endpoint_policy.EndpointKind, provenance: []const u8) LinkClassification {
    const kind: LinkKind = switch (channel) {
        .command_control, .operator_approval, .emergency_status => .command_control,
        .audit_report, .safety_case_report => .audit_report,
        .heartbeat, .health_status, .mavlink_telemetry, .sensor_metadata, .mission_upload, .mission_download, .video_stream, .image_snapshot => .telemetry,
        else => switch (endpoint_kind) {
            .customer_endpoint => .customer_endpoint,
            .px4_sitl, .ardupilot_sitl, .fake_adapter => .sitl_fake_adapter,
            else => .unknown,
        },
    };
    const spoof = kind == .command_control and switch (endpoint_kind) {
        .webhook, .tunnel_service, .paste_site, .cloud_endpoint, .direct_ip, .unknown, .customer_endpoint => true,
        else => false,
    };
    return .{
        .kind = if (endpoint_kind == .customer_endpoint and kind == .audit_report) .customer_endpoint else if (endpoint_kind == .px4_sitl or endpoint_kind == .ardupilot_sitl or endpoint_kind == .fake_adapter) .sitl_fake_adapter else kind,
        .spoofing_suspected = spoof or (data_classification.containsAny(provenance, &.{"sitl"}) and endpoint_kind == .customer_endpoint),
        .reason = if (spoof) "command/control link to non-control endpoint" else "link classified from channel and endpoint provenance",
    };
}

test "flags command control spoofing to webhook" {
    const result = classifyLink(.command_control, .webhook, "fake_adapter");
    try std.testing.expectEqual(LinkKind.command_control, result.kind);
    try std.testing.expect(result.spoofing_suspected);
}
