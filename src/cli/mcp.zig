const std = @import("std");

const env_util = @import("../env_util.zig");
const orca_mcp = @import("../mcp/mod.zig");
const core = @import("orca_core").core;
const supervisor = core.supervisor;
const core_api = @import("orca_core").api;
const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");
const policy = @import("orca_core").policy;
const version_command = @import("version.zig");

pub fn command(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len > 0 and (std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h"))) {
        _ = try help.writeCommand(io, stdout, "mcp");
        return exit_codes.success;
    }
    if (argv.len == 0) {
        _ = try help.writeCommand(io, stderr, "mcp");
        return exit_codes.usage;
    }
    if (std.mem.eql(u8, argv[0], "inspect")) return inspect(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "proxy")) return proxy(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "list")) return list(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "trust")) return trust(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "manifest")) return manifestCommand(io, argv[1..], stdout, stderr);
    try stderr.print("orca mcp: unknown subcommand '{s}'.\n", .{argv[0]});
    return exit_codes.usage;
}

const Options = struct {
    command_argv: []const []const u8 = &.{},
    owns_command_argv: bool = false,
    server_name: []const u8 = "fake",
    policy_path: ?[]const u8 = null,
    manifest_path: ?[]const u8 = null,
    mode: ?policy.schema.Mode = null,

    fn deinit(self: Options, allocator: std.mem.Allocator) void {
        if (self.owns_command_argv) allocator.free(self.command_argv);
    }
};

fn parseOptions(allocator: std.mem.Allocator, argv: []const []const u8, stderr: anytype) !Options {
    var options: Options = .{};
    var command_parts: std.ArrayList([]const u8) = .empty;
    defer command_parts.deinit(allocator);
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        const arg = argv[index];
        if (std.mem.eql(u8, arg, "--command")) {
            index += 1;
            if (index >= argv.len) return error.Usage;
            try command_parts.append(allocator, argv[index]);
        } else if (std.mem.eql(u8, arg, "--server")) {
            index += 1;
            if (index >= argv.len) return error.Usage;
            options.server_name = argv[index];
            try stderr.print("orca mcp: --server presets are not implemented in Phase 11; use --command.\n", .{});
            return error.Unsupported;
        } else if (std.mem.eql(u8, arg, "--name")) {
            index += 1;
            if (index >= argv.len) return error.Usage;
            options.server_name = argv[index];
        } else if (std.mem.eql(u8, arg, "--policy")) {
            index += 1;
            if (index >= argv.len) return error.Usage;
            options.policy_path = argv[index];
        } else if (std.mem.eql(u8, arg, "--manifest")) {
            index += 1;
            if (index >= argv.len) return error.Usage;
            options.manifest_path = argv[index];
        } else if (std.mem.eql(u8, arg, "--mode")) {
            index += 1;
            if (index >= argv.len) return error.Usage;
            options.mode = policy.schema.Mode.parse(argv[index]) orelse return error.Usage;
        } else if (std.mem.eql(u8, arg, "--")) {
            for (argv[index + 1 ..]) |command_arg| try command_parts.append(allocator, command_arg);
            break;
        } else {
            try stderr.print("orca mcp: unknown option '{s}'.\n", .{arg});
            return error.Usage;
        }
    }
    if (command_parts.items.len == 0) return error.MissingCommand;
    options.command_argv = try command_parts.toOwnedSlice(allocator);
    options.owns_command_argv = true;
    return options;
}

