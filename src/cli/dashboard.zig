const std = @import("std");
const builtin = @import("builtin");

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
const daemon = @import("daemon.zig");
const exit_codes = @import("exit_codes.zig");
const feed_writer = @import("feed_writer.zig");
const help = @import("help.zig");
const core = @import("orca_core").core;
const core_api = @import("orca_core").api;
const core_policy = @import("orca_core").policy;
const intercept = @import("../intercept/mod.zig");

const default_host = "127.0.0.1";
const default_port: u16 = 7742;
const canonical_ui_dir = "src/dashboard/assets";
const installed_ui_dir = "orca-dashboard-ui/dist";
const dashboard_ui_missing_html =
    \\<!doctype html>
    \\<html lang="en">
    \\<head><meta charset="utf-8"><title>Orca Dashboard</title></head>
    \\<body>
    \\<h1>Dashboard UI not installed</h1>
    \\<p>The Orca install on this machine is missing <code>orca-dashboard-ui/dist</code> under <code>ORCA_RESOURCE_ROOT</code>.</p>
    \\<p>Reinstall from a current release artifact or export <code>ORCA_RESOURCE_ROOT</code> to a checkout that contains the dashboard bundle.</p>
    \\</body>
    \\</html>
;

fn dashboardWorkspaceSelection(
    explicit_workspace: ?[]const u8,
    explicit_machine: bool,
    environment_workspace: ?[]const u8,
) ?[]const u8 {
    if (explicit_workspace) |workspace| return workspace;
    if (explicit_machine) return null;
    return environment_workspace;
}

fn actionAllowedWithoutWorkspace(action: []const u8) bool {
    return std.mem.eql(u8, action, "doctor") or
        std.mem.eql(u8, action, "license-status") or
        // Plugin doctor is host-global (not workspace policy) and safe in machine mode.
        std.mem.eql(u8, action, "openclaw-doctor") or
        std.mem.eql(u8, action, "hermes-doctor");
}

const DashboardOptions = struct {
    host: []const u8 = default_host,
    port: u16 = default_port,
    once: bool = false,
    workspace: ?[]const u8 = null,
};

const DashboardContext = struct {
    workspace_root: ?[]const u8,
    dashboard_root: ?[]const u8,
};

const Request = struct {
    method: []const u8,
    path: []const u8,
    body: []const u8,
    csrf_token: ?[]const u8,
    host: ?[]const u8,
    origin: ?[]const u8,
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
    var explicit_workspace: ?[]const u8 = null;
    var explicit_machine = false;
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
        } else if (std.mem.eql(u8, arg, "--workspace")) {
            index += 1;
            if (index >= argv.len or argv[index].len == 0) {
                try stderr.writeAll("orca dashboard: --workspace requires a path.\n");
                return error.Usage;
            }
            explicit_workspace = argv[index];
        } else if (std.mem.eql(u8, arg, "--machine")) {
            explicit_machine = true;
        } else {
            const suggestions = @import("suggestions.zig");
            suggestions.writeUnknownOption(
                stderr,
                "orca dashboard",
                arg,
                &.{ "--host", "--port", "--once", "--workspace", "--machine", "--help" },
                "dashboard",
            ) catch {};
            return error.Usage;
        }
    }
    if (explicit_workspace != null and explicit_machine) {
        try stderr.writeAll("orca dashboard: --workspace and --machine cannot be used together.\n");
        return error.Usage;
    }
    const environment_workspace = if (std.c.getenv("ORCA_DASHBOARD_WORKSPACE")) |value| blk: {
        const path = std.mem.span(value);
        break :blk if (path.len == 0) null else path;
    } else null;
    options.workspace = dashboardWorkspaceSelection(explicit_workspace, explicit_machine, environment_workspace);
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
    const mode_label: []const u8 = if (options.workspace != null) "workspace" else "machine";
    try stdout.print("Orca dashboard listening at http://{s}:{d} ({s} mode)\n", .{ options.host, options.port, mode_label });
    try flushIfSupported(stdout);

    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    const csrf_token = try makeCsrfToken(io, allocator);
    defer allocator.free(csrf_token);
    const workspace_root = if (options.workspace) |path|
        try dashboard.resolveWorkspaceRootFrom(io, allocator, path)
    else
        null;
    defer if (workspace_root) |root| allocator.free(root);
    const dashboard_root = if (workspace_root == null)
        try feed_writer.resolveGlobalDashboardRoot(allocator)
    else
        null;
    defer if (dashboard_root) |root| allocator.free(root);
    const context = DashboardContext{
        .workspace_root = workspace_root,
        .dashboard_root = dashboard_root,
    };

    while (true) {
        var stream = server.accept(io) catch |err| {
            try stderr.print("orca dashboard: accept failed: {s}\n", .{@errorName(err)});
            continue;
        };
        defer stream.close(io);
        handleConnection(io, allocator, stream, csrf_token, context) catch |err| {
            try stderr.print("orca dashboard: request failed: {s}\n", .{@errorName(err)});
            if (isFatalRequestError(err)) return err;
        };
        if (options.once) break;
    }
    return exit_codes.success;
}

