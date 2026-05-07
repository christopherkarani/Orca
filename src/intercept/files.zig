const std = @import("std");

const audit = @import("../audit/mod.zig");
const core = @import("../core/mod.zig");
const policy = @import("../policy/mod.zig");

pub const max_staged_file_bytes: usize = 16 * 1024 * 1024;

pub const Operation = enum {
    create,
    update,
    delete,

    fn parse(value: []const u8) ?Operation {
        if (std.mem.eql(u8, value, "create")) return .create;
        if (std.mem.eql(u8, value, "update")) return .update;
        if (std.mem.eql(u8, value, "delete")) return .delete;
        return null;
    }

    fn toString(self: Operation) []const u8 {
        return @tagName(self);
    }
};

pub const NormalizedPath = struct {
    workspace_root: []u8,
    absolute_path: []u8,
    resolved_path: []u8,
    relative_path: []u8,
    policy_path: []u8,

    pub fn deinit(self: *NormalizedPath, allocator: std.mem.Allocator) void {
        allocator.free(self.workspace_root);
        allocator.free(self.absolute_path);
        allocator.free(self.resolved_path);
        allocator.free(self.relative_path);
        allocator.free(self.policy_path);
        self.* = undefined;
    }
};

pub const FileDecision = struct {
    normalized: ?NormalizedPath = null,
    decision: core.decision.Decision,
    owned_reason: []u8,
    owned_rule_id: ?[]u8 = null,

    pub fn deinit(self: *FileDecision, allocator: std.mem.Allocator) void {
        if (self.normalized) |*normalized| normalized.deinit(allocator);
        allocator.free(self.owned_reason);
        if (self.owned_rule_id) |rule_id| allocator.free(rule_id);
        self.* = undefined;
    }
};

pub const StagedEntry = struct {
    original_path: []u8,
    normalized_path: []u8,
    staged_path: []u8,
    original_hash: ?[]u8,
    staged_hash: ?[]u8,
    operation: Operation,
    timestamp: []u8,
    actor: []u8,

    pub fn deinit(self: *StagedEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.original_path);
        allocator.free(self.normalized_path);
        allocator.free(self.staged_path);
        if (self.original_hash) |hash| allocator.free(hash);
        if (self.staged_hash) |hash| allocator.free(hash);
        allocator.free(self.timestamp);
        allocator.free(self.actor);
        self.* = undefined;
    }
};

pub const StageResult = struct {
    entry: StagedEntry,
    session_dir: []u8,

    pub fn deinit(self: *StageResult, allocator: std.mem.Allocator) void {
        self.entry.deinit(allocator);
        allocator.free(self.session_dir);
        self.* = undefined;
    }
};

pub const ApplyDiscardResult = struct {
    count: usize,
};

pub const AuditContext = struct {
    writer: *audit.writer.SessionWriter,
    session: core.session.Session,
};

const BuiltinRule = struct {
    id: []const u8,
    pattern: []const u8,
};

const read_rules = [_]BuiltinRule{
    .{ .id = "builtin.files.read.deny[0]", .pattern = "./.env" },
    .{ .id = "builtin.files.read.deny[1]", .pattern = "./.env.*" },
    .{ .id = "builtin.files.read.deny[2]", .pattern = "~/.ssh/**" },
    .{ .id = "builtin.files.read.deny[3]", .pattern = "~/.aws/**" },
    .{ .id = "builtin.files.read.deny[4]", .pattern = "~/.gcloud/**" },
    .{ .id = "builtin.files.read.deny[5]", .pattern = "~/.azure/**" },
    .{ .id = "builtin.files.read.deny[6]", .pattern = "~/.config/gh/**" },
    .{ .id = "builtin.files.read.deny[7]", .pattern = "**/id_rsa" },
    .{ .id = "builtin.files.read.deny[8]", .pattern = "**/id_ed25519" },
    .{ .id = "builtin.files.read.deny[9]", .pattern = "**/*_rsa" },
    .{ .id = "builtin.files.read.deny[10]", .pattern = "**/*_ed25519" },
    .{ .id = "builtin.files.read.deny[11]", .pattern = "**/*credentials*" },
    .{ .id = "builtin.files.read.deny[12]", .pattern = "**/*credential*" },
    .{ .id = "builtin.files.read.deny[13]", .pattern = "**/*secret*" },
    .{ .id = "builtin.files.read.deny[14]", .pattern = "**/*token*" },
    .{ .id = "builtin.files.read.deny[15]", .pattern = "~/Library/Keychains/**" },
    .{ .id = "builtin.files.read.deny[16]", .pattern = "./Library/Keychains/**" },
    .{ .id = "builtin.files.read.deny[17]", .pattern = "~/Library/Application Support/**/Cookies*" },
    .{ .id = "builtin.files.read.deny[18]", .pattern = "./Library/Application Support/**/Cookies*" },
    .{ .id = "builtin.files.read.deny[19]", .pattern = "~/Library/Application Support/**/Login Data*" },
    .{ .id = "builtin.files.read.deny[20]", .pattern = "./Library/Application Support/**/Login Data*" },
    .{ .id = "builtin.files.read.deny[21]", .pattern = "~/Library/Application Support/Google/Chrome/**" },
    .{ .id = "builtin.files.read.deny[22]", .pattern = "./Library/Application Support/Google/Chrome/**" },
    .{ .id = "builtin.files.read.deny[23]", .pattern = "~/Library/Application Support/BraveSoftware/**" },
    .{ .id = "builtin.files.read.deny[24]", .pattern = "./Library/Application Support/BraveSoftware/**" },
    .{ .id = "builtin.files.read.deny[25]", .pattern = "~/Library/Application Support/Firefox/**" },
    .{ .id = "builtin.files.read.deny[26]", .pattern = "./Library/Application Support/Firefox/**" },
    .{ .id = "builtin.files.read.deny[27]", .pattern = "~/Library/Mobile Documents/**" },
    .{ .id = "builtin.files.read.deny[28]", .pattern = "./Library/Mobile Documents/**" },
    .{ .id = "builtin.files.read.deny[29]", .pattern = "~/.zsh_history" },
    .{ .id = "builtin.files.read.deny[30]", .pattern = "~/.bash_history" },
    .{ .id = "builtin.files.read.deny[31]", .pattern = "~/.zshrc" },
    .{ .id = "builtin.files.read.deny[32]", .pattern = "~/.bashrc" },
    .{ .id = "builtin.files.read.deny[33]", .pattern = "~/.profile" },
};

const write_rules = [_]BuiltinRule{
    .{ .id = "builtin.files.write.deny[0]", .pattern = "./.git/**" },
    .{ .id = "builtin.files.write.deny[1]", .pattern = "./.aegis/**" },
};

