const std = @import("std");
const builtin = @import("builtin");
const core = @import("../core/mod.zig");
const core_api = @import("../core/api.zig");
const sandbox = @import("../sandbox/mod.zig");

const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");
const cli = @import("mod.zig");

// ---------------------------------------------------------------------------
// Top-level dispatch
// ---------------------------------------------------------------------------

pub fn command(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len > 0 and (std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h"))) {
        _ = try help.writeCommand(stdout, "plugin");
        return exit_codes.success;
    }
    if (argv.len == 0) {
        _ = try help.writeCommand(stderr, "plugin");
        return exit_codes.usage;
    }

    if (std.mem.eql(u8, argv[0], "doctor")) return doctorCommand(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "manifest")) return manifestCommand(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "install")) return installCommand(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "mcp-server")) return mcpServerCommand(argv[1..], stdout, stderr);

    try stderr.print("aegis plugin: unknown subcommand '{s}'.\n", .{argv[0]});
    return exit_codes.usage;
}

// ---------------------------------------------------------------------------
// doctor
// ---------------------------------------------------------------------------

const DoctorTarget = enum { all, codex, claude };

fn doctorCommand(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var target: DoctorTarget = .all;
    var json_mode = false;

    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try stdout.writeAll(
                \\Usage:
                \\  aegis plugin doctor
                \\  aegis plugin doctor [--json]
                \\  aegis plugin doctor codex
                \\  aegis plugin doctor claude
                \\  aegis plugin doctor codex [--json]
                \\  aegis plugin doctor claude [--json]
                \\
            );
            return exit_codes.success;
        }
        if (std.mem.eql(u8, arg, "--json")) {
            json_mode = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "codex")) {
            target = .codex;
            continue;
        }
        if (std.mem.eql(u8, arg, "claude")) {
            target = .claude;
            continue;
        }
        try stderr.print("aegis plugin doctor: unknown option '{s}'.\n", .{arg});
        return exit_codes.usage;
    }

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var report = try collectPluginDoctorReport(allocator);
    defer report.deinit(allocator);

    if (json_mode) {
        try writeDoctorJson(stdout, report, target);
    } else {
        try writeDoctorPlain(stdout, report, target);
    }
    return exit_codes.success;
}

// ---------------------------------------------------------------------------
// Plugin doctor report data
// ---------------------------------------------------------------------------

const PluginDirStatus = struct {
    codex: bool,
    claude: bool,
    common: bool,
};

const HostBinaryStatus = struct {
    codex: bool,
    claude: bool,
};

const PluginDoctorReport = struct {
    aegis_version: []const u8,
    aegis_binary_path: ?[]const u8,
    cwd: []const u8,
    workspace_root: []const u8,
    policy_present: bool,
    policy_valid: bool,
    policy_error: ?[]const u8,
    audit_replay_available: bool,
    mcp_support_status: []const u8,
    plugin_directories: PluginDirStatus,
    host_binaries: HostBinaryStatus,
    drone_workstream_detected: bool,
    drone_safety_mode_active: bool,
    platform_summary: []const u8,
    warnings: [][]const u8,

    fn deinit(self: *PluginDoctorReport, allocator: std.mem.Allocator) void {
        allocator.free(self.cwd);
        allocator.free(self.workspace_root);
        if (self.policy_error) |e| allocator.free(e);
        allocator.free(self.mcp_support_status);
        allocator.free(self.platform_summary);
        if (self.warnings.len > 0) {
            for (self.warnings) |w| allocator.free(w);
            allocator.free(self.warnings);
        }
        if (self.aegis_binary_path) |p| allocator.free(p);
        self.* = undefined;
    }
};

