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
    for (items, 0..) |item, i| {
        owned[i] = .{
            .label = try allocator.dupe(u8, item.label),
            .checked = item.checked,
            .id = if (item.id) |id| try allocator.dupe(u8, id) else null,
        };
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

    // Simple line-based interactive loop (now using pure helpers for render + parse)
    const title = "Select hosts to integrate with Orca (toggle by number, c=confirm, q=cancel):";
    while (true) {
        const menu = try renderSelectionMenu(allocator, owned, title);
        defer allocator.free(menu);
        try stdout.writeAll(menu);

        var buf: [128]u8 = undefined;
        var n: usize = 0;
        if (is_interactive) {
            // Real TTY path: read directly from global stdin (File.read always available).
            // The passed stdin reader param is for test streams in non-tty path only.
            n = try std.fs.File.stdin().read(&buf);
        } else {
            n = try stdin.read(&buf);
        }
        const input = buf[0..n];

        const action = parseSelectionInput(input, owned.len);
        switch (action) {
            .confirm => {
                return .{
                    .items = owned,
                    .confirmed = true,
                };
            },
            .cancel => {
                return .{
                    .items = owned,
                    .confirmed = false,
                };
            },
            .toggle => |num| {
                owned[num - 1].checked = !owned[num - 1].checked;
            },
            .invalid => {
                try stdout.writeAll("  (invalid input — enter a number, 'c', or 'q')\n");
            },
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

/// Result of parsing a single line of user input in the line-based selector.
pub const SelectionAction = union(enum) {
    toggle: usize, // 1-based index to toggle
    confirm,
    cancel,
    invalid,
};

/// Pure helper: parse a trimmed user input line into a SelectionAction.
/// Supports numbers for toggle (1-based), 'c'/'C' confirm, 'q'/'Q' cancel.
pub fn parseSelectionInput(input: []const u8, num_items: usize) SelectionAction {
    const trimmed = std.mem.trim(u8, input, " \r\n\t");
    if (trimmed.len == 0) return .invalid;

    if (std.mem.eql(u8, trimmed, "c") or std.mem.eql(u8, trimmed, "C")) {
        return .confirm;
    }
    if (std.mem.eql(u8, trimmed, "q") or std.mem.eql(u8, trimmed, "Q")) {
        return .cancel;
    }

    const num = std.fmt.parseInt(usize, trimmed, 10) catch return .invalid;
    if (num >= 1 and num <= num_items) {
        return .{ .toggle = num };
    }
    return .invalid;
}

/// Pure helper: render the full interactive menu prompt into an allocated string.
/// Caller must free the returned slice.
pub fn renderSelectionMenu(allocator: std.mem.Allocator, items: []const SelectionItem, title: []const u8) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);

    try buf.writer(allocator).print("\n{s}\n\n", .{title});

    for (items, 0..) |item, i| {
        const checkbox = if (item.checked) "[x]" else "[ ]";
        try buf.writer(allocator).print("  {d}. {s} {s}\n", .{ i + 1, checkbox, item.label });
    }

    try buf.writer(allocator).writeAll("\n> ");
    return buf.toOwnedSlice(allocator);
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

// ---------------------------------------------------------------------------
// Phase 4 hardening: tests for pure helpers (render + parse) + line-based logic
// These lock in the improved testable structure for the interactive selector.
// Written to drive and verify the refactored render/parse path.
// ---------------------------------------------------------------------------

test "interactive: parseSelectionInput handles numbers, c, q, invalid, and trims" {
    try std.testing.expectEqual(SelectionAction{ .toggle = 1 }, parseSelectionInput("1", 5));
    try std.testing.expectEqual(SelectionAction{ .toggle = 3 }, parseSelectionInput(" 3 \n", 5));
    try std.testing.expectEqual(SelectionAction.confirm, parseSelectionInput("c", 3));
    try std.testing.expectEqual(SelectionAction.confirm, parseSelectionInput("C\r\n", 3));
    try std.testing.expectEqual(SelectionAction.cancel, parseSelectionInput("q", 2));
    try std.testing.expectEqual(SelectionAction.cancel, parseSelectionInput(" Q ", 2));
    try std.testing.expectEqual(SelectionAction.invalid, parseSelectionInput("", 3));
    try std.testing.expectEqual(SelectionAction.invalid, parseSelectionInput("0", 3));
    try std.testing.expectEqual(SelectionAction.invalid, parseSelectionInput("99", 3));
    try std.testing.expectEqual(SelectionAction.invalid, parseSelectionInput("abc", 3));
    try std.testing.expectEqual(SelectionAction.invalid, parseSelectionInput("1.5", 3));
}

test "interactive: renderSelectionMenu produces expected checkbox lines and prompt" {
    const allocator = std.testing.allocator;

    const items = [_]SelectionItem{
        .{ .label = "Hermes", .checked = true, .id = "hermes" },
        .{ .label = "OpenCode", .checked = false, .id = "opencode" },
    };

    const rendered = try renderSelectionMenu(allocator, &items, "Select hosts:");
    defer allocator.free(rendered);

    try std.testing.expect(std.mem.indexOf(u8, rendered, "Select hosts:") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "1. [x] Hermes") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "2. [ ] OpenCode") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "\n> ") != null);
}

test "interactive: runMultiSelect non-tty still respects input checked state (Phase 4 regression guard)" {
    const allocator = std.testing.allocator;

    const input = [_]SelectionItem{
        .{ .label = "Hermes", .checked = true, .id = "hermes" },
        .{ .label = "Claude", .checked = false, .id = "claude" },
    };

    var stdout_buf: [256]u8 = undefined;
    var stdin_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stdin_stream = std.io.fixedBufferStream(&stdin_buf);

    var result = try runMultiSelect(allocator, &input, stdout_stream.writer(), stdin_stream.reader());
    defer deinitMultiSelectResult(&result, allocator);

    try std.testing.expectEqual(true, result.confirmed);
    try std.testing.expectEqual(true, result.items[0].checked);
    try std.testing.expectEqual(false, result.items[1].checked);
}
