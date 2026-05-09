const coordinates = @import("coordinates.zig");

pub const BoundaryAction = enum {
    deny,
    ask,
    return_to_home,
    land,
    hold,
};

pub const Polygon = struct {
    vertices: []const coordinates.GeoPoint,

    pub fn validate(self: Polygon) !void {
        if (self.vertices.len < 3) return error.InvalidGeofencePolygon;
        for (self.vertices) |vertex| try vertex.validate();
    }
};

pub const Circle = struct {
    center: coordinates.GeoPoint,
    max_radius_m: f64,

    pub fn validate(self: Circle) !void {
        try self.center.validate();
        if (self.max_radius_m <= 0) return error.InvalidGeofenceRadius;
    }
};

pub const GeofenceShape = union(enum) {
    allowed_polygon: Polygon,
    circle: Circle,
};

pub const Geofence = struct {
    shape: GeofenceShape,
    home_position: ?coordinates.GeoPoint = null,
    altitude_floor_m: f64,
    altitude_ceiling_m: f64,
    altitude_reference: coordinates.AltitudeReference,
    boundary_action: BoundaryAction,

    pub fn validate(self: Geofence) !void {
        switch (self.shape) {
            .allowed_polygon => |polygon| try polygon.validate(),
            .circle => |circle| try circle.validate(),
        }
        if (self.home_position) |home| try home.validate();
        if (self.altitude_reference == .unknown) return error.UnknownAltitudeReference;
        if (self.altitude_ceiling_m < self.altitude_floor_m) return error.InvalidAltitudeLimit;
    }
};
