//! Documents and enforces the single production apply-before-exec authority (P0-A-03).
//!
//! Production agent launch for `orca run` is:
//!   supervisor.run → process.prepareChild → std.process.spawn
//!
//! `sandbox.backend.prepare` / PreparedSandbox is capability scaffolding and unit-test surface
//! until it is folded into the production path. It must never alone authorize a session
//! posture of `active`.

const std = @import("std");
const backend = @import("backend.zig");
const posture = @import("posture.zig");

pub const ProductionLaunchAuthority = enum {
    /// Zig supervisor + process.prepareChild (current production).
    supervisor_process,
};

/// Until apply is wired, production cannot claim OS FS attach.
pub const production_apply_wired = false;

pub fn productionAuthority() ProductionLaunchAuthority {
    return .supervisor_process;
}

/// Scaffold prepare must not satisfy attach.
pub fn scaffoldPrepareIsAttachAuthority() bool {
    return false;
}

/// Session active is forbidden when production apply is not wired.
pub fn mayReportSessionActive(receipt: posture.AttachReceipt) bool {
    if (!production_apply_wired) return false;
    return receipt.isActive();
}

test "production launch authority is supervisor_process (P0-A-03)" {
    try std.testing.expectEqual(ProductionLaunchAuthority.supervisor_process, productionAuthority());
}

test "scaffold prepare is not attach authority (P0-A-03)" {
    try std.testing.expect(!scaffoldPrepareIsAttachAuthority());
}

test "session active forbidden while production apply unwired (S-GLO-01)" {
    const forged = posture.activeReceipt(.landlock, "hash", "workspace RW");
    try std.testing.expect(forged.isActive());
    try std.testing.expect(!mayReportSessionActive(forged));
}

test "backend strong_sandbox featureAvailable is false on all detect paths" {
    const linux = backend.detect(.linux);
    const macos = backend.detect(.macos);
    const windows = backend.detect(.windows);
    try std.testing.expect(!linux.featureAvailable(.strong_sandbox));
    try std.testing.expect(!macos.featureAvailable(.strong_sandbox));
    try std.testing.expect(!windows.featureAvailable(.strong_sandbox));
    try std.testing.expect(linux.get(.strong_sandbox).level != .active);
    try std.testing.expect(macos.get(.strong_sandbox).level != .active);
    try std.testing.expect(windows.get(.strong_sandbox).level != .active);
}
