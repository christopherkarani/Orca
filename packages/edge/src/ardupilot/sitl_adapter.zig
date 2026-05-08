const std = @import("std");

const domain = @import("../domain/mod.zig");
const mavlink = @import("../mavlink/mod.zig");
const schema = @import("../schema/mod.zig");
const connection = @import("connection.zig");

pub const Options = struct {
    environment: connection.Environment = .fake_ardupilot,
    mode: connection.Mode = .observe,
    vehicle_id: []const u8 = "edge-vehicle-1",
    now_ms: i128,
    endpoint_policy: mavlink.gateway.EndpointPolicy = .{},
};

pub const Adapter = struct {
    options: Options,

    pub fn init(options: Options) Adapter {
        return .{ .options = options };
    }

    pub fn mediateFrame(
        self: Adapter,
        allocator: std.mem.Allocator,
        selected_policy: *const schema.edge_policy_schema.EdgePolicyV1,
        state: domain.state.VehicleState,
        frame: mavlink.framing.Frame,
    ) !mavlink.gateway.ProcessResult {
        return mavlink.gateway.processFrame(allocator, .{
            .mode = gatewayMode(self.options.mode),
            .direction = .companion_to_vehicle,
            .vehicle_id = self.options.vehicle_id,
            .now_ms = self.options.now_ms,
            .command_source = provenanceFor(self.options.environment),
            .endpoint_policy = self.options.endpoint_policy,
        }, selected_policy, state, frame);
    }
};

pub fn gatewayMode(mode: connection.Mode) mavlink.gateway.GatewayMode {
    return switch (mode) {
        .observe => .observe,
        .enforce => .enforce,
        .simulation => .simulation,
        .ci => .ci,
        .redteam => .redteam,
        .bench => .bench,
    };
}

pub fn provenanceFor(environment: connection.Environment) domain.state.StateProvenance {
    return switch (environment) {
        .fake_ardupilot => .fake_ardupilot_adapter,
        .ardupilot_sitl => .sitl_ardupilot,
    };
}