fn collectPluginDoctorReport(allocator: std.mem.Allocator) !PluginDoctorReport {
    const cwd = std.fs.cwd().realpathAlloc(allocator, ".") catch try allocator.dupe(u8, ".");
    const workspace_root = core.supervisor.resolveWorkspaceRoot(allocator, null, ".") catch try allocator.dupe(u8, cwd);

    const policy_path = std.fs.path.join(allocator, &.{ workspace_root, ".aegis", "policy.yaml" }) catch unreachable;
    defer allocator.free(policy_path);
    var policy_present = false;
    var policy_valid = false;
    var policy_error: ?[]const u8 = null;
    if (fileExistsAbsolute(policy_path)) {
        policy_present = true;
        if (core_api.loadPolicyFile(allocator, policy_path)) |loaded_policy| {
            var loaded = loaded_policy;
            loaded.deinit();
            policy_valid = true;
        } else |err| {
            policy_error = std.fmt.allocPrint(allocator, "{s}", .{@errorName(err)}) catch null;
        }
    }

    const audit_replay_available = hasPath(workspace_root, ".aegis/sessions");
    const mcp_support = "stdio proxy active; HTTP transport deferred";

    const plugin_dirs = PluginDirStatus{
        .codex = dirExists("integrations/codex-plugin"),
        .claude = dirExists("integrations/claude-code-plugin"),
        .common = dirExists("integrations/common"),
    };

    const host_bins = HostBinaryStatus{
        .codex = binaryInPath(allocator, "codex"),
        .claude = binaryInPath(allocator, "claude"),
    };

    const drone_detected = hasPath(workspace_root, "packages/edge") or binaryInPath(allocator, "aegis-edge");
    const drone_safety = drone_detected; // safety mode is active when workstream is detected

    var warnings: std.ArrayList([]const u8) = .empty;
    if (!plugin_dirs.common) try warnings.append(allocator, try allocator.dupe(u8, "integrations/common directory missing"));
    if (!plugin_dirs.codex) try warnings.append(allocator, try allocator.dupe(u8, "Codex plugin directory not yet created"));
    if (!plugin_dirs.claude) try warnings.append(allocator, try allocator.dupe(u8, "Claude Code plugin directory not yet created"));
    if (!host_bins.codex) try warnings.append(allocator, try allocator.dupe(u8, "Codex host binary not found in PATH"));
    if (!host_bins.claude) try warnings.append(allocator, try allocator.dupe(u8, "Claude Code host binary not found in PATH"));

    const os = core.platform.detectOs();
    const backend_report = sandbox.backend.detect(os);
    const platform_summary = try std.fmt.allocPrint(allocator, "{s} / {s} / fallback: {s}", .{
        os.toString(),
        backend_report.backend_name,
        backend_report.fallback_level.toString(),
    });

    const binary_path = std.fs.selfExePathAlloc(allocator) catch null;

    return .{
        .aegis_version = cli.version,
        .aegis_binary_path = binary_path,
        .cwd = cwd,
        .workspace_root = workspace_root,
        .policy_present = policy_present,
        .policy_valid = policy_valid,
        .policy_error = policy_error,
        .audit_replay_available = audit_replay_available,
        .mcp_support_status = try allocator.dupe(u8, mcp_support),
        .plugin_directories = plugin_dirs,
        .host_binaries = host_bins,
        .drone_workstream_detected = drone_detected,
        .drone_safety_mode_active = drone_safety,
        .platform_summary = platform_summary,
        .warnings = try warnings.toOwnedSlice(allocator),
    };
}

// ---------------------------------------------------------------------------
// doctor plain output
// ---------------------------------------------------------------------------

