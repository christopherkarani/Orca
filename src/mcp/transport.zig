const std = @import("std");

const core = @import("../core/mod.zig");
const jsonrpc = @import("jsonrpc.zig");
const stdio = @import("stdio.zig");

pub const implemented = true;

pub const ProcessServer = struct {
    allocator: std.mem.Allocator,
    child: std.process.Child,
    stdin_writer: std.fs.File.Writer,
    stdout_reader: std.fs.File.Reader,
    stdin_buffer: []u8,
    stdout_buffer: []u8,

    pub fn spawn(allocator: std.mem.Allocator, argv: []const []const u8) !ProcessServer {
        if (argv.len == 0) return error.InvalidCommand;
        var child = std.process.Child.init(argv, allocator);
        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Inherit;
        try child.spawn();
        try child.waitForSpawn();

        const stdin_buffer = try allocator.alloc(u8, 16 * 1024);
        errdefer allocator.free(stdin_buffer);
        const stdout_buffer = try allocator.alloc(u8, core.limits.max_mcp_message_len + 1);
        errdefer allocator.free(stdout_buffer);

        return .{
            .allocator = allocator,
            .child = child,
            .stdin_writer = child.stdin.?.writer(stdin_buffer),
            .stdout_reader = child.stdout.?.reader(stdout_buffer),
            .stdin_buffer = stdin_buffer,
            .stdout_buffer = stdout_buffer,
        };
    }

    pub fn deinit(self: *ProcessServer) void {
        self.stdin_writer.interface.flush() catch {};
        _ = self.child.kill() catch self.child.wait() catch {};
        self.allocator.free(self.stdin_buffer);
        self.allocator.free(self.stdout_buffer);
        self.* = undefined;
    }

    pub fn request(context: *anyopaque, allocator: std.mem.Allocator, line: []const u8) ![]u8 {
        const self: *ProcessServer = @ptrCast(@alignCast(context));
        try stdio.writeRawMessage(&self.stdin_writer.interface, line);
        try self.stdin_writer.interface.flush();
        const response = try stdio.readMessageLine(&self.stdout_reader.interface, allocator) orelse return error.McpServerClosed;
        errdefer allocator.free(response);
        var parsed = try jsonrpc.parseLine(allocator, response);
        parsed.deinit();
        return response;
    }

    pub fn notify(context: *anyopaque, line: []const u8) !void {
        const self: *ProcessServer = @ptrCast(@alignCast(context));
        try stdio.writeRawMessage(&self.stdin_writer.interface, line);
        try self.stdin_writer.interface.flush();
    }
};
