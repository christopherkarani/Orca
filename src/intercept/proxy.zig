const std = @import("std");

const network = @import("orca_core").policy.network_eval;
const core = @import("orca_core").core;
const schema = @import("orca_core").policy.schema;

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

    pub fn bindPort(self: Runtime) u16 {
        return self.state.bind_port;
    }

    /// True when the accept-loop thread has been started (M-5).
    pub fn isServing(self: Runtime) bool {
        return self.state.serving.load(.acquire);
    }

    pub fn isHealthy(self: Runtime) bool {
        if (!self.state.serving.load(.acquire)) return true;
        return !self.state.stop.load(.acquire) and !self.state.failed.load(.acquire);
    }

    pub fn failed(self: Runtime) bool {
        return self.state.failed.load(.acquire);
    }

    /// Start the accept-loop thread. Safe to call once after `listen`.
    /// Call after sandboxed agent fork so Seatbelt `sandbox_init` is not
    /// raced with a multi-threaded parent (M-5).
    pub fn startServing(self: *Runtime) !void {
        if (self.state.serving.swap(true, .acq_rel)) return;
        self.state.thread = try std.Thread.spawn(.{}, serverLoop, .{self.state});
        self.state.thread_started = true;
    }

    pub fn waitForIdle(self: Runtime, timeout_ns: u64) !void {
        var threaded: std.Io.Threaded = .init_single_threaded;
        const io = threaded.io();
        const started = std.Io.Clock.Timestamp.now(io, .awake);
        while (self.state.active_connections.load(.acquire) > 0) {
            const elapsed = started.durationFromNow(io).raw.nanoseconds;
            if (elapsed > timeout_ns) return error.ProxyConnectionsActive;
            const duration = std.Io.Duration.fromNanoseconds(10 * std.time.ns_per_ms);
            std.Io.sleep(io, duration, .awake) catch {};
        }
    }

    pub fn snapshotAuditEvents(self: Runtime, allocator: std.mem.Allocator) ![]AuditEvent {
        const io = self.state.threaded.io();
        try self.state.audit_mutex.lock(io);
        defer self.state.audit_mutex.unlock(io);
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
        wake(self.state.threaded.io(), self.state.bind_port);
        if (self.state.thread_started) {
            self.state.thread.join();
        }
        self.waitForIdle(2 * std.time.ns_per_s) catch {};
        self.state.server.deinit(self.state.threaded.io());
        for (self.state.audit_events.items) |ev| ev.deinit(self.state.allocator);
        self.state.audit_events.deinit(self.state.allocator);
        self.state.allocator.free(self.state.bind_url);
        self.state.allocator.destroy(self.state);
        self.* = undefined;
    }
};