fn writeDoctorPlain(stdout: anytype, report: PluginDoctorReport, target: DoctorTarget) !void {
    try stdout.writeAll("Aegis Plugin Doctor\n\n");

    try stdout.print("Aegis version: {s}\n", .{report.aegis_version});
    if (report.aegis_binary_path) |path| {
        try stdout.print("Aegis binary: {s}\n", .{path});
    } else {
        try stdout.writeAll("Aegis binary: unknown\n");
    }
    try stdout.print("Current directory: {s}\n", .{report.cwd});
    try stdout.print("Workspace root: {s}\n", .{report.workspace_root});

    try stdout.writeAll("\nPolicy:\n");
    if (report.policy_present) {
        if (report.policy_valid) {
            try stdout.writeAll("  .aegis/policy.yaml: present and valid\n");
        } else {
            try stdout.print("  .aegis/policy.yaml: invalid ({s})\n", .{report.policy_error orelse "validation failed"});
        }
    } else {
        try stdout.writeAll("  .aegis/policy.yaml: missing\n");
    }

    try stdout.writeAll("\nAudit / replay:\n");
    try stdout.print("  {s}\n", .{if (report.audit_replay_available) "session artifacts present" else "no local sessions detected"});

    try stdout.writeAll("\nMCP support:\n");
    try stdout.print("  {s}\n", .{report.mcp_support_status});

    try stdout.writeAll("\nPlugin directories:\n");
    try stdout.print("  integrations/common: {s}\n", .{if (report.plugin_directories.common) "found" else "missing"});
    try stdout.print("  integrations/codex-plugin: {s}\n", .{if (report.plugin_directories.codex) "found" else "missing"});
    try stdout.print("  integrations/claude-code-plugin: {s}\n", .{if (report.plugin_directories.claude) "found" else "missing"});

    try stdout.writeAll("\nHost binaries:\n");
    try stdout.print("  codex: {s}\n", .{if (report.host_binaries.codex) "found in PATH" else "not found"});
    try stdout.print("  claude: {s}\n", .{if (report.host_binaries.claude) "found in PATH" else "not found"});

    try stdout.writeAll("\nDrone workstream:\n");
    if (report.drone_workstream_detected) {
        try stdout.writeAll("  detected: yes\n");
        try stdout.writeAll("  safety mode: plugin default-deny for live-control patterns\n");
        try stdout.writeAll("  simulation demos: allowed\n");
        try stdout.writeAll("  live control: requires explicit policy and human approval\n");
    } else {
        try stdout.writeAll("  detected: no\n");
    }

    try stdout.writeAll("\nPlatform:\n");
    try stdout.print("  {s}\n", .{report.platform_summary});

    if (report.warnings.len > 0) {
        try stdout.writeAll("\nWarnings:\n");
        for (report.warnings) |w| {
            try stdout.print("  - {s}\n", .{w});
        }
    }

    // Target-specific section
    switch (target) {
        .all => {},
        .codex => {
            try stdout.writeAll("\nCodex plugin status:\n");
            try stdout.print("  host binary: {s}\n", .{if (report.host_binaries.codex) "detected" else "not detected"});
            try stdout.print("  plugin directory: {s}\n", .{if (report.plugin_directories.codex) "present" else "not yet created"});
            try stdout.writeAll("  install: use 'aegis plugin install codex --dry-run' to preview\n");
        },
        .claude => {
            try stdout.writeAll("\nClaude Code plugin status:\n");
            try stdout.print("  host binary: {s}\n", .{if (report.host_binaries.claude) "detected" else "not detected"});
            try stdout.print("  plugin directory: {s}\n", .{if (report.plugin_directories.claude) "present" else "not yet created"});
            try stdout.writeAll("  install: use 'aegis plugin install claude --dry-run' to preview\n");
        },
    }

    try stdout.writeAll("\n");
}

// ---------------------------------------------------------------------------
// doctor JSON output
// ---------------------------------------------------------------------------

