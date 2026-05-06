const std = @import("std");

const core = @import("../core/mod.zig");
const presets = @import("presets.zig");
const schema = @import("schema.zig");
const validate = @import("validate.zig");

pub const PolicyParseError = error{
    InvalidPolicy,
    UnsupportedPolicyVersion,
    UnsupportedPolicyMode,
    UnsupportedPolicyDecision,
    UnsupportedPolicyWriteMode,
    UnsupportedPolicyAuditLevel,
    PolicyFileTooLarge,
    MissingPolicyVersion,
    MissingPolicyMode,
};

const Section = enum {
    root,
    workspace,
    env,
    files,
    files_read,
    files_write,
    commands,
    network,
    mcp,
    mcp_servers,
    mcp_server,
    mcp_server_tools,
    audit,
    ignored,
};

const ListTarget = enum {
    none,
    env_allow,
    env_deny,
    env_ask,
    files_read_allow,
    files_read_deny,
    files_read_ask,
    files_write_allow,
    files_write_deny,
    files_write_ask,
    commands_allow,
    commands_deny,
    commands_ask,
    network_allow,
    network_deny,
    network_ask,
    mcp_allow,
    mcp_deny,
    mcp_ask,
};

const Builder = struct {
    allocator: std.mem.Allocator,
    saw_version: bool = false,
    version_value: u16 = 0,
    mode: ?schema.Mode = null,
    workspace_root: ?[]const u8 = null,
    workspace_write_mode: schema.WriteMode = .staged,
    env_inherit: bool = false,
    env_allow: std.ArrayList([]const u8) = .empty,
    env_deny: std.ArrayList([]const u8) = .empty,
    env_ask: std.ArrayList([]const u8) = .empty,
    env_default: ?schema.DecisionValue = null,
    files_read_allow: std.ArrayList([]const u8) = .empty,
    files_read_deny: std.ArrayList([]const u8) = .empty,
    files_read_ask: std.ArrayList([]const u8) = .empty,
    files_read_default: ?schema.DecisionValue = null,
    files_write_allow: std.ArrayList([]const u8) = .empty,
    files_write_deny: std.ArrayList([]const u8) = .empty,
    files_write_ask: std.ArrayList([]const u8) = .empty,
    files_write_default: ?schema.DecisionValue = null,
    files_write_mode: schema.WriteMode = .staged,
    commands_allow: std.ArrayList([]const u8) = .empty,
    commands_deny: std.ArrayList([]const u8) = .empty,
    commands_ask: std.ArrayList([]const u8) = .empty,
    commands_default: ?schema.DecisionValue = null,
    network_allow: std.ArrayList([]const u8) = .empty,
    network_deny: std.ArrayList([]const u8) = .empty,
    network_ask: std.ArrayList([]const u8) = .empty,
    network_default: ?schema.DecisionValue = null,
    mcp_allow: std.ArrayList([]const u8) = .empty,
    mcp_deny: std.ArrayList([]const u8) = .empty,
    mcp_ask: std.ArrayList([]const u8) = .empty,
    mcp_default: ?schema.DecisionValue = null,
    active_mcp_server: ?[]const u8 = null,
    audit_level: schema.AuditLevel = .full,
    audit_redact_secrets: bool = true,
    audit_tamper_evident: bool = true,

    fn init(allocator: std.mem.Allocator) Builder {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *Builder) void {
        if (self.workspace_root) |root| self.allocator.free(root);
        freeList(self.allocator, &self.env_allow);
        freeList(self.allocator, &self.env_deny);
        freeList(self.allocator, &self.env_ask);
        freeList(self.allocator, &self.files_read_allow);
        freeList(self.allocator, &self.files_read_deny);
        freeList(self.allocator, &self.files_read_ask);
        freeList(self.allocator, &self.files_write_allow);
        freeList(self.allocator, &self.files_write_deny);
        freeList(self.allocator, &self.files_write_ask);
        freeList(self.allocator, &self.commands_allow);
        freeList(self.allocator, &self.commands_deny);
        freeList(self.allocator, &self.commands_ask);
        freeList(self.allocator, &self.network_allow);
        freeList(self.allocator, &self.network_deny);
        freeList(self.allocator, &self.network_ask);
        freeList(self.allocator, &self.mcp_allow);
        freeList(self.allocator, &self.mcp_deny);
        freeList(self.allocator, &self.mcp_ask);
        if (self.active_mcp_server) |server| self.allocator.free(server);
    }

    fn append(self: *Builder, target: ListTarget, value: []const u8) !void {
        const owned = if ((target == .mcp_allow or target == .mcp_deny or target == .mcp_ask) and self.active_mcp_server != null)
            try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ self.active_mcp_server.?, value })
        else
            try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(owned);
        switch (target) {
            .env_allow => try self.env_allow.append(self.allocator, owned),
            .env_deny => try self.env_deny.append(self.allocator, owned),
            .env_ask => try self.env_ask.append(self.allocator, owned),
            .files_read_allow => try self.files_read_allow.append(self.allocator, owned),
            .files_read_deny => try self.files_read_deny.append(self.allocator, owned),
            .files_read_ask => try self.files_read_ask.append(self.allocator, owned),
            .files_write_allow => try self.files_write_allow.append(self.allocator, owned),
            .files_write_deny => try self.files_write_deny.append(self.allocator, owned),
            .files_write_ask => try self.files_write_ask.append(self.allocator, owned),
            .commands_allow => try self.commands_allow.append(self.allocator, owned),
            .commands_deny => try self.commands_deny.append(self.allocator, owned),
            .commands_ask => try self.commands_ask.append(self.allocator, owned),
            .network_allow => try self.network_allow.append(self.allocator, owned),
            .network_deny => try self.network_deny.append(self.allocator, owned),
            .network_ask => try self.network_ask.append(self.allocator, owned),
            .mcp_allow => try self.mcp_allow.append(self.allocator, owned),
            .mcp_deny => try self.mcp_deny.append(self.allocator, owned),
            .mcp_ask => try self.mcp_ask.append(self.allocator, owned),
            .none => return error.InvalidPolicy,
        }
    }

    fn toPolicy(self: *Builder, source_path: ?[]const u8) !schema.Policy {
        if (!self.saw_version) return error.MissingPolicyVersion;
        if (self.version_value != schema.version) return error.UnsupportedPolicyVersion;
        const mode = self.mode orelse return error.MissingPolicyMode;

        var policy: schema.Policy = .{
            .version_value = self.version_value,
            .mode = mode,
            .workspace = .{
                .root = if (self.workspace_root) |root| try self.allocator.dupe(u8, root) else try self.allocator.dupe(u8, "."),
                .write_mode = self.workspace_write_mode,
            },
            .env = .{
                .inherit = self.env_inherit,
                .allow = try self.env_allow.toOwnedSlice(self.allocator),
                .deny_patterns = try self.env_deny.toOwnedSlice(self.allocator),
                .ask = try self.env_ask.toOwnedSlice(self.allocator),
                .default = self.env_default,
            },
            .files = .{
                .read = .{
                    .allow = try self.files_read_allow.toOwnedSlice(self.allocator),
                    .deny = try self.files_read_deny.toOwnedSlice(self.allocator),
                    .ask = try self.files_read_ask.toOwnedSlice(self.allocator),
                    .default = self.files_read_default,
                },
                .write = .{
                    .allow = try self.files_write_allow.toOwnedSlice(self.allocator),
                    .deny = try self.files_write_deny.toOwnedSlice(self.allocator),
                    .ask = try self.files_write_ask.toOwnedSlice(self.allocator),
                    .default = self.files_write_default,
                },
                .write_mode = self.files_write_mode,
            },
            .commands = .{
                .allow = try self.commands_allow.toOwnedSlice(self.allocator),
                .deny = try self.commands_deny.toOwnedSlice(self.allocator),
                .ask = try self.commands_ask.toOwnedSlice(self.allocator),
                .default = self.commands_default,
            },
            .network = .{
                .allow = try self.network_allow.toOwnedSlice(self.allocator),
                .deny = try self.network_deny.toOwnedSlice(self.allocator),
                .ask = try self.network_ask.toOwnedSlice(self.allocator),
                .default = self.network_default,
            },
            .mcp = .{
                .allow = try self.mcp_allow.toOwnedSlice(self.allocator),
                .deny = try self.mcp_deny.toOwnedSlice(self.allocator),
                .ask = try self.mcp_ask.toOwnedSlice(self.allocator),
                .default = self.mcp_default,
            },
            .audit = .{
                .level = self.audit_level,
                .redact_secrets = self.audit_redact_secrets,
                .tamper_evident = self.audit_tamper_evident,
            },
            .source_path = if (source_path) |path| try self.allocator.dupe(u8, path) else null,
            .allocator = self.allocator,
        };
        errdefer policy.deinit();
        try validate.policy(&policy);
        return policy;
    }
};

