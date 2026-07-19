//! Phase B merge integration tests (kept out of evaluate.zig for file-size hygiene).

const std = @import("std");
const core = @import("../../core/public.zig");
const evaluate = @import("../evaluate.zig");
const load = @import("../load.zig");

test "structural args deny notify with to+body under effects.deny comms.message" {
    var policy = try load.parseFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: strict
        \\mcp:
        \\  default: allow
        \\  allow:
        \\    - "*"
        \\effects:
        \\  deny:
        \\    - comms.message
    , "structural.yaml");
    defer policy.deinit();

    const keys = [_][]const u8{ "to", "body" };
    var denied = try evaluate.toolWithArgs(&policy, "notify", .{ .keys = &keys }, std.testing.allocator);
    defer denied.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, denied.decision.result);
    try std.testing.expect(std.mem.indexOf(u8, denied.decision.reason, "structural.") != null);
    try std.testing.expect(std.mem.indexOf(u8, denied.decision.reason, "comms.message") != null);

    var allowed = try evaluate.toolWithArgs(&policy, "notify", .{}, std.testing.allocator);
    defer allowed.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.allow, allowed.decision.result);
}

test "network effect tag denies tagged host when effects deny publish" {
    var policy = try load.parseFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: strict
        \\network:
        \\  mode: open
        \\  default: allow
        \\effects:
        \\  deny:
        \\    - comms.publish
    , "net-effects.yaml");
    defer policy.deinit();

    var denied = try evaluate.network(&policy, "https://api.twitter.com/2/tweets", std.testing.allocator);
    defer denied.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, denied.decision.result);
    try std.testing.expect(std.mem.indexOf(u8, denied.decision.reason, "network_tag.") != null or
        std.mem.indexOf(u8, denied.decision.reason, "comms.publish") != null);

    var open_policy = try load.parseFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: strict
        \\network:
        \\  mode: open
        \\  default: allow
    , "net-open.yaml");
    defer open_policy.deinit();
    var allowed = try evaluate.network(&open_policy, "https://api.twitter.com/2/tweets", std.testing.allocator);
    defer allowed.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.allow, allowed.decision.result);
}

test "shell mailto bypass denies under effects deny comms.message" {
    var policy = try load.parseFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: strict
        \\commands:
        \\  default: allow
        \\effects:
        \\  deny:
        \\    - comms.message
    , "shell-effects.yaml");
    defer policy.deinit();

    var denied = try evaluate.command(&policy, "open 'mailto:x@y.com'", std.testing.allocator);
    defer denied.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, denied.decision.result);
    try std.testing.expect(std.mem.indexOf(u8, denied.decision.reason, "shell_bypass.") != null);

    var ok = try evaluate.command(&policy, "git status", std.testing.allocator);
    defer ok.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.allow, ok.decision.result);
}