fn writeDoctorJson(stdout: anytype, report: PluginDoctorReport, target: DoctorTarget) !void {
    try stdout.writeAll("{\n");
    try stdout.writeAll("  \"aegis_version\": ");
    try writeJsonString(stdout, report.aegis_version);
    try stdout.writeAll(",\n");

    try stdout.writeAll("  \"aegis_binary_path\": ");
    if (report.aegis_binary_path) |path| {
        try writeJsonString(stdout, path);
    } else {
        try stdout.writeAll("null");
    }
    try stdout.writeAll(",\n");

    try stdout.print("  \"cwd\": ", .{});
    try writeJsonString(stdout, report.cwd);
    try stdout.writeAll(",\n");

    try stdout.print("  \"workspace_root\": ", .{});
    try writeJsonString(stdout, report.workspace_root);
    try stdout.writeAll(",\n");

    try stdout.writeAll("  \"policy\": {\n");
    try stdout.print("    \"present\": {s},\n", .{if (report.policy_present) "true" else "false"});
    try stdout.print("    \"valid\": {s}\n", .{if (report.policy_valid) "true" else "false"});
    try stdout.writeAll("  },\n");

    try stdout.writeAll("  \"audit_replay_available\": ");
    try stdout.writeAll(if (report.audit_replay_available) "true" else "false");
    try stdout.writeAll(",\n");

    try stdout.print("  \"mcp_support_status\": ", .{});
    try writeJsonString(stdout, report.mcp_support_status);
    try stdout.writeAll(",\n");

    try stdout.writeAll("  \"plugin_directories\": {\n");
    try stdout.print("    \"codex\": {s},\n", .{if (report.plugin_directories.codex) "true" else "false"});
    try stdout.print("    \"claude\": {s},\n", .{if (report.plugin_directories.claude) "true" else "false"});
    try stdout.print("    \"common\": {s}\n", .{if (report.plugin_directories.common) "true" else "false"});
    try stdout.writeAll("  },\n");

    try stdout.writeAll("  \"host_binaries\": {\n");
    try stdout.print("    \"codex\": {s},\n", .{if (report.host_binaries.codex) "true" else "false"});
    try stdout.print("    \"claude\": {s}\n", .{if (report.host_binaries.claude) "true" else "false"});
    try stdout.writeAll("  },\n");

    try stdout.writeAll("  \"drone\": {\n");
    try stdout.print("    \"workstream_detected\": {s},\n", .{if (report.drone_workstream_detected) "true" else "false"});
    try stdout.print("    \"safety_mode_active\": {s},\n", .{if (report.drone_safety_mode_active) "true" else "false"});
    try stdout.writeAll("    \"live_control_policy\": \"default-deny\",\n");
    try stdout.writeAll("    \"simulation_demos\": \"allowed\"\n");
    try stdout.writeAll("  },\n");

    try stdout.print("  \"platform_summary\": ", .{});
    try writeJsonString(stdout, report.platform_summary);
    try stdout.writeAll(",\n");

    try stdout.writeAll("  \"target\": ");
    try writeJsonString(stdout, @tagName(target));
    try stdout.writeAll(",\n");

    try stdout.writeAll("  \"warnings\": [\n");
    for (report.warnings, 0..) |w, i| {
        try stdout.writeAll("    ");
        try writeJsonString(stdout, w);
        if (i < report.warnings.len - 1) try stdout.writeAll(",");
        try stdout.writeAll("\n");
    }
    try stdout.writeAll("  ]\n");

    try stdout.writeAll("}\n");
}

// ---------------------------------------------------------------------------
// manifest
// ---------------------------------------------------------------------------

const ManifestTarget = enum { codex, claude, all };

fn manifestCommand(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var target: ManifestTarget = .all;
    var json_mode = false;

    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try stdout.writeAll(
                \\Usage:
                \\  aegis plugin manifest codex
                \\  aegis plugin manifest claude
                \\  aegis plugin manifest all
                \\  aegis plugin manifest <target> [--json]
                \\
            );
            return exit_codes.success;
        }
        if (std.mem.eql(u8, arg, "--json")) {
            json_mode = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "codex")) {
            target = .codex;
            continue;
        }
        if (std.mem.eql(u8, arg, "claude")) {
            target = .claude;
            continue;
        }
        if (std.mem.eql(u8, arg, "all")) {
            target = .all;
            continue;
        }
        try stderr.print("aegis plugin manifest: unknown option '{s}'.\n", .{arg});
        return exit_codes.usage;
    }

    if (json_mode) {
        try writeManifestJson(stdout, target);
    } else {
        try writeManifestPlain(stdout, target);
    }
    return exit_codes.success;
}

fn writeManifestPlain(stdout: anytype, target: ManifestTarget) !void {
    switch (target) {
        .codex => {
            const path = "integrations/codex-plugin/.codex-plugin/plugin.json";
            const exists = fileExistsAbsolute(path);
            try stdout.writeAll("Codex plugin manifest:\n");
            try stdout.print("  expected path: {s}\n", .{path});
            try stdout.print("  status: {s}\n", .{if (exists) "exists" else "missing"});
            if (exists) {
                try stdout.writeAll("  note: validation of manifest shape is deferred to host-specific checks\n");
            }
        },
        .claude => {
            const path = "integrations/claude-code-plugin/.claude-plugin/plugin.json";
            const exists = fileExistsAbsolute(path);
            try stdout.writeAll("Claude Code plugin manifest:\n");
            try stdout.print("  expected path: {s}\n", .{path});
            try stdout.print("  status: {s}\n", .{if (exists) "exists" else "missing"});
            if (exists) {
                try stdout.writeAll("  note: validation of manifest shape is deferred to host-specific checks\n");
            }
        },
        .all => {
            try stdout.writeAll("Plugin manifests:\n");
            const codex_path = "integrations/codex-plugin/.codex-plugin/plugin.json";
            const claude_path = "integrations/claude-code-plugin/.claude-plugin/plugin.json";
            try stdout.print("  codex:   {s} ({s})\n", .{ codex_path, if (fileExistsAbsolute(codex_path)) "exists" else "missing" });
            try stdout.print("  claude:  {s} ({s})\n", .{ claude_path, if (fileExistsAbsolute(claude_path)) "exists" else "missing" });
        },
    }
}

