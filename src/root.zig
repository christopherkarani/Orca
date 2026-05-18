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
pub const dashboard = @import("dashboard/mod.zig");
pub const report = @import("report.zig");
pub const license = @import("license.zig");
pub const ci_check = @import("ci_check.zig");
pub const demo = @import("demo.zig");
pub const resource_root = @import("resource_root.zig");

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
    _ = dashboard;
    _ = report;
    _ = license;
    _ = ci_check;
    _ = demo;
    _ = resource_root;
}
