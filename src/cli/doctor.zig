const std = @import("std");
const builtin = @import("builtin");
const core = @import("orca_core").core;
const supervisor = core.supervisor;
const core_api = @import("orca_core").api;
const orca_mcp = @import("../mcp/mod.zig");
const orca_policy = @import("orca_core").policy;
const sandbox = @import("../sandbox/mod.zig");
const resource_root = @import("../resource_root.zig");

const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");
const cli = @import("mod.zig");

const DoctorCapability = struct {
    label: []const u8,
    feature: ?sandbox.backend.Feature = null,
    capability: ?core.platform.Capability = null,
};

const doctor_capabilities = [_]DoctorCapability{
    .{ .label = "process supervision", .feature = .process_supervision },
    .{ .label = "env filtering", .feature = .env_filtering },
    .{ .label = "staged writes", .feature = .path_staging },
    .{ .label = "mcp stdio proxy", .feature = .mcp_stdio_proxy },
    .{ .label = "network policy engine", .capability = .network_policy_engine },
    .{ .label = "network observation", .feature = .network_observe },
    .{ .label = "transparent network enforcement", .feature = .network_enforce },
    .{ .label = "proxy-mediated enforcement", .capability = .network_proxy_enforce },
    .{ .label = "strong sandbox", .feature = .strong_sandbox },
};

const AgentBinary = struct {
    name: []const u8,
    command: []const u8,
};

const known_agent_binaries = [_]AgentBinary{
    .{ .name = "Claude Code", .command = "claude" },
    .{ .name = "Codex", .command = "codex" },
    .{ .name = "Cursor", .command = "cursor" },
    .{ .name = "OpenCode", .command = "opencode" },
    .{ .name = "Cline/Roo", .command = "cline" },
};

const IntegrationContext = struct {
    allocator: std.mem.Allocator,
    workspace_root: []const u8,
    git_present: bool,
    policy_present: bool,
    policy_valid: bool,
    policy_error: ?[]const u8 = null,
    agent_found: []const AgentBinary,
    mcp_manifest_count: usize,
    mcp_manifest_invalid_count: usize,
    ci_detected: bool,
    ci_provider: []const u8,
    shell_name: []const u8,
    audit_sessions_present: bool,
    redteam_fixtures_present: bool,

    fn deinit(self: *IntegrationContext) void {
        self.allocator.free(self.workspace_root);
        if (self.policy_error) |value| self.allocator.free(value);
        if (self.agent_found.len > 0) self.allocator.free(self.agent_found);
        self.allocator.free(self.ci_provider);
        self.allocator.free(self.shell_name);
        self.* = undefined;
    }
};

