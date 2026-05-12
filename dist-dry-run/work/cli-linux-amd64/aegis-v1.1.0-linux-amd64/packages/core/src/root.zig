const aegis = @import("aegis");

pub const api = @import("api.zig");
pub const abi = @import("abi.zig");
pub const schemas = @import("schemas.zig");

pub const core = aegis.core;
pub const policy = aegis.policy;
pub const audit = aegis.audit;
pub const intercept = aegis.intercept;
pub const redteam = aegis.redteam;
pub const capabilities = aegis.sandbox.backend;

pub const actions = core.types;
pub const decision = core.decision;
pub const event = core.event;
pub const limits = core.limits;
pub const platform = core.platform;
pub const session = core.session;
pub const types = core.types;
pub const util = core.util;

pub const phase = "24-aegis-core-library-and-abi";

test {
    _ = api;
    _ = abi;
    _ = schemas;
    _ = core;
    _ = policy;
    _ = audit;
    _ = intercept;
    _ = redteam;
    _ = capabilities;
    _ = actions;
}
