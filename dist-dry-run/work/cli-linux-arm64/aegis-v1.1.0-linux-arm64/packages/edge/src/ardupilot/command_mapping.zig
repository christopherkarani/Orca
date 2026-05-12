const domain = @import("../domain/mod.zig");
const mavlink = @import("../mavlink/mod.zig");
const connection = @import("connection.zig");
const sitl_adapter = @import("sitl_adapter.zig");

pub fn sourceForEnvironment(environment: connection.Environment) domain.state.StateProvenance {
    return sitl_adapter.provenanceFor(environment);
}

pub fn gatewayMode(mode: connection.Mode) mavlink.gateway.GatewayMode {
    return sitl_adapter.gatewayMode(mode);
}
