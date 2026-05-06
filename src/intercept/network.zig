const std = @import("std");

const audit_redact = @import("../audit/redact_bridge.zig");
const core = @import("../core/mod.zig");
const matchers = @import("../policy/matchers.zig");
const schema = @import("../policy/schema.zig");

pub const implemented = true;

pub const NetworkMode = enum {
    off,
    ask,
    allowlist,
    observe,
    open,

    pub fn parse(value: []const u8) ?NetworkMode {
        inline for (@typeInfo(NetworkMode).@"enum".fields) |field| {
            if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
        }
        return null;
    }

    pub fn toString(self: NetworkMode) []const u8 {
        return @tagName(self);
    }
};

pub const EnforcementMode = enum {
    direct,
    proxy_mediated,
    shim_mediated,
    observe_only,
    unavailable,

    pub fn toString(self: EnforcementMode) []const u8 {
        return switch (self) {
            .direct => "direct",
            .proxy_mediated => "proxy-mediated",
            .shim_mediated => "shim-mediated",
            .observe_only => "observe-only",
            .unavailable => "unavailable",
        };
    }
};

pub const HostClass = enum {
    domain,
    direct_ip,
    localhost,
    private_network,
    cloud_metadata,
    invalid,
};

pub const Destination = struct {
    raw: []const u8,
    scheme: ?[]const u8 = null,
    host: []const u8,
    port: ?u16 = null,
    path: []const u8 = "",
    query: []const u8 = "",
    host_class: HostClass,

    pub fn endpointDisplay(self: Destination, allocator: std.mem.Allocator) ![]u8 {
        if (self.port) |port| return std.fmt.allocPrint(allocator, "{s}:{d}", .{ self.host, port });
        return allocator.dupe(u8, self.host);
    }
};

pub const ExfilSignal = enum {
    long_query_string,
    base64_like_url_component,
    high_entropy_dns_label,
    paste_site_destination,
    webhook_request_bin_destination,
    tunneling_service_destination,
    direct_ip_destination,
    secret_like_url_value,
    long_subdomain,
    many_unknown_domains,

    pub fn reason(self: ExfilSignal) []const u8 {
        return switch (self) {
            .long_query_string => "long query string",
            .base64_like_url_component => "base64-like URL component",
            .high_entropy_dns_label => "high-entropy DNS label",
            .paste_site_destination => "paste-site destination",
            .webhook_request_bin_destination => "webhook/request-bin destination",
            .tunneling_service_destination => "tunneling service destination",
            .direct_ip_destination => "direct IP destination",
            .secret_like_url_value => "secret-like URL value",
            .long_subdomain => "long subdomain",
            .many_unknown_domains => "repeated attempts to many unknown domains",
        };
    }
};

pub const ExfilFinding = struct {
    signal: ExfilSignal,
    score: u8,
};

pub const Decision = struct {
    destination: Destination,
    decision: core.decision.Decision,
    matched_rule: ?schema.RuleRef = null,
    enforcement_mode: EnforcementMode,
    exfil_findings: []ExfilFinding = &.{},
    redacted_target: []u8,
    owned_reason: []u8,
    owned_rule_id: ?[]u8 = null,
    owned_findings: bool = false,

    pub fn deinit(self: Decision, allocator: std.mem.Allocator) void {
        allocator.free(self.redacted_target);
        allocator.free(self.owned_reason);
        if (self.owned_rule_id) |rule_id| allocator.free(rule_id);
        if (self.owned_findings and self.exfil_findings.len > 0) allocator.free(self.exfil_findings);
    }
};

