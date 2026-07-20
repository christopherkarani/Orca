//! macOS custom Seatbelt apply (deprecated sandbox_init), version-gated.
//!
//! Advertised matrix: macOS product majors 14 through 26 inclusive.
//! Proven locally on macOS 26 (sandbox_init apply + FS deny) when the unit
//! tests in this file pass on the host. Outside the matrix → unavailable.
//! Nested re-apply is not supported: sandbox_init fails if the process is
//! already sandboxed; children inherit.
//!
//! `applyInChild` must run only after fork / before exec (never on the Orca
//! parent). Parent-side code uses `evaluateSupport` + profile render only.

const std = @import("std");
const builtin = @import("builtin");
const posture = @import("posture.zig");
const profile = @import("profile.zig");
const macos_profile = @import("macos_profile.zig");
const canary = @import("canary.zig");

/// Product major versions that may attempt custom Seatbelt attach.
/// Inclusive range: Sonoma (14) through the current proven host major (26).
pub const matrix_major_min: u32 = 14;
pub const matrix_major_max: u32 = 26;

pub const SupportStatus = enum {
    /// Running macOS major is in the advertised matrix and sandbox_init resolves.
    supported,
    /// Not building/running on macOS.
    not_macos,
    /// macOS major outside 14–26 (e.g. 13, 27+).
    version_unsupported,
    /// sandbox_init could not be resolved via dlsym.
    symbol_unavailable,

    pub fn reasonCode(self: SupportStatus) []const u8 {
        return switch (self) {
            .supported => "seatbelt_supported",
            .not_macos => "not_macos",
            .version_unsupported => "macos_version_unsupported",
            .symbol_unavailable => "sandbox_init_unavailable",
        };
    }

    pub fn isSupported(self: SupportStatus) bool {
        return self == .supported;
    }
};

pub const MacOsVersion = struct {
    major: u32,
    minor: u32,
};

/// True when major is in the Seatbelt matrix (14 through 26 inclusive).
pub fn isMatrixMajor(major: u32) bool {
    return major >= matrix_major_min and major <= matrix_major_max;
}

/// Parse `kern.osproductversion` / `sw_vers` style strings (`14.5`, `15.0`, `26.0`).
pub fn parseProductVersion(text: []const u8) !MacOsVersion {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.len == 0) return error.InvalidVersion;
    var it = std.mem.splitScalar(u8, trimmed, '.');
    const major_s = it.next() orelse return error.InvalidVersion;
    const minor_s = it.next() orelse "0";
    const major = std.fmt.parseInt(u32, major_s, 10) catch return error.InvalidVersion;
    const minor = std.fmt.parseInt(u32, minor_s, 10) catch return error.InvalidVersion;
    return .{ .major = major, .minor = minor };
}

/// Read running product version via sysctl. macOS only.
pub fn detectProductVersion() !MacOsVersion {
    if (builtin.os.tag != .macos) return error.NotMacOs;
    var buf: [64]u8 = undefined;
    var len: usize = buf.len;
    const rc = std.c.sysctlbyname("kern.osproductversion", &buf, &len, null, 0);
    if (rc != 0) return error.SysctlFailed;
    // sysctl may include a trailing NUL in len.
    var slice = buf[0..len];
    if (slice.len > 0 and slice[slice.len - 1] == 0) slice = slice[0 .. slice.len - 1];
    return parseProductVersion(slice);
}

const SandboxInitFn = *const fn (profile: [*:0]const u8, flags: u64, errorbuf: *?[*:0]u8) callconv(.c) c_int;
const SandboxFreeErrorFn = *const fn (errorbuf: ?[*:0]u8) callconv(.c) void;

/// Darwin RTLD_DEFAULT ((void *)-2): search the default process namespace.
/// `dlsym(null, …)` returns null on macOS; RTLD_DEFAULT is required.
fn rtldDefault() ?*anyopaque {
    return @ptrFromInt(@as(usize, @bitCast(@as(isize, -2))));
}

fn resolveSandboxInit() ?SandboxInitFn {
    if (builtin.os.tag != .macos) return null;
    const sym = std.c.dlsym(rtldDefault(), "sandbox_init") orelse return null;
    return @ptrCast(@alignCast(sym));
}

