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

/// True when `s` is exactly 64 ASCII hex digits (`0-9`, `a-f`, `A-F`).
/// Production profile hashes are lowercase SHA-256 hex; uppercase is accepted for callers.
pub fn isValidProfileHashHex(s: []const u8) bool {
    if (s.len != 64) return false;
    for (s) |c| {
        if (!std.ascii.isHex(c)) return false;
    }
    return true;
}

/// Build an active receipt only when all attach conditions hold.
///
/// `profile_hash_hex` must be exactly 64 hex digits (SHA-256 hex of the compiled
/// profile). Empty, short, long, or non-hex inputs are rejected with
/// `error.InvalidProfileHash` — never zero-padded into a fake full hash.
pub fn activeReceipt(
    mechanism: BackendMechanism,
    profile_hash_hex: []const u8,
    fs_scope: []const u8,
) error{InvalidProfileHash}!AttachReceipt {
    if (!isValidProfileHashHex(profile_hash_hex)) return error.InvalidProfileHash;
    // Copy into owned fixed storage (N1: no borrow of caller-owned / ephemeral memory).
    var hex: [64]u8 = undefined;
    @memcpy(&hex, profile_hash_hex[0..64]);
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
///
/// Active path runs the launch allowlist on child env before attach (M-2 / M-20):
/// secret/provider keys are stripped, but intentional keepers (SSH_AUTH_SOCK,
/// TLS CA bundle vars) may remain — do not imply total credential wipe.
///
/// Unavailable/failed grade-drop keeps denylist-only scrub (injection keys
/// removed; provider credentials retained) — surface that honesty explicitly.
pub fn formatSessionBanner(buf: []u8, receipt: AttachReceipt) ![]const u8 {
    return switch (receipt.posture) {
        .active => try std.fmt.bufPrint(
            buf,
            "OS sandbox: active (filesystem: {s}; network: unrestricted; credentials: launch-allowlist (secrets stripped; agent sockets/certs may remain); tools: wrapper-mediated)",
            .{receipt.fs_scope},
        ),
        .unavailable => if (receipt.reason_code) |reason|
            try std.fmt.bufPrint(buf, "OS sandbox: unavailable ({s}; credentials retained)", .{reason})
        else
            try std.fmt.bufPrint(buf, "OS sandbox: unavailable (credentials retained)", .{}),
        .failed => if (receipt.reason_code) |reason|
            try std.fmt.bufPrint(buf, "OS sandbox: failed ({s}; credentials retained)", .{reason})
        else
            try std.fmt.bufPrint(buf, "OS sandbox: failed (credentials retained)", .{}),
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

/// Test fixture: full 64-char lowercase hex (SHA-256 width). Not a real profile hash.
const test_hash_64 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

test "active receipt requires mechanism and profile hash (S-GLO-01)" {
    const incomplete = AttachReceipt{
        .posture = .active,
        .mechanism = .none,
        .profile_hash_hex = null,
    };
    try std.testing.expect(!incomplete.isActive());

    const complete = try activeReceipt(.landlock, test_hash_64, "workspace RW, system RO, no home");
    try std.testing.expect(complete.isActive());
    try std.testing.expect(complete.posture.isOsEnforced());
    try std.testing.expectEqualStrings(test_hash_64, complete.profileHashSlice().?);
}

test "activeReceipt rejects empty, short, long, and non-hex profile hashes" {
    try std.testing.expectError(error.InvalidProfileHash, activeReceipt(.landlock, "", "workspace RW"));
    try std.testing.expectError(error.InvalidProfileHash, activeReceipt(.landlock, "abcd", "workspace RW"));
    try std.testing.expectError(error.InvalidProfileHash, activeReceipt(.seatbelt, "abc123", "workspace RW"));
    try std.testing.expectError(error.InvalidProfileHash, activeReceipt(.landlock, "deadbeef", "workspace RW"));
    // 63 hex digits
    try std.testing.expectError(error.InvalidProfileHash, activeReceipt(.landlock, test_hash_64[0..63], "workspace RW"));
    // 65 hex digits
    try std.testing.expectError(error.InvalidProfileHash, activeReceipt(.landlock, test_hash_64 ++ "0", "workspace RW"));
    // non-hex in an otherwise 64-length string
    const bad_hex = "g123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    try std.testing.expectEqual(@as(usize, 64), bad_hex.len);
    try std.testing.expectError(error.InvalidProfileHash, activeReceipt(.landlock, bad_hex, "workspace RW"));
}

test "activeReceipt accepts full 64 hex (lower and upper)" {
    const lower = try activeReceipt(.landlock, test_hash_64, "workspace child RW, root RO, system RO, no home");
    try std.testing.expect(lower.isActive());
    try std.testing.expectEqual(BackendMechanism.landlock, lower.mechanism);
    try std.testing.expectEqualStrings(test_hash_64, lower.profileHashSlice().?);

    const upper_src = "ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789";
    try std.testing.expectEqual(@as(usize, 64), upper_src.len);
    const upper = try activeReceipt(.seatbelt, upper_src, "workspace RW, system RO, no home");
    try std.testing.expect(upper.isActive());
    try std.testing.expectEqualStrings(upper_src, upper.profileHashSlice().?);
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
    var buf: [320]u8 = undefined;
    const active = try activeReceipt(.seatbelt, test_hash_64, "workspace RW, system RO, no home");
    const line = try formatSessionBanner(&buf, active);
    try std.testing.expect(std.mem.indexOf(u8, line, "OS sandbox: active") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "Seatbelt") == null);
    try std.testing.expect(std.mem.indexOf(u8, line, "Landlock") == null);
    try std.testing.expect(std.mem.indexOf(u8, line, "network: unrestricted") != null);
    // M-2 residual: secrets stripped, but intentional keepers may remain (not total wipe).
    try std.testing.expect(std.mem.indexOf(u8, line, "launch-allowlist") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "secrets stripped") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "agent sockets/certs may remain") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "as configured") == null);
}

test "grade-drop unavailable/failed banners mention credentials retained" {
    var buf: [256]u8 = undefined;
    const unavail = unavailableReceipt("backend_missing");
    const u_line = try formatSessionBanner(&buf, unavail);
    try std.testing.expect(std.mem.indexOf(u8, u_line, "OS sandbox: unavailable") != null);
    try std.testing.expect(std.mem.indexOf(u8, u_line, "backend_missing") != null);
    try std.testing.expect(std.mem.indexOf(u8, u_line, "credentials retained") != null);

    const failed = failedReceipt("apply_failed");
    const f_line = try formatSessionBanner(&buf, failed);
    try std.testing.expect(std.mem.indexOf(u8, f_line, "OS sandbox: failed") != null);
    try std.testing.expect(std.mem.indexOf(u8, f_line, "apply_failed") != null);
    try std.testing.expect(std.mem.indexOf(u8, f_line, "credentials retained") != null);

    // No reason_code still surfaces credential honesty.
    const bare = AttachReceipt{ .posture = .unavailable };
    const bare_line = try formatSessionBanner(&buf, bare);
    try std.testing.expect(std.mem.indexOf(u8, bare_line, "credentials retained") != null);
}

test "M-12 landlock fs_scope surfaces root RO create-at-root contract" {
    var buf: [320]u8 = undefined;
    // Production Landlock receipt string (apply.promoteWithProof).
    const active = try activeReceipt(.landlock, test_hash_64, "workspace child RW, root RO, system RO, no home");
    const line = try formatSessionBanner(&buf, active);
    try std.testing.expect(std.mem.indexOf(u8, line, "workspace child RW") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "root RO") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "Landlock") == null); // still mechanism-neutral
}