fn isFatalRequestError(err: anyerror) bool {
    return err == error.WorkspaceCwdRestoreFailed;
}

fn resolveDashboardDistDirTrusted(io: std.Io, allocator: std.mem.Allocator) ![]u8 {
    return resolveDashboardDistDirTrustedFrom(io, allocator, null);
}

fn resolveDashboardDistDirTrustedFrom(
    io: std.Io,
    allocator: std.mem.Allocator,
    resource_root_override: ?[]const u8,
) ![]u8 {
    for ([_][]const u8{ installed_ui_dir, canonical_ui_dir }) |relative_path| {
        const resolved = resource_root.resolveResourcePath(io, allocator, .{
            // Dashboard code must never be selected from the current workspace.
            .workspace_root = "/__orca_dashboard_workspace_assets_disabled__",
            .resource_root_override = resource_root_override,
        }, relative_path) catch continue;
        const index_path = std.fs.path.join(allocator, &.{ resolved, "index.html" }) catch |err| {
            allocator.free(resolved);
            return err;
        };
        defer allocator.free(index_path);
        std.Io.Dir.cwd().access(io, index_path, .{}) catch {
            allocator.free(resolved);
            continue;
        };
        return resolved;
    }
    return error.ResourceNotFound;
}

fn handleConnection(
    io: std.Io,
    allocator: std.mem.Allocator,
    stream: std.Io.net.Stream,
    csrf_token: []const u8,
    context: DashboardContext,
) !void {
    var request_buffer: std.ArrayList(u8) = .empty;
    defer request_buffer.deinit(allocator);
    try readRequest(io, allocator, stream, &request_buffer);
    const request = parseRequest(request_buffer.items) catch {
        try sendText(io, stream, 400, "Bad Request", "text/plain; charset=utf-8", "bad request\n");
        return;
    };
    if (!requestSourceAllowed(request)) {
        try sendJsonError(io, stream, 403, "Forbidden", "request_source");
        return;
    }

    const dist_dir = resolveDashboardDistDirTrusted(io, allocator) catch |err| switch (err) {
        error.ResourceNotFound => {
            if (std.mem.eql(u8, request.method, "GET") and !std.mem.startsWith(u8, request.path, "/api/")) {
                return sendText(io, stream, 503, "Service Unavailable", "text/html; charset=utf-8", dashboard_ui_missing_html);
            }
            return sendJsonError(io, stream, 503, "Service Unavailable", "dashboard_ui_missing");
        },
        else => return err,
    };
    defer allocator.free(dist_dir);
    var body_aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer body_aw.deinit();
    const writer = &body_aw.writer;

    if (std.mem.eql(u8, request.method, "GET") and !std.mem.startsWith(u8, request.path, "/api/")) {
        try serveStaticFile(io, allocator, stream, request.path, csrf_token, dist_dir);
        return;
    }
    if (std.mem.eql(u8, request.method, "GET") and std.mem.eql(u8, request.path, "/api/status")) {
        if (context.workspace_root) |workspace_root|
            try dashboard.writeStatusJson(io, allocator, writer, workspace_root)
        else
            try dashboard.writeMachineStatusJson(io, allocator, writer, context.dashboard_root.?);
        try body_aw.writer.flush();
        const response_body = try body_aw.toOwnedSlice();
        defer allocator.free(response_body);
        try sendText(io, stream, 200, "OK", "application/json; charset=utf-8", response_body);
        return;
    }
    if (std.mem.eql(u8, request.method, "GET") and std.mem.eql(u8, request.path, "/api/policy")) {
        const workspace_root = context.workspace_root orelse return sendJsonError(io, stream, 409, "Conflict", "workspace_required");
        try dashboard.writePolicyJson(io, allocator, writer, workspace_root);
        try body_aw.writer.flush();
        const response_body = try body_aw.toOwnedSlice();
        defer allocator.free(response_body);
        try sendText(io, stream, 200, "OK", "application/json; charset=utf-8", response_body);
        return;
    }
    if (std.mem.eql(u8, request.method, "GET") and std.mem.eql(u8, request.path, "/api/sessions")) {
        if (context.workspace_root) |workspace_root|
            try dashboard.writeSessionsJson(io, allocator, writer, workspace_root)
        else
            try dashboard.writeMachineSessionsJson(io, allocator, writer, context.dashboard_root.?);
        try body_aw.writer.flush();
        const response_body = try body_aw.toOwnedSlice();
        defer allocator.free(response_body);
        try sendText(io, stream, 200, "OK", "application/json; charset=utf-8", response_body);
        return;
    }
    if (std.mem.eql(u8, request.method, "POST") and std.mem.eql(u8, request.path, "/api/policy")) {
        if (!tokenMatches(request.csrf_token, csrf_token)) return sendJsonError(io, stream, 403, "Forbidden", "csrf");
        const workspace_root = context.workspace_root orelse return sendJsonError(io, stream, 409, "Conflict", "workspace_required");
        try handlePolicySave(io, allocator, writer, workspace_root, request.body);
        try body_aw.writer.flush();
        const response_body = try body_aw.toOwnedSlice();
        defer allocator.free(response_body);
        try sendText(io, stream, 200, "OK", "application/json; charset=utf-8", response_body);
        return;
    }
    if (std.mem.eql(u8, request.method, "POST") and std.mem.eql(u8, request.path, "/api/policy/init")) {
        if (!tokenMatches(request.csrf_token, csrf_token)) return sendJsonError(io, stream, 403, "Forbidden", "csrf");
        const workspace_root = context.workspace_root orelse return sendJsonError(io, stream, 409, "Conflict", "workspace_required");
        try handlePolicyInit(io, allocator, writer, workspace_root, request.body);
        try body_aw.writer.flush();
        const response_body = try body_aw.toOwnedSlice();
        defer allocator.free(response_body);
        try sendText(io, stream, 200, "OK", "application/json; charset=utf-8", response_body);
        return;
    }
    if (std.mem.eql(u8, request.method, "POST") and std.mem.eql(u8, request.path, "/api/actions")) {
        if (!tokenMatches(request.csrf_token, csrf_token)) return sendJsonError(io, stream, 403, "Forbidden", "csrf");
        handleAction(io, allocator, writer, request.body, context.workspace_root) catch |err| switch (err) {
            error.WorkspaceRequired => return sendJsonError(io, stream, 409, "Conflict", "workspace_required"),
            else => return err,
        };
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
    if (!isSafeStaticPath(rel_path)) return sendJsonError(io, stream, 404, "Not Found", "not_found");

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
        var reader_storage: [8192]u8 = undefined;
        var file_reader = file.reader(io, &reader_storage);
        var chunk: [8192]u8 = undefined;
        while (raw_list.items.len < size) {
            const n = try file_reader.interface.readSliceShort(chunk[0..@min(chunk.len, size - raw_list.items.len)]);
            if (n == 0) break;
            try raw_list.appendSlice(allocator, chunk[0..n]);
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
        "HTTP/1.1 200 OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nCache-Control: public, max-age=3600\r\nX-Content-Type-Options: nosniff\r\nX-Frame-Options: DENY\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; connect-src 'self'; object-src 'none'; frame-ancestors 'none'; base-uri 'none'\r\nConnection: close\r\n\r\n",
        .{ content_type, size },
    );
    var stream_buf: [8192]u8 = undefined;
    var stream_writer = stream.writer(io, &stream_buf);
    try stream_writer.interface.writeAll(header);
    try stream_writer.interface.flush();

    var reader_storage: [8192]u8 = undefined;
    var file_reader = file.reader(io, &reader_storage);
    var chunk: [8192]u8 = undefined;
    var remaining = size;
    while (remaining > 0) {
        const to_read = @min(chunk.len, remaining);
        const n = try file_reader.interface.readSliceShort(chunk[0..to_read]);
        if (n == 0) break;
        try stream_writer.interface.writeAll(chunk[0..n]);
        remaining -= n;
    }
    try stream_writer.interface.flush();
}

fn readRequest(io: std.Io, allocator: std.mem.Allocator, stream: std.Io.net.Stream, buffer: *std.ArrayList(u8)) !void {
    if (builtin.os.tag == .windows) {
        var reader_storage: [8192]u8 = undefined;
        var reader = stream.reader(io, &reader_storage);
        var chunk: [8192]u8 = undefined;
        while (buffer.items.len < dashboard.max_request_body_len + 8192) {
            const n = try reader.interface.readSliceShort(&chunk);
            if (n == 0) break;
            try buffer.appendSlice(allocator, chunk[0..n]);
            if (requestComplete(buffer.items)) break;
        }
        return;
    }

    var chunk: [8192]u8 = undefined;
    const started = std.Io.Clock.Timestamp.now(io, .awake);
    const deadline_ns: i96 = 5 * std.time.ns_per_s;
    while (buffer.items.len < dashboard.max_request_body_len + 8192 and started.durationFromNow(io).raw.nanoseconds < deadline_ns) {
        var fds = [_]std.posix.pollfd{.{
            .fd = stream.socket.handle,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};
        const ready = std.posix.poll(&fds, 100) catch break;
        if (ready == 0) continue;
        const n = std.posix.read(stream.socket.handle, chunk[0..]) catch |err| switch (err) {
            error.WouldBlock => continue,
            else => return err,
        };
        if (n == 0) break;
        try buffer.appendSlice(allocator, chunk[0..n]);
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
        .host = headerValue(headers, "host"),
        .origin = headerValue(headers, "origin"),
    };
}

fn isSafeStaticPath(path: []const u8) bool {
    if (path.len == 0 or std.fs.path.isAbsolute(path)) return false;
    for (path) |byte| {
        if (byte == '\\' or byte == 0 or byte < 0x20) return false;
    }
    var segments = std.mem.splitScalar(u8, path, '/');
    while (segments.next()) |segment| {
        if (segment.len == 0 or std.mem.eql(u8, segment, ".") or std.mem.eql(u8, segment, "..")) return false;
        if (std.ascii.eqlIgnoreCase(segment, "%2e") or std.ascii.eqlIgnoreCase(segment, "%2e%2e")) return false;
        if (std.mem.indexOfScalar(u8, segment, ':') != null) return false;
    }
    return true;
}

fn loopbackAuthority(value: []const u8) bool {
    const authority = if (std.mem.startsWith(u8, value, "http://"))
        value["http://".len..]
    else if (std.mem.startsWith(u8, value, "https://"))
        value["https://".len..]
    else
        value;
    const host_port = authority[0 .. std.mem.indexOfScalar(u8, authority, '/') orelse authority.len];
    const host = host_port[0 .. std.mem.indexOfScalar(u8, host_port, ':') orelse host_port.len];
    return std.ascii.eqlIgnoreCase(host, "localhost") or std.mem.eql(u8, host, "127.0.0.1");
}

fn requestSourceAllowed(request: Request) bool {
    const host = request.host orelse return false;
    if (!loopbackAuthority(host)) return false;
    if (request.origin) |origin| return loopbackAuthority(origin);
    return true;
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

fn handleAction(io: std.Io, allocator: std.mem.Allocator, writer: anytype, body: []const u8, workspace_root: ?[]const u8) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    const object = if (parsed.value == .object) parsed.value.object else return error.BadRequest;
    const action_value = object.get("action") orelse return error.BadRequest;
    if (action_value != .string) return error.BadRequest;
    const result = try runAllowedAction(io, allocator, action_value.string, workspace_root);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    try writeCapturedActionJson(allocator, writer, result);
}

fn writeCapturedActionJson(allocator: std.mem.Allocator, writer: anytype, result: CapturedAction) !void {
    const safe_stdout = try core_api.redactAlloc(allocator, result.stdout);
    defer allocator.free(safe_stdout);
    const safe_stderr = try core_api.redactAlloc(allocator, result.stderr);
    defer allocator.free(safe_stderr);
    try writer.print("{{\"ok\":{},\"exit_code\":{d},\"stdout\":", .{ result.exit_code == exit_codes.success, result.exit_code });
    try core.util.writeJsonString(writer, safe_stdout);
    try writer.writeAll(",\"stderr\":");
    try core.util.writeJsonString(writer, safe_stderr);
    try writer.writeByte('}');
}

const CapturedAction = struct {
    exit_code: u8,
    stdout: []u8,
    stderr: []u8,
};

/// Commands that still resolve workspace from the process cwd (no path/Dir API yet).
/// Prefer absolute paths or open Dir handles for new dashboard actions.
fn actionNeedsWorkspaceCwd(action: []const u8) bool {
    return std.mem.eql(u8, action, "doctor") or
        std.mem.eql(u8, action, "credentials-check") or
        std.mem.eql(u8, action, "credentials-check-github") or
        std.mem.eql(u8, action, "policy-explain-github") or
        std.mem.eql(u8, action, "replay-last") or
        std.mem.eql(u8, action, "replay-denied") or
        std.mem.eql(u8, action, "report-last") or
        std.mem.eql(u8, action, "ci-check") or
        std.mem.eql(u8, action, "demo-blocked-action");
}

/// Scoped process cwd change for legacy CLI entrypoints. Restore failures are hard errors
/// so a subsequent dashboard request never inherits a foreign workspace.
const WorkspaceCwdGuard = struct {
    /// Owned path of the process cwd before enter(); not null-terminated.
    original: ?[]u8,
    allocator: std.mem.Allocator,

    fn enter(io: std.Io, allocator: std.mem.Allocator, workspace_root: []const u8) !WorkspaceCwdGuard {
        const original = try std.Io.Dir.cwd().realPathFileAlloc(io, ".", allocator);
        errdefer allocator.free(original);
        try std.Io.Threaded.chdir(workspace_root);
        return .{ .original = original, .allocator = allocator };
    }

    fn leave(self: *WorkspaceCwdGuard) !void {
        const original = self.original orelse return;
        self.original = null;
        defer self.allocator.free(original);
        std.Io.Threaded.chdir(original) catch return error.WorkspaceCwdRestoreFailed;
    }
};

fn runAllowedAction(io: std.Io, allocator: std.mem.Allocator, action: []const u8, workspace_root: ?[]const u8) !CapturedAction {
    if (workspace_root == null and !actionAllowedWithoutWorkspace(action)) return error.WorkspaceRequired;

    var stdout_aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer stdout_aw.deinit();
    var stderr_aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer stderr_aw.deinit();
    const stdout = &stdout_aw.writer;
    const stderr = &stderr_aw.writer;

    // Daemon-proxied remediation: trusted cwd rides on ExecuteCli — never touch process cwd.
    if (dashboardDaemonActionArgv(action)) |argv| {
        const code = try runDaemonProxyAction(allocator, argv, workspace_root.?, stdout, stderr);
        return .{
            .exit_code = code,
            .stdout = try stdout_aw.toOwnedSlice(),
            .stderr = try stderr_aw.toOwnedSlice(),
        };
    }

    // Init accepts an open Dir; no process chdir required.
    if (std.mem.eql(u8, action, "init-generic-agent")) {
        var workspace_dir = try std.Io.Dir.cwd().openDir(io, workspace_root.?, .{});
        defer workspace_dir.close(io);
        const code = try init.command(io, workspace_dir, &.{ "--preset", "generic-agent" }, stdout, stderr);
        return .{
            .exit_code = code,
            .stdout = try stdout_aw.toOwnedSlice(),
            .stderr = try stderr_aw.toOwnedSlice(),
        };
    }

    // Policy check can use an absolute policy path without changing process cwd.
    if (std.mem.eql(u8, action, "policy-check")) {
        const policy_path = try std.fs.path.join(allocator, &.{ workspace_root.?, ".orca", "policy.yaml" });
        defer allocator.free(policy_path);
        const code = try policy.command(io, &.{ "check", policy_path }, stdout, stderr);
        return .{
            .exit_code = code,
            .stdout = try stdout_aw.toOwnedSlice(),
            .stderr = try stderr_aw.toOwnedSlice(),
        };
    }

    var cwd_guard: ?WorkspaceCwdGuard = null;
    if (workspace_root != null and actionNeedsWorkspaceCwd(action)) {
        cwd_guard = try WorkspaceCwdGuard.enter(io, allocator, workspace_root.?);
    }

    const code = (if (std.mem.eql(u8, action, "doctor"))
        doctor.command(io, &.{}, stdout, stderr)
    else if (std.mem.eql(u8, action, "credentials-check"))
        credentials_cmd.command(io, &.{"check"}, stdout, stderr)
    else if (std.mem.eql(u8, action, "credentials-check-github"))
        credentials_cmd.command(io, &.{ "check", "github_pat" }, stdout, stderr)
    else if (std.mem.eql(u8, action, "proxy-smoke"))
        proxySmokeAction(io, allocator, stdout, stderr)
    else if (std.mem.eql(u8, action, "policy-explain-github"))
        policy.command(io, &.{ "explain", "network", "https://api.github.com/repos/acme/app/issues", "--method", "POST" }, stdout, stderr)
    else if (std.mem.eql(u8, action, "replay-last"))
        replay.command(io, &.{ "--session", "last", "--verify" }, stdout, stderr)
    else if (std.mem.eql(u8, action, "openclaw-doctor"))
        plugin.command(io, &.{ "doctor", "openclaw" }, stdout, stderr)
    else if (std.mem.eql(u8, action, "hermes-doctor"))
        plugin.command(io, &.{ "doctor", "hermes" }, stdout, stderr)
    else if (std.mem.eql(u8, action, "replay-denied"))
        replay.command(io, &.{ "--session", "last", "--only", "denied", "--verify" }, stdout, stderr)
    else if (std.mem.eql(u8, action, "report-last"))
        report_cmd.command(io, &.{ "--session", "last", "--format", "markdown" }, stdout, stderr)
    else if (std.mem.eql(u8, action, "ci-check"))
        ci_cmd.command(io, &.{ "check", "--format", "markdown" }, stdout, stderr)
    else if (std.mem.eql(u8, action, "demo-blocked-action"))
        demo_cmd.command(io, &.{"blocked-action"}, stdout, stderr)
    else if (std.mem.eql(u8, action, "license-status"))
        license_cmd.command(io, &.{"status"}, stdout, stderr)
    else
        return error.UnsupportedDashboardAction) catch |err| {
        if (cwd_guard) |*guard| try guard.leave();
        return err;
    };

    if (cwd_guard) |*guard| {
        try guard.leave();
    }

    return .{
        .exit_code = code,
        .stdout = try stdout_aw.toOwnedSlice(),
        .stderr = try stderr_aw.toOwnedSlice(),
    };
}

fn dashboardDaemonActionArgv(action: []const u8) ?[]const []const u8 {
    if (std.mem.eql(u8, action, "suggest-allowlist")) return &.{ "suggest-allowlist", "--confidence", "high", "--non-interactive" };
    if (std.mem.eql(u8, action, "allowlist-list")) return &.{ "allowlist", "list" };
    return null;
}

/// Fixed argv proxy for allowlisted dashboard remediation actions (no browser-supplied args).
fn runDaemonProxyAction(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    workspace_root: []const u8,
    stdout: anytype,
    stderr: anytype,
) !u8 {
    var parsed = daemon.executeCliAt(allocator, argv, workspace_root) catch |err| {
        try stderr.print("orca dashboard: daemon proxy failed ({s})\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer parsed.deinit();

    if (daemon.responseStatus(parsed.value.result) == .error_status) {
        if (daemon.responseErrorMessage(parsed.value.result)) |message| {
            try stderr.print("orca daemon: {s}\n", .{message});
        } else {
            try stderr.writeAll("orca daemon: protocol error\n");
        }
        return exit_codes.general;
    }

    const execution = daemon.parseCliExecution(parsed.value.result) catch {
        try stderr.writeAll("orca dashboard: malformed daemon CLI response\n");
        return exit_codes.general;
    };
    try stdout.writeAll(execution.stdout);
    if (execution.stderr.len > 0) try stderr.writeAll(execution.stderr);
    return execution.exit_code;
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
        "HTTP/1.1 {d} {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nX-Frame-Options: DENY\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; connect-src 'self'; object-src 'none'; frame-ancestors 'none'; base-uri 'none'\r\nConnection: close\r\n\r\n",
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

test "dashboard mode defaults to machine and honors workspace sources" {
    try std.testing.expect(dashboardWorkspaceSelection(null, false, null) == null);
    try std.testing.expect(dashboardWorkspaceSelection(null, true, null) == null);
    try std.testing.expectEqualStrings("/tmp/flag", dashboardWorkspaceSelection("/tmp/flag", false, null).?);
    try std.testing.expectEqualStrings("/tmp/env", dashboardWorkspaceSelection(null, false, "/tmp/env").?);
}

test "dashboard ignores workspace assets and accepts explicit trusted resource root" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "src/dashboard/assets");
    try tmp.dir.createDirPath(std.testing.io, "orca-dashboard-ui/dist");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "src/dashboard/assets/index.html", .data = "legacy" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "orca-dashboard-ui/dist/index.html", .data = "polished" });
    try tmp.dir.createDirPath(std.testing.io, "trusted/orca-dashboard-ui/dist");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "trusted/orca-dashboard-ui/dist/index.html", .data = "trusted" });
    const trusted_root = try tmp.dir.realPathFileAlloc(std.testing.io, "trusted", std.testing.allocator);
    defer std.testing.allocator.free(trusted_root);

    const resolved = try resolveDashboardDistDirTrustedFrom(std.testing.io, std.testing.allocator, trusted_root);
    defer std.testing.allocator.free(resolved);
    try std.testing.expect(std.mem.startsWith(u8, resolved, trusted_root));
    try std.testing.expect(std.mem.endsWith(u8, resolved, installed_ui_dir));
}