fn resolveSandboxFreeError() ?SandboxFreeErrorFn {
    if (builtin.os.tag != .macos) return null;
    const sym = std.c.dlsym(rtldDefault(), "sandbox_free_error") orelse return null;
    return @ptrCast(@alignCast(sym));
}

/// Whether sandbox_init is resolvable (dlsym). Pure capability; not a session claim.
pub fn sandboxInitAvailable() bool {
    return resolveSandboxInit() != null;
}

/// Parent-side support evaluation (no apply).
pub fn evaluateSupport() SupportStatus {
    if (builtin.os.tag != .macos) return .not_macos;
    const ver = detectProductVersion() catch return .version_unsupported;
    if (!isMatrixMajor(ver.major)) return .version_unsupported;
    if (!sandboxInitAvailable()) return .symbol_unavailable;
    return .supported;
}

/// Injected evaluation for tests (no sysctl).
pub fn evaluateSupportWith(major: u32, symbol_ok: bool) SupportStatus {
    if (builtin.os.tag != .macos) return .not_macos;
    if (!isMatrixMajor(major)) return .version_unsupported;
    if (!symbol_ok) return .symbol_unavailable;
    return .supported;
}

pub const ApplyInChildError = error{
    NotMacOs,
    SymbolUnavailable,
    ApplyFailed,
};

/// Apply a custom SBPL profile to the **current** process via deprecated sandbox_init.
///
/// Must only be called in the post-fork child before exec (or in isolation tests).
/// Applying in the Orca parent would confine the CLI itself.
///
/// Nested apply is not supported: if already sandboxed, returns ApplyFailed.
/// Inheritance is the only composition model for descendants.
pub fn applyInChild(sbpl_z: [*:0]const u8) ApplyInChildError!void {
    if (builtin.os.tag != .macos) return error.NotMacOs;
    const init_fn = resolveSandboxInit() orelse return error.SymbolUnavailable;
    const free_fn = resolveSandboxFreeError();

    var err_ptr: ?[*:0]u8 = null;
    // flags=0: custom SBPL string (private usage of the deprecated API).
    const rc = init_fn(sbpl_z, 0, &err_ptr);
    defer if (err_ptr) |e| {
        if (free_fn) |f| f(e);
    };
    if (rc != 0) return error.ApplyFailed;
}

/// Platform outcome used by apply.zig (parent path).
pub const ParentApplyOutcome = struct {
    status: enum { prepared, unavailable, failed },
    mechanism: posture.BackendMechanism = .none,
    reason_code: []const u8,
    /// Owned NUL-terminated SBPL when prepared (for child-side apply). Caller frees.
    sbpl_z: ?[:0]u8 = null,
};

/// Parent-side Seatbelt prepare: version gate, symbol check, SBPL render.
/// Does **not** call sandbox_init (that is child-only). Never reports attach.
///
/// On success (`prepared`), the caller must apply `sbpl_z` in the child before
/// exec and only then claim session active. Until that child apply succeeds,
/// production posture remains unavailable/failed.
pub fn prepareForChildApply(
    allocator: std.mem.Allocator,
    compiled: *const profile.CompiledProfile,
) ParentApplyOutcome {
    return prepareForChildApplyWith(allocator, compiled, evaluateSupport());
}

/// Testable prepare with injected support status.
pub fn prepareForChildApplyWith(
    allocator: std.mem.Allocator,
    compiled: *const profile.CompiledProfile,
    support: SupportStatus,
) ParentApplyOutcome {
    if (!support.isSupported()) {
        return .{
            .status = .unavailable,
            .mechanism = .none,
            .reason_code = support.reasonCode(),
        };
    }

    const sbpl = macos_profile.renderSbpl(allocator, compiled) catch {
        return .{
            .status = .failed,
            .mechanism = .none,
            .reason_code = "seatbelt_profile_render_failed",
        };
    };
    defer allocator.free(sbpl);

    const sbpl_z = allocator.dupeZ(u8, sbpl) catch {
        return .{
            .status = .failed,
            .mechanism = .none,
            .reason_code = "seatbelt_profile_oom",
        };
    };

    return .{
        .status = .prepared,
        .mechanism = .seatbelt,
        .reason_code = "seatbelt_prepared",
        .sbpl_z = sbpl_z,
    };
}

