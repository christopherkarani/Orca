const std = @import("std");

pub const DataClass = enum {
    public,
    operational,
    vehicle_state,
    vehicle_identifier,
    mission_plan,
    geolocation,
    operator_identifier,
    customer_identifier,
    sensor_metadata,
    image_frame,
    video_stream,
    audio_stream,
    map_data,
    safety_finding,
    audit_metadata,
    credential,
    secret,
    unknown,

    pub fn toString(self: DataClass) []const u8 {
        return @tagName(self);
    }

    pub fn parse(value: []const u8) ?DataClass {
        inline for (std.meta.fields(DataClass)) |field| {
            if (matchesNormalized(field.name, value)) return @field(DataClass, field.name);
        }
        return null;
    }
};

pub const Sensitivity = enum {
    low,
    medium,
    high,
    critical,
    unknown,

    pub fn toString(self: Sensitivity) []const u8 {
        return @tagName(self);
    }
};

pub const ChannelKind = enum {
    mavlink_telemetry,
    command_control,
    mission_upload,
    mission_download,
    video_stream,
    image_snapshot,
    sensor_metadata,
    audit_report,
    safety_case_report,
    operator_approval,
    emergency_status,
    heartbeat,
    health_status,
    unknown,

    pub fn toString(self: ChannelKind) []const u8 {
        return @tagName(self);
    }

    pub fn parse(value: []const u8) ?ChannelKind {
        if (matchesNormalized("vehicle_state", value)) return .mavlink_telemetry;
        inline for (std.meta.fields(ChannelKind)) |field| {
            if (matchesNormalized(field.name, value)) return @field(ChannelKind, field.name);
        }
        return null;
    }
};

pub const Direction = enum {
    inbound,
    outbound,
    internal,
    external,
    vehicle_to_agent,
    agent_to_vehicle,
    edge_to_ground,
    edge_to_customer_endpoint,
    unknown,

    pub fn toString(self: Direction) []const u8 {
        return @tagName(self);
    }

    pub fn parse(value: []const u8) ?Direction {
        inline for (std.meta.fields(Direction)) |field| {
            if (matchesNormalized(field.name, value)) return @field(Direction, field.name);
        }
        return null;
    }
};

pub const RedactionStatus = enum {
    none,
    required,
    redacted,
    coarsened,
    minimized,
    denied,

    pub fn toString(self: RedactionStatus) []const u8 {
        return @tagName(self);
    }
};

pub const ClassificationResult = struct {
    allocator: std.mem.Allocator,
    classes: []DataClass,
    sensitivity: Sensitivity,
    size_bytes: usize,
    fingerprint: [64]u8,

    pub fn deinit(self: *ClassificationResult) void {
        self.allocator.free(self.classes);
        self.* = undefined;
    }

    pub fn hasClass(self: ClassificationResult, class: DataClass) bool {
        for (self.classes) |candidate| {
            if (candidate == class) return true;
        }
        return false;
    }

    pub fn highestClass(self: ClassificationResult) DataClass {
        var selected: DataClass = .public;
        var selected_score: u8 = 0;
        for (self.classes) |class| {
            const score = sensitivityScore(defaultSensitivity(class));
            if (score >= selected_score) {
                selected = class;
                selected_score = score;
            }
        }
        return selected;
    }
};

pub const TelemetryPayload = struct {
    channel_kind: ChannelKind = .unknown,
    direction: Direction = .unknown,
    source: []const u8 = "unknown",
    destination: []const u8 = "unknown",
    vehicle_id: ?[]const u8 = null,
    scenario_id: ?[]const u8 = null,
    provenance: []const u8 = "unknown",
    payload: []const u8 = "",
    declared_classes: []const DataClass = &.{},
    declared_sensitivity: ?Sensitivity = null,
    size_bytes: ?usize = null,
    timestamp_ms: ?i128 = null,
    redaction_status: RedactionStatus = .none,

    pub fn effectiveSize(self: TelemetryPayload) usize {
        return self.size_bytes orelse self.payload.len;
    }
};

