const std = @import("std");
const core = @import("orca_core");
const data_classification = @import("data_classification.zig");
const endpoint_policy = @import("endpoint_policy.zig");

pub const EvaluationMode = enum {
    observe,
    ask,
    strict,
    ci,
    redteam,
    simulation,
    bench,

    pub fn toString(self: EvaluationMode) []const u8 {
        return @tagName(self);
    }

    pub fn parse(value: []const u8) ?EvaluationMode {
        inline for (std.meta.fields(EvaluationMode)) |field| {
            if (data_classification.matchesNormalized(field.name, value)) return @field(EvaluationMode, field.name);
        }
        if (data_classification.matchesNormalized("enforce", value)) return .strict;
        return null;
    }
};

pub const RedactPrecision = enum {
    none,
    coarse,
    full,

    pub fn parse(value: []const u8) ?RedactPrecision {
        inline for (std.meta.fields(RedactPrecision)) |field| {
            if (data_classification.matchesNormalized(field.name, value)) return @field(RedactPrecision, field.name);
        }
        return null;
    }
};

pub const EgressSettings = struct {
    detect_long_query_strings: bool = true,
    detect_high_entropy_labels: bool = true,
    detect_secret_patterns: bool = true,
    max_payload_bytes: usize = 262_144,
    max_url_bytes: usize = 4096,
};

pub const TelemetryRule = struct {
    channel: data_classification.ChannelKind,
    decision: core.decision.DecisionResult,
    id: []const u8,
};

pub const EndpointRule = struct {
    label: ?[]const u8 = null,
    host_pattern: ?[]const u8 = null,
    port: ?u16 = null,
    decision: core.decision.DecisionResult,
    id: []const u8,
};

pub const DataClassRule = struct {
    class: data_classification.DataClass,
    default_decision: core.decision.DecisionResult,
    redact_precision: RedactPrecision = .none,
    id: []const u8,
};

pub const Policy = struct {
    mode: EvaluationMode = .strict,
    default_decision: core.decision.DecisionResult = .deny,
    telemetry_rules: []const TelemetryRule = &.{},
    endpoint_rules: []const EndpointRule = &.{},
    data_class_rules: []const DataClassRule = &.{},
    egress: EgressSettings = .{},

    pub fn resolveChannel(self: Policy, channel: data_classification.ChannelKind) RuleDecision {
        var selected: ?RuleDecision = null;
        for (self.telemetry_rules) |rule| {
            if (rule.channel == channel) {
                if (rule.decision == .deny) return .{ .decision = .deny, .rule_id = rule.id };
                selected = .{ .decision = rule.decision, .rule_id = rule.id };
            }
        }
        return selected orelse .{ .decision = self.default_decision, .rule_id = "data_guard.default" };
    }

    pub fn resolveDataClass(self: Policy, class: data_classification.DataClass) RuleDecision {
        var selected: ?RuleDecision = null;
        for (self.data_class_rules) |rule| {
            if (rule.class == class) {
                if (rule.default_decision == .deny) return .{ .decision = .deny, .rule_id = rule.id };
                selected = .{ .decision = rule.default_decision, .rule_id = rule.id };
            }
        }
        return selected orelse .{ .decision = builtinDefaultForClass(class, self.default_decision), .rule_id = "data_guard.data_class.default" };
    }

    pub fn precisionForClass(self: Policy, class: data_classification.DataClass) RedactPrecision {
        for (self.data_class_rules) |rule| {
            if (rule.class == class) return rule.redact_precision;
        }
        return if (class == .geolocation) .coarse else .none;
    }

    pub fn resolveEndpoint(self: Policy, endpoint: endpoint_policy.Endpoint, classification: endpoint_policy.Classification) RuleDecision {
        var selected: ?RuleDecision = null;
        for (self.endpoint_rules) |rule| {
            if (endpointRuleMatches(rule, endpoint)) {
                if (rule.decision == .deny) return .{ .decision = .deny, .rule_id = rule.id };
                if (selected == null or selected.?.decision != .allow or rule.decision == .allow) {
                    selected = .{ .decision = rule.decision, .rule_id = rule.id };
                }
            }
        }
        if (selected) |decision| return decision;
        return switch (classification.kind) {
            .webhook, .tunnel_service, .paste_site, .direct_ip, .unknown, .cloud_endpoint => .{ .decision = self.default_decision, .rule_id = "data_guard.endpoint.default" },
            else => .{ .decision = if (self.default_decision == .deny) .ask else self.default_decision, .rule_id = "data_guard.endpoint.implicit_local" },
        };
    }
};