fn freeList(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8)) void {
    for (list.items) |value| allocator.free(value);
    list.deinit(allocator);
}

pub fn parseFromSlice(allocator: std.mem.Allocator, text: []const u8, source_path: ?[]const u8) !schema.Policy {
    if (text.len > core.limits.max_policy_file_len) return error.PolicyFileTooLarge;
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.len == 0) return error.InvalidPolicy;
    if (trimmed[0] == '{') return parseJson(allocator, trimmed, source_path);
    return parseYaml(allocator, trimmed, source_path);
}

pub fn loadFile(allocator: std.mem.Allocator, path: []const u8) !schema.Policy {
    const text = try std.fs.cwd().readFileAlloc(allocator, path, core.limits.max_policy_file_len + 1);
    defer allocator.free(text);
    if (text.len > core.limits.max_policy_file_len) return error.PolicyFileTooLarge;
    return parseFromSlice(allocator, text, path);
}

pub fn loadPreset(allocator: std.mem.Allocator, preset: presets.Preset) !schema.Policy {
    const source = try std.fmt.allocPrint(allocator, "builtin:{s}", .{@tagName(preset)});
    defer allocator.free(source);
    return parseFromSlice(allocator, presets.text(preset), source);
}

pub fn discover(
    allocator: std.mem.Allocator,
    cli_policy_path: ?[]const u8,
    workspace_root: []const u8,
) !schema.LoadedPolicy {
    if (cli_policy_path) |path| {
        const policy = try loadFile(allocator, path);
        return .{
            .policy = policy,
            .source = .cli,
            .path = try allocator.dupe(u8, policy.source_path orelse path),
        };
    }

    const workspace_path = try std.fs.path.join(allocator, &.{ workspace_root, ".aegis", "policy.yaml" });
    defer allocator.free(workspace_path);
    if (loadFile(allocator, workspace_path)) |policy| {
        return .{
            .policy = policy,
            .source = .workspace,
            .path = try allocator.dupe(u8, policy.source_path orelse workspace_path),
        };
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }

    if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
        defer allocator.free(home);
        const user_path = try std.fs.path.join(allocator, &.{ home, ".config", "aegis", "policy.yaml" });
        defer allocator.free(user_path);
        if (loadFile(allocator, user_path)) |policy| {
            return .{
                .policy = policy,
                .source = .user,
                .path = try allocator.dupe(u8, policy.source_path orelse user_path),
            };
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        }
    } else |_| {}

    const policy = try loadPreset(allocator, presets.defaultPreset());
    return .{
        .policy = policy,
        .source = .builtin,
        .path = try allocator.dupe(u8, policy.source_path orelse "builtin:strict"),
    };
}

