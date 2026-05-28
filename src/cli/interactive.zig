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

    const owned = try allocator.alloc(SelectionItem, items.len);
    for (items, 0..) |item, i| {
        owned[i] = .{
            .label = try allocator.dupe(u8, item.label),
            .checked = true, // Phase 0 default: everything selected
            .id = if (item.id) |id| try allocator.dupe(u8, id) else null,
        };
    }

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
