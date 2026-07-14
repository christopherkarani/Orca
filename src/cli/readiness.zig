//! Core readiness for doctor/status/quickstart --check contracts.
//! Scope: daemon health + workspace policy present/valid (not host protection grade).

const std = @import("std");
const core_api = @import("orca_core").api;

const exit_codes = @import("exit_codes.zig");
const onboarding = @import("onboarding.zig");
const plugin = @import("plugin.zig");

/// Machine-facing readiness state (JSON `state` field).
/// Only values actually produced by `assess` today — host grades stay out of this field.
pub const State = enum {
    ready,
    not_ready,

    pub fn label(self: State) []const u8 {
        return switch (self) {
            .ready => "ready",
            .not_ready => "not_ready",
        };
    }
};

pub const PolicyValidity = struct {
    present: bool,
    valid: bool,
    /// Owned by caller when non-null (error name from load/parse).
    error_name: ?[]const u8 = null,

    pub fn deinit(self: *PolicyValidity, allocator: std.mem.Allocator) void {
        if (self.error_name) |name| allocator.free(name);
        self.* = undefined;
    }
};

/// Core readiness: daemon compatible + policy present + policy valid.
pub const Assessment = struct {
    ready: bool,
    state: State,
    daemon_ok: bool,
    policy_present: bool,
    policy_valid: bool,

    pub fn exitCode(self: Assessment, check_mode: bool) u8 {
        if (!check_mode) return exit_codes.success;
        return if (self.ready) exit_codes.success else exit_codes.general;
    }

    /// Human-scoped receipt line for quickstart / setup.
    pub fn formatReceipt(self: Assessment, buf: []u8) []const u8 {
        const daemon_part: []const u8 = if (self.daemon_ok) "compatible" else "not ready";
        const policy_part: []const u8 = if (!self.policy_present)
            "missing"
        else if (!self.policy_valid)
            "invalid"
        else
            "valid";
        return std.fmt.bufPrint(buf, "daemon: {s} | policy: {s}", .{ daemon_part, policy_part }) catch "daemon: ? | policy: ?";
    }
};

/// Wire / machine label for daemon health (not the human "healthy" display label).
pub fn daemonWireLabel(status: onboarding.DaemonHealthStatus) []const u8 {
    return switch (status) {
        .compatible => "compatible",
        .unavailable => "unavailable",
        .incompatible => "incompatible",
        .degraded => "degraded",
    };
}

/// Assess core readiness from daemon enum + policy flags.
pub fn assess(daemon_status: onboarding.DaemonHealthStatus, policy_present: bool, policy_valid: bool) Assessment {
    const daemon_ok = daemon_status == .compatible;
    const ready = daemon_ok and policy_present and policy_valid;
    return .{
        .ready = ready,
        .state = if (ready) .ready else .not_ready,
        .daemon_ok = daemon_ok,
        .policy_present = policy_present,
        .policy_valid = policy_valid,
    };
}

/// Real policy load/parse (not existence-only). Frees any loaded policy on success.
pub fn assessPolicyFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !PolicyValidity {
    if (!plugin.fileExistsAbsolute(io, path)) {
        return .{ .present = false, .valid = false, .error_name = null };
    }
    if (core_api.loadPolicyFile(io, allocator, path)) |loaded_policy| {
        var loaded = loaded_policy;
        loaded.deinit();
        return .{ .present = true, .valid = true, .error_name = null };
    } else |err| {
        if (err == error.OutOfMemory) return err;
        return .{
            .present = true,
            .valid = false,
            .error_name = try std.fmt.allocPrint(allocator, "{s}", .{@errorName(err)}),
        };
    }
}

/// Assess workspace policy at `.orca/policy.yaml` under `workspace_root`.
pub fn assessWorkspacePolicy(io: std.Io, allocator: std.mem.Allocator, workspace_root: []const u8) !PolicyValidity {
    const path = try onboarding.policyPath(allocator, workspace_root);
    defer allocator.free(path);
    return assessPolicyFile(io, allocator, path);
}

