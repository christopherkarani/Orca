const std = @import("std");
const edge = @import("aegis_edge");
const schema_documents = @import("edge_schema_documents");
const build_options = @import("build_options");

const usage =
    \\Aegis Edge policy evaluation
    \\
    \\Usage:
    \\  aegis-edge <command> [args]
    \\
    \\Commands:
    \\  doctor [assets|deployment|bench|arm64]
    \\                                 Show domain/schema/deployment capability status
    \\  deployment doctor              Show deployment diagnostics
    \\  deployment assets              Verify runtime assets from source/package context
    \\  deployment check --profile <profile.yaml>
    \\                                 Validate a bounded source/package/container/SITL/bench profile
    \\  deployment package-info        Print Edge package artifact manifest metadata
    \\  bench doctor                   Show non-flight bench mode diagnostics
    \\  bench check --policy <policy>  Validate bench policy/assets without hardware
    \\  bench report --policy <policy> --scenario <scenario>
    \\                                 Produce a bench-readiness report with no-flight disclaimers
    \\  ardupilot doctor               Show ArduPilot SITL simulation capability status
    \\  ardupilot scenario run --policy <policy> --scenario <scenario>
    \\                                 Run a deterministic fake-ArduPilot or opt-in SITL scenario
    \\  ardupilot observe --duration <seconds>
    \\                                 Observe deterministic fake-ArduPilot state unless SITL is explicitly enabled
    \\  ardupilot gateway --policy <policy> --endpoint <endpoint> --mode observe|enforce|simulation
    \\                                 Configure ArduPilot SITL mediation parameters without hardware assumptions
    \\  ardupilot test-fixture --name <fixture>
    \\                                 Print deterministic fake-ArduPilot fixture metadata
    \\  px4 doctor                     Show PX4 SITL simulation capability status
    \\  px4 scenario run --policy <policy> --scenario <scenario>
    \\                                 Run a deterministic fake-PX4 or opt-in SITL scenario
    \\  px4 observe --duration <seconds>
    \\                                 Observe deterministic fake-PX4 state unless SITL is explicitly enabled
    \\  px4 gateway --policy <policy> --endpoint <endpoint> --mode observe|enforce|simulation
    \\                                 Configure PX4 SITL mediation parameters without hardware assumptions
    \\  px4 test-fixture --name <fixture>
    \\                                 Print deterministic fake-PX4 fixture metadata
    \\  mavlink doctor                 Show MAVLink gateway capabilities and limitations
    \\  mavlink inspect-frame <file-or-hex>
    \\                                 Parse one MAVLink frame and print bounded metadata
    \\  mavlink classify <file-or-hex>  Classify and map one MAVLink frame where supported
    \\  mavlink simulate --policy <policy> --scenario <scenario>
    \\                                 Run a deterministic fake-transport scenario
    \\  mavlink gateway --fake --policy <policy>
    \\                                 Configure fake/in-memory gateway mode only
    \\  safety doctor                  Show flight safety enforcement capability status
    \\  safety check --policy <policy> Validate and compile a safety envelope
    \\  safety evaluate --policy <policy> --request <request.json> --state <state.json>
    \\                                 Evaluate a command request through the Phase 31 safety API
    \\  safety explain --policy <policy> --request <request.json> --state <state.json>
    \\                                 Explain one safety decision without forwarding commands
    \\  safety scenario run --policy <policy> --scenario <scenario>
    \\                                 Run a deterministic fake/simulation safety scenario
    \\  operator request --policy <policy> --request <request.json> --state <state.json>
    \\                                 Create a bounded local operator approval request
    \\  operator approve <approval-request-id> --scope once
    \\                                 Record a local explicit operator approval decision
    \\  operator deny <approval-request-id>
    \\                                 Record a local operator denial
    \\  operator list                  List local session approval audit records
    \\  operator revoke <approval-id>   Revoke a local approval record
    \\  emergency evaluate --policy <policy> --state <state.json> --reason <reason>
    \\                                 Evaluate policy-controlled emergency fallback behavior
    \\  emergency scenario run --policy <policy> --scenario <scenario>
    \\                                 Run a deterministic emergency decision scenario
    \\  data doctor                    Show Edge data/network guard status
    \\  data classify --payload <file> [--json]
    \\                                 Classify a local telemetry/data payload without sending it
    \\  data evaluate --policy <policy> --payload <payload.json> --endpoint <endpoint.json> [--json]
    \\                                 Evaluate local egress policy for a payload and endpoint
    \\  data redact --payload <file> [--json]
    \\                                 Print redacted/minimized payload output only
    \\  data scenario run --policy <policy> --scenario <scenario>
    \\                                 Run a deterministic local data guard scenario
    \\  network explain --policy <policy> --endpoint <endpoint.json> [--json]
    \\                                 Classify and explain one local endpoint
    \\  health [--json]                Show runtime health/watchdog status without hardware access
    \\  health doctor                  Show runtime-health diagnostics and limitations
    \\  health watch --duration <seconds>
    \\                                 Sample deterministic local runtime health without hardware access
    \\  health check --policy <policy>|--profile <profile>
    \\                                 Validate watchdog policy settings or bounded deployment profile
    \\  health report --session last   Show last local health evidence summary
    \\  health scenario run --policy <policy> --scenario <scenario>
    \\                                 Run a deterministic local health/watchdog scenario
    \\  watchdog doctor                Show watchdog diagnostics and limitations
    \\  watchdog simulate [--policy <policy>] --scenario <scenario>
    \\                                 Simulate one deterministic watchdog scenario
    \\  watchdog status --session last Show last local watchdog status placeholder
    \\  watchdog explain --finding <finding-id>
    \\                                 Explain a watchdog finding id
    \\  safety-case generate --session last
    \\                                 Regenerate/show the latest Edge safety-case evidence when available
    \\  safety-case generate --scenario <scenario> --policy <policy>
    \\                                 Generate hash-chained Edge audit evidence and JSON/Markdown safety reports
    \\  safety-case show --session last [--json]
    \\                                 Show a generated safety-case report
    \\  safety-case verify --session last
    \\                                 Verify the Edge audit hash chain for a safety-case session
    \\  safety-case bundle --session last
    \\                                 Create a local directory evidence bundle
    \\  replay --session last [--verify|--json|--findings|--commands|--approvals|--safety-case]
    \\                                 Replay a hash-chained Edge session under .aegis-edge
    \\  redteam [list|validate] [--ci] [--json] [--category <category>] [--fixture <id>]
    \\                                 Run deterministic simulation-only Edge red-team/fault-injection fixtures
    \\  redteam --environment fake_adapter|px4_sitl|ardupilot_sitl --report safety-case --output <dir>
    \\                                 Filter environments and generate scorecards/safety evidence
    \\  policy check <policy>          Validate an Edge policy file
    \\  policy explain <policy> <cmd>   Explain one command decision with fake state
    \\  policy evaluate <policy> --request <request.json> --state <state.json>
    \\                                 Evaluate a command request without sending it
    \\  schema list                    List versioned Edge schemas
    \\  schema print <schema-id>       Print a built-in schema document
    \\  help                           Show this help
    \\
    \\MAVLink fake transport is deterministic by default. PX4 and ArduPilot SITL are opt-in local simulation only. No real hardware, ROS2, or real-flight endpoint is opened by default.
    \\
;

const edge_policy_schema_document = schema_documents.edge_policy_v1;
const edge_event_schema_document = schema_documents.edge_event_v1;
const safety_report_schema_document = schema_documents.safety_report_v1;

pub fn main() !void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    var stdout_buffer: [4096]u8 = undefined;
    var stderr_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);

    const code = try run(argv[1..], &stdout_writer.interface, &stderr_writer.interface);
    try stdout_writer.interface.flush();
    try stderr_writer.interface.flush();
    std.process.exit(code);
}

pub fn run(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0) {
        try stdout.writeAll(usage);
        return 0;
    }

    const command = argv[0];
    if (std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h") or std.mem.eql(u8, command, "help")) {
        try stdout.writeAll(usage);
        return 0;
    }
    if (std.mem.eql(u8, command, "doctor")) return runDoctor(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "deployment")) return runDeployment(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "bench")) return runBench(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, command, "schema")) {
        return runSchema(argv[1..], stdout, stderr);
    }
    if (std.mem.eql(u8, command, "ardupilot")) {
        return runArduPilot(argv[1..], stdout, stderr);
    }
    if (std.mem.eql(u8, command, "px4")) {
        return runPx4(argv[1..], stdout, stderr);
    }
    if (std.mem.eql(u8, command, "mavlink")) {
        return runMavlink(argv[1..], stdout, stderr);
    }
    if (std.mem.eql(u8, command, "safety")) {
        return runSafety(argv[1..], stdout, stderr);
    }
    if (std.mem.eql(u8, command, "operator")) {
        return runOperator(argv[1..], stdout, stderr);
    }
    if (std.mem.eql(u8, command, "emergency")) {
        return runEmergency(argv[1..], stdout, stderr);
    }
    if (std.mem.eql(u8, command, "data")) {
        return runData(argv[1..], stdout, stderr);
    }
    if (std.mem.eql(u8, command, "network")) {
        return runNetwork(argv[1..], stdout, stderr);
    }
    if (std.mem.eql(u8, command, "health")) {
        return runHealth(argv[1..], stdout, stderr);
    }
    if (std.mem.eql(u8, command, "watchdog")) {
        return runWatchdog(argv[1..], stdout, stderr);
    }
    if (std.mem.eql(u8, command, "safety-case")) {
        return runSafetyCase(argv[1..], stdout, stderr);
    }
    if (std.mem.eql(u8, command, "replay")) {
        return runEdgeReplay(argv[1..], stdout, stderr);
    }
    if (std.mem.eql(u8, command, "redteam")) {
        return runRedteam(argv[1..], stdout, stderr);
    }
    if (std.mem.eql(u8, command, "policy")) {
        return runPolicy(argv[1..], stdout, stderr);
    }

    try stderr.print("aegis-edge: unknown command '{s}'. Run 'aegis-edge --help' for usage.\n", .{command});
    return 64;
}

fn runDoctor(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0) {
        try edge.doctor(stdout);
        return 0;
    }
    if (argv.len != 1) return usageError(stderr, "aegis-edge doctor: expected optional assets, deployment, bench, or arm64.\n");
    if (std.mem.eql(u8, argv[0], "assets")) return runDeploymentAssets(&.{}, stdout, stderr);
    if (std.mem.eql(u8, argv[0], "deployment")) return runDeploymentDoctor(&.{}, stdout, stderr);
    if (std.mem.eql(u8, argv[0], "bench")) return runBenchDoctor(&.{}, stdout, stderr);
    if (std.mem.eql(u8, argv[0], "arm64")) {
        try writeArm64Doctor(stdout);
        return 0;
    }
    try stderr.print("aegis-edge doctor: unknown doctor topic '{s}'.\n", .{argv[0]});
    return 64;
}

fn runDeployment(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0) return usageError(stderr, "aegis-edge deployment: expected doctor, check, package-info, or assets.\n");
    if (std.mem.eql(u8, argv[0], "doctor")) return runDeploymentDoctor(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "assets")) return runDeploymentAssets(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "check")) return runDeploymentCheck(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "package-info")) return runDeploymentPackageInfo(argv[1..], stdout, stderr);
    try stderr.print("aegis-edge deployment: unknown subcommand '{s}'.\n", .{argv[0]});
    return 64;
}

fn runDeploymentDoctor(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var json = false;
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--json")) json = true else return usageError(stderr, "aegis-edge deployment doctor: expected optional --json.\n");
    }
    const arch = edge.deployment.currentTargetArch();
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    var assets = try edge.deployment.doctorAssets(gpa_state.allocator());
    defer assets.deinit();
    if (json) {
        try stdout.print("{{\"status\":\"active\",\"phase\":", .{});
        try edge.core.core.util.writeJsonString(stdout, edge.deployment.phase);
        try stdout.print(",\"target_arch\":\"{s}\",\"asset_status\":\"{s}\",\"limitations\":", .{ arch.toString(), assets.overall().toString() });
        try edge.core.core.util.writeJsonString(stdout, edge.deployment.no_flight_disclaimer);
        try stdout.writeAll("}\n");
        return 0;
    }
    try stdout.print("Deployment diagnostics: active\nPhase: {s}\nTarget architecture: {s} ({s})\nRuntime assets: {s}\n", .{ edge.deployment.phase, arch.toString(), arch.supportStatus().toString(), assets.overall().toString() });
    try stdout.writeAll("Supported release targets: linux-amd64, linux-arm64. linux-armv7 is unsupported in this phase.\n");
    try stdout.writeAll("Modes: source, packaged, container, simulation, bench, edge_device evaluation only.\n");
    try stdout.print("Limitations: {s}\n", .{edge.deployment.no_flight_disclaimer});
    return 0;
}

fn runDeploymentAssets(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var json = false;
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--json")) json = true else return usageError(stderr, "aegis-edge deployment assets: expected optional --json.\n");
    }
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    var report = try edge.deployment.doctorAssets(gpa_state.allocator());
    defer report.deinit();
    if (json) {
        try stdout.print("{{\"status\":\"{s}\",\"assets\":[", .{report.overall().toString()});
        for (report.checks, 0..) |check, index| {
            if (index > 0) try stdout.writeByte(',');
            try stdout.print("{{\"name\":", .{});
            try edge.core.core.util.writeJsonString(stdout, check.name);
            try stdout.print(",\"path\":", .{});
            try edge.core.core.util.writeJsonString(stdout, check.path);
            try stdout.print(",\"status\":\"{s}\",\"required\":{}}}", .{ check.status.toString(), check.required });
        }
        try stdout.writeAll("]}\n");
        return if (report.overall() == .missing) 65 else 0;
    }
    try stdout.print("Runtime assets: {s}\n", .{report.overall().toString()});
    for (report.checks) |check| {
        try stdout.print("  {s}: {s} - {s}\n", .{ check.status.toString(), check.name, check.path });
    }
    try stdout.writeAll("Asset lookup supports source-tree and packaged-release relative paths; missing required assets fail deployment checks.\n");
    return if (report.overall() == .missing) 65 else 0;
}

fn runDeploymentCheck(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var profile_path: ?[]const u8 = null;
    var json = false;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--profile")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge deployment check: --profile requires a file.\n");
            profile_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--json")) {
            json = true;
        } else {
            try stderr.print("aegis-edge deployment check: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected = profile_path orelse return usageError(stderr, "aegis-edge deployment check: missing --profile.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var profile = edge.deployment.loadProfileFile(allocator, selected) catch |err| {
        try stderr.print("Deployment profile invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer profile.deinit();
    const check = edge.deployment.checkProfile(profile);
    const policy_status = edge.deployment.validatePolicy(profile.policy_path, allocator);
    if (json) {
        try stdout.print("{{\"profile_id\":", .{});
        try edge.core.core.util.writeJsonString(stdout, profile.id);
        try stdout.print(",\"status\":\"{s}\",\"target_arch\":\"{s}\",\"mode\":\"{s}\",\"environment\":\"{s}\",\"policy_status\":\"{s}\",\"reason\":", .{ check.status.toString(), profile.target_arch.toString(), profile.mode.toString(), profile.environment.toString(), policy_status.toString() });
        try edge.core.core.util.writeJsonString(stdout, check.reason);
        try stdout.writeAll("}\n");
        return if (check.status == .active and policy_status == .active) 0 else 65;
    }
    try stdout.print("Deployment profile: {s}\nStatus: {s}\nReason: {s}\nTarget: {s} / {s}\nMode: {s}\nEnvironment: {s}\nPolicy: {s} ({s})\nScenario: {s}\nNetwork mode: {s}\n", .{ profile.id, check.status.toString(), check.reason, profile.os, profile.target_arch.toString(), profile.mode.toString(), profile.environment.toString(), profile.policy_path, policy_status.toString(), profile.scenario_path, profile.network_mode.toString() });
    if (profile.mavlink_endpoint) |endpoint| try stdout.print("MAVLink endpoint: {s}\n", .{endpoint});
    try stdout.print("Limitations: {s}\n", .{edge.deployment.no_flight_disclaimer});
    return if (check.status == .active and policy_status == .active) 0 else 65;
}

fn runDeploymentPackageInfo(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var arch = edge.deployment.currentTargetArch();
    var json = false;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--arch")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge deployment package-info: --arch requires a value.\n");
            arch = edge.deployment.TargetArch.parse(argv[index]);
        } else if (std.mem.eql(u8, argv[index], "--json")) {
            json = true;
        } else {
            try stderr.print("aegis-edge deployment package-info: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    const package_status = arch.packageStatus();
    const info: edge.deployment.PackageInfo = .{ .version = build_options.version, .target_arch = arch };
    const artifact = try info.artifactName(allocator);
    defer allocator.free(artifact);
    if (json) {
        try stdout.print("{{\"package\":\"aegis-edge\",\"version\":", .{});
        try edge.core.core.util.writeJsonString(stdout, build_options.version);
        try stdout.print(",\"target_arch\":\"{s}\",\"artifact\":", .{arch.toString()});
        try edge.core.core.util.writeJsonString(stdout, artifact);
        try stdout.print(",\"support\":\"{s}\",\"reason\":", .{package_status.toString()});
        try edge.core.core.util.writeJsonString(stdout, if (package_status == .active) "standalone Linux Edge package is produced by scripts/build-release.sh" else "standalone aegis-edge packages are produced only for linux-amd64 and linux-arm64 in Phase 36");
        try stdout.writeAll("}\n");
        return if (package_status == .unsupported) 65 else 0;
    }
    if (package_status == .unsupported) {
        try stderr.print("aegis-edge deployment package-info: standalone Edge package target '{s}' is unsupported; use --arch linux-amd64 or --arch linux-arm64.\n", .{arch.toString()});
        return 65;
    }
    try edge.deployment.packageManifest(stdout, build_options.version, arch);
    return 0;
}

fn runBench(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0) return usageError(stderr, "aegis-edge bench: expected doctor, check, or report.\n");
    if (std.mem.eql(u8, argv[0], "doctor")) return runBenchDoctor(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "check")) return runBenchCheck(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "report")) return runBenchReport(argv[1..], stdout, stderr);
    try stderr.print("aegis-edge bench: unknown subcommand '{s}'.\n", .{argv[0]});
    return 64;
}

fn runBenchDoctor(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len != 0) return usageError(stderr, "aegis-edge bench doctor: expected no arguments.\n");
    try stdout.writeAll("Bench mode: active\nEnvironment: hardware_bench_no_actuation\nDefault behavior: observe/simulation, no actuation, no real hardware assumption\nRequired: explicit --bench/profile, explicit policy, explicit operator acknowledgement for endpoint-like physical interfaces\n");
    try stdout.print("Limitations: {s}\n", .{edge.deployment.no_flight_disclaimer});
    return 0;
}

fn runBenchCheck(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    const policy_path = parsePolicyOnly(argv, stderr, "aegis-edge bench check") catch return 64;
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const policy_status = edge.deployment.validatePolicy(policy_path, gpa_state.allocator());
    const report = edge.deployment.benchReport(policy_path, null);
    try stdout.print("Bench check: {s}\nPolicy: {s} ({s})\nRuntime assets: {s}\nEnvironment: hardware_bench_no_actuation\n", .{ if (policy_status == .active and report.asset_status == .active) "active" else "failed", policy_path, policy_status.toString(), report.asset_status.toString() });
    try stdout.print("Limitations: {s}\n", .{edge.deployment.no_flight_disclaimer});
    return if (policy_status == .active and report.asset_status == .active) 0 else 65;
}