pub fn command(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            _ = try help.writeCommand(stdout, "doctor");
            return exit_codes.success;
        }
        try stderr.print("orca doctor: unknown option '{s}'.\n", .{arg});
        return exit_codes.usage;
    }

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const os = core.platform.detectOs();
    const backend_report = sandbox.backend.detect(os);
    var context = collectIntegrationContext(allocator) catch |err| {
        try stderr.print("orca doctor: failed to collect integration context: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer context.deinit();
    try writeReport(stdout, os, backend_report, context);
    return exit_codes.success;
}

fn writeReport(stdout: anytype, os: core.platform.Os, backend_report: sandbox.backend.ReportSet, context: IntegrationContext) !void {
    try stdout.writeAll("Orca Doctor\n\n");
    try stdout.print("OS: {s}\n", .{os.toString()});
    try stdout.print("Version: {s}\n\n", .{cli.version});
    try writeIntegrationReport(stdout, context);
    try stdout.writeAll("Capabilities:\n");
    for (doctor_capabilities) |item| {
        if (item.feature) |feature| {
            const report = backend_report.get(feature);
            try stdout.print("  {s}: {s} ({s})\n", .{ item.label, report.level.toString(), report.note });
        } else if (item.capability) |capability| {
            const report = core.platform.reportCapability(os, capability);
            try stdout.print("  {s}: {s} ({s})\n", .{ item.label, report.state.toString(), report.note });
        }
    }
    try stdout.writeByte('\n');
    if (os == .linux) {
        try stdout.writeAll("Linux backend:\n");
    } else if (os == .macos) {
        try stdout.writeAll("macOS backend:\n");
    } else if (os == .windows) {
        try stdout.writeAll("Windows backend:\n");
    } else {
        try stdout.writeAll("Backend:\n");
    }
    try stdout.print("  selected: {s}\n", .{backend_report.backend_name});
    try stdout.print("  fallback mode: {s} ({s})\n", .{ backend_report.fallback_level.toString(), backend_report.fallback_note });
    if (os == .windows) {
        try writeWindowsBackendReport(stdout, backend_report);
    } else {
        try writeBackendLine(stdout, backend_report, .policy_engine);
        try writeBackendLine(stdout, backend_report, .env_filtering);
        try writeBackendLine(stdout, backend_report, .path_staging);
        if (os == .macos) {
            try stdout.writeAll("  transparent file enforcement: limited (no transparent macOS filesystem monitor is installed; Orca-mediated staging and protected path matching are active)\n");
        }
        try writeBackendLine(stdout, backend_report, .shell_wrapping);
        try writeBackendLine(stdout, backend_report, .path_shims);
        try writeBackendLine(stdout, backend_report, .process_supervision);
        if (os == .linux) {
            try writeBackendLine(stdout, backend_report, .user_namespaces);
            try writeBackendLine(stdout, backend_report, .mount_namespaces);
            try writeBackendLine(stdout, backend_report, .seccomp);
            try writeBackendLine(stdout, backend_report, .landlock);
            try writeBackendLine(stdout, backend_report, .cgroups);
        }
        try writeBackendLine(stdout, backend_report, .network_enforce);
        try writeBackendLine(stdout, backend_report, .mcp_stdio_proxy);
        try writeBackendLine(stdout, backend_report, .strong_sandbox);
        try writeBackendLine(stdout, backend_report, .audit);
    }
    try writeRecommendations(stdout, context);
}

fn writeIntegrationReport(stdout: anytype, context: IntegrationContext) !void {
    try stdout.writeAll("Integration checks:\n");
    try stdout.print("  workspace root: {s}\n", .{context.workspace_root});
    try stdout.print("  git repository: {s}\n", .{if (context.git_present) "detected" else "not detected"});
    if (context.policy_present) {
        if (context.policy_valid) {
            try stdout.writeAll("  .orca/policy.yaml: present and valid\n");
        } else {
            try stdout.print("  .orca/policy.yaml: invalid ({s})\n", .{context.policy_error orelse "validation failed"});
        }
    } else {
        try stdout.writeAll("  .orca/policy.yaml: missing\n");
    }
    if (context.agent_found.len == 0) {
        try stdout.writeAll("  known agent binaries: none detected in PATH\n");
    } else {
        try stdout.writeAll("  known agent binaries: ");
        for (context.agent_found, 0..) |agent, index| {
            if (index > 0) try stdout.writeAll(", ");
            try stdout.print("{s}", .{agent.command});
        }
        try stdout.writeAll(" (presence only; not a security claim)\n");
    }
    if (context.mcp_manifest_count == 0) {
        try stdout.writeAll("  MCP manifests: none detected under .orca/mcp\n");
    } else {
        try stdout.print("  MCP manifests: {d} found, {d} invalid\n", .{ context.mcp_manifest_count, context.mcp_manifest_invalid_count });
    }
    try stdout.print("  CI environment: {s}", .{if (context.ci_detected) "detected" else "not detected"});
    if (context.ci_detected) try stdout.print(" ({s})", .{context.ci_provider});
    try stdout.writeByte('\n');
    try stdout.print("  shell: {s}\n", .{context.shell_name});
    try stdout.print("  audit/replay: {s}\n", .{if (context.audit_sessions_present) "session artifacts present; replay available" else "replay available; no local sessions detected"});
    try stdout.print("  red-team fixtures: {s}\n\n", .{if (context.redteam_fixtures_present) "available" else "not found"});
}

fn writeWindowsBackendReport(stdout: anytype, backend_report: sandbox.backend.ReportSet) !void {
    try writeBackendLine(stdout, backend_report, .policy_engine);
    try writeBackendLine(stdout, backend_report, .env_filtering);
    try writeBackendLine(stdout, backend_report, .path_staging);
    try writeBackendLine(stdout, backend_report, .path_shims);
    const shell = backend_report.get(.shell_wrapping);
    try stdout.print("  cmd wrapper: partial ({s})\n", .{shell.note});
    try stdout.print("  PowerShell wrapper: partial ({s})\n", .{shell.note});
    const cleanup = backend_report.get(.process_supervision);
    try stdout.print("  process cleanup: {s} ({s})\n", .{ cleanup.level.toString(), cleanup.note });
    try stdout.writeAll("  transparent file enforcement: limited (no transparent Windows filesystem enforcement is installed; Orca-mediated staging and protected path matching are active)\n");
    try writeBackendLine(stdout, backend_report, .network_enforce);
    try writeBackendLine(stdout, backend_report, .strong_sandbox);
    try writeBackendLine(stdout, backend_report, .mcp_stdio_proxy);
    try writeBackendLine(stdout, backend_report, .audit);
    try stdout.writeByte('\n');
}

fn writeBackendLine(stdout: anytype, backend_report: sandbox.backend.ReportSet, feature: sandbox.backend.Feature) !void {
    const report = backend_report.get(feature);
    try stdout.print("  {s}: {s} ({s})\n", .{ report.feature.label(), report.level.toString(), report.note });
}

fn writeRecommendations(stdout: anytype, context: IntegrationContext) !void {
    try stdout.writeAll("\nRecommended next step:\n");
    if (!context.policy_present) {
        try stdout.writeAll("  Run `orca init --preset generic-agent` and review .orca/policy.yaml.\n");
    } else if (!context.policy_valid) {
        try stdout.writeAll("  Fix `.orca/policy.yaml`, then run `orca policy check .orca/policy.yaml`.\n");
    } else if (context.mcp_manifest_invalid_count > 0) {
        try stdout.writeAll("  Fix invalid MCP manifests with `orca mcp manifest check <path>`.\n");
    } else if (!context.redteam_fixtures_present) {
        try stdout.writeAll("  Add or restore local red-team fixtures before relying on CI regression checks.\n");
    } else {
        try stdout.writeAll("  Run `orca run -- <command>` or `orca redteam --ci` for a local smoke test.\n");
    }
}

fn collectIntegrationContext(allocator: std.mem.Allocator) !IntegrationContext {
    const workspace_root = supervisor.resolveWorkspaceRoot(allocator, null, ".") catch try allocator.dupe(u8, ".");
    errdefer allocator.free(workspace_root);
    return try collectIntegrationContextAt(allocator, workspace_root);
}

fn collectIntegrationContextAt(allocator: std.mem.Allocator, workspace_root: []const u8) !IntegrationContext {
    const git_present = hasPath(workspace_root, ".git");

    const policy_path = try std.fs.path.join(allocator, &.{ workspace_root, ".orca", "policy.yaml" });
    defer allocator.free(policy_path);
    var policy_present = false;
    var policy_valid = false;
    var policy_error: ?[]const u8 = null;
    errdefer if (policy_error) |value| allocator.free(value);
    if (fileExistsAbsolute(policy_path)) {
        policy_present = true;
        if (core_api.loadPolicyFile(allocator, policy_path)) |loaded_policy| {
            var loaded = loaded_policy;
            loaded.deinit();
            policy_valid = true;
        } else |err| {
            if (err == error.OutOfMemory) return err;
            policy_error = try std.fmt.allocPrint(allocator, "{s}", .{@errorName(err)});
        }
    }
    const manifests = countMcpManifests(allocator, workspace_root);
    const agents = try detectAgents(allocator);
    errdefer if (agents.len > 0) allocator.free(agents);
    const ci_status = try detectCi(allocator);
    errdefer allocator.free(ci_status.provider);
    const shell_name = try detectShell(allocator);
    errdefer allocator.free(shell_name);
    return .{
        .allocator = allocator,
        .workspace_root = workspace_root,
        .git_present = git_present,
        .policy_present = policy_present,
        .policy_valid = policy_valid,
        .policy_error = policy_error,
        .agent_found = agents,
        .mcp_manifest_count = manifests.total,
        .mcp_manifest_invalid_count = manifests.invalid,
        .ci_detected = ci_status.detected,
        .ci_provider = ci_status.provider,
        .shell_name = shell_name,
        .audit_sessions_present = hasPath(workspace_root, ".orca/sessions"),
        .redteam_fixtures_present = resource_root.resourcePathExists(allocator, .{ .workspace_root = workspace_root }, "fixtures"),
    };
}

fn hasPath(root: []const u8, relative: []const u8) bool {
    const allocator = std.heap.page_allocator;
    const path = std.fs.path.join(allocator, &.{ root, relative }) catch return false;
    defer allocator.free(path);
    return fileExistsAbsolute(path);
}

fn fileExistsAbsolute(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

const ManifestCounts = struct { total: usize = 0, invalid: usize = 0 };

fn countMcpManifests(allocator: std.mem.Allocator, workspace_root: []const u8) ManifestCounts {
    const mcp_dir_path = std.fs.path.join(allocator, &.{ workspace_root, ".orca", "mcp" }) catch return .{};
    defer allocator.free(mcp_dir_path);
    var dir = std.fs.cwd().openDir(mcp_dir_path, .{ .iterate = true }) catch return .{};
    defer dir.close();

    var counts: ManifestCounts = .{};
    var iterator = dir.iterate();
    while (iterator.next() catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".yaml") and !std.mem.endsWith(u8, entry.name, ".yml")) continue;
        counts.total += 1;
        const manifest_path = std.fs.path.join(allocator, &.{ mcp_dir_path, entry.name }) catch {
            counts.invalid += 1;
            continue;
        };
        defer allocator.free(manifest_path);
        var manifest = orca_mcp.manifests.loadFile(allocator, manifest_path) catch {
            counts.invalid += 1;
            continue;
        };
        manifest.deinit(allocator);
    }
    return counts;
}

