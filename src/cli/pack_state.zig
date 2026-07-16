//! Shared pack enablement + summary helpers for Orca CLI (P2a power baseline).
//!
//! Pack *definitions* stay in the Rust registry (daemon). This module only:
//! - maps policy presets → opt-in pack IDs
//! - writes/merges pack enablement into the config the daemon already loads
//! - summarizes enabled packs for `orca doctor` / `orca status`
//!
//! Config path rule (documented in help + status):
//! - Prefer project `.orca.toml` when the workspace is a git repo
//! - Otherwise write user config (`$XDG_CONFIG_HOME/orca/config.toml` or `~/.config/orca/config.toml`)
//!
//! Baseline always-on (never claim the user "disabled" these unless explicitly in `disabled`):
//! - `core` / `core.*` (always enabled by PacksConfig)
//! - `system.disk` (default-on, opt-out via disabled)

const std = @import("std");
const orca_policy = @import("orca_core").policy;
const contracts = @import("daemon_contracts.zig");
const exit_codes = @import("exit_codes.zig");
const plugin = @import("plugin.zig");

/// Max opt-in pack IDs shown inline in summaries (rest become "and K more").
pub const summary_list_limit: usize = 4;

pub const ConfigScope = enum {
    project,
    user,

    pub fn label(self: ConfigScope) []const u8 {
        return switch (self) {
            .project => "project",
            .user => "user",
        };
    }
};

pub const ResolvedPackConfig = struct {
    path: []u8,
    scope: ConfigScope,
};

pub const EnsurePacksResult = struct {
    /// Short user-facing line, e.g. "Packs: baseline only" or "Enabled packs: a, b".
    message: []const u8,
    /// Absolute or relative path written/merged, if any.
    config_path: ?[]const u8 = null,
    scope: ?ConfigScope = null,
    changed: bool = false,
    /// True when caller must free message and config_path.
    owned: bool = false,

    pub fn deinit(self: *EnsurePacksResult, allocator: std.mem.Allocator) void {
        if (!self.owned) return;
        allocator.free(self.message);
        if (self.config_path) |path| allocator.free(path);
        self.* = undefined;
    }
};

/// Result of `enablePacks` / `disablePacks` (CLI activation UX).
pub const PackMutationResult = struct {
    message: []const u8,
    config_path: ?[]const u8 = null,
    scope: ?ConfigScope = null,
    changed: bool = false,
    added: []const []const u8 = &.{},
    removed: []const []const u8 = &.{},
    disabled_added: []const []const u8 = &.{},
    baseline_notes: []const []const u8 = &.{},
    owned: bool = false,

    pub fn deinit(self: *PackMutationResult, allocator: std.mem.Allocator) void {
        if (!self.owned) return;
        allocator.free(self.message);
        if (self.config_path) |path| allocator.free(path);
        freeOwnedSlice(allocator, self.added);
        freeOwnedSlice(allocator, self.removed);
        freeOwnedSlice(allocator, self.disabled_added);
        freeOwnedSlice(allocator, self.baseline_notes);
        self.* = undefined;
    }
};

fn freeOwnedSlice(allocator: std.mem.Allocator, items: []const []const u8) void {
    for (items) |item| allocator.free(item);
    allocator.free(items);
}

pub const PacksSummary = struct {
    known: bool,
    /// Total packs with enabled=true from daemon listing (includes baseline).
    total_enabled: usize = 0,
    total_available: usize = 0,
    /// Opt-in (non-baseline) enabled pack IDs, owned when known.
    opt_in_ids: []const []const u8 = &.{},
    /// Owned when deinit is required.
    owned: bool = false,

    pub fn deinit(self: *PacksSummary, allocator: std.mem.Allocator) void {
        if (!self.owned) return;
        for (self.opt_in_ids) |id| allocator.free(id);
        allocator.free(self.opt_in_ids);
        self.* = undefined;
    }

    pub fn optInCount(self: PacksSummary) usize {
        return self.opt_in_ids.len;
    }
};

/// Opt-in pack IDs for a policy preset. Empty means baseline only.
/// Real registry IDs only — daemon remains source of truth for definitions.
pub fn presetOptInPacks(preset: orca_policy.presets.AgentPreset) []const []const u8 {
    return switch (preset) {
        // Default / conservative coding agents: no surprise opt-ins.
        .generic_agent, .solo_dev, .trusted_local, .mcp_dev => &.{},
        // Coding agents: small safe package-manager pack.
        .claude_code, .codex, .cursor_agent, .opencode, .cline_roo => &.{"package_managers"},
        // Local strict: extra git paranoia on top of baseline.
        .strict_local => &.{"strict_git"},
        // Team / CI style: containers + k8s + terraform + GHA.
        .team_ci, .github_actions => &.{
            "containers.docker",
            "containers.compose",
            "kubernetes.kubectl",
            "infrastructure.terraform",
            "cicd.github_actions",
        },
        // OpenClaw / Hermes plugin workflows: infra-oriented opt-ins.
        .openclaw_hermes => &.{
            "containers.docker",
            "containers.compose",
            "kubernetes.kubectl",
            "infrastructure.terraform",
        },
    };
}

pub fn presetOptInPacksByName(preset_name: []const u8) []const []const u8 {
    const preset = orca_policy.presets.AgentPreset.parse(preset_name) orelse return &.{};
    return presetOptInPacks(preset);
}

/// Baseline packs the daemon always treats as on (unless system.disk explicitly disabled).
pub fn isBaselinePackId(id: []const u8) bool {
    if (std.mem.eql(u8, id, "core") or std.mem.eql(u8, id, "system.disk")) return true;
    if (std.mem.startsWith(u8, id, "core.")) return true;
    return false;
}

