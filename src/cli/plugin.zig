const std = @import("std");
const builtin = @import("builtin");
const core = @import("orca_core").core;
const supervisor = @import("../core/supervisor.zig");
const core_api = @import("orca_core").api;
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

    try stderr.print("orca plugin: unknown subcommand '{s}'.\n", .{argv[0]});
    return exit_codes.usage;
}

// ---------------------------------------------------------------------------
// doctor
// ---------------------------------------------------------------------------

const DoctorTarget = enum { all, codex, claude, opencode, openclaw, hermes };

fn doctorCommand(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var target: DoctorTarget = .all;
    var json_mode = false;

    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try stdout.writeAll(
                \\Usage:
                \\  orca plugin doctor
                \\  orca plugin doctor [--json]
                \\  orca plugin doctor codex
                \\  orca plugin doctor claude
                \\  orca plugin doctor opencode
                \\  orca plugin doctor openclaw
                \\  orca plugin doctor hermes
                \\  orca plugin doctor codex [--json]
                \\  orca plugin doctor claude [--json]
                \\  orca plugin doctor opencode [--json]
                \\  orca plugin doctor openclaw [--json]
                \\  orca plugin doctor hermes [--json]
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
        if (std.mem.eql(u8, arg, "opencode")) {
            target = .opencode;
            continue;
        }
        if (std.mem.eql(u8, arg, "openclaw")) {
            target = .openclaw;
            continue;
        }
        if (std.mem.eql(u8, arg, "hermes") or std.mem.eql(u8, arg, "hermess")) {
            target = .hermes;
            continue;
        }
        try stderr.print("orca plugin doctor: unknown option '{s}'.\n", .{arg});
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
    opencode: bool,
    openclaw: bool,
    hermes: bool,
    common: bool,
};

const HostBinaryStatus = struct {
    codex: bool,
    claude: bool,
    opencode: bool,
    openclaw: bool,
    hermes: bool,
};

const OpenCodePaths = struct {
    project_plugin_exists: bool,
    global_plugin_exists: bool,
    config_references_plugin: bool,
};

const OpenClawPaths = struct {
    plugin_manifest_exists: bool,
    package_json_exists: bool,
    source_exists: bool,
};

const HermesPaths = struct {
    repo_manifest_exists: bool,
    repo_source_exists: bool,
    user_manifest_exists: bool,
    user_source_exists: bool,
    config_references_plugin: bool,
};

const MarketplaceStatus = struct {
    codex_marketplace: bool,
    claude_marketplace: bool,
    codex_plugin_manifest: bool,
    claude_plugin_manifest: bool,
};

const PluginDoctorReport = struct {
    orca_version: []const u8,
    orca_binary_path: ?[]const u8,
    cwd: []const u8,
    workspace_root: []const u8,
    policy_present: bool,
    policy_valid: bool,
    policy_error: ?[]const u8,
    audit_replay_available: bool,
    mcp_support_status: []const u8,
    plugin_directories: PluginDirStatus,
    host_binaries: HostBinaryStatus,
    opencode_paths: OpenCodePaths,
    openclaw_paths: OpenClawPaths,
    hermes_paths: HermesPaths,
    hermes_hook_smoke_passed: bool,
    marketplace: MarketplaceStatus,
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
        if (self.orca_binary_path) |p| allocator.free(p);
        self.* = undefined;
    }
};

fn collectPluginDoctorReport(allocator: std.mem.Allocator) !PluginDoctorReport {
    const cwd = std.fs.cwd().realpathAlloc(allocator, ".") catch try allocator.dupe(u8, ".");
    errdefer allocator.free(cwd);
    const workspace_root = supervisor.resolveWorkspaceRoot(allocator, null, ".") catch try allocator.dupe(u8, cwd);
    errdefer allocator.free(workspace_root);

    const policy_path = try std.fs.path.join(allocator, &.{ workspace_root, ".orca", "policy.yaml" });
    defer allocator.free(policy_path);
    var policy_present = false;
    var policy_valid = false;
    var policy_error: ?[]const u8 = null;
    errdefer if (policy_error) |e| allocator.free(e);
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

    const audit_replay_available = hasPath(workspace_root, ".orca/sessions");
    const mcp_support = "stdio proxy active; HTTP transport deferred";

    const plugin_dirs = PluginDirStatus{
        .codex = pluginDirExists(allocator, "integrations/codex-plugin"),
        .claude = pluginDirExists(allocator, "integrations/claude-code-plugin"),
        .opencode = pluginDirExists(allocator, "integrations/opencode-plugin"),
        .openclaw = pluginDirExists(allocator, "integrations/openclaw-plugin"),
        .hermes = pluginDirExists(allocator, "integrations/hermes-plugin"),
        .common = pluginDirExists(allocator, "integrations/common"),
    };

    const host_bins = HostBinaryStatus{
        .codex = binaryInPath(allocator, "codex"),
        .claude = binaryInPath(allocator, "claude"),
        .opencode = binaryInPath(allocator, "opencode"),
        .openclaw = binaryInPath(allocator, "openclaw"),
        .hermes = binaryInPath(allocator, "hermes"),
    };

    // Check OpenCode-specific plugin paths
    const opencode_project_path = try std.fs.path.join(allocator, &.{ cwd, ".opencode", "plugins", "orca.ts" });
    defer allocator.free(opencode_project_path);

    const opencode_global_path = blk: {
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch {
            break :blk try std.fs.path.join(allocator, &.{ "~", ".config", "opencode", "plugins", "orca.ts" });
        };
        defer allocator.free(home);
        break :blk try std.fs.path.join(allocator, &.{ home, ".config", "opencode", "plugins", "orca.ts" });
    };
    defer allocator.free(opencode_global_path);

    const opencode_paths = OpenCodePaths{
        .project_plugin_exists = fileExistsAbsolute(opencode_project_path),
        .global_plugin_exists = fileExistsAbsolute(opencode_global_path),
        .config_references_plugin = false, // Safe detection deferred
    };

    // Check OpenClaw-specific plugin paths
    const openclaw_manifest_path = try std.fs.path.join(allocator, &.{ cwd, "integrations", "openclaw-plugin", "openclaw.plugin.json" });
    defer allocator.free(openclaw_manifest_path);

    const openclaw_package_json_path = try std.fs.path.join(allocator, &.{ cwd, "integrations", "openclaw-plugin", "package.json" });
    defer allocator.free(openclaw_package_json_path);

    const openclaw_source_path = try std.fs.path.join(allocator, &.{ cwd, "integrations", "openclaw-plugin", "src", "index.ts" });
    defer allocator.free(openclaw_source_path);

    const openclaw_paths = OpenClawPaths{
        .plugin_manifest_exists = fileExistsAbsolute(openclaw_manifest_path),
        .package_json_exists = fileExistsAbsolute(openclaw_package_json_path),
        .source_exists = fileExistsAbsolute(openclaw_source_path),
    };

    const hermes_plugin_dir = try resolveBundledPath(allocator, "integrations/hermes-plugin");
    defer allocator.free(hermes_plugin_dir);
    const hermes_repo_manifest_path = try std.fs.path.join(allocator, &.{ hermes_plugin_dir, "plugin.yaml" });
    defer allocator.free(hermes_repo_manifest_path);
    const hermes_repo_source_path = try std.fs.path.join(allocator, &.{ hermes_plugin_dir, "__init__.py" });
    defer allocator.free(hermes_repo_source_path);
    const hermes_user_root = try hermesUserPluginRoot(allocator);
    defer allocator.free(hermes_user_root);
    const hermes_user_manifest_path = try std.fs.path.join(allocator, &.{ hermes_user_root, "plugin.yaml" });
    defer allocator.free(hermes_user_manifest_path);
    const hermes_user_source_path = try std.fs.path.join(allocator, &.{ hermes_user_root, "__init__.py" });
    defer allocator.free(hermes_user_source_path);
    const hermes_config_path = try hermesConfigPath(allocator);
    defer allocator.free(hermes_config_path);

    const hermes_paths = HermesPaths{
        .repo_manifest_exists = fileExistsAbsolute(hermes_repo_manifest_path),
        .repo_source_exists = fileExistsAbsolute(hermes_repo_source_path),
        .user_manifest_exists = fileExistsAbsolute(hermes_user_manifest_path),
        .user_source_exists = fileExistsAbsolute(hermes_user_source_path),
        .config_references_plugin = fileContains(allocator, hermes_config_path, "orca"),
    };

    const marketplace = MarketplaceStatus{
        .codex_marketplace = fileExistsAbsolute(".agents/plugins/marketplace.json"),
        .claude_marketplace = fileExistsAbsolute(".claude-plugin/marketplace.json"),
        .codex_plugin_manifest = fileExistsAbsolute("integrations/codex-plugin/.codex-plugin/plugin.json"),
        .claude_plugin_manifest = fileExistsAbsolute("integrations/claude-code-plugin/.claude-plugin/plugin.json"),
    };

    var warnings: std.ArrayList([]const u8) = .empty;
    defer warnings.deinit(allocator);
    errdefer {
        for (warnings.items) |warning| allocator.free(warning);
    }
    if (!plugin_dirs.common) try appendWarning(allocator, &warnings, "integrations/common directory missing");
    if (!plugin_dirs.codex) try appendWarning(allocator, &warnings, "Codex plugin directory not yet created");
    if (!plugin_dirs.claude) try appendWarning(allocator, &warnings, "Claude Code plugin directory not yet created");
    if (!plugin_dirs.opencode) try appendWarning(allocator, &warnings, "OpenCode plugin directory not yet created");
    if (!plugin_dirs.openclaw) try appendWarning(allocator, &warnings, "OpenClaw plugin directory not yet created");
    if (!plugin_dirs.hermes) try appendWarning(allocator, &warnings, "Hermes plugin directory not yet created");
    if (!host_bins.codex) try appendWarning(allocator, &warnings, "Codex host binary not found in PATH");
    if (!host_bins.claude) try appendWarning(allocator, &warnings, "Claude Code host binary not found in PATH");
    if (!host_bins.opencode) try appendWarning(allocator, &warnings, "OpenCode host binary not found in PATH");
    if (!host_bins.openclaw) try appendWarning(allocator, &warnings, "OpenClaw host binary not found in PATH");
    if (!host_bins.hermes) try appendWarning(allocator, &warnings, "Hermes host binary not found in PATH");

    const hermes_hook_smoke_passed = blk: {
        const result = smokeTestHook(allocator, "hermes", "pre_tool_call", "tests/fixtures/hook-safe.json", "allow") catch break :blk false;
        break :blk result.passed;
    };
    if (!hermes_hook_smoke_passed) {
        try appendWarning(allocator, &warnings, "Hermes hook smoke test failed: Orca may be too old for Hermes hooks (upgrade via ./scripts/install-orca-plugin.sh hermes)");
    }

    const os = core.platform.detectOs();
    const backend_report = sandbox.backend.detect(os);
    const platform_summary = try std.fmt.allocPrint(allocator, "{s} / {s} / fallback: {s}", .{
        os.toString(),
        backend_report.backend_name,
        backend_report.fallback_level.toString(),
    });
    errdefer allocator.free(platform_summary);

    const binary_path = std.fs.selfExePathAlloc(allocator) catch null;
    errdefer if (binary_path) |p| allocator.free(p);
    const mcp_support_status = try allocator.dupe(u8, mcp_support);
    errdefer allocator.free(mcp_support_status);
    const warning_items = try warnings.toOwnedSlice(allocator);

    return .{
        .orca_version = cli.version,
        .orca_binary_path = binary_path,
        .cwd = cwd,
        .workspace_root = workspace_root,
        .policy_present = policy_present,
        .policy_valid = policy_valid,
        .policy_error = policy_error,
        .audit_replay_available = audit_replay_available,
        .mcp_support_status = mcp_support_status,
        .plugin_directories = plugin_dirs,
        .host_binaries = host_bins,
        .opencode_paths = opencode_paths,
        .openclaw_paths = openclaw_paths,
        .hermes_paths = hermes_paths,
        .hermes_hook_smoke_passed = hermes_hook_smoke_passed,
        .marketplace = marketplace,
        .platform_summary = platform_summary,
        .warnings = warning_items,
    };
}

