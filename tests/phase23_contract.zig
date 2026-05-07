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
            .px4_adapter,
            .ardupilot_adapter,
            .real_flight_enforcement,
            .detect_and_avoid,
            .regulatory_certification,
            => try std.testing.expect(report.status != .scaffolded),
            .policy_scaffold,
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