fn runBenchReport(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var policy_path: ?[]const u8 = null;
    var scenario_path: ?[]const u8 = null;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--policy")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge bench report: --policy requires a file.\n");
            policy_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--scenario")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge bench report: --scenario requires a file.\n");
            scenario_path = argv[index];
        } else {
            try stderr.print("aegis-edge bench report: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected_policy = policy_path orelse return usageError(stderr, "aegis-edge bench report: missing --policy.\n");
    const selected_scenario = scenario_path orelse return usageError(stderr, "aegis-edge bench report: missing --scenario.\n");
    var report = edge.deployment.benchReport(selected_policy, selected_scenario);
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const policy_status = edge.deployment.validatePolicy(selected_policy, gpa_state.allocator());
    if (policy_status != .active) report.policy_status = policy_status;
    try stdout.writeAll("Bench-readiness report\n");
    try stdout.print("Status: {s}\nTarget architecture: {s}\nBinary version: {s}\nRuntime assets: {s}\nPolicy validation: {s}\nScenario validation: {s}\nProvenance: {s}\nMAVLink/PX4/ArduPilot support: fake/SITL only; bench is no-actuation evidence\nRed-team status: {s}\nSafety-case report status: {s}\nNetwork/data guard status: {s}\nOperator approval status: {s}\nEmergency-mode status: {s}\n", .{ report.status.toString(), report.target_arch.toString(), build_options.version, report.asset_status.toString(), report.policy_status.toString(), report.scenario_status.toString(), report.provenance.toString(), report.redteam_status.toString(), report.safety_case_status.toString(), report.network_data_guard_status.toString(), report.operator_approval_status.toString(), report.emergency_mode_status.toString() });
    try stdout.print("Limitations: {s}\n", .{edge.deployment.no_flight_disclaimer});
    try stdout.writeAll("No-flight disclaimer: bench readiness is not flight readiness.\nNo-certification disclaimer: this report is not regulatory approval or certification.\n");
    return if (report.status == .active and report.policy_status == .active) 0 else 65;
}

fn writeArm64Doctor(stdout: anytype) !void {
    try stdout.writeAll("ARM64 deployment support: active\n");
    try stdout.writeAll("linux-arm64 artifact: aegis-edge-vX.Y.Z-linux-arm64.tar.gz\n");
    try stdout.writeAll("linux-amd64 artifact: aegis-edge-vX.Y.Z-linux-amd64.tar.gz\n");
    try stdout.writeAll("linux-armv7 artifact: unsupported in Phase 36 unless future release scripts add it explicitly\n");
    try stdout.writeAll("Cross-build command: zig build -Dtarget=aarch64-linux\n");
    try stdout.print("Limitations: {s}\n", .{edge.deployment.no_flight_disclaimer});
}

fn runPx4(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0) {
        try stderr.writeAll("aegis-edge px4: expected doctor, scenario, observe, gateway, or test-fixture.\n");
        return 64;
    }
    if (std.mem.eql(u8, argv[0], "doctor")) return runPx4Doctor(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "scenario")) return runPx4Scenario(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "observe")) return runPx4Observe(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "gateway")) return runPx4Gateway(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "test-fixture")) return runPx4TestFixture(argv[1..], stdout, stderr);
    try stderr.print("aegis-edge px4: unknown subcommand '{s}'.\n", .{argv[0]});
    return 64;
}

fn runPx4Doctor(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len != 0) return usageError(stderr, "aegis-edge px4 doctor: expected no arguments.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var gate = try edge.px4.connection.integrationTestGateFromEnv(allocator);
    defer gate.deinit(allocator);
    var config = edge.px4.connection.defaultConfig();
    const version = try edge.px4.connection.testedVersionFromEnv(allocator);
    defer allocator.free(version);
    config.tested_version = version;
    if (gate.endpoint) |endpoint| config.endpoint = endpoint;
    try edge.px4.health.writeDoctor(stdout, .{ .config = config, .gate = gate });
    return 0;
}

fn runPx4Scenario(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0 or !std.mem.eql(u8, argv[0], "run")) return usageError(stderr, "aegis-edge px4 scenario: expected run --policy <policy> --scenario <scenario>.\n");
    var policy_path: ?[]const u8 = null;
    var scenario_path: ?[]const u8 = null;
    var artifact_dir: ?[]const u8 = null;
    var index: usize = 1;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--policy")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge px4 scenario run: --policy requires a file.\n");
            policy_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--scenario")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge px4 scenario run: --scenario requires a file.\n");
            scenario_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--artifacts")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge px4 scenario run: --artifacts requires a directory.\n");
            artifact_dir = argv[index];
        } else {
            try stderr.print("aegis-edge px4 scenario run: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected_policy = policy_path orelse return usageError(stderr, "aegis-edge px4 scenario run: missing --policy.\n");
    const selected_scenario = scenario_path orelse return usageError(stderr, "aegis-edge px4 scenario run: missing --scenario.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var gate = try edge.px4.connection.integrationTestGateFromEnv(allocator);
    defer gate.deinit(allocator);
    var result = edge.px4.scenario.run(allocator, .{
        .policy_path = selected_policy,
        .scenario_path = selected_scenario,
        .artifact_dir = artifact_dir,
        .gate = gate,
    }) catch |err| {
        try stderr.print("PX4 scenario failed: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer result.deinit();
    try stdout.print("{s}\n", .{result.summary});
    if (result.skipped) {
        try stdout.writeAll("Skipped result is not a fake-PX4 pass and not PX4 SITL success.\n");
    } else {
        try stdout.print("Environment: {s}\nDecision: {s}\nForwarded: {}\nBlocked: {}\n", .{ result.environment.toString(), if (result.decision) |decision| decision.toString() else "none", result.forwarded, result.blocked });
        if (result.artifact_dir) |dir| try stdout.print("Artifacts: {s}\n", .{dir});
    }
    try stdout.writeAll("Limitations: simulation evidence only; not ready for real flight; no hardware integration; PX4 evidence is distinct from ArduPilot evidence.\n");
    return 0;
}

fn runPx4Observe(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var duration: u64 = 5;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--duration")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge px4 observe: --duration requires seconds.\n");
            duration = std.fmt.parseInt(u64, argv[index], 10) catch return usageError(stderr, "aegis-edge px4 observe: invalid --duration.\n");
        } else {
            try stderr.print("aegis-edge px4 observe: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var fake = edge.px4.fake_adapter.FakePx4Adapter.init(allocator, .{});
    defer fake.deinit();
    var mapper = edge.px4.telemetry_mapping.StateMapper.init(.{ .vehicle_id = "edge-vehicle-1", .provenance = .fake_adapter, .now_ms = 1_000_000 });
    const heartbeat = try fake.heartbeatFrame(.{ .armed = true, .base_mode = 0x08 });
    defer allocator.free(heartbeat);
    try mapper.observeFrame(try edge.mavlink.framing.parseFrame(heartbeat));
    const state = mapper.state();
    try stdout.print("PX4 observe environment: fake_px4\nDuration requested: {d}s\nVehicle: {s}\nMode: {s}\nArm state: {s}\nProvenance: {s}\n", .{ duration, state.vehicle_id.value, @tagName(state.mode), @tagName(state.arm_state), @tagName(state.provenance) });
    try stdout.writeAll("No PX4 SITL endpoint or hardware was opened. Use opt-in PX4 SITL tests for local simulator evidence.\n");
    return 0;
}

fn runPx4Gateway(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var policy_path: ?[]const u8 = null;
    var endpoint_text: []const u8 = "127.0.0.1:14540";
    var mode: edge.px4.connection.Mode = .observe;
    var protocol: edge.px4.connection.Protocol = .udp;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--policy")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge px4 gateway: --policy requires a file.\n");
            policy_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--endpoint")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge px4 gateway: --endpoint requires host:port.\n");
            endpoint_text = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--mode")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge px4 gateway: --mode requires observe|enforce|simulation.\n");
            mode = edge.px4.connection.Mode.parse(argv[index]) catch return usageError(stderr, "aegis-edge px4 gateway: invalid --mode.\n");
        } else if (std.mem.eql(u8, argv[index], "--protocol")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge px4 gateway: --protocol requires udp|tcp.\n");
            protocol = edge.px4.connection.Protocol.parse(argv[index]) catch return usageError(stderr, "aegis-edge px4 gateway: invalid --protocol.\n");
        } else {
            try stderr.print("aegis-edge px4 gateway: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected_policy = policy_path orelse return usageError(stderr, "aegis-edge px4 gateway: missing --policy.\n");
    const endpoint = edge.px4.connection.Endpoint.parse(endpoint_text) catch return usageError(stderr, "aegis-edge px4 gateway: invalid endpoint.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    var loaded = edge.policy.loadFile(gpa_state.allocator(), selected_policy, .{}) catch |err| {
        try stderr.print("Edge policy invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer loaded.deinit();
    try stdout.print("PX4 SITL gateway configured: endpoint={s}:{d} protocol={s} mode={s}\n", .{ endpoint.host, endpoint.port, protocol.toString(), mode.toString() });
    try stdout.print("Policy: {s}\n", .{selected_policy});
    try stdout.writeAll("Live PX4 SITL transport is opt-in local simulation only; this command does not assume hardware or real flight.\n");
    try stdout.writeAll("Mapped commands are mediated through the Phase 28 MAVLink gateway and Phase 27 Edge policy engine.\n");
    return 0;
}

fn runPx4TestFixture(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var name: ?[]const u8 = null;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--name")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge px4 test-fixture: --name requires a fixture name.\n");
            name = argv[index];
        } else {
            try stderr.print("aegis-edge px4 test-fixture: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected = name orelse return usageError(stderr, "aegis-edge px4 test-fixture: missing --name.\n");
    try stdout.print("PX4 fake fixture: {s}\n", .{selected});
    try stdout.writeAll("Environment: fake_px4\nProvenance: fake_adapter\nSupported names: heartbeat, position, battery, land, disable_failsafe, waypoint_outside_geofence\n");
    try stdout.writeAll("Fixtures are deterministic fake-PX4 records and are not PX4 SITL success evidence.\n");
    return 0;
}

fn runArduPilot(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0) {
        try stderr.writeAll("aegis-edge ardupilot: expected doctor, scenario, observe, gateway, or test-fixture.\n");
        return 64;
    }
    if (std.mem.eql(u8, argv[0], "doctor")) return runArduPilotDoctor(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "scenario")) return runArduPilotScenario(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "observe")) return runArduPilotObserve(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "gateway")) return runArduPilotGateway(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "test-fixture")) return runArduPilotTestFixture(argv[1..], stdout, stderr);
    try stderr.print("aegis-edge ardupilot: unknown subcommand '{s}'.\n", .{argv[0]});
    return 64;
}

fn runArduPilotDoctor(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len != 0) return usageError(stderr, "aegis-edge ardupilot doctor: expected no arguments.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var gate = try edge.ardupilot.connection.integrationTestGateFromEnv(allocator);
    defer gate.deinit(allocator);
    var config = edge.ardupilot.connection.defaultConfig();
    const version = try edge.ardupilot.connection.testedVersionFromEnv(allocator);
    defer allocator.free(version);
    config.tested_version = version;
    config.vehicle = gate.vehicle;
    if (gate.endpoint) |endpoint| config.endpoint = endpoint;
    try edge.ardupilot.health.writeDoctor(stdout, .{ .config = config, .gate = gate });
    return 0;
}

fn runArduPilotScenario(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0 or !std.mem.eql(u8, argv[0], "run")) return usageError(stderr, "aegis-edge ardupilot scenario: expected run --policy <policy> --scenario <scenario>.\n");
    var policy_path: ?[]const u8 = null;
    var scenario_path: ?[]const u8 = null;
    var artifact_dir: ?[]const u8 = null;
    var index: usize = 1;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--policy")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge ardupilot scenario run: --policy requires a file.\n");
            policy_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--scenario")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge ardupilot scenario run: --scenario requires a file.\n");
            scenario_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--artifacts")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge ardupilot scenario run: --artifacts requires a directory.\n");
            artifact_dir = argv[index];
        } else {
            try stderr.print("aegis-edge ardupilot scenario run: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected_policy = policy_path orelse return usageError(stderr, "aegis-edge ardupilot scenario run: missing --policy.\n");
    const selected_scenario = scenario_path orelse return usageError(stderr, "aegis-edge ardupilot scenario run: missing --scenario.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var gate = try edge.ardupilot.connection.integrationTestGateFromEnv(allocator);
    defer gate.deinit(allocator);
    var result = edge.ardupilot.scenario.run(allocator, .{
        .policy_path = selected_policy,
        .scenario_path = selected_scenario,
        .artifact_dir = artifact_dir,
        .gate = gate,
    }) catch |err| {
        try stderr.print("ArduPilot scenario failed: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer result.deinit();
    try stdout.print("{s}\n", .{result.summary});
    if (result.skipped) {
        try stdout.writeAll("Skipped result is not a fake-ArduPilot pass and not ArduPilot SITL success.\n");
    } else {
        try stdout.print("Environment: {s}\nVehicle: {s}\nDecision: {s}\nForwarded: {}\nBlocked: {}\n", .{ result.environment.toString(), result.vehicle.toString(), if (result.decision) |decision| decision.toString() else "none", result.forwarded, result.blocked });
        if (result.artifact_dir) |dir| try stdout.print("Artifacts: {s}\n", .{dir});
    }
    try stdout.writeAll("Limitations: simulation evidence only; not ready for real flight; no hardware integration; ArduPilot behavior is not identical to PX4 behavior.\n");
    return 0;
}

fn runArduPilotObserve(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var duration: u64 = 5;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--duration")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge ardupilot observe: --duration requires seconds.\n");
            duration = std.fmt.parseInt(u64, argv[index], 10) catch return usageError(stderr, "aegis-edge ardupilot observe: invalid --duration.\n");
        } else {
            try stderr.print("aegis-edge ardupilot observe: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var fake = edge.ardupilot.fake_adapter.FakeArduPilotAdapter.init(allocator, .{ .vehicle = .copter });
    defer fake.deinit();
    var mapper = edge.ardupilot.telemetry_mapping.StateMapper.init(.{
        .vehicle_id = "edge-vehicle-1",
        .vehicle = .copter,
        .provenance = .fake_ardupilot_adapter,
        .now_ms = 1_000_000,
    });
    const heartbeat = try fake.heartbeatFrame(.{ .armed = true, .custom_mode = edge.ardupilot.telemetry_mapping.copter_mode_guided });
    defer allocator.free(heartbeat);
    try mapper.observeFrame(try edge.mavlink.framing.parseFrame(heartbeat));
    const state = mapper.state();
    try stdout.print("ArduPilot observe environment: fake_ardupilot\nDuration requested: {d}s\nVehicle: {s}\nMode: {s}\nArm state: {s}\nProvenance: {s}\n", .{ duration, state.vehicle_id.value, @tagName(state.mode), @tagName(state.arm_state), @tagName(state.provenance) });
    try stdout.writeAll("No ArduPilot SITL endpoint or hardware was opened. Use opt-in ArduPilot SITL tests for local simulator evidence.\n");
    return 0;
}

fn runArduPilotGateway(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var policy_path: ?[]const u8 = null;
    var endpoint_text: []const u8 = "127.0.0.1:14550";
    var mode: edge.ardupilot.connection.Mode = .observe;
    var protocol: edge.ardupilot.connection.Protocol = .udp;
    var vehicle: edge.ardupilot.vehicle_kind.VehicleKind = .copter;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--policy")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge ardupilot gateway: --policy requires a file.\n");
            policy_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--endpoint")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge ardupilot gateway: --endpoint requires host:port.\n");
            endpoint_text = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--mode")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge ardupilot gateway: --mode requires observe|enforce|simulation.\n");
            mode = edge.ardupilot.connection.Mode.parse(argv[index]) catch return usageError(stderr, "aegis-edge ardupilot gateway: invalid --mode.\n");
        } else if (std.mem.eql(u8, argv[index], "--protocol")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge ardupilot gateway: --protocol requires udp|tcp.\n");
            protocol = edge.ardupilot.connection.Protocol.parse(argv[index]) catch return usageError(stderr, "aegis-edge ardupilot gateway: invalid --protocol.\n");
        } else if (std.mem.eql(u8, argv[index], "--vehicle")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge ardupilot gateway: --vehicle requires copter|plane|rover|sub|unknown.\n");
            vehicle = edge.ardupilot.vehicle_kind.VehicleKind.parse(argv[index]) catch return usageError(stderr, "aegis-edge ardupilot gateway: invalid --vehicle.\n");
        } else {
            try stderr.print("aegis-edge ardupilot gateway: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected_policy = policy_path orelse return usageError(stderr, "aegis-edge ardupilot gateway: missing --policy.\n");
    const endpoint = edge.ardupilot.connection.Endpoint.parse(endpoint_text) catch return usageError(stderr, "aegis-edge ardupilot gateway: invalid endpoint.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    var loaded = edge.policy.loadFile(gpa_state.allocator(), selected_policy, .{}) catch |err| {
        try stderr.print("Edge policy invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer loaded.deinit();
    try stdout.print("ArduPilot SITL gateway configured: endpoint={s}:{d} protocol={s} mode={s} vehicle={s}\n", .{ endpoint.host, endpoint.port, protocol.toString(), mode.toString(), vehicle.toString() });
    try stdout.print("Policy: {s}\n", .{selected_policy});
    try stdout.writeAll("Live ArduPilot SITL transport is opt-in local simulation only; this command does not assume hardware or real flight.\n");
    try stdout.writeAll("Mapped commands are mediated through the Phase 28 MAVLink gateway and Phase 27 Edge policy engine.\n");
    return 0;
}

fn runArduPilotTestFixture(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var name: ?[]const u8 = null;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--name")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge ardupilot test-fixture: --name requires a fixture name.\n");
            name = argv[index];
        } else {
            try stderr.print("aegis-edge ardupilot test-fixture: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected = name orelse return usageError(stderr, "aegis-edge ardupilot test-fixture: missing --name.\n");
    try stdout.print("ArduPilot fake fixture: {s}\n", .{selected});
    try stdout.writeAll("Environment: fake_ardupilot\nProvenance: fake_ardupilot_adapter\nSupported names: heartbeat, position, battery, land, rtl, disable_failsafe, waypoint_outside_geofence\n");
    try stdout.writeAll("Fixtures are deterministic fake-ArduPilot records and are not ArduPilot SITL success evidence.\n");
    return 0;
}

fn runMavlink(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0) {
        try stderr.writeAll("aegis-edge mavlink: expected doctor, inspect-frame, classify, simulate, or gateway.\n");
        return 64;
    }
    if (std.mem.eql(u8, argv[0], "doctor")) return runMavlinkDoctor(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "inspect-frame")) return runMavlinkInspect(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "classify")) return runMavlinkClassify(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "simulate")) return runMavlinkSimulate(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "gateway")) return runMavlinkGateway(argv[1..], stdout, stderr);
    try stderr.print("aegis-edge mavlink: unknown subcommand '{s}'.\n", .{argv[0]});
    return 64;
}