fn appendWarning(allocator: std.mem.Allocator, warnings: *std.ArrayList([]const u8), message: []const u8) !void {
    const owned = try allocator.dupe(u8, message);
    errdefer allocator.free(owned);
    try warnings.append(allocator, owned);
}

// ---------------------------------------------------------------------------
// doctor plain output
// ---------------------------------------------------------------------------

fn writeDoctorPlain(stdout: anytype, report: PluginDoctorReport, target: DoctorTarget) !void {
    try stdout.writeAll("Orca Plugin Doctor\n\n");

    try stdout.print("Orca version: {s}\n", .{report.orca_version});
    if (report.orca_binary_path) |path| {
        try stdout.print("Orca binary: {s}\n", .{path});
    } else {
        try stdout.writeAll("Orca binary: unknown\n");
    }
    try stdout.print("Current directory: {s}\n", .{report.cwd});
    try stdout.print("Workspace root: {s}\n", .{report.workspace_root});

    try stdout.writeAll("\nPolicy:\n");
    if (report.policy_present) {
        if (report.policy_valid) {
            try stdout.writeAll("  .orca/policy.yaml: present and valid\n");
        } else {
            try stdout.print("  .orca/policy.yaml: invalid ({s})\n", .{report.policy_error orelse "validation failed"});
        }
    } else {
        try stdout.writeAll("  .orca/policy.yaml: missing\n");
        try stdout.writeAll("    → Fix: orca init --preset generic-agent\n");
    }

    try stdout.writeAll("\nAudit / replay:\n");
    try stdout.print("  {s}\n", .{if (report.audit_replay_available) "session artifacts present" else "no local sessions detected"});

    try stdout.writeAll("\nMCP support:\n");
    try stdout.print("  {s}\n", .{report.mcp_support_status});

    try stdout.writeAll("\nPlugin directories:\n");
    try stdout.print("  integrations/common: {s}\n", .{if (report.plugin_directories.common) "found" else "missing"});
    if (!report.plugin_directories.common) try stdout.writeAll("    → Fix: orca plugin install all --yes\n");
    try stdout.print("  integrations/codex-plugin: {s}\n", .{if (report.plugin_directories.codex) "found" else "missing"});
    if (!report.plugin_directories.codex) try stdout.writeAll("    → Fix: orca plugin install codex --yes\n");
    try stdout.print("  integrations/claude-code-plugin: {s}\n", .{if (report.plugin_directories.claude) "found" else "missing"});
    if (!report.plugin_directories.claude) try stdout.writeAll("    → Fix: orca plugin install claude --yes\n");
    try stdout.print("  integrations/opencode-plugin: {s}\n", .{if (report.plugin_directories.opencode) "found" else "missing"});
    if (!report.plugin_directories.opencode) try stdout.writeAll("    → Fix: orca plugin install opencode --yes\n");
    try stdout.print("  integrations/openclaw-plugin: {s}\n", .{if (report.plugin_directories.openclaw) "found" else "missing"});
    if (!report.plugin_directories.openclaw) try stdout.writeAll("    → Fix: orca plugin install openclaw --yes\n");
    try stdout.print("  integrations/hermes-plugin: {s}\n", .{if (report.plugin_directories.hermes) "found" else "missing"});
    if (!report.plugin_directories.hermes) try stdout.writeAll("    → Fix: orca plugin install hermes --yes\n");

    try stdout.writeAll("\nHost binaries:\n");
    try stdout.print("  codex: {s}\n", .{if (report.host_binaries.codex) "found in PATH" else "not found"});
    if (!report.host_binaries.codex) try stdout.writeAll("    → Fix: orca plugin install codex --yes\n");
    try stdout.print("  claude: {s}\n", .{if (report.host_binaries.claude) "found in PATH" else "not found"});
    if (!report.host_binaries.claude) try stdout.writeAll("    → Fix: orca plugin install claude --yes\n");
    try stdout.print("  opencode: {s}\n", .{if (report.host_binaries.opencode) "found in PATH" else "not found"});
    if (!report.host_binaries.opencode) try stdout.writeAll("    → Fix: orca plugin install opencode --yes\n");
    try stdout.print("  openclaw: {s}\n", .{if (report.host_binaries.openclaw) "found in PATH" else "not found"});
    if (!report.host_binaries.openclaw) try stdout.writeAll("    → Fix: orca plugin install openclaw --yes\n");
    try stdout.print("  hermes: {s}\n", .{if (report.host_binaries.hermes) "found in PATH" else "not found"});
    if (!report.host_binaries.hermes) try stdout.writeAll("    → Fix: orca plugin install hermes --yes\n");

    try stdout.writeAll("\nMarketplace files:\n");
    try stdout.print("  .agents/plugins/marketplace.json: {s}\n", .{if (report.marketplace.codex_marketplace) "present" else "missing"});
    if (!report.marketplace.codex_marketplace) try stdout.writeAll("    → Fix: orca plugin install codex --yes\n");
    try stdout.print("  .claude-plugin/marketplace.json: {s}\n", .{if (report.marketplace.claude_marketplace) "present" else "missing"});
    if (!report.marketplace.claude_marketplace) try stdout.writeAll("    → Fix: orca plugin install claude --yes\n");

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
            if (!report.host_binaries.codex) try stdout.writeAll("    → Fix: orca plugin install codex --yes\n");
            try stdout.print("  plugin directory: {s}\n", .{if (report.plugin_directories.codex) "present" else "not yet created"});
            if (!report.plugin_directories.codex) try stdout.writeAll("    → Fix: orca plugin install codex --yes\n");
            try stdout.print("  marketplace file: {s}\n", .{if (report.marketplace.codex_marketplace) "present" else "missing"});
            if (!report.marketplace.codex_marketplace) try stdout.writeAll("    → Fix: orca plugin install codex --yes\n");
            try stdout.print("  plugin manifest: {s}\n", .{if (report.marketplace.codex_plugin_manifest) "present" else "missing"});
            if (!report.marketplace.codex_plugin_manifest) try stdout.writeAll("    → Fix: orca plugin install codex --yes\n");
            try stdout.writeAll("  install: use 'orca plugin install codex --dry-run' to preview\n");
        },
        .claude => {
            try stdout.writeAll("\nClaude Code plugin status:\n");
            try stdout.print("  host binary: {s}\n", .{if (report.host_binaries.claude) "detected" else "not detected"});
            if (!report.host_binaries.claude) try stdout.writeAll("    → Fix: orca plugin install claude --yes\n");
            try stdout.print("  plugin directory: {s}\n", .{if (report.plugin_directories.claude) "present" else "not yet created"});
            if (!report.plugin_directories.claude) try stdout.writeAll("    → Fix: orca plugin install claude --yes\n");
            try stdout.print("  marketplace file: {s}\n", .{if (report.marketplace.claude_marketplace) "present" else "missing"});
            if (!report.marketplace.claude_marketplace) try stdout.writeAll("    → Fix: orca plugin install claude --yes\n");
            try stdout.print("  plugin manifest: {s}\n", .{if (report.marketplace.claude_plugin_manifest) "present" else "missing"});
            if (!report.marketplace.claude_plugin_manifest) try stdout.writeAll("    → Fix: orca plugin install claude --yes\n");
            try stdout.writeAll("  install: use 'orca plugin install claude --dry-run' to preview\n");
        },
        .opencode => {
            try stdout.writeAll("\nOpenCode plugin status:\n");
            try stdout.print("  host binary: {s}\n", .{if (report.host_binaries.opencode) "detected" else "not detected"});
            if (!report.host_binaries.opencode) try stdout.writeAll("    → Fix: orca plugin install opencode --yes\n");
            try stdout.print("  plugin directory: {s}\n", .{if (report.plugin_directories.opencode) "present" else "not yet created"});
            if (!report.plugin_directories.opencode) try stdout.writeAll("    → Fix: orca plugin install opencode --yes\n");
            try stdout.print("  project plugin path (.opencode/plugins/orca.ts): {s}\n", .{if (report.opencode_paths.project_plugin_exists) "exists" else "not found"});
            if (!report.opencode_paths.project_plugin_exists) try stdout.writeAll("    → Fix: orca plugin install opencode --yes\n");
            try stdout.print("  global plugin path (~/.config/opencode/plugins/orca.ts): {s}\n", .{if (report.opencode_paths.global_plugin_exists) "exists" else "not found"});
            if (!report.opencode_paths.global_plugin_exists) try stdout.writeAll("    → Fix: orca plugin install opencode --yes\n");
            try stdout.writeAll("  install: use 'orca plugin install opencode --dry-run' to preview\n");
            try stdout.writeAll("  note: OpenCode plugin uses TypeScript hooks, not a manifest file\n");
        },
        .openclaw => {
            try stdout.writeAll("\nOpenClaw plugin status:\n");
            try stdout.print("  host binary: {s}\n", .{if (report.host_binaries.openclaw) "detected" else "not detected"});
            if (!report.host_binaries.openclaw) try stdout.writeAll("    → Fix: orca plugin install openclaw --yes\n");
            try stdout.print("  plugin directory: {s}\n", .{if (report.plugin_directories.openclaw) "present" else "not yet created"});
            if (!report.plugin_directories.openclaw) try stdout.writeAll("    → Fix: orca plugin install openclaw --yes\n");
            try stdout.print("  plugin manifest (openclaw.plugin.json): {s}\n", .{if (report.openclaw_paths.plugin_manifest_exists) "exists" else "not found"});
            if (!report.openclaw_paths.plugin_manifest_exists) try stdout.writeAll("    → Fix: orca plugin install openclaw --yes\n");
            try stdout.print("  package.json: {s}\n", .{if (report.openclaw_paths.package_json_exists) "exists" else "not found"});
            if (!report.openclaw_paths.package_json_exists) try stdout.writeAll("    → Fix: orca plugin install openclaw --yes\n");
            try stdout.print("  source (src/index.ts): {s}\n", .{if (report.openclaw_paths.source_exists) "exists" else "not found"});
            if (!report.openclaw_paths.source_exists) try stdout.writeAll("    → Fix: orca plugin install openclaw --yes\n");
            try stdout.writeAll("  install: use 'orca plugin install openclaw --dry-run' to preview\n");
            try stdout.writeAll("  note: npm package orca-openclaw-plugin is published; ClawHub package orca-openclaw-plugin is published\n");
        },
        .hermes => {
            try stdout.writeAll("\nHermes plugin status:\n");
            try stdout.print("  host binary: {s}\n", .{if (report.host_binaries.hermes) "detected" else "not detected"});
            if (!report.host_binaries.hermes) try stdout.writeAll("    → Fix: orca plugin install hermes --yes\n");
            try stdout.print("  plugin directory: {s}\n", .{if (report.plugin_directories.hermes) "present" else "not yet created"});
            if (!report.plugin_directories.hermes) try stdout.writeAll("    → Fix: orca plugin install hermes --yes\n");
            try stdout.print("  repo plugin.yaml: {s}\n", .{if (report.hermes_paths.repo_manifest_exists) "exists" else "not found"});
            if (!report.hermes_paths.repo_manifest_exists) try stdout.writeAll("    → Fix: orca plugin install hermes --yes\n");
            try stdout.print("  repo __init__.py: {s}\n", .{if (report.hermes_paths.repo_source_exists) "exists" else "not found"});
            if (!report.hermes_paths.repo_source_exists) try stdout.writeAll("    → Fix: orca plugin install hermes --yes\n");
            try stdout.print("  user plugin path (~/.hermes/plugins/orca/plugin.yaml): {s}\n", .{if (report.hermes_paths.user_manifest_exists) "exists" else "not found"});
            if (!report.hermes_paths.user_manifest_exists) try stdout.writeAll("    → Fix: orca plugin install hermes --yes\n");
            try stdout.print("  config references plugin: {s}\n", .{if (report.hermes_paths.config_references_plugin) "yes" else "unknown/no"});
            if (!report.hermes_paths.config_references_plugin) try stdout.writeAll("    → Fix: orca plugin install hermes --yes\n");
            try stdout.print("  hook smoke test (pre_tool_call): {s}\n", .{if (report.hermes_hook_smoke_passed) "passed" else "FAILED"});
            if (!report.hermes_hook_smoke_passed) try stdout.writeAll("    → Fix: upgrade Orca (./scripts/install-orca-plugin.sh hermes) or set ORCA_BIN to a build with Hermes host support\n");
            try stdout.writeAll("  install: use 'orca plugin install hermes --dry-run' to preview\n");
            try stdout.writeAll("  note: Hermes hooks are additive; strongest protection remains 'orca run -- hermes'\n");
        },
    }

    try stdout.writeAll("\n");
}