const State = struct {
    allocator: std.mem.Allocator,
    server: std.Io.net.Server,
    bind_port: u16,
    bind_url: []u8,
    selected_policy: *const schema.Policy,
    effective_mode: schema.Mode,
    stop: std.atomic.Value(bool) = .init(false),
    failed: std.atomic.Value(bool) = .init(false),
    serving: std.atomic.Value(bool) = .init(false),
    active_connections: std.atomic.Value(usize) = .init(0),
    audit_mutex: std.Io.Mutex = .init,
    audit_events: std.ArrayList(AuditEvent) = .empty,
    threaded: std.Io.Threaded = undefined,
    thread: std.Thread = undefined,
    thread_started: bool = false,

    fn record(self: *State, event_type: core.event.EventType, target: []const u8, maybe_decision: ?core.decision.Decision) !void {
        const owned_target = try self.allocator.dupe(u8, target);
        errdefer self.allocator.free(owned_target);
        const owned_reason = if (maybe_decision) |decision| try self.allocator.dupe(u8, decision.reason) else null;
        errdefer if (owned_reason) |reason| self.allocator.free(reason);
        const io = self.threaded.io();
        try self.audit_mutex.lock(io);
        defer self.audit_mutex.unlock(io);
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

/// Bind the proxy listener without starting the accept-loop thread (M-5).
/// Returns a Runtime that can inject bind URL into the agent env while the
/// parent stays single-threaded for sandboxed fork. Call `startServing` after
/// the agent child has been forked (or use `start` for the legacy all-in-one path).
pub fn listen(
    allocator: std.mem.Allocator,
    selected_policy: *const schema.Policy,
    effective_mode: schema.Mode,
) !Runtime {
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    const address = try std.Io.net.IpAddress.parse("127.0.0.1", 0);
    var server = try address.listen(io, .{ .reuse_address = true });
    errdefer server.deinit(io);
    const port = server.socket.address.getPort();
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
        .threaded = threaded,
    };
    return .{ .state = state };
}

/// Bind and immediately start the accept-loop thread (legacy / tests).
pub fn start(
    allocator: std.mem.Allocator,
    selected_policy: *const schema.Policy,
    effective_mode: schema.Mode,
) !Runtime {
    var runtime = try listen(allocator, selected_policy, effective_mode);
    errdefer runtime.deinit();
    try runtime.startServing();
    return runtime;
}

fn serverLoop(state: *State) void {
    const io = state.threaded.io();
    while (!state.stop.load(.acquire)) {
        var stream = state.server.accept(io) catch {
            if (!state.stop.load(.acquire)) state.failed.store(true, .release);
            break;
        };
        if (state.stop.load(.acquire)) {
            stream.close(io);
            break;
        }
        const context = state.allocator.create(ConnectionContext) catch {
            stream.close(io);
            continue;
        };
        context.* = .{ .state = state, .client = stream };
        _ = state.active_connections.fetchAdd(1, .acq_rel);
        const thread = std.Thread.spawn(.{}, connectionLoop, .{context}) catch {
            _ = state.active_connections.fetchSub(1, .acq_rel);
            stream.close(io);
            state.allocator.destroy(context);
            continue;
        };
        thread.detach();
    }
}

const ConnectionContext = struct {
    state: *State,
    client: std.Io.net.Stream,
};

fn connectionLoop(context: *ConnectionContext) void {
    const io = context.state.threaded.io();
    defer {
        _ = context.state.active_connections.fetchSub(1, .acq_rel);
        context.state.allocator.destroy(context);
    }
    handleConnection(context.state, io, context.client) catch {};
}

fn handleConnection(state: *State, io: std.Io, client: std.Io.net.Stream) !void {
    defer client.close(io);
    var buffer: [64 * 1024]u8 = undefined;
    const read_len = try readHeaders(io, client, &buffer);
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
        try writeProxyError(io, client, 403, "Forbidden");
        return;
    }
    state.record(.network_connect_allowed, decision.redacted_target, decision.decision) catch {};

    if (request.https_connect) {
        try tunnelConnect(state.allocator, io, client, request.host, request.port orelse 443);
        return;
    }
    try forwardHttp(state.allocator, io, client, request, buffer[0..read_len]);
}