pub fn normalizePath(allocator: std.mem.Allocator, workspace_root_raw: []const u8, raw_path: []const u8) !NormalizedPath {
    if (raw_path.len == 0 or std.mem.indexOfScalar(u8, raw_path, 0) != null) return error.InvalidPath;
    if (!std.unicode.utf8ValidateSlice(raw_path)) return error.InvalidUtf8;

    const workspace_root = try std.fs.cwd().realpathAlloc(allocator, workspace_root_raw);
    errdefer allocator.free(workspace_root);

    const expanded = try expandHome(allocator, raw_path);
    defer allocator.free(expanded);

    const absolute_path = try lexicalAbsolute(allocator, workspace_root, expanded);
    errdefer allocator.free(absolute_path);

    const resolved_path = try resolveExistingPrefix(allocator, absolute_path);
    errdefer allocator.free(resolved_path);

    if (!isWithin(workspace_root, absolute_path)) return error.OutsideWorkspace;
    if (!isWithin(workspace_root, resolved_path)) return error.SymlinkEscapesWorkspace;

    const relative_path = try relativeFromWorkspace(allocator, workspace_root, resolved_path);
    errdefer allocator.free(relative_path);
    if (relative_path.len == 0) return error.InvalidPath;

    const policy_path = try std.fmt.allocPrint(allocator, "./{s}", .{relative_path});
    errdefer allocator.free(policy_path);

    return .{
        .workspace_root = workspace_root,
        .absolute_path = absolute_path,
        .resolved_path = resolved_path,
        .relative_path = relative_path,
        .policy_path = policy_path,
    };
}

pub fn decideRead(allocator: std.mem.Allocator, loaded_policy: *const policy.schema.Policy, workspace_root: []const u8, raw_path: []const u8) !FileDecision {
    var normalized = normalizePath(allocator, workspace_root, raw_path) catch {
        if (rawBuiltinReadRule(raw_path)) |rule| {
            const reason = try std.fmt.allocPrint(allocator, "matched {s} rule \"{s}\"", .{ rule.id, rule.pattern });
            return denyWithReasonOnly(allocator, rule.id, reason);
        }
        return deniedDecision(allocator, null, "builtin.files.read.deny[outside_workspace]", "file read denied: path resolves outside workspace or through a symlink escape");
    };
    errdefer normalized.deinit(allocator);

    var evaluation = try policy.evaluate.fileRead(loaded_policy, normalized.policy_path, allocator);
    defer evaluation.deinit(allocator);

    if (builtinReadRule(normalized.policy_path, normalized.resolved_path)) |rule| {
        return denyWithNormalized(allocator, normalized, rule.id, try std.fmt.allocPrint(allocator, "matched {s} rule \"{s}\"", .{ rule.id, rule.pattern }));
    }

    return decisionFromEvaluation(allocator, normalized, evaluation);
}

pub fn decideWrite(allocator: std.mem.Allocator, loaded_policy: *const policy.schema.Policy, workspace_root: []const u8, raw_path: []const u8) !FileDecision {
    var normalized = normalizePath(allocator, workspace_root, raw_path) catch {
        return deniedDecision(allocator, null, "builtin.files.write.deny[outside_workspace]", "file write denied: path resolves outside workspace or through a symlink escape");
    };
    errdefer normalized.deinit(allocator);

    var evaluation = try policy.evaluate.fileWrite(loaded_policy, normalized.policy_path, allocator);
    defer evaluation.deinit(allocator);

    if (builtinWriteRule(normalized.policy_path)) |rule| {
        return denyWithNormalized(allocator, normalized, rule.id, try std.fmt.allocPrint(allocator, "matched {s} rule \"{s}\"", .{ rule.id, rule.pattern }));
    }

    return decisionFromEvaluation(allocator, normalized, evaluation);
}

pub fn stageCreate(
    allocator: std.mem.Allocator,
    loaded_policy: *const policy.schema.Policy,
    workspace_root: []const u8,
    session_id: []const u8,
    raw_path: []const u8,
    bytes: []const u8,
    audit_context: ?AuditContext,
) !StageResult {
    var normalized = try normalizePath(allocator, workspace_root, raw_path);
    defer normalized.deinit(allocator);
    if (fileExists(normalized.resolved_path)) return error.PathAlreadyExists;
    return stageBytes(allocator, loaded_policy, workspace_root, session_id, raw_path, bytes, audit_context);
}

pub fn stageUpdate(
    allocator: std.mem.Allocator,
    loaded_policy: *const policy.schema.Policy,
    workspace_root: []const u8,
    session_id: []const u8,
    raw_path: []const u8,
    bytes: []const u8,
    audit_context: ?AuditContext,
) !StageResult {
    var normalized = try normalizePath(allocator, workspace_root, raw_path);
    defer normalized.deinit(allocator);
    if (!fileExists(normalized.resolved_path)) return error.FileNotFound;
    return stageBytes(allocator, loaded_policy, workspace_root, session_id, raw_path, bytes, audit_context);
}

pub fn stageWrite(
    allocator: std.mem.Allocator,
    loaded_policy: *const policy.schema.Policy,
    workspace_root: []const u8,
    session_id: []const u8,
    raw_path: []const u8,
    bytes: []const u8,
    audit_context: ?AuditContext,
) !StageResult {
    return stageBytes(allocator, loaded_policy, workspace_root, session_id, raw_path, bytes, audit_context);
}

pub fn stageDelete(
    allocator: std.mem.Allocator,
    loaded_policy: *const policy.schema.Policy,
    workspace_root: []const u8,
    session_id: []const u8,
    raw_path: []const u8,
    audit_context: ?AuditContext,
) !StageResult {
    var decision = try decideWrite(allocator, loaded_policy, workspace_root, raw_path);
    defer decision.deinit(allocator);
    try auditFileEvent(audit_context, .file_write_attempt, raw_path, decision.decision);
    if (!isWriteAllowed(decision.decision.result)) {
        try auditFileEvent(audit_context, .file_write_denied, raw_path, decision.decision);
        return error.WriteDenied;
    }

    const normalized = decision.normalized.?;
    if (!fileExists(normalized.resolved_path)) return error.FileNotFound;

    const session_dir = try sessionDirPath(allocator, workspace_root, session_id);
    errdefer allocator.free(session_dir);
    try ensureStagingDirs(session_dir);

    const original_bytes = try std.fs.cwd().readFileAlloc(allocator, normalized.resolved_path, max_staged_file_bytes);
    defer allocator.free(original_bytes);
    const original_hash = try sha256HexAlloc(allocator, original_bytes);
    errdefer allocator.free(original_hash);
    try writeSessionRelFile(session_dir, "original", normalized.relative_path, original_bytes);

    var index = try loadIndex(allocator, session_dir);
    defer index.deinit();
    try index.upsert(.{
        .original_path = try allocator.dupe(u8, normalized.resolved_path),
        .normalized_path = try allocator.dupe(u8, normalized.relative_path),
        .staged_path = try stagedPathForEntry(allocator, session_dir, normalized.relative_path),
        .original_hash = original_hash,
        .staged_hash = null,
        .operation = .delete,
        .timestamp = try timestampNowAlloc(allocator),
        .actor = try allocator.dupe(u8, "aegis"),
    });
    try writeIndex(allocator, session_dir, session_id, index.entries.items);
    try auditFileEvent(audit_context, .file_write_staged, normalized.policy_path, .{
        .result = .stage,
        .rule_id = decision.decision.rule_id,
        .reason = "delete staged for review",
        .ci_may_proceed = true,
    });

    return .{ .entry = try cloneEntry(allocator, index.find(normalized.relative_path).?), .session_dir = session_dir };
}