pub fn summarizeFromPacksOutput(allocator: std.mem.Allocator, output: contracts.PacksOutput) !PacksSummary {
    var opt_in: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer {
        for (opt_in.items) |id| allocator.free(id);
        opt_in.deinit(allocator);
    }

    var total_enabled: usize = 0;
    for (output.packs) |pack| {
        if (!pack.enabled) continue;
        total_enabled += 1;
        if (isBaselinePackId(pack.id)) continue;
        const owned = try allocator.dupe(u8, pack.id);
        errdefer allocator.free(owned);
        try opt_in.append(allocator, owned);
    }
    std.mem.sort([]const u8, opt_in.items, {}, struct {
        fn less(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.less);

    return .{
        .known = true,
        .total_enabled = if (output.enabled_count > 0) output.enabled_count else total_enabled,
        .total_available = output.total_count,
        .opt_in_ids = try opt_in.toOwnedSlice(allocator),
        .owned = true,
    };
}

pub fn unknownPacksSummary() PacksSummary {
    return .{ .known = false };
}

/// Format a one-line packs summary for status/doctor (caller owns returned slice).
pub fn formatSummaryLine(allocator: std.mem.Allocator, summary: PacksSummary) ![]u8 {
    if (!summary.known) {
        return try allocator.dupe(u8, "unknown (daemon unavailable; shell evaluation fails closed)");
    }
    if (summary.opt_in_ids.len == 0) {
        return try allocator.dupe(u8, "baseline only — enable more with `orca packs enable …`");
    }
    var list_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer list_buf.deinit(allocator);
    const show = @min(summary.opt_in_ids.len, summary_list_limit);
    var i: usize = 0;
    while (i < show) : (i += 1) {
        if (i > 0) try list_buf.appendSlice(allocator, ", ");
        try list_buf.appendSlice(allocator, summary.opt_in_ids[i]);
    }
    if (summary.opt_in_ids.len > summary_list_limit) {
        const more = summary.opt_in_ids.len - summary_list_limit;
        const more_txt = try std.fmt.allocPrint(allocator, ", and {d} more", .{more});
        defer allocator.free(more_txt);
        try list_buf.appendSlice(allocator, more_txt);
    }
    return try std.fmt.allocPrint(
        allocator,
        "baseline + {d} opt-in enabled ({s})",
        .{ summary.opt_in_ids.len, list_buf.items },
    );
}

/// Write doctor-style multi-line packs section (stable labels for tests).
pub fn writeDoctorPacksSection(stdout: anytype, summary: PacksSummary) !void {
    try writeDoctorPacksSectionWithConfig(stdout, summary, null, null);
}

/// Doctor packs section with optional config path/scope for next-action context.
pub fn writeDoctorPacksSectionWithConfig(
    stdout: anytype,
    summary: PacksSummary,
    config_path: ?[]const u8,
    scope: ?ConfigScope,
) !void {
    try stdout.writeAll("\nPacks\n");
    if (!summary.known) {
        try stdout.writeAll("  unknown (daemon unavailable; shell evaluation fails closed)\n");
        try stdout.writeAll("  Next: orca doctor · orca packs  (retry once the daemon is healthy)\n");
        return;
    }
    try stdout.writeAll("  baseline: core.*, system.disk (always on)\n");
    if (summary.opt_in_ids.len == 0) {
        try stdout.writeAll("  opt-in: none enabled (baseline only)\n");
        try stdout.writeAll("  Next: orca packs enable <id>  ·  orca packs --enabled  ·  orca packs show <id>\n");
    } else {
        try stdout.print("  opt-in: {d} enabled", .{summary.opt_in_ids.len});
        const show = @min(summary.opt_in_ids.len, summary_list_limit);
        if (show > 0) {
            try stdout.writeAll(" (");
            var i: usize = 0;
            while (i < show) : (i += 1) {
                if (i > 0) try stdout.writeAll(", ");
                try stdout.writeAll(summary.opt_in_ids[i]);
            }
            if (summary.opt_in_ids.len > summary_list_limit) {
                try stdout.print(", and {d} more", .{summary.opt_in_ids.len - summary_list_limit});
            }
            try stdout.writeAll(")");
        }
        try stdout.writeAll("\n");
        try stdout.writeAll("  Next: orca packs --enabled  ·  orca packs show <id>  ·  orca packs enable <id>\n");
    }
    if (config_path) |path| {
        if (scope) |s| {
            try stdout.print("  Config: {s} ({s})\n", .{ path, s.label() });
        } else {
            try stdout.print("  Config: {s}\n", .{path});
        }
    }
}

/// Query daemon packs JSON via ExecuteCli-compatible callback.
pub fn queryPacksSummary(
    comptime execute_cli: anytype,
    io: std.Io,
    allocator: std.mem.Allocator,
) !PacksSummary {
    var daemon_stdout: std.Io.Writer.Allocating = .init(allocator);
    defer daemon_stdout.deinit();
    var daemon_stderr: std.Io.Writer.Allocating = .init(allocator);
    defer daemon_stderr.deinit();

    const code = execute_cli(io, &.{ "packs", "--format", "json" }, &daemon_stdout.writer, &daemon_stderr.writer) catch {
        return unknownPacksSummary();
    };
    if (code != exit_codes.success) return unknownPacksSummary();

    var parsed = contracts.parsePacks(allocator, daemon_stdout.written()) catch {
        return unknownPacksSummary();
    };
    defer parsed.deinit();
    return try summarizeFromPacksOutput(allocator, parsed.value);
}

pub fn queryPacksSummaryDefault(io: std.Io, allocator: std.mem.Allocator) !PacksSummary {
    const cli = @import("mod.zig");
    return queryPacksSummary(cli.executeDaemonCli, io, allocator);
}

// ─── Config write path ───────────────────────────────────────────────────────

/// Resolve where pack enablement should be written.
/// Prefers project `.orca.toml` when `.git` is present under workspace_root.
pub fn resolvePackConfigPath(
    io: std.Io,
    allocator: std.mem.Allocator,
    workspace_root: []const u8,
) !ResolvedPackConfig {
    const git_path = try std.fs.path.join(allocator, &.{ workspace_root, ".git" });
    defer allocator.free(git_path);
    if (plugin.fileExistsAbsolute(io, git_path) or plugin.dirExists(git_path)) {
        const path = try std.fs.path.join(allocator, &.{ workspace_root, ".orca.toml" });
        return .{ .path = path, .scope = .project };
    }
    return try resolveUserPackConfigPath(allocator);
}

fn resolveUserPackConfigPath(allocator: std.mem.Allocator) !ResolvedPackConfig {
    if (std.c.getenv("XDG_CONFIG_HOME")) |xdg| {
        const path = try std.fs.path.join(allocator, &.{ std.mem.span(xdg), "orca", "config.toml" });
        return .{ .path = path, .scope = .user };
    }
    const home = std.c.getenv("HOME") orelse return error.HomeDirectoryNotFound;
    const path = try std.fs.path.join(allocator, &.{ std.mem.span(home), ".config", "orca", "config.toml" });
    return .{ .path = path, .scope = .user };
}

/// Ensure opt-in packs for `preset` are listed in the daemon-readable pack config.
/// Additive / idempotent: never removes existing enabled packs or disabled entries.
pub fn ensurePresetPacks(
    io: std.Io,
    allocator: std.mem.Allocator,
    workspace_root: []const u8,
    preset: orca_policy.presets.AgentPreset,
) !EnsurePacksResult {
    const desired = presetOptInPacks(preset);
    if (desired.len == 0) {
        return .{
            .message = "Packs: baseline only",
            .changed = false,
            .owned = false,
        };
    }

    const resolved = try resolvePackConfigPath(io, allocator, workspace_root);
    errdefer allocator.free(resolved.path);

    const merge = try mergeEnabledPacksIntoConfig(io, allocator, resolved.path, desired);
    defer {
        for (merge.final_enabled) |id| allocator.free(id);
        allocator.free(merge.final_enabled);
    }

    const list_msg = try formatEnabledPacksMessage(allocator, merge.final_enabled);
    errdefer allocator.free(list_msg);

    return .{
        .message = list_msg,
        .config_path = resolved.path,
        .scope = resolved.scope,
        .changed = merge.changed,
        .owned = true,
    };
}

pub fn ensurePresetPacksByName(
    io: std.Io,
    allocator: std.mem.Allocator,
    workspace_root: []const u8,
    preset_name: []const u8,
) !EnsurePacksResult {
    const preset = orca_policy.presets.AgentPreset.parse(preset_name) orelse {
        return .{
            .message = "Packs: baseline only",
            .changed = false,
            .owned = false,
        };
    };
    return ensurePresetPacks(io, allocator, workspace_root, preset);
}

/// Additive enable of opt-in pack IDs into project/user pack config.
/// Baseline IDs are noted as always-on (and removed from disabled if present).
pub fn enablePacks(
    io: std.Io,
    allocator: std.mem.Allocator,
    workspace_root: []const u8,
    ids: []const []const u8,
) !PackMutationResult {
    if (ids.len == 0) return error.InvalidArguments;

    const resolved = try resolvePackConfigPath(io, allocator, workspace_root);
    errdefer allocator.free(resolved.path);

    const existing_raw = readFileIfExists(io, allocator, resolved.path) catch null;
    defer if (existing_raw) |raw| allocator.free(raw);

    var enabled_list: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (enabled_list.items) |id| allocator.free(id);
        enabled_list.deinit(allocator);
    }
    var disabled_list: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (disabled_list.items) |id| allocator.free(id);
        disabled_list.deinit(allocator);
    }

    if (existing_raw) |raw| {
        try collectQuotedPackIdsOwned(allocator, raw, &enabled_list);
        try collectQuotedDisabledIdsOwned(allocator, raw, &disabled_list);
    }

    var added: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer {
        for (added.items) |id| allocator.free(id);
        added.deinit(allocator);
    }
    var baseline_notes: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer {
        for (baseline_notes.items) |n| allocator.free(n);
        baseline_notes.deinit(allocator);
    }
    // Creating a new config file is a change only when we write opt-in ids or clear disabled.
    var changed = false;

    for (ids) |pack_id| {
        if (!looksLikePackId(pack_id)) return error.InvalidArguments;

        // Re-enable: drop from disabled when present.
        if (removeIdFromList(allocator, &disabled_list, pack_id)) {
            changed = true;
        }

        if (isBaselinePackId(pack_id)) {
            const note = try std.fmt.allocPrint(
                allocator,
                "{s} is always on (baseline); no need to list it in enabled",
                .{pack_id},
            );
            try baseline_notes.append(allocator, note);
            continue;
        }

        if (listContains(enabled_list.items, pack_id)) continue;
        try enabled_list.append(allocator, try allocator.dupe(u8, pack_id));
        try added.append(allocator, try allocator.dupe(u8, pack_id));
        changed = true;
    }

    if (changed) {
        try writePacksArrays(io, allocator, resolved.path, existing_raw, enabled_list.items, disabled_list.items);
    }

    const message = try formatMutationMessage(allocator, .enable, added.items, &.{}, &.{}, baseline_notes.items, changed);
    const added_owned = try added.toOwnedSlice(allocator);
    added = .empty;
    const notes_owned = try baseline_notes.toOwnedSlice(allocator);
    baseline_notes = .empty;
    return .{
        .message = message,
        .config_path = resolved.path,
        .scope = resolved.scope,
        .changed = changed,
        .added = added_owned,
        .baseline_notes = notes_owned,
        .owned = true,
    };
}

