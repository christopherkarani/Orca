const orca = @import("orca");
const orca_core = @import("orca_core");

pub const cli = orca.cli;
pub const desktop = struct {
    pub const intercept = orca.intercept;
    pub const mcp = orca.mcp;
    pub const sandbox = orca.sandbox;
};
pub const core = orca_core;

pub const phase = "23-product-split-cli-contract";

test {
    _ = cli;
    _ = desktop;
    _ = core;
}
