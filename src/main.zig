const std = @import("std");
const builtin = @import("builtin");
const orca = @import("orca");

pub fn main() !void {
    if (builtin.os.tag == .windows) {
        setupWindowsConsole();
    }

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    var stdout_buffer: [4096]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);

    // Prime the color decision once at true CLI startup, before any command
    // dispatch or warm output. The module-level cache in style.zig is populated
    // as a side-effect; all subsequent maybeColor/useColor calls hit the fast
    // cached path. The existing call in cli.runWithCwd remains as a fallback
    // for library/direct usage.
    _ = orca.cli.style.useColor(stdout_writer);

    const shim_alias = if (builtin.os.tag == .windows) orca.intercept.commands.shimAliasFromExecutablePath(argv[0]) else null;
    const code = if (shim_alias) |alias|
        try runWindowsExecutableShim(allocator, alias, argv[1..], &stdout_writer.interface, &stderr_writer.interface)
    else
        try orca.cli.run(argv[1..], &stdout_writer.interface, &stderr_writer.interface);
    try stdout_writer.interface.flush();
    try stderr_writer.interface.flush();
    std.process.exit(code);
}

/// On legacy Windows consoles, enable UTF-8 output (code page 65001) and virtual
/// terminal processing so emoji and ANSI escape codes render correctly.
/// Errors are silently ignored — the console may already support these features.
fn setupWindowsConsole() void {
    if (builtin.os.tag != .windows) return;

    const kernel32 = std.os.windows.kernel32;
    const DWORD = std.os.windows.DWORD;
    const HANDLE = std.os.windows.HANDLE;

    const STD_OUTPUT_HANDLE: DWORD = 0xFFFFFFF5; // -11 as DWORD
    const ENABLE_VIRTUAL_TERMINAL_PROCESSING: DWORD = 0x0004;

    _ = kernel32.SetConsoleOutputCP(65001);

    const handle: ?HANDLE = kernel32.GetStdHandle(STD_OUTPUT_HANDLE);
    if (handle == null or handle.? == std.os.windows.INVALID_HANDLE_VALUE) return;

    var mode: DWORD = 0;
    if (kernel32.GetConsoleMode(handle.?, &mode) != 0) {
        _ = kernel32.SetConsoleMode(handle.?, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
    }
}

fn runWindowsExecutableShim(allocator: std.mem.Allocator, alias: []const u8, args: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var shim_argv = try allocator.alloc([]const u8, args.len + 3);
    defer allocator.free(shim_argv);
    shim_argv[0] = "exec";
    shim_argv[1] = "--";
    shim_argv[2] = alias;
    if (args.len > 0) @memcpy(shim_argv[3..], args);
    return orca.cli.shim.command(shim_argv, stdout, stderr);
}

test {
    _ = orca.cli;
}