/// Disable pack IDs: opt-in removed from enabled; baseline added to disabled.
pub fn disablePacks(
    io: std.Io,
    allocator: std.mem.Allocator,
    workspace_root: []const u8,
    ids: []const []const u8,
) !PackMutationResult {
    if (ids.len == 0) return error.InvalidArguments;

    const resolved = try resolvePackConfigPath(io, allocator, workspace_root);
    errdefer allocator.free(resolved.path);

    const existing_raw = readFileIfExists(io, allocator, resolved.path) catch null;
    defer if (existing_raw) |raw| allocator.free(raw);

    var enabled_list: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (enabled_list.items) |id| allocator.free(id);
        enabled_list.deinit(allocator);
    }
    var disabled_list: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (disabled_list.items) |id| allocator.free(id);
        disabled_list.deinit(allocator);
    }

    if (existing_raw) |raw| {
        try collectQuotedPackIdsOwned(allocator, raw, &enabled_list);
        try collectQuotedDisabledIdsOwned(allocator, raw, &disabled_list);
    }

    var removed: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer {
        for (removed.items) |id| allocator.free(id);
        removed.deinit(allocator);
    }
    var disabled_added: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer {
        for (disabled_added.items) |id| allocator.free(id);
        disabled_added.deinit(allocator);
    }
    var baseline_notes: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer {
        for (baseline_notes.items) |n| allocator.free(n);
        baseline_notes.deinit(allocator);
    }
    var changed = false;

    for (ids) |pack_id| {
        if (!looksLikePackId(pack_id)) return error.InvalidArguments;

        if (isBaselinePackId(pack_id)) {
            if (removeIdFromList(allocator, &enabled_list, pack_id)) {
                try removed.append(allocator, try allocator.dupe(u8, pack_id));
                changed = true;
            }
            if (!listContains(disabled_list.items, pack_id)) {
                try disabled_list.append(allocator, try allocator.dupe(u8, pack_id));
                try disabled_added.append(allocator, try allocator.dupe(u8, pack_id));
                changed = true;
            }
            if (std.mem.eql(u8, pack_id, "core") or std.mem.startsWith(u8, pack_id, "core.")) {
                const note = try std.fmt.allocPrint(
                    allocator,
                    "{s}: listed in disabled; daemon may still expand core category as always-on",
                    .{pack_id},
                );
                try baseline_notes.append(allocator, note);
            }
            continue;
        }

        if (removeIdFromList(allocator, &enabled_list, pack_id)) {
            try removed.append(allocator, try allocator.dupe(u8, pack_id));
            changed = true;
        }
    }

    if (changed) {
        try writePacksArrays(io, allocator, resolved.path, existing_raw, enabled_list.items, disabled_list.items);
    }

    const message = try formatMutationMessage(allocator, .disable, &.{}, removed.items, disabled_added.items, baseline_notes.items, changed);
    const removed_owned = try removed.toOwnedSlice(allocator);
    removed = .empty;
    const disabled_owned = try disabled_added.toOwnedSlice(allocator);
    disabled_added = .empty;
    const notes_owned = try baseline_notes.toOwnedSlice(allocator);
    baseline_notes = .empty;
    return .{
        .message = message,
        .config_path = resolved.path,
        .scope = resolved.scope,
        .changed = changed,
        .removed = removed_owned,
        .disabled_added = disabled_owned,
        .baseline_notes = notes_owned,
        .owned = true,
    };
}