fn writeManifestJson(stdout: anytype, target: ManifestTarget) !void {
    try stdout.writeAll("{\n");
    switch (target) {
        .codex => {
            const path = "integrations/codex-plugin/.codex-plugin/plugin.json";
            try stdout.writeAll("  \"codex\": {\n");
            try stdout.print("    \"path\": ", .{});
            try writeJsonString(stdout, path);
            try stdout.writeAll(",\n");
            try stdout.print("    \"status\": \"{s}\"\n", .{if (fileExistsAbsolute(path)) "exists" else "missing"});
            try stdout.writeAll("  }\n");
        },
        .claude => {
            const path = "integrations/claude-code-plugin/.claude-plugin/plugin.json";
            try stdout.writeAll("  \"claude\": {\n");
            try stdout.print("    \"path\": ", .{});
            try writeJsonString(stdout, path);
            try stdout.writeAll(",\n");
            try stdout.print("    \"status\": \"{s}\"\n", .{if (fileExistsAbsolute(path)) "exists" else "missing"});
            try stdout.writeAll("  }\n");
        },
        .all => {
            const codex_path = "integrations/codex-plugin/.codex-plugin/plugin.json";
            const claude_path = "integrations/claude-code-plugin/.claude-plugin/plugin.json";
            try stdout.writeAll("  \"codex\": {\n");
            try stdout.print("    \"path\": ", .{});
            try writeJsonString(stdout, codex_path);
            try stdout.writeAll(",\n");
            try stdout.print("    \"status\": \"{s}\"\n", .{if (fileExistsAbsolute(codex_path)) "exists" else "missing"});
            try stdout.writeAll("  },\n");
            try stdout.writeAll("  \"claude\": {\n");
            try stdout.print("    \"path\": ", .{});
            try writeJsonString(stdout, claude_path);
            try stdout.writeAll(",\n");
            try stdout.print("    \"status\": \"{s}\"\n", .{if (fileExistsAbsolute(claude_path)) "exists" else "missing"});
            try stdout.writeAll("  }\n");
        },
    }
    try stdout.writeAll("}\n");
}

// ---------------------------------------------------------------------------
// install
// ---------------------------------------------------------------------------

const InstallTarget = enum { codex, claude, all };

fn installCommand(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var target: InstallTarget = .all;
    var dry_run = true; // default to safe dry-run
    var custom_path: ?[]const u8 = null;
    var yes = false;

    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        const arg = argv[index];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try stdout.writeAll(
                \\Usage:
                \\  aegis plugin install codex [--dry-run]
                \\  aegis plugin install claude [--dry-run]
                \\  aegis plugin install all [--dry-run]
                \\  aegis plugin install codex --path <plugin-path> [--dry-run]
                \\  aegis plugin install claude --path <plugin-path> [--dry-run]
                \\  aegis plugin install <target> [--yes]
                \\
                \\Options:
                \\  --dry-run   Preview changes without mutating host config (default)
                \\  --path      Use a custom plugin path instead of the default
                \\  --yes       Skip confirmation prompt (use with care)
                \\
            );
            return exit_codes.success;
        }
        if (std.mem.eql(u8, arg, "--dry-run")) {
            dry_run = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--yes")) {
            yes = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--path")) {
            if (index + 1 >= argv.len) {
                try stderr.writeAll("aegis plugin install: --path requires a value.\n");
                return exit_codes.usage;
            }
            custom_path = argv[index + 1];
            index += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "codex")) {
            target = .codex;
            continue;
        }
        if (std.mem.eql(u8, arg, "claude")) {
            target = .claude;
            continue;
        }
        if (std.mem.eql(u8, arg, "all")) {
            target = .all;
            continue;
        }
        try stderr.print("aegis plugin install: unknown option '{s}'.\n", .{arg});
        return exit_codes.usage;
    }

    if (!dry_run and !yes) {
        try stderr.writeAll("aegis plugin install: actual installation requires --yes or use --dry-run to preview.\n");
        return exit_codes.usage;
    }

    try stdout.writeAll("Aegis Plugin Install\n\n");

    const targets = switch (target) {
        .codex => &[_]InstallTarget{.codex},
        .claude => &[_]InstallTarget{.claude},
        .all => &[_]InstallTarget{ .codex, .claude },
    };

    for (targets) |t| {
        try stdout.print("Target: {s}\n", .{@tagName(t)});
        try stdout.print("  mode: {s}\n", .{if (dry_run) "dry-run (no changes made)" else "install"});

        if (custom_path) |p| {
            try stdout.print("  custom path: {s}\n", .{p});
        }

        const plugin_dir = switch (t) {
            .codex => custom_path orelse "integrations/codex-plugin",
            .claude => custom_path orelse "integrations/claude-code-plugin",
            .all => unreachable,
        };

        if (!dirExists(plugin_dir)) {
            try stdout.print("  plugin directory: missing ({s})\n", .{plugin_dir});
            try stdout.writeAll("  next step: create the plugin directory and manifest before installing\n");
        } else {
            try stdout.print("  plugin directory: found ({s})\n", .{plugin_dir});

            if (dry_run) {
                try stdout.writeAll("  action: no changes made (dry-run)\n");
                try stdout.writeAll("  next step: host install command is not yet known; manual integration required\n");
            } else {
                try stdout.writeAll("  action: installation would proceed (deferred)\n");
                try stdout.writeAll("  note: actual host plugin installation is not yet implemented\n");
            }
        }

        // Safety notes (always printed)
        try stdout.writeAll("  safety: host config will not be silently overwritten\n");
        try stdout.writeAll("  safety: no credentials or telemetry will be stored\n");
    }

    try stdout.writeAll("\n");
    return exit_codes.success;
}

