//! Immutable evidence manifest for security gate verification (P0-I-06, S-GLO-09).
//!
//! Evidence files live under gitignored planning/security/evidence/ and must never
//! contain raw secret values or live canary bodies.

const std = @import("std");

pub const schema_version: u16 = 1;

pub const ControlResult = struct {
    ok: bool,
    detail: []const u8 = "",
};

pub const Manifest = struct {
    schema_version: u16 = schema_version,
    gate_ids: []const []const u8,
    case_id: []const u8,
    source_commit: []const u8,
    binary_sha256: []const u8,
    platform_os: []const u8,
    platform_arch: []const u8,
    backend_id: []const u8,
    profile_hash: []const u8 = "",
    command: []const u8,
    exit_code: i32 = 0,
    ctrl_baseline: ControlResult,
    /// Optional/partial prepare path; not required by allControlsPass.
    ctrl_prepare: ControlResult = .{ .ok = false },
    ctrl_attach: ControlResult,
    test_deny: ControlResult,
    ctrl_neighbor: ControlResult,
    ctrl_off: ControlResult,
    canary_fingerprint: []const u8 = "",
    rerun: []const u8 = "",

    pub fn allControlsPass(self: Manifest) bool {
        // ctrl_prepare is optional/partial and is intentionally not required.
        return self.ctrl_baseline.ok and
            self.ctrl_attach.ok and
            self.test_deny.ok and
            self.ctrl_neighbor.ok and
            self.ctrl_off.ok;
    }

    pub fn validate(self: Manifest) !void {
        if (self.schema_version != schema_version) return error.UnsupportedSchemaVersion;
        if (self.gate_ids.len == 0) return error.MissingGateIds;
        if (self.case_id.len == 0) return error.MissingCaseId;
        if (self.source_commit.len == 0) return error.MissingSourceCommit;
        if (self.binary_sha256.len == 0) return error.MissingBinaryHash;
        if (self.platform_os.len == 0) return error.MissingPlatform;
        if (self.command.len == 0) return error.MissingCommand;
        // Probe-only / prepare-only attach is forbidden for enforcement manifests (F-1).
        if (std.mem.eql(u8, self.ctrl_attach.detail, "capability_probe")) return error.ProbeOnlyAttach;
        if (std.mem.eql(u8, self.ctrl_attach.detail, "zig_status_pipe_or_prepare_handshake")) return error.PrepareOnlyAttach;
        if (std.mem.indexOf(u8, self.ctrl_attach.detail, "prepare") != null and
            std.mem.indexOf(u8, self.ctrl_attach.detail, "without") != null)
        {
            return error.PrepareOnlyAttach;
        }
        // Unit-canary-only attach (no production handshake) is forbidden for enforcement.
        // Dual-proof details (e.g. zig_real_fs_deny_canary_and_handshake) remain allowed.
        if (std.mem.eql(u8, self.ctrl_attach.detail, "zig_real_fs_deny_canary")) return error.UnitCanaryOnlyAttach;
        // CTRL-ATTACH without TEST-DENY is not an enforcement claim.
        if (self.ctrl_attach.ok and !self.test_deny.ok) return error.AttachWithoutDeny;
    }
};

