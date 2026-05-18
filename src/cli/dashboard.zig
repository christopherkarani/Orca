const std = @import("std");

const dashboard = @import("../dashboard/mod.zig");
const credentials_cmd = @import("credentials.zig");
const doctor = @import("doctor.zig");
const report_cmd = @import("report.zig");
const init = @import("init.zig");
const license_cmd = @import("license.zig");
const ci_cmd = @import("ci.zig");
const demo_cmd = @import("demo.zig");
const plugin = @import("plugin.zig");
const policy = @import("policy.zig");
const replay = @import("replay.zig");
const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");
const core = @import("aegis_core").core;
const core_policy = @import("aegis_core").policy;
const intercept = @import("../intercept/mod.zig");

const default_host = "127.0.0.1";
const default_port: u16 = 7742;

const index_html = @embedFile("../dashboard/assets/index.html");
const app_css = @embedFile("../dashboard/assets/app.css");
const app_js = @embedFile("../dashboard/assets/app.js");

const DashboardOptions = struct {
    host: []const u8 = default_host,
    port: u16 = default_port,
    once: bool = false,
};

const Request = struct {
    method: []const u8,
    path: []const u8,
    body: []const u8,
    csrf_token: ?[]const u8,
};

pub fn command(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    const options = parseOptions(argv, stdout, stderr) catch |err| switch (err) {
        error.HelpShown => return exit_codes.success,
        error.Usage => return exit_codes.usage,
        else => return err,
    };
    return serve(options, stdout, stderr);
}

pub fn commandForTest(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    return command(argv, stdout, stderr);
}

fn parseOptions(argv: []const []const u8, stdout: anytype, stderr: anytype) !DashboardOptions {
    var options: DashboardOptions = .{};
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        const arg = argv[index];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            _ = try help.writeCommand(stdout, "dashboard");
            return error.HelpShown;
        } else if (std.mem.eql(u8, arg, "--host")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("orca dashboard: --host requires an address.\n");
                return error.Usage;
            }
            if (!std.mem.eql(u8, argv[index], "127.0.0.1") and !std.mem.eql(u8, argv[index], "localhost")) {
                try stderr.writeAll("orca dashboard: only localhost bindings are supported by default.\n");
                return error.Usage;
            }
            options.host = if (std.mem.eql(u8, argv[index], "localhost")) "127.0.0.1" else argv[index];
        } else if (std.mem.eql(u8, arg, "--port")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("orca dashboard: --port requires a number.\n");
                return error.Usage;
            }
            options.port = std.fmt.parseInt(u16, argv[index], 10) catch {
                try stderr.writeAll("orca dashboard: --port must be between 1 and 65535.\n");
                return error.Usage;
            };
        } else if (std.mem.eql(u8, arg, "--once")) {
            options.once = true;
        } else {
            try stderr.print("orca dashboard: unknown option '{s}'.\n", .{arg});
            return error.Usage;
        }
    }
    return options;
}

fn serve(options: DashboardOptions, stdout: anytype, stderr: anytype) !u8 {
    const address = std.net.Address.parseIp(options.host, options.port) catch |err| {
        try stderr.print("orca dashboard: invalid bind address: {s}\n", .{@errorName(err)});
        return exit_codes.usage;
    };
    var server = address.listen(.{ .reuse_address = true }) catch |err| {
        try stderr.print("orca dashboard: failed to listen on {s}:{d}: {s}\n", .{ options.host, options.port, @errorName(err) });
        return exit_codes.general;
    };
    defer server.deinit();
    try stdout.print("Orca dashboard listening at http://{s}:{d}\n", .{ options.host, options.port });
    try flushIfSupported(stdout);

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    const csrf_token = try makeCsrfToken(allocator);
    defer allocator.free(csrf_token);

    while (true) {
        var connection = server.accept() catch |err| {
            try stderr.print("orca dashboard: accept failed: {s}\n", .{@errorName(err)});
            continue;
        };
        defer connection.stream.close();
        handleConnection(allocator, connection.stream, csrf_token) catch |err| {
            try stderr.print("orca dashboard: request failed: {s}\n", .{@errorName(err)});
        };
        if (options.once) break;
    }
    return exit_codes.success;
}

