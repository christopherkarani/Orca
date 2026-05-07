const aegis = @import("aegis");

pub const core = aegis.core;
pub const policy = aegis.policy;
pub const audit = aegis.audit;
pub const intercept = aegis.intercept;
pub const redteam = aegis.redteam;
pub const capabilities = aegis.sandbox.backend;

pub const decision = core.decision;
pub const event = core.event;
pub const limits = core.limits;
pub const platform = core.platform;
pub const session = core.session;
pub const types = core.types;
pub const util = core.util;

pub const phase = "23-product-split-core-contract";

test {
    _ = core;
    _ = policy;
    _ = audit;
    _ = intercept;
    _ = redteam;
    _ = capabilities;
}