pub fn diffStaged(allocator: std.mem.Allocator, workspace_root: []const u8, session_id: []const u8, optional_file: ?[]const u8) ![]u8 {
    const session_dir = try sessionDirPath(allocator, workspace_root, session_id);
    defer allocator.free(session_dir);
    var index = try loadIndex(allocator, session_dir);
    defer index.deinit();

    const normalized_filter = if (optional_file) |file| blk: {
        var normalized = try normalizePath(allocator, workspace_root, file);
        defer normalized.deinit(allocator);
        break :blk try allocator.dupe(u8, normalized.relative_path);
    } else null;
    defer if (normalized_filter) |filter| allocator.free(filter);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    for (index.entries.items) |entry| {
        if (normalized_filter) |filter| {
            if (!std.mem.eql(u8, filter, entry.normalized_path)) continue;
        }
        try appendEntryDiff(allocator, &out, session_dir, entry);
    }
    return try out.toOwnedSlice(allocator);
}

pub fn applyStaged(allocator: std.mem.Allocator, workspace_root: []const u8, session_id: []const u8, optional_file: ?[]const u8, audit_context: ?AuditContext) !ApplyDiscardResult {
    return applyOrDiscard(allocator, workspace_root, session_id, optional_file, true, audit_context);
}

pub fn discardStaged(allocator: std.mem.Allocator, workspace_root: []const u8, session_id: []const u8, optional_file: ?[]const u8, audit_context: ?AuditContext) !ApplyDiscardResult {
    return applyOrDiscard(allocator, workspace_root, session_id, optional_file, false, audit_context);
}

pub fn resolveSessionId(allocator: std.mem.Allocator, workspace_root: []const u8, requested: []const u8) ![]u8 {
    if (!std.mem.eql(u8, requested, "last")) return try allocator.dupe(u8, requested);
    const last_path = try std.fs.path.join(allocator, &.{ workspace_root, ".aegis", "last" });
    defer allocator.free(last_path);
    const text = try std.fs.cwd().readFileAlloc(allocator, last_path, core.limits.max_session_id_len + 2);
    defer allocator.free(text);
    return try allocator.dupe(u8, std.mem.trim(u8, text, " \t\r\n"));
}

fn stageBytes(
    allocator: std.mem.Allocator,
    loaded_policy: *const policy.schema.Policy,
    workspace_root: []const u8,
    session_id: []const u8,
    raw_path: []const u8,
    bytes: []const u8,
    audit_context: ?AuditContext,
) !StageResult {
    if (bytes.len > max_staged_file_bytes) return error.FileTooLarge;

    var decision = try decideWrite(allocator, loaded_policy, workspace_root, raw_path);
    defer decision.deinit(allocator);
    try auditFileEvent(audit_context, .file_write_attempt, raw_path, decision.decision);
    if (!isWriteAllowed(decision.decision.result)) {
        try auditFileEvent(audit_context, .file_write_denied, raw_path, decision.decision);
        return error.WriteDenied;
    }

    const normalized = decision.normalized.?;
    const session_dir = try sessionDirPath(allocator, workspace_root, session_id);
    errdefer allocator.free(session_dir);
    try ensureStagingDirs(session_dir);

    const existed = fileExists(normalized.resolved_path);
    var original_hash: ?[]u8 = null;
    errdefer if (original_hash) |hash| allocator.free(hash);
    if (existed) {
        const original_bytes = try std.fs.cwd().readFileAlloc(allocator, normalized.resolved_path, max_staged_file_bytes);
        defer allocator.free(original_bytes);
        original_hash = try sha256HexAlloc(allocator, original_bytes);
        try writeSessionRelFile(session_dir, "original", normalized.relative_path, original_bytes);
    }

    try writeSessionRelFile(session_dir, "staged", normalized.relative_path, bytes);
    const staged_hash = try sha256HexAlloc(allocator, bytes);
    errdefer allocator.free(staged_hash);

    const staged_path = try stagedPathForEntry(allocator, session_dir, normalized.relative_path);
    errdefer allocator.free(staged_path);

    var index = try loadIndex(allocator, session_dir);
    defer index.deinit();
    try index.upsert(.{
        .original_path = try allocator.dupe(u8, normalized.resolved_path),
        .normalized_path = try allocator.dupe(u8, normalized.relative_path),
        .staged_path = staged_path,
        .original_hash = original_hash,
        .staged_hash = staged_hash,
        .operation = if (existed) .update else .create,
        .timestamp = try timestampNowAlloc(allocator),
        .actor = try allocator.dupe(u8, "aegis"),
    });
    original_hash = null;
    try writeIndex(allocator, session_dir, session_id, index.entries.items);

    try auditFileEvent(audit_context, .file_write_staged, normalized.policy_path, .{
        .result = .stage,
        .rule_id = decision.decision.rule_id,
        .reason = "write staged for review",
        .ci_may_proceed = true,
    });

    return .{ .entry = try cloneEntry(allocator, index.find(normalized.relative_path).?), .session_dir = session_dir };
}

fn applyOrDiscard(
    allocator: std.mem.Allocator,
    workspace_root: []const u8,
    session_id: []const u8,
    optional_file: ?[]const u8,
    comptime apply: bool,
    audit_context: ?AuditContext,
) !ApplyDiscardResult {
    const session_dir = try sessionDirPath(allocator, workspace_root, session_id);
    defer allocator.free(session_dir);
    var index = try loadIndex(allocator, session_dir);
    defer index.deinit();

    const normalized_filter = if (optional_file) |file| blk: {
        var normalized = try normalizePath(allocator, workspace_root, file);
        defer normalized.deinit(allocator);
        break :blk try allocator.dupe(u8, normalized.relative_path);
    } else null;
    defer if (normalized_filter) |filter| allocator.free(filter);

    var remaining: std.ArrayList(StagedEntry) = .empty;
    defer {
        for (remaining.items) |*entry| entry.deinit(allocator);
        remaining.deinit(allocator);
    }

    var count: usize = 0;
    for (index.entries.items) |entry| {
        const selected = if (normalized_filter) |filter| std.mem.eql(u8, filter, entry.normalized_path) else true;
        if (!selected) {
            try remaining.append(allocator, try cloneEntry(allocator, entry));
            continue;
        }

        if (apply) {
            try verifyOriginalState(allocator, entry);
            switch (entry.operation) {
                .create, .update => {
                    const staged_bytes = try readVerifiedStagedBytes(allocator, entry);
                    defer allocator.free(staged_bytes);
                    try ensureParentPath(entry.original_path);
                    try writeAbsoluteFile(entry.original_path, staged_bytes);
                },
                .delete => std.fs.cwd().deleteFile(entry.original_path) catch |err| switch (err) {
                    error.FileNotFound => {},
                    else => return err,
                },
            }
            try auditFileEvent(audit_context, .file_apply, entry.normalized_path, .{ .result = .allow, .reason = "staged file applied", .ci_may_proceed = true });
        } else {
            try auditFileEvent(audit_context, .file_discard, entry.normalized_path, .{ .result = .allow, .reason = "staged file discarded", .ci_may_proceed = true });
        }

        cleanupEntryFiles(session_dir, entry.normalized_path);
        count += 1;
    }

    try writeIndex(allocator, session_dir, session_id, remaining.items);
    return .{ .count = count };
}