const MutationKind = enum { enable, disable };

fn formatMutationMessage(
    allocator: std.mem.Allocator,
    kind: MutationKind,
    added: []const []const u8,
    removed: []const []const u8,
    disabled_added: []const []const u8,
    baseline_notes: []const []const u8,
    changed: bool,
) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(allocator);
    switch (kind) {
        .enable => {
            if (added.len == 0 and !changed) {
                try buf.appendSlice(allocator, "No pack config changes (already enabled or baseline only)");
            } else if (added.len == 0 and changed) {
                try buf.appendSlice(allocator, "Updated pack config (baseline / disabled list)");
            } else {
                try buf.appendSlice(allocator, "Enabled ");
                try appendIdList(allocator, &buf, added);
            }
        },
        .disable => {
            if (!changed) {
                try buf.appendSlice(allocator, "No pack config changes (already disabled or not enabled)");
            } else {
                if (removed.len > 0) {
                    try buf.appendSlice(allocator, "Disabled ");
                    try appendIdList(allocator, &buf, removed);
                }
                if (disabled_added.len > 0) {
                    if (buf.items.len > 0) try buf.appendSlice(allocator, "; ");
                    try buf.appendSlice(allocator, "opted out ");
                    try appendIdList(allocator, &buf, disabled_added);
                    try buf.appendSlice(allocator, " via disabled");
                }
                if (buf.items.len == 0) {
                    try buf.appendSlice(allocator, "Updated pack config");
                }
            }
        },
    }
    if (baseline_notes.len > 0) {
        try buf.appendSlice(allocator, " · ");
        try buf.appendSlice(allocator, baseline_notes[0]);
        if (baseline_notes.len > 1) {
            const more = try std.fmt.allocPrint(allocator, " (+{d} more notes)", .{baseline_notes.len - 1});
            defer allocator.free(more);
            try buf.appendSlice(allocator, more);
        }
    }
    return try buf.toOwnedSlice(allocator);
}

fn appendIdList(allocator: std.mem.Allocator, buf: *std.ArrayListUnmanaged(u8), ids: []const []const u8) !void {
    for (ids, 0..) |id, i| {
        if (i > 0) try buf.appendSlice(allocator, ", ");
        try buf.appendSlice(allocator, id);
    }
}

fn listContains(haystack: []const []const u8, needle: []const u8) bool {
    for (haystack) |id| {
        if (std.mem.eql(u8, id, needle)) return true;
    }
    return false;
}

fn removeIdFromList(allocator: std.mem.Allocator, list: *std.ArrayListUnmanaged([]const u8), id: []const u8) bool {
    var i: usize = 0;
    while (i < list.items.len) : (i += 1) {
        if (std.mem.eql(u8, list.items[i], id)) {
            allocator.free(list.items[i]);
            _ = list.orderedRemove(i);
            return true;
        }
    }
    return false;
}

fn writePacksArrays(
    io: std.Io,
    allocator: std.mem.Allocator,
    config_path: []const u8,
    existing_raw: ?[]const u8,
    enabled: []const []const u8,
    disabled: []const []const u8,
) !void {
    if (existing_raw) |raw| {
        const rewritten = try rewritePacksEnabledSection(allocator, raw, enabled);
        defer allocator.free(rewritten);
        const with_disabled = try rewritePacksDisabledSection(allocator, rewritten, disabled);
        defer allocator.free(with_disabled);
        try writeConfigFile(io, allocator, config_path, with_disabled);
    } else {
        const body = try renderNewPackConfigWithDisabled(allocator, enabled, disabled);
        defer allocator.free(body);
        try writeConfigFile(io, allocator, config_path, body);
    }
}

fn formatEnabledPacksMessage(allocator: std.mem.Allocator, enabled: []const []const u8) ![]u8 {
    if (enabled.len == 0) return try allocator.dupe(u8, "Packs: baseline only");
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, "Enabled packs: ");
    for (enabled, 0..) |id, i| {
        if (i > 0) try buf.appendSlice(allocator, ", ");
        try buf.appendSlice(allocator, id);
    }
    return try buf.toOwnedSlice(allocator);
}

const MergeResult = struct {
    final_enabled: [][]const u8,
    changed: bool,
};

fn mergeEnabledPacksIntoConfig(
    io: std.Io,
    allocator: std.mem.Allocator,
    config_path: []const u8,
    desired: []const []const u8,
) !MergeResult {
    const existing_raw = readFileIfExists(io, allocator, config_path) catch null;
    defer if (existing_raw) |raw| allocator.free(raw);

    var enabled_set: std.StringArrayHashMapUnmanaged(void) = .empty;
    defer enabled_set.deinit(allocator);

    if (existing_raw) |raw| {
        try collectQuotedPackIds(allocator, raw, &enabled_set);
    }

    var changed = existing_raw == null;
    for (desired) |pack_id| {
        const gop = try enabled_set.getOrPut(allocator, pack_id);
        if (!gop.found_existing) {
            // Key must be owned by map for later free of keys we allocate;
            // desired slices are static — store pointer as-is for set membership only.
            gop.key_ptr.* = pack_id;
            gop.value_ptr.* = {};
            changed = true;
        }
    }

    // Build ordered final list: desired first (stable), then any pre-existing extras.
    var final_list: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer {
        for (final_list.items) |id| allocator.free(id);
        final_list.deinit(allocator);
    }
    for (desired) |pack_id| {
        try final_list.append(allocator, try allocator.dupe(u8, pack_id));
    }
    if (existing_raw) |raw| {
        var existing_ids: std.ArrayListUnmanaged([]const u8) = .empty;
        defer {
            for (existing_ids.items) |id| allocator.free(id);
            existing_ids.deinit(allocator);
        }
        try collectQuotedPackIdsOwned(allocator, raw, &existing_ids);
        for (existing_ids.items) |id| {
            var already = false;
            for (final_list.items) |have| {
                if (std.mem.eql(u8, have, id)) {
                    already = true;
                    break;
                }
            }
            if (!already) try final_list.append(allocator, try allocator.dupe(u8, id));
        }
    }

    if (!changed and existing_raw != null) {
        return .{
            .final_enabled = try final_list.toOwnedSlice(allocator),
            .changed = false,
        };
    }

    // Write full config when new, or replace [packs] enabled when merging.
    if (existing_raw) |raw| {
        const rewritten = try rewritePacksEnabledSection(allocator, raw, final_list.items);
        defer allocator.free(rewritten);
        try writeConfigFile(io, allocator, config_path, rewritten);
    } else {
        const body = try renderNewPackConfig(allocator, final_list.items);
        defer allocator.free(body);
        try writeConfigFile(io, allocator, config_path, body);
    }

    return .{
        .final_enabled = try final_list.toOwnedSlice(allocator),
        .changed = true,
    };
}

