const std = @import("std");

const core = @import("../core/mod.zig");

pub const version: u16 = 1;

pub const Mode = enum {
    observe,
    ask,
    strict,
    ci,
    redteam,
    trusted,

    pub fn parse(value: []const u8) ?Mode {
        inline for (@typeInfo(Mode).@"enum".fields) |field| {
            if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
        }
        return null;
    }

    pub fn toString(self: Mode) []const u8 {
        return @tagName(self);
    }

    pub fn toCoreMode(self: Mode) core.types.Mode {
        return switch (self) {
            .observe, .trusted => .observe,
            .ask => .ask,
            .strict, .redteam => .strict,
            .ci => .ci,
        };
    }
};

pub const DecisionValue = enum {
    allow,
    deny,
    ask,
    observe,

    pub fn parse(value: []const u8) ?DecisionValue {
        inline for (@typeInfo(DecisionValue).@"enum".fields) |field| {
            if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
        }
        return null;
    }

    pub fn toDecisionResult(self: DecisionValue) core.decision.DecisionResult {
        return switch (self) {
            .allow => .allow,
            .deny => .deny,
            .ask => .ask,
            .observe => .observe,
        };
    }

    pub fn toString(self: DecisionValue) []const u8 {
        return @tagName(self);
    }
};

pub const WriteMode = enum {
    staged,
    direct,

    pub fn parse(value: []const u8) ?WriteMode {
        if (std.mem.eql(u8, value, "staged")) return .staged;
        if (std.mem.eql(u8, value, "direct")) return .direct;
        return null;
    }

    pub fn toString(self: WriteMode) []const u8 {
        return @tagName(self);
    }
};

pub const AuditLevel = enum {
    full,
    minimal,

    pub fn parse(value: []const u8) ?AuditLevel {
        if (std.mem.eql(u8, value, "full")) return .full;
        if (std.mem.eql(u8, value, "minimal")) return .minimal;
        return null;
    }
};

pub const RuleSet = struct {
    allow: []const []const u8 = &.{},
    deny: []const []const u8 = &.{},
    ask: []const []const u8 = &.{},
    default: ?DecisionValue = null,

    pub fn deinit(self: RuleSet, allocator: std.mem.Allocator) void {
        freeStringList(allocator, self.allow);
        freeStringList(allocator, self.deny);
        freeStringList(allocator, self.ask);
    }
};

pub const WorkspacePolicy = struct {
    root: []const u8 = ".",
    write_mode: WriteMode = .staged,

    pub fn deinit(self: WorkspacePolicy, allocator: std.mem.Allocator) void {
        allocator.free(self.root);
    }
};

pub const EnvPolicy = struct {
    inherit: bool = false,
    allow: []const []const u8 = &.{},
    deny_patterns: []const []const u8 = &.{},
    ask: []const []const u8 = &.{},
    default: ?DecisionValue = null,

    pub fn deinit(self: EnvPolicy, allocator: std.mem.Allocator) void {
        freeStringList(allocator, self.allow);
        freeStringList(allocator, self.deny_patterns);
        freeStringList(allocator, self.ask);
    }
};

pub const FilesPolicy = struct {
    read: RuleSet = .{},
    write: RuleSet = .{},
    write_mode: WriteMode = .staged,

    pub fn deinit(self: FilesPolicy, allocator: std.mem.Allocator) void {
        self.read.deinit(allocator);
        self.write.deinit(allocator);
    }
};

pub const CommandsPolicy = RuleSet;
pub const NetworkPolicy = RuleSet;
pub const MCPPolicy = RuleSet;

pub const AuditPolicy = struct {
    level: AuditLevel = .full,
    redact_secrets: bool = true,
    tamper_evident: bool = true,
};

pub const Policy = struct {
    version_value: u16 = version,
    mode: Mode = .strict,
    workspace: WorkspacePolicy = .{ .root = "." },
    env: EnvPolicy = .{},
    files: FilesPolicy = .{},
    commands: CommandsPolicy = .{},
    network: NetworkPolicy = .{},
    mcp: MCPPolicy = .{},
    audit: AuditPolicy = .{},
    source_path: ?[]const u8 = null,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Policy) void {
        self.workspace.deinit(self.allocator);
        self.env.deinit(self.allocator);
        self.files.deinit(self.allocator);
        self.commands.deinit(self.allocator);
        self.network.deinit(self.allocator);
        self.mcp.deinit(self.allocator);
        if (self.source_path) |path| self.allocator.free(path);
        self.* = undefined;
    }
};

pub const RuleRef = struct {
    id: []const u8,
    pattern: []const u8,
};

pub const Evaluation = struct {
    decision: core.decision.Decision,
    matched_rule: ?RuleRef = null,
    explanation: []const u8,
    owned_rule_id: ?[]const u8 = null,

    pub fn deinit(self: Evaluation, allocator: std.mem.Allocator) void {
        allocator.free(self.explanation);
        if (self.owned_rule_id) |rule_id| allocator.free(rule_id);
    }
};

pub const EvaluationContext = struct {
    mode: ?Mode = null,
};

pub const LoadSource = enum {
    cli,
    workspace,
    user,
    builtin,
};

pub const LoadedPolicy = struct {
    policy: Policy,
    source: LoadSource,
    path: []const u8,

    pub fn deinit(self: *LoadedPolicy) void {
        const allocator = self.policy.allocator;
        self.policy.deinit();
        allocator.free(self.path);
        self.* = undefined;
    }
};

pub fn duplicateStringList(allocator: std.mem.Allocator, values: []const []const u8) ![]const []const u8 {
    if (values.len == 0) return &.{};
    var out = try allocator.alloc([]const u8, values.len);
    errdefer allocator.free(out);
    var owned: usize = 0;
    errdefer {
        for (out[0..owned]) |value| allocator.free(value);
    }
    for (values, 0..) |value, index| {
        out[index] = try allocator.dupe(u8, value);
        owned += 1;
    }
    return out;
}

pub fn freeStringList(allocator: std.mem.Allocator, values: []const []const u8) void {
    for (values) |value| allocator.free(value);
    if (values.len > 0) allocator.free(values);
}

test "policy modes parse all phase 07 modes" {
    try std.testing.expectEqual(Mode.observe, Mode.parse("observe").?);
    try std.testing.expectEqual(Mode.ask, Mode.parse("ask").?);
    try std.testing.expectEqual(Mode.strict, Mode.parse("strict").?);
    try std.testing.expectEqual(Mode.ci, Mode.parse("ci").?);
    try std.testing.expectEqual(Mode.redteam, Mode.parse("redteam").?);
    try std.testing.expectEqual(Mode.trusted, Mode.parse("trusted").?);
    try std.testing.expectEqual(@as(?Mode, null), Mode.parse("invalid"));
}