fn runMavlinkDoctor(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len != 0) return usageError(stderr, "aegis-edge mavlink doctor: expected no arguments.\n");
    try stdout.writeAll("MAVLink gateway foundation: active for fake_transport simulation/protocol mediation only.\n");
    try stdout.writeAll("Supported parsing: MAVLink v1 and v2 frames, bounded payloads, partial streams, known-message CRC validation, MAVLink2 signing detection.\n");
    try stdout.writeAll("Supported mediation subset: heartbeat/state, COMMAND_LONG, COMMAND_INT, SET_MODE, PARAM_SET safety toggles, setpoint targets, and generic mission upload messages.\n");
    try stdout.writeAll("Unsupported in this generic MAVLink subcommand: serial hardware endpoints, ROS2, real hardware flight, signing key management, and signing verification. Use aegis-edge px4 or aegis-edge ardupilot for opt-in SITL simulation evidence.\n");
    try stdout.writeAll("Recommendation for real deployments: use MAVLink2 signing at the deployment boundary; Aegis Edge Phase 28 only detects signing presence.\n");
    return 0;
}

fn runMavlinkInspect(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len != 1) return usageError(stderr, "aegis-edge mavlink inspect-frame: expected exactly one file path or hex string.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    const bytes = readFileOrHex(allocator, argv[0]) catch |err| {
        try stderr.print("MAVLink frame input invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer allocator.free(bytes);
    const frame = edge.mavlink.framing.parseFrame(bytes) catch |err| {
        try stderr.print("MAVLink frame invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    try stdout.print("MAVLink frame: version={s} msgid={d} name={s} seq={d} sysid={d} compid={d} payload_len={d}\n", .{
        @tagName(frame.version),
        frame.msgid,
        edge.mavlink.dialect.nameFor(frame.msgid),
        frame.sequence,
        frame.sysid,
        frame.compid,
        frame.payload.len,
    });
    try stdout.print("CRC: {s}\n", .{if (frame.checksum_valid == true) "valid" else if (frame.checksum_valid == false) "invalid" else "not-validated-for-unknown-message"});
    try stdout.print("MAVLink2 signing: {s}\n", .{if (frame.signature_present) "present-detection-only" else "absent"});
    try stdout.writeAll("Payload logging is bounded; raw payload bytes are not dumped unbounded.\n");
    return 0;
}

fn runMavlinkClassify(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len != 1) return usageError(stderr, "aegis-edge mavlink classify: expected exactly one file path or hex string.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    const bytes = readFileOrHex(allocator, argv[0]) catch |err| {
        try stderr.print("MAVLink frame input invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer allocator.free(bytes);
    const frame = edge.mavlink.framing.parseFrame(bytes) catch |err| {
        try stderr.print("MAVLink frame invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    const classification = edge.mavlink.classifier.classifyFrame(frame) catch |err| {
        try stderr.print("MAVLink classification failed: {s}\n", .{@errorName(err)});
        return 65;
    };
    var mapping = edge.mavlink.mapping.mapFrameToCommand(allocator, frame, .{ .vehicle_id = "edge-vehicle-1", .now_ms = 1_000_100 }) catch |err| {
        try stderr.print("MAVLink mapping failed: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer mapping.deinit();
    try stdout.print("Message: {s} ({d})\n", .{ classification.message_name, classification.message_id });
    try stdout.print("Category: {s}\n", .{@tagName(classification.category)});
    try stdout.print("Safety-sensitive: {}\n", .{classification.safety_sensitive});
    if (classification.command_id) |command_id| try stdout.print("MAV_CMD: {d} ({s})\n", .{ command_id, edge.mavlink.commands.nameFor(command_id) });
    if (mapping.request) |request| {
        try stdout.print("Mapped Edge action: {s}\n", .{@tagName(request.action)});
        try stdout.print("Risk: {s}\n", .{@tagName(request.risk_classification)});
    } else if (mapping.unsupported) |unsupported| {
        try stdout.print("Mapped Edge action: unsupported\nRisk: {s}\nReason: {s}\n", .{ @tagName(unsupported.risk), unsupported.reason });
    } else {
        try stdout.writeAll("Mapped Edge action: none\nRisk: low-or-unknown-message\n");
    }
    try stdout.writeAll("No command was sent to a vehicle, simulator, or flight controller.\n");
    return 0;
}

fn runMavlinkSimulate(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var policy_path: ?[]const u8 = null;
    var scenario_path: ?[]const u8 = null;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--policy")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge mavlink simulate: --policy requires a file.\n");
            policy_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--scenario")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge mavlink simulate: --scenario requires a file.\n");
            scenario_path = argv[index];
        } else {
            try stderr.print("aegis-edge mavlink simulate: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected_policy_path = policy_path orelse return usageError(stderr, "aegis-edge mavlink simulate: missing --policy.\n");
    const selected_scenario_path = scenario_path orelse return usageError(stderr, "aegis-edge mavlink simulate: missing --scenario.\n");

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var loaded = edge.policy.loadFile(allocator, selected_policy_path, .{}) catch |err| {
        try stderr.print("Edge policy invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer loaded.deinit();
    var scenario = loadScenario(allocator, selected_scenario_path) catch |err| {
        try stderr.print("MAVLink scenario invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer scenario.deinit();
    const frame = edge.mavlink.framing.parseFrame(scenario.frame_bytes) catch |err| {
        try stderr.print("Generated MAVLink scenario frame invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    var tracker = edge.mavlink.mission.MissionTracker.init();
    var result = if (edge.mavlink.dialect.isMission(frame.msgid)) blk: {
        const count = try edge.mavlink.fake_transport.frameMissionCountV2(allocator, .{ .seq = 1, .sysid = 42, .compid = 191 }, 1);
        defer allocator.free(count);
        try tracker.observe(try edge.mavlink.messages.decode(try edge.mavlink.framing.parseFrame(count)));
        break :blk try edge.mavlink.gateway.processMissionFrame(allocator, .{ .mode = .enforce, .direction = .companion_to_vehicle, .vehicle_id = "edge-vehicle-1", .now_ms = 1_000_500 }, &loaded.value, defaultStateForPolicy(&loaded.value, 1_000_000), frame, &tracker);
    } else try edge.mavlink.gateway.processFrame(allocator, .{ .mode = .enforce, .direction = .companion_to_vehicle, .vehicle_id = "edge-vehicle-1", .now_ms = 1_000_500 }, &loaded.value, defaultStateForPolicy(&loaded.value, 1_000_000), frame);
    defer result.deinit();

    if (scenario.expected_decision) |expected| {
        const actual = result.decision orelse {
            try stderr.writeAll("MAVLink scenario expectation failed: expected decision but gateway produced none.\n");
            return 65;
        };
        if (actual != expected) {
            try stderr.print("MAVLink scenario expectation failed: expected_decision={s} actual={s}\n", .{ expected.toString(), actual.toString() });
            return 65;
        }
    }
    if (scenario.expected_forwarded) |expected| {
        if (result.forwarded != expected) {
            try stderr.print("MAVLink scenario expectation failed: expected_forwarded={} actual={}\n", .{ expected, result.forwarded });
            return 65;
        }
    }

    try stdout.print("Scenario: {s}\n", .{selected_scenario_path});
    try stdout.writeAll("Transport: fake_transport/simulation\n");
    try stdout.print("Message: {s} ({d})\n", .{ result.classification.message_name, result.classification.message_id });
    try stdout.print("Decision: {s}\n", .{if (result.decision) |decision| decision.toString() else "none"});
    try stdout.print("Forwarded: {}\nBlocked: {}\n", .{ result.forwarded, result.blocked });
    try stdout.writeAll("Audit events:\n");
    for (result.audit.records.items) |record| try stdout.print("  - {s}\n", .{record.event_type});
    try stdout.writeAll("No serial hardware, SITL, ROS2, or hardware endpoint was opened by this fake MAVLink scenario.\n");
    return 0;
}

fn runMavlinkGateway(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var fake = false;
    var policy_path: ?[]const u8 = null;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--fake")) {
            fake = true;
        } else if (std.mem.eql(u8, argv[index], "--policy")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge mavlink gateway: --policy requires a file.\n");
            policy_path = argv[index];
        } else {
            try stderr.print("aegis-edge mavlink gateway: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    if (!fake) return usageError(stderr, "aegis-edge mavlink gateway: only --fake in-memory mode is implemented in Phase 28.\n");
    const selected_policy_path = policy_path orelse return usageError(stderr, "aegis-edge mavlink gateway: missing --policy.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    var loaded = edge.policy.loadFile(gpa_state.allocator(), selected_policy_path, .{}) catch |err| {
        try stderr.print("Edge policy invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer loaded.deinit();
    try stdout.print("MAVLink fake gateway configured with policy {s}\n", .{selected_policy_path});
    try stdout.writeAll("Mode: fake_transport only. Serial hardware endpoints were not opened.\n");
    return 0;
}

fn runOperator(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0) return usageError(stderr, "aegis-edge operator: expected request, approve, deny, list, or revoke.\n");
    if (std.mem.eql(u8, argv[0], "request")) return runOperatorRequest(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "approve")) return runOperatorApprove(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "deny")) return runOperatorDeny(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "list")) return runOperatorList(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "revoke")) return runOperatorRevoke(argv[1..], stdout, stderr);
    try stderr.print("aegis-edge operator: unknown subcommand '{s}'.\n", .{argv[0]});
    return 64;
}

fn runOperatorRequest(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var policy_path: ?[]const u8 = null;
    var request_path: ?[]const u8 = null;
    var state_path: ?[]const u8 = null;
    var session_id: []const u8 = "last";
    var json = false;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--json")) {
            json = true;
        } else if (std.mem.eql(u8, argv[index], "--policy")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge operator request: --policy requires a file.\n");
            policy_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--request")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge operator request: --request requires a file.\n");
            request_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--state")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge operator request: --state requires a file.\n");
            state_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--session")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge operator request: --session requires an id.\n");
            session_id = argv[index];
        } else {
            try stderr.print("aegis-edge operator request: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected_policy = policy_path orelse return usageError(stderr, "aegis-edge operator request: missing --policy.\n");
    const selected_request = request_path orelse return usageError(stderr, "aegis-edge operator request: missing --request.\n");
    const selected_state = state_path orelse return usageError(stderr, "aegis-edge operator request: missing --state.\n");

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var loaded = edge.policy.loadFile(allocator, selected_policy, .{}) catch |err| {
        try stderr.print("Edge policy invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer loaded.deinit();
    var parsed_command = loadCommandFile(allocator, selected_request, stderr) catch return 65;
    defer parsed_command.deinit();
    var parsed_state = loadStateFile(allocator, selected_state, stderr) catch return 65;
    defer parsed_state.deinit();
    var evaluation = edge.safety.evaluateSafety(allocator, &loaded.value, parsed_state.value, parsed_command.value, .{
        .mode = .ask,
        .now_ms = parsed_state.value.timestamp.value + 500,
        .non_interactive = false,
    }) catch |err| {
        try stderr.print("Operator approval request evaluation failed: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer evaluation.deinit();
    if (evaluation.approval_request == null) {
        try stdout.print("No operator approval request created. Decision: {s}\n", .{evaluation.decision.result.toString()});
        try stdout.writeAll("No command was sent. CI/non-interactive mode is not prompting.\n");
        return 0;
    }
    const root = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(root);
    var store = try edge.operator.ApprovalStore.init(allocator, root, session_id);
    defer store.deinit();
    try store.appendRequest(evaluation.approval_request.?);
    if (json) {
        try stdout.writeAll("{\"approval_request_id\":");
        try edge.core.core.util.writeJsonString(stdout, evaluation.approval_request.?.approval_request_id);
        try stdout.writeAll(",\"decision\":\"ask\",\"scope\":\"exact_action_only\",\"expires_at_ms\":");
        try stdout.print("{d}", .{evaluation.approval_request.?.expires_at_ms});
        try stdout.writeAll(",\"environment\":");
        try edge.core.core.util.writeJsonString(stdout, @tagName(evaluation.approval_request.?.environment));
        try stdout.writeAll("}\n");
    } else {
        try stdout.print("Approval request: {s}\n", .{evaluation.approval_request.?.approval_request_id});
        try stdout.print("Command: {s} ({s})\nVehicle: {s}\nEnvironment: {s}\nRisk: {s}\nScope: exact_action_only\nExpires at ms: {d}\n", .{
            evaluation.approval_request.?.command_id,
            @tagName(evaluation.approval_request.?.command_type),
            evaluation.approval_request.?.vehicle_id,
            @tagName(evaluation.approval_request.?.environment),
            @tagName(evaluation.approval_request.?.risk_class),
            evaluation.approval_request.?.expires_at_ms,
        });
        if (evaluation.matched_rule) |rule| try stdout.print("Matched rule: {s} ({s})\n", .{ rule.id, rule.description });
        try stdout.writeAll("Choices for an interactive operator are: allow once, deny, explain, abort. Broad approval is not the default.\n");
        try stdout.writeAll("No command was sent to a vehicle, adapter, simulator, or flight controller. This is local simulation/SITL/bench-preparation evidence only.\n");
    }
    return 0;
}

fn runOperatorApprove(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len < 1) return usageError(stderr, "aegis-edge operator approve: expected <approval-request-id> --scope once.\n");
    const approval_id = argv[0];
    var scope_once = false;
    var index: usize = 1;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--scope")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge operator approve: --scope requires once.\n");
            scope_once = std.mem.eql(u8, argv[index], "once");
        } else {
            try stderr.print("aegis-edge operator approve: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    if (!scope_once) return usageError(stderr, "aegis-edge operator approve: only --scope once is supported in the local Phase 32 CLI.\n");
    return appendOperatorCliDecision(stdout, approval_id, "operator.approval_granted", "approved once");
}

fn runOperatorDeny(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len != 1) return usageError(stderr, "aegis-edge operator deny: expected <approval-request-id>.\n");
    return appendOperatorCliDecision(stdout, argv[0], "operator.approval_denied", "denied");
}

fn runOperatorRevoke(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len != 1) return usageError(stderr, "aegis-edge operator revoke: expected <approval-id>.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    const root = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(root);
    var store = try edge.operator.ApprovalStore.init(allocator, root, "last");
    defer store.deinit();
    try store.revoke(argv[0], "operator-cli", 1_000_700);
    try stdout.print("Approval revoked locally: {s}\n", .{argv[0]});
    try stdout.writeAll("This local store is not a long-term authorization database.\n");
    return 0;
}

fn runOperatorList(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len != 0) return usageError(stderr, "aegis-edge operator list: expected no arguments.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    const root = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(root);
    var store = try edge.operator.ApprovalStore.init(allocator, root, "last");
    defer store.deinit();
    const maybe_text = std.fs.cwd().readFileAlloc(allocator, store.approvals_path, 128 * 1024) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    defer if (maybe_text) |text| allocator.free(text);
    if (maybe_text == null or maybe_text.?.len == 0) {
        try stdout.writeAll("No local operator approvals recorded for session last.\n");
    } else {
        try stdout.writeAll("Local operator approval audit records (session last):\n");
        try stdout.writeAll(maybe_text.?);
    }
    try stdout.writeAll("Approval records are local-only, bounded, and not a long-term authorization database.\n");
    return 0;
}

fn appendOperatorCliDecision(stdout: anytype, approval_id: []const u8, event_type: []const u8, label: []const u8) !u8 {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    const root = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(root);
    var store = try edge.operator.ApprovalStore.init(allocator, root, "last");
    defer store.deinit();
    try store.appendCliEvent(event_type, approval_id, "operator-cli", 1_000_700, label);
    try stdout.print("Approval {s}: {s}\n", .{ label, approval_id });
    try stdout.writeAll("Only exact-action local approvals are supported by this CLI path; CI/non-interactive mode never prompts.\n");
    return 0;
}

fn runEmergency(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0) return usageError(stderr, "aegis-edge emergency: expected evaluate or scenario.\n");
    if (std.mem.eql(u8, argv[0], "evaluate")) return runEmergencyEvaluate(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "scenario")) return runEmergencyScenario(argv[1..], stdout, stderr);
    try stderr.print("aegis-edge emergency: unknown subcommand '{s}'.\n", .{argv[0]});
    return 64;
}

fn runEmergencyEvaluate(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var policy_path: ?[]const u8 = null;
    var state_path: ?[]const u8 = null;
    var reason: edge.emergency.EmergencyReason = .unknown;
    var json = false;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--json")) {
            json = true;
        } else if (std.mem.eql(u8, argv[index], "--policy")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge emergency evaluate: --policy requires a file.\n");
            policy_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--state")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge emergency evaluate: --state requires a file.\n");
            state_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--reason")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge emergency evaluate: --reason requires a value.\n");
            reason = std.meta.stringToEnum(edge.emergency.EmergencyReason, argv[index]) orelse return usageError(stderr, "aegis-edge emergency evaluate: invalid reason.\n");
        } else {
            try stderr.print("aegis-edge emergency evaluate: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected_policy = policy_path orelse return usageError(stderr, "aegis-edge emergency evaluate: missing --policy.\n");
    const selected_state = state_path orelse return usageError(stderr, "aegis-edge emergency evaluate: missing --state.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var loaded = edge.policy.loadFile(allocator, selected_policy, .{}) catch |err| {
        try stderr.print("Emergency policy invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer loaded.deinit();
    var parsed_state = loadStateFile(allocator, selected_state, stderr) catch return 65;
    defer parsed_state.deinit();
    var decision = edge.emergency.evaluateFallback(allocator, &loaded.value, parsed_state.value, reason, .{ .now_ms = parsed_state.value.timestamp.value + 500 }) catch |err| {
        try stderr.print("Emergency evaluation failed: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer decision.deinit(allocator);
    try writeEmergencyDecision(stdout, decision, json);
    return 0;
}

fn runEmergencyScenario(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0 or !std.mem.eql(u8, argv[0], "run")) return usageError(stderr, "aegis-edge emergency scenario: expected run --policy <policy> --scenario <scenario>.\n");
    var policy_path: ?[]const u8 = null;
    var scenario_path: ?[]const u8 = null;
    var index: usize = 1;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--policy")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge emergency scenario run: --policy requires a file.\n");
            policy_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--scenario")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge emergency scenario run: --scenario requires a file.\n");
            scenario_path = argv[index];
        } else {
            try stderr.print("aegis-edge emergency scenario run: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected_policy = policy_path orelse return usageError(stderr, "aegis-edge emergency scenario run: missing --policy.\n");
    const selected_scenario = scenario_path orelse return usageError(stderr, "aegis-edge emergency scenario run: missing --scenario.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    const spec = loadEmergencyScenario(allocator, selected_scenario) catch |err| {
        try stderr.print("Emergency scenario invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer spec.deinit(allocator);
    var loaded = edge.policy.loadFile(allocator, selected_policy, .{}) catch |err| {
        try stderr.print("Emergency policy invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer loaded.deinit();
    var parsed_state = loadStateFile(allocator, spec.state_path, stderr) catch return 65;
    defer parsed_state.deinit();
    var decision = try edge.emergency.evaluateFallback(allocator, &loaded.value, parsed_state.value, spec.reason, .{ .now_ms = parsed_state.value.timestamp.value + 500 });
    defer decision.deinit(allocator);
    if (spec.expected_command) |expected| if (decision.command != expected) {
        try stderr.print("Emergency scenario mismatch: expected_command={s} actual={s}\n", .{ @tagName(expected), @tagName(decision.command) });
        return 65;
    };
    try stdout.print("Scenario: {s}\n", .{spec.id});
    try writeEmergencyDecision(stdout, decision, false);
    return 0;
}

fn runPolicy(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0) {
        try stderr.writeAll("aegis-edge policy: expected check, explain, or evaluate.\n");
        return 64;
    }
    if (std.mem.eql(u8, argv[0], "check")) return runPolicyCheck(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "explain")) return runPolicyExplain(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "evaluate")) return runPolicyEvaluate(argv[1..], stdout, stderr);
    try stderr.print("aegis-edge policy: unknown subcommand '{s}'.\n", .{argv[0]});
    return 64;
}

fn runData(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0) return usageError(stderr, "aegis-edge data: expected doctor, classify, evaluate, redact, or scenario.\n");
    if (std.mem.eql(u8, argv[0], "doctor")) return runDataDoctor(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "classify")) return runDataClassify(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "evaluate")) return runDataEvaluate(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "redact")) return runDataRedact(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "scenario")) return runDataScenario(argv[1..], stdout, stderr);
    try stderr.print("aegis-edge data: unknown subcommand '{s}'.\n", .{argv[0]});
    return 64;
}

fn runNetwork(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0 or !std.mem.eql(u8, argv[0], "explain")) return usageError(stderr, "aegis-edge network: expected explain --policy <policy> --endpoint <endpoint.json>.\n");
    var policy_path: ?[]const u8 = null;
    var endpoint_path: ?[]const u8 = null;
    var json = false;
    var index: usize = 1;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--policy")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge network explain: --policy requires a file.\n");
            policy_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--endpoint")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge network explain: --endpoint requires a file.\n");
            endpoint_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--json")) {
            json = true;
        } else {
            try stderr.print("aegis-edge network explain: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected_policy = policy_path orelse return usageError(stderr, "aegis-edge network explain: missing --policy.\n");
    const selected_endpoint = endpoint_path orelse return usageError(stderr, "aegis-edge network explain: missing --endpoint.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var loaded = edge.data_guard.loadPolicyFile(allocator, selected_policy) catch |err| {
        try stderr.print("Data guard policy invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer loaded.deinit();
    const endpoint_text = try std.fs.cwd().readFileAlloc(allocator, selected_endpoint, 32 * 1024);
    defer allocator.free(endpoint_text);
    var endpoint = edge.data_guard.parseEndpointJsonOwned(allocator, endpoint_text) catch |err| {
        try stderr.print("Endpoint invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer endpoint.deinit();
    var classification = try edge.data_guard.classifyEndpoint(allocator, endpoint.value);
    defer classification.deinit();
    const decision = loaded.value.resolveEndpoint(endpoint.value, classification).decision;
    if (json) {
        try stdout.writeAll("{\"endpoint_kind\":");
        try edge.core.core.util.writeJsonString(stdout, classification.kind.toString());
        try stdout.writeAll(",\"decision\":");
        try edge.core.core.util.writeJsonString(stdout, decision.toString());
        try stdout.writeAll(",\"endpoint\":");
        try edge.core.core.util.writeJsonString(stdout, classification.redacted_endpoint);
        try stdout.print(",\"suspicious\":{}}}\n", .{classification.suspicious});
    } else {
        try stdout.print("Endpoint: {s}\nKind: {s}\nDecision: {s}\nReason: {s}\n", .{ classification.redacted_endpoint, classification.kind.toString(), decision.toString(), classification.reason });
        try stdout.writeAll("No network connection was opened. Endpoint URLs are redacted before output.\n");
    }
    return 0;
}

fn runDataDoctor(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len != 0) return usageError(stderr, "aegis-edge data doctor: expected no arguments.\n");
    try stdout.writeAll("Aegis Edge data/network guard: active for local classification, policy evaluation, redaction, audit/report evidence, and deterministic fake/SITL/customer-evaluation scenarios.\n");
    try stdout.writeAll("Controls: data classes, telemetry channels, endpoint classification, allow/ask/deny policy, CI ask-to-deny, observe logging, exfiltration heuristics, and redaction before persistence.\n");
    try stdout.writeAll("Unsupported: hosted telemetry, SaaS, real-flight deployment, real hardware procedures, detect-and-avoid, autopilot replacement, regulatory approval, or certification.\n");
    try stdout.writeAll("No external network call, PX4 endpoint, ArduPilot endpoint, or hardware connection is opened by data doctor.\n");
    return 0;
}

fn runDataClassify(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var payload_path: ?[]const u8 = null;
    var json = false;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--payload")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge data classify: --payload requires a file.\n");
            payload_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--json")) {
            json = true;
        } else {
            try stderr.print("aegis-edge data classify: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected_payload = payload_path orelse return usageError(stderr, "aegis-edge data classify: missing --payload.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    const text = try std.fs.cwd().readFileAlloc(allocator, selected_payload, 256 * 1024);
    defer allocator.free(text);
    var result = edge.data_guard.classifyPayload(allocator, text) catch |err| {
        try stderr.print("Payload classification failed: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer result.deinit();
    try writeDataClassification(stdout, result, json);
    return 0;
}

fn runDataEvaluate(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var policy_path: ?[]const u8 = null;
    var payload_path: ?[]const u8 = null;
    var endpoint_path: ?[]const u8 = null;
    var json = false;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--policy")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge data evaluate: --policy requires a file.\n");
            policy_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--payload")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge data evaluate: --payload requires a file.\n");
            payload_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--endpoint")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge data evaluate: --endpoint requires a file.\n");
            endpoint_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--json")) {
            json = true;
        } else {
            try stderr.print("aegis-edge data evaluate: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected_policy = policy_path orelse return usageError(stderr, "aegis-edge data evaluate: missing --policy.\n");
    const selected_payload = payload_path orelse return usageError(stderr, "aegis-edge data evaluate: missing --payload.\n");
    const selected_endpoint = endpoint_path orelse return usageError(stderr, "aegis-edge data evaluate: missing --endpoint.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var owned = evaluateDataGuardFiles(allocator, selected_policy, selected_payload, selected_endpoint) catch |err| {
        try stderr.print("Data guard evaluation failed: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer owned.deinit();
    try writeDataEvaluation(stdout, owned, json);
    return 0;
}

fn runDataRedact(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var payload_path: ?[]const u8 = null;
    var json = false;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--payload")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge data redact: --payload requires a file.\n");
            payload_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--json")) {
            json = true;
        } else {
            try stderr.print("aegis-edge data redact: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected_payload = payload_path orelse return usageError(stderr, "aegis-edge data redact: missing --payload.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    const text = try std.fs.cwd().readFileAlloc(allocator, selected_payload, 256 * 1024);
    defer allocator.free(text);
    var classification = try edge.data_guard.classifyPayload(allocator, text);
    defer classification.deinit();
    var redacted = try edge.data_guard.redactPayload(allocator, text, classification.classes, true);
    defer redacted.deinit();
    if (json) {
        try stdout.writeAll("{\"redacted\":");
        try edge.core.core.util.writeJsonString(stdout, redacted.text);
        try stdout.print(",\"redaction_count\":{d},\"safe_to_persist\":{}}}\n", .{ redacted.redaction_count, redacted.safe_to_persist });
    } else {
        try stdout.writeAll(redacted.text);
        try stdout.writeByte('\n');
    }
    return 0;
}

fn runDataScenario(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0 or !std.mem.eql(u8, argv[0], "run")) return usageError(stderr, "aegis-edge data scenario: expected run --policy <policy> --scenario <scenario>.\n");
    var policy_path: ?[]const u8 = null;
    var scenario_path: ?[]const u8 = null;
    var index: usize = 1;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--policy")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge data scenario run: --policy requires a file.\n");
            policy_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--scenario")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge data scenario run: --scenario requires a file.\n");
            scenario_path = argv[index];
        } else {
            try stderr.print("aegis-edge data scenario run: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected_policy = policy_path orelse return usageError(stderr, "aegis-edge data scenario run: missing --policy.\n");
    const selected_scenario = scenario_path orelse return usageError(stderr, "aegis-edge data scenario run: missing --scenario.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var scenario = try loadDataScenario(allocator, selected_scenario);
    defer scenario.deinit(allocator);
    var evaluation = try evaluateDataGuardFiles(allocator, selected_policy, scenario.payload_path, scenario.endpoint_path);
    defer evaluation.deinit();
    const ok = if (scenario.expected_decision) |expected| expected == evaluation.decision.result else true;
    try stdout.print("Scenario {s}: decision={s} endpoint={s}\n", .{ scenario.id, evaluation.decision.result.toString(), evaluation.redacted_endpoint });
    try stdout.print("Explanation: {s}\n", .{evaluation.explanation});
    try stdout.writeAll("No external network call, hardware endpoint, or real-flight action was performed.\n");
    return if (ok) 0 else 6;
}

fn evaluateDataGuardFiles(allocator: std.mem.Allocator, policy_path: []const u8, payload_path: []const u8, endpoint_path: []const u8) !edge.data_guard.EgressEvaluation {
    var loaded = try edge.data_guard.loadPolicyFile(allocator, policy_path);
    defer loaded.deinit();
    const payload_text = try std.fs.cwd().readFileAlloc(allocator, payload_path, 256 * 1024);
    defer allocator.free(payload_text);
    const endpoint_text = try std.fs.cwd().readFileAlloc(allocator, endpoint_path, 32 * 1024);
    defer allocator.free(endpoint_text);
    var endpoint = try edge.data_guard.parseEndpointJsonOwned(allocator, endpoint_text);
    defer endpoint.deinit();
    const payload = parseDataPayload(payload_text);
    return edge.data_guard.evaluateEgress(allocator, loaded.value, payload, endpoint.value, .{
        .mode = loaded.value.mode,
        .ci = loaded.value.mode == .ci,
        .non_interactive = loaded.value.mode == .ci,
    });
}

fn parseDataPayload(text: []const u8) edge.data_guard.TelemetryPayload {
    var channel: edge.data_guard.ChannelKind = .unknown;
    var direction: edge.data_guard.Direction = .unknown;
    var source: []const u8 = "file";
    var destination: []const u8 = "endpoint";
    const vehicle_id: ?[]const u8 = if (edge.data_guard.data_classification.containsAny(text, &.{"vehicle_id"})) "edge-vehicle-1" else null;
    const scenario_id: ?[]const u8 = null;
    var provenance: []const u8 = "fake_adapter";
    if (std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, text, .{})) |parsed| {
        defer parsed.deinit();
        if (parsed.value == .object) {
            const object = parsed.value.object;
            if (object.get("channel_kind")) |value| {
                if (value == .string) channel = edge.data_guard.ChannelKind.parse(value.string) orelse .unknown;
            }
            if (object.get("channel")) |value| {
                if (value == .string) channel = edge.data_guard.ChannelKind.parse(value.string) orelse channel;
            }
            if (object.get("direction")) |value| {
                if (value == .string) direction = edge.data_guard.Direction.parse(value.string) orelse .unknown;
            }
            if (object.get("provenance")) |value| {
                if (value == .string) {
                    if (std.mem.eql(u8, value.string, "sitl_px4")) provenance = "sitl_px4" else if (std.mem.eql(u8, value.string, "sitl_ardupilot")) provenance = "sitl_ardupilot" else if (std.mem.eql(u8, value.string, "fake_ardupilot_adapter")) provenance = "fake_ardupilot_adapter" else provenance = "fake_adapter";
                }
            }
        }
    } else |_| {}
    if (channel == .safety_case_report or direction == .edge_to_customer_endpoint) {
        source = "edge";
        destination = "customer_endpoint";
    }
    return .{
        .channel_kind = channel,
        .direction = direction,
        .source = source,
        .destination = destination,
        .vehicle_id = vehicle_id,
        .scenario_id = scenario_id,
        .provenance = provenance,
        .payload = text,
    };
}

const DataScenarioSpec = struct {
    id: []u8,
    payload_path: []u8,
    endpoint_path: []u8,
    expected_decision: ?edge.core.decision.DecisionResult = null,

    fn deinit(self: DataScenarioSpec, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.payload_path);
        allocator.free(self.endpoint_path);
    }
};

fn loadDataScenario(allocator: std.mem.Allocator, path: []const u8) !DataScenarioSpec {
    const text = try std.fs.cwd().readFileAlloc(allocator, path, 32 * 1024);
    defer allocator.free(text);
    var id: ?[]const u8 = null;
    var payload: ?[]const u8 = null;
    var endpoint: ?[]const u8 = null;
    var expected: ?edge.core.decision.DecisionResult = null;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const no_comment = if (std.mem.indexOfScalar(u8, raw_line, '#')) |comment| raw_line[0..comment] else raw_line;
        const line = std.mem.trim(u8, no_comment, " \t\r");
        if (line.len == 0) continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const key = std.mem.trim(u8, line[0..colon], " \t");
        const value = cleanDataScalar(line[colon + 1 ..]);
        if (std.mem.eql(u8, key, "id") or std.mem.eql(u8, key, "name")) id = value else if (std.mem.eql(u8, key, "payload")) payload = value else if (std.mem.eql(u8, key, "endpoint")) endpoint = value else if (std.mem.eql(u8, key, "expected_decision")) expected = std.meta.stringToEnum(edge.core.decision.DecisionResult, value) orelse null;
    }
    return .{
        .id = try allocator.dupe(u8, id orelse std.fs.path.stem(path)),
        .payload_path = try allocator.dupe(u8, payload orelse return error.InvalidDataGuardScenario),
        .endpoint_path = try allocator.dupe(u8, endpoint orelse return error.InvalidDataGuardScenario),
        .expected_decision = expected,
    };
}

fn cleanDataScalar(raw: []const u8) []const u8 {
    var value = std.mem.trim(u8, raw, " \t\r");
    if (value.len >= 2) {
        const first = value[0];
        const last = value[value.len - 1];
        if ((first == '"' and last == '"') or (first == '\'' and last == '\'')) value = value[1 .. value.len - 1];
    }
    return value;
}

fn writeDataClassification(stdout: anytype, result: edge.data_guard.data_classification.ClassificationResult, json: bool) !void {
    if (json) {
        try stdout.writeAll("{\"sensitivity\":");
        try edge.core.core.util.writeJsonString(stdout, result.sensitivity.toString());
        try stdout.writeAll(",\"classes\":[");
        for (result.classes, 0..) |class, index| {
            if (index > 0) try stdout.writeByte(',');
            try edge.core.core.util.writeJsonString(stdout, class.toString());
        }
        try stdout.print("],\"size_bytes\":{d}}}\n", .{result.size_bytes});
        return;
    }
    try stdout.print("Sensitivity: {s}\nClasses:", .{result.sensitivity.toString()});
    for (result.classes) |class| try stdout.print(" {s}", .{class.toString()});
    try stdout.print("\nSize bytes: {d}\n", .{result.size_bytes});
    try stdout.writeAll("Payload was not sent anywhere. Unknown and sensitive classes are not treated as safe.\n");
}

fn writeDataEvaluation(stdout: anytype, evaluation: edge.data_guard.EgressEvaluation, json: bool) !void {
    if (json) {
        try stdout.writeAll("{\"decision\":");
        try edge.core.core.util.writeJsonString(stdout, evaluation.decision.result.toString());
        try stdout.writeAll(",\"endpoint_kind\":");
        try edge.core.core.util.writeJsonString(stdout, evaluation.endpoint_kind.toString());
        try stdout.writeAll(",\"redacted_endpoint\":");
        try edge.core.core.util.writeJsonString(stdout, evaluation.redacted_endpoint);
        try stdout.writeAll(",\"sensitivity\":");
        try edge.core.core.util.writeJsonString(stdout, evaluation.sensitivity.toString());
        try stdout.writeAll(",\"findings\":[");
        for (evaluation.findings, 0..) |finding, index| {
            if (index > 0) try stdout.writeByte(',');
            try stdout.writeByte('{');
            try stdout.writeAll("\"category\":");
            try edge.core.core.util.writeJsonString(stdout, finding.category.toString());
            try stdout.writeAll(",\"severity\":");
            try edge.core.core.util.writeJsonString(stdout, finding.severity.toString());
            try stdout.writeAll(",\"reason\":");
            try edge.core.core.util.writeJsonString(stdout, finding.reason);
            try stdout.writeByte('}');
        }
        try stdout.writeAll("]}\n");
        return;
    }
    try stdout.print("Decision: {s}\nEndpoint: {s} ({s})\nSensitivity: {s}\n", .{ evaluation.decision.result.toString(), evaluation.redacted_endpoint, evaluation.endpoint_kind.toString(), evaluation.sensitivity.toString() });
    try stdout.print("Explanation: {s}\n", .{evaluation.explanation});
    try stdout.writeAll("Data classes:");
    for (evaluation.data_classes) |class| try stdout.print(" {s}", .{class.toString()});
    try stdout.writeAll("\nFindings:\n");
    for (evaluation.findings) |finding| try stdout.print("  - {s}/{s}: {s}\n", .{ finding.category.toString(), finding.severity.toString(), finding.reason });
    try stdout.writeAll("No external network call was made. Output is redacted/minimized.\n");
}

fn runSafety(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0) return usageError(stderr, "aegis-edge safety: expected doctor, check, evaluate, explain, or scenario.\n");
    if (std.mem.eql(u8, argv[0], "doctor")) return runSafetyDoctor(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "check")) return runSafetyCheck(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "evaluate")) return runSafetyEvaluate(argv[1..], stdout, stderr, false);
    if (std.mem.eql(u8, argv[0], "explain")) return runSafetyEvaluate(argv[1..], stdout, stderr, true);
    if (std.mem.eql(u8, argv[0], "scenario")) return runSafetyScenario(argv[1..], stdout, stderr);
    try stderr.print("aegis-edge safety: unknown subcommand '{s}'.\n", .{argv[0]});
    return 64;
}

