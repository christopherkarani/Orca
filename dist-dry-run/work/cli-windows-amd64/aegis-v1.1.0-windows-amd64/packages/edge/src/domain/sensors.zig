const coordinates = @import("coordinates.zig");

pub const GpsFixType = enum {
    none,
    two_d,
    three_d,
    differential,
    rtk_float,
    rtk_fixed,
    unknown,
};

pub const GpsState = struct {
    fix_type: GpsFixType = .unknown,
    satellites_visible: u8 = 0,
    hdop: ?f64 = null,
    vdop: ?f64 = null,
    accuracy_estimate: ?coordinates.AccuracyEstimate = null,
    is_valid: bool = false,
    source: coordinates.TimestampSource = .unknown,

    pub fn validate(self: GpsState) !void {
        if (self.source == .unknown) return error.UnknownTimestampSource;
        if (self.accuracy_estimate) |accuracy| try accuracy.validate();
    }
};

pub const SensorState = struct {
    imu_valid: bool = false,
    barometer_valid: bool = false,
    compass_valid: bool = false,
    rangefinder_valid: bool = false,
    camera_valid: bool = false,
    source: coordinates.TimestampSource = .unknown,

    pub fn validate(self: SensorState) !void {
        if (self.source == .unknown) return error.UnknownTimestampSource;
    }
};
