const std = @import("std");

const network = @import("network.zig");
const core = @import("aegis_core").core;
const schema = @import("aegis_core").policy.schema;

pub const AuditEvent = struct {
    event_type: core.event.EventType,
    target: []u8,
    result: ?core.decision.DecisionResult = null,
    reason: ?[]u8 = null,
    ci_may_proceed: bool = false,

    pub fn deinit(self: AuditEvent, allocator: std.mem.Allocator) void {
        allocator.free(self.target);
        if (self.reason) |reason| allocator.free(reason);
    }
};

pub const Runtime = struct {
    state: *State,

    pub fn bindUrl(self: Runtime) []const u8 {
        return self.state.bind_url;
    }

    pub fn isHealthy(self: Runtime) bool {
        return !self.state.stop.load(.acquire) and !self.state.failed.load(.acquire);
    }

    pub fn failed(self: Runtime) bool {
        return self.state.failed.load(.acquire);
    }

    pub fn waitForIdle(self: Runtime, timeout_ns: u64) !void {
        const started = std.time.nanoTimestamp();
        while (self.state.active_connections.load(.acquire) > 0) {
            if (std.time.nanoTimestamp() - started > timeout_ns) return error.ProxyConnectionsActive;
            std.Thread.sleep(10 * std.time.ns_per_ms);
        }
    }

    pub fn snapshotAuditEvents(self: Runtime, allocator: std.mem.Allocator) ![]AuditEvent {
        self.state.audit_mutex.lock();
        defer self.state.audit_mutex.unlock();
        const out = try allocator.alloc(AuditEvent, self.state.audit_events.items.len);
        var copied: usize = 0;
        errdefer {
            for (out[0..copied]) |ev| ev.deinit(allocator);
            allocator.free(out);
        }
        for (self.state.audit_events.items, 0..) |ev, index| {
            const target = try allocator.dupe(u8, ev.target);
            errdefer allocator.free(target);
            const reason = if (ev.reason) |value| try allocator.dupe(u8, value) else null;
            errdefer if (reason) |value| allocator.free(value);
            out[index] = .{
                .event_type = ev.event_type,
                .target = target,
                .result = ev.result,
                .reason = reason,
                .ci_may_proceed = ev.ci_may_proceed,
            };
            copied += 1;
        }
        return out;
    }

    pub fn freeAuditEvents(_: Runtime, allocator: std.mem.Allocator, events: []AuditEvent) void {
        for (events) |ev| ev.deinit(allocator);
        allocator.free(events);
    }

    pub fn deinit(self: *Runtime) void {
        self.state.stop.store(true, .release);
        wake(self.state.bind_port);
        self.state.thread.join();
        self.waitForIdle(2 * std.time.ns_per_s) catch {};
        self.state.server.deinit();
        for (self.state.audit_events.items) |ev| ev.deinit(self.state.allocator);
        self.state.audit_events.deinit(self.state.allocator);
        self.state.allocator.free(self.state.bind_url);
        self.state.allocator.destroy(self.state);
        self.* = undefined;
    }
};

const State = struct {
    allocator: std.mem.Allocator,
    server: std.net.Server,
    bind_port: u16,
    bind_url: []u8,
    selected_policy: *const schema.Policy,
    effective_mode: schema.Mode,
    stop: std.atomic.Value(bool) = .init(false),
    failed: std.atomic.Value(bool) = .init(false),
    active_connections: std.atomic.Value(usize) = .init(0),
    audit_mutex: std.Thread.Mutex = .{},
    audit_events: std.ArrayList(AuditEvent) = .empty,
    thread: std.Thread = undefined,

    fn record(self: *State, event_type: core.event.EventType, target: []const u8, maybe_decision: ?core.decision.Decision) !void {
        const owned_target = try self.allocator.dupe(u8, target);
        errdefer self.allocator.free(owned_target);
        const owned_reason = if (maybe_decision) |decision| try self.allocator.dupe(u8, decision.reason) else null;
        errdefer if (owned_reason) |reason| self.allocator.free(reason);
        self.audit_mutex.lock();
        defer self.audit_mutex.unlock();
        try self.audit_events.append(self.allocator, .{
            .event_type = event_type,
            .target = owned_target,
            .result = if (maybe_decision) |decision| decision.result else null,
            .reason = owned_reason,
            .ci_may_proceed = if (maybe_decision) |decision| decision.ci_may_proceed else true,
        });
    }
};

