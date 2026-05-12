const std = @import("std");
const aegis_core = @import("aegis_core");

test "core package exposes shared policy audit replay redaction and capability surfaces" {
    try std.testing.expectEqualStrings("24-aegis-core-library-and-abi", aegis_core.phase);
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

test "phase 24 core API evaluates CLI and Edge actions through one policy path" {
    var selected = try aegis_core.api.parsePolicyFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: observe
        \\commands:
        \\  allow:
        \\    - "echo *"
        \\  deny:
        \\    - "rm -rf *"
        \\network:
        \\  default: ask
    , "phase24-core-api.yaml");
    defer selected.deinit();

    const cli_action: aegis_core.actions.Action = .{ .command_exec = .{ .argv = &.{ "echo", "hello" } } };
    var cli_eval = try aegis_core.api.evaluateAction(std.testing.allocator, &selected, cli_action, .{});
    defer cli_eval.deinit(std.testing.allocator);
    try std.testing.expectEqual(aegis_core.decision.DecisionResult.allow, cli_eval.decision.result);
    try std.testing.expect(cli_eval.matched_rule != null);
    try std.testing.expect(cli_eval.decision.ci_may_proceed);

    const edge_action: aegis_core.actions.Action = .{ .edge_vehicle_state_read = .{ .vehicle_id = "vehicle-1" } };
    var edge_eval = try aegis_core.api.evaluateAction(std.testing.allocator, &selected, edge_action, .{});
    defer edge_eval.deinit(std.testing.allocator);
    try std.testing.expectEqual(aegis_core.decision.DecisionResult.observe, edge_eval.decision.result);
    try std.testing.expect(edge_eval.matched_rule == null);
    try std.testing.expect(edge_eval.decision.ci_may_proceed);
    try std.testing.expect(std.mem.indexOf(u8, edge_eval.explanation, "edge.vehicle_state_read") != null);
}

test "phase 24 core API keeps CI non-interactive and deny beats allow" {
    var selected = try aegis_core.api.parsePolicyFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: strict
        \\commands:
        \\  allow:
        \\    - "rm *"
        \\  deny:
        \\    - "rm -rf *"
        \\  ask:
        \\    - "deploy *"
    , "phase24-ci.yaml");
    defer selected.deinit();

    var deny_eval = try aegis_core.api.evaluateAction(std.testing.allocator, &selected, .{ .command_exec = .{ .argv = &.{ "rm", "-rf", "tmp" } } }, .{});
    defer deny_eval.deinit(std.testing.allocator);
    try std.testing.expectEqual(aegis_core.decision.DecisionResult.deny, deny_eval.decision.result);

    var ci_eval = try aegis_core.api.evaluateAction(std.testing.allocator, &selected, .{ .command_exec = .{ .argv = &.{ "deploy", "prod" } } }, .{ .mode = .ci });
    defer ci_eval.deinit(std.testing.allocator);
    try std.testing.expectEqual(aegis_core.decision.DecisionResult.deny, ci_eval.decision.result);
    try std.testing.expect(!ci_eval.decision.requires_user);
    try std.testing.expect(!ci_eval.decision.ci_may_proceed);
}

test "phase 24 core API writes redacted audit events and verifies replay hash chain" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    const ts = aegis_core.core.time.Timestamp.fromUnixSeconds(1_777_983_130);
    const session: aegis_core.core.session.Session = .{
        .id = try aegis_core.core.session.generateSessionId(ts),
        .started_at = ts,
        .command = "echo",
        .args = &.{"fake_secret_value_phase24"},
        .workspace_root = root,
        .mode = .observe,
        .platform = aegis_core.core.platform.detectOs(),
    };

    var writer = try aegis_core.api.createAuditWriter(std.testing.allocator, session);
    defer writer.deinit();
    const ev = try aegis_core.api.createAuditEvent(.{
        .session_id = session.id,
        .event_id = try aegis_core.core.event.generateEventId(ts),
        .timestamp = ts,
        .event_type = .command_attempt,
        .actor = .{ .kind = .aegis, .display = "aegis" },
        .target = .{ .kind = .command, .value = "echo fake_secret_value_phase24" },
        .decision = aegis_core.api.makeDecision(.{
            .result = .deny,
            .reason = "blocked fake_secret_value_phase24 before persistence",
        }),
    });
    try aegis_core.api.appendAuditEvent(&writer, ev);
    try writer.writeLastPointer();
    try aegis_core.audit.summary.writeFiles(std.testing.allocator, writer.sessionDirPath(), .{
        .session = session,
        .status = .{ .exited = 1 },
        .event_count = writer.event_count,
        .final_event_hash = writer.finalHash().?,
        .policy = "phase24 fake_secret_value_phase24 policy",
    });

    var verify = try aegis_core.api.verifyReplay(std.testing.allocator, writer.sessionDirPath());
    defer verify.deinit(std.testing.allocator);
    try std.testing.expect(verify.ok);

    const events_path = try std.fs.path.join(std.testing.allocator, &.{ ".aegis", "sessions", session.id.slice(), "events.jsonl" });
    defer std.testing.allocator.free(events_path);
    const events = try tmp.dir.readFileAlloc(std.testing.allocator, events_path, 16 * 1024);
    defer std.testing.allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "fake_secret_value_phase24") == null);
    try std.testing.expect(std.mem.indexOf(u8, events, "[REDACTED:") != null);

    var replay = try aegis_core.api.loadReplay(std.testing.allocator, root, .{ .session = session.id.slice(), .verify = true });
    defer replay.deinit();
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);
    try aegis_core.api.writeReplayJson(out.writer(std.testing.allocator), replay);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "fake_secret_value_phase24") == null);
}

test "phase 24 schema registry exposes CLI and Edge reserved schemas" {
    const policy_schema = aegis_core.schemas.lookup(.policy) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("policy-v1", policy_schema.id);
    try std.testing.expect(std.mem.indexOf(u8, policy_schema.contents, "\"version\"") != null);
    try expectSchemaFileExists(policy_schema.path);

    const edge_policy_schema = aegis_core.schemas.lookup(.edge_policy) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("edge-policy-placeholder-v1", edge_policy_schema.id);
    try std.testing.expect(std.mem.indexOf(u8, edge_policy_schema.contents, "placeholder") != null);
    try expectSchemaFileExists(edge_policy_schema.path);

    const safety_report_schema = aegis_core.schemas.lookup(.safety_report) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("safety-report-placeholder-v1", safety_report_schema.id);
    try expectSchemaFileExists(safety_report_schema.path);
}

test "phase 24 experimental ABI skeleton compiles and documents instability" {
    try std.testing.expectEqualStrings("experimental", aegis_core.abi.stability);
    try std.testing.expect(std.mem.indexOf(u8, aegis_core.abi.documentation, "not stable v1") != null);

    const raw = "OPENAI_API_KEY=fake_secret_value_phase24";
    var output: [128]u8 = undefined;
    var written: usize = 0;
    const code = aegis_core.abi.aegis_core_redact(raw, raw.len, &output, output.len, &written);
    try std.testing.expectEqual(@as(c_int, 0), code);
    try std.testing.expect(std.mem.indexOf(u8, output[0..written], "fake_secret_value_phase24") == null);
}

fn expectSchemaFileExists(path: []const u8) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    file.close();
}