pub fn writeJson(allocator: std.mem.Allocator, manifest: Manifest) ![]u8 {
    try manifest.validate();
    var aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer aw.deinit();
    const w = &aw.writer;

    try w.writeAll("{\n");
    try w.print("  \"schema_version\": {d},\n", .{manifest.schema_version});
    try w.writeAll("  \"gate_ids\": [");
    for (manifest.gate_ids, 0..) |id, i| {
        if (i > 0) try w.writeAll(", ");
        try w.print("\"{s}\"", .{id});
    }
    try w.writeAll("],\n");
    try w.print("  \"case_id\": \"{s}\",\n", .{manifest.case_id});
    try w.print("  \"source_commit\": \"{s}\",\n", .{manifest.source_commit});
    try w.print("  \"binary_sha256\": \"{s}\",\n", .{manifest.binary_sha256});
    try w.print("  \"platform\": {{\"os\": \"{s}\", \"arch\": \"{s}\"}},\n", .{ manifest.platform_os, manifest.platform_arch });
    try w.print("  \"backend_id\": \"{s}\",\n", .{manifest.backend_id});
    try w.print("  \"profile_hash\": \"{s}\",\n", .{manifest.profile_hash});
    try w.print("  \"command\": \"{s}\",\n", .{manifest.command});
    try w.print("  \"exit_code\": {d},\n", .{manifest.exit_code});
    try w.writeAll("  \"controls\": {\n");
    try writeControl(w, "CTRL-BASELINE", manifest.ctrl_baseline);
    try w.writeAll(",\n");
    try writeControl(w, "CTRL-PREPARE", manifest.ctrl_prepare);
    try w.writeAll(",\n");
    try writeControl(w, "CTRL-ATTACH", manifest.ctrl_attach);
    try w.writeAll(",\n");
    try writeControl(w, "TEST-DENY", manifest.test_deny);
    try w.writeAll(",\n");
    try writeControl(w, "CTRL-NEIGHBOR", manifest.ctrl_neighbor);
    try w.writeAll(",\n");
    try writeControl(w, "CTRL-OFF", manifest.ctrl_off);
    try w.writeAll("\n  },\n");
    try w.print("  \"canary_fingerprint\": \"{s}\",\n", .{manifest.canary_fingerprint});
    try w.print("  \"rerun\": \"{s}\"\n", .{manifest.rerun});
    try w.writeAll("}\n");
    return try aw.toOwnedSlice();
}

fn writeControl(w: anytype, name: []const u8, result: ControlResult) !void {
    try w.print("    \"{s}\": {{\"ok\": {}, \"detail\": \"{s}\"}}", .{ name, result.ok, result.detail });
}

test "evidence manifest rejects empty required fields (P0-I-06)" {
    const incomplete = Manifest{
        .gate_ids = &.{},
        .case_id = "",
        .source_commit = "",
        .binary_sha256 = "",
        .platform_os = "",
        .platform_arch = "arm64",
        .backend_id = "none",
        .command = "",
        .ctrl_baseline = .{ .ok = false },
        .ctrl_prepare = .{ .ok = false },
        .ctrl_attach = .{ .ok = false },
        .test_deny = .{ .ok = false },
        .ctrl_neighbor = .{ .ok = false },
        .ctrl_off = .{ .ok = false },
    };
    try std.testing.expectError(error.MissingGateIds, incomplete.validate());
}

test "evidence manifest rejects capability_probe as CTRL-ATTACH (S-GLO-09)" {
    const bad = Manifest{
        .gate_ids = &.{"P1-I-01"},
        .case_id = "home-deny",
        .source_commit = "deadbeef",
        .binary_sha256 = "00",
        .platform_os = "linux",
        .platform_arch = "x86_64",
        .backend_id = "landlock",
        .command = "orca run -- true",
        .ctrl_baseline = .{ .ok = true },
        .ctrl_prepare = .{ .ok = true, .detail = "applySelf" },
        .ctrl_attach = .{ .ok = true, .detail = "capability_probe" },
        .test_deny = .{ .ok = true },
        .ctrl_neighbor = .{ .ok = true },
        .ctrl_off = .{ .ok = true },
    };
    try std.testing.expectError(error.ProbeOnlyAttach, bad.validate());
}

test "evidence manifest rejects prepare-only and attach-without-deny (F-1)" {
    const prepare_only = Manifest{
        .gate_ids = &.{"P1-I-01"},
        .case_id = "prep",
        .source_commit = "deadbeef",
        .binary_sha256 = "00",
        .platform_os = "linux",
        .platform_arch = "x86_64",
        .backend_id = "landlock",
        .command = "test-fast",
        .ctrl_baseline = .{ .ok = true },
        .ctrl_attach = .{ .ok = true, .detail = "zig_status_pipe_or_prepare_handshake" },
        .test_deny = .{ .ok = true },
        .ctrl_neighbor = .{ .ok = true },
        .ctrl_off = .{ .ok = true },
    };
    try std.testing.expectError(error.PrepareOnlyAttach, prepare_only.validate());

    const no_deny = Manifest{
        .gate_ids = &.{"P1-I-01"},
        .case_id = "no-deny",
        .source_commit = "deadbeef",
        .binary_sha256 = "00",
        .platform_os = "linux",
        .platform_arch = "x86_64",
        .backend_id = "landlock",
        .command = "test-fast",
        .ctrl_baseline = .{ .ok = true },
        .ctrl_attach = .{ .ok = true, .detail = "zig_real_fs_deny_canary_and_handshake" },
        .test_deny = .{ .ok = false },
        .ctrl_neighbor = .{ .ok = true },
        .ctrl_off = .{ .ok = true },
    };
    try std.testing.expectError(error.AttachWithoutDeny, no_deny.validate());
}

