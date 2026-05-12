const status_mod = @import("health_status.zig");

pub const RuntimeStatus = status_mod.RuntimeStatus;

pub const RuntimeSnapshot = struct {
    status: RuntimeStatus = .unknown,
    mode_reason: []const u8 = "runtime status unknown",
    timestamp_ms: i128 = 0,
};