fn parseYaml(allocator: std.mem.Allocator, text: []const u8, source_path: ?[]const u8) !schema.Policy {
    var builder = Builder.init(allocator);
    defer builder.deinit();

    var section: Section = .root;
    var list_target: ListTarget = .none;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const cleaned = stripComment(std.mem.trimRight(u8, raw_line, " \t\r"));
        if (std.mem.trim(u8, cleaned, " \t").len == 0) continue;
        const indent = countIndent(cleaned);
        if (indent % 2 != 0) return error.InvalidPolicy;
        const line = std.mem.trim(u8, cleaned[indent..], " \t");

        if (std.mem.startsWith(u8, line, "- ")) {
            try builder.append(list_target, try parseScalar(line[2..]));
            continue;
        }

        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.InvalidPolicy;
        const key = std.mem.trim(u8, line[0..colon], " \t");
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");

        list_target = .none;
        if (indent == 0) {
            section = .root;
            if (std.mem.eql(u8, key, "version")) {
                builder.version_value = try parseU16(value);
                builder.saw_version = true;
            } else if (std.mem.eql(u8, key, "mode")) {
                builder.mode = schema.Mode.parse(try parseScalar(value)) orelse return error.UnsupportedPolicyMode;
            } else if (std.mem.eql(u8, key, "workspace")) {
                section = .workspace;
            } else if (std.mem.eql(u8, key, "env")) {
                section = .env;
            } else if (std.mem.eql(u8, key, "files")) {
                section = .files;
            } else if (std.mem.eql(u8, key, "commands")) {
                section = .commands;
            } else if (std.mem.eql(u8, key, "network")) {
                section = .network;
            } else if (std.mem.eql(u8, key, "mcp")) {
                section = .mcp;
            } else if (std.mem.eql(u8, key, "audit")) {
                section = .audit;
            } else {
                return error.InvalidPolicy;
            }
            continue;
        }

        if (indent == 2 and (section == .mcp or section == .mcp_servers or section == .mcp_server or section == .mcp_server_tools)) {
            section = .mcp;
            if (selfActiveMcpServerClear(&builder)) {}
            try applyYamlField(&builder, section, key, value, &list_target);
            if (std.mem.eql(u8, key, "servers")) section = .mcp_servers;
            continue;
        }

        if (indent == 4 and (section == .mcp_servers or section == .mcp_server or section == .mcp_server_tools)) {
            if (builder.active_mcp_server) |server| builder.allocator.free(server);
            builder.active_mcp_server = try builder.allocator.dupe(u8, key);
            section = .mcp_server;
            continue;
        }

        if (indent == 6 and section == .mcp_server) {
            if (!std.mem.eql(u8, key, "tools")) return error.InvalidPolicy;
            section = .mcp_server_tools;
            continue;
        }

        if (indent == 8 and section == .mcp_server_tools) {
            try applyRuleSetField(&builder, .mcp_allow, .mcp_deny, .mcp_ask, &builder.mcp_default, key, try parseScalar(value), &list_target);
            continue;
        }

        if (indent == 2 and (section == .files or section == .files_read or section == .files_write)) {
            if (std.mem.eql(u8, key, "read")) {
                section = .files_read;
                continue;
            } else if (std.mem.eql(u8, key, "write")) {
                section = .files_write;
                continue;
            } else {
                return error.InvalidPolicy;
            }
        }

        try applyYamlField(&builder, section, key, value, &list_target);
    }

    return builder.toPolicy(source_path);
}