pub const RuleDecision = struct {
    decision: core.decision.DecisionResult,
    rule_id: []const u8,
};

pub const LoadedPolicy = struct {
    arena: std.heap.ArenaAllocator,
    value: Policy,

    pub fn deinit(self: *LoadedPolicy) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

const Section = enum {
    root,
    data_guard,
    telemetry,
    telemetry_allow,
    telemetry_ask,
    telemetry_deny,
    endpoints,
    endpoints_allow,
    endpoints_ask,
    endpoints_deny,
    data_classes,
    data_class_rule,
    egress,
};

const PendingEndpoint = struct {
    active: bool = false,
    decision: core.decision.DecisionResult = .deny,
    label: ?[]const u8 = null,
    host_pattern: ?[]const u8 = null,
    port: ?u16 = null,
};

pub fn loadFile(allocator: std.mem.Allocator, path: []const u8) !LoadedPolicy {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const aa = arena.allocator();
    const text = try std.fs.cwd().readFileAlloc(aa, path, 128 * 1024);
    const value = try parseYaml(aa, text);
    return .{ .arena = arena, .value = value };
}

pub fn parseYaml(allocator: std.mem.Allocator, text: []const u8) !Policy {
    var telemetry_rules: std.ArrayList(TelemetryRule) = .empty;
    var endpoint_rules: std.ArrayList(EndpointRule) = .empty;
    var data_rules: std.ArrayList(DataClassRule) = .empty;
    var mode: EvaluationMode = .strict;
    var default_decision: core.decision.DecisionResult = .deny;
    var egress: EgressSettings = .{};
    var section: Section = .root;
    var current_class: ?data_classification.DataClass = null;
    var pending_endpoint: PendingEndpoint = .{};

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const no_comment = if (std.mem.indexOfScalar(u8, raw_line, '#')) |index| raw_line[0..index] else raw_line;
        const line = std.mem.trimRight(u8, no_comment, " \t\r");
        if (std.mem.trim(u8, line, " \t\r").len == 0) continue;
        const indent = countIndent(line);
        const trimmed = std.mem.trimLeft(u8, line, " ");

        if (indent <= 4 and pending_endpoint.active and (std.mem.startsWith(u8, trimmed, "-") or (indent <= 2 and !std.mem.startsWith(u8, trimmed, "host:") and !std.mem.startsWith(u8, trimmed, "port:") and !std.mem.startsWith(u8, trimmed, "label:")))) {
            try flushEndpoint(allocator, &endpoint_rules, &pending_endpoint);
        }

        if (std.mem.startsWith(u8, trimmed, "-")) {
            const item = cleanScalar(std.mem.trim(u8, trimmed[1..], " \t"));
            switch (section) {
                .telemetry_allow => try appendChannelRule(allocator, &telemetry_rules, item, .allow),
                .telemetry_ask => try appendChannelRule(allocator, &telemetry_rules, item, .ask),
                .telemetry_deny => try appendChannelRule(allocator, &telemetry_rules, item, .deny),
                .endpoints_allow => try startEndpointRule(allocator, &endpoint_rules, &pending_endpoint, item, .allow),
                .endpoints_ask => try startEndpointRule(allocator, &endpoint_rules, &pending_endpoint, item, .ask),
                .endpoints_deny => try startEndpointRule(allocator, &endpoint_rules, &pending_endpoint, item, .deny),
                else => {},
            }
            continue;
        }

        const pair = splitKeyValue(trimmed) catch continue;
        const key = pair.key;
        const value = pair.value;
        if (indent == 0) {
            if (std.mem.eql(u8, key, "mode")) {
                mode = EvaluationMode.parse(value) orelse return error.InvalidDataGuardPolicy;
            } else if (std.mem.eql(u8, key, "data_guard")) {
                section = .data_guard;
            }
            continue;
        }
        if (section == .root) continue;
        if (indent == 2) {
            if (std.mem.eql(u8, key, "default")) default_decision = parseDecision(value) orelse return error.InvalidDataGuardPolicy else if (std.mem.eql(u8, key, "telemetry")) section = .telemetry else if (std.mem.eql(u8, key, "endpoints")) section = .endpoints else if (std.mem.eql(u8, key, "data_classes")) section = .data_classes else if (std.mem.eql(u8, key, "egress")) section = .egress else {}
            continue;
        }
        if (indent == 4 and (section == .telemetry or section == .telemetry_allow or section == .telemetry_ask or section == .telemetry_deny)) {
            if (std.mem.eql(u8, key, "allow")) section = .telemetry_allow else if (std.mem.eql(u8, key, "ask")) section = .telemetry_ask else if (std.mem.eql(u8, key, "deny")) section = .telemetry_deny;
            continue;
        }
        if (indent == 4 and (section == .endpoints or section == .endpoints_allow or section == .endpoints_ask or section == .endpoints_deny)) {
            if (std.mem.eql(u8, key, "allow")) section = .endpoints_allow else if (std.mem.eql(u8, key, "ask")) section = .endpoints_ask else if (std.mem.eql(u8, key, "deny")) section = .endpoints_deny;
            continue;
        }
        if (indent == 4 and (section == .data_classes or section == .data_class_rule)) {
            current_class = data_classification.DataClass.parse(key) orelse return error.InvalidDataGuardPolicy;
            section = .data_class_rule;
            continue;
        }
        if (indent == 6 and section == .data_class_rule) {
            const class = current_class orelse return error.InvalidDataGuardPolicy;
            if (std.mem.eql(u8, key, "default")) {
                try data_rules.append(allocator, .{ .class = class, .default_decision = parseDecision(value) orelse return error.InvalidDataGuardPolicy, .id = try std.fmt.allocPrint(allocator, "data_class.{s}", .{class.toString()}) });
            } else if (std.mem.eql(u8, key, "redact_precision")) {
                if (data_rules.items.len == 0 or data_rules.items[data_rules.items.len - 1].class != class) {
                    try data_rules.append(allocator, .{ .class = class, .default_decision = builtinDefaultForClass(class, default_decision), .id = try std.fmt.allocPrint(allocator, "data_class.{s}", .{class.toString()}) });
                }
                data_rules.items[data_rules.items.len - 1].redact_precision = RedactPrecision.parse(value) orelse return error.InvalidDataGuardPolicy;
            }
            continue;
        }
        if ((section == .endpoints_allow or section == .endpoints_ask or section == .endpoints_deny) and pending_endpoint.active) {
            if (std.mem.eql(u8, key, "host")) pending_endpoint.host_pattern = try allocator.dupe(u8, value) else if (std.mem.eql(u8, key, "label")) pending_endpoint.label = try allocator.dupe(u8, value) else if (std.mem.eql(u8, key, "port")) pending_endpoint.port = std.fmt.parseInt(u16, value, 10) catch return error.InvalidDataGuardPolicy;
            continue;
        }
        if (section == .egress and indent == 4) {
            if (std.mem.eql(u8, key, "detect_long_query_strings")) egress.detect_long_query_strings = try parseBool(value) else if (std.mem.eql(u8, key, "detect_high_entropy_labels")) egress.detect_high_entropy_labels = try parseBool(value) else if (std.mem.eql(u8, key, "detect_secret_patterns")) egress.detect_secret_patterns = try parseBool(value) else if (std.mem.eql(u8, key, "max_payload_bytes")) egress.max_payload_bytes = std.fmt.parseInt(usize, value, 10) catch return error.InvalidDataGuardPolicy else if (std.mem.eql(u8, key, "max_url_bytes")) egress.max_url_bytes = std.fmt.parseInt(usize, value, 10) catch return error.InvalidDataGuardPolicy;
        }
    }
    if (pending_endpoint.active) try flushEndpoint(allocator, &endpoint_rules, &pending_endpoint);
    return .{
        .mode = mode,
        .default_decision = default_decision,
        .telemetry_rules = try telemetry_rules.toOwnedSlice(allocator),
        .endpoint_rules = try endpoint_rules.toOwnedSlice(allocator),
        .data_class_rules = try data_rules.toOwnedSlice(allocator),
        .egress = egress,
    };
}