pub const UnknownDomainTracker = struct {
    allocator: std.mem.Allocator,
    hosts: std.StringHashMap(void),

    pub fn init(allocator: std.mem.Allocator) UnknownDomainTracker {
        return .{ .allocator = allocator, .hosts = std.StringHashMap(void).init(allocator) };
    }

    pub fn deinit(self: *UnknownDomainTracker) void {
        var it = self.hosts.keyIterator();
        while (it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.hosts.deinit();
    }

    pub fn record(self: *UnknownDomainTracker, host: []const u8) !bool {
        if (self.hosts.contains(host)) return self.hosts.count() >= 5;
        const owned = try self.allocator.dupe(u8, host);
        errdefer self.allocator.free(owned);
        try self.hosts.put(owned, {});
        return self.hosts.count() >= 5;
    }
};

pub const Options = struct {
    ci_mode: bool = false,
    enforcement_mode: EnforcementMode = .direct,
    unknown_tracker: ?*UnknownDomainTracker = null,
};

const Match = struct {
    label: []const u8,
    index: usize,
    pattern: []const u8,
};

pub fn parseDestination(input: []const u8) !Destination {
    if (input.len == 0 or input.len > core.limits.max_url_len) return error.InvalidNetworkDestination;
    if (!std.unicode.utf8ValidateSlice(input)) return error.InvalidNetworkDestination;
    if (std.mem.indexOfScalar(u8, input, 0) != null) return error.InvalidNetworkDestination;

    var rest = std.mem.trim(u8, input, " \t\r\n");
    var scheme: ?[]const u8 = null;
    if (std.mem.indexOf(u8, rest, "://")) |scheme_end| {
        if (scheme_end == 0) return error.InvalidNetworkDestination;
        scheme = rest[0..scheme_end];
        rest = rest[scheme_end + 3 ..];
    }

    const authority_end = std.mem.indexOfAny(u8, rest, "/?#") orelse rest.len;
    var authority = rest[0..authority_end];
    var path: []const u8 = "";
    var query: []const u8 = "";
    const tail = rest[authority_end..];
    if (tail.len > 0) {
        const query_start = std.mem.indexOfScalar(u8, tail, '?');
        if (query_start) |idx| {
            path = tail[0..idx];
            const after_question = tail[idx + 1 ..];
            const fragment = std.mem.indexOfScalar(u8, after_question, '#') orelse after_question.len;
            query = after_question[0..fragment];
        } else {
            const fragment = std.mem.indexOfScalar(u8, tail, '#') orelse tail.len;
            path = tail[0..fragment];
        }
    }

    if (std.mem.indexOfScalar(u8, authority, '@')) |at| authority = authority[at + 1 ..];
    if (authority.len == 0) return error.InvalidNetworkDestination;

    var host: []const u8 = authority;
    var port: ?u16 = null;
    if (authority[0] == '[') {
        const close = std.mem.indexOfScalar(u8, authority, ']') orelse return error.InvalidNetworkDestination;
        host = authority[1..close];
        if (authority.len > close + 1) {
            if (authority[close + 1] != ':') return error.InvalidNetworkDestination;
            port = try parsePort(authority[close + 2 ..]);
        }
    } else if (std.mem.lastIndexOfScalar(u8, authority, ':')) |colon| {
        if (std.mem.indexOfScalar(u8, authority[0..colon], ':') == null) {
            host = authority[0..colon];
            port = try parsePort(authority[colon + 1 ..]);
        }
    }
    host = trimTrailingDot(std.mem.trim(u8, host, " \t\r\n"));
    if (host.len == 0 or host.len > 253) return error.InvalidNetworkDestination;

    return .{
        .raw = input,
        .scheme = scheme,
        .host = host,
        .port = port,
        .path = path,
        .query = query,
        .host_class = classifyHost(host),
    };
}

pub fn evaluate(
    allocator: std.mem.Allocator,
    policy: *const schema.Policy,
    effective_mode: schema.Mode,
    destination_text: []const u8,
    options: Options,
) !Decision {
    const destination = parseDestination(destination_text) catch |err| {
        if (effective_mode == .ci or effective_mode == .strict or policy.network.effectiveMode() == .off or policy.network.effectiveMode() == .allowlist) {
            const target = try allocator.dupe(u8, "[invalid-network-destination]");
            const reason = try allocator.dupe(u8, "invalid or ambiguous network destination");
            return .{
                .destination = .{ .raw = destination_text, .host = "", .host_class = .invalid },
                .decision = .{ .result = .deny, .reason = reason, .ci_may_proceed = false },
                .enforcement_mode = options.enforcement_mode,
                .redacted_target = target,
                .owned_reason = reason,
            };
        }
        return err;
    };

    const mode = policy.network.effectiveMode();
    const enforcement_mode = if (mode == .observe) EnforcementMode.observe_only else options.enforcement_mode;
    var findings = try detectExfiltration(allocator, destination, policy.network.detect_exfiltration);
    errdefer if (findings.len > 0) allocator.free(findings);
    if (options.unknown_tracker) |tracker| {
        if (try tracker.record(destination.host)) {
            const old_len = findings.len;
            findings = try allocator.realloc(findings, old_len + 1);
            findings[old_len] = .{ .signal = .many_unknown_domains, .score = 75 };
        }
    }

    const target = try redactedDestinationAlloc(allocator, destination);
    errdefer allocator.free(target);

    if (findMatch("network.deny", destination, policy.network.deny)) |matched| {
        return buildDecision(allocator, destination, .deny, matched, "explicit network deny", enforcement_mode, findings, target, true, options.ci_mode);
    }
    if (findMatch("network.allow", destination, policy.network.allow)) |matched| {
        const base = if (mode == .off) schema.DecisionValue.deny else schema.DecisionValue.allow;
        return buildDecision(allocator, destination, base, matched, if (mode == .off) "network mode off" else "explicit network allow", enforcement_mode, findings, target, true, options.ci_mode);
    }
    if (findMatch("network.ask", destination, policy.network.ask)) |matched| {
        const base: schema.DecisionValue = if (mode == .off or options.ci_mode or effective_mode == .ci) .deny else .ask;
        return buildDecision(allocator, destination, base, matched, if (base == .deny) "ask converted to deny in ci/off mode" else "explicit network ask", enforcement_mode, findings, target, true, options.ci_mode);
    }

    if (strictDefaultDenyReason(destination)) |reason| {
        const value: schema.DecisionValue = switch (mode) {
            .observe => .observe,
            .open => .allow,
            else => .deny,
        };
        return buildDecision(allocator, destination, value, null, reason, enforcement_mode, findings, target, true, options.ci_mode);
    }

    if (policy.network.default) |default| {
        const value = if ((effective_mode == .ci or options.ci_mode) and default == .ask) schema.DecisionValue.deny else default;
        return buildDecision(allocator, destination, value, null, "network.default", enforcement_mode, findings, target, true, options.ci_mode);
    }

    const fallback: schema.DecisionValue = switch (mode) {
        .off => .deny,
        .ask => if (effective_mode == .ci or options.ci_mode) .deny else .ask,
        .allowlist => .deny,
        .observe => .observe,
        .open => .allow,
    };
    return buildDecision(allocator, destination, fallback, null, "network mode default", enforcement_mode, findings, target, true, options.ci_mode);
}

pub fn detectExfiltration(allocator: std.mem.Allocator, destination: Destination, config: schema.ExfiltrationDetection) ![]ExfilFinding {
    var findings: std.ArrayList(ExfilFinding) = .empty;
    errdefer findings.deinit(allocator);

    if (config.long_query_strings and destination.query.len >= 120) try findings.append(allocator, .{ .signal = .long_query_string, .score = 70 });
    if (config.secret_patterns and urlContainsSecret(destination)) try findings.append(allocator, .{ .signal = .secret_like_url_value, .score = 95 });
    if (destination.host_class == .direct_ip) try findings.append(allocator, .{ .signal = .direct_ip_destination, .score = 70 });
    if (isPasteSite(destination.host)) try findings.append(allocator, .{ .signal = .paste_site_destination, .score = 85 });
    if (isWebhookOrRequestBin(destination.host)) try findings.append(allocator, .{ .signal = .webhook_request_bin_destination, .score = 90 });
    if (isTunnelingService(destination.host)) try findings.append(allocator, .{ .signal = .tunneling_service_destination, .score = 85 });
    if (config.dns and hasHighEntropyDnsLabel(destination.host)) try findings.append(allocator, .{ .signal = .high_entropy_dns_label, .score = 75 });
    if (config.dns and hasLongSubdomain(destination.host)) try findings.append(allocator, .{ .signal = .long_subdomain, .score = 65 });
    if (hasBase64LikeComponent(destination.path) or hasBase64LikeComponent(destination.query)) try findings.append(allocator, .{ .signal = .base64_like_url_component, .score = 70 });

    return try findings.toOwnedSlice(allocator);
}

pub fn redactedDestinationAlloc(allocator: std.mem.Allocator, destination: Destination) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    if (destination.scheme) |scheme| {
        try list.appendSlice(allocator, scheme);
        try list.appendSlice(allocator, "://");
    }
    try list.appendSlice(allocator, destination.host);
    if (destination.port) |port| try list.writer(allocator).print(":{d}", .{port});
    if (destination.path.len > 0) try appendRedactedUrlPart(allocator, &list, destination.path, false);
    if (destination.query.len > 0) {
        try list.append(allocator, '?');
        try appendRedactedUrlPart(allocator, &list, destination.query, true);
    }
    return try list.toOwnedSlice(allocator);
}

