const std = @import("std");
const orca_core = @import("orca_core");

test "core package exposes engine policy audit replay redaction and schema surfaces only" {
    try std.testing.expectEqualStrings("core-engine-hard-split", orca_core.phase);
    try std.testing.expectEqual(orca_core.decision.DecisionResult.deny, orca_core.policy.schema.DecisionValue.deny.toDecisionResult());
    try std.testing.expect(orca_core.audit.implemented);
    try std.testing.expect(@hasDecl(orca_core, "api"));
    try std.testing.expect(@hasDecl(orca_core, "schemas"));
    try std.testing.expect(!@hasDecl(orca_core.core, "supervisor"));
    try std.testing.expect(!@hasDecl(orca_core, "cli"));
    try std.testing.expect(!@hasDecl(orca_core, "intercept"));
    try std.testing.expect(!@hasDecl(orca_core, "mcp"));
    try std.testing.expect(!@hasDecl(orca_core, "sandbox"));
    try std.testing.expect(!@hasDecl(orca_core, "redteam"));
    try std.testing.expect(!@hasDecl(orca_core, "capabilities"));
    try std.testing.expect(!@hasDecl(orca_core, "edge"));
}

test "core package sources do not depend on the monolithic product module" {
    try expectFileNotContains("packages/core/src/root.zig", "@import(\"orca\")");
    try expectFileNotContains("packages/core/src/api.zig", "@import(\"orca\")");
    try expectFileNotContains("packages/core/src/abi.zig", "@import(\"orca\")");
}

test "core README does not advertise removed Edge placeholder exports" {
    try expectFileNotContains("packages/core/README.md", "Edge placeholder");
    try expectFileNotContains("packages/core/README.md", "reserved Edge");
    try expectFileNotContains("packages/core/README.md", "safety-report placeholders");
}

test "core audit summaries do not hard-code Orca product copy" {
    try expectFileNotContains("src/audit/summary.zig", "Orca Session");
}

test "core supervisor does not depend on Orca sandbox backends" {
    try expectFileNotContains("src/core/supervisor.zig", "../sandbox/");
}

test "core package redaction does not return raw synthetic fake secret values" {
    const raw = "OPENAI_API_KEY=fake_secret_value_phase23";
    const redacted = orca_core.audit.redact_bridge.redactString(raw);

    try std.testing.expect(!std.mem.eql(u8, raw, redacted));
    try std.testing.expect(std.mem.indexOf(u8, redacted, "fake_secret_value_phase23") == null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "[REDACTED") != null);
}