fn handleConnection(allocator: std.mem.Allocator, stream: std.net.Stream, csrf_token: []const u8) !void {
    var request_buffer: std.ArrayList(u8) = .empty;
    defer request_buffer.deinit(allocator);
    try readRequest(allocator, stream, &request_buffer);
    const request = parseRequest(request_buffer.items) catch {
        try sendText(stream, 400, "Bad Request", "text/plain; charset=utf-8", "bad request\n");
        return;
    };

    const workspace_root = try dashboard.resolveWorkspaceRoot(allocator);
    defer allocator.free(workspace_root);
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(allocator);
    const writer = body.writer(allocator);

    if (std.mem.eql(u8, request.method, "GET") and (std.mem.eql(u8, request.path, "/") or std.mem.eql(u8, request.path, "/index.html"))) {
        const html = try std.mem.replaceOwned(u8, allocator, index_html, "__ORCA_DASHBOARD_TOKEN__", csrf_token);
        defer allocator.free(html);
        try sendText(stream, 200, "OK", "text/html; charset=utf-8", html);
        return;
    }
    if (std.mem.eql(u8, request.method, "GET") and std.mem.eql(u8, request.path, "/assets/app.css")) {
        try sendText(stream, 200, "OK", "text/css; charset=utf-8", app_css);
        return;
    }
    if (std.mem.eql(u8, request.method, "GET") and std.mem.eql(u8, request.path, "/assets/app.js")) {
        try sendText(stream, 200, "OK", "application/javascript; charset=utf-8", app_js);
        return;
    }
    if (std.mem.eql(u8, request.method, "GET") and std.mem.eql(u8, request.path, "/api/status")) {
        try dashboard.writeStatusJson(allocator, writer, workspace_root);
        try sendText(stream, 200, "OK", "application/json; charset=utf-8", body.items);
        return;
    }
    if (std.mem.eql(u8, request.method, "GET") and std.mem.eql(u8, request.path, "/api/policy")) {
        try dashboard.writePolicyJson(allocator, writer, workspace_root);
        try sendText(stream, 200, "OK", "application/json; charset=utf-8", body.items);
        return;
    }
    if (std.mem.eql(u8, request.method, "GET") and std.mem.eql(u8, request.path, "/api/sessions")) {
        try dashboard.writeSessionsJson(allocator, writer, workspace_root);
        try sendText(stream, 200, "OK", "application/json; charset=utf-8", body.items);
        return;
    }
    if (std.mem.eql(u8, request.method, "POST") and std.mem.eql(u8, request.path, "/api/policy")) {
        if (!tokenMatches(request.csrf_token, csrf_token)) return sendJsonError(stream, 403, "Forbidden", "csrf");
        try handlePolicySave(allocator, writer, workspace_root, request.body);
        try sendText(stream, 200, "OK", "application/json; charset=utf-8", body.items);
        return;
    }
    if (std.mem.eql(u8, request.method, "POST") and std.mem.eql(u8, request.path, "/api/policy/init")) {
        if (!tokenMatches(request.csrf_token, csrf_token)) return sendJsonError(stream, 403, "Forbidden", "csrf");
        try handlePolicyInit(allocator, writer, workspace_root, request.body);
        try sendText(stream, 200, "OK", "application/json; charset=utf-8", body.items);
        return;
    }
    if (std.mem.eql(u8, request.method, "POST") and std.mem.eql(u8, request.path, "/api/actions")) {
        if (!tokenMatches(request.csrf_token, csrf_token)) return sendJsonError(stream, 403, "Forbidden", "csrf");
        try handleAction(allocator, writer, request.body);
        try sendText(stream, 200, "OK", "application/json; charset=utf-8", body.items);
        return;
    }
    try sendText(stream, 404, "Not Found", "application/json; charset=utf-8", "{\"error\":\"not_found\"}\n");
}

fn readRequest(allocator: std.mem.Allocator, stream: std.net.Stream, buffer: *std.ArrayList(u8)) !void {
    var temp: [8192]u8 = undefined;
    while (buffer.items.len < dashboard.max_request_body_len + 8192) {
        const n = try stream.read(&temp);
        if (n == 0) break;
        try buffer.appendSlice(allocator, temp[0..n]);
        if (requestComplete(buffer.items)) break;
    }
}

fn requestComplete(bytes: []const u8) bool {
    const header_end = std.mem.indexOf(u8, bytes, "\r\n\r\n") orelse return false;
    const content_length = parseContentLength(bytes[0..header_end]) orelse 0;
    return bytes.len >= header_end + 4 + content_length;
}