pub fn appendProxyEnvironment(env_map: *std.process.EnvMap, proxy_url: []const u8, no_proxy: []const u8) !void {
    try env_map.put("HTTP_PROXY", proxy_url);
    try env_map.put("HTTPS_PROXY", proxy_url);
    try env_map.put("ALL_PROXY", proxy_url);
    try env_map.put("NO_PROXY", no_proxy);
    try env_map.put("AEGIS_NETWORK_ENFORCEMENT", "proxy-mediated");
}

fn buildDecision(
    allocator: std.mem.Allocator,
    destination: Destination,
    value: schema.DecisionValue,
    matched: ?Match,
    reason_label: []const u8,
    enforcement_mode: EnforcementMode,
    findings: []ExfilFinding,
    redacted_target: []u8,
    owns_findings: bool,
    ci_mode: bool,
) !Decision {
    const result = value.toDecisionResult();
    var rule_id: ?[]u8 = null;
    var matched_rule: ?schema.RuleRef = null;
    if (matched) |item| {
        rule_id = try std.fmt.allocPrint(allocator, "{s}[{d}]", .{ item.label, item.index });
        matched_rule = .{ .id = rule_id.?, .pattern = item.pattern };
    }
    errdefer if (rule_id) |owned| allocator.free(owned);

    const reason = try formatReason(allocator, reason_label, destination, enforcement_mode, findings);
    errdefer allocator.free(reason);
    return .{
        .destination = destination,
        .decision = .{
            .result = result,
            .rule_id = rule_id,
            .reason = reason,
            .risk_score = maxRisk(findings),
            .requires_user = result == .ask,
            .ci_may_proceed = if (ci_mode) (result == .allow or result == .observe) else (result != .deny),
        },
        .matched_rule = matched_rule,
        .enforcement_mode = enforcement_mode,
        .exfil_findings = findings,
        .redacted_target = redacted_target,
        .owned_reason = reason,
        .owned_rule_id = rule_id,
        .owned_findings = owns_findings,
    };
}

