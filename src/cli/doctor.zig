const std = @import("std");
const builtin = @import("builtin");
const env_util = @import("../env_util.zig");
const core = @import("orca_core").core;
const supervisor = core.supervisor;
const core_api = @import("orca_core").api;
const orca_mcp = @import("../mcp/mod.zig");
const orca_policy = @import("orca_core").policy;
const sandbox = @import("../sandbox/mod.zig");
const resource_root = @import("../resource_root.zig");
const style = @import("style.zig");

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

pub fn command(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var verbose = false;
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            _ = try help.writeCommand(io, stdout, "doctor");
            return exit_codes.success;
        }
        if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
            continue;
        }
        try stderr.print("orca doctor: unknown option '{s}'.\n", .{arg});
        return exit_codes.usage;
    }

    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const os = core.platform.detectOs();
    const backend_report = sandbox.backend.detect(os);
    var context = collectIntegrationContext(io, allocator) catch |err| {
        try stderr.print("orca doctor: failed to collect integration context: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer context.deinit();
    try writeReport(io, stdout, os, backend_report, context, verbose);
    return exit_codes.success;
}

fn countCapabilitySummary(os: core.platform.Os, backend_report: sandbox.backend.ReportSet) struct { active: usize, limited: usize, unavailable: usize } {
    var active_count: usize = 0;
    var limited_count: usize = 0;
    var unavailable_count: usize = 0;

    for (doctor_capabilities) |item| {
        if (item.feature) |feature| {
            switch (backend_report.get(feature).level) {
                .active => active_count += 1,
                .partial, .limited, .observe_only, .wrapper_only => limited_count += 1,
                .unavailable, .unsupported, .failed => unavailable_count += 1,
            }
        } else if (item.capability) |capability| {
            switch (core.platform.reportCapability(os, capability).state) {
                .active => active_count += 1,
                .partial, .limited, .observe => limited_count += 1,
                .unavailable, .unknown => unavailable_count += 1,
            }
        }
    }

    return .{ .active = active_count, .limited = limited_count, .unavailable = unavailable_count };
}

fn writeReport(io: std.Io, stdout: anytype, os: core.platform.Os, backend_report: sandbox.backend.ReportSet, context: IntegrationContext, verbose: bool) !void {
    try stdout.writeAll("Orca Doctor\n\n");

    const counts = countCapabilitySummary(os, backend_report);
    const policy_status = if (!context.policy_present)
        "no policy"
    else if (!context.policy_valid)
        "policy invalid"
    else
        "policy valid";

    if (style.useColor(io, stdout)) {
        try stdout.print("Summary: {s} · {s}{d} active{s} · {s}{d} limited{s} · {s}{d} unavailable{s} · {s}\n\n", .{
            os.toString(),
            style.Style.green,
            counts.active,
            style.Style.reset,
            style.Style.yellow,
            counts.limited,
            style.Style.reset,
            style.Style.red,
            counts.unavailable,
            style.Style.reset,
            policy_status,
        });
    } else {
        try stdout.print("Summary: {s} · {d} active · {d} limited · {d} unavailable · {s}\n\n", .{
            os.toString(),
            counts.active,
            counts.limited,
            counts.unavailable,
            policy_status,
        });
    }

    if (!verbose) {
        try writeRecommendations(stdout, context);
        return;
    }

    try stdout.print("OS: {s}\n", .{os.toString()});
    try stdout.print("Version: {s}\n\n", .{cli.version});
    try writeIntegrationReport(stdout, context);
    try stdout.writeAll("Capabilities:\n");
    for (doctor_capabilities) |item| {
        if (item.feature) |feature| {
            const report = backend_report.get(feature);
            const cg = levelColorAndGlyph(report.level);
            if (style.useColor(io, stdout)) {
                try stdout.print("  {s} {s}: {s}{s}{s} ({s})\n", .{ cg.glyph, item.label, cg.color, report.level.toString(), style.Style.reset, report.note });
            } else {
                try stdout.print("  {s} {s}: {s} ({s})\n", .{ cg.glyph, item.label, report.level.toString(), report.note });
            }
        } else if (item.capability) |capability| {
            const report = core.platform.reportCapability(os, capability);
            const cg = stateColorAndGlyph(report.state);
            if (style.useColor(io, stdout)) {
                try stdout.print("  {s} {s}: {s}{s}{s} ({s})\n", .{ cg.glyph, item.label, cg.color, report.state.toString(), style.Style.reset, report.note });
            } else {
                try stdout.print("  {s} {s}: {s} ({s})\n", .{ cg.glyph, item.label, report.state.toString(), report.note });
            }
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
        try writeWindowsBackendReport(io, stdout, backend_report);
    } else {
        try writeBackendLine(io, stdout, backend_report, .policy_engine);
        try writeBackendLine(io, stdout, backend_report, .env_filtering);
        try writeBackendLine(io, stdout, backend_report, .path_staging);
        if (os == .macos) {
            try stdout.writeAll("  transparent file enforcement: limited (no transparent macOS filesystem monitor is installed; Orca-mediated staging and protected path matching are active)\n");
        }
        try writeBackendLine(io, stdout, backend_report, .shell_wrapping);
        try writeBackendLine(io, stdout, backend_report, .path_shims);
        try writeBackendLine(io, stdout, backend_report, .process_supervision);
        if (os == .linux) {
            try writeBackendLine(io, stdout, backend_report, .user_namespaces);
            try writeBackendLine(io, stdout, backend_report, .mount_namespaces);
            try writeBackendLine(io, stdout, backend_report, .seccomp);
            try writeBackendLine(io, stdout, backend_report, .landlock);
            try writeBackendLine(io, stdout, backend_report, .cgroups);
        }
        try writeBackendLine(io, stdout, backend_report, .network_enforce);
        try writeBackendLine(io, stdout, backend_report, .mcp_stdio_proxy);
        try writeBackendLine(io, stdout, backend_report, .strong_sandbox);
        try writeBackendLine(io, stdout, backend_report, .audit);
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

fn writeWindowsBackendReport(io: std.Io, stdout: anytype, backend_report: sandbox.backend.ReportSet) !void {
    try writeBackendLine(io, stdout, backend_report, .policy_engine);
    try writeBackendLine(io, stdout, backend_report, .env_filtering);
    try writeBackendLine(io, stdout, backend_report, .path_staging);
    try writeBackendLine(io, stdout, backend_report, .path_shims);
    const shell = backend_report.get(.shell_wrapping);
    const shell_cg = levelColorAndGlyph(shell.level);
    if (style.useColor(io, stdout)) {
        try stdout.print("  {s} cmd wrapper: {s}partial{s} ({s})\n", .{ shell_cg.glyph, style.Style.yellow, style.Style.reset, shell.note });
        try stdout.print("  {s} PowerShell wrapper: {s}partial{s} ({s})\n", .{ shell_cg.glyph, style.Style.yellow, style.Style.reset, shell.note });
    } else {
        try stdout.print("  cmd wrapper: partial ({s})\n", .{shell.note});
        try stdout.print("  PowerShell wrapper: partial ({s})\n", .{shell.note});
    }
    const cleanup = backend_report.get(.process_supervision);
    const cleanup_cg = levelColorAndGlyph(cleanup.level);
    if (style.useColor(io, stdout)) {
        try stdout.print("  {s} process cleanup: {s}{s}{s} ({s})\n", .{ cleanup_cg.glyph, cleanup_cg.color, cleanup.level.toString(), style.Style.reset, cleanup.note });
    } else {
        try stdout.print("  process cleanup: {s} ({s})\n", .{ cleanup.level.toString(), cleanup.note });
    }
    try stdout.writeAll("  transparent file enforcement: limited (no transparent Windows filesystem enforcement is installed; Orca-mediated staging and protected path matching are active)\n");
    try writeBackendLine(io, stdout, backend_report, .network_enforce);
    try writeBackendLine(io, stdout, backend_report, .strong_sandbox);
    try writeBackendLine(io, stdout, backend_report, .mcp_stdio_proxy);
    try writeBackendLine(io, stdout, backend_report, .audit);
    try stdout.writeByte('\n');
}

fn levelColorAndGlyph(level: sandbox.backend.Level) struct { color: []const u8, glyph: []const u8 } {
    return switch (level) {
        .active => .{ .color = style.Style.green, .glyph = "✓" },
        .partial, .limited, .observe_only, .wrapper_only => .{ .color = style.Style.yellow, .glyph = "◌" },
        .unavailable, .unsupported, .failed => .{ .color = style.Style.red, .glyph = "✗" },
    };
}

fn stateColorAndGlyph(state: core.platform.CapabilityState) struct { color: []const u8, glyph: []const u8 } {
    return switch (state) {
        .active => .{ .color = style.Style.green, .glyph = "✓" },
        .partial, .limited, .observe => .{ .color = style.Style.yellow, .glyph = "◌" },
        .unavailable, .unknown => .{ .color = style.Style.red, .glyph = "✗" },
    };
}

fn writeBackendLine(io: std.Io, stdout: anytype, backend_report: sandbox.backend.ReportSet, feature: sandbox.backend.Feature) !void {
    const report = backend_report.get(feature);
    const cg = levelColorAndGlyph(report.level);
    if (style.useColor(io, stdout)) {
        try stdout.print("  {s} {s}: {s}{s}{s} ({s})\n", .{ cg.glyph, report.feature.label(), cg.color, report.level.toString(), style.Style.reset, report.note });
    } else {
        try stdout.print("  {s} {s}: {s} ({s})\n", .{ cg.glyph, report.feature.label(), report.level.toString(), report.note });
    }
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
        try stdout.writeAll("  Runtime assets (fixtures, integrations) not found.\n");
        try stdout.writeAll("  This is common after a fresh packaged install (curl|sh, Homebrew, npm).\n\n");
        try stdout.writeAll("  Paste these two lines in your current terminal (then re-run `orca doctor`):\n\n");
        try stdout.writeAll("      export PATH=\"$HOME/.local/bin:$PATH\"\n");
        try stdout.writeAll("      export ORCA_RESOURCE_ROOT=\"$HOME/.local/share/orca/current\"\n\n");
        try stdout.writeAll("  (Use the exact paths printed by your installer if they differ.)\n");
    } else {
        try stdout.writeAll("  Run `orca run -- <command>` or `orca redteam --ci` for a local smoke test.\n");
    }
}

fn collectIntegrationContext(io: std.Io, allocator: std.mem.Allocator) !IntegrationContext {
    const workspace_root = supervisor.resolveWorkspaceRoot(io, allocator, null, ".") catch try allocator.dupe(u8, ".");
    errdefer allocator.free(workspace_root);
    return try collectIntegrationContextAt(io, allocator, workspace_root);
}

fn collectIntegrationContextAt(io: std.Io, allocator: std.mem.Allocator, workspace_root: []const u8) !IntegrationContext {
    const git_present = hasPath(io, workspace_root, ".git");

    const policy_path = try std.fs.path.join(allocator, &.{ workspace_root, ".orca", "policy.yaml" });
    defer allocator.free(policy_path);
    var policy_present = false;
    var policy_valid = false;
    var policy_error: ?[]const u8 = null;
    errdefer if (policy_error) |value| allocator.free(value);
    if (fileExistsAbsolute(io, policy_path)) {
        policy_present = true;
        if (core_api.loadPolicyFile(io, allocator, policy_path)) |loaded_policy| {
            var loaded = loaded_policy;
            loaded.deinit();
            policy_valid = true;
        } else |err| {
            if (err == error.OutOfMemory) return err;
            policy_error = try std.fmt.allocPrint(allocator, "{s}", .{@errorName(err)});
        }
    }
    const manifests = countMcpManifests(io, allocator, workspace_root);
    const agents = try detectAgents(io, allocator);
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
        .audit_sessions_present = hasPath(io, workspace_root, ".orca/sessions"),
        .redteam_fixtures_present = resource_root.resourcePathExists(io, allocator, .{ .workspace_root = workspace_root }, "fixtures"),
    };
}

fn hasPath(io: std.Io, root: []const u8, relative: []const u8) bool {
    const allocator = std.heap.page_allocator;
    const path = std.fs.path.join(allocator, &.{ root, relative }) catch return false;
    defer allocator.free(path);
    return fileExistsAbsolute(io, path);
}

fn fileExistsAbsolute(io: std.Io, path: []const u8) bool {
    if (std.fs.path.isAbsolute(path)) {
        std.Io.Dir.accessAbsolute(io, path, .{}) catch return false;
    } else {
        std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    }
    return true;
}

const ManifestCounts = struct { total: usize = 0, invalid: usize = 0 };

fn countMcpManifests(io: std.Io, allocator: std.mem.Allocator, workspace_root: []const u8) ManifestCounts {
    const mcp_dir_path = std.fs.path.join(allocator, &.{ workspace_root, ".orca", "mcp" }) catch return .{};
    defer allocator.free(mcp_dir_path);
    var dir = std.Io.Dir.cwd().openDir(io, mcp_dir_path, .{ .iterate = true }) catch return .{};
    defer dir.close(io);

    var counts: ManifestCounts = .{};
    var iterator = dir.iterate();
    while (iterator.next(io) catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".yaml") and !std.mem.endsWith(u8, entry.name, ".yml")) continue;
        counts.total += 1;
        const manifest_path = std.fs.path.join(allocator, &.{ mcp_dir_path, entry.name }) catch {
            counts.invalid += 1;
            continue;
        };
        defer allocator.free(manifest_path);
        var manifest = orca_mcp.manifests.loadFile(io, allocator, manifest_path) catch {
            counts.invalid += 1;
            continue;
        };
        manifest.deinit(allocator);
    }
    return counts;
}

