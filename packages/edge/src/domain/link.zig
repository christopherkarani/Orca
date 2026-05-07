const coordinates = @import("coordinates.zig");

pub const LinkState = struct {
    connected: bool,
    last_heartbeat: ?coordinates.Timestamp = null,
    latency_ms: ?u64 = null,
    packet_loss_percent: f64 = 0,
    source: coordinates.TimestampSource = .unknown,

    pub fn validate(self: LinkState) !void {
        if (self.packet_loss_percent < 0 or self.packet_loss_percent > 100) return error.InvalidPercent;
        if (self.source == .unknown) return error.UnknownTimestampSource;
        if (self.last_heartbeat) |ts| try ts.validate();
    }
};
