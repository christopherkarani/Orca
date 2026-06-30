const std = @import("std");
const exit_codes = @import("exit_codes.zig");
const contracts = @import("daemon_contracts.zig");
const tui = @import("../tui/mod.zig");
const suggestions = @import("suggestions.zig");

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
    return renderHuman(io, options, parsed.value, stdout, stderr);
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
            suggestions.writeUnknownOption(stderr, "orca packs", arg, &.{ "--installed", "--enabled", "--filter", "--page", "--page-size" }, "packs") catch {};
            return error.InvalidArguments;
        }
    }
    return options;
}

fn usageError(stderr: anytype, message: []const u8) error{InvalidArguments} {
    stderr.print("orca packs: {s}. Run 'orca help packs' for usage.\n", .{message}) catch {};
    return error.InvalidArguments;
}

fn renderHuman(io: std.Io, options: Options, output: contracts.PacksOutput, stdout: anytype, stderr: anytype) !u8 {
    return renderHumanAlloc(std.heap.smp_allocator, io, options, output, stdout, stderr);
}

fn renderHumanAlloc(allocator: std.mem.Allocator, io: std.Io, options: Options, output: contracts.PacksOutput, stdout: anytype, stderr: anytype) !u8 {
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

    const total_pages = 1 + (selected.items.len - 1) / options.page_size;
    if (options.page > total_pages) {
        return usageExit(stderr, "--page is beyond the available filtered results");
    }

    const start = std.math.mul(usize, options.page - 1, options.page_size) catch
        return usageExit(stderr, "--page and --page-size are too large");
    const end = @min(selected.items.len, std.math.add(usize, start, options.page_size) catch selected.items.len);
    const page_items = selected.items[start..end];

    const rows = try allocator.alloc([]const []const u8, page_items.len);
    defer allocator.free(rows);
    var initialized_rows: usize = 0;
    defer for (rows[0..initialized_rows]) |row| allocator.free(row);
    var owned: std.ArrayListUnmanaged([]u8) = .empty;
    defer {
        for (owned.items) |value| allocator.free(value);
        owned.deinit(allocator);
    }
    for (page_items, 0..) |pack, index| {
        const status = if (pack.enabled) "enabled" else "available";
        const safe_id = try tui.terminal_text.sanitizeAlloc(allocator, pack.id, .single_line);
        owned.append(allocator, safe_id) catch |err| {
            allocator.free(safe_id);
            return err;
        };
        const safe_category = try tui.terminal_text.sanitizeAlloc(allocator, pack.category, .single_line);
        owned.append(allocator, safe_category) catch |err| {
            allocator.free(safe_category);
            return err;
        };
        const safe_description = try tui.terminal_text.sanitizeAlloc(allocator, pack.description, .single_line);
        owned.append(allocator, safe_description) catch |err| {
            allocator.free(safe_description);
            return err;
        };
        const patterns = try std.fmt.allocPrint(allocator, "{d} safe / {d} blocked", .{ pack.safe_pattern_count, pack.destructive_pattern_count });
        owned.append(allocator, patterns) catch |err| {
            allocator.free(patterns);
            return err;
        };
        const cells = try allocator.alloc([]const u8, 5);
        cells[0] = safe_id;
        cells[1] = safe_category;
        cells[2] = status;
        cells[3] = patterns;
        cells[4] = safe_description;
        rows[index] = cells;
        initialized_rows += 1;
    }

    try tui.render.table(io, stdout, &.{
        .{ .name = "PACK" },     .{ .name = "CATEGORY" },    .{ .name = "STATUS" },
        .{ .name = "PATTERNS" }, .{ .name = "DESCRIPTION" },
    }, rows);
    try stdout.print("\nPage {d} of {d} · {d} pack(s)\n", .{ options.page, total_pages, selected.items.len });
    return exit_codes.success;
}

fn usageExit(stderr: anytype, message: []const u8) u8 {
    usageError(stderr, message) catch {};
    return exit_codes.usage;
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
    const Case = struct { args: []const []const u8, expected: []const u8 };
    const cases = [_]Case{
        .{ .args = &.{ "--format", "json" }, .expected = "packs|--format|json" },
        .{ .args = &.{"--robot"}, .expected = "packs|--robot" },
        .{ .args = &.{"--help"}, .expected = "packs|--help" },
        .{ .args = &.{"-h"}, .expected = "packs|-h" },
        .{ .args = &.{ "-f", "json" }, .expected = "packs|-f|json" },
        .{ .args = &.{"--format=json"}, .expected = "packs|--format=json" },
        .{ .args = &.{ "--format", "pretty" }, .expected = "packs|--format|pretty" },
        .{ .args = &.{"--expand"}, .expected = "packs|--expand" },
        .{ .args = &.{ "--max-patterns", "7" }, .expected = "packs|--max-patterns|7" },
        .{ .args = &.{"--max-patterns=7"}, .expected = "packs|--max-patterns=7" },
    };
    for (cases) |case| {
        var stdout_buf: [128]u8 = undefined;
        var stderr_buf: [128]u8 = undefined;
        var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
        var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);
        const code = try commandWithExecutor(fakePassthrough, std.testing.io, case.args, &stdout_writer, &stderr_writer);
        try std.testing.expectEqual(@as(u8, 23), code);
        try std.testing.expectEqualStrings(case.expected, stdout_writer.buffered());
        try std.testing.expectEqualStrings("daemon exact stderr\n", stderr_writer.buffered());
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

test "packs sanitizes fields before deterministic table layout" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);
    const code = try commandWithExecutor(fakeHostilePacksJson, std.testing.io, &.{}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expectEqualStrings(
        "  PACK      CATEGORY  STATUS   PATTERNS            DESCRIPTION  \n" ++
            "  --------------------------------------------------------------\n" ++
            "  db.mysql  database  enabled  3 safe / 4 blocked  safe line    \n" ++
            "\n" ++
            "Page 1 of 1 · 1 pack(s)\n",
        stdout_writer.buffered(),
    );
}