// ---------------------------------------------------------------------------
// mcp-server
// ---------------------------------------------------------------------------

fn mcpServerCommand(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try stdout.writeAll(
                \\Usage:
                \\  aegis plugin mcp-server [--help]
                \\
                \\Status: limited / deferred
                \\  The Aegis MCP plugin server is planned but not yet active.
                \\  When implemented, it will expose safe read-only Aegis capabilities as MCP tools:
                \\    - aegis_doctor
                \\    - aegis_plugin_doctor
                \\    - aegis_policy_check
                \\    - aegis_policy_explain
                \\    - aegis_redteam
                \\    - aegis_replay_summary
                \\    - aegis_capabilities
                \\    - aegis_drone_safety_status
                \\  The following will NOT be exposed by default:
                \\    - arbitrary shell execution
                \\    - arbitrary file writes
                \\    - raw audit log dumping without redaction
                \\    - credential access
                \\    - policy mutation without explicit approval
                \\    - live drone actuation commands
                \\
            );
            return exit_codes.success;
        }
        try stderr.print("aegis plugin mcp-server: unknown option '{s}'.\n", .{arg});
        return exit_codes.usage;
    }

    try stdout.writeAll("Aegis Plugin MCP Server\n\n");
    try stdout.writeAll("Status: limited / deferred\n");
    try stdout.writeAll("  The Aegis MCP plugin server is planned but not yet active.\n");
    try stdout.writeAll("  It does not listen on any port or transport.\n\n");
    try stdout.writeAll("Planned safe tools (when implemented):\n");
    try stdout.writeAll("  - aegis_doctor\n");
    try stdout.writeAll("  - aegis_plugin_doctor\n");
    try stdout.writeAll("  - aegis_policy_check\n");
    try stdout.writeAll("  - aegis_policy_explain\n");
    try stdout.writeAll("  - aegis_redteam\n");
    try stdout.writeAll("  - aegis_replay_summary\n");
    try stdout.writeAll("  - aegis_capabilities\n");
    try stdout.writeAll("  - aegis_drone_safety_status\n\n");
    try stdout.writeAll("Blocked by default (not exposed):\n");
    try stdout.writeAll("  - arbitrary shell execution\n");
    try stdout.writeAll("  - arbitrary file writes\n");
    try stdout.writeAll("  - raw audit log dumping without redaction\n");
    try stdout.writeAll("  - credential access\n");
    try stdout.writeAll("  - policy mutation without explicit approval\n");
    try stdout.writeAll("  - live drone actuation (arming, takeoff, motor commands, etc.)\n\n");
    try stdout.writeAll("Use 'aegis plugin mcp-server --help' for full details.\n");
    return exit_codes.success;
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