test "dashboard parses machine and workspace flags" {
    var stdout_buf: [256]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout: std.Io.Writer = .fixed(&stdout_buf);
    var stderr: std.Io.Writer = .fixed(&stderr_buf);
    const workspace = try parseOptions(std.testing.io, &.{ "--workspace", "/tmp/project" }, &stdout, &stderr);
    try std.testing.expectEqualStrings("/tmp/project", workspace.workspace.?);
    const machine = try parseOptions(std.testing.io, &.{"--machine"}, &stdout, &stderr);
    try std.testing.expect(machine.workspace == null);
    try std.testing.expectError(error.Usage, parseOptions(std.testing.io, &.{ "--workspace", "/tmp/project", "--machine" }, &stdout, &stderr));
}

test "machine dashboard actions exclude workspace-scoped commands" {
    try std.testing.expect(actionAllowedWithoutWorkspace("doctor"));
    try std.testing.expect(actionAllowedWithoutWorkspace("license-status"));
    try std.testing.expect(actionAllowedWithoutWorkspace("openclaw-doctor"));
    try std.testing.expect(actionAllowedWithoutWorkspace("hermes-doctor"));
    try std.testing.expect(!actionAllowedWithoutWorkspace("replay-last"));
    try std.testing.expect(!actionAllowedWithoutWorkspace("report-last"));
    try std.testing.expect(!actionAllowedWithoutWorkspace("demo-blocked-action"));
    try std.testing.expectError(error.WorkspaceRequired, runAllowedAction(std.testing.io, std.testing.allocator, "replay-last", null));
}

