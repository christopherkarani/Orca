const std = @import("std");
const edge = @import("aegis_edge");

const dg = edge.data_guard;
const decision = edge.core.decision.DecisionResult;

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(allocator, path, 512 * 1024);
}

fn expectEvent(eval: dg.EgressEvaluation, event_type: []const u8) !void {
    try std.testing.expect(eval.hasAuditEvent(event_type));
}

fn expectFinding(eval: dg.EgressEvaluation, category: dg.network_finding.FindingCategory) !void {
    try std.testing.expect(eval.hasFindingCategory(category));
}

test "phase 35 data classification covers sensitive edge payload classes" {
    const allocator = std.testing.allocator;
    const cases = [_]struct {
        path: []const u8,
        class: dg.DataClass,
        sensitivity: dg.Sensitivity,
    }{
        .{ .path = "examples/edge/data-guard/payloads/vehicle-state.json", .class = .vehicle_state, .sensitivity = .medium },
        .{ .path = "examples/edge/data-guard/payloads/exact-geolocation.json", .class = .geolocation, .sensitivity = .high },
        .{ .path = "examples/edge/data-guard/payloads/mission-plan.json", .class = .mission_plan, .sensitivity = .high },
        .{ .path = "examples/edge/data-guard/payloads/video-stream-metadata.json", .class = .video_stream, .sensitivity = .high },
        .{ .path = "examples/edge/data-guard/payloads/fake-secret-payload.json", .class = .credential, .sensitivity = .critical },
    };
    for (cases) |case| {
        const text = try readFile(allocator, case.path);
        defer allocator.free(text);
        var result = try dg.classifyPayload(allocator, text);
        defer result.deinit();
        try std.testing.expect(result.hasClass(case.class));
        try std.testing.expectEqual(case.sensitivity, result.sensitivity);
    }

    var unknown = try dg.classifyPayload(allocator, "{\"opaque\":\"blob\"}");
    defer unknown.deinit();
    try std.testing.expect(unknown.hasClass(.unknown));
    try std.testing.expectEqual(dg.Sensitivity.unknown, unknown.sensitivity);
}

test "phase 35 endpoint classification fails closed for unknown and suspicious endpoints" {
    const allocator = std.testing.allocator;
    const cases = [_]struct {
        endpoint: dg.Endpoint,
        kind: dg.EndpointKind,
        suspicious: bool,
    }{
        .{ .endpoint = .{ .host = "127.0.0.1", .label = "ground_control", .port = 14550 }, .kind = .ground_control_station, .suspicious = false },
        .{ .endpoint = .{ .host = "10.0.0.10" }, .kind = .private_network, .suspicious = false },
        .{ .endpoint = .{ .host = "127.0.0.1", .label = "px4_sitl", .environment = "px4_sitl" }, .kind = .px4_sitl, .suspicious = false },
        .{ .endpoint = .{ .host = "127.0.0.1", .label = "fake_adapter", .provenance = "fake_adapter" }, .kind = .fake_adapter, .suspicious = false },
        .{ .endpoint = .{ .host = "203.0.113.44" }, .kind = .direct_ip, .suspicious = true },
        .{ .endpoint = .{ .host = "fake.webhook.site" }, .kind = .webhook, .suspicious = true },
        .{ .endpoint = .{ .host = "fake-tunnel.ngrok.io" }, .kind = .tunnel_service, .suspicious = true },
        .{ .endpoint = .{ .host = "telemetry.example.invalid" }, .kind = .unknown, .suspicious = true },
    };
    for (cases) |case| {
        var classified = try dg.classifyEndpoint(allocator, case.endpoint);
        defer classified.deinit();
        try std.testing.expectEqual(case.kind, classified.kind);
        try std.testing.expectEqual(case.suspicious, classified.suspicious);
    }

    var with_query = try dg.classifyEndpoint(allocator, .{ .host = "fake.webhook.site", .scheme = "https", .query = "token=fake_secret_value_phase35" });
    defer with_query.deinit();
    try std.testing.expect(std.mem.indexOf(u8, with_query.redacted_endpoint, "fake_secret_value_phase35") == null);
    try std.testing.expect(std.mem.indexOf(u8, with_query.redacted_endpoint, "query=[REDACTED]") != null);
}