const ParsedRequest = struct {
    method: []const u8,
    target: []const u8,
    version: []const u8,
    host: []const u8,
    port: ?u16,
    path: []const u8,
    destination: []const u8,
    https_connect: bool,
    headers_end: usize,
};

pub fn start(
    allocator: std.mem.Allocator,
    selected_policy: *const schema.Policy,
    effective_mode: schema.Mode,
) !Runtime {
    const address = try std.net.Address.parseIp("127.0.0.1", 0);
    var server = try address.listen(.{ .reuse_address = true });
    errdefer server.deinit();
    const port = server.listen_address.in.getPort();
    const bind_url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{port});
    errdefer allocator.free(bind_url);

    const state = try allocator.create(State);
    errdefer allocator.destroy(state);
    state.* = .{
        .allocator = allocator,
        .server = server,
        .bind_port = port,
        .bind_url = bind_url,
        .selected_policy = selected_policy,
        .effective_mode = effective_mode,
    };
    state.thread = try std.Thread.spawn(.{}, serverLoop, .{state});
    return .{ .state = state };
}

fn serverLoop(state: *State) void {
    while (!state.stop.load(.acquire)) {
        var connection = state.server.accept() catch {
            if (!state.stop.load(.acquire)) state.failed.store(true, .release);
            break;
        };
        if (state.stop.load(.acquire)) {
            connection.stream.close();
            break;
        }
        const context = state.allocator.create(ConnectionContext) catch {
            connection.stream.close();
            continue;
        };
        context.* = .{ .state = state, .client = connection.stream };
        _ = state.active_connections.fetchAdd(1, .acq_rel);
        const thread = std.Thread.spawn(.{}, connectionLoop, .{context}) catch {
            _ = state.active_connections.fetchSub(1, .acq_rel);
            connection.stream.close();
            state.allocator.destroy(context);
            continue;
        };
        thread.detach();
    }
}

const ConnectionContext = struct {
    state: *State,
    client: std.net.Stream,
};

fn connectionLoop(context: *ConnectionContext) void {
    defer {
        _ = context.state.active_connections.fetchSub(1, .acq_rel);
        context.state.allocator.destroy(context);
    }
    handleConnection(context.state, context.client) catch {};
}

fn handleConnection(state: *State, client: std.net.Stream) !void {
    defer client.close();
    var buffer: [64 * 1024]u8 = undefined;
    const read_len = try readHeaders(client, &buffer);
    if (read_len == 0) return;
    const request = try parseRequest(buffer[0..read_len]);
    var decision = try network.evaluate(state.allocator, state.selected_policy, state.effective_mode, request.destination, .{
        .enforcement_mode = .proxy_mediated,
        .ci_mode = state.effective_mode == .ci,
        .method = if (request.https_connect) null else request.method,
    });
    defer decision.deinit(state.allocator);
    state.record(.network_connect_attempt, decision.redacted_target, null) catch {};

    if (!(decision.decision.result == .allow or decision.decision.result == .observe)) {
        state.record(.network_connect_denied, decision.redacted_target, decision.decision) catch {};
        try writeProxyError(client, 403, "Forbidden");
        return;
    }
    state.record(.network_connect_allowed, decision.redacted_target, decision.decision) catch {};

    if (request.https_connect) {
        try tunnelConnect(state.allocator, client, request.host, request.port orelse 443);
        return;
    }
    try forwardHttp(state.allocator, client, request, buffer[0..read_len]);
}

fn readHeaders(stream: std.net.Stream, buffer: []u8) !usize {
    var total: usize = 0;
    while (total < buffer.len) {
        const n = try stream.read(buffer[total..]);
        if (n == 0) return total;
        total += n;
        if (std.mem.indexOf(u8, buffer[0..total], "\r\n\r\n") != null) return total;
    }
    return error.RequestTooLarge;
}