test "dashboard action allowlist rejects arbitrary browser commands" {
    try std.testing.expectError(error.UnsupportedDashboardAction, runAllowedAction(std.testing.io, std.testing.allocator, "rm -rf /", "."));
    try std.testing.expectError(error.UnsupportedDashboardAction, runAllowedAction(std.testing.io, std.testing.allocator, "allowlist add evil", "."));
    try std.testing.expectError(error.UnsupportedDashboardAction, runAllowedAction(std.testing.io, std.testing.allocator, "shell-anything", "."));
}

test "dashboard remediation actions are registered on the allowlist" {
    // Workspace required: these proxy daemon CLI and mutate/read workspace history.
    try std.testing.expect(!actionAllowedWithoutWorkspace("suggest-allowlist"));
    try std.testing.expect(!actionAllowedWithoutWorkspace("allowlist-list"));
    try std.testing.expectError(error.WorkspaceRequired, runAllowedAction(std.testing.io, std.testing.allocator, "suggest-allowlist", null));
    try std.testing.expectError(error.WorkspaceRequired, runAllowedAction(std.testing.io, std.testing.allocator, "allowlist-list", null));
}

test "dashboard remediation action argv is fixed and non-interactive" {
    try std.testing.expectEqualSlices([]const u8, &.{ "suggest-allowlist", "--confidence", "high", "--non-interactive" }, dashboardDaemonActionArgv("suggest-allowlist").?);
    try std.testing.expectEqualSlices([]const u8, &.{ "allowlist", "list" }, dashboardDaemonActionArgv("allowlist-list").?);
    try std.testing.expect(dashboardDaemonActionArgv("allowlist add browser-controlled") == null);
}

