const std = @import("std");

/// Represents a single selectable item in a multi-select checkbox list.
/// Used by guided flows (e.g. host selection after install).
pub const SelectionItem = struct {
    /// Human-readable label (e.g. "Hermes", "Claude Code")
    label: []const u8,
    /// Whether the item is currently selected/checked.
    checked: bool = false,
    /// Optional stable identifier (e.g. "hermes", "claude").
    id: ?[]const u8 = null,
};

/// Result returned after a multi-select interaction completes.
pub const MultiSelectResult = struct {
    /// The final state of all items presented to the user.
    items: []SelectionItem,
    /// True if the user confirmed the selection (e.g. pressed Enter).
    /// False if the user canceled (e.g. Esc / q).
    confirmed: bool,
};

/// High-level entry point for a checkbox-style multi-select.
/// Phase 1 implementation: line-based interactive selector (works in all terminals).
/// User can type numbers to toggle items, then 'c' to confirm or 'q' to cancel.
/// Full raw-mode (arrows + spacebar) can be layered on top later.
pub fn runMultiSelect(
    allocator: std.mem.Allocator,
    items: []const SelectionItem,
    stdout: anytype,
    stdin: anytype,
) !MultiSelectResult {
    const owned = try allocator.alloc(SelectionItem, items.len);
    errdefer allocator.free(owned);

    var initialized: usize = 0;
    errdefer {
        for (owned[0..initialized]) |*it| {
            allocator.free(it.label);
            if (it.id) |id| allocator.free(id);
        }
    }

    for (items, 0..) |item, i| {
        const label = try allocator.dupe(u8, item.label);
        errdefer allocator.free(label);

        const maybe_id = if (item.id) |id_str| try allocator.dupe(u8, id_str) else null;
        errdefer if (maybe_id) |id_str| allocator.free(id_str);

        owned[i] = .{
            .label = label,
            .checked = item.checked,
            .id = maybe_id,
        };
        initialized = i + 1;
    }

    const stdin_file = std.fs.File.stdin();
    const is_interactive = stdin_file.isTty();

    if (!is_interactive) {
        // Non-interactive: return current state as confirmed (safe default for scripts)
        return .{
            .items = owned,
            .confirmed = true,
        };
    }

    // Simple line-based interactive loop
    while (true) {
        try stdout.writeAll("\nSelect hosts to integrate with Orca (toggle by number, c=confirm, q=cancel):\n\n");

        for (owned, 0..) |item, i| {
            const checkbox = if (item.checked) "[x]" else "[ ]";
            try stdout.print("  {d}. {s} {s}\n", .{ i + 1, checkbox, item.label });
        }

        try stdout.writeAll("\n> ");

        var buf: [128]u8 = undefined;
        const n = try stdin.read(&buf);
        const input = std.mem.trimRight(u8, buf[0..n], "\r\n ");

        if (input.len == 0) continue;

        if (std.mem.eql(u8, input, "c") or std.mem.eql(u8, input, "C")) {
            return .{
                .items = owned,
                .confirmed = true,
            };
        }
        if (std.mem.eql(u8, input, "q") or std.mem.eql(u8, input, "Q")) {
            return .{
                .items = owned,
                .confirmed = false,
            };
        }

        // Try to parse as number to toggle
        const num = std.fmt.parseInt(usize, input, 10) catch {
            try stdout.writeAll("  (invalid input — enter a number, 'c', or 'q')\n");
            continue;
        };

        if (num >= 1 and num <= owned.len) {
            owned[num - 1].checked = !owned[num - 1].checked;
        } else {
            try stdout.writeAll("  (number out of range)\n");
        }
    }
}

/// Frees memory owned by a MultiSelectResult.
pub fn deinitMultiSelectResult(result: *MultiSelectResult, allocator: std.mem.Allocator) void {
    for (result.items) |item| {
        allocator.free(item.label);
        if (item.id) |id| allocator.free(id);
    }
    allocator.free(result.items);
    result.* = undefined;
}