fn selfActiveMcpServerClear(builder: *Builder) bool {
    if (builder.active_mcp_server) |server| {
        builder.allocator.free(server);
        builder.active_mcp_server = null;
        return true;
    }
    return false;
}

fn applyYamlField(builder: *Builder, section: Section, key: []const u8, value: []const u8, list_target: *ListTarget) !void {
    const scalar = try parseScalar(value);
    switch (section) {
        .workspace => {
            if (std.mem.eql(u8, key, "root")) {
                if (builder.workspace_root) |root| builder.allocator.free(root);
                builder.workspace_root = try builder.allocator.dupe(u8, scalar);
            } else if (std.mem.eql(u8, key, "write_mode")) {
                builder.workspace_write_mode = schema.WriteMode.parse(scalar) orelse return error.UnsupportedPolicyWriteMode;
            } else return error.InvalidPolicy;
        },
        .env => {
            if (std.mem.eql(u8, key, "inherit")) builder.env_inherit = try parseBool(scalar) else if (std.mem.eql(u8, key, "allow")) list_target.* = .env_allow else if (std.mem.eql(u8, key, "deny_patterns")) list_target.* = .env_deny else if (std.mem.eql(u8, key, "ask")) list_target.* = .env_ask else if (std.mem.eql(u8, key, "default")) builder.env_default = try parseDecision(scalar) else return error.InvalidPolicy;
        },
        .files_read => try applyRuleSetField(builder, .files_read_allow, .files_read_deny, .files_read_ask, &builder.files_read_default, key, scalar, list_target),
        .files_write => {
            if (std.mem.eql(u8, key, "mode")) builder.files_write_mode = schema.WriteMode.parse(scalar) orelse return error.UnsupportedPolicyWriteMode else try applyRuleSetField(builder, .files_write_allow, .files_write_deny, .files_write_ask, &builder.files_write_default, key, scalar, list_target);
        },
        .commands => try applyRuleSetField(builder, .commands_allow, .commands_deny, .commands_ask, &builder.commands_default, key, scalar, list_target),
        .network => try applyRuleSetField(builder, .network_allow, .network_deny, .network_ask, &builder.network_default, key, scalar, list_target),
        .mcp => {
            if (std.mem.eql(u8, key, "servers")) {
                list_target.* = .none;
            } else {
                try applyRuleSetField(builder, .mcp_allow, .mcp_deny, .mcp_ask, &builder.mcp_default, key, scalar, list_target);
            }
        },
        .audit => {
            if (std.mem.eql(u8, key, "level")) builder.audit_level = schema.AuditLevel.parse(scalar) orelse return error.UnsupportedPolicyAuditLevel else if (std.mem.eql(u8, key, "redact_secrets")) builder.audit_redact_secrets = try parseBool(scalar) else if (std.mem.eql(u8, key, "tamper_evident")) builder.audit_tamper_evident = try parseBool(scalar) else return error.InvalidPolicy;
        },
        else => return error.InvalidPolicy,
    }
}