fn runSafetyDoctor(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len != 0) return usageError(stderr, "aegis-edge safety doctor: expected no arguments.\n");
    try stdout.writeAll("Aegis Edge flight safety enforcement: active for fake adapters and opt-in PX4/ArduPilot SITL simulation evidence only.\n");
    try stdout.writeAll("Checks: command risk, geofence circle, altitude, velocity, battery, state freshness, mode, authority, mission item safety.\n");
    try stdout.writeAll("Unsupported: polygon conversion, local/WGS84 conversion, NED/ENU conversion, detect-and-avoid, autopilot replacement, regulatory certification, real-flight readiness.\n");
    try stdout.writeAll("No hardware, serial endpoint, SITL endpoint, or network connection is opened by safety doctor.\n");
    return 0;
}

fn runSafetyCheck(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var policy_path: ?[]const u8 = null;
    var json = false;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--json")) {
            json = true;
        } else if (std.mem.eql(u8, argv[index], "--policy")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge safety check: --policy requires a file.\n");
            policy_path = argv[index];
        } else {
            try stderr.print("aegis-edge safety check: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected_policy = policy_path orelse return usageError(stderr, "aegis-edge safety check: missing --policy.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var loaded = edge.policy.loadFile(allocator, selected_policy, .{}) catch |err| {
        try stderr.print("Safety policy invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer loaded.deinit();
    var compiled = edge.safety.compileEnvelope(allocator, &loaded.value) catch |err| {
        try stderr.print("Safety envelope invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer compiled.deinit();
    if (json) {
        try stdout.writeAll("{\"ok\":true,\"policy\":");
        try edge.core.core.util.writeJsonString(stdout, selected_policy);
        try stdout.print(",\"geofence_count\":{d},\"rules\":{d}}}\n", .{ compiled.geofence_count, compiled.rules.len });
    } else {
        try stdout.print("Safety envelope valid: {s}\n", .{selected_policy});
        try stdout.print("Compiled rules: {d}\nGeofences: {d}\n", .{ compiled.rules.len, compiled.geofence_count });
        try stdout.writeAll("This is validation only; no command was sent and no hardware endpoint was opened.\n");
    }
    return 0;
}

fn runSafetyEvaluate(argv: []const []const u8, stdout: anytype, stderr: anytype, explain: bool) !u8 {
    var policy_path: ?[]const u8 = null;
    var request_path: ?[]const u8 = null;
    var state_path: ?[]const u8 = null;
    var command_text: ?[]const u8 = null;
    var mode: edge.safety.EvaluationMode = .strict;
    var json = false;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--json")) {
            json = true;
        } else if (std.mem.eql(u8, argv[index], "--policy")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge safety evaluate: --policy requires a file.\n");
            policy_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--request")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge safety evaluate: --request requires a file.\n");
            request_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--state")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge safety evaluate: --state requires a file.\n");
            state_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--command")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge safety explain: --command requires a command action.\n");
            command_text = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--mode")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge safety evaluate: --mode requires a value.\n");
            mode = parseMode(argv[index]) catch |err| {
                try stderr.print("aegis-edge safety evaluate: invalid mode: {s}\n", .{@errorName(err)});
                return 64;
            };
        } else {
            try stderr.print("aegis-edge safety evaluate: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected_policy = policy_path orelse return usageError(stderr, "aegis-edge safety evaluate: missing --policy.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var loaded = edge.policy.loadFile(allocator, selected_policy, .{}) catch |err| {
        try stderr.print("Safety policy invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer loaded.deinit();

    var parsed_state: ?edge.policy.ParsedVehicleState = null;
    defer if (parsed_state) |*parsed| parsed.deinit();
    var parsed_command: ?edge.policy.ParsedCommandRequest = null;
    defer if (parsed_command) |*parsed| parsed.deinit();

    const state = if (state_path) |state_file| blk: {
        const state_text = try std.fs.cwd().readFileAlloc(allocator, state_file, 128 * 1024);
        defer allocator.free(state_text);
        parsed_state = edge.policy.parseVehicleStateJsonOwned(allocator, state_text) catch |err| {
            try stderr.print("Edge vehicle state invalid: {s}\n", .{@errorName(err)});
            return 65;
        };
        break :blk parsed_state.?.value;
    } else defaultStateForPolicy(&loaded.value, 1_000_000);

    const command = if (request_path) |request_file| blk: {
        const request_text = try std.fs.cwd().readFileAlloc(allocator, request_file, 128 * 1024);
        defer allocator.free(request_text);
        parsed_command = edge.policy.parseCommandRequestJsonOwned(allocator, request_text) catch |err| {
            try stderr.print("Edge command request invalid: {s}\n", .{@errorName(err)});
            return 65;
        };
        break :blk parsed_command.?.value;
    } else blk: {
        const action_text = command_text orelse return usageError(stderr, if (explain) "aegis-edge safety explain: missing --request/--state or --command.\n" else "aegis-edge safety evaluate: missing --request and --state.\n");
        const action = std.meta.stringToEnum(edge.domain.commands.CommandAction, action_text) orelse {
            try stderr.print("aegis-edge safety explain: unknown command '{s}'.\n", .{action_text});
            return 64;
        };
        break :blk defaultRequestForAction(&loaded.value, action, 1_000_100);
    };

    var evaluation = edge.safety.evaluateSafety(allocator, &loaded.value, state, command, .{
        .mode = mode,
        .now_ms = state.timestamp.value + 500,
        .non_interactive = mode == .ci or mode == .redteam,
    }) catch |err| {
        try stderr.print("Safety evaluation failed: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer evaluation.deinit();
    try writeSafetyEvaluation(stdout, evaluation, json);
    return 0;
}

fn runSafetyScenario(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0 or !std.mem.eql(u8, argv[0], "run")) return usageError(stderr, "aegis-edge safety scenario: expected run --policy <policy> --scenario <scenario>.\n");
    var policy_path: ?[]const u8 = null;
    var scenario_path: ?[]const u8 = null;
    var artifact_dir: ?[]const u8 = null;
    var index: usize = 1;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--policy")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge safety scenario run: --policy requires a file.\n");
            policy_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--scenario")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge safety scenario run: --scenario requires a file.\n");
            scenario_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--artifacts")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge safety scenario run: --artifacts requires a directory.\n");
            artifact_dir = argv[index];
        } else {
            try stderr.print("aegis-edge safety scenario run: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected_policy = policy_path orelse return usageError(stderr, "aegis-edge safety scenario run: missing --policy.\n");
    const selected_scenario = scenario_path orelse return usageError(stderr, "aegis-edge safety scenario run: missing --scenario.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var result = edge.safety.scenario.run(allocator, .{
        .policy_path = selected_policy,
        .scenario_path = selected_scenario,
        .artifact_dir = artifact_dir,
    }) catch |err| {
        try stderr.print("Safety scenario failed: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer result.deinit();
    try stdout.print("{s}\nDecision: {s}\n", .{ result.summary, result.decision.toString() });
    if (result.artifact_dir) |dir| try stdout.print("Artifacts: {s}\n", .{dir});
    try stdout.writeAll("No real hardware, real-flight endpoint, or regulatory validation is implied.\n");
    return 0;
}

fn runHealth(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0) {
        try edge.health.writeDoctor(stdout);
        return 0;
    }
    if (argv.len == 1 and std.mem.eql(u8, argv[0], "--json")) {
        try edge.health.writeJsonStatus(stdout);
        return 0;
    }
    if (std.mem.eql(u8, argv[0], "doctor")) {
        if (argv.len != 1) return usageError(stderr, "aegis-edge health doctor: expected no arguments.\n");
        try edge.health.writeDoctor(stdout);
        return 0;
    }
    if (std.mem.eql(u8, argv[0], "watch")) return runHealthWatch(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "check")) return runHealthCheck(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "report")) return runHealthReport(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "scenario")) {
        if (argv.len >= 2 and std.mem.eql(u8, argv[1], "run")) return runHealthScenario(argv[2..], stdout, stderr);
        return usageError(stderr, "aegis-edge health scenario: expected run.\n");
    }
    try stderr.print("aegis-edge health: unknown subcommand '{s}'.\n", .{argv[0]});
    return 64;
}