fn formatReason(allocator: std.mem.Allocator, reason_label: []const u8, destination: Destination, enforcement_mode: EnforcementMode, findings: []ExfilFinding) ![]u8 {
    if (findings.len == 0) {
        return std.fmt.allocPrint(allocator, "{s}; host={s}; enforcement={s}", .{ reason_label, destination.host, enforcement_mode.toString() });
    }
    return std.fmt.allocPrint(allocator, "{s}; host={s}; enforcement={s}; risk={s}", .{ reason_label, destination.host, enforcement_mode.toString(), findings[0].signal.reason() });
}

fn maxRisk(findings: []const ExfilFinding) ?u8 {
    if (findings.len == 0) return null;
    var max: u8 = 0;
    for (findings) |finding| max = @max(max, finding.score);
    return max;
}

fn findMatch(label: []const u8, destination: Destination, rules: []const []const u8) ?Match {
    for (rules, 0..) |pattern, index| {
        if (matchesNetworkRule(pattern, destination)) return .{ .label = label, .index = index, .pattern = pattern };
    }
    return null;
}

pub fn matchesNetworkRule(pattern: []const u8, destination: Destination) bool {
    if (std.mem.indexOfScalar(u8, pattern, ':')) |colon| {
        const maybe_port = std.fmt.parseInt(u16, pattern[colon + 1 ..], 10) catch null;
        if (maybe_port) |rule_port| {
            if (destination.port == null or destination.port.? != rule_port) return false;
            return matchesHostPattern(pattern[0..colon], destination);
        }
    }
    return matchesHostPattern(pattern, destination);
}