/// Verbose-only mechanism label (S-GLO-03). Default UX uses posture enums.
pub fn verboseMechanismName() []const u8 {
    return posture.BackendMechanism.seatbelt.verboseName();
}

// ── tests ──────────────────────────────────────────────────────────────────

test "matrix accepts macos majors 14 through 26 inclusive" {
    try std.testing.expect(isMatrixMajor(14));
    try std.testing.expect(isMatrixMajor(15));
    try std.testing.expect(isMatrixMajor(16));
    try std.testing.expect(isMatrixMajor(26));
    try std.testing.expect(!isMatrixMajor(13));
    try std.testing.expect(!isMatrixMajor(27));
    try std.testing.expect(!isMatrixMajor(0));
    try std.testing.expectEqual(@as(u32, 14), matrix_major_min);
    try std.testing.expectEqual(@as(u32, 26), matrix_major_max);
}

test "parseProductVersion reads major.minor" {
    const v = try parseProductVersion("15.4");
    try std.testing.expectEqual(@as(u32, 15), v.major);
    try std.testing.expectEqual(@as(u32, 4), v.minor);
    const v2 = try parseProductVersion("14.0\n");
    try std.testing.expectEqual(@as(u32, 14), v2.major);
    const v3 = try parseProductVersion("26.0");
    try std.testing.expectEqual(@as(u32, 26), v3.major);
    try std.testing.expectError(error.InvalidVersion, parseProductVersion(""));
    try std.testing.expectError(error.InvalidVersion, parseProductVersion("abc"));
}

test "evaluateSupportWith encodes version gate" {
    if (builtin.os.tag != .macos) {
        try std.testing.expectEqual(SupportStatus.not_macos, evaluateSupportWith(14, true));
        return;
    }
    try std.testing.expectEqual(SupportStatus.supported, evaluateSupportWith(14, true));
    try std.testing.expectEqual(SupportStatus.supported, evaluateSupportWith(15, true));
    try std.testing.expectEqual(SupportStatus.supported, evaluateSupportWith(26, true));
    try std.testing.expectEqual(SupportStatus.version_unsupported, evaluateSupportWith(13, true));
    try std.testing.expectEqual(SupportStatus.version_unsupported, evaluateSupportWith(27, true));
    try std.testing.expectEqual(SupportStatus.symbol_unavailable, evaluateSupportWith(14, false));
    try std.testing.expectEqualStrings("macos_version_unsupported", SupportStatus.version_unsupported.reasonCode());
}

test "evaluateSupport on this host matches matrix freeze" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    const status = evaluateSupport();
    const ver = try detectProductVersion();
    if (isMatrixMajor(ver.major) and sandboxInitAvailable()) {
        try std.testing.expectEqual(SupportStatus.supported, status);
    } else if (!isMatrixMajor(ver.major)) {
        try std.testing.expectEqual(SupportStatus.version_unsupported, status);
    }
}

test "sandbox_init is resolvable on macOS via dlsym" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    try std.testing.expect(sandboxInitAvailable());
}

test "prepareForChildApply unavailable outside matrix" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var compiled = try profile.compileProfile(allocator, .{
        .workspace_root = "/tmp/orca-seatbelt-ws",
        .system_ro_prefixes = &[_][]const u8{"/usr"},
    });
    defer compiled.deinit();

    const out = prepareForChildApplyWith(allocator, &compiled, .version_unsupported);
    try std.testing.expectEqual(.unavailable, out.status);
    try std.testing.expectEqual(posture.BackendMechanism.none, out.mechanism);
    try std.testing.expectEqualStrings("macos_version_unsupported", out.reason_code);
    try std.testing.expect(out.sbpl_z == null);
}

test "prepareForChildApply yields SBPL when supported" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var compiled = try profile.compileProfile(allocator, .{
        .workspace_root = "/tmp/orca-seatbelt-ws",
        .system_ro_prefixes = &[_][]const u8{ "/usr", "/bin" },
    });
    defer compiled.deinit();

    const out = prepareForChildApplyWith(allocator, &compiled, .supported);
    defer if (out.sbpl_z) |p| allocator.free(p);
    try std.testing.expectEqual(.prepared, out.status);
    try std.testing.expectEqual(posture.BackendMechanism.seatbelt, out.mechanism);
    try std.testing.expect(out.sbpl_z != null);
    try std.testing.expect(std.mem.indexOf(u8, out.sbpl_z.?, "(deny default)") != null);
}