test "packs rejects pages beyond filtered results including max usize" {
    const max_page = try std.fmt.allocPrint(std.testing.allocator, "{d}", .{std.math.maxInt(usize)});
    defer std.testing.allocator.free(max_page);
    const cases = [_][]const []const u8{
        &.{ "--filter", "git", "--page", "2" },
        &.{ "--page", max_page, "--page-size", max_page },
    };
    for (cases) |args| {
        var stdout_buf: [64]u8 = undefined;
        var stderr_buf: [256]u8 = undefined;
        var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
        var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);
        const code = try commandWithExecutor(fakeUnsortedPacksJson, std.testing.io, args, &stdout_writer, &stderr_writer);
        try std.testing.expectEqual(exit_codes.usage, code);
        try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "page") != null);
        try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "orca help packs") != null);
    }
}

test "packs daemon failures preserve stdout stderr and exit code" {
    var stdout_buf: [128]u8 = undefined;
    var stderr_buf: [128]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);
    const code = try commandWithExecutor(fakeDaemonFailure, std.testing.io, &.{}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(@as(u8, 17), code);
    try std.testing.expectEqualStrings("daemon partial stdout\n", stdout_writer.buffered());
    try std.testing.expectEqualStrings("daemon exact stderr\n", stderr_writer.buffered());
}

test "packs invalid daemon JSON gives doctor remediation without leaking payload" {
    var stdout_buf: [128]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);
    const code = try commandWithExecutor(fakeInvalidJson, std.testing.io, &.{}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.general, code);
    try std.testing.expectEqualStrings("", stdout_writer.buffered());
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "orca doctor") != null);
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "TOP_SECRET") == null);
}

test "packs row construction cleans completed rows on later allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, renderPacksAllocationFailureProbe, .{});
}

fn renderPacksAllocationFailureProbe(allocator: std.mem.Allocator) !void {
    const pack_rows = [_]contracts.PackInfo{
        .{ .id = "core.git", .name = "Git", .category = "core", .description = "Protects Git", .enabled = true, .safe_pattern_count = 2, .destructive_pattern_count = 3 },
        .{ .id = "database.mysql", .name = "MySQL", .category = "database", .description = "Protects MySQL", .enabled = false, .safe_pattern_count = 4, .destructive_pattern_count = 5 },
    };
    const output: contracts.PacksOutput = .{ .packs = &pack_rows, .enabled_count = 1, .total_count = 2 };
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);
    _ = renderHumanAlloc(allocator, std.testing.io, .{}, output, &stdout_writer, &stderr_writer) catch |err| switch (err) {
        // AllocatingWriter intentionally erases allocator failures to WriteFailed.
        error.WriteFailed => return error.OutOfMemory,
        else => return err,
    };
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

fn fakeHostilePacksJson(_: std.Io, _: []const []const u8, stdout: anytype, _: anytype) !u8 {
    try stdout.writeAll(
        \\{"packs":[{"id":"db.\u001b[2Jmysql","name":"MySQL","category":"data\u001b]0;x\u0007base","description":"safe\nline","enabled":true,"safe_pattern_count":3,"destructive_pattern_count":4}],"enabled_count":1,"total_count":1}
    );
    return exit_codes.success;
}

fn fakeDaemonFailure(_: std.Io, _: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    try stdout.writeAll("daemon partial stdout\n");
    try stderr.writeAll("daemon exact stderr\n");
    return 17;
}

fn fakeInvalidJson(_: std.Io, _: []const []const u8, stdout: anytype, _: anytype) !u8 {
    try stdout.writeAll("{TOP_SECRET:not-json}");
    return exit_codes.success;
}

fn fakePassthrough(_: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    for (argv, 0..) |arg, index| {
        if (index > 0) try stdout.writeByte('|');
        try stdout.writeAll(arg);
    }
    try stderr.writeAll("daemon exact stderr\n");
    return 23;
}

fn failIfCalled(_: std.Io, _: []const []const u8, _: anytype, _: anytype) !u8 {
    return error.UnexpectedExecutorCall;
}