test "phase 35 policy evaluation enforces endpoint data class and mode rules" {
    const allocator = std.testing.allocator;
    var loaded = try dg.loadPolicyFile(allocator, "examples/edge/data-guard/policies/data-guard-strict.yaml");
    defer loaded.deinit();

    const vehicle_state = try readFile(allocator, "examples/edge/data-guard/payloads/vehicle-state.json");
    defer allocator.free(vehicle_state);
    const ground_text = try readFile(allocator, "examples/edge/data-guard/endpoints/ground-control-local.json");
    defer allocator.free(ground_text);
    var ground = try dg.parseEndpointJsonOwned(allocator, ground_text);
    defer ground.deinit();
    var allowed = try dg.evaluateEgress(allocator, loaded.value, .{ .channel_kind = .mavlink_telemetry, .direction = .vehicle_to_agent, .payload = vehicle_state, .provenance = "fake_adapter" }, ground.value, .{ .mode = .strict });
    defer allowed.deinit();
    try std.testing.expectEqual(decision.allow, allowed.decision.result);
    try expectEvent(allowed, "data.egress_allowed");

    const mission = try readFile(allocator, "examples/edge/data-guard/payloads/mission-plan.json");
    defer allocator.free(mission);
    const webhook_text = try readFile(allocator, "examples/edge/data-guard/endpoints/webhook-site.json");
    defer allocator.free(webhook_text);
    var webhook = try dg.parseEndpointJsonOwned(allocator, webhook_text);
    defer webhook.deinit();
    var mission_eval = try dg.evaluateEgress(allocator, loaded.value, .{ .channel_kind = .mission_upload, .direction = .outbound, .payload = mission, .provenance = "fake_adapter" }, webhook.value, .{ .mode = .strict, .ci = true, .non_interactive = true });
    defer mission_eval.deinit();
    try std.testing.expectEqual(decision.deny, mission_eval.decision.result);
    try expectFinding(mission_eval, .exfiltration);
    try expectEvent(mission_eval, "data.egress_denied");

    const geolocation = try readFile(allocator, "examples/edge/data-guard/payloads/exact-geolocation.json");
    defer allocator.free(geolocation);
    const direct_text = try readFile(allocator, "examples/edge/data-guard/endpoints/unknown-direct-ip.json");
    defer allocator.free(direct_text);
    var direct = try dg.parseEndpointJsonOwned(allocator, direct_text);
    defer direct.deinit();
    var geo_eval = try dg.evaluateEgress(allocator, loaded.value, .{ .channel_kind = .mavlink_telemetry, .direction = .outbound, .payload = geolocation, .provenance = "fake_adapter" }, direct.value, .{ .mode = .strict, .ci = true, .non_interactive = true });
    defer geo_eval.deinit();
    try std.testing.expectEqual(decision.deny, geo_eval.decision.result);
    try std.testing.expect(geo_eval.redactions_required);
    try std.testing.expect(std.mem.indexOf(u8, geo_eval.redacted_payload, "37.0001234") == null);

    const secret = try readFile(allocator, "examples/edge/data-guard/payloads/fake-secret-payload.json");
    defer allocator.free(secret);
    var secret_eval = try dg.evaluateEgress(allocator, loaded.value, .{ .channel_kind = .mavlink_telemetry, .direction = .outbound, .payload = secret, .provenance = "fake_adapter" }, ground.value, .{ .mode = .strict });
    defer secret_eval.deinit();
    try std.testing.expectEqual(decision.deny, secret_eval.decision.result);
    try std.testing.expect(secret_eval.redactions_required);
    try std.testing.expect(std.mem.indexOf(u8, secret_eval.redacted_payload, "fake_secret_value_phase35") == null);

    const video = try readFile(allocator, "examples/edge/data-guard/payloads/video-stream-metadata.json");
    defer allocator.free(video);
    var video_eval = try dg.evaluateEgress(allocator, loaded.value, .{ .channel_kind = .video_stream, .direction = .outbound, .payload = video, .provenance = "fake_adapter" }, direct.value, .{ .mode = .strict });
    defer video_eval.deinit();
    try std.testing.expectEqual(decision.deny, video_eval.decision.result);

    const safety = try readFile(allocator, "examples/edge/data-guard/payloads/safety-report.json");
    defer allocator.free(safety);
    const customer_text = try readFile(allocator, "examples/edge/data-guard/endpoints/customer-endpoint.json");
    defer allocator.free(customer_text);
    var customer = try dg.parseEndpointJsonOwned(allocator, customer_text);
    defer customer.deinit();
    var safety_eval = try dg.evaluateEgress(allocator, loaded.value, .{ .channel_kind = .safety_case_report, .direction = .edge_to_customer_endpoint, .payload = safety, .provenance = "fake_adapter" }, customer.value, .{ .mode = .strict });
    defer safety_eval.deinit();
    try std.testing.expectEqual(decision.allow, safety_eval.decision.result);
    try expectEvent(safety_eval, "data.egress_allowed");
}