pub fn parseRequest(bytes: []const u8) !ParsedRequest {
    const headers_end = (std.mem.indexOf(u8, bytes, "\r\n\r\n") orelse return error.InvalidProxyRequest) + 4;
    const line_end = std.mem.indexOf(u8, bytes, "\r\n") orelse return error.InvalidProxyRequest;
    const line = bytes[0..line_end];
    var parts = std.mem.splitScalar(u8, line, ' ');
    const method = parts.next() orelse return error.InvalidProxyRequest;
    const target = parts.next() orelse return error.InvalidProxyRequest;
    const version = parts.next() orelse return error.InvalidProxyRequest;
    if (std.ascii.eqlIgnoreCase(method, "CONNECT")) {
        const parsed = try parseAuthority(target, 443);
        return .{
            .method = method,
            .target = target,
            .version = version,
            .host = parsed.host,
            .port = parsed.port,
            .path = "",
            .destination = target,
            .https_connect = true,
            .headers_end = headers_end,
        };
    }

    const host_header = headerValue(bytes[0 .. headers_end - 4], "host") orelse return error.InvalidProxyRequest;
    const parsed_host = try parseAuthority(host_header, 80);
    const destination = target;
    var path = target;
    if (std.mem.indexOf(u8, target, "://")) |_| {
        const parsed_destination = try network.parseDestination(target);
        path = if (parsed_destination.path.len == 0) "/" else parsed_destination.path;
    } else {
        path = if (target.len == 0) "/" else target;
    }
    return .{
        .method = method,
        .target = target,
        .version = version,
        .host = parsed_host.host,
        .port = parsed_host.port,
        .path = path,
        .destination = destination,
        .https_connect = false,
        .headers_end = headers_end,
    };
}

fn forwardHttp(allocator: std.mem.Allocator, client: std.net.Stream, request: ParsedRequest, first_read: []const u8) !void {
    var upstream = try std.net.tcpConnectToHost(allocator, request.host, request.port orelse 80);
    defer upstream.close();
    if (std.mem.indexOf(u8, request.target, "://")) |_| {
        const rewritten = try rewriteAbsoluteRequest(allocator, request, first_read);
        defer allocator.free(rewritten);
        try upstream.writeAll(rewritten);
    } else {
        try upstream.writeAll(first_read);
    }
    try tunnel(client, upstream);
}

fn tunnelConnect(allocator: std.mem.Allocator, client: std.net.Stream, host: []const u8, port: u16) !void {
    var upstream = try std.net.tcpConnectToHost(allocator, host, port);
    defer upstream.close();
    try client.writeAll("HTTP/1.1 200 Connection Established\r\nProxy-Agent: Orca\r\n\r\n");
    try tunnel(client, upstream);
}

fn tunnel(a: std.net.Stream, b: std.net.Stream) !void {
    var fds = [_]std.posix.pollfd{
        .{ .fd = a.handle, .events = std.posix.POLL.IN, .revents = 0 },
        .{ .fd = b.handle, .events = std.posix.POLL.IN, .revents = 0 },
    };
    var buf: [16 * 1024]u8 = undefined;
    while (true) {
        const ready = try std.posix.poll(&fds, 30_000);
        if (ready == 0) return;
        if ((fds[0].revents & std.posix.POLL.IN) != 0) {
            const n = try a.read(&buf);
            if (n == 0) return;
            try b.writeAll(buf[0..n]);
        }
        if ((fds[1].revents & std.posix.POLL.IN) != 0) {
            const n = try b.read(&buf);
            if (n == 0) return;
            try a.writeAll(buf[0..n]);
        }
        if ((fds[0].revents & (std.posix.POLL.HUP | std.posix.POLL.ERR)) != 0) return;
        if ((fds[1].revents & (std.posix.POLL.HUP | std.posix.POLL.ERR)) != 0) return;
        fds[0].revents = 0;
        fds[1].revents = 0;
    }
}

