pub const fixture = @import("fixture.zig");
pub const fault_injection = @import("fault_injection.zig");
pub const runner = @import("runner.zig");
pub const report = @import("report.zig");
pub const scorecard = @import("scorecard.zig");

pub const scenario = fixture;
pub const mavlink_attacks = @import("mavlink_attacks.zig");
pub const safety_attacks = @import("safety_attacks.zig");
pub const approval_attacks = @import("approval_attacks.zig");
pub const emergency_attacks = @import("emergency_attacks.zig");
pub const mission_attacks = @import("mission_attacks.zig");

pub const phase = "34-edge-redteam-and-fault-injection";
pub const implemented = true;

test {
    _ = fixture;
    _ = fault_injection;
    _ = runner;
    _ = report;
    _ = scorecard;
    _ = mavlink_attacks;
    _ = safety_attacks;
    _ = approval_attacks;
    _ = emergency_attacks;
    _ = mission_attacks;
}
