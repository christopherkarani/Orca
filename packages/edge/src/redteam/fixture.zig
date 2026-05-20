const std = @import("std");
const core = @import("orca_core");

pub const max_fixture_yaml_bytes: usize = 96 * 1024;

pub const Category = enum {
    geofence,
    altitude,
    velocity,
    battery,
    stale_state,
    mission,
    mavlink_parser,
    mavlink_command,
    endpoint_spoofing,
    approval_bypass,
    emergency_bypass,
    mode_authority,
    telemetry_fault,
    px4_sitl,
    ardupilot_sitl,
    data_guard,
    health,
    audit_redaction,
    safety_case,
    unsupported_feature,

    pub fn parse(value: []const u8) ?Category {
        inline for (std.meta.fields(Category)) |field| {
            if (matchesNormalized(field.name, value)) return @field(Category, field.name);
        }
        return null;
    }

    pub fn slug(self: Category) []const u8 {
        return switch (self) {
            .approval_bypass => "approval-bypass",
            .emergency_bypass => "emergency-bypass",
            .mode_authority => "mode-authority",
            .stale_state => "stale-state",
            .mavlink_parser => "mavlink-parser",
            .mavlink_command => "mavlink-command",
            .endpoint_spoofing => "endpoint-spoofing",
            .telemetry_fault => "telemetry-fault",
            .px4_sitl => "px4-sitl",
            .ardupilot_sitl => "ardupilot-sitl",
            .data_guard => "data-guard",
            .health => "health",
            .audit_redaction => "audit-redaction",
            .safety_case => "safety-case",
            .unsupported_feature => "unsupported-feature",
            else => @tagName(self),
        };
    }

    pub fn display(self: Category) []const u8 {
        return switch (self) {
            .geofence => "Geofence",
            .altitude => "Altitude",
            .velocity => "Velocity",
            .battery => "Battery",
            .stale_state => "State Freshness",
            .mission => "Mission",
            .mavlink_parser => "MAVLink Parser",
            .mavlink_command => "MAVLink Command",
            .endpoint_spoofing => "Endpoint Spoofing",
            .approval_bypass => "Approval Bypass",
            .emergency_bypass => "Emergency Bypass",
            .mode_authority => "Mode Authority",
            .telemetry_fault => "Telemetry Fault",
            .px4_sitl => "PX4 SITL",
            .ardupilot_sitl => "ArduPilot SITL",
            .data_guard => "Data Guard",
            .health => "Health/Watchdog",
            .audit_redaction => "Audit Redaction",
            .safety_case => "Safety Case",
            .unsupported_feature => "Unsupported Feature",
        };
    }
};

pub const Environment = enum {
    fake_adapter,
    fake_px4_adapter,
    fake_ardupilot_adapter,
    px4_sitl,
    ardupilot_sitl,

    pub fn parse(value: []const u8) ?Environment {
        inline for (std.meta.fields(Environment)) |field| {
            if (matchesNormalized(field.name, value)) return @field(Environment, field.name);
        }
        return null;
    }

    pub fn toString(self: Environment) []const u8 {
        return @tagName(self);
    }
};

