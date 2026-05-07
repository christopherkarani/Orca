const std = @import("std");

const redact_bridge = @import("../audit/redact_bridge.zig");
const core = @import("../core/mod.zig");
const policy_schema = @import("../policy/schema.zig");
const tools = @import("tools.zig");

pub const implemented = true;

pub const ManifestError = error{
    InvalidManifest,
    ManifestFileTooLarge,
    UnsupportedManifestVersion,
    UnsupportedTransport,
    UnsupportedRisk,
    UnsupportedDecision,
    MissingServerName,
    MissingServerCommand,
};

pub const Transport = enum {
    stdio,
    http,

    pub fn parse(value: []const u8) ?Transport {
        if (std.mem.eql(u8, value, "stdio")) return .stdio;
        if (std.mem.eql(u8, value, "http")) return .http;
        return null;
    }

    pub fn toString(self: Transport) []const u8 {
        return @tagName(self);
    }
};

pub const ToolEntry = struct {
    name: []const u8,
    risk: tools.RiskClass,
    default: policy_schema.DecisionValue,

    pub fn deinit(self: ToolEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

pub const Server = struct {
    name: []const u8,
    transport: Transport,
    command: []const u8,
    args: []const []const u8,
    expected_hash: ?[]const u8,
    env_allow: []const []const u8,

    pub fn deinit(self: Server, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.command);
        for (self.args) |arg| allocator.free(arg);
        if (self.args.len > 0) allocator.free(self.args);
        if (self.expected_hash) |hash| allocator.free(hash);
        for (self.env_allow) |name| allocator.free(name);
        if (self.env_allow.len > 0) allocator.free(self.env_allow);
    }
};

pub const Manifest = struct {
    version: u16,
    server: Server,
    tools: []ToolEntry,
    resources_default: ?policy_schema.DecisionValue,
    prompts_default: ?policy_schema.DecisionValue,
    sampling_default: ?policy_schema.DecisionValue,
    source_path: ?[]const u8 = null,

    pub fn deinit(self: *Manifest, allocator: std.mem.Allocator) void {
        self.server.deinit(allocator);
        for (self.tools) |entry| entry.deinit(allocator);
        if (self.tools.len > 0) allocator.free(self.tools);
        if (self.source_path) |path| allocator.free(path);
        self.* = undefined;
    }

    pub fn toolDefault(self: Manifest, name: []const u8) ?policy_schema.DecisionValue {
        for (self.tools) |entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry.default;
        }
        return null;
    }
};

const Section = enum {
    root,
    server,
    server_args,
    server_env,
    server_env_allow,
    tools,
    tool,
    resources,
    prompts,
    sampling,
};

const ListTarget = enum {
    none,
    server_args,
    env_allow,
};

const Builder = struct {
    allocator: std.mem.Allocator,
    saw_version: bool = false,
    version: u16 = 0,
    server_name: ?[]const u8 = null,
    server_transport: ?Transport = null,
    server_command: ?[]const u8 = null,
    server_args: std.ArrayList([]const u8) = .empty,
    expected_hash: ?[]const u8 = null,
    env_allow: std.ArrayList([]const u8) = .empty,
    tools: std.ArrayList(ToolEntry) = .empty,
    active_tool: ?usize = null,
    resources_default: ?policy_schema.DecisionValue = null,
    prompts_default: ?policy_schema.DecisionValue = null,
    sampling_default: ?policy_schema.DecisionValue = null,

    fn init(allocator: std.mem.Allocator) Builder {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *Builder) void {
        if (self.server_name) |value| self.allocator.free(value);
        if (self.server_command) |value| self.allocator.free(value);
        if (self.expected_hash) |value| self.allocator.free(value);
        for (self.server_args.items) |value| self.allocator.free(value);
        self.server_args.deinit(self.allocator);
        for (self.env_allow.items) |value| self.allocator.free(value);
        self.env_allow.deinit(self.allocator);
        for (self.tools.items) |entry| entry.deinit(self.allocator);
        self.tools.deinit(self.allocator);
    }

    fn append(self: *Builder, target: ListTarget, value: []const u8) !void {
        const owned = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(owned);
        switch (target) {
            .server_args => try self.server_args.append(self.allocator, owned),
            .env_allow => try self.env_allow.append(self.allocator, owned),
            .none => return error.InvalidManifest,
        }
    }

    fn addTool(self: *Builder, name: []const u8) !void {
        const owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned);
        try self.tools.append(self.allocator, .{
            .name = owned,
            .risk = .unknown,
            .default = .ask,
        });
        self.active_tool = self.tools.items.len - 1;
    }

    fn toManifest(self: *Builder, source_path: ?[]const u8) !Manifest {
        if (!self.saw_version) return error.InvalidManifest;
        if (self.version != 1) return error.UnsupportedManifestVersion;
        const name = self.server_name orelse return error.MissingServerName;
        if (name.len == 0) return error.MissingServerName;
        const transport = self.server_transport orelse return error.UnsupportedTransport;
        const command = self.server_command orelse "";
        if (transport == .stdio and command.len == 0) return error.MissingServerCommand;

        return .{
            .version = self.version,
            .server = .{
                .name = try self.allocator.dupe(u8, name),
                .transport = transport,
                .command = try self.allocator.dupe(u8, command),
                .args = try self.server_args.toOwnedSlice(self.allocator),
                .expected_hash = if (self.expected_hash) |hash| try self.allocator.dupe(u8, hash) else null,
                .env_allow = try self.env_allow.toOwnedSlice(self.allocator),
            },
            .tools = try self.tools.toOwnedSlice(self.allocator),
            .resources_default = self.resources_default,
            .prompts_default = self.prompts_default,
            .sampling_default = self.sampling_default,
            .source_path = if (source_path) |path| try self.allocator.dupe(u8, path) else null,
        };
    }
};

