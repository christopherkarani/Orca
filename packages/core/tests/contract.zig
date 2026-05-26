const std = @import("std");
const aegis_core = @import("aegis_core");

test "core package root does not expose product facade modules" {
    try std.testing.expectEqualStrings("core-boundary-isolation", aegis_core.phase);
    try std.testing.expect(@hasDecl(aegis_core, "api"));
    try std.testing.expect(@hasDecl(aegis_core, "abi"));

    try expectNoDecl(aegis_core, "core");
    try expectNoDecl(aegis_core, "policy");
    try expectNoDecl(aegis_core, "audit");
    try expectNoDecl(aegis_core, "intercept");
    try expectNoDecl(aegis_core, "redteam");
    try expectNoDecl(aegis_core, "capabilities");
    try expectNoDecl(aegis_core, "schemas");
}

test "core package sources do not import the monolithic product facade" {
    try expectFileDoesNotContain("packages/core/src/root.zig", "@import(\"aegis\")");
    try expectFileDoesNotContain("packages/core/src/abi.zig", "@import(\"aegis\")");
}

test "core engine module graph stays within core policy and audit" {
    try expectFileDoesNotContain("src/core_engine.zig", "intercept");
    try expectFileDoesNotContain("src/core_engine.zig", "redteam");
    try expectFileDoesNotContain("src/policy/evaluate.zig", "../intercept/");
    try expectFileDoesNotContain("src/core/boundary_api.zig", "@import(\"aegis\")");
}

test "public Policy handle is opaque and does not expose storage pointers" {
    try std.testing.expect(@typeInfo(aegis_core.api.Policy) == .@"opaque");
}

test "extension audit targets preserve extension kind in core events" {
    const ts = aegis_core.api.Timestamp.fromUnixSeconds(1_777_983_130);
    const event = try aegis_core.api.createAuditEvent(.{
        .session_id = try aegis_core.api.generateSessionId(ts),
        .event_id = try aegis_core.api.generateEventId(ts),
        .timestamp = ts,
        .event_type = .command_attempt,
        .actor = .{ .kind = .core, .display = "aegis-core" },
        .target = .{ .kind = .extension, .value = "edge.vehicle_state_read/vehicle-1" },
    });
    try std.testing.expectEqualStrings("extension", @tagName(event.target.kind));
}

test "core public actions are product neutral" {
    try std.testing.expect(@hasDecl(aegis_core.api, "Action"));
    const info = @typeInfo(aegis_core.api.Action).@"union";

    try expectUnionField(info, "env_read");
    try expectUnionField(info, "file_read");
    try expectUnionField(info, "file_write");
    try expectUnionField(info, "command_exec");
    try expectUnionField(info, "network_connect");
    try expectUnionField(info, "approval_decision");
    try expectUnionField(info, "staging_decision");
    try expectUnionField(info, "extension");

    try expectNoUnionField(info, "mcp_tool_call");
    try expectNoUnionField(info, "mcp_resource_read");
    try expectNoUnionField(info, "mcp_prompt_get");
    try expectNoUnionField(info, "mcp_sampling_request");
    try expectNoUnionField(info, "edge_vehicle_state_read");
    try expectNoUnionField(info, "edge_vehicle_command_request");
    try expectNoUnionField(info, "edge_mission_upload_request");
    try expectNoUnionField(info, "edge_geofence_evaluation_request");
    try expectNoUnionField(info, "edge_telemetry_egress_request");
    try expectNoUnionField(info, "edge_emergency_command_request");
    try expectNoUnionField(info, "edge_safety_envelope_evaluation_request");
}

test "core public event names exclude MCP Edge drone and SITL domains" {
    try std.testing.expect(@hasDecl(aegis_core.api, "EventType"));
    const fields = @typeInfo(aegis_core.api.EventType).@"enum".fields;

    try expectEnumField(fields, "session_start");
    try expectEnumField(fields, "command_attempt");
    try expectEnumField(fields, "network_connect_denied");

    inline for (fields) |field| {
        try std.testing.expect(std.mem.indexOf(u8, field.name, "mcp") == null);
        try std.testing.expect(std.mem.indexOf(u8, field.name, "edge") == null);
        try std.testing.expect(std.mem.indexOf(u8, field.name, "drone") == null);
        try std.testing.expect(std.mem.indexOf(u8, field.name, "vehicle") == null);
        try std.testing.expect(std.mem.indexOf(u8, field.name, "mavlink") == null);
        try std.testing.expect(std.mem.indexOf(u8, field.name, "px4") == null);
        try std.testing.expect(std.mem.indexOf(u8, field.name, "ardupilot") == null);
        try std.testing.expect(std.mem.indexOf(u8, field.name, "sitl") == null);
    }
}