pub const FaultType = enum {
    stale_position,
    expired_position,
    stale_battery,
    unknown_battery,
    invalid_gps_fix,
    poor_gps_accuracy,
    missing_home_position,
    unknown_mode,
    unknown_control_authority,
    low_battery,
    critical_battery,
    outside_geofence_current_position,
    waypoint_outside_geofence,
    altitude_above_ceiling,
    altitude_below_floor,
    velocity_too_high,
    horizontal_velocity_too_high,
    vertical_velocity_too_high,
    unknown_velocity_frame,
    unknown_coordinate_frame,
    mismatched_altitude_reference,
    unknown_command,
    critical_command,
    disable_failsafe,
    disable_geofence,
    raw_actuator_output,
    override_operator,
    payload_release,
    firmware_update,
    mission_item_outside_geofence,
    mission_altitude_violation,
    partial_mission_upload,
    duplicate_mission_item,
    missing_mission_item,
    unsupported_mission_item,
    mission_start_without_safe_mission,
    malformed_frame,
    truncated_frame,
    oversized_frame,
    bad_checksum,
    unknown_message_id,
    unknown_command_id,
    unexpected_sysid,
    unexpected_compid,
    replayed_sequence,
    duplicate_message,
    signing_absent_when_required,
    signing_unsupported,
    binary_payload_with_fake_secret,
    expired_approval,
    mismatched_policy_hash,
    mismatched_command_hash,
    mismatched_vehicle_id,
    mismatched_state_hash,
    reused_one_time_approval,
    broad_approval_not_allowed,
    approval_attempt_for_non_overridable_command,
    approval_cannot_bypass_geofence,
    approval_cannot_disable_failsafe,
    emergency_attempt_to_disable_failsafe,
    emergency_attempt_raw_actuator,
    rth_without_home_position,
    land_on_stale_state_without_policy,
    emergency_override_operator_attempt,
    no_safe_fallback_available,
    unsupported_polygon_geofence,
    fake_secret_in_request,
    fake_secret_in_mavlink_payload,
    safety_case_fake_secret_check,
    mission_plan_exfiltration,
    exact_geolocation_exfiltration,
    fake_secret_payload_exfiltration,
    video_stream_unknown_endpoint,
    direct_ip_egress,
    webhook_egress,
    tunnel_egress,
    paste_site_egress,
    long_query_exfiltration,
    high_entropy_dns_label,
    unknown_endpoint_egress,
    repeated_unknown_endpoint_egress,
    safety_report_customer_allow,
    telemetry_ground_control_allow,
    stale_agent_heartbeat,
    stale_adapter_heartbeat,
    stale_mavlink_heartbeat,
    stale_telemetry_watchdog,
    audit_failure_watchdog,
    missing_policy_watchdog,
    health_missing_home_position,
    health_critical_battery_land,
    event_queue_depth_exceeded,
    fake_secret_in_health_payload,

    pub fn parse(value: []const u8) ?FaultType {
        inline for (std.meta.fields(FaultType)) |field| {
            if (matchesNormalized(field.name, value)) return @field(FaultType, field.name);
        }
        return null;
    }

    pub fn toString(self: FaultType) []const u8 {
        return @tagName(self);
    }
};

pub const Requirements = struct {
    px4_sitl: bool = false,
    ardupilot_sitl: bool = false,
    real_hardware: bool = false,
    capabilities: []const []const u8 = &.{},

    pub fn deinit(self: Requirements, allocator: std.mem.Allocator) void {
        freeStringList(allocator, self.capabilities);
    }
};

pub const Expected = struct {
    status: ?@import("../audit/safety_report.zig").ScenarioResultStatus = null,
    decision: core.decision.DecisionResult,
    findings: []const []const u8 = &.{},
    events: []const []const u8 = &.{},
    no_log_contains: []const []const u8 = &.{},

    pub fn deinit(self: Expected, allocator: std.mem.Allocator) void {
        freeStringList(allocator, self.findings);
        freeStringList(allocator, self.events);
        freeStringList(allocator, self.no_log_contains);
    }
};

pub const Score = struct {
    points: u32 = 1,
};

pub const Fixture = struct {
    allocator: std.mem.Allocator,
    path: []u8,
    version: u16,
    id: []u8,
    name: []u8,
    category: Category,
    environment: Environment,
    description: []u8,
    policy_path: ?[]u8 = null,
    state_path: ?[]u8 = null,
    request_path: ?[]u8 = null,
    scenario_path: ?[]u8 = null,
    mavlink_frames: []const []const u8 = &.{},
    faults: []const FaultType = &.{},
    expected: Expected,
    requirements: Requirements = .{},
    skip_conditions: []const []const u8 = &.{},
    limitations: []const []const u8 = &.{},
    required: bool = true,
    score: Score = .{},

    pub fn deinit(self: *Fixture) void {
        self.allocator.free(self.path);
        self.allocator.free(self.id);
        self.allocator.free(self.name);
        self.allocator.free(self.description);
        if (self.policy_path) |value| self.allocator.free(value);
        if (self.state_path) |value| self.allocator.free(value);
        if (self.request_path) |value| self.allocator.free(value);
        if (self.scenario_path) |value| self.allocator.free(value);
        freeStringList(self.allocator, self.mavlink_frames);
        if (self.faults.len > 0) self.allocator.free(self.faults);
        self.expected.deinit(self.allocator);
        self.requirements.deinit(self.allocator);
        freeStringList(self.allocator, self.skip_conditions);
        freeStringList(self.allocator, self.limitations);
        self.* = undefined;
    }
};