fn detectAgents(allocator: std.mem.Allocator) ![]const AgentBinary {
    var found: std.ArrayList(AgentBinary) = .empty;
    errdefer found.deinit(allocator);
    for (known_agent_binaries) |agent| {
        if (binaryInPath(allocator, agent.command)) try found.append(allocator, agent);
    }
    return try found.toOwnedSlice(allocator);
}

fn binaryInPath(allocator: std.mem.Allocator, binary_name: []const u8) bool {
    const path_value = std.process.getEnvVarOwned(allocator, "PATH") catch return false;
    defer allocator.free(path_value);
    var parts = std.mem.splitScalar(u8, path_value, std.fs.path.delimiter);
    while (parts.next()) |dir| {
        if (dir.len == 0) continue;
        const candidate = std.fs.path.join(allocator, &.{ dir, binary_name }) catch continue;
        defer allocator.free(candidate);
        if (fileExistsAbsolute(candidate)) return true;
        if (builtin.os.tag == .windows) {
            const exe_candidate = std.fmt.allocPrint(allocator, "{s}.exe", .{candidate}) catch continue;
            defer allocator.free(exe_candidate);
            if (fileExistsAbsolute(exe_candidate)) return true;
        }
    }
    return false;
}

const CiStatus = struct {
    detected: bool,
    provider: []const u8,
};

