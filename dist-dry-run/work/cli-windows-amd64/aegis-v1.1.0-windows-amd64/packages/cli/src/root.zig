const aegis = @import("aegis");
const aegis_core = @import("aegis_core");

pub const cli = aegis.cli;
pub const desktop = struct {
    pub const intercept = aegis.intercept;
    pub const mcp = aegis.mcp;
    pub const sandbox = aegis.sandbox;
};
pub const core = aegis_core;

pub const phase = "23-product-split-cli-contract";

test {
    _ = cli;
    _ = desktop;
    _ = core;
}