fn inspect(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len > 0 and (std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h"))) {
        try stdout.writeAll("Usage: orca mcp inspect --command <server> [--name <server-name>] [--policy <path>]\n");
        return exit_codes.success;
    }
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const options = parseOptions(allocator, argv, stderr) catch |err| return usageCode(err, stderr);
    defer options.deinit(allocator);
    var loaded_policy: ?*core_api.Policy = null;
    defer if (loaded_policy) |loaded| loaded.deinit();
    if (options.policy_path) |path| {
        loaded_policy = core_api.loadPolicyFile(io, allocator, path) catch |err| {
            try stderr.print("orca mcp inspect: invalid policy: {s}\n", .{@errorName(err)});
            return exit_codes.general;
        };
    }
    var server = orca_mcp.transport.ProcessServer.spawn(io, allocator, options.command_argv) catch |err| {
        try stderr.print("orca mcp inspect: failed to start server: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer server.deinit(io);

    const initialize = try initializeRequestAlloc(allocator);
    defer allocator.free(initialize);
    const initialized = "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\",\"params\":{}}";
    const list_tools = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\",\"params\":{}}";
    const init_response = orca_mcp.transport.ProcessServer.request(&server, allocator, initialize) catch |err| {
        try stderr.print("orca mcp inspect: initialize failed: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    allocator.free(init_response);
    orca_mcp.transport.ProcessServer.notify(&server, initialized) catch |err| {
        try stderr.print("orca mcp inspect: initialized notification failed: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    const tools_response = orca_mcp.transport.ProcessServer.request(&server, allocator, list_tools) catch |err| {
        try stderr.print("orca mcp inspect: tools/list failed: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer allocator.free(tools_response);
    var parsed = orca_mcp.jsonrpc.parseLine(allocator, tools_response) catch |err| {
        try stderr.print("orca mcp inspect: invalid tools/list response: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer parsed.deinit();
    var inventory = orca_mcp.tools.inspectToolsListResponse(allocator, options.server_name, parsed.value()) catch |err| {
        try stderr.print("orca mcp inspect: could not inspect tools: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer inventory.deinit(allocator);

    try stdout.print("MCP Server: {s}\nTransport: stdio\nTools:\n", .{options.server_name});
    for (inventory.tools) |tool| {
        try stdout.print("  {s:<24} risk: {s:<8} default: {s}", .{ tool.name, tool.risk.toString(), orca_mcp.tools.defaultDecisionForRisk(tool.risk) });
        if (loaded_policy) |selected| {
            var evaluation = try core_api.evaluateAction(allocator, selected, .{ .mcp_tool_call = .{ .server = options.server_name, .tool_name = tool.name } }, .{});
            defer evaluation.deinit(allocator);
            try stdout.print(" policy: {s}", .{evaluation.decision.result.toString()});
            if (evaluation.decision.rule_id) |rule_id| try stdout.print(" rule: {s}", .{rule_id});
        }
        try stdout.writeByte('\n');
    }
    try stdout.writeAll("\nFindings:\n");
    var finding_count: usize = 0;
    for (inventory.tools) |tool| {
        for (tool.findings) |finding| {
            finding_count += 1;
            try stdout.print("  {s}: {s} ({s})\n", .{ tool.name, finding.reason, finding.risk.toString() });
        }
    }
    if (finding_count == 0) try stdout.writeAll("  none\n");
    return exit_codes.success;
}

fn proxy(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len > 0 and (std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h"))) {
        try stdout.writeAll("Usage: orca mcp proxy --command <server> [--name <server-name>] [--policy <path>] [--manifest <path>] [--mode observe|ask|strict|ci]\n");
        return exit_codes.success;
    }
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const options = parseOptions(allocator, argv, stderr) catch |err| return usageCode(err, stderr);
    defer options.deinit(allocator);
    const workspace = try supervisor.resolveWorkspaceRoot(io, allocator, null, ".");
    defer allocator.free(workspace);
    var loaded = core_api.discoverPolicy(io, allocator, options.policy_path, workspace) catch |err| {
        try stderr.print("orca mcp proxy: invalid policy: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer loaded.deinit();
    const mode = options.mode orelse loaded.policy.mode();
    var loaded_manifest: ?orca_mcp.manifests.Manifest = null;
    defer if (loaded_manifest) |*manifest| manifest.deinit(allocator);
    var bound_launch: ?BoundManifestLaunch = null;
    defer if (bound_launch) |*binding| binding.deinit(allocator);
    if (options.manifest_path) |manifest_path| {
        loaded_manifest = orca_mcp.manifests.loadFile(io, allocator, manifest_path) catch |err| {
            try stderr.print("orca mcp proxy: invalid manifest: {s}\n", .{@errorName(err)});
            return exit_codes.usage;
        };
        if (!std.mem.eql(u8, loaded_manifest.?.server.name, options.server_name)) {
            try stderr.print("orca mcp proxy: manifest server '{s}' does not match --name '{s}'.\n", .{ loaded_manifest.?.server.name, options.server_name });
            return exit_codes.usage;
        }
        bound_launch = bindManifestLaunch(io, allocator, loaded_manifest.?, options.command_argv) catch |err| {
            try stderr.print("orca mcp proxy: manifest does not match launched server: {s}\n", .{@errorName(err)});
            return exit_codes.usage;
        };
    }
    const spawn_argv = if (bound_launch) |binding| binding.argv else options.command_argv;
    const spawn_env = if (bound_launch) |*binding| &binding.env_map else null;

    const session = try makeSession(io, options.command_argv, workspace, mode);
    var session_writer = core_api.createAuditWriter(io, allocator, session) catch |err| {
        try stderr.print("orca mcp proxy: audit unavailable: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer session_writer.deinit();
    try session_writer.writeLastPointer();

    var server = orca_mcp.transport.ProcessServer.spawnWithEnvMap(io, allocator, spawn_argv, spawn_env) catch |err| {
        try stderr.print("orca mcp proxy: failed to start server: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer server.deinit(io);

    const stdin_buffer = try allocator.alloc(u8, core.limits.max_mcp_message_len + 1);
    defer allocator.free(stdin_buffer);
    var stdin_reader = std.Io.File.stdin().reader(io, stdin_buffer);
    var tty_file: ?std.Io.File = null;
    var approval_reader_storage: ?std.Io.File.Reader = null;
    var approval_writer_storage: ?std.Io.File.Writer = null;
    var approval_read_buffer: [1024]u8 = undefined;
    var approval_write_buffer: [4096]u8 = undefined;
    if (mode != .ci) {
        if (std.Io.Dir.openFileAbsolute(io, "/dev/tty", .{ .mode = .read_write })) |file| {
            tty_file = file;
            approval_reader_storage = file.reader(io, &approval_read_buffer);
            approval_writer_storage = file.writer(io, &approval_write_buffer);
        } else |_| {}
    }
    defer if (tty_file) |file| file.close(io);

    orca_mcp.proxy.runWithServer(allocator, .{
        .server_name = options.server_name,
        .server_command_display = options.command_argv[0],
        .policy = loaded.innerPtr(),
        .mode = mode,
        .audit_writer = &session_writer,
        .approval_reader = if (approval_reader_storage) |*reader| &reader.interface else null,
        .approval_writer = if (approval_writer_storage) |*writer| &writer.interface else null,
        .manifest = if (loaded_manifest) |*manifest| manifest else null,
    }, &stdin_reader.interface, stdout, .{
        .context = &server,
        .request = orca_mcp.transport.ProcessServer.request,
        .notify = orca_mcp.transport.ProcessServer.notify,
        .read = orca_mcp.transport.ProcessServer.read,
    }) catch |err| {
        if (approval_writer_storage) |*writer| writer.interface.flush() catch {};
        var completed_session = session;
        completed_session.ended_at = core.time.Timestamp.now(io);
        try core_api.writeAuditSummary(allocator, session_writer.session_dir_path, .{
            .session = completed_session,
            .status = .{ .exited = exit_codes.general },
            .event_count = session_writer.event_count,
            .final_event_hash = session_writer.finalHash() orelse "",
            .policy = loaded.path,
            .product_label = "Orca",
        });
        try stderr.print("orca mcp proxy: protocol failed: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    if (approval_writer_storage) |*writer| writer.interface.flush() catch {};
    var completed_session = session;
    completed_session.ended_at = core.time.Timestamp.now(io);
    try core_api.writeAuditSummary(allocator, session_writer.session_dir_path, .{
        .session = completed_session,
        .status = .{ .exited = 0 },
        .event_count = session_writer.event_count,
        .final_event_hash = session_writer.finalHash() orelse "",
        .policy = loaded.path,
        .product_label = "Orca",
    });
    return exit_codes.success;
}

fn initializeRequestAlloc(allocator: std.mem.Allocator) ![]u8 {
    return try std.fmt.allocPrint(
        allocator,
        "{{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{{\"protocolVersion\":\"2025-03-26\",\"capabilities\":{{}},\"clientInfo\":{{\"name\":\"orca\",\"version\":\"{s}\"}}}}}}",
        .{version_command.current().version},
    );
}

fn list(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len > 0 and (std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h"))) {
        try stdout.writeAll("Usage: orca mcp list\n");
        return exit_codes.success;
    }
    if (argv.len != 0) {
        try stderr.writeAll("orca mcp list: unexpected arguments.\n");
        return exit_codes.usage;
    }
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    try stdout.writeAll("Known MCP servers:\n");
    var found = false;
    if (std.Io.Dir.cwd().openDir(io, ".orca/mcp", .{ .iterate = true })) |dir_value| {
        var dir = dir_value;
        defer dir.close(io);
        var it = dir.iterate();
        while (try it.next(io)) |entry| {
            if (entry.kind != .file or !(std.mem.endsWith(u8, entry.name, ".yaml") or std.mem.endsWith(u8, entry.name, ".yml"))) continue;
            const path = try std.fs.path.join(allocator, &.{ ".orca", "mcp", entry.name });
            defer allocator.free(path);
            var manifest = orca_mcp.manifests.loadFile(io, allocator, path) catch |err| {
                try stdout.print("  invalid manifest: {s} ({s})\n", .{ path, @errorName(err) });
                found = true;
                continue;
            };
            defer manifest.deinit(allocator);
            try stdout.print("  {s} transport={s} command={s} manifest={s}\n", .{ manifest.server.name, manifest.server.transport.toString(), manifest.server.command, path });
            found = true;
        }
    } else |_| {}
    if (!found) try stdout.writeAll("  none configured (checked .orca/mcp/*.yaml)\n");
    return exit_codes.success;
}

fn trust(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len > 0 and (std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h"))) {
        try stdout.writeAll("Usage: orca mcp trust <server> --tool <tool>\n");
        return exit_codes.success;
    }
    if (argv.len != 3 or !std.mem.eql(u8, argv[1], "--tool")) {
        try stderr.writeAll("orca mcp trust: expected <server> --tool <tool>.\n");
        return exit_codes.usage;
    }
    const server = argv[0];
    const tool = argv[2];
    if (!safeSelectorPart(server) or !safeSelectorPart(tool)) {
        try stderr.writeAll("orca mcp trust: server and tool must be simple selector names.\n");
        return exit_codes.usage;
    }
    try stdout.print(
        \\Direct policy mutation is not implemented for this command.
        \\Add this snippet to your policy after reviewing the server manifest:
        \\
        \\mcp:
        \\  allow:
        \\    - "{s}.{s}"
        \\
    , .{ server, tool });
    return exit_codes.success;
}

fn manifestCommand(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0 or std.mem.eql(u8, argv[0], "--help") or std.mem.eql(u8, argv[0], "-h")) {
        try stdout.writeAll(
            \\Usage:
            \\  orca mcp manifest check <manifest.yaml>
            \\  orca mcp manifest generate --command <server-command> [-- <args...>]
            \\  orca mcp manifest generate --server <name>
            \\
        );
        return if (argv.len == 0) exit_codes.usage else exit_codes.success;
    }
    if (std.mem.eql(u8, argv[0], "check")) return manifestCheck(io, argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "generate")) return manifestGenerate(argv[1..], stdout, stderr);
    try stderr.print("orca mcp manifest: unknown subcommand '{s}'.\n", .{argv[0]});
    return exit_codes.usage;
}

fn manifestCheck(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len != 1) {
        try stderr.writeAll("orca mcp manifest check: expected <manifest.yaml>.\n");
        return exit_codes.usage;
    }
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var manifest = orca_mcp.manifests.loadFile(io, allocator, argv[0]) catch |err| {
        try stderr.print("invalid MCP manifest: {s}\n", .{@errorName(err)});
        return exit_codes.usage;
    };
    defer manifest.deinit(allocator);
    try stdout.print("valid MCP manifest: server={s} transport={s} command={s} tools={d}\n", .{
        manifest.server.name,
        manifest.server.transport.toString(),
        manifest.server.command,
        manifest.tools.len,
    });
    return exit_codes.success;
}

fn manifestGenerate(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var command_name: ?[]const u8 = null;
    var server_name: ?[]const u8 = null;
    var args_start: ?usize = null;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--command")) {
            index += 1;
            if (index >= argv.len) return exit_codes.usage;
            command_name = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--server")) {
            index += 1;
            if (index >= argv.len) return exit_codes.usage;
            server_name = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--")) {
            args_start = index + 1;
            break;
        } else {
            try stderr.print("orca mcp manifest generate: unknown option '{s}'.\n", .{argv[index]});
            return exit_codes.usage;
        }
    }
    const name = server_name orelse command_name orelse {
        try stderr.writeAll("orca mcp manifest generate: expected --command or --server.\n");
        return exit_codes.usage;
    };
    const command_text = command_name orelse name;
    const extra_args = if (args_start) |start| argv[start..] else &.{};
    try orca_mcp.manifests.writeStarterManifest(stdout, name, command_text, extra_args);
    return exit_codes.success;
}

fn safeSelectorPart(value: []const u8) bool {
    if (value.len == 0 or value.len > 128) return false;
    for (value) |char| {
        if (!(std.ascii.isAlphanumeric(char) or char == '_' or char == '-' or char == '.')) return false;
    }
    return true;
}

const BoundManifestLaunch = struct {
    argv: []const []const u8,
    env_map: std.process.Environ.Map,

    fn deinit(self: *BoundManifestLaunch, allocator: std.mem.Allocator) void {
        for (self.argv) |arg| allocator.free(arg);
        if (self.argv.len > 0) allocator.free(self.argv);
        self.env_map.deinit();
        self.* = undefined;
    }
};

fn bindManifestLaunch(
    io: std.Io,
    allocator: std.mem.Allocator,
    manifest: orca_mcp.manifests.Manifest,
    requested_argv: []const []const u8,
) !BoundManifestLaunch {
    if (manifest.server.transport != .stdio) return error.UnsupportedManifestTransport;
    if (requested_argv.len != manifest.server.args.len + 1) return error.ManifestArgvMismatch;
    if (!std.mem.eql(u8, requested_argv[0], manifest.server.command)) return error.ManifestCommandMismatch;
    for (manifest.server.args, 0..) |expected, index| {
        if (!std.mem.eql(u8, expected, requested_argv[index + 1])) return error.ManifestArgvMismatch;
    }

    const resolved_command = try resolveCommandPath(io, allocator, manifest.server.command);
    errdefer allocator.free(resolved_command);
    if (manifest.server.expected_hash) |expected_hash| {
        try verifyExpectedHash(io, allocator, resolved_command, expected_hash);
    }

    var argv = try allocator.alloc([]const u8, requested_argv.len);
    errdefer allocator.free(argv);
    argv[0] = resolved_command;
    var owned_count: usize = 1;
    errdefer {
        for (argv[0..owned_count]) |arg| allocator.free(arg);
    }
    for (requested_argv[1..], 1..) |arg, index| {
        argv[index] = try allocator.dupe(u8, arg);
        owned_count += 1;
    }

    var process_env = try env_util.createProcessMap(allocator);
    defer process_env.deinit();
    var env_map = std.process.Environ.Map.init(allocator);
    errdefer env_map.deinit();
    for (manifest.server.env_allow) |name| {
        if (!safeEnvName(name)) return error.InvalidManifestEnvAllow;
        if (env_util.getOwned(&process_env, allocator, name) catch null) |value| {
            defer allocator.free(value);
            try env_map.put(name, value);
        }
    }

    return .{ .argv = argv, .env_map = env_map };
}

fn resolveCommandPath(io: std.Io, allocator: std.mem.Allocator, command_name: []const u8) ![]const u8 {
    const cwd = std.Io.Dir.cwd();
    if (std.fs.path.isAbsolute(command_name) or std.mem.indexOfAny(u8, command_name, "/\\") != null) {
        return realPathDupe(io, cwd, command_name, allocator) catch try allocator.dupe(u8, command_name);
    }
    var process_env = try env_util.createProcessMap(allocator);
    defer process_env.deinit();
    const path_value = try env_util.getOwned(&process_env, allocator, "PATH") orelse return error.ManifestCommandNotFound;
    defer allocator.free(path_value);
    var parts = std.mem.splitScalar(u8, path_value, std.fs.path.delimiter);
    while (parts.next()) |dir| {
        if (dir.len == 0) continue;
        const candidate = try std.fs.path.join(allocator, &.{ dir, command_name });
        defer allocator.free(candidate);
        cwd.access(io, candidate, .{}) catch continue;
        return realPathDupe(io, cwd, candidate, allocator) catch try allocator.dupe(u8, candidate);
    }
    return error.ManifestCommandNotFound;
}

fn realPathDupe(io: std.Io, dir: std.Io.Dir, path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const n = try dir.realPathFile(io, path, &buffer);
    return try allocator.dupe(u8, buffer[0..n]);
}

fn verifyExpectedHash(io: std.Io, allocator: std.mem.Allocator, resolved_command: []const u8, expected_hash: []const u8) !void {
    const normalized_expected = if (std.mem.startsWith(u8, expected_hash, "sha256:")) expected_hash["sha256:".len..] else expected_hash;
    if (normalized_expected.len != 64) return error.InvalidManifestExpectedHash;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, resolved_command, allocator, .limited(128 * 1024 * 1024));
    defer allocator.free(bytes);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    if (!std.ascii.eqlIgnoreCase(normalized_expected, &hex)) return error.ManifestExpectedHashMismatch;
}

fn safeEnvName(value: []const u8) bool {
    if (value.len == 0 or value.len > core.limits.max_env_name_len) return false;
    for (value) |char| {
        if (!(std.ascii.isAlphanumeric(char) or char == '_')) return false;
    }
    return true;
}

fn usageCode(err: anyerror, stderr: anytype) !u8 {
    switch (err) {
        error.MissingCommand => try stderr.writeAll("orca mcp: expected --command <server>.\n"),
        error.Unsupported => {},
        else => try stderr.writeAll("orca mcp: invalid arguments.\n"),
    }
    return if (err == error.Unsupported) exit_codes.unsupported else exit_codes.usage;
}

fn makeSession(io: std.Io, command_argv: []const []const u8, workspace: []const u8, mode: policy.schema.Mode) !core.session.Session {
    const now = core.time.Timestamp.now(io);
    return .{
        .id = try core.session.generateSessionId(now),
        .started_at = now,
        .command = "orca mcp proxy",
        .args = command_argv,
        .workspace_root = workspace,
        .mode = mode.toCoreMode(),
        .platform = core.platform.detectOs(),
    };
}

test "mcp command help and invalid subcommands are stable" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const help_code = try command(std.testing.io, &.{"--help"}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, help_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "Inspect and proxy MCP servers") != null);

    stdout_writer = .fixed(&stdout_buf);
    stderr_writer = .fixed(&stderr_buf);
    const bad_code = try command(std.testing.io, &.{"unknown"}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.usage, bad_code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "unknown subcommand") != null);
}

test "mcp command parsing preserves server argv after --command" {
    var stderr_buf: [256]u8 = undefined;
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const options = try parseOptions(std.testing.allocator, &.{ "--command", "node", "--", "server.js", "--flag" }, &stderr_writer);
    defer options.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), options.command_argv.len);
    try std.testing.expectEqualStrings("node", options.command_argv[0]);
    try std.testing.expectEqualStrings("server.js", options.command_argv[1]);
    try std.testing.expectEqualStrings("--flag", options.command_argv[2]);
}

test "mcp initialize request uses build version metadata" {
    const request = try initializeRequestAlloc(std.testing.allocator);
    defer std.testing.allocator.free(request);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"clientInfo\":{\"name\":\"orca\",\"version\":\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, version_command.current().version) != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"version\":\"1.0.0\"") == null or std.mem.eql(u8, version_command.current().version, "1.0.0"));
}

test "mcp proxy reports invalid policy as CLI error" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    {
        const file = try tmp.dir.createFile(std.testing.io, "bad-policy.yaml", .{});
        defer file.close(std.testing.io);
        try file.writeStreamingAll(std.testing.io, 
            \\version: 1
            \\mode: not-a-mode
        );
    }
    const policy_path = try tmp.dir.realPathFileAlloc(std.testing.io, "bad-policy.yaml", std.testing.allocator);
    defer std.testing.allocator.free(policy_path);

    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try command(std.testing.io, &.{ "proxy", "--policy", policy_path, "--command", "python3", "--", "fixtures/mcp/fake_server.py" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.general, code);
    try std.testing.expectEqualStrings("", stdout_writer.buffered());
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "orca mcp proxy: invalid policy") != null);
}

test "mcp inspect policy option reports Core policy decisions" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    {
        const file = try tmp.dir.createFile(std.testing.io, "mcp-policy.yaml", .{});
        defer file.close(std.testing.io);
        try file.writeStreamingAll(std.testing.io, 
            \\version: 1
            \\mode: strict
            \\mcp:
            \\  allow:
            \\    - "fake.search_issues"
            \\  deny:
            \\    - "fake.delete_repository"
        );
    }
    const policy_path = try tmp.dir.realPathFileAlloc(std.testing.io, "mcp-policy.yaml", std.testing.allocator);
    defer std.testing.allocator.free(policy_path);

    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [2048]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try command(std.testing.io, &.{ "inspect", "--name", "fake", "--policy", policy_path, "--command", "python3", "--", "fixtures/mcp/fake_server.py" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);
    const output = stdout_writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "search_issues") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "policy: allow") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "delete_repository") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "policy: deny") != null);
    _ = stderr_writer.buffered();
}