pub fn classifyPayload(allocator: std.mem.Allocator, payload: []const u8) !ClassificationResult {
    var classes: std.ArrayList(DataClass) = .empty;
    errdefer classes.deinit(allocator);

    if (containsAny(payload, &.{ "fake_secret", "fake-secret", "secret_value", "secret-value", "private_key", "\"secret\"", " secret:" })) try appendClass(allocator, &classes, .secret);
    if (containsAny(payload, &.{ "api_key", "apikey", "authorization", "bearer ", "password", "passwd", "\"token\"", "access_token", "credential" })) try appendClass(allocator, &classes, .credential);
    if (containsAny(payload, &.{ "vehicle_state", "armed", "battery", "mode", "velocity", "altitude", "attitude" })) try appendClass(allocator, &classes, .vehicle_state);
    if (containsAny(payload, &.{ "vehicle_id", "vehicleid", "sysid", "compid", "serial_number", "autopilot_id" })) try appendClass(allocator, &classes, .vehicle_identifier);
    if (containsAny(payload, &.{ "mission_plan", "mission_items", "mission_upload", "mission_download", "waypoint", "waypoints" })) try appendClass(allocator, &classes, .mission_plan);
    if (containsAny(payload, &.{ "latitude", "longitude", "lat_deg", "lon_deg", "lat_int", "lon_int", "\"lat\"", "\"lon\"", "\"x\"", "\"y\"" })) try appendClass(allocator, &classes, .geolocation);
    if (containsAny(payload, &.{ "operator_id", "pilot_id", "operator_identifier", "operator_email" })) try appendClass(allocator, &classes, .operator_identifier);
    if (containsAny(payload, &.{ "customer_id", "tenant_id", "account_id", "customer_identifier" })) try appendClass(allocator, &classes, .customer_identifier);
    if (containsAny(payload, &.{ "sensor", "\"imu\"", " gps", "\"gps\"", "magnetometer", "barometer", "camera_metadata", "frame_metadata" })) try appendClass(allocator, &classes, .sensor_metadata);
    if (containsAny(payload, &.{ "image_frame", "image_snapshot", "\"image\"", "jpeg", "png", "exif" })) try appendClass(allocator, &classes, .image_frame);
    if (containsAny(payload, &.{ "video_stream", "\"video\"", "h264", "rtsp", "stream_url" })) try appendClass(allocator, &classes, .video_stream);
    if (containsAny(payload, &.{ "audio_stream", "\"audio\"", "microphone" })) try appendClass(allocator, &classes, .audio_stream);
    if (containsAny(payload, &.{ "map_data", "tile", "basemap", "mapbox", "osm" })) try appendClass(allocator, &classes, .map_data);
    if (containsAny(payload, &.{ "safety_finding", "safety_case", "finding", "violation", "denied" })) try appendClass(allocator, &classes, .safety_finding);
    if (containsAny(payload, &.{ "audit", "event_id", "session_id", "event_hash", "traceability" })) try appendClass(allocator, &classes, .audit_metadata);
    if (containsAny(payload, &.{ "heartbeat", "health_status" })) try appendClass(allocator, &classes, .operational);
    if (containsAny(payload, &.{ "public", "documentation", "example" })) try appendClass(allocator, &classes, .public);

    if (classes.items.len == 0) try appendClass(allocator, &classes, .unknown);

    const owned = try classes.toOwnedSlice(allocator);
    errdefer allocator.free(owned);
    return .{
        .allocator = allocator,
        .classes = owned,
        .sensitivity = sensitivityForClasses(owned),
        .size_bytes = payload.len,
        .fingerprint = fingerprint(payload),
    };
}

pub fn inferChannel(classification: ClassificationResult) ChannelKind {
    if (classification.hasClass(.video_stream)) return .video_stream;
    if (classification.hasClass(.image_frame)) return .image_snapshot;
    if (classification.hasClass(.mission_plan)) return .mission_upload;
    if (classification.hasClass(.sensor_metadata)) return .sensor_metadata;
    if (classification.hasClass(.safety_finding) or classification.hasClass(.audit_metadata)) return .safety_case_report;
    if (classification.hasClass(.vehicle_state) or classification.hasClass(.geolocation)) return .mavlink_telemetry;
    if (classification.hasClass(.operational)) return .health_status;
    return .unknown;
}

pub fn sensitivityForClasses(classes: []const DataClass) Sensitivity {
    var selected: Sensitivity = .low;
    for (classes) |class| {
        const candidate = defaultSensitivity(class);
        if (sensitivityScore(candidate) > sensitivityScore(selected)) selected = candidate;
    }
    return selected;
}

pub fn defaultSensitivity(class: DataClass) Sensitivity {
    return switch (class) {
        .credential, .secret => .critical,
        .geolocation,
        .mission_plan,
        .operator_identifier,
        .customer_identifier,
        .image_frame,
        .video_stream,
        .audio_stream,
        => .high,
        .vehicle_state,
        .vehicle_identifier,
        .sensor_metadata,
        .map_data,
        .safety_finding,
        => .medium,
        .public, .operational, .audit_metadata => .low,
        .unknown => .unknown,
    };
}

pub fn sensitivityScore(value: Sensitivity) u8 {
    return switch (value) {
        .low => 1,
        .medium => 2,
        .high => 3,
        .critical => 4,
        .unknown => 5,
    };
}

pub fn appendClass(allocator: std.mem.Allocator, classes: *std.ArrayList(DataClass), class: DataClass) !void {
    for (classes.items) |existing| {
        if (existing == class) return;
    }
    try classes.append(allocator, class);
}

pub fn fingerprint(payload: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(payload, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

pub fn containsAny(haystack: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (containsIgnoreCase(haystack, needle)) return true;
    }
    return false;
}

pub fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return true;
    }
    return false;
}

pub fn matchesNormalized(expected: []const u8, value: []const u8) bool {
    var e: usize = 0;
    var v: usize = 0;
    while (e < expected.len and v < value.len) {
        while (e < expected.len and (expected[e] == '_' or expected[e] == '-')) e += 1;
        while (v < value.len and (value[v] == '_' or value[v] == '-')) v += 1;
        if (e >= expected.len or v >= value.len) break;
        if (std.ascii.toLower(expected[e]) != std.ascii.toLower(value[v])) return false;
        e += 1;
        v += 1;
    }
    while (e < expected.len and (expected[e] == '_' or expected[e] == '-')) e += 1;
    while (v < value.len and (value[v] == '_' or value[v] == '-')) v += 1;
    return e == expected.len and v == value.len;
}

test "classifies mission geolocation and fake secrets as unsafe" {
    var result = try classifyPayload(std.testing.allocator, "{\"mission_plan\":{\"waypoints\":[{\"latitude\":37.0,\"longitude\":-122.0}]},\"api_key\":\"sk-fakeSyntheticOpenAIKey1234567890\"}");
    defer result.deinit();
    try std.testing.expect(result.hasClass(.mission_plan));
    try std.testing.expect(result.hasClass(.geolocation));
    try std.testing.expect(result.hasClass(.credential));
    try std.testing.expectEqual(Sensitivity.critical, result.sensitivity);
}

test "unknown payload is not safe" {
    var result = try classifyPayload(std.testing.allocator, "{\"opaque\":\"blob\"}");
    defer result.deinit();
    try std.testing.expect(result.hasClass(.unknown));
    try std.testing.expectEqual(Sensitivity.unknown, result.sensitivity);
}