fn detectCi(allocator: std.mem.Allocator) !CiStatus {
    if (envPresent(allocator, "GITHUB_ACTIONS")) return .{ .detected = true, .provider = try allocator.dupe(u8, "GitHub Actions") };
    if (envPresent(allocator, "CI")) return .{ .detected = true, .provider = try allocator.dupe(u8, "generic CI") };
    return .{ .detected = false, .provider = try allocator.dupe(u8, "none") };
}

fn envPresent(allocator: std.mem.Allocator, name: []const u8) bool {
    const value = std.process.getEnvVarOwned(allocator, name) catch return false;
    defer allocator.free(value);
    return value.len > 0;
}

fn detectShell(allocator: std.mem.Allocator) ![]const u8 {
    if (std.process.getEnvVarOwned(allocator, "SHELL")) |value| {
        defer allocator.free(value);
        return try allocator.dupe(u8, std.fs.path.basename(value));
    } else |_| {}
    if (std.process.getEnvVarOwned(allocator, "COMSPEC")) |value| {
        defer allocator.free(value);
        return try allocator.dupe(u8, std.fs.path.basename(value));
    } else |_| {}
    if (envPresent(allocator, "PSModulePath")) return try allocator.dupe(u8, "powershell");
    return try allocator.dupe(u8, "unknown");
}