test "core public API omits host plugin presets and direct MCP evaluator surface" {
    try expectNoDecl(aegis_core.api, "AgentPreset");
    try expectNoDecl(aegis_core.api, "loadAgentPreset");
    try expectNoDecl(aegis_core.api, "ExplainKind");
    try expectNoDecl(aegis_core.api, "explainAction");
    try expectNoDecl(aegis_core.api, "mcp");
    try expectNoDecl(aegis_core.api, "MCPPolicy");
}

test "core API evaluates generic command and extension actions" {
    var selected = try aegis_core.api.parsePolicyFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: observe
        \\commands:
        \\  allow:
        \\    - "echo *"
    , "core-boundary-policy.yaml");
    defer selected.deinit();

    var command_eval = try aegis_core.api.evaluateAction(
        std.testing.allocator,
        selected,
        .{ .command_exec = .{ .argv = &.{ "echo", "hello" } } },
        .{},
    );
    defer command_eval.deinit(std.testing.allocator);
    try std.testing.expectEqual(aegis_core.api.DecisionResult.allow, command_eval.decision.result);

    var extension_eval = try aegis_core.api.evaluateAction(
        std.testing.allocator,
        selected,
        .{ .extension = .{ .domain = "edge", .operation = "vehicle_state_read", .target = "vehicle-1" } },
        .{},
    );
    defer extension_eval.deinit(std.testing.allocator);
    try std.testing.expectEqual(aegis_core.api.DecisionResult.observe, extension_eval.decision.result);
    try std.testing.expect(std.mem.indexOf(u8, extension_eval.explanation, "extension edge.vehicle_state_read") != null);
    try std.testing.expect(std.mem.indexOf(u8, extension_eval.explanation, "drone") == null);
    try std.testing.expect(std.mem.indexOf(u8, extension_eval.explanation, "SITL") == null);
}

test "core API writes redacted audit events and verifies replay hash chain" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    const ts = aegis_core.api.Timestamp.fromUnixSeconds(1_777_983_130);
    const session: aegis_core.api.Session = .{
        .id = try aegis_core.api.generateSessionId(ts),
        .started_at = ts,
        .command = "echo",
        .args = &.{"fake_secret_value_phase24"},
        .workspace_root = root,
        .mode = .observe,
        .platform = aegis_core.api.detectOs(),
    };

    var writer = try aegis_core.api.createAuditWriter(std.testing.allocator, session);
    defer writer.deinit();
    const ev = try aegis_core.api.createAuditEvent(.{
        .session_id = session.id,
        .event_id = try aegis_core.api.generateEventId(ts),
        .timestamp = ts,
        .event_type = .command_attempt,
        .actor = .{ .kind = .core, .display = "aegis-core" },
        .target = .{ .kind = .command, .value = "echo fake_secret_value_phase24" },
        .decision = aegis_core.api.makeDecision(.{
            .result = .deny,
            .reason = "blocked fake_secret_value_phase24 before persistence",
        }),
    });
    try aegis_core.api.appendAuditEvent(&writer, ev);
    try writer.writeLastPointer();
    try aegis_core.api.writeAuditSummary(std.testing.allocator, writer.sessionDirPath(), .{
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

test "cli and edge compat facade still exposes full product core surface" {
    const compat_source = try std.fs.cwd().readFileAlloc(std.testing.allocator, "build.zig", 256 * 1024);
    defer std.testing.allocator.free(compat_source);
    try std.testing.expect(std.mem.indexOf(u8, compat_source, "aegis_core_product_compat_mod") != null);
    try std.testing.expect(std.mem.indexOf(u8, compat_source, "pub const actions = core.types") != null);
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

fn expectNoDecl(comptime namespace: type, comptime name: []const u8) !void {
    try std.testing.expect(!@hasDecl(namespace, name));
}

fn expectFileDoesNotContain(path: []const u8, needle: []const u8) !void {
    const text = try std.fs.cwd().readFileAlloc(std.testing.allocator, path, 128 * 1024);
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, needle) == null);
}

fn expectUnionField(info: std.builtin.Type.Union, comptime name: []const u8) !void {
    inline for (info.fields) |field| {
        if (std.mem.eql(u8, field.name, name)) return;
    }
    return error.TestUnexpectedResult;
}

fn expectNoUnionField(info: std.builtin.Type.Union, comptime name: []const u8) !void {
    inline for (info.fields) |field| {
        if (std.mem.eql(u8, field.name, name)) return error.TestUnexpectedResult;
    }
}

fn expectEnumField(fields: []const std.builtin.Type.EnumField, comptime name: []const u8) !void {
    inline for (fields) |field| {
        if (std.mem.eql(u8, field.name, name)) return;
    }
    return error.TestUnexpectedResult;
}
