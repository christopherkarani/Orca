const std = @import("std");

const dashboard = @import("../dashboard/mod.zig");
const resource_root = @import("../resource_root.zig");
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
const core = @import("orca_core").core;
const core_policy = @import("orca_core").policy;
const intercept = @import("../intercept/mod.zig");

const default_host = "127.0.0.1";
const default_port: u16 = 7742;
const ui_dist_dir = "orca-dashboard-ui/dist";

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

pub fn command(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    const options = parseOptions(io, argv, stdout, stderr) catch |err| switch (err) {
        error.HelpShown => return exit_codes.success,
        error.Usage => return exit_codes.usage,
        else => return err,
    };
    return serve(io, options, stdout, stderr);
}

pub fn commandForTest(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    return command(std.testing.io, argv, stdout, stderr);
}

fn parseOptions(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !DashboardOptions {
    var options: DashboardOptions = .{};
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        const arg = argv[index];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            _ = try help.writeCommand(io, stdout, "dashboard");
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

fn serve(io: std.Io, options: DashboardOptions, stdout: anytype, stderr: anytype) !u8 {
    const address = std.Io.net.IpAddress.parse(options.host, options.port) catch |err| {
        try stderr.print("orca dashboard: invalid bind address: {s}\n", .{@errorName(err)});
        return exit_codes.usage;
    };
    var server = address.listen(io, .{ .reuse_address = true }) catch |err| {
        try stderr.print("orca dashboard: failed to listen on {s}:{d}: {s}\n", .{ options.host, options.port, @errorName(err) });
        return exit_codes.general;
    };
    defer server.deinit(io);
    try stdout.print("Orca dashboard listening at http://{s}:{d}\n", .{ options.host, options.port });
    try flushIfSupported(stdout);

    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    const csrf_token = try makeCsrfToken(io, allocator);
    defer allocator.free(csrf_token);

    while (true) {
        var stream = server.accept(io) catch |err| {
            try stderr.print("orca dashboard: accept failed: {s}\n", .{@errorName(err)});
            continue;
        };
        defer stream.close(io);
        handleConnection(io, allocator, stream, csrf_token) catch |err| {
            try stderr.print("orca dashboard: request failed: {s}\n", .{@errorName(err)});
        };
        if (options.once) break;
    }
    return exit_codes.success;
}

fn handleConnection(io: std.Io, allocator: std.mem.Allocator, stream: std.Io.net.Stream, csrf_token: []const u8) !void {
    var request_buffer: std.ArrayList(u8) = .empty;
    defer request_buffer.deinit(allocator);
    try readRequest(io, allocator, stream, &request_buffer);
    const request = parseRequest(request_buffer.items) catch {
        try sendText(io, stream, 400, "Bad Request", "text/plain; charset=utf-8", "bad request\n");
        return;
    };

    const workspace_root = try dashboard.resolveWorkspaceRoot(io, allocator);
    defer allocator.free(workspace_root);
    const dist_dir = try resource_root.resolveResourcePath(io, allocator, .{ .workspace_root = workspace_root }, ui_dist_dir);
    defer allocator.free(dist_dir);
    var body_aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer body_aw.deinit();
    const writer = &body_aw.writer;

    if (std.mem.eql(u8, request.method, "GET") and !std.mem.startsWith(u8, request.path, "/api/")) {
        try serveStaticFile(io, allocator, stream, request.path, csrf_token, dist_dir);
        return;
    }
    if (std.mem.eql(u8, request.method, "GET") and std.mem.eql(u8, request.path, "/api/status")) {
        try dashboard.writeStatusJson(io, allocator, writer, workspace_root);
        try body_aw.writer.flush();
        const response_body = try body_aw.toOwnedSlice();
        defer allocator.free(response_body);
        try sendText(io, stream, 200, "OK", "application/json; charset=utf-8", response_body);
        return;
    }
    if (std.mem.eql(u8, request.method, "GET") and std.mem.eql(u8, request.path, "/api/policy")) {
        try dashboard.writePolicyJson(io, allocator, writer, workspace_root);
        try body_aw.writer.flush();
        const response_body = try body_aw.toOwnedSlice();
        defer allocator.free(response_body);
        try sendText(io, stream, 200, "OK", "application/json; charset=utf-8", response_body);
        return;
    }
    if (std.mem.eql(u8, request.method, "GET") and std.mem.eql(u8, request.path, "/api/sessions")) {
        try dashboard.writeSessionsJson(io, allocator, writer, workspace_root);
        try body_aw.writer.flush();
        const response_body = try body_aw.toOwnedSlice();
        defer allocator.free(response_body);
        try sendText(io, stream, 200, "OK", "application/json; charset=utf-8", response_body);
        return;
    }
    if (std.mem.eql(u8, request.method, "POST") and std.mem.eql(u8, request.path, "/api/policy")) {
        if (!tokenMatches(request.csrf_token, csrf_token)) return sendJsonError(io, stream, 403, "Forbidden", "csrf");
        try handlePolicySave(io, allocator, writer, workspace_root, request.body);
        try body_aw.writer.flush();
        const response_body = try body_aw.toOwnedSlice();
        defer allocator.free(response_body);
        try sendText(io, stream, 200, "OK", "application/json; charset=utf-8", response_body);
        return;
    }
    if (std.mem.eql(u8, request.method, "POST") and std.mem.eql(u8, request.path, "/api/policy/init")) {
        if (!tokenMatches(request.csrf_token, csrf_token)) return sendJsonError(io, stream, 403, "Forbidden", "csrf");
        try handlePolicyInit(io, allocator, writer, workspace_root, request.body);
        try body_aw.writer.flush();
        const response_body = try body_aw.toOwnedSlice();
        defer allocator.free(response_body);
        try sendText(io, stream, 200, "OK", "application/json; charset=utf-8", response_body);
        return;
    }
    if (std.mem.eql(u8, request.method, "POST") and std.mem.eql(u8, request.path, "/api/actions")) {
        if (!tokenMatches(request.csrf_token, csrf_token)) return sendJsonError(io, stream, 403, "Forbidden", "csrf");
        try handleAction(io, allocator, writer, request.body);
        try body_aw.writer.flush();
        const response_body = try body_aw.toOwnedSlice();
        defer allocator.free(response_body);
        try sendText(io, stream, 200, "OK", "application/json; charset=utf-8", response_body);
        return;
    }
    try sendText(io, stream, 404, "Not Found", "application/json; charset=utf-8", "{\"error\":\"not_found\"}\n");
}

fn serveStaticFile(io: std.Io, allocator: std.mem.Allocator, stream: std.Io.net.Stream, path: []const u8, csrf_token: []const u8, dist_dir: []const u8) !void {
    const rel_path = if (std.mem.eql(u8, path, "/")) "index.html" else path[1..];

    const file_path = try std.fs.path.join(allocator, &.{ dist_dir, rel_path });
    defer allocator.free(file_path);

    const file = std.Io.Dir.cwd().openFile(io, file_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            return tryServeIndexOrFallback(io, allocator, stream, rel_path, csrf_token, dist_dir);
        },
        else => return sendJsonError(io, stream, 500, "Internal Server Error", "read_failed"),
    };
    defer file.close(io);

    const stat = try file.stat(io);
    if (stat.kind == .directory) {
        return tryServeIndexOrFallback(io, allocator, stream, rel_path, csrf_token, dist_dir);
    }

    const content_type = blk: {
        const basename = std.fs.path.basename(rel_path);
        if (std.mem.endsWith(u8, basename, ".css"))
            break :blk "text/css; charset=utf-8"
        else if (std.mem.endsWith(u8, basename, ".js"))
            break :blk "application/javascript; charset=utf-8"
        else if (std.mem.endsWith(u8, basename, ".html"))
            break :blk "text/html; charset=utf-8"
        else if (std.mem.endsWith(u8, basename, ".json"))
            break :blk "application/json; charset=utf-8"
        else if (std.mem.endsWith(u8, basename, ".svg"))
            break :blk "image/svg+xml"
        else if (std.mem.endsWith(u8, basename, ".png"))
            break :blk "image/png"
        else
            break :blk "application/octet-stream";
    };

    return sendFile(io, stream, file, content_type, allocator, csrf_token);
}

fn tryServeIndexOrFallback(io: std.Io, allocator: std.mem.Allocator, stream: std.Io.net.Stream, rel_path: []const u8, csrf_token: []const u8, dist_dir: []const u8) !void {
    if (std.mem.endsWith(u8, rel_path, "/index.html")) {
        return sendJsonError(io, stream, 404, "Not Found", "not_found");
    }
    const index_fallback = try std.fs.path.join(allocator, &.{ dist_dir, rel_path, "index.html" });
    defer allocator.free(index_fallback);
    const index_file = std.Io.Dir.cwd().openFile(io, index_fallback, .{}) catch |inner_err| switch (inner_err) {
        error.FileNotFound => return serveSpaFallback(io, allocator, stream, csrf_token, dist_dir),
        else => return sendJsonError(io, stream, 500, "Internal Server Error", "read_failed"),
    };
    defer index_file.close(io);
    return sendFile(io, stream, index_file, "text/html; charset=utf-8", allocator, csrf_token);
}

fn serveSpaFallback(io: std.Io, allocator: std.mem.Allocator, stream: std.Io.net.Stream, csrf_token: []const u8, dist_dir: []const u8) !void {
    const index_path = try std.fs.path.join(allocator, &.{ dist_dir, "index.html" });
    defer allocator.free(index_path);
    const file = std.Io.Dir.cwd().openFile(io, index_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return sendJsonError(io, stream, 404, "Not Found", "not_found"),
        else => return sendJsonError(io, stream, 500, "Internal Server Error", "read_failed"),
    };
    defer file.close(io);
    return sendFile(io, stream, file, "text/html; charset=utf-8", allocator, csrf_token);
}

fn sendFile(io: std.Io, stream: std.Io.net.Stream, file: std.Io.File, content_type: []const u8, allocator: std.mem.Allocator, csrf_token: []const u8) !void {
    const stat = try file.stat(io);
    const size = stat.size;

    if (std.mem.eql(u8, content_type, "text/html; charset=utf-8")) {
        var raw_list: std.ArrayList(u8) = .empty;
        defer raw_list.deinit(allocator);
        var read_buf: [8192]u8 = undefined;
        var file_reader = file.reader(io, &read_buf);
        while (raw_list.items.len < size) {
            const n = try file_reader.interface.readSliceShort(read_buf[0..@min(read_buf.len, size - raw_list.items.len)]);
            if (n == 0) break;
            try raw_list.appendSlice(allocator, read_buf[0..n]);
        }
        const raw = try raw_list.toOwnedSlice(allocator);
        defer allocator.free(raw);
        const html = try std.mem.replaceOwned(u8, allocator, raw, "__ORCA_DASHBOARD_TOKEN__", csrf_token);
        defer allocator.free(html);
        try sendText(io, stream, 200, "OK", content_type, html);
        return;
    }

    var header_buf: [512]u8 = undefined;
    const header = try std.fmt.bufPrint(
        &header_buf,
        "HTTP/1.1 200 OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nCache-Control: public, max-age=3600\r\nConnection: close\r\n\r\n",
        .{ content_type, size },
    );
    var stream_buf: [8192]u8 = undefined;
    var stream_writer = stream.writer(io, &stream_buf);
    try stream_writer.interface.writeAll(header);
    try stream_writer.interface.flush();

    var read_buf: [8192]u8 = undefined;
    var file_reader = file.reader(io, &read_buf);
    var remaining = size;
    while (remaining > 0) {
        const to_read = @min(read_buf.len, remaining);
        const n = try file_reader.interface.readSliceShort(read_buf[0..to_read]);
        if (n == 0) break;
        try stream_writer.interface.writeAll(read_buf[0..n]);
        remaining -= n;
    }
    try stream_writer.interface.flush();
}

fn readRequest(io: std.Io, allocator: std.mem.Allocator, stream: std.Io.net.Stream, buffer: *std.ArrayList(u8)) !void {
    var temp: [8192]u8 = undefined;
    while (buffer.items.len < dashboard.max_request_body_len + 8192) {
        var reader = stream.reader(io, &temp);
        const n = try reader.interface.readSliceShort(&temp);
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

fn makeCsrfToken(io: std.Io, allocator: std.mem.Allocator) ![]u8 {
    var bytes: [16]u8 = undefined;
    try io.randomSecure(&bytes);
    const hex = std.fmt.bytesToHex(bytes, .lower);
    return try allocator.dupe(u8, &hex);
}

fn handlePolicySave(io: std.Io, allocator: std.mem.Allocator, writer: anytype, workspace_root: []const u8, body: []const u8) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    const object = if (parsed.value == .object) parsed.value.object else return error.BadRequest;
    const text_value = object.get("text") orelse return error.BadRequest;
    if (text_value != .string) return error.BadRequest;
    const result = try dashboard.savePolicyText(io, allocator, workspace_root, text_value.string);
    try writePolicyMutationResult(writer, result);
}

fn handlePolicyInit(io: std.Io, allocator: std.mem.Allocator, writer: anytype, workspace_root: []const u8, body: []const u8) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    const object = if (parsed.value == .object) parsed.value.object else return error.BadRequest;
    const preset_value = object.get("preset") orelse return error.BadRequest;
    if (preset_value != .string) return error.BadRequest;
    const force = if (object.get("force")) |value| value == .bool and value.bool else false;
    const result = try dashboard.initPolicyFromPreset(io, allocator, workspace_root, preset_value.string, force);
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

fn handleAction(io: std.Io, allocator: std.mem.Allocator, writer: anytype, body: []const u8) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    const object = if (parsed.value == .object) parsed.value.object else return error.BadRequest;
    const action_value = object.get("action") orelse return error.BadRequest;
    if (action_value != .string) return error.BadRequest;
    const result = try runAllowedAction(io, allocator, action_value.string);
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

fn runAllowedAction(io: std.Io, allocator: std.mem.Allocator, action: []const u8) !CapturedAction {
    var stdout_aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer stdout_aw.deinit();
    var stderr_aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer stderr_aw.deinit();
    const stdout = &stdout_aw.writer;
    const stderr = &stderr_aw.writer;

    const code = if (std.mem.eql(u8, action, "doctor"))
        try doctor.command(io, &.{}, stdout, stderr)
    else if (std.mem.eql(u8, action, "policy-check"))
        try policy.command(io, &.{ "check", ".orca/policy.yaml" }, stdout, stderr)
    else if (std.mem.eql(u8, action, "credentials-check"))
        try credentials_cmd.command(io, &.{"check"}, stdout, stderr)
    else if (std.mem.eql(u8, action, "credentials-check-github"))
        try credentials_cmd.command(io, &.{ "check", "github_pat" }, stdout, stderr)
    else if (std.mem.eql(u8, action, "proxy-smoke"))
        try proxySmokeAction(io, allocator, stdout, stderr)
    else if (std.mem.eql(u8, action, "policy-explain-github"))
        try policy.command(io, &.{ "explain", "network", "https://api.github.com/repos/acme/app/issues", "--method", "POST" }, stdout, stderr)
    else if (std.mem.eql(u8, action, "replay-last"))
        try replay.command(io, &.{ "--session", "last", "--verify" }, stdout, stderr)
    else if (std.mem.eql(u8, action, "openclaw-doctor"))
        try plugin.command(io, &.{ "doctor", "openclaw" }, stdout, stderr)
    else if (std.mem.eql(u8, action, "hermes-doctor"))
        try plugin.command(io, &.{ "doctor", "hermes" }, stdout, stderr)
    else if (std.mem.eql(u8, action, "replay-denied"))
        try replay.command(io, &.{ "--session", "last", "--only", "denied", "--verify" }, stdout, stderr)
    else if (std.mem.eql(u8, action, "init-generic-agent"))
        try init.command(io, std.Io.Dir.cwd(), &.{ "--preset", "generic-agent" }, stdout, stderr)
    else if (std.mem.eql(u8, action, "report-last"))
        try report_cmd.command(io, &.{ "--session", "last", "--format", "markdown" }, stdout, stderr)
    else if (std.mem.eql(u8, action, "ci-check"))
        try ci_cmd.command(io, &.{ "check", "--format", "markdown" }, stdout, stderr)
    else if (std.mem.eql(u8, action, "demo-blocked-action"))
        try demo_cmd.command(io, &.{"blocked-action"}, stdout, stderr)
    else if (std.mem.eql(u8, action, "license-status"))
        try license_cmd.command(io, &.{"status"}, stdout, stderr)
    else
        return error.UnsupportedDashboardAction;

    return .{
        .exit_code = code,
        .stdout = try stdout_aw.toOwnedSlice(),
        .stderr = try stderr_aw.toOwnedSlice(),
    };
}

fn proxySmokeAction(io: std.Io, allocator: std.mem.Allocator, stdout: anytype, _: anytype) !u8 {
    var loaded = try core_policy.load.parseFromSlice(allocator,
        \\version: 1
        \\mode: observe
        \\network:
        \\  mode: open
        \\  backend: proxy
    , "dashboard-proxy-smoke.yaml");
    defer loaded.deinit();

    const upstream_address = try std.Io.net.IpAddress.parse("127.0.0.1", 0);
    var upstream = try upstream_address.listen(io, .{ .reuse_address = true });
    defer upstream.deinit(io);
    const upstream_port = upstream.socket.address.getPort();
    var upstream_state: ProxySmokeServerState = .{ .server = &upstream, .io = io };
    const upstream_thread = try std.Thread.spawn(.{}, proxySmokeServer, .{&upstream_state});
    defer upstream_thread.join();
    std.Io.sleep(io, std.Io.Duration.fromNanoseconds(50 * std.time.ns_per_ms), .awake) catch {};

    var runtime = try intercept.proxy.start(allocator, &loaded, .observe);
    std.Io.sleep(io, std.Io.Duration.fromNanoseconds(50 * std.time.ns_per_ms), .awake) catch {};
    defer runtime.deinit();
    const proxy_port = try parseBindPort(runtime.bindUrl());
    const proxy_addr = try std.Io.net.IpAddress.parse("127.0.0.1", proxy_port);
    var client = try std.Io.net.IpAddress.connect(&proxy_addr, io, .{ .mode = .stream });
    defer client.close(io);

    var request_buf: [256]u8 = undefined;
    const request = try std.fmt.bufPrint(
        &request_buf,
        "GET http://127.0.0.1:{d}/proxy-smoke HTTP/1.1\r\nHost: 127.0.0.1:{d}\r\nConnection: close\r\n\r\n",
        .{ upstream_port, upstream_port },
    );
    var client_write_buf: [512]u8 = undefined;
    var client_writer = client.writer(io, &client_write_buf);
    try client_writer.interface.writeAll(request);
    try client_writer.interface.flush();
    var response_buf: [1024]u8 = undefined;
    const response_len = try readHttpResponse(io, client, &response_buf);
    if (std.mem.indexOf(u8, response_buf[0..response_len], "proxy-smoke-ok") == null) return exit_codes.general;

    try runtime.waitForIdle(std.time.ns_per_s);
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
    server: *std.Io.net.Server,
    io: std.Io,
};

fn proxySmokeServer(state: *ProxySmokeServerState) void {
    var listen_fd = [_]std.posix.pollfd{.{
        .fd = state.server.socket.handle,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};
    _ = std.posix.poll(&listen_fd, 5_000) catch return;
    var stream = state.server.accept(state.io) catch return;
    defer stream.close(state.io);
    var request_buf: [512]u8 = undefined;
    _ = readAvailableHttpRequest(state.io, stream, &request_buf) catch return;
    const body = "proxy-smoke-ok";
    var response_buf: [160]u8 = undefined;
    const response = std.fmt.bufPrint(&response_buf, "HTTP/1.1 200 OK\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ body.len, body }) catch return;
    var write_buf: [256]u8 = undefined;
    var writer = stream.writer(state.io, &write_buf);
    writer.interface.writeAll(response) catch {};
    writer.interface.flush() catch {};
}

fn readAvailableHttpRequest(io: std.Io, stream: std.Io.net.Stream, buffer: []u8) !usize {
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

fn parseBindPort(bind_url: []const u8) !u16 {
    const colon = std.mem.lastIndexOfScalar(u8, bind_url, ':') orelse return error.InvalidBindUrl;
    return std.fmt.parseInt(u16, bind_url[colon + 1 ..], 10);
}

fn sendText(io: std.Io, stream: std.Io.net.Stream, status_code: u16, reason: []const u8, content_type: []const u8, body: []const u8) !void {
    var header_buf: [512]u8 = undefined;
    const header = try std.fmt.bufPrint(
        &header_buf,
        "HTTP/1.1 {d} {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n",
        .{ status_code, reason, content_type, body.len },
    );
    var buf: [1024]u8 = undefined;
    var writer = stream.writer(io, &buf);
    try writer.interface.writeAll(header);
    try writer.interface.writeAll(body);
    try writer.interface.flush();
}

fn sendJsonError(io: std.Io, stream: std.Io.net.Stream, status_code: u16, reason: []const u8, message: []const u8) !void {
    var body_buf: [128]u8 = undefined;
    const body = try std.fmt.bufPrint(&body_buf, "{{\"error\":\"{s}\"}}\n", .{message});
    try sendText(io, stream, status_code, reason, "application/json; charset=utf-8", body);
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
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try commandForTest(&.{ "--host", "0.0.0.0" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.usage, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "localhost") != null);
}

test "dashboard action allowlist rejects arbitrary browser commands" {
    try std.testing.expectError(error.UnsupportedDashboardAction, runAllowedAction(std.testing.io, std.testing.allocator, "rm -rf /"));
}

test "dashboard proxy-smoke action verifies local proxy forwarding" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;

    const result = try runAllowedAction(std.testing.io, std.testing.allocator, "proxy-smoke");
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