test "manifest binding requires exact argv hash and env allowlist" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    {
        const file = try tmp.dir.createFile(std.testing.io, "server-bin", .{});
        defer file.close(std.testing.io);
        try file.writeStreamingAll(std.testing.io, "fake server binary");
    }
    const server_path = try tmp.dir.realPathFileAlloc(std.testing.io, "server-bin", std.testing.allocator);
    defer std.testing.allocator.free(server_path);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("fake server binary", &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    const manifest_text = try std.fmt.allocPrint(std.testing.allocator,
        \\version: 1
        \\server:
        \\  name: fake
        \\  transport: stdio
        \\  command: {s}
        \\  args:
        \\    - --stdio
        \\  expected_hash: sha256:{s}
        \\  env:
        \\    allow:
        \\      - PATH
        \\tools:
        \\  search:
        \\    risk: low
        \\    default: allow
        \\resources:
        \\  default: ask
        \\prompts:
        \\  default: ask
        \\sampling:
        \\  default: deny
    , .{ server_path, &hex });
    defer std.testing.allocator.free(manifest_text);
    var manifest = try orca_mcp.manifests.parseFromSlice(std.testing.allocator, manifest_text, "test.yaml");
    defer manifest.deinit(std.testing.allocator);

    var binding = try bindManifestLaunch(std.testing.io, std.testing.allocator, manifest, &.{ server_path, "--stdio" });
    defer binding.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(server_path, binding.argv[0]);
    try std.testing.expectEqualStrings("--stdio", binding.argv[1]);
    try std.testing.expect(binding.env_map.get("PATH") != null);

    try std.testing.expectError(error.ManifestCommandMismatch, bindManifestLaunch(std.testing.io, std.testing.allocator, manifest, &.{ "/different", "--stdio" }));
    try std.testing.expectError(error.ManifestArgvMismatch, bindManifestLaunch(std.testing.io, std.testing.allocator, manifest, &.{ server_path, "--other" }));

    const bad_manifest_text = try std.fmt.allocPrint(std.testing.allocator,
        \\version: 1
        \\server:
        \\  name: fake
        \\  transport: stdio
        \\  command: {s}
        \\  expected_hash: {s}
        \\tools:
    , .{ server_path, "0000000000000000000000000000000000000000000000000000000000000000" });
    defer std.testing.allocator.free(bad_manifest_text);
    var bad_manifest = try orca_mcp.manifests.parseFromSlice(std.testing.allocator, bad_manifest_text, "bad.yaml");
    defer bad_manifest.deinit(std.testing.allocator);
    try std.testing.expectError(error.ManifestExpectedHashMismatch, bindManifestLaunch(std.testing.io, std.testing.allocator, bad_manifest, &.{server_path}));
}