test "evidence manifest rejects zig_real_fs_deny_canary as CTRL-ATTACH" {
    const bad = Manifest{
        .gate_ids = &.{"P1-I-01"},
        .case_id = "home-deny",
        .source_commit = "deadbeef",
        .binary_sha256 = "00",
        .platform_os = "linux",
        .platform_arch = "x86_64",
        .backend_id = "landlock",
        .command = "orca run -- true",
        .ctrl_baseline = .{ .ok = true },
        .ctrl_prepare = .{ .ok = true },
        .ctrl_attach = .{ .ok = true, .detail = "zig_real_fs_deny_canary" },
        .test_deny = .{ .ok = true },
        .ctrl_neighbor = .{ .ok = true },
        .ctrl_off = .{ .ok = true },
    };
    try std.testing.expectError(error.UnitCanaryOnlyAttach, bad.validate());
}

test "valid enforcement manifest serializes and reports all controls" {
    const good = Manifest{
        .gate_ids = &.{ "P1-I-01", "P1-R-01" },
        .case_id = "home-secret-read",
        .source_commit = "77e49049",
        .binary_sha256 = "aabbcc",
        .platform_os = "macos",
        .platform_arch = "arm64",
        .backend_id = "none",
        .profile_hash = "",
        .command = "orca run --os-sandbox off -- true",
        .ctrl_baseline = .{ .ok = true, .detail = "canary readable" },
        .ctrl_prepare = .{ .ok = true, .detail = "platform_prepare" },
        .ctrl_attach = .{ .ok = false, .detail = "no_apply_wired" },
        .test_deny = .{ .ok = false, .detail = "expected until landlock" },
        .ctrl_neighbor = .{ .ok = true, .detail = "workspace ok" },
        .ctrl_off = .{ .ok = true, .detail = "off path" },
        .canary_fingerprint = "sha256:00",
        .rerun = "./scripts/os-sandbox-adversarial-e2e.sh --case home-secret-read",
    };
    try good.validate();
    try std.testing.expect(!good.allControlsPass());
    const json = try writeJson(std.testing.allocator, good);
    defer std.testing.allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "CTRL-BASELINE") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "CTRL-PREPARE") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "CTRL-ATTACH") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "TEST-DENY") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "P1-I-01") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "capability_probe") == null);
    // CTRL-PREPARE appears after BASELINE and before ATTACH (shell order).
    const prepare_pos = std.mem.indexOf(u8, json, "CTRL-PREPARE").?;
    const baseline_pos = std.mem.indexOf(u8, json, "CTRL-BASELINE").?;
    const attach_pos = std.mem.indexOf(u8, json, "CTRL-ATTACH").?;
    try std.testing.expect(baseline_pos < prepare_pos);
    try std.testing.expect(prepare_pos < attach_pos);
}

test "dual-proof attach detail with handshake is allowed" {
    // ctrl_prepare left at default (ok=false): prepare is optional for allControlsPass.
    const dual = Manifest{
        .gate_ids = &.{"P1-I-01"},
        .case_id = "home-deny",
        .source_commit = "deadbeef",
        .binary_sha256 = "00",
        .platform_os = "macos",
        .platform_arch = "arm64",
        .backend_id = "seatbelt",
        .command = "orca run -- true",
        .ctrl_baseline = .{ .ok = true },
        .ctrl_attach = .{ .ok = true, .detail = "zig_real_fs_deny_canary_and_handshake" },
        .test_deny = .{ .ok = true },
        .ctrl_neighbor = .{ .ok = true },
        .ctrl_off = .{ .ok = true },
    };
    try dual.validate();
    try std.testing.expect(!dual.ctrl_prepare.ok);
    try std.testing.expect(dual.allControlsPass());
}