fn parseRequest(bytes: []const u8) !Request {
    const header_end = std.mem.indexOf(u8, bytes, "\r\n\r\n") orelse return error.BadRequest;
    const headers = bytes[0..header_end];
    const line_end = std.mem.indexOf(u8, headers, "\r\n") orelse return error.BadRequest;
    const request_line = headers[0..line_end];
    var parts = std.mem.splitScalar(u8, request_line, ' ');
    const method = parts.next() orelse return error.BadRequest;
    const target = parts.next() orelse return error.BadRequest;
    _ = parts.next() orelse return error.BadRequest;
    const path = stripQuery(target);
    const content_length = parseContentLength(headers) orelse 0;
    if (content_length > dashboard.max_request_body_len) return error.BadRequest;
    const body_start = header_end + 4;
    if (bytes.len < body_start + content_length) return error.BadRequest;
    return .{
        .method = method,
        .path = path,
        .body = bytes[body_start .. body_start + content_length],
        .csrf_token = headerValue(headers, "x-orca-dashboard-token"),
    };
}

fn stripQuery(target: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, target, '?')) |index| return target[0..index];
    return target;
}

fn parseContentLength(headers: []const u8) ?usize {
    const value = headerValue(headers, "content-length") orelse return null;
    return std.fmt.parseInt(usize, value, 10) catch null;
}

fn headerValue(headers: []const u8, wanted: []const u8) ?[]const u8 {
    var lines = std.mem.splitSequence(u8, headers, "\r\n");
    _ = lines.next();
    while (lines.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const name = std.mem.trim(u8, line[0..colon], " \t");
        if (!std.ascii.eqlIgnoreCase(name, wanted)) continue;
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        return value;
    }
    return null;
}

fn tokenMatches(value: ?[]const u8, expected: []const u8) bool {
    return value != null and std.mem.eql(u8, value.?, expected);
}

fn makeCsrfToken(allocator: std.mem.Allocator) ![]u8 {
    var bytes: [16]u8 = undefined;
    std.crypto.random.bytes(&bytes);
    const hex = std.fmt.bytesToHex(bytes, .lower);
    return try allocator.dupe(u8, &hex);
}

fn handlePolicySave(allocator: std.mem.Allocator, writer: anytype, workspace_root: []const u8, body: []const u8) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    const object = if (parsed.value == .object) parsed.value.object else return error.BadRequest;
    const text_value = object.get("text") orelse return error.BadRequest;
    if (text_value != .string) return error.BadRequest;
    const result = try dashboard.savePolicyText(allocator, workspace_root, text_value.string);
    try writePolicyMutationResult(writer, result);
}

fn handlePolicyInit(allocator: std.mem.Allocator, writer: anytype, workspace_root: []const u8, body: []const u8) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    const object = if (parsed.value == .object) parsed.value.object else return error.BadRequest;
    const preset_value = object.get("preset") orelse return error.BadRequest;
    if (preset_value != .string) return error.BadRequest;
    const force = if (object.get("force")) |value| value == .bool and value.bool else false;
    const result = try dashboard.initPolicyFromPreset(allocator, workspace_root, preset_value.string, force);
    try writePolicyMutationResult(writer, result);
}

fn writePolicyMutationResult(writer: anytype, result: dashboard.PolicySaveResult) !void {
    try writer.writeByte('{');
    try writer.writeAll("\"ok\":");
    try writer.writeAll(if (result.ok) "true" else "false");
    try writer.writeAll(",\"error\":");
    if (result.error_name) |name| try core.util.writeJsonString(writer, name) else try writer.writeAll("null");
    try writer.writeByte('}');
}

fn handleAction(allocator: std.mem.Allocator, writer: anytype, body: []const u8) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    const object = if (parsed.value == .object) parsed.value.object else return error.BadRequest;
    const action_value = object.get("action") orelse return error.BadRequest;
    if (action_value != .string) return error.BadRequest;
    const result = try runAllowedAction(allocator, action_value.string);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    try writer.print("{{\"ok\":{},\"exit_code\":{d},\"stdout\":", .{ result.exit_code == exit_codes.success, result.exit_code });
    try core.util.writeJsonString(writer, result.stdout);
    try writer.writeAll(",\"stderr\":");
    try core.util.writeJsonString(writer, result.stderr);
    try writer.writeByte('}');
}

const CapturedAction = struct {
    exit_code: u8,
    stdout: []u8,
    stderr: []u8,
};

