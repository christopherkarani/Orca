pub const audit = @import("audit.zig");
pub const command_mapping = @import("command_mapping.zig");
pub const connection = @import("connection.zig");
pub const fake_adapter = @import("fake_adapter.zig");
pub const health = @import("health.zig");
pub const scenario = @import("scenario.zig");
pub const sitl_adapter = @import("sitl_adapter.zig");
pub const telemetry_mapping = @import("telemetry_mapping.zig");
pub const vehicle_kind = @import("vehicle_kind.zig");

pub const phase = "30-ardupilot-sitl-integration";
pub const tested_version_policy = "ArduPilot SITL integration starts with Copter-oriented MAVLink common-subset scenarios; set AEGIS_EDGE_ARDUPILOT_TESTED_VERSION to record a local ArduPilot version in artifacts.";

test {
    _ = audit;
    _ = command_mapping;
    _ = connection;
    _ = fake_adapter;
    _ = health;
    _ = scenario;
    _ = sitl_adapter;
    _ = telemetry_mapping;
    _ = vehicle_kind;
}