fn readFileIfExists(io: std.Io, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return error.FileNotFound,
        else => return err,
    };
}

fn writeConfigFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8, contents: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| {
        std.Io.Dir.cwd().createDirPath(io, dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }
    _ = allocator;
    var file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, contents);
}

fn renderNewPackConfig(allocator: std.mem.Allocator, enabled: []const []const u8) ![]u8 {
    return renderNewPackConfigWithDisabled(allocator, enabled, &.{});
}

fn renderNewPackConfigWithDisabled(
    allocator: std.mem.Allocator,
    enabled: []const []const u8,
    disabled: []const []const u8,
) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(allocator);
    try buf.appendSlice(allocator,
        \\# Orca pack configuration
        \\# Written by `orca init` / `orca setup` / `orca start` / `orca packs enable|disable`.
        \\# Prefer project `.orca.toml` in a git repo; otherwise user config.
        \\# Baseline packs (core.*, system.disk) are always on and need not be listed.
        \\# Additive: re-running setup merges packs and does not wipe customizations.
        \\
        \\[packs]
        \\enabled = [
    );
    for (enabled, 0..) |id, i| {
        if (i > 0) try buf.appendSlice(allocator, ",");
        try buf.appendSlice(allocator, "\n    \"");
        try buf.appendSlice(allocator, id);
        try buf.appendSlice(allocator, "\"");
    }
    if (enabled.len > 0) try buf.appendSlice(allocator, "\n");
    try buf.appendSlice(allocator, "]\ndisabled = ");
    const disabled_arr = try renderEnabledArray(allocator, disabled);
    defer allocator.free(disabled_arr);
    try buf.appendSlice(allocator, disabled_arr);
    try buf.appendSlice(allocator, "\n");
    return try buf.toOwnedSlice(allocator);
}

/// Replace or append a `[packs] enabled = [...]` block while preserving other content.
fn rewritePacksEnabledSection(allocator: std.mem.Allocator, existing: []const u8, enabled: []const []const u8) ![]u8 {
    const new_enabled = try renderEnabledArray(allocator, enabled);
    defer allocator.free(new_enabled);

    // If there is no [packs] section, append one.
    if (std.mem.indexOf(u8, existing, "[packs]") == null) {
        return try std.fmt.allocPrint(allocator, "{s}\n[packs]\nenabled = {s}\ndisabled = []\n", .{ existing, new_enabled });
    }

    // Find `enabled =` after [packs] and replace the array value.
    const packs_idx = std.mem.indexOf(u8, existing, "[packs]").?;
    const after_packs = existing[packs_idx..];
    if (std.mem.indexOf(u8, after_packs, "enabled")) |rel| {
        const abs = packs_idx + rel;
        // Find '=' after enabled
        const eq_rel = std.mem.indexOfScalar(u8, existing[abs..], '=') orelse {
            return try std.fmt.allocPrint(allocator, "{s}\nenabled = {s}\n", .{ existing, new_enabled });
        };
        const value_start = abs + eq_rel + 1;
        // Skip whitespace
        var vs = value_start;
        while (vs < existing.len and (existing[vs] == ' ' or existing[vs] == '\t')) : (vs += 1) {}
        if (vs < existing.len and existing[vs] == '[') {
            // Find matching closing ]
            var depth: usize = 0;
            var ve = vs;
            while (ve < existing.len) : (ve += 1) {
                if (existing[ve] == '[') depth += 1;
                if (existing[ve] == ']') {
                    depth -= 1;
                    if (depth == 0) {
                        ve += 1;
                        break;
                    }
                }
            }
            return try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ existing[0..vs], new_enabled, existing[ve..] });
        }
    }

    // [packs] exists but no enabled key — insert after [packs] line.
    var line_end = packs_idx;
    while (line_end < existing.len and existing[line_end] != '\n') : (line_end += 1) {}
    if (line_end < existing.len) line_end += 1;
    return try std.fmt.allocPrint(
        allocator,
        "{s}enabled = {s}\n{s}",
        .{ existing[0..line_end], new_enabled, existing[line_end..] },
    );
}

fn renderEnabledArray(allocator: std.mem.Allocator, enabled: []const []const u8) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(allocator);
    try buf.appendSlice(allocator, "[\n");
    for (enabled, 0..) |id, i| {
        try buf.appendSlice(allocator, "    \"");
        try buf.appendSlice(allocator, id);
        try buf.appendSlice(allocator, "\"");
        if (i + 1 < enabled.len) try buf.appendSlice(allocator, ",");
        try buf.appendSlice(allocator, "\n");
    }
    try buf.appendSlice(allocator, "]");
    return try buf.toOwnedSlice(allocator);
}

/// Replace or append a `[packs] disabled = [...]` block while preserving other content.
fn rewritePacksDisabledSection(allocator: std.mem.Allocator, existing: []const u8, disabled: []const []const u8) ![]u8 {
    const new_disabled = try renderEnabledArray(allocator, disabled);
    defer allocator.free(new_disabled);

    if (std.mem.indexOf(u8, existing, "[packs]") == null) {
        return try std.fmt.allocPrint(allocator, "{s}\n[packs]\nenabled = []\ndisabled = {s}\n", .{ existing, new_disabled });
    }

    if (disabledArraySlice(existing)) |array_slice| {
        // Locate the absolute start of the array value inside existing.
        const packs_idx = std.mem.indexOf(u8, existing, "[packs]").?;
        const bounds = packsSectionBounds(existing).?;
        const section = existing[bounds.start..bounds.end];
        const rel = std.mem.indexOf(u8, section, array_slice) orelse {
            return try std.fmt.allocPrint(allocator, "{s}\ndisabled = {s}\n", .{ existing, new_disabled });
        };
        const abs = bounds.start + rel;
        _ = packs_idx;
        return try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ existing[0..abs], new_disabled, existing[abs + array_slice.len ..] });
    }

    // [packs] exists but no disabled key — insert after enabled array or [packs] line.
    const packs_idx = std.mem.indexOf(u8, existing, "[packs]").?;
    if (enabledArraySlice(existing)) |enabled_slice| {
        const bounds = packsSectionBounds(existing).?;
        const section = existing[bounds.start..bounds.end];
        const rel = std.mem.indexOf(u8, section, enabled_slice) orelse packs_idx;
        const abs_end = bounds.start + rel + enabled_slice.len;
        return try std.fmt.allocPrint(
            allocator,
            "{s}\ndisabled = {s}{s}",
            .{ existing[0..abs_end], new_disabled, existing[abs_end..] },
        );
    }

    var line_end = packs_idx;
    while (line_end < existing.len and existing[line_end] != '\n') : (line_end += 1) {}
    if (line_end < existing.len) line_end += 1;
    return try std.fmt.allocPrint(
        allocator,
        "{s}disabled = {s}\n{s}",
        .{ existing[0..line_end], new_disabled, existing[line_end..] },
    );
}