fn matchesHostPattern(pattern: []const u8, destination: Destination) bool {
    if (std.ascii.eqlIgnoreCase(pattern, "localhost")) return destination.host_class == .localhost;
    if (std.ascii.eqlIgnoreCase(pattern, "private") or std.ascii.eqlIgnoreCase(pattern, "private:*")) return destination.host_class == .private_network;
    if (std.ascii.eqlIgnoreCase(pattern, "metadata") or std.ascii.eqlIgnoreCase(pattern, "cloud-metadata")) return destination.host_class == .cloud_metadata;
    if (std.ascii.eqlIgnoreCase(pattern, "direct-ip")) return destination.host_class == .direct_ip;
    return matchers.matchesDomain(pattern, destination.host);
}

fn strictDefaultDenyReason(destination: Destination) ?[]const u8 {
    return switch (destination.host_class) {
        .direct_ip => "direct IP destinations deny by default",
        .localhost => "localhost destinations deny by default",
        .private_network => "private network destinations deny by default",
        .cloud_metadata => "cloud metadata endpoints deny by default",
        .invalid => "invalid destination denies by default",
        .domain => null,
    };
}

fn classifyHost(host: []const u8) HostClass {
    if (isLocalhost(host)) return .localhost;
    if (isCloudMetadataHost(host)) return .cloud_metadata;
    if (parseIpv4(host)) |ip| {
        if (isCloudMetadataIp(ip)) return .cloud_metadata;
        if (isLocalhostIp(ip)) return .localhost;
        if (isPrivateIpv4(ip)) return .private_network;
        return .direct_ip;
    }
    if (std.mem.indexOfScalar(u8, host, ':') != null) {
        if (std.ascii.eqlIgnoreCase(host, "::1")) return .localhost;
        if (std.ascii.startsWithIgnoreCase(host, "fe80:")) return .private_network;
        return .direct_ip;
    }
    if (!validDomain(host)) return .invalid;
    return .domain;
}

fn parsePort(value: []const u8) !u16 {
    if (value.len == 0) return error.InvalidNetworkDestination;
    return std.fmt.parseInt(u16, value, 10) catch return error.InvalidNetworkDestination;
}

fn trimTrailingDot(value: []const u8) []const u8 {
    if (value.len > 0 and value[value.len - 1] == '.') return value[0 .. value.len - 1];
    return value;
}

fn validDomain(host: []const u8) bool {
    if (host.len == 0) return false;
    var labels = std.mem.splitScalar(u8, host, '.');
    while (labels.next()) |label| {
        if (label.len == 0 or label.len > 63) return false;
        if (label[0] == '-' or label[label.len - 1] == '-') return false;
        for (label) |char| {
            if (!(std.ascii.isAlphanumeric(char) or char == '-')) return false;
        }
    }
    return true;
}

fn isLocalhost(host: []const u8) bool {
    return std.ascii.eqlIgnoreCase(host, "localhost") or std.ascii.endsWithIgnoreCase(host, ".localhost");
}

fn isCloudMetadataHost(host: []const u8) bool {
    return std.ascii.eqlIgnoreCase(host, "metadata.google.internal") or
        std.ascii.eqlIgnoreCase(host, "metadata") or
        std.ascii.eqlIgnoreCase(host, "169.254.169.254");
}

fn parseIpv4(host: []const u8) ?[4]u8 {
    var out: [4]u8 = undefined;
    var parts = std.mem.splitScalar(u8, host, '.');
    var index: usize = 0;
    while (parts.next()) |part| {
        if (index >= 4 or part.len == 0) return null;
        out[index] = std.fmt.parseInt(u8, part, 10) catch return null;
        index += 1;
    }
    if (index != 4) return null;
    return out;
}

fn isLocalhostIp(ip: [4]u8) bool {
    return ip[0] == 127;
}

fn isCloudMetadataIp(ip: [4]u8) bool {
    return ip[0] == 169 and ip[1] == 254 and ip[2] == 169 and ip[3] == 254;
}

fn isPrivateIpv4(ip: [4]u8) bool {
    return ip[0] == 10 or
        (ip[0] == 172 and ip[1] >= 16 and ip[1] <= 31) or
        (ip[0] == 192 and ip[1] == 168) or
        (ip[0] == 169 and ip[1] == 254);
}

fn isPasteSite(host: []const u8) bool {
    return hostMatchesAny(host, &.{ "pastebin.com", "*.pastebin.com", "gist.github.com", "hastebin.com", "*.hastebin.com" });
}