fn rewriteAbsoluteRequest(allocator: std.mem.Allocator, request: ParsedRequest, first_read: []const u8) ![]u8 {
    const line_end = std.mem.indexOf(u8, first_read, "\r\n") orelse return error.InvalidProxyRequest;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.writer(allocator).print("{s} {s} {s}\r\n", .{ request.method, request.path, request.version });
    try out.appendSlice(allocator, first_read[line_end + 2 ..]);
    return out.toOwnedSlice(allocator);
}

fn writeProxyError(stream: std.net.Stream, code: u16, label: []const u8) !void {
    var body_buf: [128]u8 = undefined;
    const body = try std.fmt.bufPrint(&body_buf, "{s}\n", .{label});
    var header_buf: [256]u8 = undefined;
    const header = try std.fmt.bufPrint(&header_buf, "HTTP/1.1 {d} {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{ code, label, body.len });
    try stream.writeAll(header);
    try stream.writeAll(body);
}

fn headerValue(headers: []const u8, wanted: []const u8) ?[]const u8 {
    var lines = std.mem.splitSequence(u8, headers, "\r\n");
    _ = lines.next();
    while (lines.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const name = std.mem.trim(u8, line[0..colon], " \t");
        if (!std.ascii.eqlIgnoreCase(name, wanted)) continue;
        return std.mem.trim(u8, line[colon + 1 ..], " \t");
    }
    return null;
}

const Authority = struct {
    host: []const u8,
    port: ?u16,
};

fn parseAuthority(raw: []const u8, default_port: u16) !Authority {
    var value = std.mem.trim(u8, raw, " \t\r\n");
    if (value.len == 0) return error.InvalidProxyRequest;
    if (std.mem.indexOfScalar(u8, value, '@')) |at| value = value[at + 1 ..];
    if (value[0] == '[') {
        const close = std.mem.indexOfScalar(u8, value, ']') orelse return error.InvalidProxyRequest;
        const host = value[1..close];
        if (value.len > close + 1) {
            if (value[close + 1] != ':') return error.InvalidProxyRequest;
            return .{ .host = host, .port = try parsePort(value[close + 2 ..]) };
        }
        return .{ .host = host, .port = default_port };
    }
    if (std.mem.lastIndexOfScalar(u8, value, ':')) |colon| {
        if (std.mem.indexOfScalar(u8, value[0..colon], ':') == null) {
            return .{ .host = value[0..colon], .port = try parsePort(value[colon + 1 ..]) };
        }
    }
    return .{ .host = value, .port = default_port };
}

fn parsePort(value: []const u8) !u16 {
    if (value.len == 0) return error.InvalidProxyRequest;
    return std.fmt.parseInt(u16, value, 10) catch return error.InvalidProxyRequest;
}

fn wake(port: u16) void {
    var stream = std.net.tcpConnectToHost(std.heap.page_allocator, "127.0.0.1", port) catch return;
    stream.close();
}

test "proxy parses HTTP requests with method and path visibility" {
    const request =
        "POST http://api.github.com/repos/acme/app/issues HTTP/1.1\r\nHost: api.github.com\r\n\r\n";
    const parsed = try parseRequest(request);
    try std.testing.expect(!parsed.https_connect);
    try std.testing.expectEqualStrings("POST", parsed.method);
    try std.testing.expectEqualStrings("api.github.com", parsed.host);
    try std.testing.expectEqual(@as(?u16, 80), parsed.port);
    try std.testing.expectEqualStrings("/repos/acme/app/issues", parsed.path);
    try std.testing.expectEqualStrings("http://api.github.com/repos/acme/app/issues", parsed.destination);
}

test "proxy parses HTTPS CONNECT as host-port only" {
    const request = "CONNECT api.github.com:443 HTTP/1.1\r\nHost: api.github.com:443\r\n\r\n";
    const parsed = try parseRequest(request);
    try std.testing.expect(parsed.https_connect);
    try std.testing.expectEqualStrings("CONNECT", parsed.method);
    try std.testing.expectEqualStrings("api.github.com", parsed.host);
    try std.testing.expectEqual(@as(?u16, 443), parsed.port);
    try std.testing.expectEqualStrings("", parsed.path);
    try std.testing.expectEqualStrings("api.github.com:443", parsed.destination);
}

test "proxy forwards delayed HTTP request bodies and records request audit events" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;

    var loaded = try @import("aegis_core").policy.load.parseFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: observe
        \\network:
        \\  mode: open
        \\  backend: proxy
    , "proxy-test.yaml");
    defer loaded.deinit();

    const upstream_address = try std.net.Address.parseIp("127.0.0.1", 0);
    var upstream = try upstream_address.listen(.{ .reuse_address = true });
    defer upstream.deinit();
    const upstream_port = upstream.listen_address.in.getPort();
    var upstream_state: TestHttpServerState = .{ .server = &upstream, .expected_body = "delayed-body" };
    const upstream_thread = try std.Thread.spawn(.{}, testHttpServer, .{&upstream_state});
    defer upstream_thread.join();

    var runtime = try start(std.testing.allocator, &loaded, .observe);
    defer runtime.deinit();
    const proxy_port = try bindPort(runtime.bindUrl());

    var client = try std.net.tcpConnectToHost(std.testing.allocator, "127.0.0.1", proxy_port);
    defer client.close();
    var request_buf: [256]u8 = undefined;
    const head = try std.fmt.bufPrint(
        &request_buf,
        "POST http://127.0.0.1:{d}/echo HTTP/1.1\r\nHost: 127.0.0.1:{d}\r\nContent-Length: 12\r\nConnection: close\r\n\r\n",
        .{ upstream_port, upstream_port },
    );
    try client.writeAll(head);
    std.Thread.sleep(40 * std.time.ns_per_ms);
    try client.writeAll("delayed-body");

    var response_buf: [512]u8 = undefined;
    const response_len = try client.read(&response_buf);
    try std.testing.expect(std.mem.indexOf(u8, response_buf[0..response_len], "200 OK") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_buf[0..response_len], "proxied") != null);

    try runtime.waitForIdle(1 * std.time.ns_per_s);
    const events = try runtime.snapshotAuditEvents(std.testing.allocator);
    defer runtime.freeAuditEvents(std.testing.allocator, events);
    try std.testing.expect(events.len >= 2);
    try std.testing.expectEqual(@import("aegis_core").core.event.EventType.network_connect_attempt, events[0].event_type);
    try std.testing.expectEqual(@import("aegis_core").core.event.EventType.network_connect_allowed, events[1].event_type);
    try std.testing.expect(std.mem.indexOf(u8, events[0].target, "127.0.0.1") != null);
}

