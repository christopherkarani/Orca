const aegis_core = @import("aegis_core");

pub const cli = @import("cli/mod.zig");
pub const core = aegis_core.core;
pub const core_api = aegis_core.api;
pub const policy = aegis_core.policy;
pub const audit = aegis_core.audit;
pub const intercept = @import("intercept/mod.zig");
pub const mcp = @import("mcp/mod.zig");
pub const sandbox = @import("sandbox/mod.zig");
pub const redteam = @import("redteam/mod.zig");
pub const release = @import("release/mod.zig");

test {
    _ = cli;
    _ = core;
    _ = core_api;
    _ = policy;
    _ = audit;
    _ = intercept;
    _ = mcp;
    _ = sandbox;
    _ = redteam;
    _ = release;
}
