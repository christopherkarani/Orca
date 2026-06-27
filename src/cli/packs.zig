const std = @import("std");
const exit_codes = @import("exit_codes.zig");
const contracts = @import("daemon_contracts.zig");
const tui = @import("../tui/mod.zig");

const Options = struct {
    filter: ?[]const u8 = null,
    installed: bool = false,
    page: usize = 1,
    page_size: usize = 25,
};

pub fn command(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    return commandWithExecutor(realExecute, io, argv, stdout, stderr);
}

fn realExecute(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    const cli = @import("mod.zig");
    return cli.executeDaemonCli(io, argv, stdout, stderr);
}

pub fn commandWithExecutor(comptime execute_cli: anytype, io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (shouldPassThrough(argv)) {
        const daemon_argv = try std.heap.smp_allocator.alloc([]const u8, argv.len + 1);
        defer std.heap.smp_allocator.free(daemon_argv);
        daemon_argv[0] = "packs";
        @memcpy(daemon_argv[1..], argv);
        return execute_cli(io, daemon_argv, stdout, stderr);
    }

    const options = parseOptions(argv, stderr) catch return exit_codes.usage;
    var daemon_stdout: std.Io.Writer.Allocating = .init(std.heap.smp_allocator);
    defer daemon_stdout.deinit();
    var daemon_stderr: std.Io.Writer.Allocating = .init(std.heap.smp_allocator);
    defer daemon_stderr.deinit();

    const daemon_argv: []const []const u8 = if (options.installed)
        &.{ "packs", "--enabled", "--format", "json" }
    else
        &.{ "packs", "--format", "json" };
    const code = try execute_cli(io, daemon_argv, &daemon_stdout.writer, &daemon_stderr.writer);
    if (code != exit_codes.success) {
        try stdout.writeAll(daemon_stdout.written());
        try stderr.writeAll(daemon_stderr.written());
        return code;
    }

    var parsed = contracts.parsePacks(std.heap.smp_allocator, daemon_stdout.written()) catch |err| {
        try stderr.print("orca packs: daemon returned invalid JSON ({s}). Try 'orca doctor'.\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer parsed.deinit();
    return renderHuman(io, options, parsed.value, stdout);
}

fn shouldPassThrough(argv: []const []const u8) bool {
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h") or
            std.mem.eql(u8, arg, "--robot") or std.mem.eql(u8, arg, "--expand") or
            std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v") or
            std.mem.eql(u8, arg, "--format") or std.mem.eql(u8, arg, "-f") or
            std.mem.startsWith(u8, arg, "--format=") or std.mem.eql(u8, arg, "--max-patterns") or
            std.mem.startsWith(u8, arg, "--max-patterns=")) return true;
    }
    return false;
}

fn parseOptions(argv: []const []const u8, stderr: anytype) !Options {
    var options: Options = .{};
    var i: usize = 0;
    while (i < argv.len) : (i += 1) {
        const arg = argv[i];
        if (std.mem.eql(u8, arg, "--installed") or std.mem.eql(u8, arg, "--enabled")) {
            options.installed = true;
        } else if (std.mem.eql(u8, arg, "--filter")) {
            i += 1;
            if (i >= argv.len or argv[i].len == 0 or std.mem.startsWith(u8, argv[i], "--"))
                return usageError(stderr, "--filter requires a non-empty search term");
            options.filter = argv[i];
        } else if (std.mem.eql(u8, arg, "--page")) {
            i += 1;
            if (i >= argv.len) return usageError(stderr, "--page requires a positive integer");
            options.page = std.fmt.parseInt(usize, argv[i], 10) catch return usageError(stderr, "--page requires a positive integer");
            if (options.page == 0) return usageError(stderr, "--page requires a positive integer");
        } else if (std.mem.eql(u8, arg, "--page-size")) {
            i += 1;
            if (i >= argv.len) return usageError(stderr, "--page-size requires a positive integer");
            options.page_size = std.fmt.parseInt(usize, argv[i], 10) catch return usageError(stderr, "--page-size requires a positive integer");
            if (options.page_size == 0) return usageError(stderr, "--page-size requires a positive integer");
        } else {
            return usageError(stderr, "unknown option");
        }
    }
    return options;
}