/// Locate the `disabled = [...]` array value inside a `[packs]` section only.
fn disabledArraySlice(content: []const u8) ?[]const u8 {
    const bounds = packsSectionBounds(content) orelse return null;
    const section = content[bounds.start..bounds.end];

    var pos: usize = 0;
    while (pos < section.len) {
        const rel = std.mem.indexOf(u8, section[pos..], "disabled") orelse break;
        const abs = pos + rel;
        if (abs > 0) {
            const prev = section[abs - 1];
            if (prev != '\n' and prev != '\r' and prev != ' ' and prev != '\t') {
                pos = abs + "disabled".len;
                continue;
            }
        }
        var cursor = abs + "disabled".len;
        while (cursor < section.len and (section[cursor] == ' ' or section[cursor] == '\t')) : (cursor += 1) {}
        if (cursor >= section.len or section[cursor] != '=') {
            pos = abs + "disabled".len;
            continue;
        }
        cursor += 1;
        while (cursor < section.len and (section[cursor] == ' ' or section[cursor] == '\t' or section[cursor] == '\n' or section[cursor] == '\r')) : (cursor += 1) {}
        if (cursor >= section.len or section[cursor] != '[') {
            pos = abs + "disabled".len;
            continue;
        }
        const array_start = cursor;
        var depth: usize = 0;
        var ve = cursor;
        while (ve < section.len) : (ve += 1) {
            if (section[ve] == '[') depth += 1;
            if (section[ve] == ']') {
                depth -= 1;
                if (depth == 0) {
                    ve += 1;
                    return section[array_start..ve];
                }
            }
        }
        return null;
    }
    return null;
}

fn collectQuotedDisabledIdsOwned(allocator: std.mem.Allocator, content: []const u8, out: *std.ArrayListUnmanaged([]const u8)) !void {
    const array = disabledArraySlice(content) orelse return;
    var i: usize = 0;
    while (i < array.len) : (i += 1) {
        if (array[i] != '"') continue;
        const start = i + 1;
        const close = std.mem.indexOfScalar(u8, array[start..], '"') orelse break;
        const id = array[start .. start + close];
        if (looksLikePackId(id)) {
            try out.append(allocator, try allocator.dupe(u8, id));
        }
        i = start + close;
    }
}

fn packsSectionBounds(content: []const u8) ?struct { start: usize, end: usize } {
    const packs_idx = std.mem.indexOf(u8, content, "[packs]") orelse return null;
    var end = content.len;
    var search = packs_idx + "[packs]".len;
    while (search < content.len) : (search += 1) {
        if (content[search] == '\n' and search + 1 < content.len and content[search + 1] == '[') {
            const line_start = search + 1;
            if (std.mem.startsWith(u8, content[line_start..], "[")) {
                end = line_start;
                break;
            }
        }
    }
    return .{ .start = packs_idx, .end = end };
}

/// Locate the `enabled = [...]` array value inside a `[packs]` section only.
/// Does not scan `disabled` (or other keys) — disabled IDs must never be treated as enabled.
fn enabledArraySlice(content: []const u8) ?[]const u8 {
    const bounds = packsSectionBounds(content) orelse return null;
    const section = content[bounds.start..bounds.end];

    var pos: usize = 0;
    while (pos < section.len) {
        const rel = std.mem.indexOf(u8, section[pos..], "enabled") orelse break;
        const abs = pos + rel;
        // Require key-ish token: start of section/line or preceded by whitespace.
        if (abs > 0) {
            const prev = section[abs - 1];
            if (prev != '\n' and prev != '\r' and prev != ' ' and prev != '\t') {
                pos = abs + "enabled".len;
                continue;
            }
        }
        var cursor = abs + "enabled".len;
        while (cursor < section.len and (section[cursor] == ' ' or section[cursor] == '\t')) : (cursor += 1) {}
        if (cursor >= section.len or section[cursor] != '=') {
            pos = abs + "enabled".len;
            continue;
        }
        cursor += 1;
        while (cursor < section.len and (section[cursor] == ' ' or section[cursor] == '\t' or section[cursor] == '\n' or section[cursor] == '\r')) : (cursor += 1) {}
        if (cursor >= section.len or section[cursor] != '[') {
            pos = abs + "enabled".len;
            continue;
        }
        const array_start = cursor;
        var depth: usize = 0;
        var ve = cursor;
        while (ve < section.len) : (ve += 1) {
            if (section[ve] == '[') depth += 1;
            if (section[ve] == ']') {
                depth -= 1;
                if (depth == 0) {
                    ve += 1;
                    return section[array_start..ve];
                }
            }
        }
        return null;
    }
    return null;
}