fn runWatchdog(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0) return usageError(stderr, "aegis-edge watchdog: expected doctor, simulate, status, or explain.\n");
    if (std.mem.eql(u8, argv[0], "doctor")) {
        if (argv.len != 1) return usageError(stderr, "aegis-edge watchdog doctor: expected no arguments.\n");
        try edge.health.writeDoctor(stdout);
        return 0;
    }
    if (std.mem.eql(u8, argv[0], "simulate")) return runHealthScenario(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "status")) {
        if (argv.len == 3 and std.mem.eql(u8, argv[1], "--session") and std.mem.eql(u8, argv[2], "last")) {
            try stdout.writeAll("Watchdog status for session last: local health events are available in Edge replay when a health scenario writes a session. No real hardware or hosted telemetry is queried.\n");
            return 0;
        }
        return usageError(stderr, "aegis-edge watchdog status: expected --session last.\n");
    }
    if (std.mem.eql(u8, argv[0], "explain")) {
        if (argv.len == 3 and std.mem.eql(u8, argv[1], "--finding")) {
            try stdout.print("Finding {s}: watchdog health finding. Stale, missing, unavailable, or critical health is conservative; degraded mode never bypasses policy or the safety envelope.\n", .{argv[2]});
            return 0;
        }
        return usageError(stderr, "aegis-edge watchdog explain: expected --finding <finding-id>.\n");
    }
    try stderr.print("aegis-edge watchdog: unknown subcommand '{s}'.\n", .{argv[0]});
    return 64;
}

