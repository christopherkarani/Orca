pub const audit = @import("audit.zig");
pub const command_mapping = @import("command_mapping.zig");
pub const connection = @import("connection.zig");
pub const fake_adapter = @import("fake_adapter.zig");
pub const health = @import("health.zig");
pub const scenario = @import("scenario.zig");
pub const sitl_adapter = @import("sitl_adapter.zig");
pub const telemetry_mapping = @import("telemetry_mapping.zig");

pub const phase = "29-px4-sitl-integration";
pub const tested_version_policy = "PX4 SITL integration is tested against the MAVLink common subset used by PX4 stable releases; set EDGE_BIN_PX4_TESTED_VERSION to record a local PX4 version in artifacts.";

test {
    _ = audit;
    _ = command_mapping;
    _ = connection;
    _ = fake_adapter;
    _ = health;
    _ = scenario;
    _ = sitl_adapter;
    _ = telemetry_mapping;
}