fn looksLikePackId(id: []const u8) bool {
    if (id.len == 0) return false;
    for (id) |c| {
        const ok = (c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9') or
            c == '_' or c == '.' or c == '-';
        if (!ok) return false;
    }
    return true;
}

fn collectQuotedPackIds(allocator: std.mem.Allocator, content: []const u8, set: *std.StringArrayHashMapUnmanaged(void)) !void {
    const array = enabledArraySlice(content) orelse return;
    var i: usize = 0;
    while (i < array.len) : (i += 1) {
        if (array[i] != '"') continue;
        const start = i + 1;
        const close = std.mem.indexOfScalar(u8, array[start..], '"') orelse break;
        const id = array[start .. start + close];
        if (looksLikePackId(id)) {
            const gop = try set.getOrPut(allocator, id);
            if (!gop.found_existing) {
                gop.key_ptr.* = id;
                gop.value_ptr.* = {};
            }
        }
        i = start + close;
    }
}

fn collectQuotedPackIdsOwned(allocator: std.mem.Allocator, content: []const u8, out: *std.ArrayListUnmanaged([]const u8)) !void {
    var set: std.StringArrayHashMapUnmanaged(void) = .empty;
    defer set.deinit(allocator);
    try collectQuotedPackIds(allocator, content, &set);
    var it = set.iterator();
    while (it.next()) |entry| {
        try out.append(allocator, try allocator.dupe(u8, entry.key_ptr.*));
    }
}

// ─── Tests ───────────────────────────────────────────────────────────────────

test "preset opt-in map: baseline vs infra vs coding" {
    try std.testing.expectEqual(@as(usize, 0), presetOptInPacks(.generic_agent).len);
    try std.testing.expectEqual(@as(usize, 0), presetOptInPacks(.solo_dev).len);
    try std.testing.expectEqualStrings("package_managers", presetOptInPacks(.claude_code)[0]);
    try std.testing.expectEqualStrings("package_managers", presetOptInPacks(.codex)[0]);
    try std.testing.expectEqualStrings("strict_git", presetOptInPacks(.strict_local)[0]);
    const team = presetOptInPacks(.team_ci);
    try std.testing.expect(team.len >= 3);
    try std.testing.expectEqualStrings("containers.docker", team[0]);
    const hermes = presetOptInPacks(.openclaw_hermes);
    try std.testing.expectEqualStrings("kubernetes.kubectl", hermes[2]);
    try std.testing.expectEqualStrings("infrastructure.terraform", hermes[3]);
}

test "isBaselinePackId covers core and system.disk only" {
    try std.testing.expect(isBaselinePackId("core"));
    try std.testing.expect(isBaselinePackId("core.git"));
    try std.testing.expect(isBaselinePackId("core.filesystem"));
    try std.testing.expect(isBaselinePackId("system.disk"));
    try std.testing.expect(!isBaselinePackId("containers.docker"));
    try std.testing.expect(!isBaselinePackId("system.services"));
    try std.testing.expect(!isBaselinePackId("package_managers"));
}

test "summarizeFromPacksOutput separates baseline and opt-in" {
    const rows = [_]contracts.PackInfo{
        .{ .id = "core.git", .name = "Git", .category = "core", .description = "g", .enabled = true, .safe_pattern_count = 1, .destructive_pattern_count = 1 },
        .{ .id = "system.disk", .name = "Disk", .category = "system", .description = "d", .enabled = true, .safe_pattern_count = 1, .destructive_pattern_count = 1 },
        .{ .id = "containers.docker", .name = "Docker", .category = "containers", .description = "c", .enabled = true, .safe_pattern_count = 1, .destructive_pattern_count = 1 },
        .{ .id = "database.postgresql", .name = "PG", .category = "database", .description = "p", .enabled = false, .safe_pattern_count = 1, .destructive_pattern_count = 1 },
    };
    var summary = try summarizeFromPacksOutput(std.testing.allocator, .{
        .packs = &rows,
        .enabled_count = 3,
        .total_count = 4,
    });
    defer summary.deinit(std.testing.allocator);
    try std.testing.expect(summary.known);
    try std.testing.expectEqual(@as(usize, 1), summary.opt_in_ids.len);
    try std.testing.expectEqualStrings("containers.docker", summary.opt_in_ids[0]);
    const line = try formatSummaryLine(std.testing.allocator, summary);
    defer std.testing.allocator.free(line);
    try std.testing.expect(std.mem.indexOf(u8, line, "baseline + 1 opt-in") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "containers.docker") != null);
}

test "ensurePresetPacks writes project config and is idempotent" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root_z = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root_z);
    const root = try std.testing.allocator.dupe(u8, root_z);
    defer std.testing.allocator.free(root);

    try tmp.dir.createDirPath(std.testing.io, ".git");

    var first = try ensurePresetPacks(std.testing.io, std.testing.allocator, root, .team_ci);
    defer first.deinit(std.testing.allocator);
    try std.testing.expect(first.changed);
    try std.testing.expect(first.scope == .project);
    try std.testing.expect(std.mem.indexOf(u8, first.message, "containers.docker") != null);

    const config = try tmp.dir.readFileAlloc(std.testing.io, ".orca.toml", std.testing.allocator, .limited(8192));
    defer std.testing.allocator.free(config);
    try std.testing.expect(std.mem.indexOf(u8, config, "containers.docker") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "kubernetes.kubectl") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "cicd.github_actions") != null);

    var second = try ensurePresetPacks(std.testing.io, std.testing.allocator, root, .team_ci);
    defer second.deinit(std.testing.allocator);
    try std.testing.expect(!second.changed);

    // Adding another preset merges without wiping.
    var third = try ensurePresetPacks(std.testing.io, std.testing.allocator, root, .claude_code);
    defer third.deinit(std.testing.allocator);
    try std.testing.expect(third.changed);
    const config2 = try tmp.dir.readFileAlloc(std.testing.io, ".orca.toml", std.testing.allocator, .limited(8192));
    defer std.testing.allocator.free(config2);
    try std.testing.expect(std.mem.indexOf(u8, config2, "containers.docker") != null);
    try std.testing.expect(std.mem.indexOf(u8, config2, "package_managers") != null);
}

test "generic-agent ensure leaves baseline only without writing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root_z = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root_z);
    const root = try std.testing.allocator.dupe(u8, root_z);
    defer std.testing.allocator.free(root);
    try tmp.dir.createDirPath(std.testing.io, ".git");

    var result = try ensurePresetPacks(std.testing.io, std.testing.allocator, root, .generic_agent);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(!result.changed);
    try std.testing.expectEqualStrings("Packs: baseline only", result.message);
    const cfg_path = try std.fs.path.join(std.testing.allocator, &.{ root, ".orca.toml" });
    defer std.testing.allocator.free(cfg_path);
    try std.testing.expect(!plugin.fileExistsAbsolute(std.testing.io, cfg_path));
}

test "doctor packs section labels are stable" {
    var buf: [1024]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    const ids = [_][]const u8{ "containers.docker", "kubernetes.kubectl" };
    const summary: PacksSummary = .{
        .known = true,
        .total_enabled = 4,
        .total_available = 10,
        .opt_in_ids = &ids,
        .owned = false,
    };
    try writeDoctorPacksSection(&writer, summary);
    const out = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, out, "\nPacks\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "baseline: core.*, system.disk") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "opt-in: 2 enabled") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "containers.docker") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "orca packs show") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "orca packs enable") != null);

    writer = .fixed(&buf);
    try writeDoctorPacksSection(&writer, unknownPacksSummary());
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "unknown (daemon unavailable") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "orca packs") != null);
}

test "rewritePacksEnabledSection preserves other keys" {
    const existing =
        \\[general]
        \\verbose = true
        \\
        \\[packs]
        \\enabled = ["old.pack"]
        \\disabled = ["system.disk"]
        \\
    ;
    const enabled = [_][]const u8{ "containers.docker", "old.pack" };
    const out = try rewritePacksEnabledSection(std.testing.allocator, existing, &enabled);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "verbose = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "containers.docker") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "disabled = [\"system.disk\"]") != null);
}

