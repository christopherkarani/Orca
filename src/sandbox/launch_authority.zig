//! Documents and enforces the single production apply-before-exec authority (P0-A-03).
//!
//! Production agent launch for `orca run` is:
//!   apply.applyBeforeExec → supervisor.run → process.prepareChild → std.process.spawn
//!
//! `sandbox.backend.prepare` / PreparedSandbox is capability scaffolding and unit-test surface
//! until it is folded into the production path. It must never alone authorize a session
//! posture of `active`.
//!
//! U04 wires the apply seam (`production_apply_wired = true`). Session `active` still
//! requires `receipt.isActive()` (mechanism + profile hash), which stub backends cannot
//! satisfy until U05/U06.

const std = @import("std");
const backend = @import("backend.zig");
const posture = @import("posture.zig");

pub const ProductionLaunchAuthority = enum {
    /// Zig supervisor + process.prepareChild (current production), preceded by apply seam.
    supervisor_process,
};

/// U04+: apply seam exists on the production launch path.
/// Active claims still require a real attach receipt (stubs cannot satisfy).
pub const production_apply_wired = true;

pub fn productionAuthority() ProductionLaunchAuthority {
    return .supervisor_process;
}

/// Scaffold prepare must not satisfy attach.
pub fn scaffoldPrepareIsAttachAuthority() bool {
    return false;
}

/// Session active requires the production apply seam and a complete attach receipt.
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

test "production apply seam is wired (U04)" {
    try std.testing.expect(production_apply_wired);
}

test "session active still requires complete attach receipt (S-GLO-01)" {
    const unavailable = posture.unavailableReceipt("backend_not_implemented");
    try std.testing.expect(!mayReportSessionActive(unavailable));
    try std.testing.expect(!mayReportSessionActive(posture.disabledReceipt()));
    try std.testing.expect(!mayReportSessionActive(posture.failedReceipt("apply_failed")));

    // Incomplete active claim (no mechanism/hash) is rejected even when wired.
    const incomplete = posture.AttachReceipt{
        .posture = .active,
        .mechanism = .none,
        .profile_hash_hex = null,
    };
    try std.testing.expect(!incomplete.isActive());
    try std.testing.expect(!mayReportSessionActive(incomplete));

    // Complete receipt shape is allowed by the authority gate; only real backends
    // (U05/U06) may construct one on the production path.
    const complete = posture.activeReceipt(.landlock, "hash", "workspace RW");
    try std.testing.expect(complete.isActive());
    try std.testing.expect(mayReportSessionActive(complete));
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