fn appendEntryDiff(allocator: std.mem.Allocator, out: *std.ArrayList(u8), session_dir: []const u8, entry: StagedEntry) !void {
    var old_bytes_owned = false;
    const old_bytes = switch (entry.operation) {
        .create => "",
        .update, .delete => blk: {
            const original_capture = try originalPathForEntry(allocator, session_dir, entry.normalized_path);
            defer allocator.free(original_capture);
            old_bytes_owned = true;
            break :blk try std.fs.cwd().readFileAlloc(allocator, original_capture, max_staged_file_bytes);
        },
    };
    defer if (old_bytes_owned) allocator.free(old_bytes);

    const new_bytes = switch (entry.operation) {
        .delete => "",
        .create, .update => try std.fs.cwd().readFileAlloc(allocator, entry.staged_path, max_staged_file_bytes),
    };
    defer if (entry.operation != .delete) allocator.free(new_bytes);

    if (entry.operation == .create) {
        try out.writer(allocator).print("--- /dev/null\n+++ b/{s}\n", .{entry.normalized_path});
    } else if (entry.operation == .delete) {
        try out.writer(allocator).print("--- a/{s}\n+++ /dev/null\n", .{entry.normalized_path});
    } else {
        try out.writer(allocator).print("--- a/{s}\n+++ b/{s}\n", .{ entry.normalized_path, entry.normalized_path });
    }
    try out.appendSlice(allocator, "@@\n");
    try appendPrefixedLines(allocator, out, '-', old_bytes);
    try appendPrefixedLines(allocator, out, '+', new_bytes);
}

fn appendPrefixedLines(allocator: std.mem.Allocator, out: *std.ArrayList(u8), prefix: u8, bytes: []const u8) !void {
    if (bytes.len == 0) return;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (line.len == 0 and lines.index == null) continue;
        try out.append(allocator, prefix);
        try out.appendSlice(allocator, line);
        try out.append(allocator, '\n');
    }
}

fn verifyOriginalState(allocator: std.mem.Allocator, entry: StagedEntry) !void {
    if (entry.original_hash) |expected| {
        const bytes = try std.fs.cwd().readFileAlloc(allocator, entry.original_path, max_staged_file_bytes);
        defer allocator.free(bytes);
        const actual = try sha256HexAlloc(allocator, bytes);
        defer allocator.free(actual);
        if (!std.mem.eql(u8, expected, actual)) return error.OriginalChanged;
    } else if (fileExists(entry.original_path)) {
        return error.OriginalChanged;
    }
}

fn readVerifiedStagedBytes(allocator: std.mem.Allocator, entry: StagedEntry) ![]u8 {
    const expected = entry.staged_hash orelse return error.StagedChanged;
    const bytes = try std.fs.cwd().readFileAlloc(allocator, entry.staged_path, max_staged_file_bytes);
    errdefer allocator.free(bytes);
    const actual = try sha256HexAlloc(allocator, bytes);
    defer allocator.free(actual);
    if (!std.mem.eql(u8, expected, actual)) return error.StagedChanged;
    return bytes;
}

fn cleanupEntryFiles(session_dir: []const u8, relative_path: []const u8) void {
    const allocator = std.heap.page_allocator;
    const staged_path = std.fs.path.join(allocator, &.{ session_dir, "staged", relative_path }) catch return;
    defer allocator.free(staged_path);
    std.fs.cwd().deleteFile(staged_path) catch {};
    const original_path = std.fs.path.join(allocator, &.{ session_dir, "original", relative_path }) catch return;
    defer allocator.free(original_path);
    std.fs.cwd().deleteFile(original_path) catch {};
}

const Index = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(StagedEntry),

    fn deinit(self: *Index) void {
        for (self.entries.items) |*entry| entry.deinit(self.allocator);
        self.entries.deinit(self.allocator);
        self.* = undefined;
    }

    fn upsert(self: *Index, new_entry: StagedEntry) !void {
        for (self.entries.items) |*entry| {
            if (std.mem.eql(u8, entry.normalized_path, new_entry.normalized_path)) {
                entry.deinit(self.allocator);
                entry.* = new_entry;
                return;
            }
        }
        try self.entries.append(self.allocator, new_entry);
    }

    fn find(self: *Index, relative_path: []const u8) ?StagedEntry {
        for (self.entries.items) |entry| {
            if (std.mem.eql(u8, entry.normalized_path, relative_path)) return entry;
        }
        return null;
    }
};

fn loadIndex(allocator: std.mem.Allocator, session_dir: []const u8) !Index {
    var index: Index = .{ .allocator = allocator, .entries = .empty };
    errdefer index.deinit();

    const path = try std.fs.path.join(allocator, &.{ session_dir, "staging-index.json" });
    defer allocator.free(path);
    const text = std.fs.cwd().readFileAlloc(allocator, path, core.limits.max_mcp_message_len) catch |err| switch (err) {
        error.FileNotFound => return index,
        else => return err,
    };
    defer allocator.free(text);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, text, .{});
    defer parsed.deinit();
    const object = parsed.value.object;
    const entries = object.get("entries") orelse return error.InvalidStagingIndex;
    if (entries != .array) return error.InvalidStagingIndex;
    for (entries.array.items) |item| {
        if (item != .object) return error.InvalidStagingIndex;
        const entry_object = item.object;
        const operation_text = try jsonString(entry_object.get("operation") orelse return error.InvalidStagingIndex);
        try index.entries.append(allocator, .{
            .original_path = try allocator.dupe(u8, try jsonString(entry_object.get("original_path") orelse return error.InvalidStagingIndex)),
            .normalized_path = try allocator.dupe(u8, try jsonString(entry_object.get("normalized_path") orelse return error.InvalidStagingIndex)),
            .staged_path = try allocator.dupe(u8, try jsonString(entry_object.get("staged_path") orelse return error.InvalidStagingIndex)),
            .original_hash = try jsonNullableStringAlloc(allocator, entry_object.get("original_hash") orelse return error.InvalidStagingIndex),
            .staged_hash = try jsonNullableStringAlloc(allocator, entry_object.get("staged_hash") orelse return error.InvalidStagingIndex),
            .operation = Operation.parse(operation_text) orelse return error.InvalidStagingIndex,
            .timestamp = try allocator.dupe(u8, try jsonString(entry_object.get("timestamp") orelse return error.InvalidStagingIndex)),
            .actor = try allocator.dupe(u8, try jsonString(entry_object.get("actor") orelse return error.InvalidStagingIndex)),
        });
    }
    return index;
}