test "phase 35 deny beats allow and CI ask becomes deny while observe logs" {
    const allocator = std.testing.allocator;
    const policy = dg.telemetry_policy.Policy{
        .mode = .strict,
        .default_decision = .deny,
        .telemetry_rules = &.{.{ .channel = .mavlink_telemetry, .decision = .allow, .id = "telemetry.allow" }},
        .endpoint_rules = &.{
            .{ .host_pattern = "127.0.0.1", .decision = .allow, .id = "endpoint.allow" },
            .{ .host_pattern = "127.0.0.1", .decision = .deny, .id = "endpoint.deny" },
        },
        .data_class_rules = &.{.{ .class = .vehicle_state, .default_decision = .allow, .id = "data.allow.vehicle_state" }},
    };
    var denied = try dg.evaluateEgress(allocator, policy, .{ .channel_kind = .mavlink_telemetry, .payload = "{\"vehicle_state\":{\"mode\":\"guided\"}}", .provenance = "fake_adapter" }, .{ .host = "127.0.0.1" }, .{ .mode = .strict });
    defer denied.deinit();
    try std.testing.expectEqual(decision.deny, denied.decision.result);

    const ask_policy = dg.telemetry_policy.Policy{
        .mode = .ci,
        .default_decision = .ask,
        .telemetry_rules = &.{.{ .channel = .mission_upload, .decision = .ask, .id = "telemetry.ask" }},
        .endpoint_rules = &.{.{ .host_pattern = "*.customer.internal", .decision = .ask, .id = "endpoint.ask" }},
        .data_class_rules = &.{.{ .class = .mission_plan, .default_decision = .ask, .id = "data.ask.mission" }},
    };
    var ci_denied = try dg.evaluateEgress(allocator, ask_policy, .{ .channel_kind = .mission_upload, .payload = "{\"mission_plan\":{\"waypoints\":[]}}", .provenance = "fake_adapter" }, .{ .host = "review.customer.internal", .scheme = "https" }, .{ .mode = .ci, .ci = true, .non_interactive = true });
    defer ci_denied.deinit();
    try std.testing.expectEqual(decision.deny, ci_denied.decision.result);

    var observe_policy = dg.defaultSimulationPolicy();
    observe_policy.mode = .observe;
    var observed = try dg.evaluateEgress(allocator, observe_policy, .{ .channel_kind = .mission_upload, .payload = "{\"mission_plan\":{\"waypoints\":[{\"latitude\":37,\"longitude\":-122}]}}", .provenance = "fake_adapter" }, .{ .host = "fake.webhook.site", .scheme = "https" }, .{ .mode = .redteam });
    defer observed.deinit();
    try std.testing.expectEqual(decision.observe, observed.decision.result);
    try expectEvent(observed, "data.egress_observed");
    try expectFinding(observed, .exfiltration);
}