/// Fields for the shared readiness JSON envelope (additive schema_version 1 fields).
pub const JsonEnvelope = struct {
    assessment: Assessment,
    check: bool,
    daemon_status: []const u8,
    daemon_detail: []const u8,
    policy_path: []const u8,
    policy_error: ?[]const u8 = null,
    policy_mode: ?[]const u8 = null,
    policy_preset: ?[]const u8 = null,
    /// When true, close the root object after the policy field (doctor minimal report).
    /// When false, leave the object open after `"policy": {...},` so callers append more keys.
    close_object: bool = true,
};

/// Write readiness preamble + daemon + policy. When `close_object` is false, ends after
/// the policy object with a trailing comma (status continues with hosts/packs/next).
pub fn writeJsonEnvelope(stdout: anytype, env: JsonEnvelope) !void {
    try stdout.writeAll("{\n");
    try stdout.writeAll("  \"schema_version\": 1,\n");
    try stdout.print("  \"ready\": {},\n", .{env.assessment.ready});
    try stdout.print("  \"state\": \"{s}\",\n", .{env.assessment.state.label()});
    try stdout.print("  \"check\": {},\n", .{env.check});

    var daemon_status_buf: [128]u8 = undefined;
    var daemon_detail_buf: [512]u8 = undefined;
    try stdout.print("  \"daemon\": {{\"status\":{s},\"detail\":{s}}},\n", .{
        escapeJson(env.daemon_status, &daemon_status_buf),
        escapeJson(env.daemon_detail, &daemon_detail_buf),
    });

    var path_buf: [1024]u8 = undefined;
    try stdout.print("  \"policy\": {{\"path\":{s},\"present\":{},\"valid\":{}", .{
        escapeJson(env.policy_path, &path_buf),
        env.assessment.policy_present,
        env.assessment.policy_valid,
    });
    if (env.policy_mode) |mode| {
        var mode_buf: [64]u8 = undefined;
        try stdout.print(",\"mode\":{s}", .{escapeJson(mode, &mode_buf)});
    } else {
        try stdout.writeAll(",\"mode\":null");
    }
    if (env.policy_preset) |preset| {
        var preset_buf: [64]u8 = undefined;
        try stdout.print(",\"preset\":{s}", .{escapeJson(preset, &preset_buf)});
    } else {
        try stdout.writeAll(",\"preset\":null");
    }
    if (env.policy_error) |err_name| {
        var err_buf: [128]u8 = undefined;
        try stdout.print(",\"error\":{s}", .{escapeJson(err_name, &err_buf)});
    } else {
        try stdout.writeAll(",\"error\":null");
    }
    if (env.close_object) {
        try stdout.writeAll("}\n}\n");
    } else {
        try stdout.writeAll("},\n");
    }
}

/// Returns a quoted JSON string using `buf` as scratch (includes quotes).
pub fn escapeJson(value: []const u8, buf: []u8) []const u8 {
    if (buf.len < 3) return "\"\"";
    var out: std.Io.Writer = .fixed(buf);
    out.writeByte('"') catch return "\"\"";
    for (value) |c| {
        switch (c) {
            '"' => out.writeAll("\\\"") catch return "\"\"",
            '\\' => out.writeAll("\\\\") catch return "\"\"",
            '\n' => out.writeAll("\\n") catch return "\"\"",
            '\r' => out.writeAll("\\r") catch return "\"\"",
            '\t' => out.writeAll("\\t") catch return "\"\"",
            else => {
                if (c < 0x20) {
                    var hex: [6]u8 = undefined;
                    const h = std.fmt.bufPrint(&hex, "\\u{x:0>4}", .{c}) catch return "\"\"";
                    out.writeAll(h) catch return "\"\"";
                } else {
                    out.writeByte(c) catch return "\"\"";
                }
            },
        }
    }
    out.writeByte('"') catch return "\"\"";
    return out.buffered();
}