pub const FixtureSet = struct {
    allocator: std.mem.Allocator,
    fixtures: []Fixture,

    pub fn deinit(self: *FixtureSet) void {
        for (self.fixtures) |*item| item.deinit();
        if (self.fixtures.len > 0) self.allocator.free(self.fixtures);
        self.* = undefined;
    }
};

const Section = enum {
    root,
    faults,
    expected,
    expected_findings,
    expected_events,
    expected_no_log_contains,
    requirements,
    requirements_capabilities,
    skip_conditions,
    limitations,
    mavlink_frames,
    score,
};

const Builder = struct {
    allocator: std.mem.Allocator,
    path: []const u8,
    version: ?u16 = null,
    id: ?[]u8 = null,
    name: ?[]u8 = null,
    category: ?Category = null,
    environment: ?Environment = null,
    description: ?[]u8 = null,
    policy_path: ?[]u8 = null,
    state_path: ?[]u8 = null,
    request_path: ?[]u8 = null,
    scenario_path: ?[]u8 = null,
    required: bool = true,
    expected_status: ?@import("../audit/safety_report.zig").ScenarioResultStatus = null,
    expected_decision: ?core.decision.DecisionResult = null,
    expected_findings: std.ArrayList([]const u8) = .empty,
    expected_events: std.ArrayList([]const u8) = .empty,
    expected_no_log_contains: std.ArrayList([]const u8) = .empty,
    faults: std.ArrayList(FaultType) = .empty,
    mavlink_frames: std.ArrayList([]const u8) = .empty,
    px4_sitl: bool = false,
    ardupilot_sitl: bool = false,
    real_hardware: bool = false,
    capabilities: std.ArrayList([]const u8) = .empty,
    skip_conditions: std.ArrayList([]const u8) = .empty,
    limitations: std.ArrayList([]const u8) = .empty,
    points: ?u32 = null,

    fn init(allocator: std.mem.Allocator, path: []const u8) Builder {
        return .{ .allocator = allocator, .path = path };
    }

    fn deinit(self: *Builder) void {
        if (self.id) |value| self.allocator.free(value);
        if (self.name) |value| self.allocator.free(value);
        if (self.description) |value| self.allocator.free(value);
        if (self.policy_path) |value| self.allocator.free(value);
        if (self.state_path) |value| self.allocator.free(value);
        if (self.request_path) |value| self.allocator.free(value);
        if (self.scenario_path) |value| self.allocator.free(value);
        freeList(self.allocator, &self.expected_findings);
        freeList(self.allocator, &self.expected_events);
        freeList(self.allocator, &self.expected_no_log_contains);
        self.faults.deinit(self.allocator);
        freeList(self.allocator, &self.mavlink_frames);
        freeList(self.allocator, &self.capabilities);
        freeList(self.allocator, &self.skip_conditions);
        freeList(self.allocator, &self.limitations);
    }

    fn dupSet(self: *Builder, target: *?[]u8, value: []const u8) !void {
        if (target.*) |old| self.allocator.free(old);
        target.* = try self.allocator.dupe(u8, try parseScalar(value));
    }

    fn appendString(self: *Builder, section: Section, value: []const u8) !void {
        const owned = try self.allocator.dupe(u8, try parseScalar(value));
        errdefer self.allocator.free(owned);
        switch (section) {
            .expected_findings => try self.expected_findings.append(self.allocator, owned),
            .expected_events => try self.expected_events.append(self.allocator, owned),
            .expected_no_log_contains => try self.expected_no_log_contains.append(self.allocator, owned),
            .requirements_capabilities => try self.capabilities.append(self.allocator, owned),
            .skip_conditions => try self.skip_conditions.append(self.allocator, owned),
            .limitations => try self.limitations.append(self.allocator, owned),
            .mavlink_frames => try self.mavlink_frames.append(self.allocator, owned),
            else => return error.InvalidRedteamFixture,
        }
    }

    fn appendFault(self: *Builder, value: []const u8) !void {
        const fault = FaultType.parse(try parseScalar(value)) orelse return error.InvalidRedteamFault;
        try self.faults.append(self.allocator, fault);
    }

    fn toFixture(self: *Builder) !Fixture {
        const version = self.version orelse return error.InvalidRedteamFixture;
        if (version != 1) return error.UnsupportedRedteamFixtureVersion;
        if (self.real_hardware) return error.RealHardwareFixturesUnsupported;
        const id = self.id orelse return error.InvalidRedteamFixture;
        const name = self.name orelse return error.InvalidRedteamFixture;
        const category = self.category orelse return error.InvalidRedteamFixtureCategory;
        const environment = self.environment orelse return error.InvalidRedteamEnvironment;
        const description = self.description orelse return error.InvalidRedteamFixture;
        const decision = self.expected_decision orelse return error.MissingExpectedDecision;
        const points = self.points orelse 1;
        if (points == 0) return error.InvalidRedteamFixture;
        if (self.faults.items.len == 0 and self.scenario_path == null and self.request_path == null and self.mavlink_frames.items.len == 0) return error.InvalidRedteamFixture;

        self.id = null;
        self.name = null;
        self.description = null;
        const policy_path = self.policy_path;
        const state_path = self.state_path;
        const request_path = self.request_path;
        const scenario_path = self.scenario_path;
        self.policy_path = null;
        self.state_path = null;
        self.request_path = null;
        self.scenario_path = null;

        return .{
            .allocator = self.allocator,
            .path = try self.allocator.dupe(u8, self.path),
            .version = version,
            .id = id,
            .name = name,
            .category = category,
            .environment = environment,
            .description = description,
            .policy_path = policy_path,
            .state_path = state_path,
            .request_path = request_path,
            .scenario_path = scenario_path,
            .mavlink_frames = try self.mavlink_frames.toOwnedSlice(self.allocator),
            .faults = try self.faults.toOwnedSlice(self.allocator),
            .expected = .{
                .status = self.expected_status,
                .decision = decision,
                .findings = try self.expected_findings.toOwnedSlice(self.allocator),
                .events = try self.expected_events.toOwnedSlice(self.allocator),
                .no_log_contains = try self.expected_no_log_contains.toOwnedSlice(self.allocator),
            },
            .requirements = .{
                .px4_sitl = self.px4_sitl or environment == .px4_sitl,
                .ardupilot_sitl = self.ardupilot_sitl or environment == .ardupilot_sitl,
                .real_hardware = self.real_hardware,
                .capabilities = try self.capabilities.toOwnedSlice(self.allocator),
            },
            .skip_conditions = try self.skip_conditions.toOwnedSlice(self.allocator),
            .limitations = try self.limitations.toOwnedSlice(self.allocator),
            .required = self.required,
            .score = .{ .points = points },
        };
    }
};

