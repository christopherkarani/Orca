const std = @import("std");

const core = @import("aegis_core");
const request_mod = @import("approval_request.zig");
const decision_mod = @import("approval_decision.zig");

pub const ApprovalStore = struct {
    allocator: std.mem.Allocator,
    root: []u8,
    session_id: []u8,
    session_dir: []u8,
    approvals_path: []u8,
    index_path: []u8,

    pub fn init(allocator: std.mem.Allocator, workspace_root: []const u8, session_id: []const u8) !ApprovalStore {
        const edge_dir = try std.fs.path.join(allocator, &.{ workspace_root, ".aegis-edge" });
        defer allocator.free(edge_dir);
        const sessions_dir = try std.fs.path.join(allocator, &.{ edge_dir, "sessions" });
        defer allocator.free(sessions_dir);
        const session_dir = try std.fs.path.join(allocator, &.{ sessions_dir, session_id });
        errdefer allocator.free(session_dir);
        try std.fs.cwd().makePath(session_dir);
        const approvals_path = try std.fs.path.join(allocator, &.{ session_dir, "approvals.jsonl" });
        errdefer allocator.free(approvals_path);
        const index_path = try std.fs.path.join(allocator, &.{ session_dir, "approval-index.json" });
        errdefer allocator.free(index_path);
        ensureFile(approvals_path) catch |err| {
            allocator.free(session_dir);
            allocator.free(approvals_path);
            allocator.free(index_path);
            return err;
        };
        ensureIndex(index_path) catch |err| {
            allocator.free(session_dir);
            allocator.free(approvals_path);
            allocator.free(index_path);
            return err;
        };
        return .{
            .allocator = allocator,
            .root = try allocator.dupe(u8, workspace_root),
            .session_id = try allocator.dupe(u8, session_id),
            .session_dir = session_dir,
            .approvals_path = approvals_path,
            .index_path = index_path,
        };
    }

    pub fn deinit(self: *ApprovalStore) void {
        self.allocator.free(self.root);
        self.allocator.free(self.session_id);
        self.allocator.free(self.session_dir);
        self.allocator.free(self.approvals_path);
        self.allocator.free(self.index_path);
        self.* = undefined;
    }

    pub fn appendRequest(self: ApprovalStore, request: request_mod.ApprovalRequest) !void {
        var line: std.ArrayList(u8) = .empty;
        defer line.deinit(self.allocator);
        const writer = line.writer(self.allocator);
        try writer.writeByte('{');
        try writePair(writer, "event_type", "operator.approval_requested");
        try writeCommaPair(writer, "approval_request_id", request.approval_request_id);
        try writeCommaPair(writer, "vehicle_id", request.vehicle_id);
        try writeCommaPair(writer, "command_id", request.command_id);
        try writeCommaPair(writer, "command_type", @tagName(request.command_type));
        try writeCommaPair(writer, "policy_hash", request.policy_hash);
        try writeCommaPair(writer, "command_request_hash", request.command_request_hash);
        try writeCommaPair(writer, "state_snapshot_hash", request.state_snapshot_hash);
        try writeCommaPair(writer, "environment", @tagName(request.environment));
        try writer.print(",\"created_at_ms\":{d},\"expires_at_ms\":{d},\"max_uses\":{d}", .{ request.created_at_ms, request.expires_at_ms, request.scope.max_uses });
        try writeCommaPair(writer, "scope", @tagName(request.scope.kind));
        try writeCommaPair(writer, "reason", request.reason);
        try writer.writeAll(",\"limitations\":\"local-only approval store; simulation/SITL/bench evidence only; not real-flight readiness\"}\n");
        try appendBytes(self.allocator, self.approvals_path, line.items);
        try self.writeIndex(request.approval_request_id, "requested");
    }

    pub fn appendDecision(self: ApprovalStore, decision: decision_mod.ApprovalDecision) !void {
        const event_type = switch (decision.decision) {
            .approved => "operator.approval_granted",
            .denied => "operator.approval_denied",
            .expired => "operator.approval_expired",
            .revoked => "operator.approval_revoked",
            .invalid => "operator.approval_invalid",
        };
        try self.appendDecisionLike(event_type, decision.approval_request_id, decision.approval_decision_id, decision.operator_id, decision.timestamp_ms, if (decision.operator_note) |note| note else "");
        try self.writeIndex(decision.approval_request_id, @tagName(decision.decision));
    }

    pub fn revoke(self: ApprovalStore, approval_id: []const u8, operator_id: []const u8, timestamp_ms: i128) !void {
        try self.appendDecisionLike("operator.approval_revoked", approval_id, approval_id, operator_id, timestamp_ms, "revoked locally");
        try self.writeIndex(approval_id, "revoked");
    }

    pub fn appendUse(self: ApprovalStore, approval_id: []const u8, timestamp_ms: i128) !void {
        try self.appendDecisionLike("operator.approval_used", approval_id, approval_id, "aegis-edge", timestamp_ms, "approval use recorded");
    }

    pub fn appendCliEvent(self: ApprovalStore, event_type: []const u8, approval_id: []const u8, operator_id: []const u8, timestamp_ms: i128, note: []const u8) !void {
        try self.appendDecisionLike(event_type, approval_id, approval_id, operator_id, timestamp_ms, note);
    }

    fn appendDecisionLike(self: ApprovalStore, event_type: []const u8, approval_request_id: []const u8, approval_decision_id: []const u8, operator_id: []const u8, timestamp_ms: i128, note: []const u8) !void {
        var line: std.ArrayList(u8) = .empty;
        defer line.deinit(self.allocator);
        const writer = line.writer(self.allocator);
        try writer.writeByte('{');
        try writePair(writer, "event_type", event_type);
        try writeCommaPair(writer, "approval_request_id", approval_request_id);
        try writeCommaPair(writer, "approval_decision_id", approval_decision_id);
        try writeCommaPair(writer, "operator_id", operator_id);
        try writer.print(",\"timestamp_ms\":{d}", .{timestamp_ms});
        try writeCommaPair(writer, "note", note);
        try writer.writeAll(",\"limitations\":\"local-only approval store; not a long-term authorization database\"}\n");
        try appendBytes(self.allocator, self.approvals_path, line.items);
    }

    fn writeIndex(self: ApprovalStore, id: []const u8, status: []const u8) !void {
        var file = try std.fs.cwd().createFile(self.index_path, .{ .truncate = true });
        defer file.close();
        var buffer: [1024]u8 = undefined;
        var writer = file.writer(&buffer);
        try writer.interface.writeAll("{\"session_id\":");
        try core.core.util.writeJsonString(&writer.interface, self.session_id);
        try writer.interface.writeAll(",\"last_approval_id\":");
        try core.core.util.writeJsonString(&writer.interface, id);
        try writer.interface.writeAll(",\"status\":");
        try core.core.util.writeJsonString(&writer.interface, status);
        try writer.interface.writeAll(",\"local_only\":true,\"not_long_term_authorization\":true}\n");
        try writer.interface.flush();
        try file.sync();
    }
};

