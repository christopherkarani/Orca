const coordinates = @import("coordinates.zig");

pub const BatteryState = struct {
    percent_remaining: f64,
    voltage_v: f64,
    current_a: f64,
    estimated_time_remaining_s: ?u64 = null,
    is_low: bool = false,
    is_critical: bool = false,
    source: coordinates.TimestampSource = .unknown,

    pub fn validate(self: BatteryState) !void {
        if (self.percent_remaining < 0 or self.percent_remaining > 100) return error.InvalidPercent;
        if (self.voltage_v < 0) return error.InvalidBatteryVoltage;
        if (self.source == .unknown) return error.UnknownTimestampSource;
    }
};