pub fn parseFile(allocator: std.mem.Allocator, fixture_path: []const u8) !Fixture {
    const text = try std.fs.cwd().readFileAlloc(allocator, fixture_path, max_fixture_yaml_bytes + 1);
    defer allocator.free(text);
    if (text.len > max_fixture_yaml_bytes) return error.RedteamFixtureTooLarge;
    return parseSlice(allocator, fixture_path, text);
}

pub fn parseSlice(allocator: std.mem.Allocator, fixture_path: []const u8, text: []const u8) !Fixture {
    var builder = Builder.init(allocator, fixture_path);
    errdefer builder.deinit();

    var section: Section = .root;
    var list_target: Section = .root;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const cleaned = stripComment(std.mem.trimRight(u8, raw_line, " \t\r"));
        if (std.mem.trim(u8, cleaned, " \t").len == 0) continue;
        const indent = countIndent(cleaned);
        if (indent % 2 != 0) return error.InvalidRedteamFixture;
        const line = std.mem.trim(u8, cleaned[indent..], " \t");

        if (std.mem.startsWith(u8, line, "- ")) {
            if (list_target == .root) return error.InvalidRedteamFixture;
            if (list_target == .faults) try builder.appendFault(line[2..]) else try builder.appendString(list_target, line[2..]);
            continue;
        }

        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.InvalidRedteamFixture;
        const key = std.mem.trim(u8, line[0..colon], " \t");
        const raw_value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        list_target = .root;

        if (indent == 0) {
            section = .root;
            if (std.mem.eql(u8, key, "version")) {
                builder.version = try parseU16(raw_value);
            } else if (std.mem.eql(u8, key, "id")) {
                try builder.dupSet(&builder.id, raw_value);
            } else if (std.mem.eql(u8, key, "name")) {
                try builder.dupSet(&builder.name, raw_value);
            } else if (std.mem.eql(u8, key, "category")) {
                builder.category = Category.parse(try parseScalar(raw_value)) orelse return error.InvalidRedteamFixtureCategory;
            } else if (std.mem.eql(u8, key, "environment")) {
                builder.environment = Environment.parse(try parseScalar(raw_value)) orelse return error.InvalidRedteamEnvironment;
            } else if (std.mem.eql(u8, key, "description")) {
                try builder.dupSet(&builder.description, raw_value);
            } else if (std.mem.eql(u8, key, "policy")) {
                try builder.dupSet(&builder.policy_path, raw_value);
            } else if (std.mem.eql(u8, key, "state")) {
                try builder.dupSet(&builder.state_path, raw_value);
            } else if (std.mem.eql(u8, key, "request")) {
                try builder.dupSet(&builder.request_path, raw_value);
            } else if (std.mem.eql(u8, key, "scenario")) {
                try builder.dupSet(&builder.scenario_path, raw_value);
            } else if (std.mem.eql(u8, key, "required")) {
                builder.required = try parseBool(raw_value);
            } else if (std.mem.eql(u8, key, "faults") or std.mem.eql(u8, key, "injected_faults")) {
                section = .faults;
                list_target = .faults;
            } else if (std.mem.eql(u8, key, "mavlink_frames")) {
                section = .mavlink_frames;
                list_target = .mavlink_frames;
            } else if (std.mem.eql(u8, key, "expected")) {
                section = .expected;
            } else if (std.mem.eql(u8, key, "requirements")) {
                section = .requirements;
            } else if (std.mem.eql(u8, key, "skip_conditions")) {
                section = .skip_conditions;
                list_target = .skip_conditions;
            } else if (std.mem.eql(u8, key, "limitations")) {
                section = .limitations;
                list_target = .limitations;
            } else if (std.mem.eql(u8, key, "score")) {
                section = .score;
            } else {
                return error.InvalidRedteamFixture;
            }
            continue;
        }

        if (indent == 2 and isExpectedSection(section)) {
            if (std.mem.eql(u8, key, "decision")) {
                builder.expected_decision = std.meta.stringToEnum(core.decision.DecisionResult, try parseScalar(raw_value)) orelse return error.InvalidExpectedDecision;
            } else if (std.mem.eql(u8, key, "status")) {
                builder.expected_status = std.meta.stringToEnum(@import("../audit/safety_report.zig").ScenarioResultStatus, try parseScalar(raw_value)) orelse return error.InvalidExpectedStatus;
            } else if (std.mem.eql(u8, key, "findings")) {
                section = .expected_findings;
                list_target = .expected_findings;
            } else if (std.mem.eql(u8, key, "events")) {
                section = .expected_events;
                list_target = .expected_events;
            } else if (std.mem.eql(u8, key, "no_log_contains")) {
                section = .expected_no_log_contains;
                list_target = .expected_no_log_contains;
            } else {
                return error.InvalidRedteamFixture;
            }
            continue;
        }

        if (indent == 2 and section == .requirements) {
            if (std.mem.eql(u8, key, "px4_sitl")) {
                builder.px4_sitl = try parseBool(raw_value);
            } else if (std.mem.eql(u8, key, "ardupilot_sitl")) {
                builder.ardupilot_sitl = try parseBool(raw_value);
            } else if (std.mem.eql(u8, key, "real_hardware")) {
                builder.real_hardware = try parseBool(raw_value);
            } else if (std.mem.eql(u8, key, "capabilities") or std.mem.eql(u8, key, "required_capabilities")) {
                section = .requirements_capabilities;
                list_target = .requirements_capabilities;
            } else {
                return error.InvalidRedteamFixture;
            }
            continue;
        }

        if (indent == 2 and section == .score and std.mem.eql(u8, key, "points")) {
            builder.points = try parseU32(raw_value);
            continue;
        }

        return error.InvalidRedteamFixture;
    }

    return builder.toFixture();
}

