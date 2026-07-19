//! Phase B merge integration tests (kept out of evaluate.zig for file-size hygiene).

const std = @import("std");
const core = @import("../../core/public.zig");
const evaluate = @import("../evaluate.zig");
const load = @import("../load.zig");

test "pack mapped tool denied via effects.deny" {
    const packs = @import("packs.zig");

    const yaml =
        \\version: 1
        \\id: acme
        \\names:
        \\  send_acme_ping: comms.message
    ;
    var pack_set = try packs.PackSet.fromPack(
        std.testing.allocator,
        try packs.parsePackFromSlice(std.testing.allocator, yaml, "acme.yaml"),
    );
    defer pack_set.deinit();

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
    , "pack-effects.yaml");
    defer policy.deinit();

    var denied = try evaluate.toolWithPacks(&policy, "send_acme_ping", null, &pack_set, std.testing.allocator);
    defer denied.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, denied.decision.result);
    try std.testing.expect(std.mem.indexOf(u8, denied.decision.rule_id.?, "effects.deny") != null);
    try std.testing.expect(std.mem.indexOf(u8, denied.decision.reason, "pack.acme.") != null);
}

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

test "classifier local residual denies acme_mailer_job under effects.deny" {
    var policy = try load.parseFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: strict
        \\mcp:
        \\  default: allow
        \\  allow:
        \\    - "*"
        \\effects:
        \\  classifier: local
        \\  deny:
        \\    - comms.message
    , "residual-deny.yaml");
    defer policy.deinit();

    var denied = try evaluate.tool(&policy, "acme_mailer_job", std.testing.allocator);
    defer denied.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, denied.decision.result);
    try std.testing.expect(std.mem.indexOf(u8, denied.decision.reason, "classifier.local.") != null);
    try std.testing.expect(std.mem.indexOf(u8, denied.decision.reason, "comms.message") != null);
}

test "classifier off leaves residual tool on mcp surface allow" {
    var policy = try load.parseFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: strict
        \\mcp:
        \\  default: allow
        \\  allow:
        \\    - "*"
        \\effects:
        \\  classifier: off
        \\  deny:
        \\    - comms.message
    , "residual-off.yaml");
    defer policy.deinit();

    var allowed = try evaluate.tool(&policy, "acme_mailer_job", std.testing.allocator);
    defer allowed.deinit(std.testing.allocator);
    // No catalog/structural hit; classifier off → no residual → effects none → mcp allow.
    try std.testing.expectEqual(core.decision.DecisionResult.allow, allowed.decision.result);
}

test "classifier residual cannot allow past surface deny" {
    var policy = try load.parseFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: strict
        \\mcp:
        \\  default: deny
        \\effects:
        \\  classifier: local
        \\  allow:
        \\    - comms.message
    , "raise-only.yaml");
    defer policy.deinit();

    var denied = try evaluate.tool(&policy, "acme_mailer_job", std.testing.allocator);
    defer denied.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, denied.decision.result);
}

test "classifier unavailable fails closed in strict mode" {
    const classifier = @import("classifier.zig");
    classifier.testing_force_unavailable = true;
    defer classifier.testing_force_unavailable = false;

    var policy = try load.parseFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: strict
        \\mcp:
        \\  default: allow
        \\effects:
        \\  classifier: local
        \\  deny:
        \\    - comms.message
    , "fail-closed.yaml");
    defer policy.deinit();

    var denied = try evaluate.tool(&policy, "acme_mailer_job", std.testing.allocator);
    defer denied.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, denied.decision.result);
    try std.testing.expect(std.mem.indexOf(u8, denied.decision.reason, "effects.classifier unavailable") != null);
}

test "classifier unavailable does not deny in observe mode" {
    const classifier = @import("classifier.zig");
    classifier.testing_force_unavailable = true;
    defer classifier.testing_force_unavailable = false;

    var policy = try load.parseFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: observe
        \\mcp:
        \\  default: allow
        \\effects:
        \\  classifier: local
        \\  deny:
        \\    - comms.message
    , "fail-open-observe.yaml");
    defer policy.deinit();

    var allowed = try evaluate.tool(&policy, "acme_mailer_job", std.testing.allocator);
    defer allowed.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.allow, allowed.decision.result);
}

test "send_email still catalog deny under classifier local" {
    var policy = try load.parseFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: strict
        \\mcp:
        \\  default: allow
        \\effects:
        \\  classifier: local
        \\  deny:
        \\    - comms.message
    , "catalog-wins.yaml");
    defer policy.deinit();

    var denied = try evaluate.tool(&policy, "send_email", std.testing.allocator);
    defer denied.deinit(std.testing.allocator);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, denied.decision.result);
    try std.testing.expect(std.mem.indexOf(u8, denied.decision.reason, "catalog.") != null);
    try std.testing.expect(std.mem.indexOf(u8, denied.decision.reason, "classifier.local.") == null);
}