fn applyRuleSetField(
    builder: *Builder,
    allow_target: ListTarget,
    deny_target: ListTarget,
    ask_target: ListTarget,
    default_field: *?schema.DecisionValue,
    key: []const u8,
    scalar: []const u8,
    list_target: *ListTarget,
) !void {
    _ = builder;
    if (std.mem.eql(u8, key, "allow")) list_target.* = allow_target else if (std.mem.eql(u8, key, "deny")) list_target.* = deny_target else if (std.mem.eql(u8, key, "ask")) list_target.* = ask_target else if (std.mem.eql(u8, key, "default")) default_field.* = try parseDecision(scalar) else return error.InvalidPolicy;
}

fn parseJson(allocator: std.mem.Allocator, text: []const u8, source_path: ?[]const u8) !schema.Policy {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, text, .{}) catch return error.InvalidPolicy;
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidPolicy;
    const object = parsed.value.object;
    try rejectUnknownKeys(object, &.{ "version", "mode", "workspace", "env", "files", "commands", "network", "mcp", "audit" });
    var builder = Builder.init(allocator);
    defer builder.deinit();

    if (object.get("version")) |value| {
        if (value != .integer or value.integer < 0 or value.integer > std.math.maxInt(u16)) return error.InvalidPolicy;
        builder.version_value = @intCast(value.integer);
        builder.saw_version = true;
    }
    if (object.get("mode")) |value| builder.mode = schema.Mode.parse(try expectString(value)) orelse return error.UnsupportedPolicyMode;
    if (object.get("workspace")) |value| try parseJsonWorkspace(&builder, value);
    if (object.get("env")) |value| try parseJsonEnv(&builder, value);
    if (object.get("files")) |value| try parseJsonFiles(&builder, value);
    if (object.get("commands")) |value| try parseJsonRules(&builder, value, .commands_allow, .commands_deny, .commands_ask, &builder.commands_default);
    if (object.get("network")) |value| try parseJsonRules(&builder, value, .network_allow, .network_deny, .network_ask, &builder.network_default);
    if (object.get("mcp")) |value| try parseJsonMcp(&builder, value);
    if (object.get("audit")) |value| try parseJsonAudit(&builder, value);
    return builder.toPolicy(source_path);
}