fn runHealthCheck(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var policy_path: ?[]const u8 = null;
    var profile_path: ?[]const u8 = null;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--policy")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge health check: --policy requires a file.\n");
            policy_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--profile")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge health check: --profile requires a file.\n");
            profile_path = argv[index];
        } else {
            try stderr.print("aegis-edge health check: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    if (policy_path != null and profile_path != null) {
        return usageError(stderr, "aegis-edge health check: use either --policy or --profile, not both.\n");
    }
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    if (profile_path) |selected_profile| {
        var profile = edge.deployment.loadProfileFile(allocator, selected_profile) catch |err| {
            try stderr.print("Health deployment profile invalid: {s}\n", .{@errorName(err)});
            return 65;
        };
        defer profile.deinit();
        const check = edge.deployment.checkProfile(profile);
        try stdout.print("Health profile valid: {s} status={s} reason={s}\n", .{ selected_profile, check.status.toString(), check.reason });
        try stdout.writeAll("Runtime health profile checks are local source/package/SITL/bench-preparation only; no hardware is opened.\n");
        return if (check.status == .failed or check.status == .missing or check.status == .unsupported) 65 else 0;
    }
    const selected_policy = policy_path orelse return usageError(stderr, "aegis-edge health check: missing --policy or --profile.\n");
    var loaded = edge.policy.loadFile(allocator, selected_policy, .{}) catch |err| {
        try stderr.print("Health policy invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer loaded.deinit();
    try stdout.print("Health policy valid: watchdog_enabled={} audit_fail_closed={} provenance=fake/SITL/bench only\n", .{ loaded.value.watchdog.enabled, loaded.value.watchdog.audit.fail_closed_on_audit_error });
    return 0;
}

fn runHealthWatch(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var duration_seconds: u64 = 1;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--duration")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge health watch: --duration requires seconds.\n");
            duration_seconds = std.fmt.parseUnsigned(u64, argv[index], 10) catch return usageError(stderr, "aegis-edge health watch: invalid duration.\n");
        } else {
            try stderr.print("aegis-edge health watch: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    if (duration_seconds == 0 or duration_seconds > 3600) return usageError(stderr, "aegis-edge health watch: duration must be 1..3600 seconds.\n");
    try stdout.print("Health watch sample: duration_seconds={d} runtime_health=healthy provenance=fake_adapter\n", .{duration_seconds});
    try stdout.writeAll("Watch mode is deterministic local sampling only; no external network, real hardware, or real-flight endpoint is opened.\n");
    return 0;
}

fn runHealthReport(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 2 and std.mem.eql(u8, argv[0], "--session") and std.mem.eql(u8, argv[1], "last")) {
        var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
        defer _ = gpa_state.deinit();
        const allocator = gpa_state.allocator();
        const root = try std.fs.cwd().realpathAlloc(allocator, ".");
        defer allocator.free(root);
        const session_id = edge.audit.edge_session.resolveSessionId(allocator, root, "last") catch |err| {
            try stdout.print("Health report for session last: unavailable ({s}).\n", .{@errorName(err)});
            try stdout.writeAll("Current local status: unknown; no verified runtime-health evidence was read. No hardware, network, or real-flight endpoint was queried.\n");
            return 0;
        };
        defer allocator.free(session_id);
        const session_dir = try edge.audit.edge_session.sessionDirPath(allocator, root, session_id);
        defer allocator.free(session_dir);
        const runtime_path = try std.fs.path.join(allocator, &.{ session_dir, "evidence", "runtime-health.json" });
        defer allocator.free(runtime_path);
        const text = std.fs.cwd().readFileAlloc(allocator, runtime_path, 128 * 1024) catch |err| {
            try stdout.print("Health report for session {s}: runtime-health evidence unavailable ({s}).\n", .{ session_id, @errorName(err) });
            try stdout.writeAll("Current local status: unknown/unavailable; missing evidence is not treated as healthy.\n");
            return 0;
        };
        defer allocator.free(text);
        const status: []const u8 = if (std.mem.indexOf(u8, text, "\"watchdog_findings\":[{") != null) "degraded_or_critical" else "healthy_or_no_findings";
        try stdout.print("Health report for session {s}: {s}\n", .{ session_id, status });
        try stdout.writeAll("Runtime health evidence summary:\n");
        try stdout.writeAll(text);
        if (text.len == 0 or text[text.len - 1] != '\n') try stdout.writeByte('\n');
        try stdout.writeAll("No hardware, network, or real-flight endpoint was queried.\n");
        return 0;
    }
    return usageError(stderr, "aegis-edge health report: expected --session last.\n");
}

fn runHealthScenario(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var policy_path: ?[]const u8 = null;
    var scenario_path: ?[]const u8 = null;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--policy")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge health scenario run: --policy requires a file.\n");
            policy_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--scenario")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge health scenario run: --scenario requires a file.\n");
            scenario_path = argv[index];
        } else {
            try stderr.print("aegis-edge health scenario run: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const selected_policy = policy_path orelse "examples/edge/health/policies/watchdog-strict.yaml";
    const selected_scenario = scenario_path orelse return usageError(stderr, "aegis-edge health scenario run: missing --scenario.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var loaded = edge.policy.loadFile(allocator, selected_policy, .{}) catch |err| {
        try stderr.print("Health scenario policy invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer loaded.deinit();
    const scenario_text = try std.fs.cwd().readFileAlloc(allocator, selected_scenario, 64 * 1024);
    defer allocator.free(scenario_text);
    const health_fault = scalarField(scenario_text, "health_fault") orelse "none";
    if (!isKnownHealthFault(health_fault)) return usageError(stderr, "aegis-edge health scenario run: unknown health_fault.\n");
    const expected_decision = if (scalarField(scenario_text, "expected_decision")) |value|
        std.meta.stringToEnum(edge.core.decision.DecisionResult, value) orelse return usageError(stderr, "aegis-edge health scenario run: invalid expected_decision.\n")
    else
        null;
    const expected_behavior = if (scalarField(scenario_text, "expected_behavior")) |value|
        edge.health.DegradedBehavior.parse(value) orelse return usageError(stderr, "aegis-edge health scenario run: invalid expected_behavior.\n")
    else
        null;
    const command = std.meta.stringToEnum(edge.domain.commands.CommandAction, scalarField(scenario_text, "command") orelse "read_telemetry") orelse .read_telemetry;
    const now_ms: i128 = 1_003_000;
    var state = defaultStateForPolicy(&loaded.value, now_ms);
    if (std.mem.eql(u8, health_fault, "missing_home_position")) state.home_position = null;
    if (std.mem.eql(u8, health_fault, "critical_battery")) {
        state.battery_state = .{ .percent_remaining = 10, .voltage_v = 14.1, .current_a = 2.2, .is_low = true, .is_critical = true, .source = .monotonic };
    }
    const request = defaultRequestForAction(&loaded.value, command, now_ms);
    const report = healthReportForScenario(health_fault);
    const health_decision = edge.health.decideForCommand(&loaded.value, report, request, state, .{
        .mode = .ci,
        .now_ms = now_ms,
        .non_interactive = true,
    });
    var evaluation = edge.safety.evaluateSafety(allocator, &loaded.value, state, request, .{
        .mode = .ci,
        .now_ms = now_ms,
        .non_interactive = true,
        .health_report = &report,
    }) catch |err| {
        try stderr.print("Health scenario failed: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer evaluation.deinit();
    try stdout.print("Health scenario: {s}\n", .{selected_scenario});
    try stdout.print("Decision: {s}\n", .{evaluation.decision.result.toString()});
    try stdout.print("Runtime health: {s}; degraded_behavior={s}\n", .{ report.overall_status.toString(), health_decision.behavior.toString() });
    try stdout.writeAll("Evidence is deterministic fake/SITL/bench-preparation only; no real hardware, real-flight readiness, or regulatory certification claim.\n");
    if (expected_decision) |expected| {
        if (evaluation.decision.result != expected) {
            try stderr.print("Health scenario expected decision {s}, got {s}.\n", .{ expected.toString(), evaluation.decision.result.toString() });
            return 65;
        }
    }
    if (expected_behavior) |expected| {
        if (health_decision.behavior != expected) {
            try stderr.print("Health scenario expected degraded behavior {s}, got {s}.\n", .{ expected.toString(), health_decision.behavior.toString() });
            return 65;
        }
    }
    return 0;
}

fn runSafetyCase(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0) return usageError(stderr, "aegis-edge safety-case: expected generate, show, verify, or bundle.\n");
    if (std.mem.eql(u8, argv[0], "generate")) return runSafetyCaseGenerate(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "show")) return runSafetyCaseShow(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "verify")) return runSafetyCaseVerify(argv[1..], stdout, stderr);
    if (std.mem.eql(u8, argv[0], "bundle")) return runSafetyCaseBundle(argv[1..], stdout, stderr);
    try stderr.print("aegis-edge safety-case: unknown subcommand '{s}'.\n", .{argv[0]});
    return 64;
}

fn runSafetyCaseGenerate(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var policy_path: ?[]const u8 = null;
    var scenario_path: ?[]const u8 = null;
    var session: []const u8 = "last";
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--policy")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge safety-case generate: --policy requires a file.\n");
            policy_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--scenario")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge safety-case generate: --scenario requires a file.\n");
            scenario_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--session")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge safety-case generate: --session requires a value.\n");
            session = argv[index];
        } else {
            try stderr.print("aegis-edge safety-case generate: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    if (policy_path == null and scenario_path == null and std.mem.eql(u8, session, "last")) {
        return runSafetyCaseShow(&.{ "--session", "last" }, stdout, stderr);
    }
    const selected_policy = policy_path orelse return usageError(stderr, "aegis-edge safety-case generate: missing --policy.\n");
    const selected_scenario = scenario_path orelse return usageError(stderr, "aegis-edge safety-case generate: missing --scenario.\n");
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var result = edge.audit.safety_case.generate(allocator, .{
        .policy_path = selected_policy,
        .scenario_path = selected_scenario,
    }) catch |err| {
        try stderr.print("Safety-case generation failed: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer result.deinit();
    try stdout.print("{s}\nSession: {s}\nArtifacts: {s}\n", .{ result.summary, result.session_id, result.session_dir });
    try stdout.writeAll("Limitations: safety-case evidence is simulation/SITL/bench-preparation/customer-evaluation only; no real-flight or certification claim.\n");
    return 0;
}

fn runSafetyCaseShow(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var session: []const u8 = "last";
    var json = false;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--session")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge safety-case show: --session requires a value.\n");
            session = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--json")) {
            json = true;
        } else {
            try stderr.print("aegis-edge safety-case show: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    const root = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(root);
    edge.audit.safety_case.show(stdout, allocator, root, session, json) catch |err| {
        try stderr.print("Safety-case report unavailable: {s}\n", .{@errorName(err)});
        return 65;
    };
    return 0;
}

fn runSafetyCaseVerify(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    const session = parseSessionOnly(argv, stderr, "aegis-edge safety-case verify") catch return 64;
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    const root = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(root);
    const result = edge.audit.safety_case.verify(allocator, root, session) catch |err| {
        try stderr.print("Safety-case verification failed: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer result.deinit(allocator);
    if (!result.ok) {
        try stderr.print("Safety-case hash chain invalid: {s}\n", .{result.reason orelse "unknown"});
        return 65;
    }
    try stdout.print("Safety-case hash chain verified for session {s}\n", .{session});
    return 0;
}

fn runSafetyCaseBundle(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    const session = parseSessionOnly(argv, stderr, "aegis-edge safety-case bundle") catch return 64;
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    const root = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(root);
    const bundle_dir = edge.audit.safety_case.bundle(allocator, root, session) catch |err| {
        try stderr.print("Safety-case bundle failed: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer allocator.free(bundle_dir);
    try stdout.print("Evidence bundle: {s}\n", .{bundle_dir});
    return 0;
}

fn runEdgeReplay(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var options: edge.audit.edge_replay.ReplayOptions = .{};
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--session")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge replay: --session requires a value.\n");
            options.session = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--verify")) {
            options.verify = true;
        } else if (std.mem.eql(u8, argv[index], "--json")) {
            options.json = true;
        } else if (std.mem.eql(u8, argv[index], "--findings")) {
            options.findings = true;
        } else if (std.mem.eql(u8, argv[index], "--commands")) {
            options.commands = true;
        } else if (std.mem.eql(u8, argv[index], "--approvals")) {
            options.approvals = true;
        } else if (std.mem.eql(u8, argv[index], "--safety-case")) {
            options.safety_case = true;
        } else {
            try stderr.print("aegis-edge replay: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    const root = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(root);
    edge.audit.edge_replay.write(stdout, allocator, root, options) catch |err| {
        try stderr.print("Edge replay failed: {s}\n", .{@errorName(err)});
        return 65;
    };
    return 0;
}

const RedteamCommand = enum { run, list, validate };

const RedteamOptions = struct {
    command: RedteamCommand = .run,
    root_path: []const u8 = "examples/edge/redteam",
    category: ?edge.redteam.fixture.Category = null,
    fixture_id: ?[]const u8 = null,
    environment: ?edge.redteam.fixture.Environment = null,
    output_dir: ?[]const u8 = null,
    deployment_profile: ?[]const u8 = null,
    json: bool = false,
    ci: bool = false,
    safety_case_report: bool = false,
};

fn runRedteam(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    const options = parseRedteamOptions(argv, stderr) catch return 64;
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var fixture_set = edge.redteam.runner.validateFixtures(allocator, .{
        .root_path = options.root_path,
        .category = options.category,
        .fixture_id = options.fixture_id,
        .environment = options.environment,
        .output_dir = options.output_dir,
        .deployment_profile = options.deployment_profile,
        .ci = options.ci,
        .safety_case_report = options.safety_case_report,
    }) catch |err| {
        try stderr.print("aegis-edge redteam: fixture validation failed: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer fixture_set.deinit();
    if (fixture_set.fixtures.len == 0) {
        try stderr.writeAll("aegis-edge redteam: no matching fixtures found.\n");
        return 65;
    }

    switch (options.command) {
        .list => {
            for (fixture_set.fixtures) |fixture| {
                try stdout.print("{s}\t{s}\t{s}\t{s}\n", .{ fixture.id, fixture.category.slug(), fixture.environment.toString(), if (fixture.required) "required" else "optional" });
            }
            return 0;
        },
        .validate => {
            var required_count: usize = 0;
            for (fixture_set.fixtures) |fixture| {
                if (fixture.required) required_count += 1;
            }
            try stdout.print("Validated {d} Edge red-team fixtures ({d} required). No real hardware fixtures are accepted.\n", .{ fixture_set.fixtures.len, required_count });
            return 0;
        },
        .run => {},
    }

    var suite = edge.redteam.runner.runSuite(allocator, fixture_set, .{
        .root_path = options.root_path,
        .category = options.category,
        .fixture_id = options.fixture_id,
        .environment = options.environment,
        .output_dir = options.output_dir,
        .deployment_profile = options.deployment_profile,
        .ci = options.ci,
        .safety_case_report = options.safety_case_report,
    }) catch |err| {
        try stderr.print("aegis-edge redteam: run failed: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer suite.deinit();

    edge.redteam.report.writeArtifacts(allocator, suite, options.safety_case_report) catch |err| {
        try stderr.print("aegis-edge redteam: report generation failed: {s}\n", .{@errorName(err)});
        return 65;
    };

    if (options.json) {
        try edge.redteam.report.writeJson(stdout, suite);
    } else {
        try edge.redteam.report.writeHuman(stdout, suite);
    }
    if (options.ci and !suite.allRequiredPassed()) return 6;
    return 0;
}

fn parseRedteamOptions(argv: []const []const u8, stderr: anytype) !RedteamOptions {
    var options: RedteamOptions = .{};
    var index: usize = 0;
    if (index < argv.len and !std.mem.startsWith(u8, argv[index], "-")) {
        if (std.mem.eql(u8, argv[index], "list")) {
            options.command = .list;
            index += 1;
        } else if (std.mem.eql(u8, argv[index], "validate")) {
            options.command = .validate;
            index += 1;
        }
    }
    while (index < argv.len) : (index += 1) {
        const arg = argv[index];
        if (std.mem.eql(u8, arg, "--ci")) {
            options.ci = true;
        } else if (std.mem.eql(u8, arg, "--json")) {
            options.json = true;
        } else if (std.mem.eql(u8, arg, "--category")) {
            index += 1;
            if (index >= argv.len) return redteamUsage(stderr, "aegis-edge redteam: --category requires a value.\n");
            options.category = edge.redteam.fixture.Category.parse(argv[index]) orelse return redteamUsage(stderr, "aegis-edge redteam: invalid --category.\n");
        } else if (std.mem.eql(u8, arg, "--fixture")) {
            index += 1;
            if (index >= argv.len) return redteamUsage(stderr, "aegis-edge redteam: --fixture requires an id.\n");
            options.fixture_id = argv[index];
        } else if (std.mem.eql(u8, arg, "--environment")) {
            index += 1;
            if (index >= argv.len) return redteamUsage(stderr, "aegis-edge redteam: --environment requires a value.\n");
            options.environment = edge.redteam.fixture.Environment.parse(argv[index]) orelse return redteamUsage(stderr, "aegis-edge redteam: invalid --environment.\n");
        } else if (std.mem.eql(u8, arg, "--output")) {
            index += 1;
            if (index >= argv.len) return redteamUsage(stderr, "aegis-edge redteam: --output requires a directory.\n");
            options.output_dir = argv[index];
        } else if (std.mem.eql(u8, arg, "--deployment-profile")) {
            index += 1;
            if (index >= argv.len) return redteamUsage(stderr, "aegis-edge redteam: --deployment-profile requires a file.\n");
            options.deployment_profile = argv[index];
        } else if (std.mem.eql(u8, arg, "--report")) {
            index += 1;
            if (index >= argv.len) return redteamUsage(stderr, "aegis-edge redteam: --report requires a value.\n");
            if (!std.mem.eql(u8, argv[index], "safety-case")) return redteamUsage(stderr, "aegis-edge redteam: only --report safety-case is supported.\n");
            options.safety_case_report = true;
        } else if (std.mem.eql(u8, arg, "--fixtures-root")) {
            index += 1;
            if (index >= argv.len) return redteamUsage(stderr, "aegis-edge redteam: --fixtures-root requires a directory.\n");
            options.root_path = argv[index];
        } else {
            try stderr.print("aegis-edge redteam: unknown argument '{s}'.\n", .{arg});
            return error.InvalidCliArguments;
        }
    }
    return options;
}

fn redteamUsage(stderr: anytype, message: []const u8) !RedteamOptions {
    try stderr.writeAll(message);
    return error.InvalidCliArguments;
}

fn parseSessionOnly(argv: []const []const u8, stderr: anytype, command_name: []const u8) ![]const u8 {
    var session: []const u8 = "last";
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--session")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.print("{s}: --session requires a value.\n", .{command_name});
                return error.InvalidCliArguments;
            }
            session = argv[index];
        } else {
            try stderr.print("{s}: unknown argument '{s}'.\n", .{ command_name, argv[index] });
            return error.InvalidCliArguments;
        }
    }
    return session;
}

fn parsePolicyOnly(argv: []const []const u8, stderr: anytype, command_name: []const u8) ![]const u8 {
    var policy_path: ?[]const u8 = null;
    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--policy")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.print("{s}: --policy requires a file.\n", .{command_name});
                return error.InvalidCliArguments;
            }
            policy_path = argv[index];
        } else {
            try stderr.print("{s}: unknown argument '{s}'.\n", .{ command_name, argv[index] });
            return error.InvalidCliArguments;
        }
    }
    return policy_path orelse {
        try stderr.print("{s}: missing --policy.\n", .{command_name});
        return error.InvalidCliArguments;
    };
}

fn runPolicyCheck(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var json = false;
    var policy_path: ?[]const u8 = null;
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--json")) {
            json = true;
        } else if (policy_path == null) {
            policy_path = arg;
        } else {
            try stderr.writeAll("aegis-edge policy check: expected one policy path and optional --json.\n");
            return 64;
        }
    }
    const path = policy_path orelse {
        try stderr.writeAll("aegis-edge policy check: missing policy path.\n");
        return 64;
    };

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    var loaded = edge.policy.loadFile(gpa_state.allocator(), path, .{}) catch |err| {
        try stderr.print("Edge policy invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer loaded.deinit();

    if (json) {
        try stdout.writeAll("{\"ok\":true,\"policy\":");
        try edge.core.core.util.writeJsonString(stdout, path);
        try stdout.print(",\"version\":{d}}}\n", .{loaded.value.version});
    } else {
        try stdout.print("Edge policy valid: {s}\n", .{path});
        try stdout.writeAll("No vehicle command mediation is active; this is policy validation only.\n");
    }
    return 0;
}

fn runPolicyExplain(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len < 2) {
        try stderr.writeAll("aegis-edge policy explain: expected <policy> <command> [--mode <mode>] [--json].\n");
        return 64;
    }
    const policy_path = argv[0];
    const action_text = argv[1];
    var mode: edge.policy.EvaluationMode = .strict;
    var json = false;
    var index: usize = 2;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--json")) {
            json = true;
        } else if (std.mem.eql(u8, argv[index], "--mode")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("aegis-edge policy explain: --mode requires a value.\n");
                return 64;
            }
            mode = parseMode(argv[index]) catch |err| {
                try stderr.print("aegis-edge policy explain: invalid mode: {s}\n", .{@errorName(err)});
                return 64;
            };
        } else {
            try stderr.print("aegis-edge policy explain: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();
    var loaded = edge.policy.loadFile(allocator, policy_path, .{}) catch |err| {
        try stderr.print("Edge policy invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer loaded.deinit();
    const action = std.meta.stringToEnum(edge.domain.commands.CommandAction, action_text) orelse {
        try stderr.print("aegis-edge policy explain: unknown command '{s}'.\n", .{action_text});
        return 64;
    };
    const state = defaultStateForPolicy(&loaded.value, 1_000_000);
    const command = defaultRequestForAction(&loaded.value, action, 1_000_100);
    var evaluation = edge.policy.evaluateEdgeAction(allocator, &loaded.value, command, state, .{ .mode = mode, .now_ms = 1_000_500, .non_interactive = mode == .ci }) catch |err| {
        try stderr.print("Edge policy explain failed: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer evaluation.deinit();
    try writeEvaluation(stdout, evaluation, json);
    return 0;
}

fn runPolicyEvaluate(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len < 1) {
        try stderr.writeAll("aegis-edge policy evaluate: expected <policy> --request <request.json> --state <state.json>.\n");
        return 64;
    }
    const policy_path = argv[0];
    var request_path: ?[]const u8 = null;
    var state_path: ?[]const u8 = null;
    var mode: edge.policy.EvaluationMode = .strict;
    var json = false;
    var index: usize = 1;
    while (index < argv.len) : (index += 1) {
        if (std.mem.eql(u8, argv[index], "--json")) {
            json = true;
        } else if (std.mem.eql(u8, argv[index], "--request")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge policy evaluate: --request requires a file.\n");
            request_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--state")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge policy evaluate: --state requires a file.\n");
            state_path = argv[index];
        } else if (std.mem.eql(u8, argv[index], "--mode")) {
            index += 1;
            if (index >= argv.len) return usageError(stderr, "aegis-edge policy evaluate: --mode requires a value.\n");
            mode = parseMode(argv[index]) catch |err| {
                try stderr.print("aegis-edge policy evaluate: invalid mode: {s}\n", .{@errorName(err)});
                return 64;
            };
        } else {
            try stderr.print("aegis-edge policy evaluate: unknown argument '{s}'.\n", .{argv[index]});
            return 64;
        }
    }
    const request_file = request_path orelse return usageError(stderr, "aegis-edge policy evaluate: missing --request.\n");
    const state_file = state_path orelse return usageError(stderr, "aegis-edge policy evaluate: missing --state.\n");

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var loaded = edge.policy.loadFile(allocator, policy_path, .{}) catch |err| {
        try stderr.print("Edge policy invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer loaded.deinit();

    const request_text = try std.fs.cwd().readFileAlloc(allocator, request_file, 128 * 1024);
    defer allocator.free(request_text);
    const state_text = try std.fs.cwd().readFileAlloc(allocator, state_file, 128 * 1024);
    defer allocator.free(state_text);

    var parsed_command = edge.policy.parseCommandRequestJsonOwned(allocator, request_text) catch |err| {
        try stderr.print("Edge command request invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer parsed_command.deinit();
    var parsed_state = edge.policy.parseVehicleStateJsonOwned(allocator, state_text) catch |err| {
        try stderr.print("Edge vehicle state invalid: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer parsed_state.deinit();
    const command = parsed_command.value;
    const state = parsed_state.value;
    var evaluation = edge.policy.evaluateEdgeAction(allocator, &loaded.value, command, state, .{ .mode = mode, .now_ms = state.timestamp.value + 500, .non_interactive = mode == .ci }) catch |err| {
        try stderr.print("Edge policy evaluation failed: {s}\n", .{@errorName(err)});
        return 65;
    };
    defer evaluation.deinit();
    try writeEvaluation(stdout, evaluation, json);
    return 0;
}

fn loadCommandFile(allocator: std.mem.Allocator, path: []const u8, stderr: anytype) !edge.policy.ParsedCommandRequest {
    const text = std.fs.cwd().readFileAlloc(allocator, path, 128 * 1024) catch |err| {
        try stderr.print("Edge command request unreadable: {s}\n", .{@errorName(err)});
        return err;
    };
    defer allocator.free(text);
    return edge.policy.parseCommandRequestJsonOwned(allocator, text) catch |err| {
        try stderr.print("Edge command request invalid: {s}\n", .{@errorName(err)});
        return err;
    };
}

fn loadStateFile(allocator: std.mem.Allocator, path: []const u8, stderr: anytype) !edge.policy.ParsedVehicleState {
    const text = std.fs.cwd().readFileAlloc(allocator, path, 128 * 1024) catch |err| {
        try stderr.print("Edge vehicle state unreadable: {s}\n", .{@errorName(err)});
        return err;
    };
    defer allocator.free(text);
    return edge.policy.parseVehicleStateJsonOwned(allocator, text) catch |err| {
        try stderr.print("Edge vehicle state invalid: {s}\n", .{@errorName(err)});
        return err;
    };
}

fn writeEmergencyDecision(stdout: anytype, decision: edge.emergency.EmergencyDecision, json: bool) !void {
    if (json) {
        try stdout.writeAll("{\"status\":");
        try edge.core.core.util.writeJsonString(stdout, @tagName(decision.status));
        try stdout.writeAll(",\"command\":");
        try edge.core.core.util.writeJsonString(stdout, @tagName(decision.command));
        try stdout.writeAll(",\"reason\":");
        try edge.core.core.util.writeJsonString(stdout, @tagName(decision.reason));
        try stdout.writeAll(",\"policy_decision\":");
        try edge.core.core.util.writeJsonString(stdout, decision.policy_decision.toString());
        try stdout.writeAll(",\"audit_events\":[");
        for (decision.audit_events, 0..) |event, index| {
            if (index > 0) try stdout.writeByte(',');
            try edge.core.core.util.writeJsonString(stdout, event.event_type);
        }
        try stdout.writeAll("]}\n");
        return;
    }
    try stdout.print("Emergency status: {s}\n", .{@tagName(decision.status)});
    try stdout.print("Recommended command: {s}\n", .{@tagName(decision.command)});
    try stdout.print("Reason: {s}\nPolicy decision: {s}\n", .{ @tagName(decision.reason), decision.policy_decision.toString() });
    if (decision.matched_rule) |rule| try stdout.print("Matched rule: {s}\n", .{rule});
    try stdout.writeAll("Fallback order:");
    for (decision.fallback_order) |command| try stdout.print(" {s}", .{@tagName(command)});
    try stdout.writeByte('\n');
    try stdout.writeAll("Audit events:\n");
    for (decision.audit_events) |event| try stdout.print("  - {s}\n", .{event.event_type});
    try stdout.writeAll("No emergency command was sent to real hardware. Emergency mode is policy-evaluated simulation/SITL/bench-preparation behavior only.\n");
}

const EmergencyScenarioSpec = struct {
    id: []u8,
    state_path: []u8,
    reason: edge.emergency.EmergencyReason,
    expected_command: ?edge.emergency.EmergencyCommand = null,

    fn deinit(self: EmergencyScenarioSpec, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.state_path);
    }
};

fn loadEmergencyScenario(allocator: std.mem.Allocator, path: []const u8) !EmergencyScenarioSpec {
    const text = try std.fs.cwd().readFileAlloc(allocator, path, 32 * 1024);
    defer allocator.free(text);
    var id: ?[]const u8 = null;
    var state_path: ?[]const u8 = null;
    var reason: edge.emergency.EmergencyReason = .unknown;
    var expected_command: ?edge.emergency.EmergencyCommand = null;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const no_comment = if (std.mem.indexOfScalar(u8, raw_line, '#')) |comment| raw_line[0..comment] else raw_line;
        const line = std.mem.trim(u8, no_comment, " \t\r");
        if (line.len == 0) continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.InvalidEmergencyScenario;
        const key = std.mem.trim(u8, line[0..colon], " \t");
        const value = cleanScenarioScalar(line[colon + 1 ..]);
        if (std.mem.eql(u8, key, "id") or std.mem.eql(u8, key, "name")) id = value else if (std.mem.eql(u8, key, "state")) state_path = value else if (std.mem.eql(u8, key, "reason")) reason = std.meta.stringToEnum(edge.emergency.EmergencyReason, value) orelse return error.InvalidEmergencyScenario else if (std.mem.eql(u8, key, "expected_command")) expected_command = std.meta.stringToEnum(edge.emergency.EmergencyCommand, value) orelse return error.InvalidEmergencyScenario else if (std.mem.eql(u8, key, "environment")) continue else return error.InvalidEmergencyScenario;
    }
    return .{
        .id = try allocator.dupe(u8, id orelse std.fs.path.stem(path)),
        .state_path = try allocator.dupe(u8, state_path orelse return error.InvalidEmergencyScenario),
        .reason = reason,
        .expected_command = expected_command,
    };
}

fn usageError(stderr: anytype, message: []const u8) !u8 {
    try stderr.writeAll(message);
    return 64;
}

fn runSchema(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len == 0) {
        try stderr.writeAll("aegis-edge schema: expected list or print.\n");
        return 64;
    }

    if (std.mem.eql(u8, argv[0], "list")) {
        if (argv.len != 1) {
            try stderr.writeAll("aegis-edge schema list: expected no arguments.\n");
            return 64;
        }
        for (edge.schema.registry) |descriptor| {
            try stdout.print("{s}\tversion={d}\t{s}\n", .{ descriptor.id, descriptor.version, descriptor.path });
        }
        return 0;
    }

    if (std.mem.eql(u8, argv[0], "print")) {
        if (argv.len != 2) {
            try stderr.writeAll("aegis-edge schema print: expected exactly one schema id.\n");
            return 64;
        }
        const schema_id = argv[1];
        if (std.mem.eql(u8, schema_id, "edge-policy-v1")) {
            return printSchemaDocument(stdout, edge_policy_schema_document);
        }
        if (std.mem.eql(u8, schema_id, "edge-event-v1")) {
            return printSchemaDocument(stdout, edge_event_schema_document);
        }
        if (std.mem.eql(u8, schema_id, "safety-report-v1")) {
            return printSchemaDocument(stdout, safety_report_schema_document);
        }
        try stderr.print("aegis-edge schema print: unknown schema id '{s}'.\n", .{schema_id});
        return 64;
    }

    try stderr.print("aegis-edge schema: unknown subcommand '{s}'.\n", .{argv[0]});
    return 64;
}

fn printSchemaDocument(stdout: anytype, document: []const u8) !u8 {
    try stdout.writeAll(document);
    if (document.len == 0 or document[document.len - 1] != '\n') try stdout.writeByte('\n');
    return 0;
}

fn parseMode(value: []const u8) !edge.policy.EvaluationMode {
    return std.meta.stringToEnum(edge.policy.EvaluationMode, value) orelse error.UnknownEvaluationMode;
}

fn scalarField(text: []const u8, field: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const key = std.mem.trim(u8, line[0..colon], " \t");
        if (!std.mem.eql(u8, key, field)) continue;
        return std.mem.trim(u8, line[colon + 1 ..], " \t\r\"'");
    }
    return null;
}

fn healthReportForScenario(health_fault: []const u8) edge.health.HealthReport {
    if (std.mem.eql(u8, health_fault, "audit_append_failure") or std.mem.eql(u8, health_fault, "audit_failure")) {
        return edge.health.HealthReport.initStatic(.{
            .overall_status = .critical,
            .recommended_behavior = .fail_closed,
            .safe_to_evaluate_commands = false,
            .safe_to_forward_commands = false,
            .findings = &.{edge.health.HealthFinding.init(.{
                .finding_id = "health-audit-fail-closed",
                .domain = .audit_writer,
                .status = .critical,
                .severity = .critical,
                .reason = "audit append failure",
                .observed_value = "append_failed=true",
                .threshold = "append_failed=false",
                .timestamp_ms = 1_003_000,
                .provenance = .fake_adapter,
                .recommended_behavior = .fail_closed,
                .audit_event_reference = "health.audit.failure",
            })},
        });
    }
    if (std.mem.eql(u8, health_fault, "stale_position") or std.mem.eql(u8, health_fault, "stale_state") or std.mem.eql(u8, health_fault, "expired_state") or std.mem.eql(u8, health_fault, "missing_gps") or std.mem.eql(u8, health_fault, "stale_battery")) {
        return edge.health.HealthReport.initStatic(.{
            .overall_status = if (std.mem.eql(u8, health_fault, "expired_state")) .critical else .degraded,
            .recommended_behavior = .deny_movement,
            .findings = &.{edge.health.HealthFinding.init(.{
                .finding_id = "health-telemetry-stale",
                .domain = .telemetry,
                .status = if (std.mem.eql(u8, health_fault, "expired_state")) .critical else .degraded,
                .severity = .high,
                .reason = "telemetry stale or missing",
                .observed_value = "telemetry freshness degraded",
                .threshold = "watchdog telemetry freshness",
                .timestamp_ms = 1_003_000,
                .provenance = .fake_adapter,
                .recommended_behavior = .deny_movement,
                .audit_event_reference = "health.watchdog.finding",
            })},
        });
    }
    if (std.mem.eql(u8, health_fault, "missing_home_position")) {
        return edge.health.HealthReport.initStatic(.{
            .overall_status = .degraded,
            .recommended_behavior = .allow_policy_emergency_only,
            .findings = &.{edge.health.HealthFinding.init(.{
                .finding_id = "health-rth-missing-home",
                .domain = .vehicle_state,
                .status = .degraded,
                .severity = .high,
                .reason = "RTH denied without valid home position",
                .observed_value = "home_position=missing",
                .threshold = "home position required for RTH",
                .timestamp_ms = 1_003_000,
                .provenance = .fake_adapter,
                .recommended_behavior = .allow_policy_emergency_only,
                .audit_event_reference = "health.watchdog.finding",
            })},
        });
    }
    if (std.mem.eql(u8, health_fault, "critical_battery") or std.mem.eql(u8, health_fault, "fallback_land_recommended")) {
        return edge.health.HealthReport.initStatic(.{
            .overall_status = .critical,
            .recommended_behavior = .allow_policy_emergency_only,
            .safe_to_evaluate_commands = true,
            .safe_to_forward_commands = false,
            .findings = &.{edge.health.HealthFinding.init(.{
                .finding_id = "health-critical-battery",
                .domain = .battery_state,
                .status = .critical,
                .severity = .critical,
                .reason = "critical battery requires policy-controlled emergency handling",
                .observed_value = "battery_percent=10",
                .threshold = "land_below_percent configured by policy",
                .timestamp_ms = 1_003_000,
                .provenance = .fake_adapter,
                .recommended_behavior = .allow_policy_emergency_only,
                .audit_event_reference = "health.watchdog.finding",
            })},
        });
    }
    if (std.mem.eql(u8, health_fault, "event_queue_depth_exceeded") or std.mem.eql(u8, health_fault, "queue_overflow")) {
        return edge.health.HealthReport.initStatic(.{
            .overall_status = if (std.mem.eql(u8, health_fault, "queue_overflow")) .critical else .degraded,
            .recommended_behavior = if (std.mem.eql(u8, health_fault, "queue_overflow")) .fail_closed else .deny_high_risk,
            .safe_to_evaluate_commands = !std.mem.eql(u8, health_fault, "queue_overflow"),
            .safe_to_forward_commands = false,
            .findings = &.{edge.health.HealthFinding.init(.{
                .finding_id = if (std.mem.eql(u8, health_fault, "queue_overflow")) "health-command-queue-overflow" else "health-resource-queue-depth",
                .domain = .resource_usage,
                .status = if (std.mem.eql(u8, health_fault, "queue_overflow")) .critical else .degraded,
                .severity = if (std.mem.eql(u8, health_fault, "queue_overflow")) .critical else .warning,
                .reason = if (std.mem.eql(u8, health_fault, "queue_overflow")) "command queue overflow" else "event queue depth exceeded",
                .observed_value = if (std.mem.eql(u8, health_fault, "queue_overflow")) "command_queue_depth exceeded" else "event_queue_depth exceeded",
                .threshold = if (std.mem.eql(u8, health_fault, "queue_overflow")) "watchdog max command queue depth" else "watchdog resource queue depth",
                .timestamp_ms = 1_003_000,
                .provenance = .bench,
                .recommended_behavior = if (std.mem.eql(u8, health_fault, "queue_overflow")) .fail_closed else .deny_high_risk,
                .audit_event_reference = if (std.mem.eql(u8, health_fault, "queue_overflow")) "health.command_queue_overflow" else "health.watchdog.finding",
            })},
        });
    }
    if (std.mem.eql(u8, health_fault, "command_timeout")) {
        return edge.health.HealthReport.initStatic(.{
            .overall_status = .critical,
            .recommended_behavior = .fail_closed,
            .safe_to_evaluate_commands = false,
            .safe_to_forward_commands = false,
            .findings = &.{edge.health.HealthFinding.init(.{
                .finding_id = "health-command-timeout",
                .domain = .core,
                .status = .critical,
                .severity = .critical,
                .reason = "command timeout is not success",
                .observed_value = "pending_command_age exceeded command_timeout_ms",
                .threshold = "watchdog command timeout",
                .timestamp_ms = 1_003_000,
                .provenance = .fake_adapter,
                .recommended_behavior = .fail_closed,
                .audit_event_reference = "health.command_timeout",
            })},
        });
    }
    if (std.mem.eql(u8, health_fault, "missing_adapter_heartbeat") or std.mem.eql(u8, health_fault, "stale_adapter_heartbeat")) {
        return edge.health.HealthReport.initStatic(.{
            .overall_status = .critical,
            .recommended_behavior = .deny_high_risk,
            .safe_to_evaluate_commands = false,
            .safe_to_forward_commands = false,
            .findings = &.{edge.health.HealthFinding.init(.{
                .finding_id = "health-adapter-heartbeat",
                .domain = .adapter,
                .status = .critical,
                .severity = .critical,
                .reason = "adapter heartbeat stale or missing",
                .observed_value = "adapter heartbeat unavailable",
                .threshold = "watchdog heartbeat max age",
                .timestamp_ms = 1_003_000,
                .provenance = .fake_adapter,
                .recommended_behavior = .deny_high_risk,
                .audit_event_reference = "health.watchdog.finding",
            })},
        });
    }
    if (std.mem.eql(u8, health_fault, "missing_mavlink_heartbeat") or std.mem.eql(u8, health_fault, "stale_mavlink_heartbeat")) {
        return edge.health.HealthReport.initStatic(.{
            .overall_status = .unavailable,
            .recommended_behavior = .deny_high_risk,
            .safe_to_evaluate_commands = false,
            .safe_to_forward_commands = false,
            .findings = &.{edge.health.HealthFinding.init(.{
                .finding_id = "health-mavlink-heartbeat",
                .domain = .mavlink,
                .status = .unavailable,
                .severity = .high,
                .reason = "MAVLink heartbeat stale or missing",
                .observed_value = "mavlink heartbeat unavailable",
                .threshold = "watchdog heartbeat max age",
                .timestamp_ms = 1_003_000,
                .provenance = .fake_adapter,
                .recommended_behavior = .deny_high_risk,
                .audit_event_reference = "health.watchdog.finding",
            })},
        });
    }
    if (std.mem.eql(u8, health_fault, "missing_runtime_asset")) {
        return edge.health.HealthReport.initStatic(.{
            .overall_status = .critical,
            .recommended_behavior = .fail_closed,
            .safe_to_evaluate_commands = false,
            .safe_to_forward_commands = false,
            .findings = &.{edge.health.HealthFinding.init(.{
                .finding_id = "health-runtime-asset-missing",
                .domain = .runtime_assets,
                .status = .critical,
                .severity = .critical,
                .reason = "critical runtime asset missing",
                .observed_value = "runtime asset missing",
                .threshold = "required runtime assets present",
                .timestamp_ms = 1_003_000,
                .provenance = .fake_adapter,
                .recommended_behavior = .fail_closed,
                .audit_event_reference = "health.runtime_asset_missing",
            })},
        });
    }
    if (std.mem.eql(u8, health_fault, "missing_policy") or std.mem.eql(u8, health_fault, "policy_failure")) {
        return edge.health.HealthReport.initStatic(.{
            .overall_status = .critical,
            .recommended_behavior = .fail_closed,
            .safe_to_evaluate_commands = false,
            .safe_to_forward_commands = false,
            .findings = &.{edge.health.policy_health.policyFailureFinding("policy engine unavailable or missing policy", 1_003_000, .fake_adapter)},
        });
    }
    if (std.mem.eql(u8, health_fault, "no_safe_fallback")) {
        return edge.health.HealthReport.initStatic(.{
            .overall_status = .critical,
            .recommended_behavior = .no_safe_action,
            .safe_to_evaluate_commands = false,
            .safe_to_forward_commands = false,
            .findings = &.{edge.health.HealthFinding.init(.{
                .finding_id = "health-no-safe-fallback",
                .domain = .vehicle_state,
                .status = .critical,
                .severity = .critical,
                .reason = "no safe fallback conditions are satisfied",
                .observed_value = "home_position/control_context missing",
                .threshold = "fallback requires valid policy and state context",
                .timestamp_ms = 1_003_000,
                .provenance = .fake_adapter,
                .recommended_behavior = .no_safe_action,
                .audit_event_reference = "health.no_safe_fallback",
            })},
        });
    }
    if (std.mem.eql(u8, health_fault, "none")) {
        return edge.health.HealthReport.initStatic(.{ .overall_status = .healthy, .recommended_behavior = .observe_only });
    }
    return edge.health.HealthReport.initStatic(.{
        .overall_status = .critical,
        .recommended_behavior = .deny_high_risk,
        .safe_to_evaluate_commands = false,
        .safe_to_forward_commands = false,
        .findings = &.{edge.health.HealthFinding.init(.{
            .finding_id = "health-agent-stale",
            .domain = .agent,
            .status = .critical,
            .severity = .critical,
            .reason = "agent or adapter heartbeat stale",
            .observed_value = "heartbeat stale or missing",
            .threshold = "watchdog heartbeat max age",
            .timestamp_ms = 1_003_000,
            .provenance = .fake_adapter,
            .recommended_behavior = .deny_high_risk,
            .audit_event_reference = "health.watchdog.finding",
        })},
    });
}

fn isKnownHealthFault(health_fault: []const u8) bool {
    const known = [_][]const u8{
        "none",
        "stale_agent_heartbeat",
        "heartbeat_expired",
        "missing_adapter_heartbeat",
        "stale_adapter_heartbeat",
        "missing_mavlink_heartbeat",
        "stale_mavlink_heartbeat",
        "stale_position",
        "stale_state",
        "expired_state",
        "missing_gps",
        "stale_battery",
        "audit_append_failure",
        "audit_failure",
        "critical_battery",
        "missing_home_position",
        "event_queue_depth_exceeded",
        "queue_overflow",
        "command_timeout",
        "missing_policy",
        "policy_failure",
        "missing_runtime_asset",
        "fallback_land_recommended",
        "no_safe_fallback",
    };
    for (known) |item| {
        if (std.mem.eql(u8, item, health_fault)) return true;
    }
    return false;
}

fn defaultStateForPolicy(policy: *const edge.schema.edge_policy_schema.EdgePolicyV1, timestamp_ms: i128) edge.domain.state.VehicleState {
    const center = if (policy.safety.geofence) |geofence| switch (geofence.shape) {
        .circle => |circle| circle.center,
        .allowed_polygon => |_| edge.domain.coordinates.GeoPoint{ .latitude_deg = 0, .longitude_deg = 0, .altitude_m = 0, .altitude_reference = .amsl },
    } else edge.domain.coordinates.GeoPoint{ .latitude_deg = 0, .longitude_deg = 0, .altitude_m = 20, .altitude_reference = .amsl };
    return .{
        .vehicle_id = .{ .value = "edge-vehicle-1" },
        .vehicle_kind = policy.vehicle.kind,
        .autopilot_kind = policy.vehicle.autopilot,
        .mode = .guided,
        .arm_state = .armed,
        .position = .{
            .latitude_deg = center.latitude_deg,
            .longitude_deg = center.longitude_deg,
            .altitude_m = if (policy.safety.geofence) |geofence| @max(geofence.altitude_floor_m, center.altitude_m + 20) else center.altitude_m,
            .altitude_reference = center.altitude_reference,
        },
        .battery_state = .{ .percent_remaining = 80, .voltage_v = 15.2, .current_a = 2.1, .source = .monotonic },
        .gps_state = .{ .fix_type = .three_d, .satellites_visible = 12, .hdop = 0.8, .is_valid = true, .source = .monotonic },
        .link_state = .{ .connected = true, .last_heartbeat = .{ .value = timestamp_ms, .source = .monotonic }, .packet_loss_percent = 0.1, .source = .monotonic },
        .control_authority = .onboard_agent,
        .home_position = center,
        .timestamp = .{ .value = timestamp_ms, .source = .monotonic },
        .state_freshness = .fresh,
        .provenance = .fake_adapter,
    };
}

fn defaultRequestForAction(policy: *const edge.schema.edge_policy_schema.EdgePolicyV1, action: edge.domain.commands.CommandAction, timestamp_ms: i128) edge.domain.commands.CommandRequest {
    const center = if (policy.safety.geofence) |geofence| switch (geofence.shape) {
        .circle => |circle| circle.center,
        .allowed_polygon => |_| edge.domain.coordinates.GeoPoint{ .latitude_deg = 0, .longitude_deg = 0, .altitude_m = 0, .altitude_reference = .amsl },
    } else edge.domain.coordinates.GeoPoint{ .latitude_deg = 0, .longitude_deg = 0, .altitude_m = 20, .altitude_reference = .amsl };
    const params: edge.domain.commands.CommandParameters = switch (action) {
        .set_waypoint => .{ .waypoint = .{ .latitude_deg = center.latitude_deg, .longitude_deg = center.longitude_deg, .altitude_m = center.altitude_m + 20, .altitude_reference = center.altitude_reference } },
        .set_velocity => .{ .velocity = .{ .vx_mps = 1, .vy_mps = 1, .vz_mps = 0, .frame = .local_ned } },
        .set_altitude, .takeoff => .{ .altitude = .{ .altitude_m = center.altitude_m + 20, .altitude_reference = center.altitude_reference } },
        .set_heading => .{ .heading = edge.domain.coordinates.Heading.degrees(90) },
        .set_mode => .{ .mode = .guided },
        else => .none,
    };
    return edge.domain.commands.CommandRequest.init(.{
        .command_id = "explain-command",
        .vehicle_id = .{ .value = "edge-vehicle-1" },
        .action = action,
        .parameters = params,
        .actor = "aegis-edge-explain",
        .timestamp = .{ .value = timestamp_ms, .source = .monotonic },
        .source = .fake_adapter,
    });
}

fn writeEvaluation(stdout: anytype, evaluation: edge.policy.EdgeEvaluation, json: bool) !void {
    if (json) {
        try stdout.writeAll("{\"result\":");
        try edge.core.core.util.writeJsonString(stdout, evaluation.decision.result.toString());
        try stdout.writeAll(",\"reason\":");
        try edge.core.core.util.writeJsonString(stdout, evaluation.explanation);
        try stdout.writeAll(",\"requires_operator_approval\":");
        try stdout.print("{}", .{evaluation.decision.requires_user});
        try stdout.writeAll(",\"ci_may_proceed\":");
        try stdout.print("{}", .{evaluation.decision.ci_may_proceed});
        if (evaluation.recommended_fallback) |fallback| {
            try stdout.writeAll(",\"recommended_fallback\":");
            try edge.core.core.util.writeJsonString(stdout, @tagName(fallback));
        }
        try stdout.writeAll(",\"audit_events\":[");
        for (evaluation.audit_events, 0..) |event, index| {
            if (index > 0) try stdout.writeByte(',');
            try edge.core.core.util.writeJsonString(stdout, event.event_type);
        }
        try stdout.writeAll("]}\n");
        return;
    }

    try stdout.print("Decision: {s}\n", .{evaluation.decision.result.toString()});
    try stdout.print("Reason: {s}\n", .{evaluation.explanation});
    if (evaluation.matched_rule) |rule| try stdout.print("Matched rule: {s} ({s})\n", .{ rule.id, rule.description });
    if (evaluation.recommended_fallback) |fallback| try stdout.print("Recommended fallback: {s}\n", .{@tagName(fallback)});
    if (evaluation.violated_constraints.len > 0) {
        try stdout.writeAll("Violated constraints:\n");
        for (evaluation.violated_constraints) |constraint| try stdout.print("  - {s}: {s}\n", .{ @tagName(constraint.kind), constraint.message });
    }
    if (evaluation.audit_events.len > 0) {
        try stdout.writeAll("Prepared audit events:\n");
        for (evaluation.audit_events) |event| try stdout.print("  - {s}\n", .{event.event_type});
    }
    try stdout.writeAll("No command was sent to a vehicle, adapter, simulator, or flight controller.\n");
}

fn writeSafetyEvaluation(stdout: anytype, evaluation: edge.safety.SafetyEvaluation, json: bool) !void {
    if (json) {
        try stdout.writeAll("{\"decision\":");
        try edge.core.core.util.writeJsonString(stdout, evaluation.decision.result.toString());
        try stdout.writeAll(",\"explanation\":");
        try edge.core.core.util.writeJsonString(stdout, evaluation.explanation);
        try stdout.writeAll(",\"operator_approval_required\":");
        try stdout.print("{}", .{evaluation.operator_approval_required});
        try stdout.writeAll(",\"ci_may_proceed\":");
        try stdout.print("{}", .{evaluation.ci_may_proceed});
        if (evaluation.risk_score) |score| try stdout.print(",\"risk_score\":{d}", .{score});
        if (evaluation.recommended_fallback) |fallback| {
            try stdout.writeAll(",\"recommended_fallback\":");
            try edge.core.core.util.writeJsonString(stdout, @tagName(fallback));
        }
        try stdout.writeAll(",\"findings\":[");
        for (evaluation.findings, 0..) |finding, index| {
            if (index > 0) try stdout.writeByte(',');
            try stdout.writeByte('{');
            try stdout.writeAll("\"id\":");
            try edge.core.core.util.writeJsonString(stdout, finding.finding_id);
            try stdout.writeAll(",\"category\":");
            try edge.core.core.util.writeJsonString(stdout, @tagName(finding.category));
            try stdout.writeAll(",\"severity\":");
            try edge.core.core.util.writeJsonString(stdout, @tagName(finding.severity));
            if (finding.constraint_id) |constraint_id| {
                try stdout.writeAll(",\"constraint_id\":");
                try edge.core.core.util.writeJsonString(stdout, constraint_id);
            }
            try stdout.writeAll(",\"explanation\":");
            try edge.core.core.util.writeJsonString(stdout, finding.explanation);
            try stdout.writeByte('}');
        }
        try stdout.writeAll("],\"audit_events\":[");
        for (evaluation.audit_events, 0..) |event, index| {
            if (index > 0) try stdout.writeByte(',');
            try edge.core.core.util.writeJsonString(stdout, event.event_type);
        }
        try stdout.writeAll("]}\n");
        return;
    }

    try stdout.print("Decision: {s}\n", .{evaluation.decision.result.toString()});
    try stdout.print("Explanation: {s}\n", .{evaluation.explanation});
    if (evaluation.risk_score) |score| try stdout.print("Risk score: {d}\n", .{score});
    try stdout.print("Operator approval required: {}\n", .{evaluation.operator_approval_required});
    try stdout.print("CI may proceed: {}\n", .{evaluation.ci_may_proceed});
    if (evaluation.matched_rule) |rule| try stdout.print("Matched rule: {s} ({s})\n", .{ rule.id, rule.description });
    if (evaluation.recommended_fallback) |fallback| try stdout.print("Recommended fallback: {s}\n", .{@tagName(fallback)});
    if (evaluation.findings.len > 0) {
        try stdout.writeAll("Safety findings:\n");
        for (evaluation.findings) |finding| {
            try stdout.print("  - {s}/{s}: {s}\n", .{ @tagName(finding.category), @tagName(finding.severity), finding.explanation });
            if (finding.constraint_id) |constraint_id| try stdout.print("    constraint: {s}\n", .{constraint_id});
            if (finding.observed_value) |observed| try stdout.print("    observed: {s}\n", .{observed});
            if (finding.limit_value) |limit| try stdout.print("    limit: {s}\n", .{limit});
        }
    }
    if (evaluation.violated_constraints.len > 0) {
        try stdout.writeAll("Violated constraints:\n");
        for (evaluation.violated_constraints) |constraint| try stdout.print("  - {s}: {s}\n", .{ @tagName(constraint.kind), constraint.message });
    }
    if (evaluation.audit_events.len > 0) {
        try stdout.writeAll("Prepared audit events:\n");
        for (evaluation.audit_events) |event| try stdout.print("  - {s}\n", .{event.event_type});
    }
    try stdout.writeAll("No command was sent to a vehicle, adapter, simulator, or flight controller.\n");
}

fn readFileOrHex(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    const text = std.fs.cwd().readFileAlloc(allocator, value, 16 * 1024) catch |err| switch (err) {
        error.FileNotFound => return parseHexAlloc(allocator, value),
        else => return err,
    };
    errdefer allocator.free(text);
    if (text.len > 0 and (text[0] == edge.mavlink.framing.magic_v1 or text[0] == edge.mavlink.framing.magic_v2)) return text;
    const parsed = try parseHexAlloc(allocator, text);
    allocator.free(text);
    return parsed;
}

fn parseHexAlloc(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var compact: std.ArrayList(u8) = .empty;
    defer compact.deinit(allocator);
    var index: usize = 0;
    while (index < text.len) : (index += 1) {
        const byte = text[index];
        switch (byte) {
            ' ', '\t', '\r', '\n', ':', '_' => continue,
            '0' => if (index + 1 < text.len and (text[index + 1] == 'x' or text[index + 1] == 'X')) {
                index += 1;
                continue;
            },
            else => {},
        }
        try compact.append(allocator, byte);
    }
    if (compact.items.len == 0 or compact.items.len % 2 != 0) return error.InvalidHex;
    var bytes = try allocator.alloc(u8, compact.items.len / 2);
    errdefer allocator.free(bytes);
    var out_index: usize = 0;
    while (out_index < bytes.len) : (out_index += 1) {
        const hi = hexValue(compact.items[out_index * 2]) orelse return error.InvalidHex;
        const lo = hexValue(compact.items[out_index * 2 + 1]) orelse return error.InvalidHex;
        bytes[out_index] = (hi << 4) | lo;
    }
    return bytes;
}

fn hexValue(byte: u8) ?u8 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        'A'...'F' => byte - 'A' + 10,
        else => null,
    };
}

const Scenario = struct {
    allocator: std.mem.Allocator,
    frame_path: []u8,
    frame_bytes: []u8,
    expected_decision: ?edge.core.decision.DecisionResult = null,
    expected_forwarded: ?bool = null,

    fn deinit(self: *Scenario) void {
        self.allocator.free(self.frame_path);
        self.allocator.free(self.frame_bytes);
        self.* = undefined;
    }
};

fn loadScenario(allocator: std.mem.Allocator, scenario_path: []const u8) !Scenario {
    const text = try std.fs.cwd().readFileAlloc(allocator, scenario_path, 32 * 1024);
    defer allocator.free(text);

    var frame_value: ?[]const u8 = null;
    var expected_decision: ?edge.core.decision.DecisionResult = null;
    var expected_forwarded: ?bool = null;

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const no_comment = if (std.mem.indexOfScalar(u8, raw_line, '#')) |index| raw_line[0..index] else raw_line;
        const line = std.mem.trim(u8, no_comment, " \t\r");
        if (line.len == 0) continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.InvalidScenario;
        const key = std.mem.trim(u8, line[0..colon], " \t");
        const value = cleanScenarioScalar(line[colon + 1 ..]);
        if (std.mem.eql(u8, key, "frame")) {
            frame_value = value;
        } else if (std.mem.eql(u8, key, "expected_decision")) {
            expected_decision = std.meta.stringToEnum(edge.core.decision.DecisionResult, value) orelse return error.InvalidScenarioDecision;
        } else if (std.mem.eql(u8, key, "expected_forwarded")) {
            expected_forwarded = parseScenarioBool(value) catch return error.InvalidScenarioForwarded;
        } else if (std.mem.eql(u8, key, "transport")) {
            if (!std.mem.eql(u8, value, "fake_transport")) return error.UnsupportedScenarioTransport;
        }
    }

    const frame_ref = frame_value orelse return error.MissingScenarioFrame;
    const frame_path = try resolveScenarioPath(allocator, scenario_path, frame_ref);
    errdefer allocator.free(frame_path);
    const frame_bytes = try readFileOrHex(allocator, frame_path);
    errdefer allocator.free(frame_bytes);
    return .{
        .allocator = allocator,
        .frame_path = frame_path,
        .frame_bytes = frame_bytes,
        .expected_decision = expected_decision,
        .expected_forwarded = expected_forwarded,
    };
}

fn resolveScenarioPath(allocator: std.mem.Allocator, scenario_path: []const u8, frame_ref: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(frame_ref)) return try allocator.dupe(u8, frame_ref);
    const scenario_dir = std.fs.path.dirname(scenario_path) orelse ".";
    return try std.fs.path.join(allocator, &.{ scenario_dir, frame_ref });
}

fn cleanScenarioScalar(raw: []const u8) []const u8 {
    var value = std.mem.trim(u8, raw, " \t\r");
    if (value.len >= 2) {
        const first = value[0];
        const last = value[value.len - 1];
        if ((first == '"' and last == '"') or (first == '\'' and last == '\'')) value = value[1 .. value.len - 1];
    }
    return value;
}

fn parseScenarioBool(value: []const u8) !bool {
    if (std.mem.eql(u8, value, "true")) return true;
    if (std.mem.eql(u8, value, "false")) return false;
    return error.InvalidBool;
}

test "aegis-edge help is honest policy evaluation output" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [128]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    const argv = [_][]const u8{"--help"};

    const code = try run(argv[0..], stdout_stream.writer(), stderr_stream.writer());

    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "policy evaluate") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "PX4 and ArduPilot SITL are opt-in local simulation only") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "aegis-edge schema print uses embedded edge policy schema" {
    var stdout_buf: [16384]u8 = undefined;
    var stderr_buf: [128]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    const argv = [_][]const u8{ "schema", "print", "edge-policy-v1" };

    const code = try run(argv[0..], stdout_stream.writer(), stderr_stream.writer());

    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "\"required\": [\"version\", \"vehicle\", \"safety\", \"commands\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "domain-schema-only") == null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "aegis-edge schema print works outside repository cwd" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const original_cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(original_cwd);
    const tmp_cwd = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_cwd);
    try std.posix.chdir(tmp_cwd);
    defer std.posix.chdir(original_cwd) catch {};

    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [128]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    const argv = [_][]const u8{ "schema", "print", "edge-event-v1" };

    const code = try run(argv[0..], stdout_stream.writer(), stderr_stream.writer());

    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "\"event_type\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "mavlink.command_denied") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "aegis-edge schema list is honest domain/schema output" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [128]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    const argv = [_][]const u8{ "schema", "list" };

    const code = try run(argv[0..], stdout_stream.writer(), stderr_stream.writer());

    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "edge-policy-v1") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "aegis-edge policy explain supplies safe defaults for heading and mode commands" {
    inline for (.{ "set_heading", "set_mode" }) |command| {
        var stdout_buf: [4096]u8 = undefined;
        var stderr_buf: [512]u8 = undefined;
        var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
        var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
        const argv = [_][]const u8{ "policy", "explain", "examples/edge/policies/geofence-basic.yaml", command };

        const code = try run(argv[0..], stdout_stream.writer(), stderr_stream.writer());

        try std.testing.expectEqual(@as(u8, 0), code);
        try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Decision:") != null);
        try std.testing.expectEqualStrings("", stderr_stream.getWritten());
    }
}