fn writeIndex(allocator: std.mem.Allocator, session_dir: []const u8, session_id: []const u8, entries: []const StagedEntry) !void {
    try ensureStagingDirs(session_dir);
    const path = try std.fs.path.join(allocator, &.{ session_dir, "staging-index.json" });
    defer allocator.free(path);

    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);
    const writer = list.writer(allocator);
    try writer.print("{{\"version\":1,\"session_id\":", .{});
    try core.util.writeJsonString(writer, session_id);
    try writer.writeAll(",\"entries\":[");
    for (entries, 0..) |entry, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.writeAll("{\"original_path\":");
        try core.util.writeJsonString(writer, entry.original_path);
        try writer.writeAll(",\"normalized_path\":");
        try core.util.writeJsonString(writer, entry.normalized_path);
        try writer.writeAll(",\"staged_path\":");
        try core.util.writeJsonString(writer, entry.staged_path);
        try writer.writeAll(",\"original_hash\":");
        try writeNullableJsonString(writer, entry.original_hash);
        try writer.writeAll(",\"staged_hash\":");
        try writeNullableJsonString(writer, entry.staged_hash);
        try writer.writeAll(",\"operation\":");
        try core.util.writeJsonString(writer, entry.operation.toString());
        try writer.writeAll(",\"timestamp\":");
        try core.util.writeJsonString(writer, entry.timestamp);
        try writer.writeAll(",\"actor\":");
        try core.util.writeJsonString(writer, entry.actor);
        try writer.writeByte('}');
    }
    try writer.writeAll("]}");

    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(list.items);
    try file.writeAll("\n");
    try file.sync();
}

fn writeNullableJsonString(writer: anytype, value: ?[]const u8) !void {
    if (value) |string| try core.util.writeJsonString(writer, string) else try writer.writeAll("null");
}

fn jsonString(value: std.json.Value) ![]const u8 {
    return switch (value) {
        .string => |string| string,
        else => error.InvalidStagingIndex,
    };
}

fn jsonNullableStringAlloc(allocator: std.mem.Allocator, value: std.json.Value) !?[]u8 {
    if (value == .null) return null;
    return try allocator.dupe(u8, try jsonString(value));
}

fn cloneEntry(allocator: std.mem.Allocator, entry: StagedEntry) !StagedEntry {
    return .{
        .original_path = try allocator.dupe(u8, entry.original_path),
        .normalized_path = try allocator.dupe(u8, entry.normalized_path),
        .staged_path = try allocator.dupe(u8, entry.staged_path),
        .original_hash = if (entry.original_hash) |hash| try allocator.dupe(u8, hash) else null,
        .staged_hash = if (entry.staged_hash) |hash| try allocator.dupe(u8, hash) else null,
        .operation = entry.operation,
        .timestamp = try allocator.dupe(u8, entry.timestamp),
        .actor = try allocator.dupe(u8, entry.actor),
    };
}

fn auditFileEvent(audit_context: ?AuditContext, event_type: core.event.EventType, target: []const u8, decision: core.decision.Decision) !void {
    const ctx = audit_context orelse return;
    const ts = core.time.Timestamp.now();
    const ev: core.event.Event = .{
        .session_id = ctx.session.id,
        .event_id = try core.event.generateEventId(ts),
        .timestamp = ts,
        .event_type = event_type,
        .actor = .{ .kind = .aegis, .display = "aegis" },
        .target = .{ .kind = .file_path, .value = target },
        .decision = decision,
    };
    try ctx.writer.appendEvent(ev);
}

fn deniedDecision(allocator: std.mem.Allocator, normalized: ?NormalizedPath, rule_id: []const u8, reason: []const u8) !FileDecision {
    const owned_reason = try allocator.dupe(u8, reason);
    errdefer allocator.free(owned_reason);
    const owned_rule_id = try allocator.dupe(u8, rule_id);
    return .{
        .normalized = normalized,
        .decision = .{
            .result = .deny,
            .rule_id = owned_rule_id,
            .reason = owned_reason,
            .ci_may_proceed = false,
        },
        .owned_reason = owned_reason,
        .owned_rule_id = owned_rule_id,
    };
}

fn denyWithReasonOnly(allocator: std.mem.Allocator, rule_id: []const u8, owned_reason: []u8) !FileDecision {
    errdefer allocator.free(owned_reason);
    const owned_rule_id = try allocator.dupe(u8, rule_id);
    return .{
        .decision = .{ .result = .deny, .rule_id = owned_rule_id, .reason = owned_reason, .ci_may_proceed = false },
        .owned_reason = owned_reason,
        .owned_rule_id = owned_rule_id,
    };
}

fn denyWithNormalized(allocator: std.mem.Allocator, normalized: NormalizedPath, rule_id: []const u8, owned_reason: []u8) !FileDecision {
    errdefer allocator.free(owned_reason);
    const owned_rule_id = try allocator.dupe(u8, rule_id);
    return .{
        .normalized = normalized,
        .decision = .{ .result = .deny, .rule_id = owned_rule_id, .reason = owned_reason, .ci_may_proceed = false },
        .owned_reason = owned_reason,
        .owned_rule_id = owned_rule_id,
    };
}

fn decisionFromEvaluation(allocator: std.mem.Allocator, normalized: NormalizedPath, evaluation: policy.schema.Evaluation) !FileDecision {
    const owned_reason = try allocator.dupe(u8, evaluation.decision.reason);
    errdefer allocator.free(owned_reason);
    const owned_rule_id = if (evaluation.decision.rule_id) |rule_id| try allocator.dupe(u8, rule_id) else null;
    return .{
        .normalized = normalized,
        .decision = .{
            .result = evaluation.decision.result,
            .rule_id = owned_rule_id,
            .reason = owned_reason,
            .risk_score = evaluation.decision.risk_score,
            .requires_user = evaluation.decision.requires_user,
            .ci_may_proceed = evaluation.decision.ci_may_proceed,
        },
        .owned_reason = owned_reason,
        .owned_rule_id = owned_rule_id,
    };
}

fn builtinReadRule(policy_path: []const u8, resolved_path: []const u8) ?BuiltinRule {
    for (read_rules) |rule| {
        if (matchesRule(rule.pattern, policy_path) or homeRuleMatches(rule.pattern, resolved_path)) return rule;
    }
    return null;
}

fn rawBuiltinReadRule(raw_path: []const u8) ?BuiltinRule {
    for (read_rules) |rule| {
        if (matchesRule(rule.pattern, raw_path)) return rule;
    }
    return null;
}

fn builtinWriteRule(policy_path: []const u8) ?BuiltinRule {
    for (write_rules) |rule| {
        if (matchesRule(rule.pattern, policy_path)) return rule;
    }
    return null;
}

fn matchesRule(pattern: []const u8, value: []const u8) bool {
    return simpleGlob(pattern, value);
}

fn simpleGlob(pattern: []const u8, value: []const u8) bool {
    return simpleGlobAt(pattern, 0, value, 0);
}