fn parseJsonWorkspace(builder: *Builder, value: std.json.Value) !void {
    if (value != .object) return error.InvalidPolicy;
    const object = value.object;
    try rejectUnknownKeys(object, &.{ "root", "write_mode" });
    if (object.get("root")) |root| builder.workspace_root = try builder.allocator.dupe(u8, try expectString(root));
    if (object.get("write_mode")) |mode| builder.workspace_write_mode = schema.WriteMode.parse(try expectString(mode)) orelse return error.UnsupportedPolicyWriteMode;
}

fn parseJsonEnv(builder: *Builder, value: std.json.Value) !void {
    if (value != .object) return error.InvalidPolicy;
    const object = value.object;
    try rejectUnknownKeys(object, &.{ "inherit", "allow", "deny_patterns", "ask", "default" });
    if (object.get("inherit")) |inherit| builder.env_inherit = try expectBool(inherit);
    if (object.get("allow")) |list| try appendJsonList(builder, .env_allow, list);
    if (object.get("deny_patterns")) |list| try appendJsonList(builder, .env_deny, list);
    if (object.get("ask")) |list| try appendJsonList(builder, .env_ask, list);
    if (object.get("default")) |default| builder.env_default = schema.DecisionValue.parse(try expectString(default)) orelse return error.UnsupportedPolicyDecision;
}

fn parseJsonFiles(builder: *Builder, value: std.json.Value) !void {
    if (value != .object) return error.InvalidPolicy;
    const object = value.object;
    try rejectUnknownKeys(object, &.{ "read", "write" });
    if (object.get("read")) |read| try parseJsonRules(builder, read, .files_read_allow, .files_read_deny, .files_read_ask, &builder.files_read_default);
    if (object.get("write")) |write| {
        try parseJsonRulesWithKeys(builder, write, .files_write_allow, .files_write_deny, .files_write_ask, &builder.files_write_default, &.{ "allow", "deny", "ask", "default", "mode" });
        if (write == .object) {
            if (write.object.get("mode")) |mode| builder.files_write_mode = schema.WriteMode.parse(try expectString(mode)) orelse return error.UnsupportedPolicyWriteMode;
        }
    }
}

fn parseJsonRules(builder: *Builder, value: std.json.Value, allow: ListTarget, deny: ListTarget, ask: ListTarget, default_field: *?schema.DecisionValue) !void {
    try parseJsonRulesWithKeys(builder, value, allow, deny, ask, default_field, &.{ "allow", "deny", "ask", "default" });
}

fn parseJsonRulesWithKeys(builder: *Builder, value: std.json.Value, allow: ListTarget, deny: ListTarget, ask: ListTarget, default_field: *?schema.DecisionValue, allowed_keys: []const []const u8) !void {
    if (value != .object) return error.InvalidPolicy;
    const object = value.object;
    try rejectUnknownKeys(object, allowed_keys);
    if (object.get("allow")) |list| try appendJsonList(builder, allow, list);
    if (object.get("deny")) |list| try appendJsonList(builder, deny, list);
    if (object.get("ask")) |list| try appendJsonList(builder, ask, list);
    if (object.get("default")) |default| default_field.* = schema.DecisionValue.parse(try expectString(default)) orelse return error.UnsupportedPolicyDecision;
}