fn isWebhookOrRequestBin(host: []const u8) bool {
    return hostMatchesAny(host, &.{ "*.requestbin.net", "requestbin.net", "*.webhook.site", "webhook.site", "*.pipipedream.net", "*.pipedream.net" });
}

fn isTunnelingService(host: []const u8) bool {
    return hostMatchesAny(host, &.{ "*.ngrok.io", "*.ngrok-free.app", "*.trycloudflare.com", "*.loca.lt", "*.localtunnel.me", "*.serveo.net" });
}

fn hostMatchesAny(host: []const u8, patterns: []const []const u8) bool {
    for (patterns) |pattern| {
        if (matchers.matchesDomain(pattern, host)) return true;
    }
    return false;
}

fn hasHighEntropyDnsLabel(host: []const u8) bool {
    var labels = std.mem.splitScalar(u8, host, '.');
    while (labels.next()) |label| {
        if (label.len >= 24 and entropyish(label)) return true;
    }
    return false;
}

fn hasLongSubdomain(host: []const u8) bool {
    var labels = std.mem.splitScalar(u8, host, '.');
    var index: usize = 0;
    while (labels.next()) |label| : (index += 1) {
        if (index == 0 and label.len >= 48) return true;
    }
    return false;
}

fn hasBase64LikeComponent(value: []const u8) bool {
    var tokens = std.mem.tokenizeAny(u8, value, "/?&=._-");
    while (tokens.next()) |token| {
        if (token.len >= 32 and base64ish(token)) return true;
    }
    return false;
}

fn entropyish(value: []const u8) bool {
    if (value.len < 24) return false;
    var classes: u8 = 0;
    var unique = [_]bool{false} ** 256;
    var unique_count: usize = 0;
    for (value) |char| {
        if (std.ascii.isUpper(char)) classes |= 1 else if (std.ascii.isLower(char)) classes |= 2 else if (std.ascii.isDigit(char)) classes |= 4 else if (char == '-' or char == '_') classes |= 8 else return false;
        if (!unique[char]) {
            unique[char] = true;
            unique_count += 1;
        }
    }
    return @popCount(classes) >= 2 and unique_count >= 14;
}

fn base64ish(value: []const u8) bool {
    var useful: usize = 0;
    for (value) |char| {
        if (std.ascii.isAlphanumeric(char) or char == '+' or char == '/' or char == '_' or char == '-' or char == '=') {
            useful += 1;
        } else return false;
    }
    return useful >= 32 and entropyish(value[0..@min(value.len, 64)]);
}

fn urlContainsSecret(destination: Destination) bool {
    return audit_redact.classifyString(destination.path) != null or audit_redact.classifyString(destination.query) != null;
}

fn appendRedactedUrlPart(allocator: std.mem.Allocator, list: *std.ArrayList(u8), value: []const u8, query: bool) !void {
    const separators = if (query) "&;" else "/";
    var cursor: usize = 0;
    while (cursor < value.len) {
        const next = std.mem.indexOfAnyPos(u8, value, cursor, separators) orelse value.len;
        const part = value[cursor..next];
        var buf: [256]u8 = undefined;
        const redacted = audit_redact.redactStringBounded(part, &buf);
        try list.appendSlice(allocator, redacted);
        if (next == value.len) break;
        try list.append(allocator, value[next]);
        cursor = next + 1;
    }
}

test "network decision allows exact and wildcard domains" {
    const load = @import("../policy/load.zig");
    var policy = try load.parseFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: strict
        \\network:
        \\  mode: allowlist
        \\  allow:
        \\    - "api.github.com"
        \\    - "*.github.com"
    , "network.yaml");
    defer policy.deinit();

    var exact = try evaluate(std.testing.allocator, &policy, .strict, "https://api.github.com/repos", .{});
    defer exact.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.allow, exact.decision.result);
    try std.testing.expectEqualStrings("network.allow[0]", exact.decision.rule_id.?);

    var wildcard = try evaluate(std.testing.allocator, &policy, .strict, "uploads.github.com", .{});
    defer wildcard.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.allow, wildcard.decision.result);
    try std.testing.expectEqualStrings("network.allow[1]", wildcard.decision.rule_id.?);
}

