pub const CoordinateFrame = enum {
    wgs84,
    local_ned,
    local_enu,
    body_frame,
    home_relative,
    unknown,
};

pub const AltitudeReference = enum {
    amsl,
    agl,
    home_relative,
    terrain_relative,
    unknown,
};

pub const DistanceUnit = enum { meters };
pub const SpeedUnit = enum { meters_per_second };
pub const AngleUnit = enum { degrees, radians };

pub const TimestampSource = enum {
    monotonic,
    gps,
    system_clock,
    autopilot,
    unknown,
};

pub const GeoPoint = struct {
    latitude_deg: f64,
    longitude_deg: f64,
    altitude_m: f64,
    altitude_reference: AltitudeReference,

    pub fn validate(self: GeoPoint) !void {
        if (self.latitude_deg < -90 or self.latitude_deg > 90) return error.InvalidLatitude;
        if (self.longitude_deg < -180 or self.longitude_deg > 180) return error.InvalidLongitude;
        if (self.altitude_reference == .unknown) return error.UnknownAltitudeReference;
    }
};

pub const LocalPosition = struct {
    x_m: f64,
    y_m: f64,
    z_m: f64,
    frame: CoordinateFrame,

    pub fn validateKnownFrame(self: LocalPosition) !void {
        if (self.frame == .unknown or self.frame == .wgs84) return error.UnknownCoordinateFrame;
    }
};

pub const Velocity3D = struct {
    vx_mps: f64,
    vy_mps: f64,
    vz_mps: f64,
    frame: CoordinateFrame,

    pub fn validateKnownFrame(self: Velocity3D) !void {
        if (self.frame == .unknown or self.frame == .wgs84) return error.UnknownCoordinateFrame;
    }
};

pub const Attitude = struct {
    roll_rad: f64,
    pitch_rad: f64,
    yaw_rad: f64,
};

pub const Heading = struct {
    value: f64,
    unit: AngleUnit,

    pub fn radians(value: f64) Heading {
        return .{ .value = value, .unit = .radians };
    }

    pub fn degrees(value: f64) Heading {
        return .{ .value = value, .unit = .degrees };
    }
};

pub const AccuracyEstimate = struct {
    horizontal_m: f64,
    vertical_m: f64,
    source: TimestampSource,

    pub fn validate(self: AccuracyEstimate) !void {
        if (self.horizontal_m < 0 or self.vertical_m < 0) return error.InvalidAccuracyEstimate;
        if (self.source == .unknown) return error.UnknownTimestampSource;
    }
};

pub const Timestamp = struct {
    value: i128,
    source: TimestampSource,

    pub fn validate(self: Timestamp) !void {
        if (self.source == .unknown) return error.MissingTimestamp;
    }
};

pub fn requireMatchingFrames(a: CoordinateFrame, b: CoordinateFrame) !void {
    if (a == .unknown or b == .unknown) return error.UnknownCoordinateFrame;
    if (a != b) return error.CoordinateFrameMismatch;
}

/// Conversion is intentionally narrow in Phase 26. NED/ENU/body/home transforms
/// require explicit math and reference metadata that later mediation phases must provide.
pub fn convertLocalPosition(position: LocalPosition, target_frame: CoordinateFrame) !LocalPosition {
    try position.validateKnownFrame();
    if (target_frame == .unknown or target_frame == .wgs84) return error.UnknownCoordinateFrame;
    if (position.frame == target_frame) return position;
    return error.UnsupportedCoordinateConversion;
}