fn usageError(stderr: anytype, message: []const u8) error{InvalidArguments} {
    stderr.print("orca packs: {s}. Run 'orca help packs' for usage.\n", .{message}) catch {};
    return error.InvalidArguments;
}

fn renderHuman(io: std.Io, options: Options, output: contracts.PacksOutput, stdout: anytype) !u8 {
    const allocator = std.heap.smp_allocator;
    var selected: std.ArrayListUnmanaged(contracts.PackInfo) = .empty;
    defer selected.deinit(allocator);
    for (output.packs) |pack| {
        if (options.installed and !pack.enabled) continue;
        if (options.filter) |term| {
            if (!containsIgnoreCase(pack.id, term) and !containsIgnoreCase(pack.name, term) and
                !containsIgnoreCase(pack.category, term) and !containsIgnoreCase(pack.description, term)) continue;
        }
        try selected.append(allocator, pack);
    }
    std.mem.sort(contracts.PackInfo, selected.items, {}, lessThanPack);

    if (selected.items.len == 0) {
        try tui.render.callout(io, stdout, .info, "No safety packs found", if (options.filter != null)
            "Try a broader --filter term, or run 'orca packs' to list all packs."
        else if (options.installed)
            "No packs are enabled. Configure packs in ~/.config/orca/config.toml."
        else
            "Run 'orca doctor' to verify the daemon and pack configuration.");
        return exit_codes.success;
    }

    const start = std.math.mul(usize, options.page - 1, options.page_size) catch selected.items.len;
    const end = @min(selected.items.len, std.math.add(usize, start, options.page_size) catch selected.items.len);
    const page_items = if (start < selected.items.len) selected.items[start..end] else selected.items[0..0];

    const rows = try allocator.alloc([]const []const u8, page_items.len);
    defer allocator.free(rows);
    var owned: std.ArrayListUnmanaged([]u8) = .empty;
    defer {
        for (owned.items) |value| allocator.free(value);
        owned.deinit(allocator);
    }
    for (page_items, 0..) |pack, index| {
        const status = if (pack.enabled) "enabled" else "available";
        const patterns = try std.fmt.allocPrint(allocator, "{d} safe / {d} blocked", .{ pack.safe_pattern_count, pack.destructive_pattern_count });
        try owned.append(allocator, patterns);
        const cells = try allocator.alloc([]const u8, 5);
        cells[0] = pack.id;
        cells[1] = pack.category;
        cells[2] = status;
        cells[3] = patterns;
        cells[4] = pack.description;
        rows[index] = cells;
    }
    defer for (rows) |row| allocator.free(row);

    try tui.render.table(io, stdout, &.{
        .{ .name = "PACK" },     .{ .name = "CATEGORY" },    .{ .name = "STATUS" },
        .{ .name = "PATTERNS" }, .{ .name = "DESCRIPTION" },
    }, rows);
    const total_pages = 1 + (selected.items.len - 1) / options.page_size;
    try stdout.print("\nPage {d} of {d} · {d} pack(s)\n", .{ options.page, total_pages, selected.items.len });
    return exit_codes.success;
}

fn lessThanPack(_: void, lhs: contracts.PackInfo, rhs: contracts.PackInfo) bool {
    return std.mem.order(u8, lhs.id, rhs.id) == .lt;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    for (0..haystack.len - needle.len + 1) |start| {
        var matches = true;
        for (needle, 0..) |char, offset| {
            if (std.ascii.toLower(haystack[start + offset]) != std.ascii.toLower(char)) {
                matches = false;
                break;
            }
        }
        if (matches) return true;
    }
    return false;
}

test "human packs requests daemon JSON instead of parsing pretty output" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try commandWithExecutor(fakePacksJson, std.testing.io, &.{}, &stdout_writer, &stderr_writer);

    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "PACK") != null);
}

