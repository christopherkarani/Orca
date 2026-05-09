const std = @import("std");
const data_classification = @import("data_classification.zig");

pub const EndpointKind = enum {
    localhost,
    private_network,
    ground_control_station,
    px4_sitl,
    ardupilot_sitl,
    fake_adapter,
    customer_endpoint,
    cloud_endpoint,
    webhook,
    tunnel_service,
    paste_site,
    direct_ip,
    unknown,

    pub fn toString(self: EndpointKind) []const u8 {
        return @tagName(self);
    }
};

pub const Endpoint = struct {
    host: []const u8 = "",
    port: ?u16 = null,
    protocol: []const u8 = "tcp",
    scheme: []const u8 = "",
    path: []const u8 = "",
    query: []const u8 = "",
    label: []const u8 = "",
    allowlist_match: ?[]const u8 = null,
    policy_rule: ?[]const u8 = null,
    provenance: []const u8 = "unknown",
    environment: []const u8 = "unknown",
};

pub const OwnedEndpoint = struct {
    arena: std.heap.ArenaAllocator,
    value: Endpoint,

    pub fn deinit(self: *OwnedEndpoint) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub const Classification = struct {
    allocator: std.mem.Allocator,
    kind: EndpointKind,
    suspicious: bool,
    safe_by_default: bool,
    redacted_endpoint: []u8,
    reason: []u8,

    pub fn deinit(self: *Classification) void {
        self.allocator.free(self.redacted_endpoint);
        self.allocator.free(self.reason);
        self.* = undefined;
    }
};

pub fn parseEndpointJsonOwned(allocator: std.mem.Allocator, text: []const u8) !OwnedEndpoint {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const aa = arena.allocator();
    const parsed = std.json.parseFromSlice(std.json.Value, aa, text, .{}) catch return error.InvalidEndpoint;
    const object = if (parsed.value == .object) parsed.value.object else return error.InvalidEndpoint;
    return .{
        .arena = arena,
        .value = .{
            .host = try dupeJsonString(aa, object, "host", ""),
            .port = try optionalPort(object),
            .protocol = try dupeJsonString(aa, object, "protocol", "tcp"),
            .scheme = try dupeJsonString(aa, object, "scheme", try dupeJsonString(aa, object, "protocol", "")),
            .path = bounded(try dupeJsonString(aa, object, "path", "")),
            .query = bounded(try dupeJsonString(aa, object, "query", "")),
            .label = try dupeJsonString(aa, object, "label", ""),
            .allowlist_match = null,
            .policy_rule = null,
            .provenance = try dupeJsonString(aa, object, "provenance", "unknown"),
            .environment = try dupeJsonString(aa, object, "environment", "unknown"),
        },
    };
}

pub fn classifyEndpoint(allocator: std.mem.Allocator, endpoint: Endpoint) !Classification {
    const kind = classifyKind(endpoint);
    const suspicious = switch (kind) {
        .webhook, .tunnel_service, .paste_site, .direct_ip, .unknown => true,
        else => false,
    };
    const safe_by_default = switch (kind) {
        .localhost, .ground_control_station, .px4_sitl, .ardupilot_sitl, .fake_adapter => true,
        else => false,
    };
    return .{
        .allocator = allocator,
        .kind = kind,
        .suspicious = suspicious,
        .safe_by_default = safe_by_default,
        .redacted_endpoint = try redactedEndpoint(allocator, endpoint),
        .reason = try allocator.dupe(u8, reasonFor(kind)),
    };
}

pub fn classifyKind(endpoint: Endpoint) EndpointKind {
    const label = endpoint.label;
    const host = endpoint.host;
    const env = endpoint.environment;
    const provenance = endpoint.provenance;

    if (data_classification.containsAny(label, &.{ "ground_control", "ground-control", "gcs" })) return .ground_control_station;
    if (data_classification.containsAny(label, &.{ "px4", "px4_sitl" }) or data_classification.containsAny(env, &.{"px4_sitl"})) return .px4_sitl;
    if (data_classification.containsAny(label, &.{ "ardupilot", "ardupilot_sitl" }) or data_classification.containsAny(env, &.{"ardupilot_sitl"})) return .ardupilot_sitl;
    if (data_classification.containsAny(label, &.{"fake_adapter"}) or data_classification.containsAny(provenance, &.{ "fake_adapter", "fake_px4", "fake_ardupilot" })) return .fake_adapter;
    if (data_classification.containsAny(label, &.{"customer"}) or data_classification.containsAny(host, &.{ ".customer.internal", "customer-eval.local" })) return .customer_endpoint;
    if (isLocalhost(host)) return .localhost;
    if (isPrivateNetwork(host)) return .private_network;
    if (isWebhook(host)) return .webhook;
    if (isTunnel(host)) return .tunnel_service;
    if (isPaste(host)) return .paste_site;
    if (data_classification.containsAny(host, &.{ "amazonaws.com", "googleapis.com", "azure.com", "cloudfront.net", "cloud" })) return .cloud_endpoint;
    if (isIpLiteral(host)) return .direct_ip;
    return .unknown;
}

pub fn redactedEndpoint(allocator: std.mem.Allocator, endpoint: Endpoint) ![]u8 {
    const scheme = if (endpoint.scheme.len > 0) endpoint.scheme else endpoint.protocol;
    const clean_path = if (endpoint.path.len > 0) "/[REDACTED-PATH]" else "";
    if (endpoint.port) |port| {
        if (endpoint.query.len > 0) return std.fmt.allocPrint(allocator, "{s}://{s}:{d}{s}?query=[REDACTED]", .{ scheme, redactedHost(endpoint.host), port, clean_path });
        return std.fmt.allocPrint(allocator, "{s}://{s}:{d}{s}", .{ scheme, redactedHost(endpoint.host), port, clean_path });
    }
    if (endpoint.query.len > 0) return std.fmt.allocPrint(allocator, "{s}://{s}{s}?query=[REDACTED]", .{ scheme, redactedHost(endpoint.host), clean_path });
    return std.fmt.allocPrint(allocator, "{s}://{s}{s}", .{ scheme, redactedHost(endpoint.host), clean_path });
}

pub fn endpointKey(endpoint: Endpoint) []const u8 {
    if (endpoint.label.len > 0) return endpoint.label;
    return endpoint.host;
}

pub fn isLocalhost(host: []const u8) bool {
    return std.ascii.eqlIgnoreCase(host, "localhost") or std.mem.eql(u8, host, "127.0.0.1") or std.mem.eql(u8, host, "::1") or std.mem.eql(u8, host, "0.0.0.0");
}

pub fn isPrivateNetwork(host: []const u8) bool {
    if (std.mem.startsWith(u8, host, "10.")) return true;
    if (std.mem.startsWith(u8, host, "192.168.")) return true;
    if (std.mem.startsWith(u8, host, "172.")) {
        var parts = std.mem.splitScalar(u8, host, '.');
        _ = parts.next();
        if (parts.next()) |second| {
            const value = std.fmt.parseInt(u8, second, 10) catch return false;
            return value >= 16 and value <= 31;
        }
    }
    return false;
}

pub fn isIpLiteral(host: []const u8) bool {
    if (std.net.Ip4Address.parse(host, 0)) |_| return true else |_| {}
    if (std.net.Ip6Address.parse(host, 0)) |_| return true else |_| {}
    return false;
}

pub fn isWebhook(host: []const u8) bool {
    return data_classification.containsAny(host, &.{ "webhook.site", "requestbin.net", "requestb.in", "pipedream.net" });
}

pub fn isTunnel(host: []const u8) bool {
    return data_classification.containsAny(host, &.{ "ngrok.io", "trycloudflare.com", "loca.lt", "localtunnel.me", "tunnel" });
}

pub fn isPaste(host: []const u8) bool {
    return data_classification.containsAny(host, &.{ "pastebin.com", "gist.github.com", "hastebin", "paste.rs" });
}

fn redactedHost(host: []const u8) []const u8 {
    if (looksHighEntropyLabel(host)) return "[REDACTED-HOST]";
    return host;
}

pub fn looksHighEntropyLabel(host: []const u8) bool {
    var labels = std.mem.splitScalar(u8, host, '.');
    while (labels.next()) |label| {
        if (label.len >= 24 and highEntropyish(label)) return true;
    }
    return false;
}

pub fn highEntropyish(value: []const u8) bool {
    if (value.len < 24) return false;
    var unique = [_]bool{false} ** 256;
    var unique_count: usize = 0;
    var classes: u8 = 0;
    for (value) |char| {
        if (std.ascii.isUpper(char)) classes |= 1 else if (std.ascii.isLower(char)) classes |= 2 else if (std.ascii.isDigit(char)) classes |= 4 else if (char == '-' or char == '_' or char == '+') classes |= 8 else return false;
        if (!unique[char]) {
            unique[char] = true;
            unique_count += 1;
        }
    }
    return @popCount(classes) >= 2 and unique_count >= 14;
}

fn reasonFor(kind: EndpointKind) []const u8 {
    return switch (kind) {
        .localhost => "localhost endpoint",
        .private_network => "private network endpoint",
        .ground_control_station => "ground-control endpoint",
        .px4_sitl => "PX4 SITL endpoint",
        .ardupilot_sitl => "ArduPilot SITL endpoint",
        .fake_adapter => "fake adapter endpoint",
        .customer_endpoint => "customer evaluation endpoint",
        .cloud_endpoint => "cloud endpoint requires explicit policy",
        .webhook => "webhook/request-bin endpoint is suspicious by default",
        .tunnel_service => "tunnel endpoint is suspicious by default",
        .paste_site => "paste endpoint is suspicious by default",
        .direct_ip => "direct public IP is not safe by default",
        .unknown => "unknown endpoint is not safe by default",
    };
}

fn dupeJsonString(allocator: std.mem.Allocator, object: std.json.ObjectMap, key: []const u8, default: []const u8) ![]const u8 {
    const value = object.get(key) orelse return allocator.dupe(u8, default);
    if (value != .string) return error.InvalidEndpoint;
    return allocator.dupe(u8, value.string);
}

fn optionalPort(object: std.json.ObjectMap) !?u16 {
    const value = object.get("port") orelse return null;
    return switch (value) {
        .integer => |port| if (port >= 0 and port <= 65535) @intCast(port) else error.InvalidEndpoint,
        .string => |text| std.fmt.parseInt(u16, text, 10) catch error.InvalidEndpoint,
        else => error.InvalidEndpoint,
    };
}

fn bounded(value: []const u8) []const u8 {
    return if (value.len > 4096) value[0..4096] else value;
}

test "classifies local SITL and suspicious endpoints" {
    var ground = try classifyEndpoint(std.testing.allocator, .{ .host = "127.0.0.1", .port = 14550, .label = "ground_control" });
    defer ground.deinit();
    try std.testing.expectEqual(EndpointKind.ground_control_station, ground.kind);
    try std.testing.expect(ground.safe_by_default);

    var webhook = try classifyEndpoint(std.testing.allocator, .{ .host = "abc.webhook.site", .scheme = "https", .query = "token=fake_secret_value" });
    defer webhook.deinit();
    try std.testing.expectEqual(EndpointKind.webhook, webhook.kind);
    try std.testing.expect(webhook.suspicious);
    try std.testing.expect(std.mem.indexOf(u8, webhook.redacted_endpoint, "fake_secret_value") == null);
}