test "aegis-edge policy check json escapes policy path" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const policy_text =
        \\version: 1
        \\vehicle:
        \\  kind: drone_multirotor
        \\  autopilot: px4
        \\  adapter: fake
        \\safety:
        \\  state_freshness:
        \\    max_state_age_ms: 1000
        \\    deny_commands_on_stale_state: true
        \\commands:
        \\  allow:
        \\    - read_telemetry
    ;
    try tmp.dir.writeFile(.{ .sub_path = "edge\"policy.yaml", .data = policy_text });
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    const policy_path = try std.fs.path.join(std.testing.allocator, &.{ root, "edge\"policy.yaml" });
    defer std.testing.allocator.free(policy_path);

    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    const argv = [_][]const u8{ "policy", "check", policy_path, "--json" };

    const code = try run(argv[0..], stdout_stream.writer(), stderr_stream.writer());

    try std.testing.expectEqual(@as(u8, 0), code);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, stdout_stream.getWritten(), .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings(policy_path, parsed.value.object.get("policy").?.string);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "aegis-edge mavlink doctor inspect classify and simulate use fake transport only" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const doctor_argv = [_][]const u8{ "mavlink", "doctor" };
    try std.testing.expectEqual(@as(u8, 0), try run(doctor_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "fake_transport") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "signing verification") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    stdout_stream.reset();
    stderr_stream.reset();
    const inspect_argv = [_][]const u8{ "mavlink", "inspect-frame", "fd2100002c2abf4c00000000803f0000000000000000000000000000000000000000000000009001010100b569" };
    try std.testing.expectEqual(@as(u8, 0), try run(inspect_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "COMMAND_LONG") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "CRC: valid") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    stdout_stream.reset();
    stderr_stream.reset();
    const classify_argv = [_][]const u8{ "mavlink", "classify", "fd2100002c2abf4c00000000000000000000000000000000000000000000000000000000f04116000101008700" };
    try std.testing.expectEqual(@as(u8, 0), try run(classify_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Mapped Edge action: takeoff") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    stdout_stream.reset();
    stderr_stream.reset();
    const simulate_argv = [_][]const u8{
        "mavlink",
        "simulate",
        "--policy",
        "examples/edge/mavlink/policies/geofence-mavlink-basic.yaml",
        "--scenario",
        "examples/edge/mavlink/scenarios/geofence-deny.yaml",
    };
    try std.testing.expectEqual(@as(u8, 0), try run(simulate_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Decision: deny") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "No serial hardware, SITL, ROS2, or hardware endpoint was opened") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "aegis-edge safety commands evaluate and scenario-run without hardware" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const doctor_argv = [_][]const u8{ "safety", "doctor" };
    try std.testing.expectEqual(@as(u8, 0), try run(doctor_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "flight safety enforcement") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "No hardware") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    stdout_stream.reset();
    stderr_stream.reset();
    const check_argv = [_][]const u8{ "safety", "check", "--policy", "examples/edge/safety/policies/safety-geofence-basic.yaml" };
    try std.testing.expectEqual(@as(u8, 0), try run(check_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Safety envelope valid") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    stdout_stream.reset();
    stderr_stream.reset();
    const evaluate_argv = [_][]const u8{
        "safety",
        "evaluate",
        "--policy",
        "examples/edge/safety/policies/safety-geofence-basic.yaml",
        "--request",
        "examples/edge/safety/requests/waypoint-outside-geofence.json",
        "--state",
        "examples/edge/safety/states/fresh-state.json",
    };
    try std.testing.expectEqual(@as(u8, 0), try run(evaluate_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Decision: deny") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "geofence/high") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    stdout_stream.reset();
    stderr_stream.reset();
    const scenario_argv = [_][]const u8{
        "safety",
        "scenario",
        "run",
        "--policy",
        "examples/edge/safety/policies/safety-strict.yaml",
        "--scenario",
        "examples/edge/safety/scenarios/mission-outside-geofence-deny.yaml",
        "--artifacts",
        root,
    };
    try std.testing.expectEqual(@as(u8, 0), try run(scenario_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Decision: deny") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "real-flight") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "aegis-edge health scenario validates expected decision and behavior" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const critical_argv = [_][]const u8{
        "health",
        "scenario",
        "run",
        "--policy",
        "examples/edge/health/policies/watchdog-emergency-policy.yaml",
        "--scenario",
        "examples/edge/health/scenarios/critical-battery-emergency-land.yaml",
    };
    try std.testing.expectEqual(@as(u8, 0), try run(critical_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Decision: allow") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "degraded_behavior=allow_policy_emergency_only") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const mismatch =
        \\id: health-mismatch
        \\environment: fake_adapter
        \\provenance: fake_adapter
        \\command: land
        \\expected_decision: allow
        \\health_fault: audit_append_failure
        \\expected_behavior: fail_closed
        \\note: mismatched expected decision must fail the CLI scenario.
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = "health-mismatch.yaml", .data = mismatch });
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    const scenario_path = try std.fs.path.join(std.testing.allocator, &.{ root, "health-mismatch.yaml" });
    defer std.testing.allocator.free(scenario_path);

    stdout_stream.reset();
    stderr_stream.reset();
    const mismatch_argv = [_][]const u8{
        "health",
        "scenario",
        "run",
        "--policy",
        "examples/edge/health/policies/watchdog-strict.yaml",
        "--scenario",
        scenario_path,
    };
    try std.testing.expectEqual(@as(u8, 65), try run(mismatch_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Decision: deny") != null);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "expected decision allow, got deny") != null);

    stdout_stream.reset();
    stderr_stream.reset();
    const watch_argv = [_][]const u8{ "health", "watch", "--duration", "1" };
    try std.testing.expectEqual(@as(u8, 0), try run(watch_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Health watch sample") != null);

    stdout_stream.reset();
    stderr_stream.reset();
    const profile_argv = [_][]const u8{ "health", "check", "--profile", "examples/edge/deployment/profiles/source-local-fake.yaml" };
    try std.testing.expectEqual(@as(u8, 0), try run(profile_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Health profile valid") != null);

    stdout_stream.reset();
    stderr_stream.reset();
    const ambiguous_check_argv = [_][]const u8{ "health", "check", "--policy", "examples/edge/health/policies/watchdog-strict.yaml", "--profile", "examples/edge/deployment/profiles/source-local-fake.yaml" };
    try std.testing.expectEqual(@as(u8, 64), try run(ambiguous_check_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "either --policy or --profile") != null);

    stdout_stream.reset();
    stderr_stream.reset();
    const report_argv = [_][]const u8{ "health", "report", "--session", "last" };
    try std.testing.expectEqual(@as(u8, 0), try run(report_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Health report for session") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "healthy placeholder") == null);

    stdout_stream.reset();
    stderr_stream.reset();
    const watchdog_argv = [_][]const u8{ "watchdog", "simulate", "--scenario", "examples/edge/health/scenarios/heartbeat-expired.yaml" };
    try std.testing.expectEqual(@as(u8, 0), try run(watchdog_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Decision: deny") != null);

    stdout_stream.reset();
    stderr_stream.reset();
    const asset_argv = [_][]const u8{ "watchdog", "simulate", "--scenario", "examples/edge/health/scenarios/missing-runtime-asset.yaml" };
    try std.testing.expectEqual(@as(u8, 0), try run(asset_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Runtime health: critical") != null);
}

test "aegis-edge mavlink simulate reads scenario frame contents instead of filename" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const land_hex = try std.fs.cwd().readFileAlloc(std.testing.allocator, "examples/edge/mavlink/frames/command-land.hex", 1024);
    defer std.testing.allocator.free(land_hex);
    try tmp.dir.writeFile(.{ .sub_path = "renamed-frame.hex", .data = land_hex });
    const neutral_scenario =
        \\name: neutral-name
        \\transport: fake_transport
        \\frame: renamed-frame.hex
        \\expected_decision: allow
        \\expected_forwarded: true
    ;
    try tmp.dir.writeFile(.{ .sub_path = "neutral-name.yaml", .data = neutral_scenario });
    const mismatch_scenario =
        \\name: mismatch
        \\transport: fake_transport
        \\frame: renamed-frame.hex
        \\expected_decision: deny
        \\expected_forwarded: false
    ;
    try tmp.dir.writeFile(.{ .sub_path = "mismatch.yaml", .data = mismatch_scenario });
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    const scenario_path = try std.fs.path.join(std.testing.allocator, &.{ root, "neutral-name.yaml" });
    defer std.testing.allocator.free(scenario_path);
    const mismatch_path = try std.fs.path.join(std.testing.allocator, &.{ root, "mismatch.yaml" });
    defer std.testing.allocator.free(mismatch_path);

    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);
    const simulate_argv = [_][]const u8{
        "mavlink",
        "simulate",
        "--policy",
        "examples/edge/mavlink/policies/geofence-mavlink-basic.yaml",
        "--scenario",
        scenario_path,
    };
    try std.testing.expectEqual(@as(u8, 0), try run(simulate_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Decision: allow") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Forwarded: true") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    stdout_stream.reset();
    stderr_stream.reset();
    const mismatch_argv = [_][]const u8{
        "mavlink",
        "simulate",
        "--policy",
        "examples/edge/mavlink/policies/geofence-mavlink-basic.yaml",
        "--scenario",
        mismatch_path,
    };
    try std.testing.expectEqual(@as(u8, 65), try run(mismatch_argv[0..], stdout_stream.writer(), stderr_stream.writer()));
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "MAVLink scenario expectation failed") != null);
}
