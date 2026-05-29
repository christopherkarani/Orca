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
/// In Phase 0 this is a stub that returns all items checked + confirmed=true.
/// Real terminal handling (raw mode, arrows, spacebar) is added in Phase 1.
pub fn runMultiSelect(
    allocator: std.mem.Allocator,
    items: []const SelectionItem,
    /// For future: injected stdout/stdin for testing and TTY detection.
    stdout: anytype,
    stdin: anytype,
) !MultiSelectResult {
    _ = stdout;
    _ = stdin;

    // Use ArrayList + errdefer for safe partial-init cleanup on dupe failure.
    // This guarantees zero leaks even if the Nth dupe fails after earlier successes.
    var list: std.ArrayList(SelectionItem) = .empty;
    errdefer {
        for (list.items) |item| {
            allocator.free(item.label);
            if (item.id) |id| allocator.free(id);
        }
        list.deinit(allocator);
    }

    for (items) |item| {
        const owned_label = try allocator.dupe(u8, item.label);
        errdefer allocator.free(owned_label);
        const owned_id = if (item.id) |id| try allocator.dupe(u8, id) else null;
        errdefer if (owned_id) |id| allocator.free(id);

        try list.append(allocator, .{
            .label = owned_label,
            .checked = true, // Phase 0 default: everything selected
            .id = owned_id,
        });
    }

    const owned = try list.toOwnedSlice(allocator);
    // list is now empty (toOwnedSlice takes ownership); the errdefer above will not run on success.
    list = .empty; // prevent double-free in errdefer if somehow reached

    return .{
        .items = owned,
        .confirmed = true,
    };
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
    try std.testing.expectEqual(true, result.items[0].checked);
    try std.testing.expectEqual(true, result.items[1].checked);
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

test "interactive: runMultiSelect does not leak on allocation failure mid-initialization (RED->GREEN safety test)" {
    // Use Zig's standard FailingAllocator to force OOM after a small number of allocations.
    // This exercises the error path in runMultiSelect where a dupe can fail after the slice alloc succeeded.
    var failing_inst = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    const failing_alloc = failing_inst.allocator();

    const input = [_]SelectionItem{
        .{ .label = "HostOne", .id = "one" },
        .{ .label = "HostTwo", .id = "two" },
    };

    var out_buf: [64]u8 = undefined;
    var in_buf: [64]u8 = undefined;
    var out = std.io.fixedBufferStream(&out_buf);
    var in_ = std.io.fixedBufferStream(&in_buf);

    const result = runMultiSelect(failing_alloc, &input, out.writer(), in_.reader());
    try std.testing.expectError(error.OutOfMemory, result);

    // RED: With current implementation, the slice for `owned` is allocated (alloc_index
    // advances), then the first dupe succeeds, second dupe triggers failure (fail_index hit),
    // but the already-allocated owned slice and first label are never freed -> leak.
    // The test asserts that on OOM path, everything that was allocated must have been freed.
    try std.testing.expect(failing_inst.has_induced_failure);
    try std.testing.expectEqual(failing_inst.allocated_bytes, failing_inst.freed_bytes);
}