pub fn defaultSimulationPolicy() Policy {
    return .{
        .mode = .simulation,
        .default_decision = .deny,
        .telemetry_rules = &.{
            .{ .channel = .heartbeat, .decision = .allow, .id = "telemetry.allow.heartbeat" },
            .{ .channel = .health_status, .decision = .allow, .id = "telemetry.allow.health_status" },
            .{ .channel = .mavlink_telemetry, .decision = .allow, .id = "telemetry.allow.mavlink_local" },
            .{ .channel = .command_control, .decision = .allow, .id = "telemetry.allow.command_control_local" },
            .{ .channel = .mission_upload, .decision = .allow, .id = "telemetry.allow.mission_upload_local" },
            .{ .channel = .mission_download, .decision = .allow, .id = "telemetry.allow.mission_download_local" },
        },
        .endpoint_rules = &.{
            .{ .label = "fake_adapter", .host_pattern = "127.0.0.1", .decision = .allow, .id = "endpoint.allow.fake_adapter" },
            .{ .label = "ground_control", .host_pattern = "127.0.0.1", .decision = .allow, .id = "endpoint.allow.ground_control" },
            .{ .label = "px4_sitl", .host_pattern = "127.0.0.1", .port = 14540, .decision = .allow, .id = "endpoint.allow.px4_sitl" },
            .{ .label = "ardupilot_sitl", .host_pattern = "127.0.0.1", .port = 14550, .decision = .allow, .id = "endpoint.allow.ardupilot_sitl" },
        },
        .data_class_rules = &.{
            .{ .class = .vehicle_state, .default_decision = .allow, .id = "data_class.vehicle_state.local" },
            .{ .class = .vehicle_identifier, .default_decision = .allow, .id = "data_class.vehicle_identifier.local" },
            .{ .class = .mission_plan, .default_decision = .allow, .id = "data_class.mission_plan.local" },
            .{ .class = .geolocation, .default_decision = .allow, .redact_precision = .coarse, .id = "data_class.geolocation.local" },
            .{ .class = .operational, .default_decision = .allow, .id = "data_class.operational.local" },
            .{ .class = .audit_metadata, .default_decision = .allow, .id = "data_class.audit_metadata.local" },
        },
    };
}