test "merge does not promote disabled packs into enabled" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root_z = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root_z);
    const root = try std.testing.allocator.dupe(u8, root_z);
    defer std.testing.allocator.free(root);
    try tmp.dir.createDirPath(std.testing.io, ".git");

    const seed =
        \\[packs]
        \\enabled = ["package_managers"]
        \\disabled = ["system.disk"]
        \\
    ;
    {
        const f = try tmp.dir.createFile(std.testing.io, ".orca.toml", .{});
        defer f.close(std.testing.io);
        try f.writeStreamingAll(std.testing.io, seed);
    }

    var result = try ensurePresetPacks(std.testing.io, std.testing.allocator, root, .team_ci);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.changed);

    const config = try tmp.dir.readFileAlloc(std.testing.io, ".orca.toml", std.testing.allocator, .limited(8192));
    defer std.testing.allocator.free(config);
    try std.testing.expect(std.mem.indexOf(u8, config, "containers.docker") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "package_managers") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "disabled = [\"system.disk\"]") != null);

    // system.disk must remain only under disabled, not be copied into enabled.
    const enabled_slice = enabledArraySlice(config) orelse {
        try std.testing.expect(false);
        return;
    };
    try std.testing.expect(std.mem.indexOf(u8, enabled_slice, "system.disk") == null);
}

test "collectQuotedPackIds reads only enabled array" {
    const content =
        \\[packs]
        \\enabled = ["package_managers", "containers.docker"]
        \\disabled = ["system.disk", "strict_git"]
        \\
    ;
    var set: std.StringArrayHashMapUnmanaged(void) = .empty;
    defer set.deinit(std.testing.allocator);
    try collectQuotedPackIds(std.testing.allocator, content, &set);
    try std.testing.expect(set.contains("package_managers"));
    try std.testing.expect(set.contains("containers.docker"));
    try std.testing.expect(!set.contains("system.disk"));
    try std.testing.expect(!set.contains("strict_git"));
}

test "enablePacks merges opt-in packs and is idempotent" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root_z = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root_z);
    const root = try std.testing.allocator.dupe(u8, root_z);
    defer std.testing.allocator.free(root);
    try tmp.dir.createDirPath(std.testing.io, ".git");

    const seed =
        \\[general]
        \\verbose = true
        \\
        \\[packs]
        \\enabled = ["package_managers"]
        \\disabled = ["system.disk"]
        \\
    ;
    {
        const f = try tmp.dir.createFile(std.testing.io, ".orca.toml", .{});
        defer f.close(std.testing.io);
        try f.writeStreamingAll(std.testing.io, seed);
    }

    var first = try enablePacks(std.testing.io, std.testing.allocator, root, &.{ "containers.docker", "package_managers" });
    defer first.deinit(std.testing.allocator);
    try std.testing.expect(first.changed);
    try std.testing.expect(first.scope == .project);
    try std.testing.expectEqual(@as(usize, 1), first.added.len);
    try std.testing.expectEqualStrings("containers.docker", first.added[0]);

    const config = try tmp.dir.readFileAlloc(std.testing.io, ".orca.toml", std.testing.allocator, .limited(8192));
    defer std.testing.allocator.free(config);
    try std.testing.expect(std.mem.indexOf(u8, config, "containers.docker") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "package_managers") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "verbose = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "disabled = [\"system.disk\"]") != null or std.mem.indexOf(u8, config, "system.disk") != null);

    var second = try enablePacks(std.testing.io, std.testing.allocator, root, &.{"containers.docker"});
    defer second.deinit(std.testing.allocator);
    try std.testing.expect(!second.changed);
    try std.testing.expectEqual(@as(usize, 0), second.added.len);
}

test "enablePacks baseline notes and re-enables from disabled" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root_z = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root_z);
    const root = try std.testing.allocator.dupe(u8, root_z);
    defer std.testing.allocator.free(root);
    try tmp.dir.createDirPath(std.testing.io, ".git");

    const seed =
        \\[packs]
        \\enabled = []
        \\disabled = ["system.disk"]
        \\
    ;
    {
        const f = try tmp.dir.createFile(std.testing.io, ".orca.toml", .{});
        defer f.close(std.testing.io);
        try f.writeStreamingAll(std.testing.io, seed);
    }

    var result = try enablePacks(std.testing.io, std.testing.allocator, root, &.{ "core.git", "system.disk" });
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.changed);
    try std.testing.expect(result.baseline_notes.len >= 1);

    const config = try tmp.dir.readFileAlloc(std.testing.io, ".orca.toml", std.testing.allocator, .limited(8192));
    defer std.testing.allocator.free(config);
    const disabled = disabledArraySlice(config) orelse "";
    try std.testing.expect(std.mem.indexOf(u8, disabled, "system.disk") == null);
}

test "disablePacks removes opt-in and opts out baseline" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root_z = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root_z);
    const root = try std.testing.allocator.dupe(u8, root_z);
    defer std.testing.allocator.free(root);
    try tmp.dir.createDirPath(std.testing.io, ".git");

    const seed =
        \\[agents]
        \\claude = true
        \\
        \\[packs]
        \\enabled = ["containers.docker", "package_managers"]
        \\disabled = []
        \\
    ;
    {
        const f = try tmp.dir.createFile(std.testing.io, ".orca.toml", .{});
        defer f.close(std.testing.io);
        try f.writeStreamingAll(std.testing.io, seed);
    }

    var result = try disablePacks(std.testing.io, std.testing.allocator, root, &.{ "containers.docker", "system.disk" });
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.changed);
    try std.testing.expectEqual(@as(usize, 1), result.removed.len);
    try std.testing.expectEqualStrings("containers.docker", result.removed[0]);
    try std.testing.expectEqual(@as(usize, 1), result.disabled_added.len);
    try std.testing.expectEqualStrings("system.disk", result.disabled_added[0]);

    const config = try tmp.dir.readFileAlloc(std.testing.io, ".orca.toml", std.testing.allocator, .limited(8192));
    defer std.testing.allocator.free(config);
    try std.testing.expect(std.mem.indexOf(u8, config, "claude = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "package_managers") != null);
    const enabled = enabledArraySlice(config) orelse "";
    try std.testing.expect(std.mem.indexOf(u8, enabled, "containers.docker") == null);
    const disabled = disabledArraySlice(config) orelse "";
    try std.testing.expect(std.mem.indexOf(u8, disabled, "system.disk") != null);

    var again = try disablePacks(std.testing.io, std.testing.allocator, root, &.{"containers.docker"});
    defer again.deinit(std.testing.allocator);
    try std.testing.expect(!again.changed);
}

test "formatSummaryLine baseline invites packs enable" {
    const line = try formatSummaryLine(std.testing.allocator, .{
        .known = true,
        .total_enabled = 2,
        .total_available = 10,
        .opt_in_ids = &.{},
        .owned = false,
    });
    defer std.testing.allocator.free(line);
    try std.testing.expect(std.mem.indexOf(u8, line, "baseline only") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "packs enable") != null);
}