fn detectAgents(io: std.Io, allocator: std.mem.Allocator) ![]const AgentBinary {
    var found: std.ArrayList(AgentBinary) = .empty;
    errdefer found.deinit(allocator);
    for (known_agent_binaries) |agent| {
        if (binaryInPath(io, allocator, agent.command)) try found.append(allocator, agent);
    }
    return try found.toOwnedSlice(allocator);
}

fn binaryInPath(io: std.Io, allocator: std.mem.Allocator, binary_name: []const u8) bool {
    var env_map = env_util.createProcessMap(allocator) catch return false;
    defer env_map.deinit();
    const path_owned = env_util.getOwned(&env_map, allocator, "PATH") catch return false;
    const path_value = path_owned orelse return false;
    defer allocator.free(path_value);
    var parts = std.mem.splitScalar(u8, path_value, std.fs.path.delimiter);
    while (parts.next()) |dir| {
        if (dir.len == 0) continue;
        const candidate = std.fs.path.join(allocator, &.{ dir, binary_name }) catch continue;
        defer allocator.free(candidate);
        if (fileExistsAbsolute(io, candidate)) return true;
        if (builtin.os.tag == .windows) {
            const exe_candidate = std.fmt.allocPrint(allocator, "{s}.exe", .{candidate}) catch continue;
            defer allocator.free(exe_candidate);
            if (fileExistsAbsolute(io, exe_candidate)) return true;
        }
    }
    return false;
}