pub fn builtinDefaultForClass(class: data_classification.DataClass, fallback: core.decision.DecisionResult) core.decision.DecisionResult {
    return switch (class) {
        .credential, .secret, .video_stream, .image_frame, .audio_stream => .deny,
        .mission_plan, .geolocation, .operator_identifier, .customer_identifier, .unknown => if (fallback == .allow) .ask else fallback,
        else => fallback,
    };
}

fn appendChannelRule(allocator: std.mem.Allocator, rules: *std.ArrayList(TelemetryRule), item: []const u8, decision: core.decision.DecisionResult) !void {
    const value = if (std.mem.startsWith(u8, item, "channel:")) cleanScalar(item["channel:".len..]) else item;
    const channel = data_classification.ChannelKind.parse(value) orelse return error.InvalidDataGuardPolicy;
    try rules.append(allocator, .{ .channel = channel, .decision = decision, .id = try std.fmt.allocPrint(allocator, "telemetry.{s}.{s}", .{ decision.toString(), channel.toString() }) });
}

fn startEndpointRule(allocator: std.mem.Allocator, rules: *std.ArrayList(EndpointRule), pending: *PendingEndpoint, item: []const u8, decision: core.decision.DecisionResult) !void {
    if (pending.active) try flushEndpoint(allocator, rules, pending);
    pending.* = .{ .active = true, .decision = decision };
    if (std.mem.startsWith(u8, item, "label:")) {
        pending.label = try allocator.dupe(u8, cleanScalar(item["label:".len..]));
    } else if (std.mem.startsWith(u8, item, "host:")) {
        pending.host_pattern = try allocator.dupe(u8, cleanScalar(item["host:".len..]));
    } else if (item.len > 0) {
        pending.host_pattern = try allocator.dupe(u8, item);
    }
}