test "doctor prints OS and planned capabilities" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(&.{}, stdout_stream.writer(), stderr_stream.writer());

    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Orca Doctor") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Integration checks:") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "OS:") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "process supervision:") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "network policy engine: active") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "transparent network enforcement: unavailable") != null or std.mem.indexOf(u8, stdout_stream.getWritten(), "transparent network enforcement: limited") != null or std.mem.indexOf(u8, stdout_stream.getWritten(), "transparent network enforcement: observe-only") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "proxy-mediated enforcement: limited") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Backend:") != null or std.mem.indexOf(u8, stdout_stream.getWritten(), "Linux backend:") != null or std.mem.indexOf(u8, stdout_stream.getWritten(), "macOS backend:") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "env filtering: active") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "strong sandbox:") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "doctor can render Linux backend details from an injected report" {
    var stdout_buf: [8192]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    const report = sandbox.backend.detect(.linux);
    var context = try testContext(std.testing.allocator, .{});
    defer context.deinit();

    try writeReport(stdout_stream.writer(), .linux, report, context);

    const written = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, written, "Linux backend:") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "user namespace:") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "mount namespace:") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "seccomp:") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "landlock:") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "transparent network enforcement: observe-only") != null);
}

test "doctor can render macOS backend details from an injected report" {
    var stdout_buf: [8192]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    const report = sandbox.backend.detect(.macos);
    var context = try testContext(std.testing.allocator, .{});
    defer context.deinit();

    try writeReport(stdout_stream.writer(), .macos, report, context);

    const written = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, written, "macOS backend:") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "selected: macos") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "env filtering: active") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "path staging: active") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "transparent file enforcement: limited") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "shell shims: wrapper-only") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "process supervision: active") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "transparent network enforcement: limited") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "strong sandbox: unavailable") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "mcp stdio proxy: active") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "audit/replay: active") != null);
}

test "doctor can render Windows backend details from an injected report" {
    var stdout_buf: [8192]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    const report = sandbox.backend.detect(.windows);
    var context = try testContext(std.testing.allocator, .{});
    defer context.deinit();

    try writeReport(stdout_stream.writer(), .windows, report, context);

    const written = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, written, "Windows backend:") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "selected: windows") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "env filtering: active") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "path staging: active") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "PATH shims: wrapper-only") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "cmd wrapper: partial") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "PowerShell wrapper: partial") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "process cleanup: partial") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "transparent file enforcement: limited") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "transparent network enforcement: limited") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "strong sandbox: unavailable") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "mcp stdio proxy: active") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "audit/replay: active") != null);
}

test "doctor detects valid policy in current workspace" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");

    try tmp.dir.makePath(".git");
    try tmp.dir.makePath(".orca");
    {
        const file = try tmp.dir.createFile(".orca/policy.yaml", .{});
        defer file.close();
        try file.writeAll(orca_policy.presets.agentPresetText(.generic_agent));
    }

    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    var context = try collectIntegrationContextAt(std.testing.allocator, tmp_path);
    defer context.deinit();

    try writeReport(stdout_stream.writer(), core.platform.detectOs(), sandbox.backend.detect(core.platform.detectOs()), context);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), ".orca/policy.yaml: present and valid") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "git repository: detected") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "doctor reports invalid policy clearly without printing synthetic secrets" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");

    try tmp.dir.makePath(".orca");
    {
        const file = try tmp.dir.createFile(".orca/policy.yaml", .{});
        defer file.close();
        try file.writeAll(
            \\version: 1
            \\mode: loose
            \\# synthetic secret should not appear in doctor output: ghp_fakeSecretShouldNotPrint
        );
    }

    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    var context = try collectIntegrationContextAt(std.testing.allocator, tmp_path);
    defer context.deinit();

    try writeReport(stdout_stream.writer(), core.platform.detectOs(), sandbox.backend.detect(core.platform.detectOs()), context);
    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, ".orca/policy.yaml: invalid") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "UnsupportedPolicyMode") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "ghp_fakeSecretShouldNotPrint") == null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "doctor integration collection returns allocator failures instead of panicking" {
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, collectIntegrationContextAt(failing_allocator.allocator(), "."));
}

const TestContextOptions = struct {
    policy_present: bool = true,
    policy_valid: bool = true,
};

fn testContext(allocator: std.mem.Allocator, options: TestContextOptions) !IntegrationContext {
    return .{
        .allocator = allocator,
        .workspace_root = try allocator.dupe(u8, "."),
        .git_present = true,
        .policy_present = options.policy_present,
        .policy_valid = options.policy_valid,
        .policy_error = null,
        .agent_found = &.{},
        .mcp_manifest_count = 0,
        .mcp_manifest_invalid_count = 0,
        .ci_detected = false,
        .ci_provider = try allocator.dupe(u8, "none"),
        .shell_name = try allocator.dupe(u8, "zsh"),
        .audit_sessions_present = false,
        .redteam_fixtures_present = true,
    };
}