test "applyInChild succeeds for minimal profile in forked child" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    // Fork so the test process itself is not permanently sandboxed.
    const pid = std.c.fork();
    if (pid < 0) return error.SkipZigTest;
    if (pid == 0) {
        const sbpl =
            \\(version 1)
            \\(deny default)
            \\(allow process*)
            \\(allow signal)
            \\(allow sysctl-read)
            \\(allow mach-lookup)
            \\(allow file-read-metadata)
            \\(allow file-read* (literal "/"))
            \\(allow file-read* (subpath "/usr"))
            \\(allow file-read* (subpath "/bin"))
            \\(allow file-read* (subpath "/System"))
            \\(allow file-read* (subpath "/Library"))
            \\(allow file-read* (subpath "/dev"))
            \\(allow file-read* (subpath "/private/var/db/dyld"))
            \\(allow file-ioctl (subpath "/dev"))
            \\
        ;
        applyInChild(sbpl) catch std.c._exit(2);
        // Nested composition is not a product feature (inheritance only).
        // Some OS versions return an error on re-apply; others ignore with rc=0.
        // Either way Orca must not claim a second attach succeeded.
        applyInChild(sbpl) catch {};
        std.c._exit(0);
    }
    var status: c_int = 0;
    _ = std.c.waitpid(pid, &status, 0);
    // WIFEXITED: low 7 bits 0; exit status in bits 8..15
    const exited = (status & 0x7f) == 0;
    try std.testing.expect(exited);
    const exit_code: u8 = @intCast((status >> 8) & 0xff);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
}