pub fn loadFile(allocator: std.mem.Allocator, path: []const u8) !Manifest {
    const text = try std.fs.cwd().readFileAlloc(allocator, path, core.limits.max_policy_file_len + 1);
    defer allocator.free(text);
    if (text.len > core.limits.max_policy_file_len) return error.ManifestFileTooLarge;
    return parseFromSlice(allocator, text, path);
}

pub fn parseFromSlice(allocator: std.mem.Allocator, text: []const u8, source_path: ?[]const u8) !Manifest {
    if (text.len > core.limits.max_policy_file_len) return error.ManifestFileTooLarge;
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.len == 0 or trimmed[0] == '{') return error.InvalidManifest;

    var builder = Builder.init(allocator);
    defer builder.deinit();

    var section: Section = .root;
    var list_target: ListTarget = .none;
    var lines = std.mem.splitScalar(u8, trimmed, '\n');
    while (lines.next()) |raw_line| {
        const cleaned = stripComment(std.mem.trimRight(u8, raw_line, " \t\r"));
        if (std.mem.trim(u8, cleaned, " \t").len == 0) continue;
        const indent = countIndent(cleaned);
        if (indent % 2 != 0 or indent > 8) return error.InvalidManifest;
        const line = std.mem.trim(u8, cleaned[indent..], " \t");

        if (std.mem.startsWith(u8, line, "- ")) {
            try builder.append(list_target, try parseScalar(line[2..]));
            continue;
        }

        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.InvalidManifest;
        const key = std.mem.trim(u8, line[0..colon], " \t");
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        list_target = .none;

        switch (indent) {
            0 => {
                section = .root;
                if (std.mem.eql(u8, key, "version")) {
                    builder.version = try parseU16(value);
                    builder.saw_version = true;
                } else if (std.mem.eql(u8, key, "server")) {
                    if (value.len != 0) return error.InvalidManifest;
                    section = .server;
                } else if (std.mem.eql(u8, key, "tools")) {
                    if (value.len != 0) return error.InvalidManifest;
                    section = .tools;
                } else if (std.mem.eql(u8, key, "resources")) {
                    if (value.len != 0) return error.InvalidManifest;
                    section = .resources;
                } else if (std.mem.eql(u8, key, "prompts")) {
                    if (value.len != 0) return error.InvalidManifest;
                    section = .prompts;
                } else if (std.mem.eql(u8, key, "sampling")) {
                    if (value.len != 0) return error.InvalidManifest;
                    section = .sampling;
                } else return error.InvalidManifest;
            },
            2 => switch (section) {
                .server, .server_args, .server_env, .server_env_allow => {
                    section = .server;
                    try applyServerField(&builder, key, value, &list_target);
                    if (std.mem.eql(u8, key, "args") and value.len == 0) section = .server_args;
                    if (std.mem.eql(u8, key, "env")) section = .server_env;
                },
                .tools, .tool => {
                    if (value.len != 0) return error.InvalidManifest;
                    try builder.addTool(key);
                    section = .tool;
                },
                .resources => try applySurfaceDefault(&builder.resources_default, key, value),
                .prompts => try applySurfaceDefault(&builder.prompts_default, key, value),
                .sampling => try applySurfaceDefault(&builder.sampling_default, key, value),
                else => return error.InvalidManifest,
            },
            4 => switch (section) {
                .server_args => return error.InvalidManifest,
                .server_env => {
                    if (!std.mem.eql(u8, key, "allow") or value.len != 0) return error.InvalidManifest;
                    section = .server_env_allow;
                    list_target = .env_allow;
                },
                .server_env_allow => {
                    if (!std.mem.eql(u8, key, "allow") or value.len != 0) return error.InvalidManifest;
                    list_target = .env_allow;
                },
                .tool => try applyToolField(&builder, key, value),
                else => return error.InvalidManifest,
            },
            else => return error.InvalidManifest,
        }
    }

    return builder.toManifest(source_path);
}