fn flushEndpoint(allocator: std.mem.Allocator, rules: *std.ArrayList(EndpointRule), pending: *PendingEndpoint) !void {
    if (!pending.active) return;
    const label = pending.label;
    const pattern = pending.host_pattern;
    const id_base = label orelse pattern orelse "endpoint";
    try rules.append(allocator, .{
        .label = label,
        .host_pattern = pattern,
        .port = pending.port,
        .decision = pending.decision,
        .id = try std.fmt.allocPrint(allocator, "endpoint.{s}.{s}", .{ pending.decision.toString(), id_base }),
    });
    pending.* = .{};
}

fn endpointRuleMatches(rule: EndpointRule, endpoint: endpoint_policy.Endpoint) bool {
    if (rule.label) |label| {
        if (!globOrEqual(label, endpoint.label)) return false;
    }
    if (rule.host_pattern) |pattern| {
        if (!globOrEqual(pattern, endpoint.host)) return false;
    }
    if (rule.port) |port| {
        if (endpoint.port == null or endpoint.port.? != port) return false;
    }
    return rule.label != null or rule.host_pattern != null or rule.port != null;
}

fn globOrEqual(pattern: []const u8, value: []const u8) bool {
    if (std.mem.startsWith(u8, pattern, "*.")) {
        const suffix = pattern[1..];
        return std.ascii.endsWithIgnoreCase(value, suffix);
    }
    return std.ascii.eqlIgnoreCase(pattern, value);
}

fn parseDecision(value: []const u8) ?core.decision.DecisionResult {
    inline for (std.meta.fields(core.decision.DecisionResult)) |field| {
        if (data_classification.matchesNormalized(field.name, value)) return @field(core.decision.DecisionResult, field.name);
    }
    return null;
}

fn parseBool(value: []const u8) !bool {
    if (std.mem.eql(u8, value, "true")) return true;
    if (std.mem.eql(u8, value, "false")) return false;
    return error.InvalidDataGuardPolicy;
}

const Pair = struct { key: []const u8, value: []const u8 };

fn splitKeyValue(line: []const u8) !Pair {
    const index = std.mem.indexOfScalar(u8, line, ':') orelse return error.InvalidDataGuardPolicy;
    return .{ .key = std.mem.trim(u8, line[0..index], " \t"), .value = cleanScalar(line[index + 1 ..]) };
}

fn cleanScalar(raw: []const u8) []const u8 {
    var value = std.mem.trim(u8, raw, " \t\r");
    if (value.len >= 2) {
        const first = value[0];
        const last = value[value.len - 1];
        if ((first == '"' and last == '"') or (first == '\'' and last == '\'')) value = value[1 .. value.len - 1];
    }
    return value;
}

fn countIndent(line: []const u8) usize {
    var count: usize = 0;
    while (count < line.len and line[count] == ' ') : (count += 1) {}
    return count;
}

test "loads strict data guard policy shape" {
    const text =
        \\mode: strict
        \\data_guard:
        \\  default: deny
        \\  telemetry:
        \\    allow:
        \\      - channel: heartbeat
        \\    deny:
        \\      - channel: video_stream
        \\  endpoints:
        \\    allow:
        \\      - label: ground_control
        \\        host: "127.0.0.1"
        \\        port: 14550
        \\    deny:
        \\      - "*.webhook.site"
        \\  data_classes:
        \\    geolocation:
        \\      default: ask
        \\      redact_precision: coarse
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const policy = try parseYaml(arena.allocator(), text);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, policy.resolveChannel(.video_stream).decision);
    try std.testing.expectEqual(core.decision.DecisionResult.ask, policy.resolveDataClass(.geolocation).decision);
}
