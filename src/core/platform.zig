const std = @import("std");
const builtin = @import("builtin");

pub const Os = enum {
    linux,
    macos,
    windows,
    freebsd,
    unknown,

    pub fn toString(self: Os) []const u8 {
        return @tagName(self);
    }
};

pub const Capability = enum {
    process_supervision,
    env_filtering,
    path_staging,
    shell_wrapping,
    path_shims,
    mcp_stdio_proxy,
    network_observe,
    network_enforce,
    strong_sandbox,

    pub fn toString(self: Capability) []const u8 {
        return @tagName(self);
    }
};

pub const CapabilityState = enum {
    active,
    partial,
    observe,
    limited,
    unavailable,
    unknown,

    pub fn toString(self: CapabilityState) []const u8 {
        return @tagName(self);
    }
};

pub const CapabilityReport = struct {
    capability: Capability,
    state: CapabilityState,
    note: []const u8,
};

pub fn detectOs() Os {
    return switch (builtin.os.tag) {
        .linux => .linux,
        .macos => .macos,
        .windows => .windows,
        .freebsd => .freebsd,
        else => .unknown,
    };
}

pub fn defaultCapabilityState(os: Os, capability: Capability) CapabilityState {
    _ = os;
    return switch (capability) {
        .env_filtering,
        .path_staging,
        .shell_wrapping,
        .mcp_stdio_proxy,
        => .unknown,
        .process_supervision,
        .path_shims,
        .network_observe,
        .network_enforce,
        .strong_sandbox,
        => .unavailable,
    };
}

pub fn reportCapability(os: Os, capability: Capability) CapabilityReport {
    const state = defaultCapabilityState(os, capability);
    return .{
        .capability = capability,
        .state = state,
        .note = switch (state) {
            .unknown => "phase 03 model only; backend not implemented",
            .unavailable => "not implemented in phase 03",
            else => "backend reported capability",
        },
    };
}

test "platform detection returns valid enum and capabilities are non-boolean" {
    const os = detectOs();
    try std.testing.expect(std.mem.eql(u8, os.toString(), @tagName(os)));

    const report = reportCapability(os, .strong_sandbox);
    try std.testing.expectEqual(Capability.strong_sandbox, report.capability);
    try std.testing.expect(report.state == .unavailable or report.state == .unknown);
}