fn applyServerField(builder: *Builder, key: []const u8, value: []const u8, list_target: *ListTarget) !void {
    const scalar = try parseScalar(value);
    if (std.mem.eql(u8, key, "name")) {
        replaceOwned(builder.allocator, &builder.server_name, scalar) catch return error.InvalidManifest;
    } else if (std.mem.eql(u8, key, "transport")) {
        builder.server_transport = Transport.parse(scalar) orelse return error.UnsupportedTransport;
    } else if (std.mem.eql(u8, key, "command")) {
        replaceOwned(builder.allocator, &builder.server_command, scalar) catch return error.InvalidManifest;
    } else if (std.mem.eql(u8, key, "args")) {
        if (std.mem.eql(u8, scalar, "[]")) return;
        if (scalar.len == 0) list_target.* = .server_args else return error.InvalidManifest;
    } else if (std.mem.eql(u8, key, "expected_hash")) {
        if (std.mem.eql(u8, scalar, "null")) {
            if (builder.expected_hash) |hash| builder.allocator.free(hash);
            builder.expected_hash = null;
        } else {
            replaceOwned(builder.allocator, &builder.expected_hash, scalar) catch return error.InvalidManifest;
        }
    } else if (std.mem.eql(u8, key, "env")) {
        if (value.len != 0) return error.InvalidManifest;
    } else return error.InvalidManifest;
}

fn applyToolField(builder: *Builder, key: []const u8, value: []const u8) !void {
    const index = builder.active_tool orelse return error.InvalidManifest;
    const scalar = try parseScalar(value);
    if (std.mem.eql(u8, key, "risk")) {
        builder.tools.items[index].risk = parseRisk(scalar) orelse return error.UnsupportedRisk;
    } else if (std.mem.eql(u8, key, "default")) {
        builder.tools.items[index].default = try parseDecision(scalar);
    } else return error.InvalidManifest;
}

fn applySurfaceDefault(target: *?policy_schema.DecisionValue, key: []const u8, value: []const u8) !void {
    if (!std.mem.eql(u8, key, "default")) return error.InvalidManifest;
    target.* = try parseDecision(try parseScalar(value));
}

fn replaceOwned(allocator: std.mem.Allocator, slot: *?[]const u8, value: []const u8) !void {
    if (slot.*) |old| allocator.free(old);
    slot.* = try allocator.dupe(u8, value);
}

fn parseRisk(value: []const u8) ?tools.RiskClass {
    if (std.mem.eql(u8, value, "low")) return .low;
    if (std.mem.eql(u8, value, "medium")) return .medium;
    if (std.mem.eql(u8, value, "high")) return .high;
    if (std.mem.eql(u8, value, "critical")) return .critical;
    if (std.mem.eql(u8, value, "unknown")) return .unknown;
    return null;
}

fn parseDecision(value: []const u8) !policy_schema.DecisionValue {
    const decision = policy_schema.DecisionValue.parse(value) orelse return error.UnsupportedDecision;
    return switch (decision) {
        .allow, .ask, .deny => decision,
        .observe => error.UnsupportedDecision,
    };
}

fn parseScalar(raw: []const u8) ![]const u8 {
    const value = std.mem.trim(u8, raw, " \t");
    if (value.len >= 2 and ((value[0] == '"' and value[value.len - 1] == '"') or (value[0] == '\'' and value[value.len - 1] == '\''))) {
        return value[1 .. value.len - 1];
    }
    return value;
}

fn parseU16(value: []const u8) !u16 {
    return std.fmt.parseInt(u16, try parseScalar(value), 10) catch return error.InvalidManifest;
}

fn stripComment(line: []const u8) []const u8 {
    var in_quote: ?u8 = null;
    for (line, 0..) |char, index| {
        if (in_quote) |quote| {
            if (char == quote) in_quote = null;
        } else if (char == '"' or char == '\'') {
            in_quote = char;
        } else if (char == '#') {
            return line[0..index];
        }
    }
    return line;
}

fn countIndent(line: []const u8) usize {
    var count: usize = 0;
    while (count < line.len and line[count] == ' ') count += 1;
    return count;
}