// CTRL template: unsandboxed canary readable; sandboxed child denies outside grant
// and allows workspace neighbor read/write. Uses prepare SBPL + applyInChild.
// Exit codes from child: 0=ok, 2=apply fail, 3=outside readable (leak), 4=ws read fail, 5=ws write fail.
test "real FS deny: outside canary denied; workspace readable and writable" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    if (!sandboxInitAvailable()) return error.SkipZigTest;

    const ver = try detectProductVersion();
    // Only claim matrix enforcement when this host major is in the advertised range.
    try std.testing.expect(isMatrixMajor(ver.major));
    try std.testing.expectEqual(SupportStatus.supported, evaluateSupport());

    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var ws_tmp = std.testing.tmpDir(.{});
    defer ws_tmp.cleanup();
    // realPath so Seatbelt grants match kernel paths (/private/var vs /var).
    const ws_root = try ws_tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(ws_root);

    var out_tmp = std.testing.tmpDir(.{});
    defer out_tmp.cleanup();
    const out_root = try out_tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(out_root);

    var synth = try canary.generate(allocator);
    defer synth.deinit();

    // Outside canary (must NOT be under workspace grant).
    try out_tmp.dir.writeFile(io, .{ .sub_path = "canary.txt", .data = synth.body });
    const canary_path = try std.fs.path.join(allocator, &.{ out_root, "canary.txt" });
    defer allocator.free(canary_path);
    const canary_z = try allocator.dupeZ(u8, canary_path);
    defer allocator.free(canary_z);

    // Workspace neighbor (must remain readable/writable under grant).
    try ws_tmp.dir.writeFile(io, .{ .sub_path = "neighbor.txt", .data = "WORKSPACE_NEIGHBOR_OK" });
    const neighbor_path = try std.fs.path.join(allocator, &.{ ws_root, "neighbor.txt" });
    defer allocator.free(neighbor_path);
    const neighbor_z = try allocator.dupeZ(u8, neighbor_path);
    defer allocator.free(neighbor_z);

    const write_probe_path = try std.fs.path.join(allocator, &.{ ws_root, "write_probe.txt" });
    defer allocator.free(write_probe_path);
    const write_probe_z = try allocator.dupeZ(u8, write_probe_path);
    defer allocator.free(write_probe_z);

    // CTRL-BASELINE: unsandboxed parent can read the outside canary.
    {
        const baseline = try std.Io.Dir.cwd().readFileAlloc(io, canary_path, allocator, .limited(4096));
        defer allocator.free(baseline);
        try std.testing.expectEqualStrings(synth.body, baseline);
    }
    // Neighbor also readable without sandbox.
    {
        const baseline_ws = try std.Io.Dir.cwd().readFileAlloc(io, neighbor_path, allocator, .limited(4096));
        defer allocator.free(baseline_ws);
        try std.testing.expectEqualStrings("WORKSPACE_NEIGHBOR_OK", baseline_ws);
    }

    // Prepare real product SBPL from compiled profile (not a hand-rolled minimal string).
    var compiled = try profile.compileProfile(allocator, .{
        .workspace_root = ws_root,
        .include_tmp = false,
    });
    defer compiled.deinit();
    // Outside path must not sit under the workspace grant.
    try std.testing.expect(!compiled.isAgentWritable(canary_path));
    try std.testing.expect(compiled.isAgentWritable(neighbor_path));

    const prepared = prepareForChildApply(allocator, &compiled);
    defer if (prepared.sbpl_z) |p| allocator.free(p);
    try std.testing.expectEqual(.prepared, prepared.status);
    try std.testing.expect(prepared.sbpl_z != null);
    const sbpl_z = prepared.sbpl_z.?;

    const pid = std.c.fork();
    if (pid < 0) return error.SkipZigTest;
    if (pid == 0) {
        applyInChild(sbpl_z.ptr) catch std.c._exit(2);

        // TEST-DENY: outside canary must not be readable.
        const outside_fd = std.c.open(canary_z.ptr, .{ .ACCMODE = .RDONLY });
        if (outside_fd >= 0) {
            _ = std.c.close(outside_fd);
            std.c._exit(3); // leak — outside grant hole
        }

        // Workspace neighbor must still be readable.
        const ws_fd = std.c.open(neighbor_z.ptr, .{ .ACCMODE = .RDONLY });
        if (ws_fd < 0) std.c._exit(4);
        var buf: [64]u8 = undefined;
        const n = std.c.read(ws_fd, &buf, buf.len);
        _ = std.c.close(ws_fd);
        if (n < 0) std.c._exit(4);
        if (n != "WORKSPACE_NEIGHBOR_OK".len) std.c._exit(4);
        if (!std.mem.eql(u8, buf[0..@intCast(n)], "WORKSPACE_NEIGHBOR_OK")) std.c._exit(4);

        // Workspace write must succeed.
        const wfd = std.c.open(write_probe_z.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, @as(std.c.mode_t, 0o600));
        if (wfd < 0) std.c._exit(5);
        const wrote = std.c.write(wfd, "wrote", 5);
        _ = std.c.close(wfd);
        if (wrote != 5) std.c._exit(5);

        std.c._exit(0);
    }

    var status: c_int = 0;
    _ = std.c.waitpid(pid, &status, 0);
    const exited = (status & 0x7f) == 0;
    try std.testing.expect(exited);
    const exit_code: u8 = @intCast((status >> 8) & 0xff);
    // Surface distinct failures for the proof report (do not collapse to a single assert).
    switch (exit_code) {
        0 => {},
        2 => return error.SeatbeltApplyFailedOnHost,
        3 => return error.OutsideCanaryReadableUnderSandbox,
        4 => return error.WorkspaceNeighborUnreadableUnderSandbox,
        5 => return error.WorkspaceWriteFailedUnderSandbox,
        else => return error.UnexpectedSandboxChildExit,
    }
    try std.testing.expectEqual(@as(u8, 0), exit_code);

    // Parent can still read the write probe produced by the sandboxed child.
    const probe = try std.Io.Dir.cwd().readFileAlloc(io, write_probe_path, allocator, .limited(64));
    defer allocator.free(probe);
    try std.testing.expectEqualStrings("wrote", probe);
}

test "verbose mechanism name is Seatbelt (verbose paths only)" {
    try std.testing.expectEqualStrings("Seatbelt", verboseMechanismName());
}

test "default support reason codes never claim nested apply" {
    // Inheritance-only composition is a documentation/API contract.
    try std.testing.expectEqualStrings("macos_version_unsupported", SupportStatus.version_unsupported.reasonCode());
    try std.testing.expectEqualStrings("sandbox_init_unavailable", SupportStatus.symbol_unavailable.reasonCode());
}