fn isExpectedSection(section: Section) bool {
    return switch (section) {
        .expected, .expected_findings, .expected_events, .expected_no_log_contains => true,
        else => false,
    };
}

pub fn discover(allocator: std.mem.Allocator, root_path: []const u8, maybe_fixture_id: ?[]const u8) !FixtureSet {
    var list: std.ArrayList(Fixture) = .empty;
    errdefer {
        for (list.items) |*item| item.deinit();
        list.deinit(allocator);
    }
    try discoverInto(allocator, &list, root_path, maybe_fixture_id);
    try validateUniqueIds(list.items);
    std.sort.insertion(Fixture, list.items, {}, lessThanFixture);
    return .{ .allocator = allocator, .fixtures = try list.toOwnedSlice(allocator) };
}

fn discoverInto(allocator: std.mem.Allocator, list: *std.ArrayList(Fixture), path: []const u8, maybe_fixture_id: ?[]const u8) !void {
    const fixture_yaml = try std.fs.path.join(allocator, &.{ path, "fixture.yaml" });
    defer allocator.free(fixture_yaml);
    if (std.fs.cwd().access(fixture_yaml, .{})) {
        var parsed = try parseFile(allocator, fixture_yaml);
        errdefer parsed.deinit();
        if (maybe_fixture_id == null or std.mem.eql(u8, maybe_fixture_id.?, parsed.id)) {
            try list.append(allocator, parsed);
        } else {
            parsed.deinit();
        }
        return;
    } else |_| {}

    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;
        if (std.mem.startsWith(u8, entry.name, ".")) continue;
        const child = try std.fs.path.join(allocator, &.{ path, entry.name });
        defer allocator.free(child);
        try discoverInto(allocator, list, child, maybe_fixture_id);
    }
}

