//! Session vs doctor posture vocabulary for OS filesystem sandbox.
//!
//! Doctor reports capability availability only.
//! Live sessions may report active only after profile compile + apply +
//! child attach handshake + profile hash recording (S-GLO-01).

const std = @import("std");

/// Live session posture after launch attempt.
pub const SessionPosture = enum {
    active,
    unavailable,
    failed,
    disabled,

    pub fn toString(self: SessionPosture) []const u8 {
        return @tagName(self);
    }

    /// Only active may map to OS-enforced grade for filesystem scope.
    pub fn isOsEnforced(self: SessionPosture) bool {
        return self == .active;
    }
};

pub const OsSandboxMode = enum {
    auto,
    on,
    off,

    pub fn parse(value: []const u8) ?OsSandboxMode {
        if (std.mem.eql(u8, value, "auto")) return .auto;
        if (std.mem.eql(u8, value, "on")) return .on;
        if (std.mem.eql(u8, value, "off")) return .off;
        return null;
    }

    pub fn toString(self: OsSandboxMode) []const u8 {
        return @tagName(self);
    }
};

/// Mechanism names are for verbose diagnostics only (S-GLO-03).
pub const BackendMechanism = enum {
    none,
    landlock,
    seatbelt,

    pub fn toString(self: BackendMechanism) []const u8 {
        return @tagName(self);
    }

    pub fn verboseName(self: BackendMechanism) []const u8 {
        return switch (self) {
            .none => "none",
            .landlock => "Landlock",
            .seatbelt => "Seatbelt",
        };
    }
};

pub const AttachReceipt = struct {
    posture: SessionPosture,
    mechanism: BackendMechanism = .none,
    /// Owned hex hash when active (fixed storage — avoids UAF on returned receipts).
    profile_hash_hex: ?[64]u8 = null,
    fs_scope: []const u8 = "none",
    reason_code: ?[]const u8 = null,

    pub fn isActive(self: AttachReceipt) bool {
        return self.posture == .active and self.profile_hash_hex != null and self.mechanism != .none;
    }

    /// View the owned hash as a slice (valid for lifetime of this receipt value).
    pub fn profileHashSlice(self: *const AttachReceipt) ?[]const u8 {
        if (self.profile_hash_hex) |*h| return h[0..];
        return null;
    }
};

/// Build an active receipt only when all attach conditions hold.
pub fn activeReceipt(
    mechanism: BackendMechanism,
    profile_hash_hex: []const u8,
    fs_scope: []const u8,
) AttachReceipt {
    // Copy into owned fixed storage (N1: no borrow of caller-owned / ephemeral memory).
    var hex: [64]u8 = .{'0'} ** 64;
    const n = @min(profile_hash_hex.len, 64);
    @memcpy(hex[0..n], profile_hash_hex[0..n]);
    return .{
        .posture = .active,
        .mechanism = mechanism,
        .profile_hash_hex = hex,
        .fs_scope = fs_scope,
        .reason_code = null,
    };
}

pub fn disabledReceipt() AttachReceipt {
    return .{
        .posture = .disabled,
        .mechanism = .none,
        .profile_hash_hex = null,
        .fs_scope = "none",
        .reason_code = "os_sandbox_off",
    };
}

pub fn unavailableReceipt(reason_code: []const u8) AttachReceipt {
    return .{
        .posture = .unavailable,
        .mechanism = .none,
        .profile_hash_hex = null,
        .fs_scope = "none",
        .reason_code = reason_code,
    };
}

pub fn failedReceipt(reason_code: []const u8) AttachReceipt {
    return .{
        .posture = .failed,
        .mechanism = .none,
        .profile_hash_hex = null,
        .fs_scope = "none",
        .reason_code = reason_code,
    };
}

/// Default user-facing banner language (mechanism-neutral).
pub fn formatSessionBanner(buf: []u8, receipt: AttachReceipt) ![]const u8 {
    return switch (receipt.posture) {
        .active => try std.fmt.bufPrint(
            buf,
            "OS sandbox: active (filesystem: {s}; network: unrestricted; credentials: session env as configured; tools: wrapper-mediated)",
            .{receipt.fs_scope},
        ),
        .unavailable => if (receipt.reason_code) |reason|
            try std.fmt.bufPrint(buf, "OS sandbox: unavailable ({s})", .{reason})
        else
            try std.fmt.bufPrint(buf, "OS sandbox: unavailable", .{}),
        .failed => if (receipt.reason_code) |reason|
            try std.fmt.bufPrint(buf, "OS sandbox: failed ({s})", .{reason})
        else
            try std.fmt.bufPrint(buf, "OS sandbox: failed", .{}),
        .disabled => try std.fmt.bufPrint(buf, "OS sandbox: disabled", .{}),
    };
}

/// Compact audit reason for `sandbox_posture` events (no SBPL / Landlock rule text).
pub fn formatAuditReason(buf: []u8, receipt: AttachReceipt) ![]const u8 {
    const posture_str = receipt.posture.toString();
    const fs_scope = receipt.fs_scope;
    if (receipt.profileHashSlice()) |hash| {
        return try std.fmt.bufPrint(buf, "posture={s}; profile_hash={s}; fs_scope={s}", .{ posture_str, hash, fs_scope });
    } else if (receipt.reason_code) |code| {
        return try std.fmt.bufPrint(buf, "posture={s}; fs_scope={s}; reason={s}", .{ posture_str, fs_scope, code });
    } else {
        return try std.fmt.bufPrint(buf, "posture={s}; fs_scope={s}", .{ posture_str, fs_scope });
    }
}

test "active receipt requires mechanism and profile hash (S-GLO-01)" {
    const incomplete = AttachReceipt{
        .posture = .active,
        .mechanism = .none,
        .profile_hash_hex = null,
    };
    try std.testing.expect(!incomplete.isActive());

    const complete = activeReceipt(.landlock, "abc123", "workspace RW, system RO, no home");
    try std.testing.expect(complete.isActive());
    try std.testing.expect(complete.posture.isOsEnforced());
}

test "disabled and unavailable receipts are not OS-enforced" {
    try std.testing.expect(!disabledReceipt().isActive());
    try std.testing.expect(!unavailableReceipt("backend_missing").isActive());
    try std.testing.expect(!failedReceipt("apply_failed").isActive());
}

test "os-sandbox mode parse" {
    try std.testing.expectEqual(OsSandboxMode.auto, OsSandboxMode.parse("auto").?);
    try std.testing.expectEqual(OsSandboxMode.on, OsSandboxMode.parse("on").?);
    try std.testing.expectEqual(OsSandboxMode.off, OsSandboxMode.parse("off").?);
    try std.testing.expect(OsSandboxMode.parse("seatbelt") == null);
}

test "session banner is mechanism-neutral (S-GLO-03)" {
    var buf: [256]u8 = undefined;
    const active = activeReceipt(.seatbelt, "deadbeef", "workspace RW, system RO, no home");
    const line = try formatSessionBanner(&buf, active);
    try std.testing.expect(std.mem.indexOf(u8, line, "OS sandbox: active") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "Seatbelt") == null);
    try std.testing.expect(std.mem.indexOf(u8, line, "Landlock") == null);
    try std.testing.expect(std.mem.indexOf(u8, line, "network: unrestricted") != null);
}