fn simpleGlobAt(pattern: []const u8, pattern_index: usize, value: []const u8, value_index: usize) bool {
    var p = pattern_index;
    var v = value_index;
    while (p < pattern.len) {
        switch (pattern[p]) {
            '*' => {
                while (p + 1 < pattern.len and pattern[p + 1] == '*') p += 1;
                if (p + 1 == pattern.len) return true;
                var next = v;
                while (next <= value.len) : (next += 1) {
                    if (simpleGlobAt(pattern, p + 1, value, next)) return true;
                }
                return false;
            },
            '?' => {
                if (v >= value.len) return false;
                p += 1;
                v += 1;
            },
            else => |char| {
                if (v >= value.len or std.ascii.toLower(value[v]) != std.ascii.toLower(char)) return false;
                p += 1;
                v += 1;
            },
        }
    }
    return v == value.len;
}

fn homeRuleMatches(pattern: []const u8, path: []const u8) bool {
    if (!std.mem.startsWith(u8, pattern, "~/")) return false;
    const home = std.process.getEnvVarOwned(std.heap.page_allocator, "HOME") catch return false;
    defer std.heap.page_allocator.free(home);
    if (homeRuleMatchesRoot(pattern, path, home)) return true;
    const real_home = std.fs.cwd().realpathAlloc(std.heap.page_allocator, home) catch return false;
    defer std.heap.page_allocator.free(real_home);
    return homeRuleMatchesRoot(pattern, path, real_home);
}

fn homeRuleMatchesRoot(pattern: []const u8, path: []const u8, home: []const u8) bool {
    if (!isWithin(home, path)) return false;
    if (path.len == home.len) return std.mem.eql(u8, pattern, "~");
    if (path[home.len] != '/') return false;
    return matchesRule(pattern[1..], path[home.len..]);
}

fn isWriteAllowed(result: core.decision.DecisionResult) bool {
    return result == .allow or result == .observe or result == .stage;
}

fn expandHome(allocator: std.mem.Allocator, raw_path: []const u8) ![]u8 {
    if (std.mem.eql(u8, raw_path, "~") or std.mem.startsWith(u8, raw_path, "~/")) {
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch return try allocator.dupe(u8, raw_path);
        defer allocator.free(home);
        if (std.mem.eql(u8, raw_path, "~")) return try allocator.dupe(u8, home);
        return try std.fs.path.join(allocator, &.{ home, raw_path[2..] });
    }
    return try allocator.dupe(u8, raw_path);
}

fn lexicalAbsolute(allocator: std.mem.Allocator, workspace_root: []const u8, path: []const u8) ![]u8 {
    var components: std.ArrayList([]u8) = .empty;
    defer {
        for (components.items) |component| allocator.free(component);
        components.deinit(allocator);
    }

    if (!std.fs.path.isAbsolute(path)) try appendComponents(allocator, &components, workspace_root);
    try appendComponents(allocator, &components, path);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    if (components.items.len == 0) try out.append(allocator, std.fs.path.sep);
    for (components.items) |component| {
        try out.append(allocator, std.fs.path.sep);
        try out.appendSlice(allocator, component);
    }
    return try out.toOwnedSlice(allocator);
}

fn appendComponents(allocator: std.mem.Allocator, components: *std.ArrayList([]u8), path: []const u8) !void {
    var it = std.mem.tokenizeAny(u8, path, "/\\");
    while (it.next()) |component| {
        if (std.mem.eql(u8, component, ".")) continue;
        if (std.mem.eql(u8, component, "..")) {
            if (components.items.len == 0) return error.OutsideWorkspace;
            allocator.free(components.pop().?);
            continue;
        }
        try components.append(allocator, try allocator.dupe(u8, component));
    }
}

fn resolveExistingPrefix(allocator: std.mem.Allocator, absolute_path: []const u8) ![]u8 {
    var current = try allocator.dupe(u8, absolute_path);
    defer allocator.free(current);
    var suffix: std.ArrayList([]u8) = .empty;
    defer {
        for (suffix.items) |part| allocator.free(part);
        suffix.deinit(allocator);
    }

    while (true) {
        const resolved = std.fs.cwd().realpathAlloc(allocator, current) catch |err| switch (err) {
            error.FileNotFound => null,
            error.NotDir => null,
            else => return err,
        };
        if (resolved) |prefix| {
            if (suffix.items.len == 0) return prefix;
            var parts = try allocator.alloc([]const u8, suffix.items.len + 1);
            defer allocator.free(parts);
            parts[0] = prefix;
            for (suffix.items, 0..) |part, index| parts[suffix.items.len - index] = part;
            defer allocator.free(prefix);
            return try std.fs.path.join(allocator, parts);
        }

        const parent = std.fs.path.dirname(current) orelse return error.FileNotFound;
        const base = std.fs.path.basename(current);
        try suffix.append(allocator, try allocator.dupe(u8, base));
        const next = try allocator.dupe(u8, parent);
        allocator.free(current);
        current = next;
    }
}

fn isWithin(root: []const u8, path: []const u8) bool {
    if (std.mem.eql(u8, root, path)) return true;
    if (path.len <= root.len) return false;
    if (!std.mem.eql(u8, path[0..root.len], root)) return false;
    return path[root.len] == std.fs.path.sep;
}

fn relativeFromWorkspace(allocator: std.mem.Allocator, workspace_root: []const u8, path: []const u8) ![]u8 {
    if (!isWithin(workspace_root, path)) return error.OutsideWorkspace;
    if (path.len == workspace_root.len) return try allocator.dupe(u8, "");
    const rel_native = path[workspace_root.len + 1 ..];
    return normalizeSeparatorsAlloc(allocator, rel_native);
}

fn normalizeSeparatorsAlloc(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    const out = try allocator.dupe(u8, value);
    for (out) |*char| {
        if (char.* == '\\') char.* = '/';
    }
    return out;
}

fn sessionDirPath(allocator: std.mem.Allocator, workspace_root: []const u8, session_id: []const u8) ![]u8 {
    return try std.fs.path.join(allocator, &.{ workspace_root, ".aegis", "sessions", session_id });
}

fn ensureStagingDirs(session_dir: []const u8) !void {
    try std.fs.cwd().makePath(session_dir);
    const allocator = std.heap.page_allocator;
    const staged = try std.fs.path.join(allocator, &.{ session_dir, "staged" });
    defer allocator.free(staged);
    try std.fs.cwd().makePath(staged);
    const original = try std.fs.path.join(allocator, &.{ session_dir, "original" });
    defer allocator.free(original);
    try std.fs.cwd().makePath(original);
}

fn stagedPathForEntry(allocator: std.mem.Allocator, session_dir: []const u8, relative_path: []const u8) ![]u8 {
    return try std.fs.path.join(allocator, &.{ session_dir, "staged", relative_path });
}

fn originalPathForEntry(allocator: std.mem.Allocator, session_dir: []const u8, relative_path: []const u8) ![]u8 {
    return try std.fs.path.join(allocator, &.{ session_dir, "original", relative_path });
}