fn runAllowedAction(allocator: std.mem.Allocator, action: []const u8) !CapturedAction {
    var stdout: std.ArrayList(u8) = .empty;
    errdefer stdout.deinit(allocator);
    var stderr: std.ArrayList(u8) = .empty;
    errdefer stderr.deinit(allocator);

    const code = if (std.mem.eql(u8, action, "doctor"))
        try doctor.command(&.{}, stdout.writer(allocator), stderr.writer(allocator))
    else if (std.mem.eql(u8, action, "policy-check"))
        try policy.command(&.{ "check", ".orca/policy.yaml" }, stdout.writer(allocator), stderr.writer(allocator))
    else if (std.mem.eql(u8, action, "credentials-check"))
        try credentials_cmd.command(&.{"check"}, stdout.writer(allocator), stderr.writer(allocator))
    else if (std.mem.eql(u8, action, "credentials-check-github"))
        try credentials_cmd.command(&.{ "check", "github_pat" }, stdout.writer(allocator), stderr.writer(allocator))
    else if (std.mem.eql(u8, action, "proxy-smoke"))
        try proxySmokeAction(allocator, stdout.writer(allocator), stderr.writer(allocator))
    else if (std.mem.eql(u8, action, "policy-explain-github"))
        try policy.command(&.{ "explain", "network", "https://api.github.com/repos/acme/app/issues", "--method", "POST" }, stdout.writer(allocator), stderr.writer(allocator))
    else if (std.mem.eql(u8, action, "replay-last"))
        try replay.command(&.{ "--session", "last", "--verify" }, stdout.writer(allocator), stderr.writer(allocator))
    else if (std.mem.eql(u8, action, "openclaw-doctor"))
        try plugin.command(&.{ "doctor", "openclaw" }, stdout.writer(allocator), stderr.writer(allocator))
    else if (std.mem.eql(u8, action, "hermes-doctor"))
        try plugin.command(&.{ "doctor", "hermes" }, stdout.writer(allocator), stderr.writer(allocator))
    else if (std.mem.eql(u8, action, "replay-denied"))
        try replay.command(&.{ "--session", "last", "--only", "denied", "--verify" }, stdout.writer(allocator), stderr.writer(allocator))
    else if (std.mem.eql(u8, action, "init-generic-agent"))
        try init.command(std.fs.cwd(), &.{ "--preset", "generic-agent" }, stdout.writer(allocator), stderr.writer(allocator))
    else if (std.mem.eql(u8, action, "report-last"))
        try report_cmd.command(&.{ "--session", "last", "--format", "markdown" }, stdout.writer(allocator), stderr.writer(allocator))
    else if (std.mem.eql(u8, action, "ci-check"))
        try ci_cmd.command(&.{ "check", "--format", "markdown" }, stdout.writer(allocator), stderr.writer(allocator))
    else if (std.mem.eql(u8, action, "demo-blocked-action"))
        try demo_cmd.command(&.{"blocked-action"}, stdout.writer(allocator), stderr.writer(allocator))
    else if (std.mem.eql(u8, action, "license-status"))
        try license_cmd.command(&.{"status"}, stdout.writer(allocator), stderr.writer(allocator))
    else
        return error.UnsupportedDashboardAction;

    return .{
        .exit_code = code,
        .stdout = try stdout.toOwnedSlice(allocator),
        .stderr = try stderr.toOwnedSlice(allocator),
    };
}

