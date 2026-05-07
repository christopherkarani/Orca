const std = @import("std");
const aegis_core = @import("aegis_core");

test "core package exposes shared policy audit replay redaction and capability surfaces" {
    try std.testing.expectEqualStrings("23-product-split-core-contract", aegis_core.phase);
    try std.testing.expectEqual(aegis_core.decision.DecisionResult.deny, aegis_core.policy.schema.DecisionValue.deny.toDecisionResult());
    try std.testing.expect(aegis_core.audit.implemented);
    try std.testing.expect(aegis_core.redteam.implemented);
    try std.testing.expect(aegis_core.capabilities.Feature.parse("policy_engine") != null);
}

test "core package redaction does not return raw synthetic fake secret values" {
    const raw = "OPENAI_API_KEY=fake_secret_value_phase23";
    const redacted = aegis_core.audit.redact_bridge.redactString(raw);

    try std.testing.expect(!std.mem.eql(u8, raw, redacted));
    try std.testing.expect(std.mem.indexOf(u8, redacted, "fake_secret_value_phase23") == null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "[REDACTED") != null);
}

test "core package preserves deny priority through policy evaluation" {
    var selected = try aegis_core.policy.load.parseFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: strict
        \\files:
        \\  read:
        \\    allow:
        \\      - "**"
        \\    deny:
        \\      - "secrets/**"
    , "phase23-core-test.yaml");
    defer selected.deinit();

    var evaluation = try aegis_core.policy.evaluate.fileRead(&selected, "secrets/token.txt", std.testing.allocator);
    defer evaluation.deinit(std.testing.allocator);

    try std.testing.expectEqual(aegis_core.decision.DecisionResult.deny, evaluation.decision.result);
}
