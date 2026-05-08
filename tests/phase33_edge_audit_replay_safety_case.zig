const std = @import("std");
const edge = @import("aegis_edge");

test "phase 33 safety-case generation creates hash-chained edge session and reports" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root);

    var result = try edge.audit.safety_case.generate(allocator, .{
        .policy_path = "examples/edge/safety/policies/safety-strict.yaml",
        .scenario_path = "examples/edge/safety/scenarios/geofence-deny.yaml",
        .workspace_root = root,
        .now = edge.core.core.time.Timestamp.fromUnixSeconds(1_777_983_130),
    });
    defer result.deinit();

    try std.testing.expectEqual(edge.audit.safety_report.ScenarioResultStatus.passed, result.status);
    const last_path = try std.fs.path.join(allocator, &.{ root, ".aegis-edge", "last" });
    defer allocator.free(last_path);
    const last = try std.fs.cwd().readFileAlloc(allocator, last_path, 128);
    defer allocator.free(last);
    try std.testing.expect(std.mem.indexOf(u8, last, result.session_id) != null);

    const events_path = try std.fs.path.join(allocator, &.{ result.session_dir, "events.jsonl" });
    defer allocator.free(events_path);
    const events = try std.fs.cwd().readFileAlloc(allocator, events_path, 128 * 1024);
    defer allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"type\":\"edge.session_start\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"previous_hash\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"event_hash\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "sk-fakeSyntheticOpenAIKey1234567890") == null);

    const report_json_path = try std.fs.path.join(allocator, &.{ result.session_dir, "safety-report.json" });
    defer allocator.free(report_json_path);
    const report_json = try std.fs.cwd().readFileAlloc(allocator, report_json_path, 128 * 1024);
    defer allocator.free(report_json);
    try std.testing.expect(std.mem.indexOf(u8, report_json, "\"result_status\":\"passed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, report_json, "regulatory approval") != null);
    try std.testing.expect(std.mem.indexOf(u8, report_json, "\"environment_provenance\":\"fake_adapter\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, report_json, "\"policy_hash\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, report_json, "\"traceability\"") != null);

    const report_md_path = try std.fs.path.join(allocator, &.{ result.session_dir, "safety-report.md" });
    defer allocator.free(report_md_path);
    const report_md = try std.fs.cwd().readFileAlloc(allocator, report_md_path, 128 * 1024);
    defer allocator.free(report_md);
    try std.testing.expect(std.mem.indexOf(u8, report_md, "## Limitations") != null);
    try std.testing.expect(std.mem.indexOf(u8, report_md, "| Real flight | Not performed |") != null);
    try std.testing.expect(std.mem.indexOf(u8, report_md, "Aegis Edge is not a flight controller") != null);

    const verify = try edge.audit.safety_case.verify(allocator, root, "last");
    defer verify.deinit(allocator);
    try std.testing.expect(verify.ok);
}

test "phase 33 replay sections and evidence bundle are generated without secrets" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root);

    var result = try edge.audit.safety_case.generate(allocator, .{
        .policy_path = "examples/edge/px4/policies/px4-geofence-basic.yaml",
        .scenario_path = "examples/edge/px4/scenarios/waypoint-outside-geofence-deny.yaml",
        .workspace_root = root,
        .now = edge.core.core.time.Timestamp.fromUnixSeconds(1_777_983_130),
    });
    defer result.deinit();

    var replay_buf: [64 * 1024]u8 = undefined;
    var replay_stream = std.io.fixedBufferStream(&replay_buf);
    try edge.audit.edge_replay.write(replay_stream.writer(), allocator, root, .{ .session = "last", .verify = true });
    const replay = replay_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, replay, "Edge session:") != null);
    try std.testing.expect(std.mem.indexOf(u8, replay, "fake_px4") != null);
    try std.testing.expect(std.mem.indexOf(u8, replay, "Hash chain: verified") != null);
    try std.testing.expect(std.mem.indexOf(u8, replay, "sk-fakeSyntheticOpenAIKey1234567890") == null);

    replay_stream.reset();
    try edge.audit.edge_replay.write(replay_stream.writer(), allocator, root, .{ .session = "last", .commands = true });
    try std.testing.expect(std.mem.indexOf(u8, replay_stream.getWritten(), "\"commands\"") != null);

    replay_stream.reset();
    try edge.audit.edge_replay.write(replay_stream.writer(), allocator, root, .{ .session = "last", .findings = true });
    try std.testing.expect(std.mem.indexOf(u8, replay_stream.getWritten(), "\"findings\"") != null);

    const bundle_dir = try edge.audit.safety_case.bundle(allocator, root, "last");
    defer allocator.free(bundle_dir);
    const manifest_path = try std.fs.path.join(allocator, &.{ bundle_dir, "manifest.json" });
    defer allocator.free(manifest_path);
    const manifest = try std.fs.cwd().readFileAlloc(allocator, manifest_path, 128 * 1024);
    defer allocator.free(manifest);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "safety-report.json") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "policy-hash.txt") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "real-flight readiness") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "sk-fakeSyntheticOpenAIKey1234567890") == null);
}