const CiStatus = struct {
    detected: bool,
    provider: []const u8,
};

fn detectCi(allocator: std.mem.Allocator) !CiStatus {
    var env_map = try env_util.createProcessMap(allocator);
    defer env_map.deinit();
    if (envPresent(&env_map, "GITHUB_ACTIONS")) return .{ .detected = true, .provider = try allocator.dupe(u8, "GitHub Actions") };
    if (envPresent(&env_map, "CI")) return .{ .detected = true, .provider = try allocator.dupe(u8, "generic CI") };
    return .{ .detected = false, .provider = try allocator.dupe(u8, "none") };
}

fn envPresent(env_map: *const std.process.Environ.Map, name: []const u8) bool {
    const value = env_map.get(name) orelse return false;
    return value.len > 0;
}

fn detectShell(allocator: std.mem.Allocator) ![]const u8 {
    var env_map = try env_util.createProcessMap(allocator);
    defer env_map.deinit();
    if (try env_util.getOwned(&env_map, allocator, "SHELL")) |value| {
        defer allocator.free(value);
        return try allocator.dupe(u8, std.fs.path.basename(value));
    }
    if (env_util.getOwned(&env_map, allocator, "COMSPEC") catch null) |value| {
        defer allocator.free(value);
        return try allocator.dupe(u8, std.fs.path.basename(value));
    }
    if (envPresent(&env_map, "PSModulePath")) return try allocator.dupe(u8, "powershell");
    return try allocator.dupe(u8, "unknown");
}