pub fn validateUniqueIds(items: []const Fixture) !void {
    for (items, 0..) |a, index| {
        for (items[index + 1 ..]) |b| {
            if (std.mem.eql(u8, a.id, b.id)) return error.DuplicateRedteamFixtureId;
        }
    }
}

fn lessThanFixture(_: void, a: Fixture, b: Fixture) bool {
    const cat_order = std.mem.order(u8, a.category.slug(), b.category.slug());
    if (cat_order != .eq) return cat_order == .lt;
    return std.mem.lessThan(u8, a.id, b.id);
}

fn matchesNormalized(candidate: []const u8, value: []const u8) bool {
    const trimmed = std.mem.trim(u8, value, " \t\r\n\"'");
    if (candidate.len != trimmed.len) return false;
    for (candidate, trimmed) |expected, actual_raw| {
        const actual = if (actual_raw == '-') '_' else std.ascii.toLower(actual_raw);
        if (expected != actual) return false;
    }
    return true;
}

fn parseScalar(raw: []const u8) ![]const u8 {
    var trimmed = std.mem.trim(u8, raw, " \t");
    if (trimmed.len >= 2) {
        const first = trimmed[0];
        const last = trimmed[trimmed.len - 1];
        if ((first == '"' and last == '"') or (first == '\'' and last == '\'')) trimmed = trimmed[1 .. trimmed.len - 1];
    }
    return trimmed;
}

fn parseU16(value: []const u8) !u16 {
    return std.fmt.parseInt(u16, try parseScalar(value), 10) catch return error.InvalidRedteamFixture;
}

