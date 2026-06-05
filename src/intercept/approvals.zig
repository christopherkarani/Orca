const std = @import("std");

const core = @import("orca_core").core;

pub const implemented = true;

pub const ApprovalChoice = enum {
    allow_once,
    allow_session,
    deny,
};

pub const Entry = struct {
    command: []const u8,
    reason: []const u8,
};

pub const SessionApprovals = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(Entry) = .empty,

    pub fn init(allocator: std.mem.Allocator) SessionApprovals {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *SessionApprovals) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.command);
            self.allocator.free(entry.reason);
        }
        self.entries.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn contains(self: *const SessionApprovals, command: []const u8) bool {
        for (self.entries.items) |entry| {
            if (std.mem.eql(u8, entry.command, command)) return true;
        }
        return false;
    }

    pub fn allowForSession(self: *SessionApprovals, command: []const u8, reason: []const u8) !void {
        if (self.contains(command)) return;
        try self.entries.append(self.allocator, .{
            .command = try self.allocator.dupe(u8, command),
            .reason = try self.allocator.dupe(u8, reason),
        });
    }
};

pub const PromptRequest = struct {
    command: []const u8,
    risk_class: []const u8,
    risk_reason: []const u8,
    policy_reason: []const u8,
    matched_rule: ?[]const u8 = null,
};

pub fn prompt(reader: *std.Io.Reader, writer: anytype, request: PromptRequest) !ApprovalChoice {
    try writer.writeAll(
        \\Orca wants your approval
        \\
        \\Command:
        \\
    );
    try writer.print("  {s}\n\nRisk:\n  {s}: {s}\n\nPolicy:\n  {s}\n", .{
        boundedForDisplay(request.command),
        request.risk_class,
        request.risk_reason,
        request.policy_reason,
    });
    if (request.matched_rule) |rule| try writer.print("  matched rule: {s}\n", .{rule});
    try writer.writeAll(
        \\
        \\Options:
        \\  [a] allow once
        \\  [A] allow for this session
        \\  [d] deny
        \\  [?] explain risk
        \\
        \\Choice:
    );

    while (true) {
        const line = (try reader.takeDelimiter('\n')) orelse return .deny;
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (std.mem.eql(u8, trimmed, "a")) return .allow_once;
        if (std.mem.eql(u8, trimmed, "A")) return .allow_session;
        if (std.mem.eql(u8, trimmed, "d") or trimmed.len == 0) return .deny;
        if (std.mem.eql(u8, trimmed, "?")) {
            try writer.print("\nRisk explanation: {s}\nChoice: ", .{request.risk_reason});
            continue;
        }
        try writer.writeAll("Choose a, A, d, or ?. Choice: ");
    }
}

pub fn applyApproval(
    allocator: std.mem.Allocator,
    decision: core.decision.Decision,
    command: []const u8,
    session_approvals: *SessionApprovals,
    choice: ApprovalChoice,
) !core.decision.Decision {
    switch (choice) {
        .deny => {
            const reason = try std.fmt.allocPrint(allocator, "user denied approval for command: {s}", .{boundedForDisplay(command)});
            return .{ .result = .deny, .reason = reason, .risk_score = decision.risk_score, .ci_may_proceed = false };
        },
        .allow_once => {
            const reason = try std.fmt.allocPrint(allocator, "user approved command once: {s}", .{boundedForDisplay(command)});
            return .{ .result = .allow, .reason = reason, .risk_score = decision.risk_score, .ci_may_proceed = true };
        },
        .allow_session => {
            try session_approvals.allowForSession(command, decision.reason);
            const reason = try std.fmt.allocPrint(allocator, "user approved command for this session: {s}", .{boundedForDisplay(command)});
            return .{ .result = .allow, .reason = reason, .risk_score = decision.risk_score, .ci_may_proceed = true };
        },
    }
}

fn boundedForDisplay(value: []const u8) []const u8 {
    return if (value.len > 512) value[0..512] else value;
}

test "session approval stores exact command for session scope" {
    var approvals = SessionApprovals.init(std.testing.allocator);
    defer approvals.deinit();
    try std.testing.expect(!approvals.contains("npm install"));
    try approvals.allowForSession("npm install", "package install");
    try std.testing.expect(approvals.contains("npm install"));
}

test "approval prompt supports explain and session allow" {
    var input: std.Io.Reader = .fixed("?\nA\n");
    var output_buf: [1024]u8 = undefined;
    var output_writer: std.Io.Writer = .fixed(&output_buf);
    const choice = try prompt(&input, &output_writer, .{
        .command = "npm install",
        .risk_class = "package_install",
        .risk_reason = "package install can run scripts",
        .policy_reason = "commands.default: ask",
    });
    try std.testing.expectEqual(ApprovalChoice.allow_session, choice);
    try std.testing.expect(std.mem.indexOf(u8, output_writer.buffered(), "Risk explanation") != null);
}