// ---------------------------------------------------------------------------
// doctor JSON output
// ---------------------------------------------------------------------------

fn writeDoctorJson(stdout: anytype, report: PluginDoctorReport, target: DoctorTarget) !void {
    try stdout.writeAll("{\n");
    try stdout.writeAll("  \"orca_version\": ");
    try writeJsonString(stdout, report.orca_version);
    try stdout.writeAll(",\n");

    try stdout.writeAll("  \"orca_binary_path\": ");
    if (report.orca_binary_path) |path| {
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
    try stdout.print("    \"opencode\": {s},\n", .{if (report.plugin_directories.opencode) "true" else "false"});
    try stdout.print("    \"openclaw\": {s},\n", .{if (report.plugin_directories.openclaw) "true" else "false"});
    try stdout.print("    \"hermes\": {s},\n", .{if (report.plugin_directories.hermes) "true" else "false"});
    try stdout.print("    \"common\": {s}\n", .{if (report.plugin_directories.common) "true" else "false"});
    try stdout.writeAll("  },\n");

    try stdout.writeAll("  \"host_binaries\": {\n");
    try stdout.print("    \"codex\": {s},\n", .{if (report.host_binaries.codex) "true" else "false"});
    try stdout.print("    \"claude\": {s},\n", .{if (report.host_binaries.claude) "true" else "false"});
    try stdout.print("    \"opencode\": {s},\n", .{if (report.host_binaries.opencode) "true" else "false"});
    try stdout.print("    \"openclaw\": {s},\n", .{if (report.host_binaries.openclaw) "true" else "false"});
    try stdout.print("    \"hermes\": {s}\n", .{if (report.host_binaries.hermes) "true" else "false"});
    try stdout.writeAll("  },\n");

    try stdout.writeAll("  \"opencode_paths\": {\n");
    try stdout.print("    \"project_plugin_exists\": {s},\n", .{if (report.opencode_paths.project_plugin_exists) "true" else "false"});
    try stdout.print("    \"global_plugin_exists\": {s},\n", .{if (report.opencode_paths.global_plugin_exists) "true" else "false"});
    try stdout.print("    \"config_references_plugin\": {s}\n", .{if (report.opencode_paths.config_references_plugin) "true" else "false"});
    try stdout.writeAll("  },\n");

    try stdout.writeAll("  \"openclaw_paths\": {\n");
    try stdout.print("    \"plugin_manifest_exists\": {s},\n", .{if (report.openclaw_paths.plugin_manifest_exists) "true" else "false"});
    try stdout.print("    \"package_json_exists\": {s},\n", .{if (report.openclaw_paths.package_json_exists) "true" else "false"});
    try stdout.print("    \"source_exists\": {s}\n", .{if (report.openclaw_paths.source_exists) "true" else "false"});
    try stdout.writeAll("  },\n");

    try stdout.writeAll("  \"hermes_paths\": {\n");
    try stdout.print("    \"repo_manifest_exists\": {s},\n", .{if (report.hermes_paths.repo_manifest_exists) "true" else "false"});
    try stdout.print("    \"repo_source_exists\": {s},\n", .{if (report.hermes_paths.repo_source_exists) "true" else "false"});
    try stdout.print("    \"user_manifest_exists\": {s},\n", .{if (report.hermes_paths.user_manifest_exists) "true" else "false"});
    try stdout.print("    \"user_source_exists\": {s},\n", .{if (report.hermes_paths.user_source_exists) "true" else "false"});
    try stdout.print("    \"config_references_plugin\": {s}\n", .{if (report.hermes_paths.config_references_plugin) "true" else "false"});
    try stdout.writeAll("  },\n");

    try stdout.writeAll("  \"hermes_hook_smoke_passed\": ");
    try stdout.writeAll(if (report.hermes_hook_smoke_passed) "true" else "false");
    try stdout.writeAll(",\n");

    try stdout.writeAll("  \"marketplace\": {\n");
    try stdout.print("    \"codex_marketplace\": {s},\n", .{if (report.marketplace.codex_marketplace) "true" else "false"});
    try stdout.print("    \"claude_marketplace\": {s},\n", .{if (report.marketplace.claude_marketplace) "true" else "false"});
    try stdout.print("    \"codex_plugin_manifest\": {s},\n", .{if (report.marketplace.codex_plugin_manifest) "true" else "false"});
    try stdout.print("    \"claude_plugin_manifest\": {s}\n", .{if (report.marketplace.claude_plugin_manifest) "true" else "false"});
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

const ManifestTarget = enum { codex, claude, opencode, openclaw, hermes, all };

fn manifestCommand(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var target: ManifestTarget = .all;
    var json_mode = false;

    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try stdout.writeAll(
                \\Usage:
                \\  orca plugin manifest codex
                \\  orca plugin manifest claude
                \\  orca plugin manifest opencode
                \\  orca plugin manifest openclaw
                \\  orca plugin manifest hermes
                \\  orca plugin manifest all
                \\  orca plugin manifest <target> [--json]
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
        if (std.mem.eql(u8, arg, "opencode")) {
            target = .opencode;
            continue;
        }
        if (std.mem.eql(u8, arg, "openclaw")) {
            target = .openclaw;
            continue;
        }
        if (std.mem.eql(u8, arg, "hermes") or std.mem.eql(u8, arg, "hermess")) {
            target = .hermes;
            continue;
        }
        if (std.mem.eql(u8, arg, "all")) {
            target = .all;
            continue;
        }
        try stderr.print("orca plugin manifest: unknown option '{s}'.\n", .{arg});
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
            const marketplace_path = ".agents/plugins/marketplace.json";
            const marketplace_exists = fileExistsAbsolute(marketplace_path);
            try stdout.writeAll("Codex plugin manifest:\n");
            try stdout.print("  expected path: {s}\n", .{path});
            try stdout.print("  status: {s}\n", .{if (exists) "exists" else "missing"});
            try stdout.print("  marketplace: {s} ({s})\n", .{ marketplace_path, if (marketplace_exists) "exists" else "missing" });
            if (exists) {
                try stdout.writeAll("  note: validation of manifest shape is deferred to host-specific checks\n");
            }
        },
        .claude => {
            const path = "integrations/claude-code-plugin/.claude-plugin/plugin.json";
            const exists = fileExistsAbsolute(path);
            const marketplace_path = ".claude-plugin/marketplace.json";
            const marketplace_exists = fileExistsAbsolute(marketplace_path);
            try stdout.writeAll("Claude Code plugin manifest:\n");
            try stdout.print("  expected path: {s}\n", .{path});
            try stdout.print("  status: {s}\n", .{if (exists) "exists" else "missing"});
            try stdout.print("  marketplace: {s} ({s})\n", .{ marketplace_path, if (marketplace_exists) "exists" else "missing" });
            if (exists) {
                try stdout.writeAll("  note: validation of manifest shape is deferred to host-specific checks\n");
            }
        },
        .opencode => {
            const path = "integrations/opencode-plugin/orca.ts";
            const exists = fileExistsAbsolute(path);
            try stdout.writeAll("OpenCode plugin manifest:\n");
            try stdout.print("  expected path: {s}\n", .{path});
            try stdout.print("  status: {s}\n", .{if (exists) "exists" else "missing"});
            try stdout.writeAll("  note: OpenCode uses TypeScript plugins, not a JSON manifest\n");
        },
        .openclaw => {
            const manifest_path = "integrations/openclaw-plugin/openclaw.plugin.json";
            const manifest_exists = fileExistsAbsolute(manifest_path);
            const pkg_path = "integrations/openclaw-plugin/package.json";
            const pkg_exists = fileExistsAbsolute(pkg_path);
            try stdout.writeAll("OpenClaw plugin manifest:\n");
            try stdout.print("  expected manifest path: {s}\n", .{manifest_path});
            try stdout.print("  manifest status: {s}\n", .{if (manifest_exists) "exists" else "missing"});
            try stdout.print("  package.json: {s} ({s})\n", .{ pkg_path, if (pkg_exists) "exists" else "missing" });
            if (manifest_exists) {
                try stdout.writeAll("  note: validation of manifest shape is deferred to host-specific checks\n");
            }
        },
        .hermes => {
            const manifest_path = "integrations/hermes-plugin/plugin.yaml";
            const manifest_exists = fileExistsAbsolute(manifest_path);
            const source_path = "integrations/hermes-plugin/__init__.py";
            const source_exists = fileExistsAbsolute(source_path);
            try stdout.writeAll("Hermes plugin manifest:\n");
            try stdout.print("  expected manifest path: {s}\n", .{manifest_path});
            try stdout.print("  manifest status: {s}\n", .{if (manifest_exists) "exists" else "missing"});
            try stdout.print("  source: {s} ({s})\n", .{ source_path, if (source_exists) "exists" else "missing" });
            try stdout.writeAll("  user install path: ~/.hermes/plugins/orca/\n");
        },
        .all => {
            try stdout.writeAll("Plugin manifests:\n");
            const codex_path = "integrations/codex-plugin/.codex-plugin/plugin.json";
            const claude_path = "integrations/claude-code-plugin/.claude-plugin/plugin.json";
            const opencode_path = "integrations/opencode-plugin/orca.ts";
            const openclaw_path = "integrations/openclaw-plugin/openclaw.plugin.json";
            const hermes_path = "integrations/hermes-plugin/plugin.yaml";
            const codex_marketplace = ".agents/plugins/marketplace.json";
            const claude_marketplace = ".claude-plugin/marketplace.json";
            try stdout.print("  codex:    {s} ({s})\n", .{ codex_path, if (fileExistsAbsolute(codex_path)) "exists" else "missing" });
            try stdout.print("  claude:   {s} ({s})\n", .{ claude_path, if (fileExistsAbsolute(claude_path)) "exists" else "missing" });
            try stdout.print("  opencode: {s} ({s})\n", .{ opencode_path, if (fileExistsAbsolute(opencode_path)) "exists" else "missing" });
            try stdout.print("  openclaw: {s} ({s})\n", .{ openclaw_path, if (fileExistsAbsolute(openclaw_path)) "exists" else "missing" });
            try stdout.print("  hermes:   {s} ({s})\n", .{ hermes_path, if (fileExistsAbsolute(hermes_path)) "exists" else "missing" });
            try stdout.writeAll("\nMarketplace files:\n");
            try stdout.print("  codex:    {s} ({s})\n", .{ codex_marketplace, if (fileExistsAbsolute(codex_marketplace)) "exists" else "missing" });
            try stdout.print("  claude:   {s} ({s})\n", .{ claude_marketplace, if (fileExistsAbsolute(claude_marketplace)) "exists" else "missing" });
        },
    }
}

fn writeManifestJson(stdout: anytype, target: ManifestTarget) !void {
    try stdout.writeAll("{\n");
    switch (target) {
        .codex => {
            const path = "integrations/codex-plugin/.codex-plugin/plugin.json";
            const marketplace_path = ".agents/plugins/marketplace.json";
            try stdout.writeAll("  \"codex\": {\n");
            try stdout.print("    \"path\": ", .{});
            try writeJsonString(stdout, path);
            try stdout.writeAll(",\n");
            try stdout.print("    \"status\": \"{s}\",\n", .{if (fileExistsAbsolute(path)) "exists" else "missing"});
            try stdout.print("    \"marketplace_path\": ", .{});
            try writeJsonString(stdout, marketplace_path);
            try stdout.writeAll(",\n");
            try stdout.print("    \"marketplace_status\": \"{s}\"\n", .{if (fileExistsAbsolute(marketplace_path)) "exists" else "missing"});
            try stdout.writeAll("  }\n");
        },
        .claude => {
            const path = "integrations/claude-code-plugin/.claude-plugin/plugin.json";
            const marketplace_path = ".claude-plugin/marketplace.json";
            try stdout.writeAll("  \"claude\": {\n");
            try stdout.print("    \"path\": ", .{});
            try writeJsonString(stdout, path);
            try stdout.writeAll(",\n");
            try stdout.print("    \"status\": \"{s}\",\n", .{if (fileExistsAbsolute(path)) "exists" else "missing"});
            try stdout.print("    \"marketplace_path\": ", .{});
            try writeJsonString(stdout, marketplace_path);
            try stdout.writeAll(",\n");
            try stdout.print("    \"marketplace_status\": \"{s}\"\n", .{if (fileExistsAbsolute(marketplace_path)) "exists" else "missing"});
            try stdout.writeAll("  }\n");
        },
        .opencode => {
            const path = "integrations/opencode-plugin/orca.ts";
            try stdout.writeAll("  \"opencode\": {\n");
            try stdout.print("    \"path\": ", .{});
            try writeJsonString(stdout, path);
            try stdout.writeAll(",\n");
            try stdout.print("    \"status\": \"{s}\"\n", .{if (fileExistsAbsolute(path)) "exists" else "missing"});
            try stdout.writeAll("  }\n");
        },
        .openclaw => {
            const manifest_path = "integrations/openclaw-plugin/openclaw.plugin.json";
            const pkg_path = "integrations/openclaw-plugin/package.json";
            try stdout.writeAll("  \"openclaw\": {\n");
            try stdout.print("    \"manifest_path\": ", .{});
            try writeJsonString(stdout, manifest_path);
            try stdout.writeAll(",\n");
            try stdout.print("    \"manifest_status\": \"{s}\",\n", .{if (fileExistsAbsolute(manifest_path)) "exists" else "missing"});
            try stdout.print("    \"package_path\": ", .{});
            try writeJsonString(stdout, pkg_path);
            try stdout.writeAll(",\n");
            try stdout.print("    \"package_status\": \"{s}\"\n", .{if (fileExistsAbsolute(pkg_path)) "exists" else "missing"});
            try stdout.writeAll("  }\n");
        },
        .hermes => {
            const manifest_path = "integrations/hermes-plugin/plugin.yaml";
            const source_path = "integrations/hermes-plugin/__init__.py";
            try stdout.writeAll("  \"hermes\": {\n");
            try stdout.print("    \"manifest_path\": ", .{});
            try writeJsonString(stdout, manifest_path);
            try stdout.writeAll(",\n");
            try stdout.print("    \"manifest_status\": \"{s}\",\n", .{if (fileExistsAbsolute(manifest_path)) "exists" else "missing"});
            try stdout.print("    \"source_path\": ", .{});
            try writeJsonString(stdout, source_path);
            try stdout.writeAll(",\n");
            try stdout.print("    \"source_status\": \"{s}\"\n", .{if (fileExistsAbsolute(source_path)) "exists" else "missing"});
            try stdout.writeAll("  }\n");
        },
        .all => {
            const codex_path = "integrations/codex-plugin/.codex-plugin/plugin.json";
            const claude_path = "integrations/claude-code-plugin/.claude-plugin/plugin.json";
            const opencode_path = "integrations/opencode-plugin/orca.ts";
            const openclaw_manifest_path = "integrations/openclaw-plugin/openclaw.plugin.json";
            const hermes_manifest_path = "integrations/hermes-plugin/plugin.yaml";
            const codex_marketplace = ".agents/plugins/marketplace.json";
            const claude_marketplace = ".claude-plugin/marketplace.json";
            try stdout.writeAll("  \"codex\": {\n");
            try stdout.print("    \"path\": ", .{});
            try writeJsonString(stdout, codex_path);
            try stdout.writeAll(",\n");
            try stdout.print("    \"status\": \"{s}\",\n", .{if (fileExistsAbsolute(codex_path)) "exists" else "missing"});
            try stdout.print("    \"marketplace_path\": ", .{});
            try writeJsonString(stdout, codex_marketplace);
            try stdout.writeAll(",\n");
            try stdout.print("    \"marketplace_status\": \"{s}\"\n", .{if (fileExistsAbsolute(codex_marketplace)) "exists" else "missing"});
            try stdout.writeAll("  },\n");
            try stdout.writeAll("  \"claude\": {\n");
            try stdout.print("    \"path\": ", .{});
            try writeJsonString(stdout, claude_path);
            try stdout.writeAll(",\n");
            try stdout.print("    \"status\": \"{s}\",\n", .{if (fileExistsAbsolute(claude_path)) "exists" else "missing"});
            try stdout.print("    \"marketplace_path\": ", .{});
            try writeJsonString(stdout, claude_marketplace);
            try stdout.writeAll(",\n");
            try stdout.print("    \"marketplace_status\": \"{s}\"\n", .{if (fileExistsAbsolute(claude_marketplace)) "exists" else "missing"});
            try stdout.writeAll("  },\n");
            try stdout.writeAll("  \"opencode\": {\n");
            try stdout.print("    \"path\": ", .{});
            try writeJsonString(stdout, opencode_path);
            try stdout.writeAll(",\n");
            try stdout.print("    \"status\": \"{s}\"\n", .{if (fileExistsAbsolute(opencode_path)) "exists" else "missing"});
            try stdout.writeAll("  },\n");
            try stdout.writeAll("  \"openclaw\": {\n");
            try stdout.print("    \"manifest_path\": ", .{});
            try writeJsonString(stdout, openclaw_manifest_path);
            try stdout.writeAll(",\n");
            try stdout.print("    \"manifest_status\": \"{s}\"\n", .{if (fileExistsAbsolute(openclaw_manifest_path)) "exists" else "missing"});
            try stdout.writeAll("  },\n");
            try stdout.writeAll("  \"hermes\": {\n");
            try stdout.print("    \"manifest_path\": ", .{});
            try writeJsonString(stdout, hermes_manifest_path);
            try stdout.writeAll(",\n");
            try stdout.print("    \"manifest_status\": \"{s}\"\n", .{if (fileExistsAbsolute(hermes_manifest_path)) "exists" else "missing"});
            try stdout.writeAll("  }\n");
        },
    }
    try stdout.writeAll("}\n");
}

// ---------------------------------------------------------------------------
// install
// ---------------------------------------------------------------------------

const InstallTarget = enum { codex, claude, opencode, openclaw, hermes, all };
const InstallScope = enum { project, global };

fn installCommand(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var target: InstallTarget = .all;
    var dry_run = true; // default to safe dry-run
    var dry_run_explicit = false;
    var custom_path: ?[]const u8 = null;
    var yes = false;
    var all_detected = false;
    var scope: InstallScope = .project;

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        const arg = argv[index];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try stdout.writeAll(
                \\Usage:
                \\  orca plugin install codex [--dry-run]
                \\  orca plugin install claude [--dry-run]
                \\  orca plugin install opencode [--dry-run]
                \\  orca plugin install openclaw [--dry-run]
                \\  orca plugin install hermes [--dry-run]
                \\  orca plugin install all [--dry-run]
                \\  orca plugin install all --all-detected [--dry-run|--yes]
                \\  orca plugin install codex --path <plugin-path> [--dry-run]
                \\  orca plugin install claude --path <plugin-path> [--dry-run]
                \\  orca plugin install opencode --path <plugin-path> [--dry-run]
                \\  orca plugin install openclaw --path <plugin-path> [--dry-run]
                \\  orca plugin install hermes --path <plugin-path> [--dry-run]
                \\  orca plugin install opencode --scope project|global [--dry-run|--yes]
                \\  orca plugin install <target> [--yes]
                \\  
                \\Options:
                \\  --dry-run       Preview changes without mutating host config (default)
                \\  --all-detected  Only install for hosts found in PATH
                \\  --path          Use a custom plugin path instead of the default
                \\  --scope         OpenCode install scope: project|global (default: project)
                \\  --yes           Skip confirmation prompt (use with care)
                \\
            );
            return exit_codes.success;
        }
        if (std.mem.eql(u8, arg, "--dry-run")) {
            dry_run = true;
            dry_run_explicit = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--yes")) {
            yes = true;
            if (!dry_run_explicit) dry_run = false;
            continue;
        }
        if (std.mem.eql(u8, arg, "--all-detected")) {
            all_detected = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--path")) {
            if (index + 1 >= argv.len) {
                try stderr.writeAll("orca plugin install: --path requires a value.\n");
                return exit_codes.usage;
            }
            custom_path = argv[index + 1];
            index += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--scope")) {
            if (index + 1 >= argv.len) {
                try stderr.writeAll("orca plugin install: --scope requires a value.\n");
                return exit_codes.usage;
            }
            const value = argv[index + 1];
            if (std.mem.eql(u8, value, "project")) {
                scope = .project;
            } else if (std.mem.eql(u8, value, "global")) {
                scope = .global;
            } else {
                try stderr.print("orca plugin install: invalid --scope '{s}' (expected project|global).\n", .{value});
                return exit_codes.usage;
            }
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
        if (std.mem.eql(u8, arg, "opencode")) {
            target = .opencode;
            continue;
        }
        if (std.mem.eql(u8, arg, "openclaw")) {
            target = .openclaw;
            continue;
        }
        if (std.mem.eql(u8, arg, "hermes") or std.mem.eql(u8, arg, "hermess")) {
            target = .hermes;
            continue;
        }
        if (std.mem.eql(u8, arg, "all")) {
            target = .all;
            continue;
        }
        try stderr.print("orca plugin install: unknown option '{s}'.\n", .{arg});
        return exit_codes.usage;
    }

    if (!dry_run_explicit and !yes) {
        const stdin = std.fs.File.stdin();
        if (stdin.isTty()) {
            const host_label = if (target == .all and all_detected) "all detected" else if (target == .all) "all" else @tagName(target);
            try stdout.print("Install {s} plugin? [Y/n] ", .{host_label});
            var buf: [8]u8 = undefined;
            const n = try stdin.read(&buf);
            const answer = if (n > 0) std.mem.trimRight(u8, buf[0..n], "\r\n") else "";
            if (answer.len > 0 and (answer[0] == 'n' or answer[0] == 'N')) {
                try stdout.writeAll("canceled\n");
                return exit_codes.success;
            }
            dry_run = false;
        } else {
            try stderr.writeAll("orca plugin install: actual installation requires --yes or --dry-run to preview.\n");
            return exit_codes.usage;
        }
    }

    try stdout.writeAll("Orca Plugin Install\n\n");

    var detected_targets: [5]InstallTarget = undefined;
    var detected_count: usize = 0;

    const targets = switch (target) {
        .codex => &[_]InstallTarget{.codex},
        .claude => &[_]InstallTarget{.claude},
        .opencode => &[_]InstallTarget{.opencode},
        .openclaw => &[_]InstallTarget{.openclaw},
        .hermes => &[_]InstallTarget{.hermes},
        .all => if (all_detected) blk: {
            if (binaryInPath(allocator, "codex")) { detected_targets[detected_count] = .codex; detected_count += 1; }
            if (binaryInPath(allocator, "claude")) { detected_targets[detected_count] = .claude; detected_count += 1; }
            if (binaryInPath(allocator, "opencode")) { detected_targets[detected_count] = .opencode; detected_count += 1; }
            if (binaryInPath(allocator, "openclaw")) { detected_targets[detected_count] = .openclaw; detected_count += 1; }
            if (binaryInPath(allocator, "hermes")) { detected_targets[detected_count] = .hermes; detected_count += 1; }
            break :blk detected_targets[0..detected_count];
        } else &[_]InstallTarget{ .codex, .claude, .opencode, .openclaw, .hermes },
    };

    for (targets) |t| {
        try stdout.print("Target: {s}\n", .{@tagName(t)});
        try stdout.print("  mode: {s}\n", .{if (dry_run) "dry-run (no changes made)" else "install"});

        if (custom_path) |p| {
            try stdout.print("  custom path: {s}\n", .{p});
        }
        if (t == .opencode) {
            try stdout.print("  scope: {s}\n", .{@tagName(scope)});
        }

        const plugin_dir = if (custom_path) |path| try allocator.dupe(u8, path) else switch (t) {
            .codex => try resolveBundledPath(allocator, "integrations/codex-plugin"),
            .claude => try resolveBundledPath(allocator, "integrations/claude-code-plugin"),
            .opencode => try resolveBundledPath(allocator, "integrations/opencode-plugin"),
            .openclaw => try resolveBundledPath(allocator, "integrations/openclaw-plugin"),
            .hermes => try resolveBundledPath(allocator, "integrations/hermes-plugin"),
            .all => unreachable,
        };
        defer allocator.free(plugin_dir);

        if (!dirExists(plugin_dir)) {
            try stdout.print("  plugin directory: missing ({s})\n", .{plugin_dir});
            try stdout.writeAll("  next step: create the plugin directory and manifest before installing\n");
            if (!dry_run) return exit_codes.general;
        } else {
            try stdout.print("  plugin directory: found ({s})\n", .{plugin_dir});

            if (t == .opencode) {
                // OpenCode-specific install guidance
                const source_path = try std.fs.path.join(allocator, &.{ plugin_dir, "orca.ts" });
                defer allocator.free(source_path);
                const destination_path = try resolveOpenCodeDestination(allocator, scope);
                defer allocator.free(destination_path);

                try stdout.writeAll("  install paths for OpenCode:\n");
                try stdout.writeAll("    project: .opencode/plugins/orca.ts\n");
                try stdout.writeAll("    global:  ~/.config/opencode/plugins/orca.ts\n");
                if (dry_run) {
                    try stdout.writeAll("  action: no changes made (dry-run)\n");
                    try stdout.print("  next step: copy {s} to {s}\n", .{ source_path, destination_path });
                } else {
                    if (!fileExistsAbsolute(source_path)) {
                        try stdout.print("  action: failed (source missing: {s})\n", .{source_path});
                        return exit_codes.general;
                    }
                    const installed = installFileIfSafe(allocator, source_path, destination_path) catch |err| switch (err) {
                        error.RefusingToOverwriteDifferentFile => {
                            try stdout.print("  action: failed (destination exists and differs: {s})\n", .{destination_path});
                            return exit_codes.general;
                        },
                        else => return err,
                    };
                    if (installed) {
                        try stdout.print("  action: installed to {s}\n", .{destination_path});
                    } else {
                        try stdout.print("  action: already up-to-date at {s}\n", .{destination_path});
                    }
                }
            } else if (t == .openclaw) {
                // OpenClaw-specific install guidance
                const install_command = try std.fmt.allocPrint(allocator, "openclaw plugins install {s}", .{plugin_dir});
                defer allocator.free(install_command);
                try stdout.writeAll("  install paths for OpenClaw:\n");
                try stdout.writeAll("    local:   openclaw plugins install ./integrations/openclaw-plugin\n");
                try stdout.writeAll("    npm:     openclaw plugins install npm:orca-openclaw-plugin (published)\n");
                try stdout.writeAll("    clawhub: openclaw plugins install clawhub:orca-openclaw-plugin (published)\n");
                if (dry_run) {
                    try stdout.writeAll("  action: no changes made (dry-run)\n");
                    try stdout.print("  next step: run '{s}' if OpenClaw is installed\n", .{install_command});
                } else {
                    if (!binaryInPath(allocator, "openclaw")) {
                        try stdout.writeAll("  action: failed (openclaw binary not found in PATH)\n");
                        return exit_codes.general;
                    }
                    const status = try runOpenClawInstall(allocator, plugin_dir);
                    if (status == 0) {
                        try stdout.writeAll("  action: installed via openclaw host command\n");
                    } else {
                        try stdout.print("  action: failed (openclaw exit code: {d})\n", .{status});
                        return exit_codes.child_failure;
                    }
                }
            } else if (t == .hermes) {
                const destination_path = try hermesUserPluginRoot(allocator);
                defer allocator.free(destination_path);
                const manifest_source = try std.fs.path.join(allocator, &.{ plugin_dir, "plugin.yaml" });
                defer allocator.free(manifest_source);
                const source_source = try std.fs.path.join(allocator, &.{ plugin_dir, "__init__.py" });
                defer allocator.free(source_source);
                const manifest_destination = try std.fs.path.join(allocator, &.{ destination_path, "plugin.yaml" });
                defer allocator.free(manifest_destination);
                const source_destination = try std.fs.path.join(allocator, &.{ destination_path, "__init__.py" });
                defer allocator.free(source_destination);

                try stdout.writeAll("  install paths for Hermes:\n");
                try stdout.print("    user: {s}\n", .{destination_path});
                try stdout.writeAll("    enable: hermes plugins enable orca\n");
                if (dry_run) {
                    try stdout.writeAll("  action: no changes made (dry-run)\n");
                    try stdout.print("  next step: copy {s} to {s}\n", .{ plugin_dir, destination_path });
                } else {
                    if (!fileExistsAbsolute(manifest_source) or !fileExistsAbsolute(source_source)) {
                        try stdout.writeAll("  action: failed (Hermes plugin files missing)\n");
                        return exit_codes.general;
                    }
                    const manifest_installed = installFileIfSafe(allocator, manifest_source, manifest_destination) catch |err| switch (err) {
                        error.RefusingToOverwriteDifferentFile => {
                            try stdout.print("  action: failed (destination exists and differs: {s})\n", .{manifest_destination});
                            return exit_codes.general;
                        },
                        else => return err,
                    };
                    const source_installed = installFileIfSafe(allocator, source_source, source_destination) catch |err| switch (err) {
                        error.RefusingToOverwriteDifferentFile => {
                            try stdout.print("  action: failed (destination exists and differs: {s})\n", .{source_destination});
                            return exit_codes.general;
                        },
                        else => return err,
                    };
                    if (manifest_installed or source_installed) {
                        try stdout.print("  action: installed to {s}\n", .{destination_path});
                    } else {
                        try stdout.print("  action: already up-to-date at {s}\n", .{destination_path});
                    }
                    if (binaryInPath(allocator, "hermes")) {
                        const status = try runHermesEnable(allocator);
                        if (status == 0) {
                            try stdout.writeAll("  enable: completed via hermes plugins enable orca\n");
                        } else {
                            try stdout.print("  enable: failed (hermes exit code: {d})\n", .{status});
                            try writeHermesEnableHelper(allocator, destination_path);
                        }
                    } else {
                        try stdout.writeAll("  enable: hermes binary not found in PATH\n");
                        try writeHermesEnableHelper(allocator, destination_path);
                    }
                }
            } else {
                if (dry_run) {
                    try stdout.writeAll("  action: no changes made (dry-run)\n");
                    try stdout.writeAll("  next step: host install command is not yet known; manual integration required\n");
                } else {
                    try stdout.writeAll("  action: failed (host plugin installation is not yet implemented)\n");
                    try stdout.writeAll("  note: use --dry-run for integration guidance until this host installer is implemented\n");
                    return exit_codes.unsupported;
                }
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
                \\  orca plugin mcp-server [--help]
                \\
                \\Status: limited / deferred
                \\  The Orca MCP plugin server is planned but not yet active.
                \\  When implemented, it will expose safe read-only Orca capabilities as MCP tools:
                \\    - orca_doctor
                \\    - orca_plugin_doctor
                \\    - orca_policy_check
                \\    - orca_policy_explain
                \\    - orca_redteam
                \\    - orca_replay_summary
                \\    - orca_capabilities
                \\  The following will NOT be exposed by default:
                \\    - arbitrary shell execution
                \\    - arbitrary file writes
                \\    - raw audit log dumping without redaction
                \\    - credential access
                \\    - policy mutation without explicit approval
                \\
            );
            return exit_codes.success;
        }
        try stderr.print("orca plugin mcp-server: unknown option '{s}'.\n", .{arg});
        return exit_codes.usage;
    }

    try stdout.writeAll("Orca Plugin MCP Server\n\n");
    try stdout.writeAll("Status: limited / deferred\n");
    try stdout.writeAll("  The Orca MCP plugin server is planned but not yet active.\n");
    try stdout.writeAll("  It does not listen on any port or transport.\n\n");
    try stdout.writeAll("Planned safe tools (when implemented):\n");
    try stdout.writeAll("  - orca_doctor\n");
    try stdout.writeAll("  - orca_plugin_doctor\n");
    try stdout.writeAll("  - orca_policy_check\n");
    try stdout.writeAll("  - orca_policy_explain\n");
    try stdout.writeAll("  - orca_redteam\n");
    try stdout.writeAll("  - orca_replay_summary\n");
    try stdout.writeAll("  - orca_capabilities\n");
    try stdout.writeAll("\n");
    try stdout.writeAll("Blocked by default (not exposed):\n");
    try stdout.writeAll("  - arbitrary shell execution\n");
    try stdout.writeAll("  - arbitrary file writes\n");
    try stdout.writeAll("  - raw audit log dumping without redaction\n");
    try stdout.writeAll("  - credential access\n");
    try stdout.writeAll("  - policy mutation without explicit approval\n\n");
    try stdout.writeAll("Use 'orca plugin mcp-server --help' for full details.\n");
    return exit_codes.success;
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

pub fn fileExistsAbsolute(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

pub fn pluginDirExists(allocator: std.mem.Allocator, relative_path: []const u8) bool {
    const resolved = resolveBundledPath(allocator, relative_path) catch return false;
    defer allocator.free(resolved);
    return dirExists(resolved);
}

pub fn resolveBundledPath(allocator: std.mem.Allocator, relative_path: []const u8) ![]u8 {
    if (dirExists(relative_path) or fileExistsAbsolute(relative_path)) {
        return allocator.dupe(u8, relative_path);
    }

    const resource_root = std.process.getEnvVarOwned(allocator, "ORCA_RESOURCE_ROOT") catch
        std.process.getEnvVarOwned(allocator, "ORCA_RESOURCE_ROOT") catch null;
    if (resource_root) |root| {
        defer allocator.free(root);
        const candidate = try std.fs.path.join(allocator, &.{ root, relative_path });
        if (dirExists(candidate) or fileExistsAbsolute(candidate)) return candidate;
        allocator.free(candidate);
    }

    return allocator.dupe(u8, relative_path);
}

pub fn resolveOpenCodeDestination(allocator: std.mem.Allocator, scope: InstallScope) ![]u8 {
    return switch (scope) {
        .project => std.fs.path.join(allocator, &.{ ".opencode", "plugins", "orca.ts" }),
        .global => blk: {
            const home = try std.process.getEnvVarOwned(allocator, "HOME");
            defer allocator.free(home);
            break :blk std.fs.path.join(allocator, &.{ home, ".config", "opencode", "plugins", "orca.ts" });
        },
    };
}

pub fn hermesUserPluginRoot(allocator: std.mem.Allocator) ![]u8 {
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch return std.fs.path.join(allocator, &.{ "~", ".hermes", "plugins", "orca" });
    defer allocator.free(home);
    return std.fs.path.join(allocator, &.{ home, ".hermes", "plugins", "orca" });
}

pub fn hermesConfigPath(allocator: std.mem.Allocator) ![]u8 {
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch return std.fs.path.join(allocator, &.{ "~", ".hermes", "config.yaml" });
    defer allocator.free(home);
    return std.fs.path.join(allocator, &.{ home, ".hermes", "config.yaml" });
}

pub fn installFileIfSafe(allocator: std.mem.Allocator, source_path: []const u8, destination_path: []const u8) !bool {
    if (fileExistsAbsolute(destination_path)) {
        const same = try filesEqual(allocator, source_path, destination_path);
        if (same) return false;
        return error.RefusingToOverwriteDifferentFile;
    }

    const parent = std.fs.path.dirname(destination_path) orelse return error.InvalidPath;
    try std.fs.cwd().makePath(parent);

    const source = try std.fs.cwd().readFileAlloc(allocator, source_path, 1024 * 1024);
    defer allocator.free(source);
    try std.fs.cwd().writeFile(.{ .sub_path = destination_path, .data = source, .flags = .{ .exclusive = true } });
    return true;
}

pub fn filesEqual(allocator: std.mem.Allocator, lhs_path: []const u8, rhs_path: []const u8) !bool {
    const lhs = try std.fs.cwd().readFileAlloc(allocator, lhs_path, 1024 * 1024);
    defer allocator.free(lhs);
    const rhs = try std.fs.cwd().readFileAlloc(allocator, rhs_path, 1024 * 1024);
    defer allocator.free(rhs);
    return std.mem.eql(u8, lhs, rhs);
}

pub fn runOpenClawInstall(allocator: std.mem.Allocator, plugin_dir: []const u8) !u8 {
    const argv = [_][]const u8{ "openclaw", "plugins", "install", plugin_dir };
    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    const term = try child.spawnAndWait();
    return switch (term) {
        .Exited => |code| @as(u8, @intCast(@min(code, 255))),
        else => 255,
    };
}

pub fn runHermesEnable(allocator: std.mem.Allocator) !u8 {
    const argv = [_][]const u8{ "hermes", "plugins", "enable", "orca" };
    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    const term = try child.spawnAndWait();
    return switch (term) {
        .Exited => |code| @as(u8, @intCast(@min(code, 255))),
        else => 255,
    };
}

pub fn fileContains(allocator: std.mem.Allocator, path: []const u8, needle: []const u8) bool {
    const content = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch return false;
    defer allocator.free(content);
    return std.mem.indexOf(u8, content, needle) != null;
}

pub fn dirExists(path: []const u8) bool {
    var dir = std.fs.cwd().openDir(path, .{}) catch return false;
    dir.close();
    return true;
}

pub fn hasPath(root: []const u8, relative: []const u8) bool {
    const allocator = std.heap.page_allocator;
    const path = std.fs.path.join(allocator, &.{ root, relative }) catch return false;
    defer allocator.free(path);
    return fileExistsAbsolute(path);
}

pub fn binaryInPath(allocator: std.mem.Allocator, binary_name: []const u8) bool {
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

pub fn writeJsonString(writer: anytype, value: []const u8) !void {
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
// Smoke test
// ---------------------------------------------------------------------------

pub const SmokeResult = struct {
    passed: bool,
};

pub fn smokeTestHook(allocator: std.mem.Allocator, host: []const u8, event: []const u8, fixture_path: []const u8, expected_decision: []const u8) !SmokeResult {
    const self_exe = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(self_exe);
    const argv = &[_][]const u8{ self_exe, "hook", host, event };
    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    try child.spawn();

    const fixture = try std.fs.cwd().readFileAlloc(allocator, fixture_path, 256 * 1024);
    defer allocator.free(fixture);
    if (child.stdin) |stdin| {
        try stdin.writeAll(fixture);
        stdin.close();
        child.stdin = null;
    }

    const stdout = if (child.stdout) |out| try out.readToEndAlloc(allocator, 256 * 1024) else "";
    defer allocator.free(stdout);
    const term = try child.wait();
    if (term != .Exited or term.Exited != 0) return error.HookFailed;

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, stdout, .{});
    defer parsed.deinit();
    const decision = parsed.value.object.get("decision") orelse return error.MissingDecision;
    return .{ .passed = std.mem.eql(u8, decision.string, expected_decision) };
}

// ---------------------------------------------------------------------------
// Hermes enable helper
// ---------------------------------------------------------------------------

fn writeHermesEnableHelper(allocator: std.mem.Allocator, plugin_dir: []const u8) !void {
    // Guard: hermesUserPluginRoot can return a path with literal ~ if HOME is unset
    const resolved_dir = if (std.mem.startsWith(u8, plugin_dir, "~/"))
        try std.fs.path.join(allocator, &.{ std.process.getEnvVarOwned(allocator, "HOME") catch return, plugin_dir[2..] })
    else
        try allocator.dupe(u8, plugin_dir);
    defer allocator.free(resolved_dir);

    const help_path = try std.fs.path.join(allocator, &.{ resolved_dir, "ENABLE.txt" });
    defer allocator.free(help_path);
    if (std.fs.path.dirname(help_path)) |parent| try std.fs.cwd().makePath(parent);

    try std.fs.cwd().writeFile(.{
        .sub_path = help_path,
        .data = "Orca plugin files are installed.\nTo enable, run:\n  hermes plugins enable orca\n",
    });
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
    try std.testing.expect(std.mem.indexOf(u8, output, "Orca Plugin Doctor") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Orca version:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Policy:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Plugin directories:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Host binaries:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Drone workstream:") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Platform:") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

fn collectPluginDoctorReportFailureHarness(allocator: std.mem.Allocator) !void {
    var report = try collectPluginDoctorReport(allocator);
    defer report.deinit(allocator);
}

test "plugin doctor report cleans up allocation failure paths" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, collectPluginDoctorReportFailureHarness, .{});
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

    try std.testing.expect(parsed.value.object.get("orca_version") != null);
    try std.testing.expect(parsed.value.object.get("policy") != null);
    try std.testing.expect(parsed.value.object.get("plugin_directories") != null);
    try std.testing.expect(parsed.value.object.get("host_binaries") != null);
    try std.testing.expect(parsed.value.object.get("hermes_paths") != null);
    try std.testing.expect(parsed.value.object.get("hermes_hook_smoke_passed") != null);
    try std.testing.expect(parsed.value.object.get("hermes_hook_smoke_passed").? == .bool);
    try std.testing.expect(parsed.value.object.get("drone") == null);
    try std.testing.expect(parsed.value.object.get("warnings") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin doctor plain output does not expose Edge or drone workstream state" {
    var stdout_buf: [16384]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try doctorCommand(&.{}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Drone workstream") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "live control") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "edge") == null);
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

test "plugin doctor opencode shows opencode-specific section" {
    var stdout_buf: [16384]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try doctorCommand(&.{"opencode"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "OpenCode plugin status:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "host binary:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "project plugin path") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "global plugin path") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin doctor openclaw shows openclaw-specific section" {
    var stdout_buf: [16384]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try doctorCommand(&.{"openclaw"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "OpenClaw plugin status:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "host binary:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "plugin manifest") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "package.json") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin doctor hermes shows hermes-specific section" {
    var stdout_buf: [16384]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try doctorCommand(&.{"hermes"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Hermes plugin status:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "repo plugin.yaml") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "~/.hermes/plugins/orca/plugin.yaml") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "hook smoke test (pre_tool_call):") != null);
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

test "plugin manifest opencode reports expected path" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try manifestCommand(&.{"opencode"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "integrations/opencode-plugin/orca.ts") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "OpenCode uses TypeScript plugins") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin manifest openclaw reports expected paths" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try manifestCommand(&.{"openclaw"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "integrations/openclaw-plugin/openclaw.plugin.json") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "package.json") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin manifest hermes reports expected paths" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try manifestCommand(&.{"hermes"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "integrations/hermes-plugin/plugin.yaml") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "integrations/hermes-plugin/__init__.py") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin manifest all reports all five" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try manifestCommand(&.{"all"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "codex:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "claude:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "opencode:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "openclaw:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "hermes:") != null);
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
    try std.testing.expect(parsed.value.object.get("opencode") != null);
    try std.testing.expect(parsed.value.object.get("openclaw") != null);
    try std.testing.expect(parsed.value.object.get("hermes") != null);
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

test "plugin install opencode --dry-run reports safe preview with paths" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try installCommand(&.{ "opencode", "--dry-run" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "dry-run") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "no changes made") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, ".opencode/plugins/orca.ts") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "~/.config/opencode/plugins/orca.ts") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin install openclaw --dry-run reports safe preview" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try installCommand(&.{ "openclaw", "--dry-run" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "dry-run") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "no changes made") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Target: openclaw") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin install hermes --dry-run reports safe preview" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try installCommand(&.{ "hermes", "--dry-run" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "dry-run") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Target: hermes") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, ".hermes/plugins/orca") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin install all --dry-run reports all five targets" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try installCommand(&.{ "all", "--dry-run" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Target: codex") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Target: claude") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Target: opencode") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Target: openclaw") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Target: hermes") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin install without --yes or --dry-run in non-TTY returns usage" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try installCommand(&.{"codex"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, code);

    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "--yes or --dry-run") != null);
}