fn writeSessionRelFile(session_dir: []const u8, bucket: []const u8, relative_path: []const u8, bytes: []const u8) !void {
    const allocator = std.heap.page_allocator;
    const path = try std.fs.path.join(allocator, &.{ session_dir, bucket, relative_path });
    defer allocator.free(path);
    try ensureParentPath(path);
    try writeAbsoluteFile(path, bytes);
}

fn ensureParentPath(path: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse return;
    try std.fs.cwd().makePath(parent);
}

fn writeAbsoluteFile(path: []const u8, bytes: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(bytes);
    try file.sync();
}

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn sha256HexAlloc(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const out = try allocator.alloc(u8, 64);
    _ = std.fmt.bytesToHex(digest, .lower);
    const hex = std.fmt.bytesToHex(digest, .lower);
    @memcpy(out, &hex);
    return out;
}

fn timestampNowAlloc(allocator: std.mem.Allocator) ![]u8 {
    var buf: [32]u8 = undefined;
    return try allocator.dupe(u8, try core.time.Timestamp.now().formatIso(&buf));
}

test "relative path normalization returns workspace relative policy path" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("src");
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    var normalized = try normalizePath(std.testing.allocator, root, "src/../src/main.zig");
    defer normalized.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("src/main.zig", normalized.relative_path);
    try std.testing.expectEqualStrings("./src/main.zig", normalized.policy_path);
}

test "absolute path normalization and workspace containment" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("src");
    try tmp.dir.writeFile(.{ .sub_path = "src/main.zig", .data = "pub fn main() void {}\n" });
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    const absolute = try tmp.dir.realpathAlloc(std.testing.allocator, "src/main.zig");
    defer std.testing.allocator.free(absolute);

    var normalized = try normalizePath(std.testing.allocator, root, absolute);
    defer normalized.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("src/main.zig", normalized.relative_path);

    try std.testing.expectError(error.OutsideWorkspace, normalizePath(std.testing.allocator, root, "/tmp/aegis-outside-file"));
}

test "path traversal cannot escape workspace" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    try std.testing.expectError(error.OutsideWorkspace, normalizePath(std.testing.allocator, root, "../outside.txt"));
}

test "symlink escape to protected path is blocked" {
    if (std.process.getEnvVarOwned(std.testing.allocator, "CI_NO_SYMLINKS")) |_| return error.SkipZigTest else |_| {}
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    const outside_dir = try std.fs.path.join(std.testing.allocator, &.{ root, "..", "aegis-secret-outside" });
    defer std.testing.allocator.free(outside_dir);
    try std.fs.cwd().makePath(outside_dir);
    defer std.fs.cwd().deleteTree(outside_dir) catch {};
    const outside_file = try std.fs.path.join(std.testing.allocator, &.{ outside_dir, "id_ed25519" });
    defer std.testing.allocator.free(outside_file);
    try writeAbsoluteFile(outside_file, "fake-private-key");

    const link_path = try std.fs.path.join(std.testing.allocator, &.{ root, "linked_key" });
    defer std.testing.allocator.free(link_path);
    std.posix.symlink(outside_file, link_path) catch |err| switch (err) {
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };

    try std.testing.expectError(error.SymlinkEscapesWorkspace, normalizePath(std.testing.allocator, root, "linked_key"));
}

test "default sensitive read decisions deny env and fake ssh key" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = "TOKEN=fake_secret_value\n" });
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    var loaded = try policy.load.loadPreset(std.testing.allocator, .strict);
    defer loaded.deinit();

    var env_decision = try decideRead(std.testing.allocator, &loaded, root, ".env");
    defer env_decision.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, env_decision.decision.result);
    try std.testing.expect(std.mem.indexOf(u8, env_decision.decision.reason, "builtin.files.read.deny") != null);

    var ssh_decision = try decideRead(std.testing.allocator, &loaded, root, "~/.ssh/id_ed25519");
    defer ssh_decision.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, ssh_decision.decision.result);
    try std.testing.expectEqualStrings("builtin.files.read.deny[2]", ssh_decision.decision.rule_id.?);
}

test "home workspace still denies protected home credential directories" {
    const home = std.process.getEnvVarOwned(std.testing.allocator, "HOME") catch return error.SkipZigTest;
    defer std.testing.allocator.free(home);
    const home_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, home);
    defer std.testing.allocator.free(home_root);
    var loaded = try policy.load.loadPreset(std.testing.allocator, .strict);
    defer loaded.deinit();

    var ssh_decision = try decideRead(std.testing.allocator, &loaded, home_root, ".ssh/config");
    defer ssh_decision.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, ssh_decision.decision.result);
    try std.testing.expectEqualStrings("builtin.files.read.deny[2]", ssh_decision.decision.rule_id.?);
}

test "macOS simulated Library protected paths are denied without reading real secrets" {
    if (@import("builtin").os.tag != .macos) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("Library/Keychains");
    try tmp.dir.makePath("Library/Application Support/Google/Chrome/Default");
    try tmp.dir.makePath("Library/Application Support/BraveSoftware/Brave-Browser/Default");
    try tmp.dir.makePath("Library/Application Support/Firefox/Profiles/fake.default");
    try tmp.dir.writeFile(.{ .sub_path = "Library/Keychains/login.keychain-db", .data = "fake_secret_value\n" });
    try tmp.dir.writeFile(.{ .sub_path = "Library/Application Support/Google/Chrome/Default/Cookies", .data = "fake_secret_value\n" });
    try tmp.dir.writeFile(.{ .sub_path = "Library/Application Support/Google/Chrome/Default/Login Data", .data = "fake_secret_value\n" });
    try tmp.dir.writeFile(.{ .sub_path = "Library/Application Support/BraveSoftware/Brave-Browser/Default/Cookies", .data = "fake_secret_value\n" });
    try tmp.dir.writeFile(.{ .sub_path = "Library/Application Support/Firefox/Profiles/fake.default/cookies.sqlite", .data = "fake_secret_value\n" });
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    var loaded = try policy.load.loadPreset(std.testing.allocator, .strict);
    defer loaded.deinit();

    const paths = [_][]const u8{
        "Library/Keychains/login.keychain-db",
        "Library/Application Support/Google/Chrome/Default/Cookies",
        "Library/Application Support/Google/Chrome/Default/Login Data",
        "Library/Application Support/BraveSoftware/Brave-Browser/Default/Cookies",
        "Library/Application Support/Firefox/Profiles/fake.default/cookies.sqlite",
    };
    for (paths) |path| {
        var decision = try decideRead(std.testing.allocator, &loaded, root, path);
        defer decision.deinit(std.testing.allocator);
        try std.testing.expectEqual(core.decision.DecisionResult.deny, decision.decision.result);
        try std.testing.expect(std.mem.indexOf(u8, decision.decision.reason, "builtin.files.read.deny") != null);
    }
}