fn parseJsonMcp(builder: *Builder, value: std.json.Value) !void {
    try parseJsonRulesWithKeys(builder, value, .mcp_allow, .mcp_deny, .mcp_ask, &builder.mcp_default, &.{ "allow", "deny", "ask", "default", "servers" });
    if (value.object.get("servers")) |servers| {
        if (servers != .object) return error.InvalidPolicy;
        var it = servers.object.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* != .object) return error.InvalidPolicy;
            try rejectUnknownKeys(entry.value_ptr.*.object, &.{ "tools" });
            const tools = entry.value_ptr.*.object.get("tools") orelse return error.InvalidPolicy;
            if (tools != .object) return error.InvalidPolicy;
            if (builder.active_mcp_server) |server| builder.allocator.free(server);
            builder.active_mcp_server = try builder.allocator.dupe(u8, entry.key_ptr.*);
            try parseJsonRules(builder, tools, .mcp_allow, .mcp_deny, .mcp_ask, &builder.mcp_default);
            if (builder.active_mcp_server) |server| {
                builder.allocator.free(server);
                builder.active_mcp_server = null;
            }
        }
    }
}

fn parseJsonAudit(builder: *Builder, value: std.json.Value) !void {
    if (value != .object) return error.InvalidPolicy;
    const object = value.object;
    try rejectUnknownKeys(object, &.{ "level", "redact_secrets", "tamper_evident" });
    if (object.get("level")) |level| builder.audit_level = schema.AuditLevel.parse(try expectString(level)) orelse return error.UnsupportedPolicyAuditLevel;
    if (object.get("redact_secrets")) |redact| builder.audit_redact_secrets = try expectBool(redact);
    if (object.get("tamper_evident")) |tamper| builder.audit_tamper_evident = try expectBool(tamper);
}

fn appendJsonList(builder: *Builder, target: ListTarget, value: std.json.Value) !void {
    if (value != .array) return error.InvalidPolicy;
    for (value.array.items) |item| try builder.append(target, try expectString(item));
}

fn rejectUnknownKeys(object: std.json.ObjectMap, allowed_keys: []const []const u8) !void {
    var it = object.iterator();
    while (it.next()) |entry| {
        if (!containsString(allowed_keys, entry.key_ptr.*)) return error.InvalidPolicy;
    }
}

fn containsString(values: []const []const u8, needle: []const u8) bool {
    for (values) |value| {
        if (std.mem.eql(u8, value, needle)) return true;
    }
    return false;
}

fn expectString(value: std.json.Value) ![]const u8 {
    if (value != .string) return error.InvalidPolicy;
    return value.string;
}