test "doctor prints OS and planned capabilities" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try command(std.testing.io, &.{"--verbose"}, &stdout_writer, &stderr_writer);

    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "Orca Doctor") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "Integration checks:") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "OS:") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "process supervision:") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "network policy engine: active") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "transparent network enforcement: unavailable") != null or std.mem.indexOf(u8, stdout_writer.buffered(), "transparent network enforcement: limited") != null or std.mem.indexOf(u8, stdout_writer.buffered(), "transparent network enforcement: observe-only") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "proxy-mediated enforcement: limited") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "Backend:") != null or std.mem.indexOf(u8, stdout_writer.buffered(), "Linux backend:") != null or std.mem.indexOf(u8, stdout_writer.buffered(), "macOS backend:") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "env filtering: active") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "strong sandbox:") != null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "doctor can render Linux backend details from an injected report" {
    var stdout_buf: [8192]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    const report = sandbox.backend.detect(.linux);
    var context = try testContext(std.testing.allocator, .{});
    defer context.deinit();

    try writeReport(std.testing.io, &stdout_writer, .linux, report, context, true);

    const written = stdout_writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, written, "Linux backend:") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "user namespace:") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "mount namespace:") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "seccomp:") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "landlock:") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "transparent network enforcement: observe-only") != null);
}