// ─── Tests ───────────────────────────────────────────────────────────────────

test "assess ready only when daemon compatible and policy valid" {
    const ok = assess(.compatible, true, true);
    try std.testing.expect(ok.ready);
    try std.testing.expectEqual(State.ready, ok.state);
    try std.testing.expectEqual(exit_codes.success, ok.exitCode(true));
    try std.testing.expectEqual(exit_codes.success, ok.exitCode(false));
}

test "assess fails check when daemon unavailable" {
    const a = assess(.unavailable, true, true);
    try std.testing.expect(!a.ready);
    try std.testing.expectEqual(State.not_ready, a.state);
    try std.testing.expectEqual(exit_codes.general, a.exitCode(true));
    try std.testing.expectEqual(exit_codes.success, a.exitCode(false));
}

test "assess fails check when daemon incompatible or degraded" {
    try std.testing.expect(!assess(.incompatible, true, true).ready);
    try std.testing.expect(!assess(.degraded, true, true).ready);
}

test "assess fails check when policy missing or invalid" {
    try std.testing.expect(!assess(.compatible, false, false).ready);
    try std.testing.expect(!assess(.compatible, true, false).ready);
    try std.testing.expect(!assess(.compatible, false, true).ready);
}

test "assessPolicyFile missing path" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const path = try std.fs.path.join(std.testing.allocator, &.{ root, "no-such-policy.yaml" });
    defer std.testing.allocator.free(path);

    var result = try assessPolicyFile(std.testing.io, std.testing.allocator, path);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(!result.present);
    try std.testing.expect(!result.valid);
}

test "assessPolicyFile invalid yaml" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "bad.yaml", .data = "mode: [[[not valid\n" });
    const path = try tmp.dir.realPathFileAlloc(std.testing.io, "bad.yaml", std.testing.allocator);
    defer std.testing.allocator.free(path);

    var result = try assessPolicyFile(std.testing.io, std.testing.allocator, path);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.present);
    try std.testing.expect(!result.valid);
    try std.testing.expect(result.error_name != null);
}

test "formatReceipt scopes daemon and policy" {
    var buf: [128]u8 = undefined;
    const line = assess(.unavailable, false, false).formatReceipt(&buf);
    try std.testing.expect(std.mem.indexOf(u8, line, "not ready") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "missing") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "daemon:") != null);

    const ok_line = assess(.compatible, true, true).formatReceipt(&buf);
    try std.testing.expect(std.mem.indexOf(u8, ok_line, "compatible") != null);
    try std.testing.expect(std.mem.indexOf(u8, ok_line, "valid") != null);
}

test "writeJsonEnvelope close and open forms" {
    var buf: [1024]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    const a = assess(.compatible, true, true);
    try writeJsonEnvelope(&w, .{
        .assessment = a,
        .check = true,
        .daemon_status = "compatible",
        .daemon_detail = "ok",
        .policy_path = "/tmp/p.yaml",
        .close_object = true,
    });
    const closed = w.buffered();
    try std.testing.expect(std.mem.indexOf(u8, closed, "\"ready\": true") != null);
    try std.testing.expect(std.mem.indexOf(u8, closed, "\"check\": true") != null);
    try std.testing.expect(std.mem.endsWith(u8, closed, "}\n"));

    w = .fixed(&buf);
    try writeJsonEnvelope(&w, .{
        .assessment = a,
        .check = false,
        .daemon_status = "compatible",
        .daemon_detail = "ok",
        .policy_path = "/tmp/p.yaml",
        .close_object = false,
    });
    const open = w.buffered();
    try std.testing.expect(std.mem.endsWith(u8, open, "},\n"));
}

test "daemonWireLabel is stable machine vocabulary" {
    try std.testing.expectEqualStrings("compatible", daemonWireLabel(.compatible));
    try std.testing.expectEqualStrings("unavailable", daemonWireLabel(.unavailable));
}