test "plugin install --yes switches out of dry-run when dry-run is not explicit" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try installCommand(&.{ "codex", "--path", "does-not-exist-orca-test-plugin", "--yes" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.general, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "mode: install") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "plugin directory: missing") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin install codex --yes fails instead of reporting deferred success" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try installCommand(&.{ "codex", "--yes" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.unsupported, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "mode: install") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "not yet implemented") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "would proceed") == null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin install explicit dry-run wins over --yes" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try installCommand(&.{ "codex", "--yes", "--dry-run" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "mode: dry-run") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin install rejects invalid scope" {
    var stdout_buf: [256]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try installCommand(&.{ "opencode", "--scope", "workspace" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "invalid --scope") != null);
}

test "plugin install opencode --scope global is accepted in dry-run" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try installCommand(&.{ "opencode", "--scope", "global", "--dry-run" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "scope: global") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, output, "orca_doctor") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "edge_safety_status") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "live drone") == null);
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
    try std.testing.expect(std.mem.indexOf(u8, output, "live drone actuation") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "MCP server is active") == null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin doctor reports marketplace status" {
    var stdout_buf: [16384]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try doctorCommand(&.{}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Marketplace files:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, ".agents/plugins/marketplace.json") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, ".claude-plugin/marketplace.json") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin doctor codex reports marketplace and manifest status" {
    var stdout_buf: [16384]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try doctorCommand(&.{"codex"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Codex plugin status:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "marketplace file:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "plugin manifest:") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin doctor claude reports marketplace and manifest status" {
    var stdout_buf: [16384]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try doctorCommand(&.{"claude"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Claude Code plugin status:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "marketplace file:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "plugin manifest:") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin manifest codex reports marketplace path" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try manifestCommand(&.{"codex"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, ".agents/plugins/marketplace.json") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin manifest claude reports marketplace path" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try manifestCommand(&.{"claude"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, ".claude-plugin/marketplace.json") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "plugin manifest all reports marketplace files" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try manifestCommand(&.{"all"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Marketplace files:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, ".agents/plugins/marketplace.json") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, ".claude-plugin/marketplace.json") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}
