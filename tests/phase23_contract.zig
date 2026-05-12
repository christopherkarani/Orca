const std = @import("std");
const aegis_core = @import("aegis_core");
const aegis_edge = @import("aegis_edge");

const fake_secret = "fake_secret_value_phase23";

test "phase 23 docs define product split without real-flight readiness claims" {
    const paths = [_][]const u8{
        "README.md",
        "docs/README.md",
        "packages/core/README.md",
        "packages/cli/README.md",
        "packages/edge/README.md",
    };

    var combined_has_core = false;
    var combined_has_cli = false;
    var combined_has_edge = false;
    var edge_boundary_present = false;

    for (paths) |path| {
        const text = try std.fs.cwd().readFileAlloc(std.testing.allocator, path, 128 * 1024);
        defer std.testing.allocator.free(text);

        if (std.mem.indexOf(u8, text, "Aegis Core") != null) combined_has_core = true;
        if (std.mem.indexOf(u8, text, "Aegis CLI") != null) combined_has_cli = true;
        if (std.mem.indexOf(u8, text, "Aegis Edge") != null) combined_has_edge = true;
        if (std.mem.indexOf(u8, text, "must not be used for real flight") != null) edge_boundary_present = true;

        try expectNoUnsupportedReadinessClaim(text);
        try std.testing.expect(std.mem.indexOf(u8, text, fake_secret) == null);
    }

    try std.testing.expect(combined_has_core);
    try std.testing.expect(combined_has_cli);
    try std.testing.expect(combined_has_edge);
    try std.testing.expect(edge_boundary_present);
}

test "phase 23 edge placeholder never reports active command or flight enforcement" {
    for (aegis_edge.capabilityReports()) |report| {
        switch (report.capability) {
            .command_mediation,
            .mavlink_gateway,
            .flight_safety_enforcement,
            .operator_approval,
            .emergency_modes,
            .audit_replay,
            .safety_case_reports,
            .evidence_bundles,
            .redteam_fault_injection,
            .data_network_guard,
            .deployment_diagnostics,
            .arm64_packaging,
            .hardware_bench_no_actuation,
            .px4_adapter,
            .ardupilot_adapter,
            .real_flight_enforcement,
            .detect_and_avoid,
            .regulatory_certification,
            => try std.testing.expect(report.status != .scaffolded),
            .policy_scaffold,
            .policy_evaluation,
            .fake_adapter,
            => {},
        }
    }
}

test "phase 23 fake secret guardrail covers redaction before durable strings" {
    var buffer: [256]u8 = undefined;
    const redacted = aegis_core.audit.redact_bridge.redactStringBounded("OPENAI_API_KEY=" ++ fake_secret, &buffer);

    try std.testing.expect(std.mem.indexOf(u8, redacted, fake_secret) == null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "[REDACTED") != null);
}

test "policy schema matches runtime file-write and MCP server-scoped policy shapes" {
    const text = try std.fs.cwd().readFileAlloc(std.testing.allocator, "schemas/policy-v1.json", 128 * 1024);
    defer std.testing.allocator.free(text);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, text, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const properties = root.get("properties").?.object;
    const files_properties = properties.get("files").?.object.get("properties").?.object;
    try std.testing.expect(files_properties.get("write_mode") == null);

    const defs = root.get("$defs").?.object;
    const file_write_properties = defs.get("fileWriteRuleSet").?.object.get("properties").?.object;
    try std.testing.expect(file_write_properties.get("mode") != null);

    const mcp_properties = defs.get("mcpPolicy").?.object.get("properties").?.object;
    const servers = mcp_properties.get("servers").?.object;
    const server_properties = servers.get("additionalProperties").?.object.get("properties").?.object;
    try std.testing.expect(server_properties.get("tools") != null);

    var policy = try aegis_core.policy.load.parseFromSlice(std.testing.allocator,
        \\{"version":1,"mode":"strict","files":{"write":{"mode":"direct","allow":["docs/**"]}},"mcp":{"servers":{"github":{"tools":{"allow":["search_repositories"]}}}}}
    , "schema-alignment.json");
    defer policy.deinit();
    try std.testing.expectEqual(aegis_core.policy.schema.WriteMode.direct, policy.files.write_mode);
    try std.testing.expectEqualStrings("github.search_repositories", policy.mcp.allow[0]);
}

test "MCP manifest schema decision and risk enums match manifest parser behavior" {
    const text = try std.fs.cwd().readFileAlloc(std.testing.allocator, "schemas/mcp-manifest-v1.json", 128 * 1024);
    defer std.testing.allocator.free(text);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, text, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const defs = root.get("$defs").?.object;
    const decision_enum = defs.get("enforcingDecision").?.object.get("enum").?.array.items;
    try expectJsonStringInEnum(decision_enum, "allow");
    try expectJsonStringInEnum(decision_enum, "deny");
    try expectJsonStringInEnum(decision_enum, "ask");
    try expectJsonStringNotInEnum(decision_enum, "observe");

    const properties = root.get("properties").?.object;
    const tools_schema = properties.get("tools").?.object.get("additionalProperties").?.object;
    const tool_properties = tools_schema.get("properties").?.object;
    const risk_enum = tool_properties.get("risk").?.object.get("enum").?.array.items;
    try expectJsonStringInEnum(risk_enum, "unknown");
    try std.testing.expectEqualStrings("#/$defs/enforcingDecision", tool_properties.get("default").?.object.get("$ref").?.string);
}

fn expectNoUnsupportedReadinessClaim(text: []const u8) !void {
    const forbidden = [_][]const u8{
        "production-flight-ready",
        "flight ready",
        "real-flight-ready",
        "certified for flight",
        "regulatory approved",
        "active MAVLink",
        "active PX4",
        "active ArduPilot",
        "is an autopilot replacement",
        "as an autopilot replacement",
        "detect-and-avoid system",
    };

    for (forbidden) |phrase| {
        try std.testing.expect(std.mem.indexOf(u8, text, phrase) == null);
    }
}

fn expectJsonStringInEnum(items: []const std.json.Value, expected: []const u8) !void {
    for (items) |item| {
        if (item == .string and std.mem.eql(u8, item.string, expected)) return;
    }
    return error.TestUnexpectedResult;
}

fn expectJsonStringNotInEnum(items: []const std.json.Value, forbidden: []const u8) !void {
    for (items) |item| {
        if (item == .string and std.mem.eql(u8, item.string, forbidden)) return error.TestUnexpectedResult;
    }
}
