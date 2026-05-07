const std = @import("std");
const aegis = @import("aegis");

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return try std.fs.cwd().readFileAlloc(allocator, path, 256 * 1024);
}

test "phase25 release scripts package runtime assets referenced by CLI docs" {
    const sh = try readFile(std.testing.allocator, "scripts/build-release.sh");
    defer std.testing.allocator.free(sh);
    const ps1 = try readFile(std.testing.allocator, "scripts/build-release.ps1");
    defer std.testing.allocator.free(ps1);

    const required = [_][]const u8{ "docs", "policies", "schemas", "fixtures", "examples", "packages", "packaging", "scripts" };
    for (required) |name| {
        try std.testing.expect(std.mem.indexOf(u8, sh, name) != null);
        try std.testing.expect(std.mem.indexOf(u8, ps1, name) != null);
    }
    try std.testing.expect(std.mem.indexOf(u8, sh, "aegis-edge") != null);
    try std.testing.expect(std.mem.indexOf(u8, ps1, "aegis-edge") != null);
}

test "phase25 Windows package templates match nested zip layout" {
    const scoop = try readFile(std.testing.allocator, "packaging/scoop/aegis.json");
    defer std.testing.allocator.free(scoop);
    const winget = try readFile(std.testing.allocator, "packaging/winget/aegis.yaml");
    defer std.testing.allocator.free(winget);

    try std.testing.expect(std.mem.indexOf(u8, scoop, "aegis-v1.1.0-windows-amd64\\\\bin\\\\aegis.exe") != null);
    try std.testing.expect(std.mem.indexOf(u8, winget, "aegis-v1.1.0-windows-amd64\\bin\\aegis.exe") != null);
}

test "phase25 npm package is honest while checksum placeholders remain" {
    const package_json = try readFile(std.testing.allocator, "packaging/npm/package.json");
    defer std.testing.allocator.free(package_json);
    const wrapper = try readFile(std.testing.allocator, "packaging/npm/bin/aegis.js");
    defer std.testing.allocator.free(wrapper);
    const readme = try readFile(std.testing.allocator, "packaging/npm/README.md");
    defer std.testing.allocator.free(readme);

    try std.testing.expect(std.mem.indexOf(u8, package_json, "Placeholder npm launcher template") != null);
    try std.testing.expect(std.mem.indexOf(u8, wrapper, "checksum placeholders have not been replaced") != null);
    try std.testing.expect(std.mem.indexOf(u8, readme, "does not download a binary") != null);
}

test "phase25 MCP docs distinguish proxy stdin and list observation" {
    const readme = try readFile(std.testing.allocator, "README.md");
    defer std.testing.allocator.free(readme);
    const mcp_doc = try readFile(std.testing.allocator, "docs/mcp.md");
    defer std.testing.allocator.free(mcp_doc);

    try std.testing.expect(std.mem.indexOf(u8, readme, "fake_client.py | ./zig-out/bin/aegis mcp proxy") != null);
    try std.testing.expect(std.mem.indexOf(u8, mcp_doc, "waits for JSON-RPC on stdin") != null);
    try std.testing.expect(std.mem.indexOf(u8, mcp_doc, "policy-gates") != null);
    try std.testing.expect(std.mem.indexOf(u8, mcp_doc, "observes and audits `tools/list`, `resources/list`, and `prompts/list`") != null);
}

test "phase25 docs preserve Edge no-real-flight safety boundary" {
    const readme = try readFile(std.testing.allocator, "README.md");
    defer std.testing.allocator.free(readme);
    const edge_readme = try readFile(std.testing.allocator, "packages/edge/README.md");
    defer std.testing.allocator.free(edge_readme);

    try std.testing.expect(std.mem.indexOf(u8, readme, "Aegis Edge policy evaluation is active for local decisions only") != null);
    try std.testing.expect(std.mem.indexOf(u8, edge_readme, "Phase 27 implements Edge policy loading") != null);
    try std.testing.expect(std.mem.indexOf(u8, readme, "flight-ready") == null);
    try std.testing.expect(std.mem.indexOf(u8, edge_readme, "flight-ready") == null);
}

test "phase25 Core facade is the shared CLI policy audit replay and redaction surface" {
    try std.testing.expect(@hasDecl(aegis, "core_api"));

    var selected = try aegis.core_api.parsePolicyFromSlice(std.testing.allocator,
        \\version: 1
        \\mode: ci
        \\commands:
        \\  ask:
        \\    - "npm install *"
    , "phase25-core-api.yaml");
    defer selected.deinit();

    var evaluation = try aegis.core_api.evaluateAction(
        std.testing.allocator,
        &selected,
        .{ .command_exec = .{ .argv = &.{ "npm", "install", "left-pad" } } },
        .{},
    );
    defer evaluation.deinit(std.testing.allocator);

    try std.testing.expectEqual(aegis.core_api.DecisionResult.deny, evaluation.decision.result);
    const redacted = aegis.core_api.redactString("OPENAI_API_KEY=sk-fakeSyntheticOpenAIKey1234567890");
    try std.testing.expect(std.mem.indexOf(u8, redacted, "sk-fakeSynthetic") == null);
}