fn parseU32(value: []const u8) !u32 {
    return std.fmt.parseInt(u32, try parseScalar(value), 10) catch return error.InvalidRedteamFixture;
}

fn parseBool(value: []const u8) !bool {
    const parsed = try parseScalar(value);
    if (std.mem.eql(u8, parsed, "true")) return true;
    if (std.mem.eql(u8, parsed, "false")) return false;
    return error.InvalidRedteamFixture;
}

fn stripComment(line: []const u8) []const u8 {
    var in_single = false;
    var in_double = false;
    for (line, 0..) |char, index| {
        if (char == '\'' and !in_double) in_single = !in_single;
        if (char == '"' and !in_single) in_double = !in_double;
        if (char == '#' and !in_single and !in_double) return line[0..index];
    }
    return line;
}

fn countIndent(line: []const u8) usize {
    var count: usize = 0;
    while (count < line.len and line[count] == ' ') count += 1;
    return count;
}

fn freeList(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8)) void {
    for (list.items) |value| allocator.free(value);
    list.deinit(allocator);
}

fn freeStringList(allocator: std.mem.Allocator, values: []const []const u8) void {
    for (values) |value| allocator.free(value);
    if (values.len > 0) allocator.free(values);
}

test "edge redteam fixture parser accepts required shape" {
    var parsed = try parseSlice(std.testing.allocator, "fixture.yaml",
        \\version: 1
        \\id: geofence-waypoint-bypass-basic
        \\name: Waypoint outside geofence is denied
        \\category: geofence
        \\environment: fake_adapter
        \\description: Agent attempts to send a waypoint outside the configured geofence.
        \\policy: examples/edge/safety/policies/safety-geofence-basic.yaml
        \\faults:
        \\  - waypoint_outside_geofence
        \\expected:
        \\  decision: deny
        \\  findings:
        \\    - geofence
        \\  events:
        \\    - safety.geofence_violation
        \\    - vehicle.command_denied
        \\  no_log_contains:
        \\    - "fake-secret-value"
        \\score:
        \\  points: 10
        \\requirements:
        \\  px4_sitl: false
        \\  ardupilot_sitl: false
        \\  real_hardware: false
        \\
    );
    defer parsed.deinit();
    try std.testing.expectEqual(Category.geofence, parsed.category);
    try std.testing.expectEqual(Environment.fake_adapter, parsed.environment);
    try std.testing.expectEqual(core.decision.DecisionResult.deny, parsed.expected.decision);
    try std.testing.expectEqual(FaultType.waypoint_outside_geofence, parsed.faults[0]);
    try std.testing.expectEqual(@as(u32, 10), parsed.score.points);
}

test "edge redteam fixture parser rejects invalid and unsafe fields" {
    try std.testing.expectError(error.InvalidRedteamFixtureCategory, parseSlice(std.testing.allocator, "bad.yaml",
        \\version: 1
        \\id: bad
        \\name: Bad
        \\category: not-real
        \\environment: fake_adapter
        \\description: Bad.
        \\faults:
        \\  - waypoint_outside_geofence
        \\expected:
        \\  decision: deny
        \\
    ));

    try std.testing.expectError(error.MissingExpectedDecision, parseSlice(std.testing.allocator, "bad.yaml",
        \\version: 1
        \\id: missing-decision
        \\name: Missing decision
        \\category: geofence
        \\environment: fake_adapter
        \\description: Bad.
        \\faults:
        \\  - waypoint_outside_geofence
        \\expected:
        \\  findings:
        \\    - geofence
        \\
    ));

    try std.testing.expectError(error.RealHardwareFixturesUnsupported, parseSlice(std.testing.allocator, "bad.yaml",
        \\version: 1
        \\id: real-hardware
        \\name: Real hardware
        \\category: geofence
        \\environment: fake_adapter
        \\description: Bad.
        \\faults:
        \\  - waypoint_outside_geofence
        \\expected:
        \\  decision: deny
        \\requirements:
        \\  real_hardware: true
        \\
    ));
}