test "phase 33 tamper delete and reorder fail Core verification" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root);

    var result = try edge.audit.safety_case.generate(allocator, .{
        .policy_path = "examples/edge/safety/policies/safety-strict.yaml",
        .scenario_path = "examples/edge/safety/scenarios/geofence-deny.yaml",
        .workspace_root = root,
        .now = edge.core.core.time.Timestamp.fromUnixSeconds(1_777_983_130),
    });
    defer result.deinit();

    const events_path = try std.fs.path.join(allocator, &.{ result.session_dir, "events.jsonl" });
    defer allocator.free(events_path);
    const original = try std.fs.cwd().readFileAlloc(allocator, events_path, 128 * 1024);
    defer allocator.free(original);

    var tampered = try allocator.dupe(u8, original);
    defer allocator.free(tampered);
    if (std.mem.indexOf(u8, tampered, "edge.session_start")) |index| tampered[index] = 'x';
    try writeFile(events_path, tampered);
    var verify_tampered = try edge.audit.safety_case.verify(allocator, root, "last");
    defer verify_tampered.deinit(allocator);
    try std.testing.expect(!verify_tampered.ok);

    try writeFile(events_path, original);
    const first_newline = std.mem.indexOfScalar(u8, original, '\n') orelse return error.TestUnexpectedResult;
    const second_newline = std.mem.indexOfScalarPos(u8, original, first_newline + 1, '\n') orelse return error.TestUnexpectedResult;
    var deleted = std.ArrayList(u8).empty;
    defer deleted.deinit(allocator);
    try deleted.appendSlice(allocator, original[0 .. first_newline + 1]);
    try deleted.appendSlice(allocator, original[second_newline + 1 ..]);
    try writeFile(events_path, deleted.items);
    var verify_deleted = try edge.audit.safety_case.verify(allocator, root, "last");
    defer verify_deleted.deinit(allocator);
    try std.testing.expect(!verify_deleted.ok);

    try writeFile(events_path, original);
    const third_newline = std.mem.indexOfScalarPos(u8, original, second_newline + 1, '\n') orelse return error.TestUnexpectedResult;
    var reordered = std.ArrayList(u8).empty;
    defer reordered.deinit(allocator);
    try reordered.appendSlice(allocator, original[0 .. first_newline + 1]);
    try reordered.appendSlice(allocator, original[second_newline + 1 .. third_newline + 1]);
    try reordered.appendSlice(allocator, original[first_newline + 1 .. second_newline + 1]);
    try reordered.appendSlice(allocator, original[third_newline + 1 ..]);
    try writeFile(events_path, reordered.items);
    var verify_reordered = try edge.audit.safety_case.verify(allocator, root, "last");
    defer verify_reordered.deinit(allocator);
    try std.testing.expect(!verify_reordered.ok);
}

test "phase 33 scenario classification refuses missing evidence as pass" {
    try std.testing.expectEqual(edge.audit.safety_report.ScenarioResultStatus.passed, edge.audit.safety_case.classifyScenarioResult(.deny, .deny, false, false, true));
    try std.testing.expectEqual(edge.audit.safety_report.ScenarioResultStatus.failed, edge.audit.safety_case.classifyScenarioResult(.allow, .deny, false, false, true));
    try std.testing.expectEqual(edge.audit.safety_report.ScenarioResultStatus.skipped, edge.audit.safety_case.classifyScenarioResult(null, .allow, true, false, true));
    try std.testing.expectEqual(edge.audit.safety_report.ScenarioResultStatus.unsupported, edge.audit.safety_case.classifyScenarioResult(null, .allow, false, true, true));
    try std.testing.expectEqual(edge.audit.safety_report.ScenarioResultStatus.inconclusive, edge.audit.safety_case.classifyScenarioResult(.deny, null, false, false, false));
}

fn writeFile(path: []const u8, bytes: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
    try file.sync();
}