test "macOS protected path matching is ASCII case-insensitive for simulated home paths" {
    if (@import("builtin").os.tag != .macos) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("library/keychains");
    try tmp.dir.writeFile(.{ .sub_path = "library/keychains/LOGIN.KEYCHAIN-DB", .data = "fake_secret_value\n" });
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    var loaded = try policy.load.loadPreset(std.testing.allocator, .strict);
    defer loaded.deinit();

    var decision = try decideRead(std.testing.allocator, &loaded, root, "library/keychains/LOGIN.KEYCHAIN-DB");
    defer decision.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, decision.decision.result);
    try std.testing.expect(std.mem.indexOf(u8, decision.decision.reason, "builtin.files.read.deny") != null);
}

test "macOS symlink escape into simulated Keychains path is rejected" {
    if (@import("builtin").os.tag != .macos) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("workspace");
    try tmp.dir.makePath("fake-home/Library/Keychains");
    try tmp.dir.writeFile(.{ .sub_path = "fake-home/Library/Keychains/login.keychain-db", .data = "fake_secret_value\n" });
    const workspace = try tmp.dir.realpathAlloc(std.testing.allocator, "workspace");
    defer std.testing.allocator.free(workspace);
    const protected_file = try tmp.dir.realpathAlloc(std.testing.allocator, "fake-home/Library/Keychains/login.keychain-db");
    defer std.testing.allocator.free(protected_file);
    const link_path = try std.fs.path.join(std.testing.allocator, &.{ workspace, "linked-keychain" });
    defer std.testing.allocator.free(link_path);
    std.posix.symlink(protected_file, link_path) catch |err| switch (err) {
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };

    try std.testing.expectError(error.SymlinkEscapesWorkspace, normalizePath(std.testing.allocator, workspace, "linked-keychain"));
}

test "staged create update diff apply discard and index integrity" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath(".git");
    try tmp.dir.makePath("src");
    try tmp.dir.writeFile(.{ .sub_path = "src/existing.txt", .data = "old\n" });
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    var loaded = try policy.load.loadPreset(std.testing.allocator, .strict);
    defer loaded.deinit();
    const session_id = "phase09-test";

    var created = try stageCreate(std.testing.allocator, &loaded, root, session_id, "src/new.txt", "new\n", null);
    defer created.deinit(std.testing.allocator);
    try std.testing.expectEqual(Operation.create, created.entry.operation);

    var updated = try stageUpdate(std.testing.allocator, &loaded, root, session_id, "src/existing.txt", "newer\n", null);
    defer updated.deinit(std.testing.allocator);
    try std.testing.expectEqual(Operation.update, updated.entry.operation);

    const diff = try diffStaged(std.testing.allocator, root, session_id, "src/existing.txt");
    defer std.testing.allocator.free(diff);
    try std.testing.expect(std.mem.indexOf(u8, diff, "--- a/src/existing.txt") != null);
    try std.testing.expect(std.mem.indexOf(u8, diff, "-old") != null);
    try std.testing.expect(std.mem.indexOf(u8, diff, "+newer") != null);

    const index_path = try std.fs.path.join(std.testing.allocator, &.{ root, ".aegis", "sessions", session_id, "staging-index.json" });
    defer std.testing.allocator.free(index_path);
    const index_text = try std.fs.cwd().readFileAlloc(std.testing.allocator, index_path, 8192);
    defer std.testing.allocator.free(index_text);
    try std.testing.expect(std.mem.indexOf(u8, index_text, "\"normalized_path\":\"src/new.txt\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, index_text, "\"operation\":\"update\"") != null);

    const applied = try applyStaged(std.testing.allocator, root, session_id, "src/existing.txt", null);
    try std.testing.expectEqual(@as(usize, 1), applied.count);
    const applied_text = try tmp.dir.readFileAlloc(std.testing.allocator, "src/existing.txt", 1024);
    defer std.testing.allocator.free(applied_text);
    try std.testing.expectEqualStrings("newer\n", applied_text);

    const discarded = try discardStaged(std.testing.allocator, root, session_id, "src/new.txt", null);
    try std.testing.expectEqual(@as(usize, 1), discarded.count);
    try std.testing.expectError(error.FileNotFound, tmp.dir.access("src/new.txt", .{}));
}

test "apply rejects tampered staged blob hash" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath(".git");
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    var loaded = try policy.load.loadPreset(std.testing.allocator, .strict);
    defer loaded.deinit();

    var staged = try stageCreate(std.testing.allocator, &loaded, root, "tamper-test", "created.txt", "reviewed\n", null);
    defer staged.deinit(std.testing.allocator);
    try writeAbsoluteFile(staged.entry.staged_path, "tampered\n");

    try std.testing.expectError(error.StagedChanged, applyStaged(std.testing.allocator, root, "tamper-test", "created.txt", null));
    const live_path = try std.fs.path.join(std.testing.allocator, &.{ root, "created.txt" });
    defer std.testing.allocator.free(live_path);
    try std.testing.expect(!fileExists(live_path));
}

test "diff uses captured original after workspace drift" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath(".git");
    try tmp.dir.writeFile(.{ .sub_path = "tracked.txt", .data = "old\n" });
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    var loaded = try policy.load.loadPreset(std.testing.allocator, .strict);
    defer loaded.deinit();

    var staged = try stageUpdate(std.testing.allocator, &loaded, root, "diff-drift-test", "tracked.txt", "new\n", null);
    defer staged.deinit(std.testing.allocator);
    try tmp.dir.writeFile(.{ .sub_path = "tracked.txt", .data = "drift\n" });

    const diff = try diffStaged(std.testing.allocator, root, "diff-drift-test", "tracked.txt");
    defer std.testing.allocator.free(diff);
    try std.testing.expect(std.mem.indexOf(u8, diff, "-old") != null);
    try std.testing.expect(std.mem.indexOf(u8, diff, "-drift") == null);
    try std.testing.expect(std.mem.indexOf(u8, diff, "+new") != null);
}

test "filesystem audit events are emitted through session writer" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath(".git");
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    var loaded = try policy.load.loadPreset(std.testing.allocator, .strict);
    defer loaded.deinit();

    const ts = core.time.Timestamp.fromUnixSeconds(1_777_983_130);
    const session: core.session.Session = .{
        .id = try core.session.generateSessionId(ts),
        .started_at = ts,
        .command = "aegis",
        .args = &.{"stage"},
        .workspace_root = root,
        .mode = .strict,
        .platform = core.platform.detectOs(),
    };
    var writer = try audit.writer.SessionWriter.init(std.testing.allocator, session);
    defer writer.deinit();
    const ctx: AuditContext = .{ .writer = &writer, .session = session };

    var staged = try stageWrite(std.testing.allocator, &loaded, root, session.id.slice(), "created.txt", "hello\n", ctx);
    defer staged.deinit(std.testing.allocator);
    _ = try discardStaged(std.testing.allocator, root, session.id.slice(), "created.txt", ctx);

    const events_path = try std.fs.path.join(std.testing.allocator, &.{ root, ".aegis", "sessions", session.id.slice(), "events.jsonl" });
    defer std.testing.allocator.free(events_path);
    const events = try std.fs.cwd().readFileAlloc(std.testing.allocator, events_path, 8192);
    defer std.testing.allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "file_write_attempt") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "file_write_staged") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "file_discard") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "fake_secret_value") == null);
}
