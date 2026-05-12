const data_classification = @import("data_classification.zig");

pub fn classesForSensorMetadata() []const data_classification.DataClass {
    return &.{ .sensor_metadata, .vehicle_identifier };
}

pub fn classesForImageSnapshot() []const data_classification.DataClass {
    return &.{ .image_frame, .sensor_metadata, .geolocation };
}

pub fn classesForVideoStream() []const data_classification.DataClass {
    return &.{ .video_stream, .sensor_metadata, .geolocation };
}
