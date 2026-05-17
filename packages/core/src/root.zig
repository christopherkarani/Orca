pub const api = @import("api.zig");
pub const abi = @import("abi.zig");
pub const schemas = @import("schemas.zig");

const core_impl = @import("core_impl");

pub const core = core_impl.core;
pub const policy = core_impl.policy;
pub const audit = core_impl.audit;

pub const actions = core.types;
pub const decision = core.decision;
pub const event = core.event;
pub const limits = core.limits;
pub const platform = core.platform;
pub const session = core.session;
pub const types = core.types;
pub const util = core.util;

pub const phase = "core-engine-hard-split";

test {
    _ = api;
    _ = abi;
    _ = schemas;
    _ = core;
    _ = policy;
    _ = audit;
    _ = actions;
}