test "dashboard action JSON redacts captured stdout and stderr" {
    const sentinel = "sk-dashboardSyntheticSecretSentinel123456789";
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writeCapturedActionJson(std.testing.allocator, &aw.writer, .{
        .exit_code = exit_codes.general,
        .stdout = @constCast("suggestion token=sk-dashboardSyntheticSecretSentinel123456789\n"),
        .stderr = @constCast("Authorization: Bearer sk-dashboardSyntheticSecretSentinel123456789\n"),
    });
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), sentinel) == null);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "[REDACTED]") != null);
}

test "workspace dashboard actions run in the selected canonical workspace" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const selected = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(selected);

    const previous_cwd = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(previous_cwd);

    const result = try runAllowedAction(std.testing.io, std.testing.allocator, "init-generic-agent", selected);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try std.testing.expectEqual(exit_codes.success, result.exit_code);
    const policy_path = try std.fs.path.join(std.testing.allocator, &.{ selected, ".orca", "policy.yaml" });
    defer std.testing.allocator.free(policy_path);
    try std.Io.Dir.cwd().access(std.testing.io, policy_path, .{});

    // init must not leave the process cwd on the selected workspace.
    const after_cwd = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(after_cwd);
    try std.testing.expectEqualStrings(previous_cwd, after_cwd);
}

