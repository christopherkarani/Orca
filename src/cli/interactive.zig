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
    // Print detected items (MVP numbered prompt, Phase 3)
    try stdout.writeAll("\nDetected agent hosts:\n");
    for (items, 0..) |item, i| {
        const marker = if (item.checked) "[x]" else "[ ]";
        try stdout.print("  {s} {d}) {s}\n", .{ marker, i + 1, item.label });
    }

    try stdout.writeAll("\nEnter numbers to integrate (e.g. 1 3), or 'all', or 'none':\n> ");

    var buf: [256]u8 = undefined;
    const n = try stdin.read(&buf);
    const input = std.mem.trimRight(u8, buf[0..n], "\r\n");

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
            .checked = item.checked, // start with incoming defaults
            .id = owned_id,
        });
    }

    const owned = try list.toOwnedSlice(allocator);
    // list is now empty (toOwnedSlice takes ownership); the errdefer above will not run on success.
    list = .empty; // prevent double-free in errdefer if somehow reached

    if (std.mem.eql(u8, input, "all")) {
        for (owned) |*item| item.checked = true;
        return .{ .items = owned, .confirmed = true };
    }

    if (std.mem.eql(u8, input, "none")) {
        for (owned) |*item| item.checked = false;
        return .{ .items = owned, .confirmed = true };
    }

    if (input.len == 0) {
        // Empty input: confirm whatever defaults were provided
        return .{ .items = owned, .confirmed = true };
    }

    // Parse space-separated numbers — explicit list means "select exactly these"
    for (owned) |*item| item.checked = false;
    var any_selected = false;
    var it = std.mem.splitScalar(u8, input, ' ');
    while (it.next()) |token| {
        const trimmed = std.mem.trim(u8, token, " \t");
        if (trimmed.len == 0) continue;
        const num = std.fmt.parseInt(usize, trimmed, 10) catch continue;
        if (num >= 1 and num <= owned.len) {
            owned[num - 1].checked = true;
            any_selected = true;
        }
    }

    if (!any_selected) {
        // All garbage / no valid numbers: fall back to incoming defaults
        for (items, 0..) |item, i| {
            owned[i].checked = item.checked;
        }
    }

    return .{ .items = owned, .confirmed = true };
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
        .{ .label = "Hermes", .id = "hermes", .checked = true },
        .{ .label = "Claude Code", .id = "claude", .checked = true },
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
    var out_buf: [256]u8 = undefined;
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

    var out_buf: [256]u8 = undefined;
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

// ---------------------------------------------------------------------------
// Phase 1: robust yes/no confirmation helper (TDD tests written FIRST)
// Replaces fragile single-char [0] == 'n' checks in uninstall/disable.
// Supports full words, case-insensitive, re-prompt on garbage, default on empty.
// Uses injected streams for full unit testability with fixedBufferStream.
// ---------------------------------------------------------------------------

/// Ask the user a yes/no question with proper validation and re-prompt.
/// Returns true only on explicit y/yes (case-insensitive).
/// Empty input uses default_yes.
/// On invalid input, prints guidance and loops.
pub fn askConfirm(
    stdout: anytype,
    stdin_reader: *std.io.Reader,
    prompt: []const u8,
    default_yes: bool,
) !bool {
    const default_indicator = if (default_yes) "[Y/n]" else "[y/N]";

    while (true) {
        try stdout.print("{s} {s} ", .{ prompt, default_indicator });

        const raw = stdin_reader.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.EndOfStream => return default_yes,
            error.StreamTooLong => {
                try stdout.writeAll("Please answer 'y' or 'n'.\n");
                continue;
            },
            error.ReadFailed => return error.ReadFailed,
        };
        const answer = std.mem.trimRight(u8, raw, "\r");
        // Use a separate buffer for lowercase to avoid aliasing issues
        var lower_buf: [128]u8 = undefined;
        const lowered = std.ascii.lowerString(&lower_buf, answer);

        if (answer.len == 0) return default_yes;

        if (std.mem.eql(u8, lowered[0..@min(lowered.len, 3)], "yes") or
            (answer.len == 1 and (answer[0] == 'y' or answer[0] == 'Y')))
        {
            return true;
        }
        if (std.mem.eql(u8, lowered[0..@min(lowered.len, 2)], "no") or
            (answer.len == 1 and (answer[0] == 'n' or answer[0] == 'N')))
        {
            return false;
        }

        try stdout.writeAll("Please answer 'y' or 'n'.\n");
    }
}

/// Convenience wrapper that uses real stdin (for production call sites).
pub fn askConfirmInteractive(stdout: anytype, prompt: []const u8, default_yes: bool) !bool {
    const stdin = std.fs.File.stdin();
    var reader_buf: [256]u8 = undefined;
    var reader = stdin.reader(&reader_buf);
    return askConfirm(stdout, &reader.interface, prompt, default_yes);
}

// TDD tests for askConfirm (use buffer streams to simulate user input exactly)
test "askConfirm rejects garbage and re-prompts" {
    var out_buf: [256]u8 = undefined;
    var out = std.io.fixedBufferStream(&out_buf);

    const input = "what\nn\n";
    var in_reader = std.io.Reader.fixed(input);

    const result = try askConfirm(out.writer(), &in_reader, "Fully uninstall Orca?", false);
    try std.testing.expectEqual(false, result);

    const written = out.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, written, "Please answer 'y' or 'n'.") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "canceled") == null); // caller prints canceled
}