fn ensureFile(path: []const u8) !void {
    const file = std.fs.cwd().createFile(path, .{ .truncate = false }) catch |err| switch (err) {
        error.PathAlreadyExists => return,
        else => return err,
    };
    file.close();
}

fn ensureIndex(path: []const u8) !void {
    const file = std.fs.cwd().createFile(path, .{ .truncate = false }) catch |err| switch (err) {
        error.PathAlreadyExists => return,
        else => return err,
    };
    defer file.close();
    try file.writeAll("{\"local_only\":true,\"not_long_term_authorization\":true}\n");
}

fn appendBytes(allocator: std.mem.Allocator, path: []const u8, bytes: []const u8) !void {
    const existing = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    defer if (existing) |contents| allocator.free(contents);
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    if (existing) |contents| try file.writeAll(contents);
    try file.writeAll(bytes);
    try file.sync();
}

fn writePair(writer: anytype, key: []const u8, value: []const u8) !void {
    try core.core.util.writeJsonString(writer, key);
    try writer.writeByte(':');
    var redacted_buffer: [512]u8 = undefined;
    try core.core.util.writeJsonString(writer, core.api.redactStringBounded(value, &redacted_buffer));
}

fn writeCommaPair(writer: anytype, key: []const u8, value: []const u8) !void {
    try writer.writeByte(',');
    try writePair(writer, key, value);
}