test "core package preserves deny priority through policy evaluation" {
    var selected = try orca_core.policy.load.parseFromSlice(std.testing.allocator,
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

    var evaluation = try orca_core.policy.evaluate.fileRead(&selected, "secrets/token.txt", std.testing.allocator);
    defer evaluation.deinit(std.testing.allocator);

    try std.testing.expectEqual(orca_core.decision.DecisionResult.deny, evaluation.decision.result);
}

test "core API evaluates Orca actions through the shared policy path" {
    var selected = try orca_core.api.parsePolicyFromSlice(std.testing.allocator,
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

    const cli_action: orca_core.actions.Action = .{ .command_exec = .{ .argv = &.{ "echo", "hello" } } };
    var cli_eval = try orca_core.api.evaluateAction(std.testing.allocator, &selected, cli_action, .{});
    defer cli_eval.deinit(std.testing.allocator);
    try std.testing.expectEqual(orca_core.decision.DecisionResult.allow, cli_eval.decision.result);
    try std.testing.expect(cli_eval.matched_rule != null);
    try std.testing.expect(cli_eval.decision.ci_may_proceed);

}

test "core action and target types do not export Edge-only surfaces" {
    try expectUnionFieldsDoNotStartWith(orca_core.actions.Action, "edge_");
    try expectEnumFieldsDoNotStartWith(orca_core.core.types.TargetKind, "edge_");
}

test "core event types do not export Edge protocol or safety-case surfaces" {
    try expectEnumFieldsDoNotStartWith(orca_core.core.event.EventType, "edge_");
    try expectEnumFieldsDoNotStartWith(orca_core.core.event.EventType, "mavlink_");
    try expectEnumFieldsDoNotStartWith(orca_core.core.event.EventType, "px4_");
    try expectEnumFieldsDoNotStartWith(orca_core.core.event.EventType, "ardupilot_");
    try expectEnumFieldsDoNotStartWith(orca_core.core.event.EventType, "safety_case_");
    try expectEnumFieldsDoNotStartWith(orca_core.core.event.EventType, "data_");
    try expectEnumFieldsDoNotStartWith(orca_core.core.event.EventType, "telemetry_");
    try expectEnumFieldsDoNotStartWith(orca_core.core.event.EventType, "link_");
    try expectEnumFieldsDoNotStartWith(orca_core.core.event.EventType, "operator_");
    try expectEnumFieldsDoNotStartWith(orca_core.core.event.EventType, "health_");
}

test "phase 24 core API keeps CI non-interactive and deny beats allow" {
    var selected = try orca_core.api.parsePolicyFromSlice(std.testing.allocator,
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

    var deny_eval = try orca_core.api.evaluateAction(std.testing.allocator, &selected, .{ .command_exec = .{ .argv = &.{ "rm", "-rf", "tmp" } } }, .{});
    defer deny_eval.deinit(std.testing.allocator);
    try std.testing.expectEqual(orca_core.decision.DecisionResult.deny, deny_eval.decision.result);

    var ci_eval = try orca_core.api.evaluateAction(std.testing.allocator, &selected, .{ .command_exec = .{ .argv = &.{ "deploy", "prod" } } }, .{ .mode = .ci });
    defer ci_eval.deinit(std.testing.allocator);
    try std.testing.expectEqual(orca_core.decision.DecisionResult.deny, ci_eval.decision.result);
    try std.testing.expect(!ci_eval.decision.requires_user);
    try std.testing.expect(!ci_eval.decision.ci_may_proceed);
}

test "phase 24 core API writes redacted audit events and verifies replay hash chain" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    const ts = orca_core.core.time.Timestamp.fromUnixSeconds(1_777_983_130);
    const session: orca_core.core.session.Session = .{
        .id = try orca_core.core.session.generateSessionId(ts),
        .started_at = ts,
        .command = "echo",
        .args = &.{"fake_secret_value_phase24"},
        .workspace_root = root,
        .mode = .observe,
        .platform = orca_core.core.platform.detectOs(),
    };

    var writer = try orca_core.api.createAuditWriter(std.testing.allocator, session);
    defer writer.deinit();
    const ev = try orca_core.api.createAuditEvent(.{
        .session_id = session.id,
        .event_id = try orca_core.core.event.generateEventId(ts),
        .timestamp = ts,
        .event_type = .command_attempt,
        .actor = .{ .kind = .orca, .display = "orca" },
        .target = .{ .kind = .command, .value = "echo fake_secret_value_phase24" },
        .decision = orca_core.api.makeDecision(.{
            .result = .deny,
            .reason = "blocked fake_secret_value_phase24 before persistence",
        }),
    });
    try orca_core.api.appendAuditEvent(&writer, ev);
    try writer.writeLastPointer();
    try orca_core.audit.summary.writeFiles(std.testing.allocator, writer.sessionDirPath(), .{
        .session = session,
        .status = .{ .exited = 1 },
        .event_count = writer.event_count,
        .final_event_hash = writer.finalHash().?,
        .policy = "phase24 fake_secret_value_phase24 policy",
    });

    var verify = try orca_core.api.verifyReplay(std.testing.allocator, writer.sessionDirPath());
    defer verify.deinit(std.testing.allocator);
    try std.testing.expect(verify.ok);

    const events_path = try std.fs.path.join(std.testing.allocator, &.{ ".orca", "sessions", session.id.slice(), "events.jsonl" });
    defer std.testing.allocator.free(events_path);
    const events = try tmp.dir.readFileAlloc(std.testing.allocator, events_path, 16 * 1024);
    defer std.testing.allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "fake_secret_value_phase24") == null);
    try std.testing.expect(std.mem.indexOf(u8, events, "[REDACTED:") != null);

    var replay = try orca_core.api.loadReplay(std.testing.allocator, root, .{ .session = session.id.slice(), .verify = true });
    defer replay.deinit();
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);
    try orca_core.api.writeReplayJson(out.writer(std.testing.allocator), replay);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "fake_secret_value_phase24") == null);
}

test "phase 24 schema registry exposes Orca Core schemas only" {
    const policy_schema = orca_core.schemas.lookup(.policy) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("policy-v1", policy_schema.id);
    try std.testing.expect(std.mem.indexOf(u8, policy_schema.contents, "\"$schema\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, policy_schema.contents, "\"properties\"") != null);
    try expectSchemaFileExists(policy_schema.path);

    try std.testing.expect(orca_core.schemas.lookupId("edge-policy-placeholder-v1") == null);
    try std.testing.expect(orca_core.schemas.lookupId("edge-event-placeholder-v1") == null);
    try std.testing.expect(orca_core.schemas.lookupId("safety-report-placeholder-v1") == null);
}

test "phase 24 experimental ABI skeleton compiles and documents instability" {
    try std.testing.expectEqualStrings("experimental", orca_core.abi.stability);
    try std.testing.expect(std.mem.indexOf(u8, orca_core.abi.documentation, "not stable v1") != null);

    const raw = "OPENAI_API_KEY=fake_secret_value_phase24";
    var output: [128]u8 = undefined;
    var written: usize = 0;
    const code = orca_core.abi.core_redact(raw, raw.len, &output, output.len, &written);
    try std.testing.expectEqual(@as(c_int, 0), code);
    try std.testing.expect(std.mem.indexOf(u8, output[0..written], "fake_secret_value_phase24") == null);
}

fn expectSchemaFileExists(path: []const u8) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    file.close();
}

fn expectFileNotContains(path: []const u8, needle: []const u8) !void {
    const text = try std.fs.cwd().readFileAlloc(std.testing.allocator, path, 256 * 1024);
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, needle) == null);
}

fn expectUnionFieldsDoNotStartWith(comptime T: type, comptime prefix: []const u8) !void {
    inline for (@typeInfo(T).@"union".fields) |field| {
        try std.testing.expect(!std.mem.startsWith(u8, field.name, prefix));
    }
}

fn expectEnumFieldsDoNotStartWith(comptime T: type, comptime prefix: []const u8) !void {
    inline for (@typeInfo(T).@"enum".fields) |field| {
        try std.testing.expect(!std.mem.startsWith(u8, field.name, prefix));
    }
}