/// Pure helper: returns a new slice with only the checked items (labels only).
/// Useful for logging / summaries in guided flows.
pub fn getSelectedLabels(allocator: std.mem.Allocator, items: []const SelectionItem) ![][]const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    defer list.deinit(allocator);

    for (items) |item| {
        if (item.checked) {
            const owned = try allocator.dupe(u8, item.label);
            try list.append(allocator, owned);
        }
    }
    return list.toOwnedSlice(allocator);
}

// ---------------------------------------------------------------------------
// Phase 0 tests (TDD style - these will be expanded in later phases)
// ---------------------------------------------------------------------------

test "interactive: runMultiSelect Phase 0 stub returns all items checked and confirmed" {
    const allocator = std.testing.allocator;

    const input = [_]SelectionItem{
        .{ .label = "Hermes", .id = "hermes" },
        .{ .label = "Claude Code", .id = "claude" },
    };

    var stdout_buf: [256]u8 = undefined;
    var stdin_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stdin_stream = std.io.fixedBufferStream(&stdin_buf);

    var result = try runMultiSelect(allocator, &input, stdout_stream.writer(), stdin_stream.reader());
    defer deinitMultiSelectResult(&result, allocator);

    try std.testing.expectEqual(true, result.confirmed);
    try std.testing.expectEqual(@as(usize, 2), result.items.len);
    // In non-TTY path we now respect the input checked state (better semantics)
    try std.testing.expectEqual(false, result.items[0].checked); // input had default false
    try std.testing.expectEqual(false, result.items[1].checked);
    try std.testing.expectEqualStrings("Hermes", result.items[0].label);
}

test "interactive: getSelectedLabels returns only checked items" {
    const allocator = std.testing.allocator;

    const items = [_]SelectionItem{
        .{ .label = "OpenCode", .checked = true },
        .{ .label = "Codex", .checked = false },
        .{ .label = "OpenClaw", .checked = true },
    };

    const labels = try getSelectedLabels(allocator, &items);
    defer {
        for (labels) |l| allocator.free(l);
        allocator.free(labels);
    }

    try std.testing.expectEqual(@as(usize, 2), labels.len);
    try std.testing.expectEqualStrings("OpenCode", labels[0]);
    try std.testing.expectEqualStrings("OpenClaw", labels[1]);
}

test "interactive: deinitMultiSelectResult frees memory cleanly" {
    const allocator = std.testing.allocator;

    const input = [_]SelectionItem{
        .{ .label = "Test Host", .id = "test" },
    };

    // Use simple fixed buffers instead of null_* (Zig 0.15 Io model)
    var out_buf: [64]u8 = undefined;
    var in_buf: [64]u8 = undefined;
    var out = std.io.fixedBufferStream(&out_buf);
    var in_ = std.io.fixedBufferStream(&in_buf);

    var result = try runMultiSelect(allocator, &input, out.writer(), in_.reader());
    deinitMultiSelectResult(&result, allocator);

    // Reaching here without leaks (under testing allocator) means deinit works.
    try std.testing.expect(true);
}

// TDD test for allocator safety on error paths (was RED, now GREEN after errdefer).
// Uses an isolated GPA + FailingAllocator so we can directly assert zero leaked bytes
// even when runMultiSelect returns an error after partial initialization.
test "interactive: runMultiSelect never leaks on allocation failure during item construction" {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit(); // will assert no leaks at test end

    var failing_state = std.testing.FailingAllocator.init(gpa.allocator(), .{ .fail_index = 2 });
    const allocator = failing_state.allocator();

    const input = [_]SelectionItem{
        .{ .label = "Hermes", .id = "hermes" },
        .{ .label = "Claude Code", .id = "claude" },
    };

    var in_buf: [64]u8 = undefined;
    var in_ = std.io.fixedBufferStream(&in_buf);
    var out_buf: [256]u8 = undefined;
    var out = std.io.fixedBufferStream(&out_buf);

    const result = runMultiSelect(allocator, &input, out.writer(), in_.reader());
    try std.testing.expectError(error.OutOfMemory, result);

    // The errdefer in runMultiSelect must have released every partial dupe + the owned slice.
    // If any bytes remain live in the GPA, the defer _ = gpa.deinit() below will panic
    // (and the test will fail). Reaching here with no panic = GREEN.
}