test "doctor can render macOS backend details from an injected report" {
    var stdout_buf: [8192]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    const report = sandbox.backend.detect(.macos);
    var context = try testContext(std.testing.allocator, .{});
    defer context.deinit();

    try writeReport(std.testing.io, &stdout_writer, .macos, report, context, true);

    const written = stdout_writer.buffered();
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
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    const report = sandbox.backend.detect(.windows);
    var context = try testContext(std.testing.allocator, .{});
    defer context.deinit();

    try writeReport(std.testing.io, &stdout_writer, .windows, report, context, true);

    const written = stdout_writer.buffered();
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
    const tmp_path_z = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(tmp_path_z);
    const tmp_path = try std.testing.allocator.dupe(u8, tmp_path_z);

    try tmp.dir.createDirPath(std.testing.io, ".git");
    try tmp.dir.createDirPath(std.testing.io, ".orca");
    {
        const file = try tmp.dir.createFile(std.testing.io, ".orca/policy.yaml", .{});
        defer file.close(std.testing.io);
        try file.writeStreamingAll(std.testing.io, orca_policy.presets.agentPresetText(.generic_agent));
    }

    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);
    var context = try collectIntegrationContextAt(std.testing.io, std.testing.allocator, tmp_path);
    defer context.deinit();

    try writeReport(std.testing.io, &stdout_writer, core.platform.detectOs(), sandbox.backend.detect(core.platform.detectOs()), context, true);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), ".orca/policy.yaml: present and valid") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "git repository: detected") != null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "doctor reports invalid policy clearly without printing synthetic secrets" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path_z = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(tmp_path_z);
    const tmp_path = try std.testing.allocator.dupe(u8, tmp_path_z);

    try tmp.dir.createDirPath(std.testing.io, ".orca");
    {
        const file = try tmp.dir.createFile(std.testing.io, ".orca/policy.yaml", .{});
        defer file.close(std.testing.io);
        try file.writeStreamingAll(std.testing.io,
            \\version: 1
            \\mode: loose
            \\# synthetic secret should not appear in doctor output: ghp_fakeSecretShouldNotPrint
        );
    }

    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);
    var context = try collectIntegrationContextAt(std.testing.io, std.testing.allocator, tmp_path);
    defer context.deinit();

    try writeReport(std.testing.io, &stdout_writer, core.platform.detectOs(), sandbox.backend.detect(core.platform.detectOs()), context, true);
    const output = stdout_writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, ".orca/policy.yaml: invalid") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "UnsupportedPolicyMode") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "ghp_fakeSecretShouldNotPrint") == null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "doctor prints summary line" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try command(std.testing.io, &.{}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "Summary:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "active") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Recommended next step:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Capabilities:") == null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "doctor --verbose prints full report" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try command(std.testing.io, &.{"--verbose"}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "Summary:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Capabilities:") != null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "doctor integration collection returns allocator failures instead of panicking" {
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, collectIntegrationContextAt(std.testing.io, failing_allocator.allocator(), "."));
}

test "doctor output contains status glyphs in plain text mode" {
    var stdout_buf: [8192]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    const report = sandbox.backend.detect(.linux);
    var context = try testContext(std.testing.allocator, .{});
    defer context.deinit();

    try writeReport(std.testing.io, &stdout_writer, .linux, report, context, true);
    const written = stdout_writer.buffered();
    const has_check = std.mem.indexOf(u8, written, "✓") != null;
    const has_diamond = std.mem.indexOf(u8, written, "◌") != null;
    const has_cross = std.mem.indexOf(u8, written, "✗") != null;
    try std.testing.expect(has_check or has_diamond or has_cross);
}

test "doctor output has no ANSI codes in non-TTY mode" {
    var stdout_buf: [8192]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    const report = sandbox.backend.detect(.linux);
    var context = try testContext(std.testing.allocator, .{});
    defer context.deinit();

    try writeReport(std.testing.io, &stdout_writer, .linux, report, context, true);
    const written = stdout_writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, written, "\x1b[") == null);
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