pub fn writeStarterManifest(writer: anytype, server_name: []const u8, command: []const u8, args: []const []const u8) !void {
    try writer.writeAll("version: 1\nserver:\n");
    try writer.print("  name: {s}\n", .{server_name});
    try writer.writeAll("  transport: stdio\n");
    try writer.print("  command: {s}\n", .{command});
    if (args.len == 0) {
        try writer.writeAll("  args: []\n");
    } else {
        try writer.writeAll("  args:\n");
        for (args, 0..) |arg, index| {
            var redacted_buf: [256]u8 = undefined;
            const safe_arg = if (index > 0 and looksLikeSecretFlag(args[index - 1]))
                "[REDACTED]"
            else
                redact_bridge.redactStringBounded(arg, &redacted_buf);
            try writer.print("    - {s}\n", .{safe_arg});
        }
    }
    try writer.writeAll(
        \\  expected_hash: null
        \\  env:
        \\    allow:
        \\      - GITHUB_TOKEN
        \\
        \\tools:
        \\resources:
        \\  default: ask
        \\prompts:
        \\  default: ask
        \\sampling:
        \\  default: deny
        \\
    );
}

fn looksLikeSecretFlag(value: []const u8) bool {
    return containsIgnoreCase(value, "token") or
        containsIgnoreCase(value, "secret") or
        containsIgnoreCase(value, "password") or
        containsIgnoreCase(value, "passwd") or
        containsIgnoreCase(value, "api-key") or
        containsIgnoreCase(value, "apikey") or
        containsIgnoreCase(value, "private-key");
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    return std.ascii.indexOfIgnoreCase(haystack, needle) != null;
}

test "valid manifest parsing covers Phase 17 schema" {
    var manifest = try parseFromSlice(std.testing.allocator,
        \\version: 1
        \\server:
        \\  name: github
        \\  transport: stdio
        \\  command: github-mcp-server
        \\  args: []
        \\  expected_hash: null
        \\  env:
        \\    allow:
        \\      - GITHUB_TOKEN
        \\tools:
        \\  search_issues:
        \\    risk: low
        \\    default: allow
        \\  delete_repository:
        \\    risk: critical
        \\    default: deny
        \\  inspect_unknown:
        \\    risk: unknown
        \\    default: ask
        \\resources:
        \\  default: ask
        \\prompts:
        \\  default: ask
        \\sampling:
        \\  default: deny
    , "github.mcp.yaml");
    defer manifest.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u16, 1), manifest.version);
    try std.testing.expectEqualStrings("github", manifest.server.name);
    try std.testing.expectEqual(Transport.stdio, manifest.server.transport);
    try std.testing.expectEqualStrings("github-mcp-server", manifest.server.command);
    try std.testing.expectEqualStrings("GITHUB_TOKEN", manifest.server.env_allow[0]);
    try std.testing.expectEqual(policy_schema.DecisionValue.allow, manifest.toolDefault("search_issues").?);
    try std.testing.expectEqual(policy_schema.DecisionValue.deny, manifest.toolDefault("delete_repository").?);
    try std.testing.expectEqual(tools.RiskClass.unknown, manifest.tools[2].risk);
    try std.testing.expectEqual(policy_schema.DecisionValue.ask, manifest.toolDefault("inspect_unknown").?);
    try std.testing.expectEqual(policy_schema.DecisionValue.ask, manifest.resources_default.?);
    try std.testing.expectEqual(policy_schema.DecisionValue.ask, manifest.prompts_default.?);
    try std.testing.expectEqual(policy_schema.DecisionValue.deny, manifest.sampling_default.?);
}

test "invalid manifest validation rejects unsafe or ambiguous schema" {
    try std.testing.expectError(error.MissingServerCommand, parseFromSlice(std.testing.allocator,
        \\version: 1
        \\server:
        \\  name: github
        \\  transport: stdio
    , "bad.yaml"));
    try std.testing.expectError(error.UnsupportedDecision, parseFromSlice(std.testing.allocator,
        \\version: 1
        \\server:
        \\  name: github
        \\  transport: stdio
        \\  command: github-mcp-server
        \\tools:
        \\  search:
        \\    risk: low
        \\    default: observe
    , "bad.yaml"));
    try std.testing.expectError(error.InvalidManifest, parseFromSlice(std.testing.allocator,
        \\version: 1
        \\server:
        \\  name: github
        \\  transport: stdio
        \\  command: github-mcp-server
        \\enterprise_dashboard: true
    , "bad.yaml"));
}

test "starter manifest omits raw secret values" {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);
    try writeStarterManifest(out.writer(std.testing.allocator), "github", "github-mcp-server", &.{"--token", "ghp_fakeSecretShouldNotBeHere"});
    try std.testing.expect(std.mem.indexOf(u8, out.items, "ghp_fakeSecretShouldNotBeHere") == null);
}