fn expectBool(value: std.json.Value) !bool {
    if (value != .bool) return error.InvalidPolicy;
    return value.bool;
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

fn parseScalar(raw: []const u8) ![]const u8 {
    const value = std.mem.trim(u8, raw, " \t");
    if (value.len >= 2 and ((value[0] == '"' and value[value.len - 1] == '"') or (value[0] == '\'' and value[value.len - 1] == '\''))) {
        return value[1 .. value.len - 1];
    }
    return value;
}

fn parseU16(value: []const u8) !u16 {
    return std.fmt.parseInt(u16, try parseScalar(value), 10) catch return error.InvalidPolicy;
}

fn parseBool(value: []const u8) !bool {
    if (std.mem.eql(u8, value, "true")) return true;
    if (std.mem.eql(u8, value, "false")) return false;
    return error.InvalidPolicy;
}

fn parseDecision(value: []const u8) !schema.DecisionValue {
    return schema.DecisionValue.parse(value) orelse error.UnsupportedPolicyDecision;
}

test "valid YAML policy parsing covers minimum schema" {
    var policy = try parseFromSlice(std.testing.allocator, presets.text(.strict), "builtin:strict");
    defer policy.deinit();

    try std.testing.expectEqual(schema.version, policy.version_value);
    try std.testing.expectEqual(schema.Mode.strict, policy.mode);
    try std.testing.expect(policy.files.read.deny.len >= 1);
    try std.testing.expect(policy.commands.deny.len >= 1);
    try std.testing.expect(policy.network.allow.len >= 1);
}

test "invalid policies fail closed with clear parser errors" {
    try std.testing.expectError(error.MissingPolicyMode, parseFromSlice(std.testing.allocator, "version: 1\n", "bad.yaml"));
    try std.testing.expectError(error.UnsupportedPolicyMode, parseFromSlice(std.testing.allocator, "version: 1\nmode: loose\n", "bad.yaml"));
}

test "policy discovery honors CLI path before workspace policy" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath(".aegis");
    {
        const file = try tmp.dir.createFile(".aegis/policy.yaml", .{});
        defer file.close();
        try file.writeAll(presets.text(.observe));
    }
    {
        const file = try tmp.dir.createFile("strict.yaml", .{});
        defer file.close();
        try file.writeAll(presets.text(.strict));
    }
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    const cli_path = try tmp.dir.realpathAlloc(std.testing.allocator, "strict.yaml");
    defer std.testing.allocator.free(cli_path);

    var loaded = try discover(std.testing.allocator, cli_path, root);
    defer loaded.deinit();
    try std.testing.expectEqual(schema.LoadSource.cli, loaded.source);
    try std.testing.expectEqual(schema.Mode.strict, loaded.policy.mode);
}

test "workspace policy discovery falls back only when missing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath(".aegis");
    {
        const file = try tmp.dir.createFile(".aegis/policy.yaml", .{});
        defer file.close();
        try file.writeAll("version: 1\nmode: loose\n");
    }
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    try std.testing.expectError(error.UnsupportedPolicyMode, discover(std.testing.allocator, null, root));
}

test "JSON policies reject unknown keys instead of silently changing policy meaning" {
    try std.testing.expectError(error.InvalidPolicy, parseFromSlice(std.testing.allocator,
        \\{"version":1,"mode":"strict","commands":{"denny":["rm -rf *"]}}
    , "bad.json"));

    try std.testing.expectError(error.InvalidPolicy, parseFromSlice(std.testing.allocator,
        \\{"version":1,"mode":"strict","defualt":"allow"}
    , "bad.json"));
}

test "MCP server-scoped policy shape flattens to server tool selectors" {
    var yaml_policy = try parseFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: strict
        \\mcp:
        \\  default: ask
        \\  servers:
        \\    github:
        \\      tools:
        \\        allow:
        \\          - search_repositories
        \\          - get_file_contents
        \\        ask:
        \\          - create_issue
        \\        deny:
        \\          - delete_repository
    , "mcp.yaml");
    defer yaml_policy.deinit();
    try std.testing.expectEqualStrings("github.search_repositories", yaml_policy.mcp.allow[0]);
    try std.testing.expectEqualStrings("github.create_issue", yaml_policy.mcp.ask[0]);
    try std.testing.expectEqualStrings("github.delete_repository", yaml_policy.mcp.deny[0]);

    var json_policy = try parseFromSlice(std.testing.allocator,
        \\{"version":1,"mode":"strict","mcp":{"default":"ask","servers":{"github":{"tools":{"allow":["search_repositories"],"deny":["delete_repository"]}}}}}
    , "mcp.json");
    defer json_policy.deinit();
    try std.testing.expectEqualStrings("github.search_repositories", json_policy.mcp.allow[0]);
    try std.testing.expectEqualStrings("github.delete_repository", json_policy.mcp.deny[0]);
}