const TestHttpServerState = struct {
    server: *std.net.Server,
    expected_body: []const u8,
};

fn testHttpServer(state: *TestHttpServerState) void {
    var connection = state.server.accept() catch return;
    defer connection.stream.close();
    var buffer: [1024]u8 = undefined;
    var total: usize = 0;
    const deadline = std.time.nanoTimestamp() + 750 * std.time.ns_per_ms;
    while (total < buffer.len and std.time.nanoTimestamp() < deadline) {
        var fds = [_]std.posix.pollfd{.{ .fd = connection.stream.handle, .events = std.posix.POLL.IN, .revents = 0 }};
        const ready = std.posix.poll(&fds, 50) catch return;
        if (ready == 0) continue;
        const n = connection.stream.read(buffer[total..]) catch return;
        if (n == 0) break;
        total += n;
        if (std.mem.indexOf(u8, buffer[0..total], state.expected_body) != null) break;
    }
    const ok = std.mem.indexOf(u8, buffer[0..total], state.expected_body) != null;
    const body = if (ok) "proxied" else "missing-body";
    var response: [128]u8 = undefined;
    const text = std.fmt.bufPrint(&response, "HTTP/1.1 {d} {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{
        if (ok) @as(u16, 200) else @as(u16, 408),
        if (ok) "OK" else "Request Timeout",
        body.len,
        body,
    }) catch return;
    connection.stream.writeAll(text) catch {};
}

fn bindPort(bind_url: []const u8) !u16 {
    const colon = std.mem.lastIndexOfScalar(u8, bind_url, ':') orelse return error.InvalidBindUrl;
    return std.fmt.parseInt(u16, bind_url[colon + 1 ..], 10);
}