test "phase 35 exfiltration heuristics and redaction minimize persisted payloads" {
    const allocator = std.testing.allocator;
    var loaded = try dg.loadPolicyFile(allocator, "examples/edge/data-guard/policies/data-guard-strict.yaml");
    defer loaded.deinit();

    const long_endpoint_text = try readFile(allocator, "examples/edge/data-guard/endpoints/long-query-endpoint.json");
    defer allocator.free(long_endpoint_text);
    var long_endpoint = try dg.parseEndpointJsonOwned(allocator, long_endpoint_text);
    defer long_endpoint.deinit();
    var long_eval = try dg.evaluateEgress(allocator, loaded.value, .{ .channel_kind = .mavlink_telemetry, .payload = "{\"vehicle_state\":{\"mode\":\"guided\"}}", .provenance = "fake_adapter" }, long_endpoint.value, .{ .mode = .strict });
    defer long_eval.deinit();
    try expectFinding(long_eval, .exfiltration);

    var entropy_eval = try dg.evaluateEgress(allocator, loaded.value, .{ .channel_kind = .mavlink_telemetry, .payload = "{\"vehicle_state\":{\"mode\":\"guided\"}}", .provenance = "fake_adapter" }, .{ .host = "Zx9Qw7Er6Ty5Ui4Op3As2Df1.example.invalid", .scheme = "https" }, .{ .mode = .strict });
    defer entropy_eval.deinit();
    try expectFinding(entropy_eval, .exfiltration);
    try std.testing.expect(std.mem.indexOf(u8, entropy_eval.redacted_endpoint, "[REDACTED-HOST]") != null);

    var b64_eval = try dg.evaluateEgress(allocator, loaded.value, .{ .channel_kind = .mavlink_telemetry, .payload = "QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVo5ODc2NTQzMjEwQUJDREVGRw==", .provenance = "fake_adapter" }, .{ .host = "telemetry.example.invalid", .scheme = "https" }, .{ .mode = .strict });
    defer b64_eval.deinit();
    try expectFinding(b64_eval, .exfiltration);

    var media_redaction = try dg.redactPayload(allocator, "\x00\x01raw-frame-bytes", &.{.image_frame}, false);
    defer media_redaction.deinit();
    try std.testing.expect(!media_redaction.safe_to_persist);
    try std.testing.expect(std.mem.indexOf(u8, media_redaction.text, "raw-frame-bytes") == null);

    const query = try dg.payload_redaction.redactQuery(allocator, "token=fake_secret_value_phase35&mode=test");
    defer allocator.free(query);
    try std.testing.expect(std.mem.indexOf(u8, query, "fake_secret_value_phase35") == null);
}

test "phase 35 MAVLink PX4 and ArduPilot paths emit data guard audit events without changing mediation" {
    const allocator = std.testing.allocator;
    var loaded = try edge.policy.loadFile(allocator, "examples/edge/safety/policies/safety-strict.yaml", .{});
    defer loaded.deinit();
    const frame_bytes = try edge.mavlink.fake_transport.frameHeartbeatV1(allocator, .{ .seq = 1, .sysid = 42, .compid = 191 });
    defer allocator.free(frame_bytes);
    const frame = try edge.mavlink.framing.parseFrame(frame_bytes);

    var state = edge.redteam.fault_injection.baseState(&loaded.value, .fake_adapter, 1_000_000);
    var gateway_result = try edge.mavlink.gateway.processFrame(allocator, .{
        .mode = .simulation,
        .direction = .vehicle_to_ground,
        .vehicle_id = "edge-vehicle-1",
        .now_ms = 1_000_500,
        .command_source = .fake_adapter,
    }, &loaded.value, state, frame);
    defer gateway_result.deinit();
    try std.testing.expect(hasAuditEvent(gateway_result.audit.records.items, "data.egress_requested"));

    const px4_adapter = edge.px4.sitl_adapter.Adapter.init(.{ .environment = .fake_px4, .mode = .simulation, .now_ms = 1_000_500 });
    var px4_result = try px4_adapter.mediateFrame(allocator, &loaded.value, state, frame);
    defer px4_result.deinit();
    try std.testing.expect(hasAuditEvent(px4_result.audit.records.items, "data.egress_requested"));

    state.provenance = .fake_ardupilot_adapter;
    const ardupilot_adapter = edge.ardupilot.sitl_adapter.Adapter.init(.{ .environment = .fake_ardupilot, .mode = .simulation, .now_ms = 1_000_500 });
    var ardupilot_result = try ardupilot_adapter.mediateFrame(allocator, &loaded.value, state, frame);
    defer ardupilot_result.deinit();
    try std.testing.expect(hasAuditEvent(ardupilot_result.audit.records.items, "data.egress_requested"));
}