fn fakePacksJson(_: std.Io, argv: []const []const u8, stdout: anytype, _: anytype) !u8 {
    try std.testing.expectEqualSlices([]const u8, &.{ "packs", "--format", "json" }, argv);
    try stdout.writeAll(
        \\{"packs":[{"id":"core.git","name":"Git","category":"core","description":"Protects Git","enabled":true,"safe_pattern_count":2,"destructive_pattern_count":3}],"enabled_count":1,"total_count":1}
    );
    return exit_codes.success;
}

test "packs filters sorts paginates and sanitizes daemon fields" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try commandWithExecutor(fakeUnsortedPacksJson, std.testing.io, &.{ "--filter", "DATA", "--page", "1", "--page-size", "1" }, &stdout_writer, &stderr_writer);
    const rendered = stdout_writer.buffered();
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "database.mysql") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "database.postgresql") == null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "Page 1 of 2") != null);
    try std.testing.expect(std.mem.indexOfScalar(u8, rendered, 0x1b) == null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "packs installed alias uses daemon enabled semantics and renders empty guidance" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);
    const code = try commandWithExecutor(fakeEnabledPacksEmpty, std.testing.io, &.{"--installed"}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "No safety packs found") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "config.toml") != null);
}

test "packs machine help and raw modes are byte identical passthrough" {
    const cases = [_][]const []const u8{
        &.{ "--format", "json" }, &.{"--robot"}, &.{"--help"}, &.{ "--format", "pretty" }, &.{"--expand"},
    };
    for (cases) |args| {
        var stdout_buf: [128]u8 = undefined;
        var stderr_buf: [128]u8 = undefined;
        var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
        var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);
        const code = try commandWithExecutor(fakePassthrough, std.testing.io, args, &stdout_writer, &stderr_writer);
        try std.testing.expectEqual(exit_codes.success, code);
        try std.testing.expectEqualStrings("daemon\x1b[raw]\n", stdout_writer.buffered());
        try std.testing.expectEqualStrings("", stderr_writer.buffered());
    }
}

test "packs rejects missing and invalid Zig option values with remediation" {
    const cases = [_][]const []const u8{
        &.{"--filter"}, &.{ "--page", "0" }, &.{ "--page", "nope" }, &.{ "--page-size", "0" }, &.{"--unknown"},
    };
    for (cases) |args| {
        var stdout_buf: [64]u8 = undefined;
        var stderr_buf: [256]u8 = undefined;
        var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
        var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);
        const code = try commandWithExecutor(failIfCalled, std.testing.io, args, &stdout_writer, &stderr_writer);
        try std.testing.expectEqual(exit_codes.usage, code);
        try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "orca help packs") != null);
    }
}

fn fakeUnsortedPacksJson(_: std.Io, argv: []const []const u8, stdout: anytype, _: anytype) !u8 {
    try std.testing.expectEqualSlices([]const u8, &.{ "packs", "--format", "json" }, argv);
    try stdout.writeAll(
        \\{"packs":[{"id":"database.postgresql","name":"Postgres","category":"database","description":"Postgres","enabled":false,"safe_pattern_count":1,"destructive_pattern_count":2},{"id":"database.mysql","name":"MySQL","category":"database","description":"MySQL\u001b[2J","enabled":true,"safe_pattern_count":3,"destructive_pattern_count":4},{"id":"core.git","name":"Git","category":"core","description":"Git","enabled":true,"safe_pattern_count":2,"destructive_pattern_count":3}],"enabled_count":2,"total_count":3}
    );
    return exit_codes.success;
}

fn fakeEnabledPacksEmpty(_: std.Io, argv: []const []const u8, stdout: anytype, _: anytype) !u8 {
    try std.testing.expectEqualSlices([]const u8, &.{ "packs", "--enabled", "--format", "json" }, argv);
    try stdout.writeAll("{\"packs\":[],\"enabled_count\":0,\"total_count\":3}");
    return exit_codes.success;
}

fn fakePassthrough(_: std.Io, argv: []const []const u8, stdout: anytype, _: anytype) !u8 {
    try std.testing.expectEqualStrings("packs", argv[0]);
    try stdout.writeAll("daemon\x1b[raw]\n");
    return exit_codes.success;
}

fn failIfCalled(_: std.Io, _: []const []const u8, _: anytype, _: anytype) !u8 {
    return error.UnexpectedExecutorCall;
}