test "dashboard action workspace cwd classification matches remediation surface" {
    try std.testing.expect(actionNeedsWorkspaceCwd("doctor"));
    try std.testing.expect(!actionNeedsWorkspaceCwd("license-status"));
    try std.testing.expect(!actionNeedsWorkspaceCwd("init-generic-agent"));
    try std.testing.expect(!actionNeedsWorkspaceCwd("policy-check"));
    try std.testing.expect(!actionNeedsWorkspaceCwd("suggest-allowlist"));
    try std.testing.expect(actionNeedsWorkspaceCwd("replay-last"));
    try std.testing.expect(actionNeedsWorkspaceCwd("ci-check"));
    try std.testing.expect(actionNeedsWorkspaceCwd("demo-blocked-action"));
}

test "workspace dashboard doctor inspects the selected workspace" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(std.testing.io, ".orca", .default_dir);
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = ".orca/policy.yaml",
        .data = "version: 1\nmode: definitely-invalid\n",
    });
    const selected = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(selected);
    const previous_cwd = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(previous_cwd);

    const result = try runAllowedAction(std.testing.io, std.testing.allocator, "doctor", selected);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "policy invalid") != null);

    const after_cwd = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(after_cwd);
    try std.testing.expectEqualStrings(previous_cwd, after_cwd);
}