test "askConfirm accepts yes and proceeds" {
    var out_buf: [128]u8 = undefined;
    var out = std.io.fixedBufferStream(&out_buf);

    const input = "yes\n";
    var in_reader = std.io.Reader.fixed(input);

    const result = try askConfirm(out.writer(), &in_reader, "Disable for all?", false);
    try std.testing.expectEqual(true, result);
}

test "askConfirm accepts empty as default (no)" {
    var out_buf: [64]u8 = undefined;
    var out = std.io.fixedBufferStream(&out_buf);

    const input = "\n"; // empty line
    var in_reader = std.io.Reader.fixed(input);

    const result = try askConfirm(out.writer(), &in_reader, "Proceed?", false);
    try std.testing.expectEqual(false, result);
}

test "askConfirm accepts Y/YES case variations" {
    var out_buf: [64]u8 = undefined;
    var out = std.io.fixedBufferStream(&out_buf);

    const input = "Y\n";
    var in_reader = std.io.Reader.fixed(input);

    const result = try askConfirm(out.writer(), &in_reader, "Test?", false);
    try std.testing.expectEqual(true, result);
}

// ---------------------------------------------------------------------------
// Phase 3: real numbered multi-select prompt (TDD tests written FIRST)
// Replaces the Phase 0 stub. Simple line-based (no raw mode). Robust across
// terminals. Accepts "1 3", "all", "none", or empty (keeps incoming defaults).
// ---------------------------------------------------------------------------

test "runMultiSelect renders list and parses selection" {
    const allocator = std.testing.allocator;
    var stdout_buf: [1024]u8 = undefined;
    const stdin_buf = "1 3\n";
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stdin_stream = std.io.fixedBufferStream(stdin_buf);

    const items = &[_]SelectionItem{
        .{ .label = "claude", .checked = true },
        .{ .label = "codex", .checked = true },
        .{ .label = "opencode", .checked = false },
    };

    var result = try runMultiSelect(
        allocator,
        items,
        stdout_stream.writer(),
        stdin_stream.reader(),
    );
    defer deinitMultiSelectResult(&result, allocator);

    try std.testing.expect(result.confirmed);
    try std.testing.expect(result.items[0].checked); // claude (1)
    try std.testing.expect(!result.items[1].checked); // codex (not listed)
    try std.testing.expect(result.items[2].checked); // opencode (3)

    const output = stdout_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Detected agent hosts:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "1) claude") != null);
}

test "runMultiSelect all selects everything" {
    const allocator = std.testing.allocator;
    var stdout_buf: [512]u8 = undefined;
    const stdin_buf = "all\n";
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stdin_stream = std.io.fixedBufferStream(stdin_buf);

    const items = &[_]SelectionItem{
        .{ .label = "claude", .checked = false },
        .{ .label = "codex", .checked = false },
    };

    var result = try runMultiSelect(
        allocator,
        items,
        stdout_stream.writer(),
        stdin_stream.reader(),
    );
    defer deinitMultiSelectResult(&result, allocator);

    try std.testing.expect(result.confirmed);
    try std.testing.expect(result.items[0].checked);
    try std.testing.expect(result.items[1].checked);
}

test "runMultiSelect none clears defaults" {
    const allocator = std.testing.allocator;
    var stdout_buf: [512]u8 = undefined;
    const stdin_buf = "none\n";
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stdin_stream = std.io.fixedBufferStream(stdin_buf);

    const items = &[_]SelectionItem{
        .{ .label = "claude", .checked = true },
        .{ .label = "codex", .checked = true },
    };

    var result = try runMultiSelect(
        allocator,
        items,
        stdout_stream.writer(),
        stdin_stream.reader(),
    );
    defer deinitMultiSelectResult(&result, allocator);

    try std.testing.expect(result.confirmed);
    try std.testing.expect(!result.items[0].checked);
    try std.testing.expect(!result.items[1].checked);
}

test "runMultiSelect empty input keeps defaults" {
    const allocator = std.testing.allocator;
    var stdout_buf: [512]u8 = undefined;
    const stdin_buf = "\n";
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stdin_stream = std.io.fixedBufferStream(stdin_buf);

    const items = &[_]SelectionItem{
        .{ .label = "claude", .checked = true },
        .{ .label = "codex", .checked = false },
    };

    var result = try runMultiSelect(
        allocator,
        items,
        stdout_stream.writer(),
        stdin_stream.reader(),
    );
    defer deinitMultiSelectResult(&result, allocator);

    try std.testing.expect(result.confirmed);
    try std.testing.expect(result.items[0].checked);
    try std.testing.expect(!result.items[1].checked);
}

test "runMultiSelect garbage input falls back to defaults" {
    const allocator = std.testing.allocator;
    var stdout_buf: [512]u8 = undefined;
    const stdin_buf = "xyz abc\n";
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stdin_stream = std.io.fixedBufferStream(stdin_buf);

    const items = &[_]SelectionItem{
        .{ .label = "claude", .checked = true },
        .{ .label = "codex", .checked = false },
    };

    var result = try runMultiSelect(
        allocator,
        items,
        stdout_stream.writer(),
        stdin_stream.reader(),
    );
    defer deinitMultiSelectResult(&result, allocator);

    try std.testing.expect(result.confirmed);
    try std.testing.expect(result.items[0].checked);
    try std.testing.expect(!result.items[1].checked);
}