fn readHeaders(io: std.Io, stream: std.Io.net.Stream, buffer: []u8) !usize {
    var total: usize = 0;
    const started = std.Io.Clock.Timestamp.now(io, .awake);
    const deadline_ns: i96 = 5 * std.time.ns_per_s;
    while (total < buffer.len and started.durationFromNow(io).raw.nanoseconds < deadline_ns) {
        var fds = [_]std.posix.pollfd{.{
            .fd = stream.socket.handle,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};
        const ready = std.posix.poll(&fds, 100) catch break;
        if (ready == 0) continue;
        const n = std.posix.read(stream.socket.handle, buffer[total..]) catch |err| switch (err) {
            error.WouldBlock => continue,
            else => return err,
        };
        if (n == 0) return if (total == 0) error.InvalidProxyRequest else total;
        total += n;
        if (std.mem.indexOf(u8, buffer[0..total], "\r\n\r\n") != null) return total;
    }
    return if (total == 0) error.InvalidProxyRequest else error.RequestTooLarge;
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

fn forwardHttp(allocator: std.mem.Allocator, io: std.Io, client: std.Io.net.Stream, request: ParsedRequest, first_read: []const u8) !void {
    const address = std.Io.net.IpAddress.parse(request.host, request.port orelse 80) catch
        try std.Io.net.IpAddress.resolve(io, request.host, request.port orelse 80);
    var upstream = try address.connect(io, .{ .mode = .stream });
    defer upstream.close(io);
    var upstream_buf: [64 * 1024]u8 = undefined;
    var upstream_writer = upstream.writer(io, &upstream_buf);
    if (std.mem.indexOf(u8, request.target, "://")) |_| {
        const rewritten = try rewriteAbsoluteRequest(allocator, request, first_read);
        defer allocator.free(rewritten);
        try upstream_writer.interface.writeAll(rewritten);
    } else {
        try upstream_writer.interface.writeAll(first_read);
    }
    try upstream_writer.interface.flush();
    try tunnel(io, client, upstream);
}

fn tunnelConnect(allocator: std.mem.Allocator, io: std.Io, client: std.Io.net.Stream, host: []const u8, port: u16) !void {
    _ = allocator;
    const address = try std.Io.net.IpAddress.resolve(io, host, port);
    var upstream = try address.connect(io, .{ .mode = .stream });
    defer upstream.close(io);
    var client_buf: [256]u8 = undefined;
    var client_writer = client.writer(io, &client_buf);
    try client_writer.interface.writeAll("HTTP/1.1 200 Connection Established\r\nProxy-Agent: Orca\r\n\r\n");
    try client_writer.interface.flush();
    try tunnel(io, client, upstream);
}

fn tunnel(io: std.Io, a: std.Io.net.Stream, b: std.Io.net.Stream) !void {
    var fds = [_]std.posix.pollfd{
        .{ .fd = a.socket.handle, .events = std.posix.POLL.IN, .revents = 0 },
        .{ .fd = b.socket.handle, .events = std.posix.POLL.IN, .revents = 0 },
    };
    var buf: [16 * 1024]u8 = undefined;
    var b_buf: [16 * 1024]u8 = undefined;
    var a_buf: [16 * 1024]u8 = undefined;
    var b_writer = b.writer(io, &b_buf);
    var a_writer = a.writer(io, &a_buf);
    var idle_ms: usize = 0;
    while (true) {
        const ready = try std.posix.poll(&fds, 200);
        if (ready == 0) {
            idle_ms += 200;
            if (idle_ms >= 3000) return;
            continue;
        }
        idle_ms = 0;
        if ((fds[0].revents & std.posix.POLL.IN) != 0) {
            const n = std.posix.read(a.socket.handle, &buf) catch |err| switch (err) {
                error.WouldBlock => continue,
                else => return err,
            };
            if (n == 0) return;
            try b_writer.interface.writeAll(buf[0..n]);
            try b_writer.interface.flush();
        }
        if ((fds[1].revents & std.posix.POLL.IN) != 0) {
            const n = std.posix.read(b.socket.handle, &buf) catch |err| switch (err) {
                error.WouldBlock => continue,
                else => return err,
            };
            if (n == 0) return;
            try a_writer.interface.writeAll(buf[0..n]);
            try a_writer.interface.flush();
        }
        if ((fds[0].revents & (std.posix.POLL.HUP | std.posix.POLL.ERR)) != 0) return;
        if ((fds[1].revents & (std.posix.POLL.HUP | std.posix.POLL.ERR)) != 0) return;
        fds[0].revents = 0;
        fds[1].revents = 0;
    }
}

fn rewriteAbsoluteRequest(allocator: std.mem.Allocator, request: ParsedRequest, first_read: []const u8) ![]u8 {
    const line_end = std.mem.indexOf(u8, first_read, "\r\n") orelse return error.InvalidProxyRequest;
    var out_aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer out_aw.deinit();
    try out_aw.writer.print("{s} {s} {s}\r\n", .{ request.method, request.path, request.version });
    try out_aw.writer.writeAll(first_read[line_end + 2 ..]);
    try out_aw.writer.flush();
    return try out_aw.toOwnedSlice();
}

fn writeProxyError(io: std.Io, stream: std.Io.net.Stream, code: u16, label: []const u8) !void {
    var body_buf: [128]u8 = undefined;
    const body = try std.fmt.bufPrint(&body_buf, "{s}\n", .{label});
    var header_buf: [256]u8 = undefined;
    const header = try std.fmt.bufPrint(&header_buf, "HTTP/1.1 {d} {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{ code, label, body.len });
    var stream_buf: [512]u8 = undefined;
    var stream_writer = stream.writer(io, &stream_buf);
    try stream_writer.interface.writeAll(header);
    try stream_writer.interface.writeAll(body);
    try stream_writer.interface.flush();
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

fn wake(io: std.Io, port: u16) void {
    const address = std.Io.net.IpAddress.parse("127.0.0.1", port) catch return;
    var stream = address.connect(io, .{ .mode = .stream }) catch return;
    stream.close(io);
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

    var loaded = try @import("orca_core").policy.load.parseFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: observe
        \\network:
        \\  mode: open
        \\  backend: proxy
    , "proxy-test.yaml");
    defer loaded.deinit();

    const io = std.testing.io;
    const upstream_address = try std.Io.net.IpAddress.parse("127.0.0.1", 0);
    var upstream = try upstream_address.listen(io, .{ .reuse_address = true });
    defer upstream.deinit(io);
    const upstream_port = upstream.socket.address.getPort();
    var upstream_state: TestHttpServerState = .{ .server = &upstream, .io = io, .expected_body = "delayed-body" };
    const upstream_thread = try std.Thread.spawn(.{}, testHttpServer, .{&upstream_state});
    defer upstream_thread.join();
    std.Io.sleep(io, std.Io.Duration.fromNanoseconds(50 * std.time.ns_per_ms), .awake) catch {};

    var runtime = try start(std.testing.allocator, &loaded, .observe);
    defer runtime.deinit();
    std.Io.sleep(io, std.Io.Duration.fromNanoseconds(50 * std.time.ns_per_ms), .awake) catch {};
    const proxy_port = try bindPort(runtime.bindUrl());
    const proxy_addr = try std.Io.net.IpAddress.parse("127.0.0.1", proxy_port);
    var client = try std.Io.net.IpAddress.connect(&proxy_addr, io, .{ .mode = .stream });
    defer client.close(io);
    var request_buf: [256]u8 = undefined;
    const head = try std.fmt.bufPrint(
        &request_buf,
        "POST http://127.0.0.1:{d}/echo HTTP/1.1\r\nHost: 127.0.0.1:{d}\r\nContent-Length: 12\r\nConnection: close\r\n\r\n",
        .{ upstream_port, upstream_port },
    );
    var client_write_buf: [512]u8 = undefined;
    var client_writer = client.writer(io, &client_write_buf);
    try client_writer.interface.writeAll(head);
    try client_writer.interface.flush();
    std.Io.sleep(io, std.Io.Duration.fromNanoseconds(250 * std.time.ns_per_ms), .awake) catch {};
    try client_writer.interface.writeAll("delayed-body");
    try client_writer.interface.flush();

    var response_buf: [512]u8 = undefined;
    const response_len = try readHttpResponse(io, client, &response_buf);
    try std.testing.expect(std.mem.indexOf(u8, response_buf[0..response_len], "200 OK") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_buf[0..response_len], "proxied") != null);

    try runtime.waitForIdle(2 * std.time.ns_per_s);
    const events = try runtime.snapshotAuditEvents(std.testing.allocator);
    defer runtime.freeAuditEvents(std.testing.allocator, events);
    try std.testing.expect(events.len >= 2);
    try std.testing.expectEqual(@import("orca_core").core.event.EventType.network_connect_attempt, events[0].event_type);
    try std.testing.expectEqual(@import("orca_core").core.event.EventType.network_connect_allowed, events[1].event_type);
    try std.testing.expect(std.mem.indexOf(u8, events[0].target, "127.0.0.1") != null);
}

test "proxy denies controlled HTTP endpoint before upstream connect" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;

    const io = std.testing.io;
    const upstream_address = try std.Io.net.IpAddress.parse("127.0.0.1", 0);
    var upstream = try upstream_address.listen(io, .{ .reuse_address = true });
    defer upstream.deinit(io);
    const upstream_port = upstream.socket.address.getPort();

    const policy_text = try std.fmt.allocPrint(std.testing.allocator,
        \\version: 1
        \\mode: strict
        \\network:
        \\  mode: open
        \\  backend: proxy
        \\  deny:
        \\    - "127.0.0.1:{d}"
    , .{upstream_port});
    defer std.testing.allocator.free(policy_text);
    var loaded = try @import("orca_core").policy.load.parseFromSlice(std.testing.allocator, policy_text, "proxy-http-deny.yaml");
    defer loaded.deinit();

    var upstream_state: TestDenyServerState = .{ .server = &upstream, .io = io };
    const upstream_thread = try std.Thread.spawn(.{}, testDenyServerNoConnect, .{&upstream_state});
    defer upstream_thread.join();

    var runtime = try start(std.testing.allocator, &loaded, .strict);
    defer runtime.deinit();
    std.Io.sleep(io, std.Io.Duration.fromNanoseconds(50 * std.time.ns_per_ms), .awake) catch {};

    const proxy_port = try bindPort(runtime.bindUrl());
    const proxy_addr = try std.Io.net.IpAddress.parse("127.0.0.1", proxy_port);
    var client = try std.Io.net.IpAddress.connect(&proxy_addr, io, .{ .mode = .stream });
    defer client.close(io);

    var request_buf: [256]u8 = undefined;
    const request = try std.fmt.bufPrint(
        &request_buf,
        "GET http://127.0.0.1:{d}/secret HTTP/1.1\r\nHost: 127.0.0.1:{d}\r\nConnection: close\r\n\r\n",
        .{ upstream_port, upstream_port },
    );
    var client_write_buf: [512]u8 = undefined;
    var client_writer = client.writer(io, &client_write_buf);
    try client_writer.interface.writeAll(request);
    try client_writer.interface.flush();

    var response_buf: [512]u8 = undefined;
    const response_len = try readHttpResponse(io, client, &response_buf);
    try std.testing.expect(std.mem.indexOf(u8, response_buf[0..response_len], "403 Forbidden") != null);

    try runtime.waitForIdle(2 * std.time.ns_per_s);
    const events = try runtime.snapshotAuditEvents(std.testing.allocator);
    defer runtime.freeAuditEvents(std.testing.allocator, events);
    try std.testing.expectEqual(@as(usize, 2), events.len);
    try std.testing.expectEqual(@import("orca_core").core.event.EventType.network_connect_attempt, events[0].event_type);
    try std.testing.expectEqual(@import("orca_core").core.event.EventType.network_connect_denied, events[1].event_type);
    try std.testing.expectEqual(@import("orca_core").core.decision.DecisionResult.deny, events[1].result.?);
    try std.testing.expect(std.mem.indexOf(u8, events[1].reason.?, "explicit network deny") != null);
    try std.testing.expect(!upstream_state.accepted.load(.acquire));
}

test "proxy applies HTTP method and path policy while CONNECT remains host-port only" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;

    const io = std.testing.io;
    const upstream_address = try std.Io.net.IpAddress.parse("127.0.0.1", 0);
    var upstream = try upstream_address.listen(io, .{ .reuse_address = true });
    defer upstream.deinit(io);
    const upstream_port = upstream.socket.address.getPort();

    const policy_text = try std.fmt.allocPrint(std.testing.allocator,
        \\version: 1
        \\mode: strict
        \\network:
        \\  mode: open
        \\  backend: proxy
        \\services:
        \\  local_test:
        \\    hosts:
        \\      - "127.0.0.1:{d}"
        \\    methods:
        \\      - "GET"
        \\    paths:
        \\      deny:
        \\        - "/secret"
        \\    unmatched: allow
    , .{upstream_port});
    defer std.testing.allocator.free(policy_text);
    var loaded = try @import("orca_core").policy.load.parseFromSlice(std.testing.allocator, policy_text, "proxy-service-deny.yaml");
    defer loaded.deinit();

    var runtime = try start(std.testing.allocator, &loaded, .strict);
    defer runtime.deinit();
    std.Io.sleep(io, std.Io.Duration.fromNanoseconds(50 * std.time.ns_per_ms), .awake) catch {};

    const proxy_port = try bindPort(runtime.bindUrl());
    const proxy_addr = try std.Io.net.IpAddress.parse("127.0.0.1", proxy_port);

    {
        var client = try std.Io.net.IpAddress.connect(&proxy_addr, io, .{ .mode = .stream });
        defer client.close(io);
        var request_buf: [256]u8 = undefined;
        const request = try std.fmt.bufPrint(
            &request_buf,
            "GET http://127.0.0.1:{d}/secret HTTP/1.1\r\nHost: 127.0.0.1:{d}\r\nConnection: close\r\n\r\n",
            .{ upstream_port, upstream_port },
        );
        var client_write_buf: [512]u8 = undefined;
        var client_writer = client.writer(io, &client_write_buf);
        try client_writer.interface.writeAll(request);
        try client_writer.interface.flush();
        var response_buf: [512]u8 = undefined;
        const response_len = try readHttpResponse(io, client, &response_buf);
        try std.testing.expect(std.mem.indexOf(u8, response_buf[0..response_len], "403 Forbidden") != null);
    }

    try runtime.waitForIdle(2 * std.time.ns_per_s);
    const events = try runtime.snapshotAuditEvents(std.testing.allocator);
    defer runtime.freeAuditEvents(std.testing.allocator, events);
    try std.testing.expect(events.len >= 2);
    try std.testing.expectEqual(@import("orca_core").core.event.EventType.network_connect_denied, events[1].event_type);
    try std.testing.expect(std.mem.indexOf(u8, events[1].reason.?, "service path deny") != null);

    var connect_target_buf: [32]u8 = undefined;
    const connect_target = try std.fmt.bufPrint(&connect_target_buf, "127.0.0.1:{d}", .{upstream_port});
    var connect_decision = try network.evaluate(std.testing.allocator, &loaded, .strict, connect_target, .{
        .enforcement_mode = .proxy_mediated,
        .method = null,
    });
    defer connect_decision.deinit(std.testing.allocator);
    try std.testing.expectEqual(@import("orca_core").core.decision.DecisionResult.allow, connect_decision.decision.result);
    try std.testing.expectEqualStrings("services.local_test.unmatched", connect_decision.decision.rule_id.?);
}