test "workspace cwd restore failure is fatal to the dashboard server" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(std.testing.io, "original", .default_dir);
    try tmp.dir.createDir(std.testing.io, "selected", .default_dir);
    const original = try tmp.dir.realPathFileAlloc(std.testing.io, "original", std.testing.allocator);
    defer std.testing.allocator.free(original);
    const selected = try tmp.dir.realPathFileAlloc(std.testing.io, "selected", std.testing.allocator);
    defer std.testing.allocator.free(selected);
    const base = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(base);
    const moved = try std.fs.path.join(std.testing.allocator, &.{ base, "original-moved" });
    defer std.testing.allocator.free(moved);
    const actual_cwd = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(actual_cwd);
    defer std.Io.Threaded.chdir(actual_cwd) catch @panic("test failed to restore process cwd");

    try std.Io.Threaded.chdir(original);
    var guard = try WorkspaceCwdGuard.enter(std.testing.io, std.testing.allocator, selected);
    try std.Io.Dir.renameAbsolute(original, moved, std.testing.io);
    try std.testing.expectError(error.WorkspaceCwdRestoreFailed, guard.leave());
    try std.testing.expect(isFatalRequestError(error.WorkspaceCwdRestoreFailed));
}

test "dashboard proxy-smoke action verifies local proxy forwarding" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;

    const result = try runAllowedAction(std.testing.io, std.testing.allocator, "proxy-smoke", ".");
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
    try std.testing.expectEqualStrings("127.0.0.1", request.host.?);
}