test "mcp manifest check list trust and generate commands are safe" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const prev_cwd = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(prev_cwd);
    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer std.process.setCurrentPath(std.testing.io, prev_cwd) catch {};

    try tmp.dir.createDirPath(std.testing.io, ".orca/mcp");
    {
        const file = try tmp.dir.createFile(std.testing.io, ".orca/mcp/github.yaml", .{});
        defer file.close(std.testing.io);
        try file.writeStreamingAll(std.testing.io, 
            \\version: 1
            \\server:
            \\  name: github
            \\  transport: stdio
            \\  command: github-mcp-server
            \\tools:
            \\  search_issues:
            \\    risk: low
            \\    default: allow
            \\resources:
            \\  default: ask
            \\prompts:
            \\  default: ask
            \\sampling:
            \\  default: deny
        );
    }

    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const check_code = try command(std.testing.io, &.{ "manifest", "check", ".orca/mcp/github.yaml" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, check_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "valid MCP manifest") != null);

    stdout_writer = .fixed(&stdout_buf);
    stderr_writer = .fixed(&stderr_buf);
    const list_code = try command(std.testing.io, &.{"list"}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, list_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "github") != null);

    stdout_writer = .fixed(&stdout_buf);
    stderr_writer = .fixed(&stderr_buf);
    const trust_code = try command(std.testing.io, &.{ "trust", "github", "--tool", "search_issues" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, trust_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "\"github.search_issues\"") != null);

    stdout_writer = .fixed(&stdout_buf);
    stderr_writer = .fixed(&stderr_buf);
    const generate_code = try command(std.testing.io, &.{ "manifest", "generate", "--command", "github-mcp-server", "--", "--token", "ghp_fakeSecretShouldNotPrint" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, generate_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "ghp_fakeSecretShouldNotPrint") == null);
}