test "deny beats allow and unknown ask denies in ci" {
    const load = @import("../policy/load.zig");
    var policy = try load.parseFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: ci
        \\network:
        \\  mode: ask
        \\  allow:
        \\    - "*.github.com"
        \\  ask:
        \\    - "*.githubusercontent.com"
        \\  deny:
        \\    - "api.github.com"
    , "network.yaml");
    defer policy.deinit();

    var denied = try evaluate(std.testing.allocator, &policy, .ci, "api.github.com", .{ .ci_mode = true });
    defer denied.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, denied.decision.result);
    try std.testing.expectEqualStrings("network.deny[0]", denied.decision.rule_id.?);

    var ask = try evaluate(std.testing.allocator, &policy, .ci, "raw.githubusercontent.com", .{ .ci_mode = true });
    defer ask.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, ask.decision.result);
}

test "strict defaults deny direct localhost private and metadata destinations" {
    const load = @import("../policy/load.zig");
    var policy = try load.parseFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: strict
        \\network:
        \\  mode: allowlist
    , "network.yaml");
    defer policy.deinit();

    const values = [_][]const u8{ "8.8.8.8", "localhost:3000", "192.168.1.2", "169.254.169.254" };
    for (values) |value| {
        var result = try evaluate(std.testing.allocator, &policy, .strict, value, .{});
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(core.decision.DecisionResult.deny, result.decision.result);
    }
}

test "unknown domain denies in allowlist mode" {
    const load = @import("../policy/load.zig");
    var policy = try load.parseFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: strict
        \\network:
        \\  mode: allowlist
        \\  allow:
        \\    - "api.github.com"
    , "network.yaml");
    defer policy.deinit();

    var result = try evaluate(std.testing.allocator, &policy, .strict, "unknown.example.com", .{});
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, result.decision.result);
}

test "exfiltration heuristics flag required URL and host patterns" {
    const config: schema.ExfiltrationDetection = .{};
    var long_query_buf: [180]u8 = undefined;
    @memset(&long_query_buf, 'a');
    const long_url = try std.fmt.allocPrint(std.testing.allocator, "https://example.com/path?q={s}", .{&long_query_buf});
    defer std.testing.allocator.free(long_url);

    const cases = [_]struct {
        url: []const u8,
        signal: ExfilSignal,
    }{
        .{ .url = long_url, .signal = .long_query_string },
        .{ .url = "https://example.com/dGhpcy1sb29rcy1saWtlLWJhc2U2NC1leGZpbC1wYXlsb2FkMTIzNDU2", .signal = .base64_like_url_component },
        .{ .url = "https://a8F3kLm9PqR2sTu7VwXyZ012345.example.com", .signal = .high_entropy_dns_label },
        .{ .url = "https://pastebin.com/abc", .signal = .paste_site_destination },
        .{ .url = "https://demo.requestbin.net/abc", .signal = .webhook_request_bin_destination },
        .{ .url = "https://demo.ngrok.io/abc", .signal = .tunneling_service_destination },
        .{ .url = "https://example.com/?token=sk-fakeSyntheticOpenAIKey1234567890", .signal = .secret_like_url_value },
    };
    for (cases) |case| {
        const destination = try parseDestination(case.url);
        const findings = try detectExfiltration(std.testing.allocator, destination, config);
        defer std.testing.allocator.free(findings);
        var found = false;
        for (findings) |finding| {
            if (finding.signal == case.signal) found = true;
        }
        try std.testing.expect(found);
    }
}

test "redacted network targets do not include fake secrets" {
    const destination = try parseDestination("https://example.com/path?token=sk-fakeSyntheticOpenAIKey1234567890&ok=1");
    const redacted = try redactedDestinationAlloc(std.testing.allocator, destination);
    defer std.testing.allocator.free(redacted);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "sk-fakeSyntheticOpenAIKey") == null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "[REDACTED:") != null);
}

test "unknown domain tracker owns host keys" {
    var tracker = UnknownDomainTracker.init(std.testing.allocator);
    defer tracker.deinit();

    const transient = try std.testing.allocator.dupe(u8, "first.example.com");
    const transient_ptr = transient.ptr;
    _ = try tracker.record(transient);
    std.testing.allocator.free(transient);

    var it = tracker.hosts.keyIterator();
    const stored = it.next().?.*;
    try std.testing.expectEqualStrings("first.example.com", stored);
    try std.testing.expect(stored.ptr != transient_ptr);
    try std.testing.expect(!try tracker.record("first.example.com"));
}