fn fileExistsAbsolute(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn dirExists(path: []const u8) bool {
    var dir = std.fs.cwd().openDir(path, .{}) catch return false;
    dir.close();
    return true;
}

fn hasPath(root: []const u8, relative: []const u8) bool {
    const allocator = std.heap.page_allocator;
    const path = std.fs.path.join(allocator, &.{ root, relative }) catch return false;
    defer allocator.free(path);
    return fileExistsAbsolute(path);
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

fn writeJsonString(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |byte| {
        switch (byte) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0...8, 11...12, 14...0x1f => try writer.print("\\u{x:0>4}", .{byte}),
            else => try writer.writeByte(byte),
        }
    }
    try writer.writeByte('"');
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "plugin command help and invalid subcommands are stable" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const help_code = try command(&.{"--help"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, help_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "plugin") != null);

    stdout_stream.reset();
    stderr_stream.reset();
    const bad_code = try command(&.{"unknown"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, bad_code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "unknown subcommand") != null);
}

test "plugin doctor prints expected sections" {
    var stdout_buf: [16384]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try doctorCommand(&.{}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Aegis Plugin Doctor") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Aegis version:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Policy:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Plugin directories:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Host binaries:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Drone workstream:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Platform:") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin doctor --json emits valid JSON" {
    var stdout_buf: [16384]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try doctorCommand(&.{"--json"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const json = stdout_stream.getWritten();
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();

    try std.testing.expect(parsed.value.object.get("aegis_version") != null);
    try std.testing.expect(parsed.value.object.get("policy") != null);
    try std.testing.expect(parsed.value.object.get("plugin_directories") != null);
    try std.testing.expect(parsed.value.object.get("host_binaries") != null);
    try std.testing.expect(parsed.value.object.get("drone") != null);
    try std.testing.expect(parsed.value.object.get("warnings") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin doctor codex shows codex-specific section" {
    var stdout_buf: [16384]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try doctorCommand(&.{"codex"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Codex plugin status:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "host binary:") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin doctor claude shows claude-specific section" {
    var stdout_buf: [16384]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try doctorCommand(&.{"claude"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Claude Code plugin status:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "host binary:") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin doctor does not print raw env values or secrets" {
    var stdout_buf: [16384]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try doctorCommand(&.{"--json"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    // Should not contain any obviously secret-looking values
    try std.testing.expect(std.mem.indexOf(u8, output, "ghp_") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "sk-") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "password") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "secret") == null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin manifest codex reports expected path" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try manifestCommand(&.{"codex"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "integrations/codex-plugin/.codex-plugin/plugin.json") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "exists") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin manifest claude reports expected path" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try manifestCommand(&.{"claude"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "integrations/claude-code-plugin/.claude-plugin/plugin.json") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "exists") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin manifest all reports both" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try manifestCommand(&.{"all"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "codex:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "claude:") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin manifest --json emits valid JSON" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try manifestCommand(&.{ "all", "--json" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const json = stdout_stream.getWritten();
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();

    try std.testing.expect(parsed.value.object.get("codex") != null);
    try std.testing.expect(parsed.value.object.get("claude") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin install codex --dry-run reports safe preview" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try installCommand(&.{ "codex", "--dry-run" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "dry-run") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "no changes made") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "safety:") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin install claude --dry-run reports safe preview" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try installCommand(&.{ "claude", "--dry-run" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "dry-run") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "no changes made") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin install all --dry-run reports both targets" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try installCommand(&.{ "all", "--dry-run" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Target: codex") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Target: claude") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin install defaults to safe dry-run behavior" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    // Without --dry-run or --yes, install defaults to dry-run (safe)
    const code = try installCommand(&.{"codex"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "dry-run") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "no changes made") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin mcp-server reports limited status honestly" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try mcpServerCommand(&.{}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "limited") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "deferred") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "not yet active") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "aegis_doctor") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "live drone actuation") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin mcp-server does not claim to expose drone actuation" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try mcpServerCommand(&.{}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    // Should mention that drone actuation is in the blocked list
    try std.testing.expect(std.mem.indexOf(u8, output, "live drone actuation") != null);
    // Should NOT say it's active or available
    try std.testing.expect(std.mem.indexOf(u8, output, "MCP server is active") == null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}