test "dashboard static paths reject traversal and platform escapes" {
    try std.testing.expect(isSafeStaticPath("index.html"));
    try std.testing.expect(isSafeStaticPath("_next/static/app.js"));
    try std.testing.expect(!isSafeStaticPath("../../README.md"));
    try std.testing.expect(!isSafeStaticPath("%2e%2e/README.md"));
    try std.testing.expect(!isSafeStaticPath("C:/Windows/win.ini"));
    try std.testing.expect(!isSafeStaticPath("..\\..\\.ssh\\id_rsa"));
}

test "dashboard request source accepts loopback and rejects rebinding origins" {
    const local = Request{ .method = "GET", .path = "/", .body = "", .csrf_token = null, .host = "127.0.0.1:7742", .origin = null };
    try std.testing.expect(requestSourceAllowed(local));
    const local_origin = Request{ .method = "POST", .path = "/api/actions", .body = "", .csrf_token = "x", .host = "localhost:7742", .origin = "http://localhost:7742" };
    try std.testing.expect(requestSourceAllowed(local_origin));
    const rebound = Request{ .method = "GET", .path = "/", .body = "", .csrf_token = null, .host = "attacker.example", .origin = "http://attacker.example" };
    try std.testing.expect(!requestSourceAllowed(rebound));
}