fn proxySmokeAction(allocator: std.mem.Allocator, stdout: anytype, _: anytype) !u8 {
    var loaded = try core_policy.load.parseFromSlice(allocator,
        \\version: 1
        \\mode: observe
        \\network:
        \\  mode: open
        \\  backend: proxy
    , "dashboard-proxy-smoke.yaml");
    defer loaded.deinit();

    const upstream_address = try std.net.Address.parseIp("127.0.0.1", 0);
    var upstream = try upstream_address.listen(.{ .reuse_address = true });
    defer upstream.deinit();
    const upstream_port = upstream.listen_address.in.getPort();
    var upstream_state: ProxySmokeServerState = .{ .server = &upstream };
    const upstream_thread = try std.Thread.spawn(.{}, proxySmokeServer, .{&upstream_state});
    defer upstream_thread.join();

    var runtime = try intercept.proxy.start(allocator, &loaded, .observe);
    defer runtime.deinit();
    const proxy_port = try parseBindPort(runtime.bindUrl());
    var client = try std.net.tcpConnectToHost(allocator, "127.0.0.1", proxy_port);
    defer client.close();

    var request_buf: [256]u8 = undefined;
    const request = try std.fmt.bufPrint(
        &request_buf,
        "GET http://127.0.0.1:{d}/proxy-smoke HTTP/1.1\r\nHost: 127.0.0.1:{d}\r\nConnection: close\r\n\r\n",
        .{ upstream_port, upstream_port },
    );
    try client.writeAll(request);
    var response_buf: [1024]u8 = undefined;
    const response_len = try client.read(&response_buf);
    if (std.mem.indexOf(u8, response_buf[0..response_len], "proxy-smoke-ok") == null) return exit_codes.general;

    try runtime.waitForIdle(1 * std.time.ns_per_s);
    const events = try runtime.snapshotAuditEvents(allocator);
    defer runtime.freeAuditEvents(allocator, events);
    var saw_attempt = false;
    var saw_allowed = false;
    for (events) |ev| {
        if (ev.event_type == .network_connect_attempt) saw_attempt = true;
        if (ev.event_type == .network_connect_allowed) saw_allowed = true;
    }
    if (!saw_attempt or !saw_allowed) return exit_codes.general;
    try stdout.writeAll("proxy forwarding smoke ok\n");
    return exit_codes.success;
}

const ProxySmokeServerState = struct {
    server: *std.net.Server,
};

fn proxySmokeServer(state: *ProxySmokeServerState) void {
    var connection = state.server.accept() catch return;
    defer connection.stream.close();
    var request_buf: [512]u8 = undefined;
    _ = connection.stream.read(&request_buf) catch return;
    const body = "proxy-smoke-ok";
    var response_buf: [160]u8 = undefined;
    const response = std.fmt.bufPrint(&response_buf, "HTTP/1.1 200 OK\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ body.len, body }) catch return;
    connection.stream.writeAll(response) catch {};
}

fn parseBindPort(bind_url: []const u8) !u16 {
    const colon = std.mem.lastIndexOfScalar(u8, bind_url, ':') orelse return error.InvalidBindUrl;
    return std.fmt.parseInt(u16, bind_url[colon + 1 ..], 10);
}

fn sendText(stream: std.net.Stream, status_code: u16, reason: []const u8, content_type: []const u8, body: []const u8) !void {
    var header_buf: [512]u8 = undefined;
    const header = try std.fmt.bufPrint(
        &header_buf,
        "HTTP/1.1 {d} {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n",
        .{ status_code, reason, content_type, body.len },
    );
    try stream.writeAll(header);
    try stream.writeAll(body);
}

fn sendJsonError(stream: std.net.Stream, status_code: u16, reason: []const u8, message: []const u8) !void {
    var body_buf: [128]u8 = undefined;
    const body = try std.fmt.bufPrint(&body_buf, "{{\"error\":\"{s}\"}}\n", .{message});
    try sendText(stream, status_code, reason, "application/json; charset=utf-8", body);
}

fn flushIfSupported(writer: anytype) !void {
    const WriterType = @TypeOf(writer);
    switch (@typeInfo(WriterType)) {
        .pointer => |pointer| {
            if (@hasDecl(pointer.child, "flush")) try writer.flush();
        },
        else => {
            if (@hasDecl(WriterType, "flush")) try writer.flush();
        },
    }
}

test "dashboard rejects non-localhost bindings" {
    var stdout_buf: [256]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try commandForTest(&.{ "--host", "0.0.0.0" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "localhost") != null);
}

test "dashboard action allowlist rejects arbitrary browser commands" {
    try std.testing.expectError(error.UnsupportedDashboardAction, runAllowedAction(std.testing.allocator, "rm -rf /"));
}

test "dashboard proxy-smoke action verifies local proxy forwarding" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;

    const result = try runAllowedAction(std.testing.allocator, "proxy-smoke");
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try std.testing.expectEqual(exit_codes.success, result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "proxy forwarding smoke ok") != null);
}

test "request parser handles post body and query stripping" {
    const request_text =
        "POST /api/actions?x=1 HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Orca-Dashboard-Token: abc\r\nContent-Length: 19\r\n\r\n{\"action\":\"doctor\"}";
    const request = try parseRequest(request_text);
    try std.testing.expectEqualStrings("POST", request.method);
    try std.testing.expectEqualStrings("/api/actions", request.path);
    try std.testing.expectEqualStrings("{\"action\":\"doctor\"}", request.body);
    try std.testing.expectEqualStrings("abc", request.csrf_token.?);
}
