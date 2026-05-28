const std = @import("std");

const core = @import("orca_core").core;
const core_api = @import("orca_core").api;
const supervisor = core.supervisor;
const report = @import("../report.zig");
const license = @import("../license.zig");
const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");

const Format = enum { markdown, json };
const Options = struct { session: []const u8 = "last", format: Format = .markdown };

pub fn command(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    const options = parseOptions(argv, stdout, stderr) catch |err| switch (err) {
        error.HelpShown => return exit_codes.success,
        error.Usage => return exit_codes.usage,
        else => return err,
    };
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var current = license.status(allocator) catch |err| switch (err) {
        error.InvalidLicense, error.InvalidLicenseSignature, error.UnsupportedLicenseIssuer, error.UnsupportedLicenseTier => {
            try stderr.print("orca report: stored license is invalid: {s}\n", .{@errorName(err)});
            return exit_codes.general;
        },
        else => return err,
    };
    defer current.deinit();
    if (!current.tier.allows(.report_export)) {
        try stderr.writeAll("orca report: report export requires a Pro or Team local license. Use 'orca license activate dev-pro' for local development.\n");
        return exit_codes.unsupported;
    }

    const workspace_root = supervisor.resolveWorkspaceRoot(allocator, null, ".") catch |err| {
        try stderr.print("orca report: failed to resolve workspace: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer allocator.free(workspace_root);

    var replay = core_api.loadReplay(allocator, workspace_root, .{ .session = options.session, .only_denied = true, .verify = true }) catch |err| switch (err) {
        error.FileNotFound => {
            try stderr.writeAll("orca report: session not found.\n");
            return exit_codes.general;
        },
        error.HashVerificationFailed => {
            try stderr.writeAll("orca report: hash verification failed; refusing to export report from tampered evidence.\n");
            return exit_codes.general;
        },
        else => {
            try stderr.print("orca report: failed: {s}\n", .{@errorName(err)});
            return exit_codes.general;
        },
    };
    defer replay.deinit();

    switch (options.format) {
        .markdown => try report.writeMarkdown(allocator, stdout, workspace_root, replay),
        .json => try report.writeJson(allocator, stdout, workspace_root, replay),
    }
    return exit_codes.success;
}

fn parseOptions(argv: []const []const u8, stdout: anytype, stderr: anytype) !Options {
    var options: Options = .{};
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        const arg = argv[index];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            _ = try help.writeCommand(stdout, "report");
            return error.HelpShown;
        } else if (std.mem.eql(u8, arg, "--session")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("orca report: --session requires a session id or 'last'.\n");
                return error.Usage;
            }
            options.session = argv[index];
        } else if (std.mem.eql(u8, arg, "--format")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("orca report: --format requires markdown or json.\n");
                return error.Usage;
            }
            if (std.mem.eql(u8, argv[index], "markdown")) options.format = .markdown else if (std.mem.eql(u8, argv[index], "json")) options.format = .json else {
                try stderr.writeAll("orca report: --format supports markdown or json.\n");
                return error.Usage;
            }
        } else {
            try stderr.print("orca report: unknown option '{s}'.\n", .{arg});
            return error.Usage;
        }
    }
    return options;
}

test "report rejects unsupported format" {
    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    const code = try command(&.{ "--format", "html" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "--format") != null);
}