const TestHttpServerState = struct {
    server: *std.Io.net.Server,
    io: std.Io,
    expected_body: []const u8,
};

fn testHttpServer(state: *TestHttpServerState) void {
    var listen_fd = [_]std.posix.pollfd{.{
        .fd = state.server.socket.handle,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};
    _ = std.posix.poll(&listen_fd, 5_000) catch return;
    var stream = state.server.accept(state.io) catch return;
    defer stream.close(state.io);
    var buffer: [1024]u8 = undefined;
    var total: usize = 0;
    const started = std.Io.Clock.Timestamp.now(state.io, .awake);
    const deadline_ns: i96 = 750 * std.time.ns_per_ms;
    while (total < buffer.len and started.durationFromNow(state.io).raw.nanoseconds < deadline_ns) {
        var fds = [_]std.posix.pollfd{.{
            .fd = stream.socket.handle,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};
        const ready = std.posix.poll(&fds, 50) catch break;
        if (ready == 0) continue;
        const n = std.posix.read(stream.socket.handle, buffer[total..]) catch |err| switch (err) {
            error.WouldBlock => continue,
            else => break,
        };
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
    var write_buf: [256]u8 = undefined;
    var writer = stream.writer(state.io, &write_buf);
    writer.interface.writeAll(text) catch {};
    writer.interface.flush() catch {};
}

const TestDenyServerState = struct {
    server: *std.Io.net.Server,
    io: std.Io,
    accepted: std.atomic.Value(bool) = .init(false),
};

fn testDenyServerNoConnect(state: *TestDenyServerState) void {
    var listen_fd = [_]std.posix.pollfd{.{
        .fd = state.server.socket.handle,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};
    const ready = std.posix.poll(&listen_fd, 500) catch return;
    if (ready == 0) return;
    var stream = state.server.accept(state.io) catch return;
    defer stream.close(state.io);
    state.accepted.store(true, .release);
}

fn readHttpResponse(io: std.Io, stream: std.Io.net.Stream, buffer: []u8) !usize {
    var total: usize = 0;
    const started = std.Io.Clock.Timestamp.now(io, .awake);
    const deadline_ns: i96 = 2 * std.time.ns_per_s;
    while (total < buffer.len and started.durationFromNow(io).raw.nanoseconds < deadline_ns) {
        var fds = [_]std.posix.pollfd{.{
            .fd = stream.socket.handle,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};
        const ready = std.posix.poll(&fds, 100) catch break;
        if (ready == 0) continue;
        const n = std.posix.read(stream.socket.handle, buffer[total..]) catch |err| switch (err) {
            error.WouldBlock => continue,
            else => return err,
        };
        if (n == 0) break;
        total += n;
        if (std.mem.indexOf(u8, buffer[0..total], "\r\n\r\n") != null) break;
    }
    return total;
}

fn bindPort(bind_url: []const u8) !u16 {
    const colon = std.mem.lastIndexOfScalar(u8, bind_url, ':') orelse return error.InvalidBindUrl;
    return std.fmt.parseInt(u16, bind_url[colon + 1 ..], 10);
}
