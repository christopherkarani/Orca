const vehicle = @import("vehicle.zig");
const coordinates = @import("coordinates.zig");
const battery = @import("battery.zig");
const link = @import("link.zig");
const sensors = @import("sensors.zig");

pub const StateFreshness = enum {
    fresh,
    stale,
    expired,
    unknown,
};

pub const StateProvenance = enum {
    fake_adapter,
    sitl_px4,
    sitl_ardupilot,
    bench,
    customer_adapter,
    unknown,
};

pub const VehicleState = struct {
    vehicle_id: vehicle.VehicleId,
    vehicle_kind: vehicle.VehicleKind = .unknown,
    autopilot_kind: vehicle.AutopilotKind = .unknown,
    mode: vehicle.VehicleMode = .unknown,
    arm_state: vehicle.ArmState = .unknown,
    position: ?coordinates.GeoPoint = null,
    local_position: ?coordinates.LocalPosition = null,
    velocity: ?coordinates.Velocity3D = null,
    attitude: ?coordinates.Attitude = null,
    heading: ?coordinates.Heading = null,
    battery_state: ?battery.BatteryState = null,
    gps_state: ?sensors.GpsState = null,
    link_state: ?link.LinkState = null,
    sensor_state: ?sensors.SensorState = null,
    control_authority: vehicle.ControlAuthority = .unknown,
    home_position: ?coordinates.GeoPoint = null,
    timestamp: coordinates.Timestamp,
    state_freshness: StateFreshness = .unknown,
    provenance: StateProvenance = .unknown,

    pub fn validateForAudit(self: VehicleState) !void {
        try self.vehicle_id.validate();
        try self.timestamp.validate();
        if (self.position) |position| try position.validate();
        if (self.local_position) |position| try position.validateKnownFrame();
        if (self.velocity) |velocity| try velocity.validateKnownFrame();
        if (self.battery_state) |battery_state| try battery_state.validate();
        if (self.gps_state) |gps_state| try gps_state.validate();
        if (self.link_state) |link_state| try link_state.validate();
        if (self.sensor_state) |sensor_state| try sensor_state.validate();
        if (self.home_position) |home| try home.validate();
        if (self.provenance == .unknown) return error.UnknownStateIsUnsafe;
    }

    pub fn validateFreshKnown(self: VehicleState) !void {
        try self.validateForAudit();
        if (self.state_freshness != .fresh) return error.StateNotFresh;
        if (self.vehicle_kind == .unknown or
            self.autopilot_kind == .unknown or
            self.mode == .unknown or
            self.arm_state == .unknown or
            self.control_authority == .unknown)
        {
            return error.UnknownStateIsUnsafe;
        }
    }

    pub fn requireFakeAdapterProvenance(self: VehicleState, adapter_kind: vehicle.AdapterKind) !void {
        if (adapter_kind == .fake and self.provenance != .fake_adapter) return error.FakeStateMislabeledAsSitlOrHardware;
    }
};