test "phase 35 red-team data guard fixtures pass and safety-case evidence includes network guard" {
    const allocator = std.testing.allocator;
    var data_set = try edge.redteam.runner.discover(allocator, .{ .category = .data_guard });
    defer data_set.deinit();
    try std.testing.expect(data_set.fixtures.len >= 12);
    var suite = try edge.redteam.runner.runSuite(allocator, data_set, .{ .output_dir = ".zig-cache/phase35-data-guard-redteam", .ci = true });
    defer suite.deinit();
    const totals = suite.totals();
    try std.testing.expectEqual(totals.required, totals.passed);
    try std.testing.expectEqual(@as(usize, 0), totals.failed);
    try std.testing.expectEqual(@as(usize, 0), totals.inconclusive);

    var generated = try edge.audit.safety_case.generate(allocator, .{
        .policy_path = "examples/edge/safety/policies/safety-strict.yaml",
        .scenario_path = "examples/edge/safety/scenarios/geofence-deny.yaml",
        .now = edge.core.core.time.Timestamp.fromUnixSeconds(1_700_000_000),
    });
    defer generated.deinit();
    const guard_path = try std.fs.path.join(allocator, &.{ generated.session_dir, "evidence", "data-network-guard.json" });
    defer allocator.free(guard_path);
    const guard_text = try readFile(allocator, guard_path);
    defer allocator.free(guard_text);
    try std.testing.expect(std.mem.indexOf(u8, guard_text, "data/network guard") != null);
    try std.testing.expect(std.mem.indexOf(u8, guard_text, "fake_secret_value_phase35") == null);
}

test "phase 35 command surface and docs preserve simulation safety boundaries" {
    const allocator = std.testing.allocator;
    const main = try readFile(allocator, "packages/edge/src/main.zig");
    defer allocator.free(main);
    const required_commands = [_][]const u8{
        "data doctor",
        "data classify --payload",
        "data evaluate --policy",
        "data redact --payload",
        "data scenario run --policy",
        "network explain --policy",
    };
    for (required_commands) |command| try std.testing.expect(std.mem.indexOf(u8, main, command) != null);

    const docs = [_][]const u8{
        "docs/edge/data-guard.md",
        "docs/edge/telemetry-policy.md",
        "docs/edge/network-egress.md",
        "docs/edge/data-classification.md",
        "docs/edge/exfiltration-detection.md",
        "docs/edge/sensitive-data-redaction.md",
        "docs/edge/safety-case.md",
        "docs/edge/redteam.md",
        "packages/edge/README.md",
    };
    for (docs) |path| {
        const text = try readFile(allocator, path);
        defer allocator.free(text);
        try std.testing.expect(std.mem.indexOf(u8, text, "data guard") != null or std.mem.indexOf(u8, text, "Data guard") != null or std.mem.indexOf(u8, text, "Data Guard") != null);
        try std.testing.expect(std.mem.indexOf(u8, text, "real-flight") != null);
        try std.testing.expect(std.mem.indexOf(u8, text, "certification") != null or std.mem.indexOf(u8, text, "Certification") != null);
        try std.testing.expect(std.mem.indexOf(u8, text, "detect-and-avoid") != null);
        try std.testing.expect(std.mem.indexOf(u8, text, "autopilot replacement") != null);
        try std.testing.expect(std.mem.indexOf(u8, text, "real hardware") != null or std.mem.indexOf(u8, text, "real-flight") != null);
    }
}

fn hasAuditEvent(records: []const edge.mavlink.audit.Record, event_type: []const u8) bool {
    for (records) |record| {
        if (std.mem.eql(u8, record.event_type, event_type)) return true;
    }
    return false;
}
