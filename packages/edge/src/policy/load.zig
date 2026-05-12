const std = @import("std");

const domain = @import("../domain/mod.zig");
const schema = @import("../schema/mod.zig");
const health_watchdog = @import("../health/watchdog.zig");

pub const LoadOptions = struct {
    strict_validation: bool = true,
};

pub const LoadedPolicy = struct {
    allocator: std.mem.Allocator,
    value: schema.edge_policy_schema.EdgePolicyV1,
    source_path: ?[]const u8 = null,

    pub fn deinit(self: *LoadedPolicy) void {
        self.allocator.free(self.value.commands.allow);
        self.allocator.free(self.value.commands.ask);
        self.allocator.free(self.value.commands.deny);
        self.allocator.free(self.value.commands.require_operator_approval);
        self.allocator.free(self.value.safety.commands.allow);
        self.allocator.free(self.value.safety.commands.ask);
        self.allocator.free(self.value.safety.commands.deny);
        self.allocator.free(self.value.safety.commands.require_operator_approval);
        self.allocator.free(self.value.safety.emergency.fallback_order);
        if (self.source_path) |source| self.allocator.free(source);
        self.* = undefined;
    }
};

pub const ParsedCommandRequest = struct {
    arena: std.heap.ArenaAllocator,
    value: domain.commands.CommandRequest,

    pub fn deinit(self: *ParsedCommandRequest) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub const ParsedVehicleState = struct {
    arena: std.heap.ArenaAllocator,
    value: domain.state.VehicleState,

    pub fn deinit(self: *ParsedVehicleState) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub fn loadFile(allocator: std.mem.Allocator, path: []const u8, options: LoadOptions) !LoadedPolicy {
    const text = try std.fs.cwd().readFileAlloc(allocator, path, 256 * 1024);
    defer allocator.free(text);
    return loadFromSlice(allocator, text, path, options);
}

pub fn loadFromSlice(allocator: std.mem.Allocator, text: []const u8, source_path: ?[]const u8, options: LoadOptions) !LoadedPolicy {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.len == 0) return error.InvalidPolicy;
    var loaded = if (trimmed[0] == '{')
        try parseJsonPolicy(allocator, trimmed, source_path, options)
    else
        try parseYamlPolicy(allocator, trimmed, source_path, options);
    errdefer loaded.deinit();
    try validateLoadedPolicy(&loaded.value, options);
    return loaded;
}

const Section = enum {
    root,
    vehicle,
    safety,
    state_freshness,
    geofence,
    geofence_center,
    geofence_home_position,
    velocity,
    altitude,
    battery,
    approval,
    emergency,
    commands,
    network,
    audit,
    data_guard,
    watchdog,
    watchdog_heartbeat,
    watchdog_telemetry,
    watchdog_audit,
    watchdog_degraded_mode,
    watchdog_resource,
};

const CommandList = enum { none, allow, ask, deny, require_operator_approval };

const PolicyBuilder = struct {
    allocator: std.mem.Allocator,
    options: LoadOptions,
    source_path: ?[]const u8,
    version_seen: bool = false,
    safety_seen: bool = false,
    commands_seen: bool = false,
    version: u32 = 1,
    vehicle_kind: ?domain.vehicle.VehicleKind = null,
    autopilot: ?domain.vehicle.AutopilotKind = null,
    adapter: ?domain.vehicle.AdapterKind = null,
    freshness: ?domain.safety_envelope.StateFreshnessPolicy = null,
    geofence_type: ?[]const u8 = null,
    geofence_center: ?domain.coordinates.GeoPoint = null,
    geofence_home_position: ?domain.coordinates.GeoPoint = null,
    geofence_radius: ?f64 = null,
    geofence_floor: ?f64 = null,
    geofence_ceiling: ?f64 = null,
    geofence_alt_ref: ?domain.coordinates.AltitudeReference = null,
    geofence_boundary_action: ?domain.geofence.BoundaryAction = null,
    altitude: ?domain.safety_envelope.AltitudeLimits = null,
    velocity: ?domain.safety_envelope.VelocityLimits = null,
    battery: ?domain.safety_envelope.BatteryPolicy = null,
    approval: domain.safety_envelope.ApprovalPolicy = .{},
    emergency: domain.safety_envelope.EmergencyBehaviorConstraints = .{},
    emergency_fallback_order: std.ArrayList(domain.commands.CommandAction) = .empty,
    commands_allow: std.ArrayList(domain.commands.CommandAction) = .empty,
    commands_ask: std.ArrayList(domain.commands.CommandAction) = .empty,
    commands_deny: std.ArrayList(domain.commands.CommandAction) = .empty,
    commands_approval: std.ArrayList(domain.commands.CommandAction) = .empty,
    network: domain.safety_envelope.NetworkConstraints = .{},
    audit: schema.edge_policy_schema.AuditPolicy = .{},
    watchdog: health_watchdog.WatchdogPolicy = .{},

    fn deinit(self: *PolicyBuilder) void {
        self.commands_allow.deinit(self.allocator);
        self.commands_ask.deinit(self.allocator);
        self.commands_deny.deinit(self.allocator);
        self.commands_approval.deinit(self.allocator);
        self.emergency_fallback_order.deinit(self.allocator);
    }

    fn appendCommand(self: *PolicyBuilder, list: CommandList, action: domain.commands.CommandAction) !void {
        switch (list) {
            .allow => try self.commands_allow.append(self.allocator, action),
            .ask => try self.commands_ask.append(self.allocator, action),
            .deny => try self.commands_deny.append(self.allocator, action),
            .require_operator_approval => try self.commands_approval.append(self.allocator, action),
            .none => return error.InvalidPolicy,
        }
    }

    fn build(self: *PolicyBuilder) !LoadedPolicy {
        if (!self.version_seen) return error.MissingPolicyVersion;
        if (self.version != 1) return error.UnsupportedSchemaVersion;
        const vehicle_kind = self.vehicle_kind orelse return error.InvalidPolicy;
        const autopilot = self.autopilot orelse return error.InvalidPolicy;
        const adapter = self.adapter orelse return error.InvalidPolicy;
        if (self.options.strict_validation and vehicle_kind == .unknown) return error.UnknownVehicleKind;
        if (self.options.strict_validation and autopilot == .unknown) return error.UnknownAutopilotKind;
        if (self.options.strict_validation and adapter == .unknown) return error.UnknownAdapterKind;
        if (!self.safety_seen) return error.MissingPolicySafetySection;
        if (!self.commands_seen) return error.MissingPolicyCommandsSection;

        const allow = try self.commands_allow.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(allow);
        const ask = try self.commands_ask.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(ask);
        const deny = try self.commands_deny.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(deny);
        const approval = try self.commands_approval.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(approval);

        const command_policy: domain.safety_envelope.CommandPolicy = .{
            .allow = allow,
            .ask = ask,
            .deny = deny,
            .require_operator_approval = approval,
        };

        const safety_command_policy: domain.safety_envelope.CommandPolicy = .{
            .allow = try self.allocator.dupe(domain.commands.CommandAction, allow),
            .ask = try self.allocator.dupe(domain.commands.CommandAction, ask),
            .deny = try self.allocator.dupe(domain.commands.CommandAction, deny),
            .require_operator_approval = try self.allocator.dupe(domain.commands.CommandAction, approval),
        };
        errdefer self.allocator.free(safety_command_policy.allow);
        errdefer self.allocator.free(safety_command_policy.ask);
        errdefer self.allocator.free(safety_command_policy.deny);
        errdefer self.allocator.free(safety_command_policy.require_operator_approval);

        const geofence = try self.buildGeofence();
        const default_emergency: domain.safety_envelope.EmergencyBehaviorConstraints = .{};
        const fallback_order = if (self.emergency_fallback_order.items.len > 0)
            try self.emergency_fallback_order.toOwnedSlice(self.allocator)
        else
            try self.allocator.dupe(domain.commands.CommandAction, default_emergency.fallback_order);
        errdefer self.allocator.free(fallback_order);
        var emergency = self.emergency;
        emergency.fallback_order = fallback_order;
        const source_copy = if (self.source_path) |source| try self.allocator.dupe(u8, source) else null;
        errdefer if (source_copy) |source| self.allocator.free(source);

        return .{
            .allocator = self.allocator,
            .source_path = source_copy,
            .value = .{
                .version = self.version,
                .vehicle = .{
                    .kind = vehicle_kind,
                    .autopilot = autopilot,
                    .adapter = adapter,
                },
                .safety = .{
                    .geofence = geofence,
                    .altitude = self.altitude,
                    .velocity = self.velocity,
                    .battery = self.battery,
                    .state_freshness = self.freshness,
                    .commands = safety_command_policy,
                    .network = self.network,
                    .approval = self.approval,
                    .emergency = emergency,
                },
                .commands = command_policy,
                .network = self.network,
                .audit = self.audit,
                .watchdog = self.watchdog,
            },
        };
    }

    fn buildGeofence(self: *PolicyBuilder) !?domain.geofence.Geofence {
        const geofence_type = self.geofence_type orelse return null;
        if (std.mem.eql(u8, geofence_type, "allowed_polygon") or std.mem.eql(u8, geofence_type, "polygon")) return error.UnsupportedGeofenceShape;
        if (!std.mem.eql(u8, geofence_type, "circle")) return error.UnsupportedGeofenceShape;
        const center = self.geofence_center orelse return error.InvalidPolicy;
        const radius = self.geofence_radius orelse return error.InvalidPolicy;
        if (radius <= 0) return error.InvalidGeofenceRadius;
        return .{
            .shape = .{ .circle = .{ .center = center, .max_radius_m = radius } },
            .home_position = self.geofence_home_position,
            .altitude_floor_m = self.geofence_floor orelse return error.InvalidPolicy,
            .altitude_ceiling_m = self.geofence_ceiling orelse return error.InvalidPolicy,
            .altitude_reference = self.geofence_alt_ref orelse return error.UnknownAltitudeReference,
            .boundary_action = self.geofence_boundary_action orelse return error.InvalidPolicy,
        };
    }
};

fn parseYamlPolicy(allocator: std.mem.Allocator, text: []const u8, source_path: ?[]const u8, options: LoadOptions) !LoadedPolicy {
    var builder: PolicyBuilder = .{ .allocator = allocator, .options = options, .source_path = source_path };
    defer builder.deinit();

    var section: Section = .root;
    var command_list: CommandList = .none;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const no_comment = stripComment(raw_line);
        const line = std.mem.trimRight(u8, no_comment, " \t\r");
        if (std.mem.trim(u8, line, " \t\r").len == 0) continue;
        const indent = countIndent(line);
        const trimmed = std.mem.trimLeft(u8, line, " ");
        if (section == .data_guard and indent > 0) continue;
        if (std.mem.startsWith(u8, trimmed, "-")) {
            const value = cleanScalar(std.mem.trim(u8, trimmed[1..], " \t"));
            try builder.appendCommand(command_list, try parseCommandAction(value));
            continue;
        }

        const pair = try splitKeyValue(trimmed);
        const key = pair.key;
        const value = pair.value;

        if (indent == 0) {
            command_list = .none;
            if (std.mem.eql(u8, key, "version")) {
                if (value.len == 0) return error.InvalidPolicy;
                builder.version = try parseU32(value);
                builder.version_seen = true;
                section = .root;
            } else if (std.mem.eql(u8, key, "vehicle")) {
                section = .vehicle;
            } else if (std.mem.eql(u8, key, "safety")) {
                builder.safety_seen = true;
                section = .safety;
            } else if (std.mem.eql(u8, key, "commands")) {
                builder.commands_seen = true;
                section = .commands;
            } else if (std.mem.eql(u8, key, "network")) {
                section = .network;
            } else if (std.mem.eql(u8, key, "audit")) {
                section = .audit;
            } else if (std.mem.eql(u8, key, "data_guard")) {
                section = .data_guard;
            } else if (std.mem.eql(u8, key, "watchdog")) {
                section = .watchdog;
            } else {
                return error.InvalidPolicy;
            }
            continue;
        }

        switch (section) {
            .vehicle => try parseYamlVehicle(&builder, key, value),
            .safety, .state_freshness, .geofence, .geofence_center, .geofence_home_position, .velocity, .altitude, .battery, .approval, .emergency => {
                try parseYamlSafety(&builder, &section, indent, key, value);
            },
            .commands => try parseYamlCommands(&command_list, key),
            .network => try parseYamlNetwork(&builder, key, value),
            .audit => try parseYamlAudit(&builder, key, value),
            .data_guard => {},
            .watchdog, .watchdog_heartbeat, .watchdog_telemetry, .watchdog_audit, .watchdog_degraded_mode, .watchdog_resource => try parseYamlWatchdog(&builder, &section, indent, key, value),
            .root => return error.InvalidPolicy,
        }
    }
    return builder.build();
}

fn parseYamlVehicle(builder: *PolicyBuilder, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "kind")) builder.vehicle_kind = try parseVehicleKind(value) else if (std.mem.eql(u8, key, "autopilot")) builder.autopilot = try parseAutopilot(value) else if (std.mem.eql(u8, key, "adapter")) builder.adapter = try parseAdapter(value) else return error.InvalidPolicy;
}

fn parseYamlSafety(builder: *PolicyBuilder, section: *Section, indent: usize, key: []const u8, value: []const u8) !void {
    if ((section.* == .geofence_center or section.* == .geofence_home_position) and indent <= 4 and !isGeoPointKey(key)) {
        section.* = .geofence;
    }
    if (indent == 2) {
        if (std.mem.eql(u8, key, "state_freshness")) section.* = .state_freshness else if (std.mem.eql(u8, key, "geofence")) section.* = .geofence else if (std.mem.eql(u8, key, "velocity")) section.* = .velocity else if (std.mem.eql(u8, key, "altitude")) section.* = .altitude else if (std.mem.eql(u8, key, "battery")) section.* = .battery else if (std.mem.eql(u8, key, "approval")) section.* = .approval else if (std.mem.eql(u8, key, "emergency")) section.* = .emergency else return error.InvalidPolicy;
        return;
    }
    if (section.* == .geofence and indent == 4 and std.mem.eql(u8, key, "center")) {
        section.* = .geofence_center;
        return;
    }
    if (section.* == .geofence and indent == 4 and std.mem.eql(u8, key, "home_position")) {
        section.* = .geofence_home_position;
        return;
    }
    switch (section.*) {
        .state_freshness => {
            var freshness = builder.freshness orelse domain.safety_envelope.StateFreshnessPolicy{ .max_state_age_ms = 1 };
            if (std.mem.eql(u8, key, "max_state_age_ms")) freshness.max_state_age_ms = try parseU64(value) else if (std.mem.eql(u8, key, "deny_commands_on_stale_state")) freshness.deny_commands_on_stale_state = try parseBool(value) else if (std.mem.eql(u8, key, "allow_emergency_land_on_stale_state")) freshness.allow_emergency_land_on_stale_state = try parseBool(value) else if (std.mem.eql(u8, key, "allow_return_home_on_stale_state")) freshness.allow_return_home_on_stale_state = try parseBool(value) else return error.InvalidPolicy;
            builder.freshness = freshness;
        },
        .geofence => try parseYamlGeofence(builder, key, value),
        .geofence_center => {
            var center = builder.geofence_center orelse domain.coordinates.GeoPoint{ .latitude_deg = 0, .longitude_deg = 0, .altitude_m = 0, .altitude_reference = .unknown };
            try parseYamlGeoPointField(&center, key, value);
            builder.geofence_center = center;
        },
        .geofence_home_position => {
            var home = builder.geofence_home_position orelse domain.coordinates.GeoPoint{ .latitude_deg = 0, .longitude_deg = 0, .altitude_m = 0, .altitude_reference = .unknown };
            try parseYamlGeoPointField(&home, key, value);
            builder.geofence_home_position = home;
        },
        .velocity => {
            var velocity = builder.velocity orelse domain.safety_envelope.VelocityLimits{ .max_horizontal_mps = 0, .max_vertical_mps = 0 };
            if (std.mem.eql(u8, key, "max_horizontal_mps")) velocity.max_horizontal_mps = try parseF64(value) else if (std.mem.eql(u8, key, "max_vertical_mps")) velocity.max_vertical_mps = try parseF64(value) else return error.InvalidPolicy;
            builder.velocity = velocity;
        },
        .altitude => {
            var altitude = builder.altitude orelse domain.safety_envelope.AltitudeLimits{ .min_altitude_m = 0, .max_altitude_m = 0, .altitude_reference = .unknown };
            if (std.mem.eql(u8, key, "min_altitude_m")) altitude.min_altitude_m = try parseF64(value) else if (std.mem.eql(u8, key, "max_altitude_m")) altitude.max_altitude_m = try parseF64(value) else if (std.mem.eql(u8, key, "altitude_reference")) altitude.altitude_reference = try parseAltitudeReference(value) else return error.InvalidPolicy;
            builder.altitude = altitude;
        },
        .battery => {
            var battery = builder.battery orelse domain.safety_envelope.BatteryPolicy{ .deny_takeoff_below_percent = 0, .return_home_below_percent = 0, .land_below_percent = 0 };
            if (std.mem.eql(u8, key, "deny_takeoff_below_percent")) battery.deny_takeoff_below_percent = try parseF64(value) else if (std.mem.eql(u8, key, "return_home_below_percent")) battery.return_home_below_percent = try parseF64(value) else if (std.mem.eql(u8, key, "land_below_percent")) battery.land_below_percent = try parseF64(value) else if (std.mem.eql(u8, key, "require_fresh_battery_state")) battery.require_fresh_battery_state = try parseBool(value) else return error.InvalidPolicy;
            builder.battery = battery;
        },
        .approval => {
            if (std.mem.eql(u8, key, "approval_ttl_ms")) builder.approval.approval_ttl_ms = try parseU64(value) else if (std.mem.eql(u8, key, "max_uses_default")) builder.approval.max_uses_default = try parseU32(value) else if (std.mem.eql(u8, key, "require_operator_identity")) builder.approval.require_operator_identity = try parseBool(value) else if (std.mem.eql(u8, key, "require_state_hash")) builder.approval.require_state_hash = try parseBool(value) else if (std.mem.eql(u8, key, "require_safety_constraints_hash")) builder.approval.require_safety_constraints_hash = try parseBool(value) else if (std.mem.eql(u8, key, "allow_broad_scopes")) builder.approval.allow_broad_scopes = try parseBool(value) else if (std.mem.eql(u8, key, "allow_non_overridable_override")) builder.approval.allow_non_overridable_override = try parseBool(value) else if (std.mem.eql(u8, key, "allow_compatible_policy_hash")) builder.approval.allow_compatible_policy_hash = try parseBool(value) else return error.InvalidPolicy;
        },
        .emergency => {
            if (std.mem.eql(u8, key, "allow_land")) builder.emergency.allow_land = try parseBool(value) else if (std.mem.eql(u8, key, "allow_return_to_home")) builder.emergency.allow_return_to_home = try parseBool(value) else if (std.mem.eql(u8, key, "allow_hold_position")) builder.emergency.allow_hold_position = try parseBool(value) else if (std.mem.eql(u8, key, "allow_stop_or_brake")) builder.emergency.allow_stop_or_brake = try parseBool(value) else if (std.mem.eql(u8, key, "allow_disarm")) builder.emergency.allow_disarm = try parseBool(value) else if (std.mem.eql(u8, key, "fallback_order")) try parseFallbackOrder(builder, value) else return error.UnknownEmergencyBehaviorDefault;
        },
        else => return error.InvalidPolicy,
    }
}

fn isGeoPointKey(key: []const u8) bool {
    return std.mem.eql(u8, key, "latitude_deg") or
        std.mem.eql(u8, key, "longitude_deg") or
        std.mem.eql(u8, key, "altitude_m") or
        std.mem.eql(u8, key, "altitude_reference");
}

fn parseYamlGeoPointField(point: *domain.coordinates.GeoPoint, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "latitude_deg")) point.latitude_deg = try parseF64(value) else if (std.mem.eql(u8, key, "longitude_deg")) point.longitude_deg = try parseF64(value) else if (std.mem.eql(u8, key, "altitude_m")) point.altitude_m = try parseF64(value) else if (std.mem.eql(u8, key, "altitude_reference")) point.altitude_reference = try parseAltitudeReference(value) else return error.InvalidPolicy;
}

fn parseYamlGeofence(builder: *PolicyBuilder, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "type")) builder.geofence_type = value else if (std.mem.eql(u8, key, "max_radius_m")) builder.geofence_radius = try parseF64(value) else if (std.mem.eql(u8, key, "altitude_floor_m")) builder.geofence_floor = try parseF64(value) else if (std.mem.eql(u8, key, "altitude_ceiling_m")) builder.geofence_ceiling = try parseF64(value) else if (std.mem.eql(u8, key, "altitude_reference")) builder.geofence_alt_ref = try parseAltitudeReference(value) else if (std.mem.eql(u8, key, "boundary_action")) builder.geofence_boundary_action = try parseBoundaryAction(value) else if (std.mem.eql(u8, key, "vertices")) return error.UnsupportedGeofenceShape else return error.InvalidPolicy;
}

fn parseFallbackOrder(builder: *PolicyBuilder, value: []const u8) !void {
    builder.emergency_fallback_order.clearRetainingCapacity();
    var parts = std.mem.splitScalar(u8, value, ',');
    while (parts.next()) |part| {
        const name = cleanScalar(std.mem.trim(u8, part, " \t\r"));
        if (name.len == 0) continue;
        try builder.emergency_fallback_order.append(builder.allocator, try parseCommandAction(name));
    }
    if (builder.emergency_fallback_order.items.len == 0) return error.InvalidEmergencyFallbackPolicy;
}

fn parseYamlCommands(command_list: *CommandList, key: []const u8) !void {
    if (std.mem.eql(u8, key, "allow")) command_list.* = .allow else if (std.mem.eql(u8, key, "ask")) command_list.* = .ask else if (std.mem.eql(u8, key, "deny")) command_list.* = .deny else if (std.mem.eql(u8, key, "require_operator_approval")) command_list.* = .require_operator_approval else return error.InvalidPolicy;
}

fn parseYamlNetwork(builder: *PolicyBuilder, key: []const u8, value: []const u8) !void {
    if (!std.mem.eql(u8, key, "mode")) return error.InvalidNetworkPolicy;
    builder.network.mode = std.meta.stringToEnum(@TypeOf(builder.network.mode), value) orelse return error.InvalidNetworkPolicy;
}

fn parseYamlAudit(builder: *PolicyBuilder, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "level")) builder.audit.level = std.meta.stringToEnum(@TypeOf(builder.audit.level), value) orelse return error.InvalidAuditPolicy else if (std.mem.eql(u8, key, "redact_secrets")) builder.audit.redact_secrets = try parseBool(value) else return error.InvalidAuditPolicy;
}

fn parseYamlWatchdog(builder: *PolicyBuilder, section: *Section, indent: usize, key: []const u8, value: []const u8) !void {
    if (section.* != .watchdog and indent == 2) section.* = .watchdog;
    if (section.* == .watchdog and indent == 2) {
        if (std.mem.eql(u8, key, "enabled")) {
            if (value.len == 0) return error.InvalidPolicy;
            builder.watchdog.enabled = try parseBool(value);
            return;
        }
        if (std.mem.eql(u8, key, "heartbeat")) section.* = .watchdog_heartbeat else if (std.mem.eql(u8, key, "telemetry")) section.* = .watchdog_telemetry else if (std.mem.eql(u8, key, "audit")) section.* = .watchdog_audit else if (std.mem.eql(u8, key, "degraded_mode")) section.* = .watchdog_degraded_mode else if (std.mem.eql(u8, key, "resource")) section.* = .watchdog_resource else return error.InvalidPolicy;
        return;
    }
    switch (section.*) {
        .watchdog_heartbeat => {
            if (std.mem.eql(u8, key, "agent_max_age_ms")) builder.watchdog.heartbeat.agent_max_age_ms = try parseU64(value) else if (std.mem.eql(u8, key, "adapter_max_age_ms")) builder.watchdog.heartbeat.adapter_max_age_ms = try parseU64(value) else if (std.mem.eql(u8, key, "mavlink_max_age_ms")) builder.watchdog.heartbeat.mavlink_max_age_ms = try parseU64(value) else if (std.mem.eql(u8, key, "px4_sitl_max_age_ms")) builder.watchdog.heartbeat.px4_sitl_max_age_ms = try parseU64(value) else if (std.mem.eql(u8, key, "ardupilot_sitl_max_age_ms")) builder.watchdog.heartbeat.ardupilot_sitl_max_age_ms = try parseU64(value) else if (std.mem.eql(u8, key, "runtime_max_age_ms")) builder.watchdog.heartbeat.runtime_max_age_ms = try parseU64(value) else if (std.mem.eql(u8, key, "audit_writer_max_age_ms")) builder.watchdog.heartbeat.audit_writer_max_age_ms = try parseU64(value) else if (std.mem.eql(u8, key, "safety_engine_max_age_ms")) builder.watchdog.heartbeat.safety_engine_max_age_ms = try parseU64(value) else return error.InvalidPolicy;
        },
        .watchdog_telemetry => {
            if (std.mem.eql(u8, key, "vehicle_state_max_age_ms")) builder.watchdog.telemetry.vehicle_state_max_age_ms = try parseU64(value) else if (std.mem.eql(u8, key, "position_max_age_ms")) builder.watchdog.telemetry.position_max_age_ms = try parseU64(value) else if (std.mem.eql(u8, key, "battery_max_age_ms")) builder.watchdog.telemetry.battery_max_age_ms = try parseU64(value) else if (std.mem.eql(u8, key, "gps_max_age_ms")) builder.watchdog.telemetry.gps_max_age_ms = try parseU64(value) else if (std.mem.eql(u8, key, "link_max_age_ms")) builder.watchdog.telemetry.link_max_age_ms = try parseU64(value) else return error.InvalidPolicy;
        },
        .watchdog_audit => {
            if (std.mem.eql(u8, key, "require_audit_writer")) builder.watchdog.audit.require_audit_writer = try parseBool(value) else if (std.mem.eql(u8, key, "fail_closed_on_audit_error")) builder.watchdog.audit.fail_closed_on_audit_error = try parseBool(value) else if (std.mem.eql(u8, key, "max_event_append_latency_ms")) builder.watchdog.audit.max_event_append_latency_ms = try parseU64(value) else return error.InvalidPolicy;
        },
        .watchdog_degraded_mode => {
            if (std.mem.eql(u8, key, "on_agent_stale")) builder.watchdog.degraded_mode.on_agent_stale = try parseDegradedBehavior(value) else if (std.mem.eql(u8, key, "on_adapter_stale")) builder.watchdog.degraded_mode.on_adapter_stale = try parseDegradedBehavior(value) else if (std.mem.eql(u8, key, "on_telemetry_stale")) builder.watchdog.degraded_mode.on_telemetry_stale = try parseDegradedBehavior(value) else if (std.mem.eql(u8, key, "on_audit_failure")) builder.watchdog.degraded_mode.on_audit_failure = try parseDegradedBehavior(value) else if (std.mem.eql(u8, key, "on_policy_error")) builder.watchdog.degraded_mode.on_policy_error = try parseDegradedBehavior(value) else if (std.mem.eql(u8, key, "on_data_guard_failure")) builder.watchdog.degraded_mode.on_data_guard_failure = try parseDegradedBehavior(value) else if (std.mem.eql(u8, key, "allow_emergency_land")) builder.watchdog.degraded_mode.allow_emergency_land = try parseBool(value) else if (std.mem.eql(u8, key, "allow_return_to_home")) builder.watchdog.degraded_mode.allow_return_to_home = try parseEmergencyAllowance(value) else if (std.mem.eql(u8, key, "allow_hold")) builder.watchdog.degraded_mode.allow_hold = try parseEmergencyAllowance(value) else return error.InvalidPolicy;
        },
        .watchdog_resource => {
            if (std.mem.eql(u8, key, "max_memory_mb")) builder.watchdog.resource.max_memory_mb = try parseU64(value) else if (std.mem.eql(u8, key, "max_cpu_percent")) builder.watchdog.resource.max_cpu_percent = try parseU8(value) else if (std.mem.eql(u8, key, "max_event_queue_depth")) builder.watchdog.resource.max_event_queue_depth = try parseU64(value) else return error.InvalidPolicy;
        },
        else => return error.InvalidPolicy,
    }
}

fn parseJsonPolicy(allocator: std.mem.Allocator, text: []const u8, source_path: ?[]const u8, options: LoadOptions) !LoadedPolicy {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, text, .{}) catch return error.InvalidPolicy;
    defer parsed.deinit();
    const object = try expectObject(parsed.value);
    try rejectUnknownKeys(object, &.{ "version", "vehicle", "safety", "commands", "network", "audit", "data_guard", "watchdog" });

    var builder: PolicyBuilder = .{ .allocator = allocator, .options = options, .source_path = source_path };
    defer builder.deinit();
    builder.version_seen = true;
    builder.version = @intCast(try expectInteger(object.get("version") orelse return error.MissingPolicyVersion));

    const vehicle = try expectObject(object.get("vehicle") orelse return error.InvalidPolicy);
    try rejectUnknownKeys(vehicle, &.{ "kind", "autopilot", "adapter" });
    builder.vehicle_kind = try parseVehicleKind(try expectString(vehicle.get("kind") orelse return error.InvalidPolicy));
    builder.autopilot = try parseAutopilot(try expectString(vehicle.get("autopilot") orelse return error.InvalidPolicy));
    builder.adapter = try parseAdapter(try expectString(vehicle.get("adapter") orelse return error.InvalidPolicy));

    if (object.get("safety")) |safety_value| {
        builder.safety_seen = true;
        try parseJsonSafety(&builder, try expectObject(safety_value));
    }
    if (object.get("commands")) |commands_value| {
        builder.commands_seen = true;
        try parseJsonCommands(&builder, try expectObject(commands_value));
    }
    if (object.get("network")) |network_value| {
        const network = try expectObject(network_value);
        try rejectUnknownKeys(network, &.{"mode"});
        if (network.get("mode")) |mode| builder.network.mode = std.meta.stringToEnum(@TypeOf(builder.network.mode), try expectString(mode)) orelse return error.InvalidNetworkPolicy;
    }
    if (object.get("audit")) |audit_value| {
        const audit = try expectObject(audit_value);
        try rejectUnknownKeys(audit, &.{ "level", "redact_secrets" });
        if (audit.get("level")) |level| builder.audit.level = std.meta.stringToEnum(@TypeOf(builder.audit.level), try expectString(level)) orelse return error.InvalidAuditPolicy;
        if (audit.get("redact_secrets")) |redact| builder.audit.redact_secrets = try expectBool(redact);
    }
    if (object.get("watchdog")) |watchdog_value| {
        try parseJsonWatchdog(&builder, try expectObject(watchdog_value));
    }
    return builder.build();
}

fn parseJsonWatchdog(builder: *PolicyBuilder, object: std.json.ObjectMap) !void {
    try rejectUnknownKeys(object, &.{ "enabled", "heartbeat", "telemetry", "audit", "degraded_mode", "resource" });
    if (object.get("enabled")) |value| builder.watchdog.enabled = try expectBool(value);
    if (object.get("heartbeat")) |value| {
        const heartbeat = try expectObject(value);
        try rejectUnknownKeys(heartbeat, &.{ "agent_max_age_ms", "adapter_max_age_ms", "mavlink_max_age_ms", "px4_sitl_max_age_ms", "ardupilot_sitl_max_age_ms", "runtime_max_age_ms", "audit_writer_max_age_ms", "safety_engine_max_age_ms" });
        if (heartbeat.get("agent_max_age_ms")) |item| builder.watchdog.heartbeat.agent_max_age_ms = try expectPositiveU64(item);
        if (heartbeat.get("adapter_max_age_ms")) |item| builder.watchdog.heartbeat.adapter_max_age_ms = try expectPositiveU64(item);
        if (heartbeat.get("mavlink_max_age_ms")) |item| builder.watchdog.heartbeat.mavlink_max_age_ms = try expectPositiveU64(item);
        if (heartbeat.get("px4_sitl_max_age_ms")) |item| builder.watchdog.heartbeat.px4_sitl_max_age_ms = try expectPositiveU64(item);
        if (heartbeat.get("ardupilot_sitl_max_age_ms")) |item| builder.watchdog.heartbeat.ardupilot_sitl_max_age_ms = try expectPositiveU64(item);
        if (heartbeat.get("runtime_max_age_ms")) |item| builder.watchdog.heartbeat.runtime_max_age_ms = try expectPositiveU64(item);
        if (heartbeat.get("audit_writer_max_age_ms")) |item| builder.watchdog.heartbeat.audit_writer_max_age_ms = try expectPositiveU64(item);
        if (heartbeat.get("safety_engine_max_age_ms")) |item| builder.watchdog.heartbeat.safety_engine_max_age_ms = try expectPositiveU64(item);
    }
    if (object.get("telemetry")) |value| {
        const telemetry = try expectObject(value);
        try rejectUnknownKeys(telemetry, &.{ "vehicle_state_max_age_ms", "position_max_age_ms", "battery_max_age_ms", "gps_max_age_ms", "link_max_age_ms" });
        if (telemetry.get("vehicle_state_max_age_ms")) |item| builder.watchdog.telemetry.vehicle_state_max_age_ms = try expectPositiveU64(item);
        if (telemetry.get("position_max_age_ms")) |item| builder.watchdog.telemetry.position_max_age_ms = try expectPositiveU64(item);
        if (telemetry.get("battery_max_age_ms")) |item| builder.watchdog.telemetry.battery_max_age_ms = try expectPositiveU64(item);
        if (telemetry.get("gps_max_age_ms")) |item| builder.watchdog.telemetry.gps_max_age_ms = try expectPositiveU64(item);
        if (telemetry.get("link_max_age_ms")) |item| builder.watchdog.telemetry.link_max_age_ms = try expectPositiveU64(item);
    }
    if (object.get("audit")) |value| {
        const audit = try expectObject(value);
        try rejectUnknownKeys(audit, &.{ "require_audit_writer", "fail_closed_on_audit_error", "max_event_append_latency_ms" });
        if (audit.get("require_audit_writer")) |item| builder.watchdog.audit.require_audit_writer = try expectBool(item);
        if (audit.get("fail_closed_on_audit_error")) |item| builder.watchdog.audit.fail_closed_on_audit_error = try expectBool(item);
        if (audit.get("max_event_append_latency_ms")) |item| builder.watchdog.audit.max_event_append_latency_ms = try expectPositiveU64(item);
    }
    if (object.get("degraded_mode")) |value| {
        const degraded = try expectObject(value);
        try rejectUnknownKeys(degraded, &.{ "on_agent_stale", "on_adapter_stale", "on_telemetry_stale", "on_audit_failure", "on_policy_error", "on_data_guard_failure", "allow_emergency_land", "allow_return_to_home", "allow_hold" });
        if (degraded.get("on_agent_stale")) |item| builder.watchdog.degraded_mode.on_agent_stale = try parseDegradedBehavior(try expectString(item));
        if (degraded.get("on_adapter_stale")) |item| builder.watchdog.degraded_mode.on_adapter_stale = try parseDegradedBehavior(try expectString(item));
        if (degraded.get("on_telemetry_stale")) |item| builder.watchdog.degraded_mode.on_telemetry_stale = try parseDegradedBehavior(try expectString(item));
        if (degraded.get("on_audit_failure")) |item| builder.watchdog.degraded_mode.on_audit_failure = try parseDegradedBehavior(try expectString(item));
        if (degraded.get("on_policy_error")) |item| builder.watchdog.degraded_mode.on_policy_error = try parseDegradedBehavior(try expectString(item));
        if (degraded.get("on_data_guard_failure")) |item| builder.watchdog.degraded_mode.on_data_guard_failure = try parseDegradedBehavior(try expectString(item));
        if (degraded.get("allow_emergency_land")) |item| builder.watchdog.degraded_mode.allow_emergency_land = try expectBool(item);
        if (degraded.get("allow_return_to_home")) |item| builder.watchdog.degraded_mode.allow_return_to_home = try parseEmergencyAllowance(try expectString(item));
        if (degraded.get("allow_hold")) |item| builder.watchdog.degraded_mode.allow_hold = try parseEmergencyAllowance(try expectString(item));
    }
    if (object.get("resource")) |value| {
        const resource = try expectObject(value);
        try rejectUnknownKeys(resource, &.{ "max_memory_mb", "max_cpu_percent", "max_event_queue_depth" });
        if (resource.get("max_memory_mb")) |item| builder.watchdog.resource.max_memory_mb = try expectPositiveU64(item);
        if (resource.get("max_cpu_percent")) |item| builder.watchdog.resource.max_cpu_percent = try expectPositiveU8(item);
        if (resource.get("max_event_queue_depth")) |item| builder.watchdog.resource.max_event_queue_depth = try expectPositiveU64(item);
    }
}

fn parseJsonSafety(builder: *PolicyBuilder, safety: std.json.ObjectMap) !void {
    try rejectUnknownKeys(safety, &.{ "state_freshness", "geofence", "velocity", "altitude", "battery", "approval", "emergency" });
    if (safety.get("state_freshness")) |value| {
        const object = try expectObject(value);
        try rejectUnknownKeys(object, &.{ "max_state_age_ms", "deny_commands_on_stale_state", "allow_emergency_land_on_stale_state", "allow_return_home_on_stale_state" });
        builder.freshness = .{
            .max_state_age_ms = @intCast(try expectInteger(object.get("max_state_age_ms") orelse return error.InvalidPolicy)),
            .deny_commands_on_stale_state = if (object.get("deny_commands_on_stale_state")) |item| try expectBool(item) else true,
            .allow_emergency_land_on_stale_state = if (object.get("allow_emergency_land_on_stale_state")) |item| try expectBool(item) else true,
            .allow_return_home_on_stale_state = if (object.get("allow_return_home_on_stale_state")) |item| try expectBool(item) else false,
        };
    }
    if (safety.get("geofence")) |value| {
        const object = try expectObject(value);
        try rejectUnknownKeys(object, &.{ "type", "center", "home_position", "vertices", "max_radius_m", "altitude_floor_m", "altitude_ceiling_m", "altitude_reference", "boundary_action" });
        builder.geofence_type = try expectString(object.get("type") orelse return error.InvalidPolicy);
        if (object.get("vertices") != null) return error.UnsupportedGeofenceShape;
        builder.geofence_center = try parseGeoPointJson(object.get("center") orelse return error.InvalidPolicy);
        if (object.get("home_position")) |home| builder.geofence_home_position = try parseGeoPointJson(home);
        builder.geofence_radius = try expectNumber(object.get("max_radius_m") orelse return error.InvalidPolicy);
        builder.geofence_floor = try expectNumber(object.get("altitude_floor_m") orelse return error.InvalidPolicy);
        builder.geofence_ceiling = try expectNumber(object.get("altitude_ceiling_m") orelse return error.InvalidPolicy);
        builder.geofence_alt_ref = try parseAltitudeReference(try expectString(object.get("altitude_reference") orelse return error.InvalidPolicy));
        builder.geofence_boundary_action = try parseBoundaryAction(try expectString(object.get("boundary_action") orelse return error.InvalidPolicy));
    }
    if (safety.get("velocity")) |value| {
        const object = try expectObject(value);
        try rejectUnknownKeys(object, &.{ "max_horizontal_mps", "max_vertical_mps" });
        builder.velocity = .{
            .max_horizontal_mps = try expectNumber(object.get("max_horizontal_mps") orelse return error.InvalidPolicy),
            .max_vertical_mps = try expectNumber(object.get("max_vertical_mps") orelse return error.InvalidPolicy),
        };
    }
    if (safety.get("altitude")) |value| {
        const object = try expectObject(value);
        try rejectUnknownKeys(object, &.{ "min_altitude_m", "max_altitude_m", "altitude_reference" });
        builder.altitude = .{
            .min_altitude_m = try expectNumber(object.get("min_altitude_m") orelse return error.InvalidPolicy),
            .max_altitude_m = try expectNumber(object.get("max_altitude_m") orelse return error.InvalidPolicy),
            .altitude_reference = try parseAltitudeReference(try expectString(object.get("altitude_reference") orelse return error.InvalidPolicy)),
        };
    }
    if (safety.get("battery")) |value| {
        const object = try expectObject(value);
        try rejectUnknownKeys(object, &.{ "deny_takeoff_below_percent", "return_home_below_percent", "land_below_percent", "require_fresh_battery_state" });
        builder.battery = .{
            .deny_takeoff_below_percent = try expectNumber(object.get("deny_takeoff_below_percent") orelse return error.InvalidPolicy),
            .return_home_below_percent = try expectNumber(object.get("return_home_below_percent") orelse return error.InvalidPolicy),
            .land_below_percent = try expectNumber(object.get("land_below_percent") orelse return error.InvalidPolicy),
            .require_fresh_battery_state = if (object.get("require_fresh_battery_state")) |item| try expectBool(item) else true,
        };
    }
    if (safety.get("approval")) |value| {
        const object = try expectObject(value);
        try rejectUnknownKeys(object, &.{ "approval_ttl_ms", "max_uses_default", "require_operator_identity", "require_state_hash", "require_safety_constraints_hash", "allow_broad_scopes", "allow_non_overridable_override", "allow_compatible_policy_hash" });
        if (object.get("approval_ttl_ms")) |item| builder.approval.approval_ttl_ms = @intCast(try expectInteger(item));
        if (object.get("max_uses_default")) |item| builder.approval.max_uses_default = @intCast(try expectInteger(item));
        if (object.get("require_operator_identity")) |item| builder.approval.require_operator_identity = try expectBool(item);
        if (object.get("require_state_hash")) |item| builder.approval.require_state_hash = try expectBool(item);
        if (object.get("require_safety_constraints_hash")) |item| builder.approval.require_safety_constraints_hash = try expectBool(item);
        if (object.get("allow_broad_scopes")) |item| builder.approval.allow_broad_scopes = try expectBool(item);
        if (object.get("allow_non_overridable_override")) |item| builder.approval.allow_non_overridable_override = try expectBool(item);
        if (object.get("allow_compatible_policy_hash")) |item| builder.approval.allow_compatible_policy_hash = try expectBool(item);
    }
    if (safety.get("emergency")) |value| {
        const object = try expectObject(value);
        try rejectUnknownKeys(object, &.{ "allow_land", "allow_return_to_home", "allow_hold_position", "allow_stop_or_brake", "allow_disarm", "fallback_order" });
        if (object.get("allow_land")) |item| builder.emergency.allow_land = try expectBool(item);
        if (object.get("allow_return_to_home")) |item| builder.emergency.allow_return_to_home = try expectBool(item);
        if (object.get("allow_hold_position")) |item| builder.emergency.allow_hold_position = try expectBool(item);
        if (object.get("allow_stop_or_brake")) |item| builder.emergency.allow_stop_or_brake = try expectBool(item);
        if (object.get("allow_disarm")) |item| builder.emergency.allow_disarm = try expectBool(item);
        if (object.get("fallback_order")) |item| try parseJsonFallbackOrder(builder, item);
    }
}

fn parseJsonFallbackOrder(builder: *PolicyBuilder, value: std.json.Value) !void {
    builder.emergency_fallback_order.clearRetainingCapacity();
    if (value != .array) return error.InvalidEmergencyFallbackPolicy;
    for (value.array.items) |item| try builder.emergency_fallback_order.append(builder.allocator, try parseCommandAction(try expectString(item)));
    if (builder.emergency_fallback_order.items.len == 0) return error.InvalidEmergencyFallbackPolicy;
}

fn parseJsonCommands(builder: *PolicyBuilder, object: std.json.ObjectMap) !void {
    try rejectUnknownKeys(object, &.{ "allow", "ask", "deny", "require_operator_approval" });
    if (object.get("allow")) |list| try parseJsonCommandList(&builder.commands_allow, builder.allocator, list);
    if (object.get("ask")) |list| try parseJsonCommandList(&builder.commands_ask, builder.allocator, list);
    if (object.get("deny")) |list| try parseJsonCommandList(&builder.commands_deny, builder.allocator, list);
    if (object.get("require_operator_approval")) |list| try parseJsonCommandList(&builder.commands_approval, builder.allocator, list);
}

fn parseJsonCommandList(out: *std.ArrayList(domain.commands.CommandAction), allocator: std.mem.Allocator, value: std.json.Value) !void {
    if (value != .array) return error.InvalidPolicy;
    for (value.array.items) |item| try out.append(allocator, try parseCommandAction(try expectString(item)));
}

fn validateLoadedPolicy(policy: *const schema.edge_policy_schema.EdgePolicyV1, options: LoadOptions) !void {
    if (options.strict_validation) {
        if (policy.vehicle.kind == .unknown) return error.UnknownVehicleKind;
        if (policy.vehicle.autopilot == .unknown) return error.UnknownAutopilotKind;
        if (policy.vehicle.adapter == .unknown) return error.UnknownAdapterKind;
    }
    try policy.validate();
    if (policy.safety.geofence) |geofence| {
        switch (geofence.shape) {
            .circle => {},
            .allowed_polygon => return error.UnsupportedGeofenceShape,
        }
    }
    if (policy.network.mode != .allowlist and policy.network.mode != .denylist and policy.network.mode != .offline) return error.InvalidNetworkPolicy;
    if (policy.audit.level != .full and policy.audit.level != .summary) return error.InvalidAuditPolicy;
}

pub fn parseCommandRequestJson(allocator: std.mem.Allocator, text: []const u8) !domain.commands.CommandRequest {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, text, .{}) catch return error.InvalidCommandRequest;
    defer parsed.deinit();
    return parseCommandRequestValue(allocator, parsed.value);
}

pub fn parseCommandRequestJsonOwned(allocator: std.mem.Allocator, text: []const u8) !ParsedCommandRequest {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), text, .{}) catch return error.InvalidCommandRequest;
    return .{
        .arena = arena,
        .value = try parseCommandRequestValue(arena.allocator(), parsed),
    };
}

fn parseCommandRequestValue(allocator: std.mem.Allocator, value: std.json.Value) !domain.commands.CommandRequest {
    _ = allocator;
    const object = try expectObject(value);
    try rejectUnknownKeys(object, &.{ "command_id", "vehicle_id", "action", "actor", "timestamp_ms", "timestamp_source", "source", "parameters", "mission_id", "correlation_id", "operator_approval_id" });
    const action = try parseCommandAction(try expectString(object.get("action") orelse return error.InvalidCommandRequest));
    return domain.commands.CommandRequest.init(.{
        .command_id = try expectString(object.get("command_id") orelse return error.InvalidCommandRequest),
        .vehicle_id = .{ .value = try expectString(object.get("vehicle_id") orelse return error.InvalidCommandRequest) },
        .action = action,
        .parameters = if (object.get("parameters")) |params| try parseCommandParametersJson(action, params) else .none,
        .actor = if (object.get("actor")) |actor| try expectString(actor) else "unknown-agent",
        .timestamp = .{
            .value = try expectInteger(object.get("timestamp_ms") orelse return error.InvalidCommandRequest),
            .source = if (object.get("timestamp_source")) |source| try parseTimestampSource(try expectString(source)) else .monotonic,
        },
        .source = if (object.get("source")) |source| try parseProvenance(try expectString(source)) else .fake_adapter,
        .mission_id = if (object.get("mission_id")) |item| try expectString(item) else null,
        .correlation_id = if (object.get("correlation_id")) |item| try expectString(item) else null,
        .operator_approval_id = if (object.get("operator_approval_id")) |item| try expectString(item) else null,
    });
}

pub fn parseVehicleStateJson(allocator: std.mem.Allocator, text: []const u8) !domain.state.VehicleState {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, text, .{}) catch return error.InvalidVehicleState;
    defer parsed.deinit();
    return parseVehicleStateValue(allocator, parsed.value);
}

pub fn parseVehicleStateJsonOwned(allocator: std.mem.Allocator, text: []const u8) !ParsedVehicleState {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), text, .{}) catch return error.InvalidVehicleState;
    return .{
        .arena = arena,
        .value = try parseVehicleStateValue(arena.allocator(), parsed),
    };
}

fn parseVehicleStateValue(allocator: std.mem.Allocator, value: std.json.Value) !domain.state.VehicleState {
    _ = allocator;
    const object = try expectObject(value);
    try rejectUnknownKeys(object, &.{ "vehicle_id", "vehicle_kind", "autopilot", "mode", "arm_state", "position", "velocity", "battery", "control_authority", "home_position", "timestamp_ms", "timestamp_source", "state_freshness", "provenance" });
    return .{
        .vehicle_id = .{ .value = try expectString(object.get("vehicle_id") orelse return error.InvalidVehicleState) },
        .vehicle_kind = if (object.get("vehicle_kind")) |item| try parseVehicleKind(try expectString(item)) else .unknown,
        .autopilot_kind = if (object.get("autopilot")) |item| try parseAutopilot(try expectString(item)) else .unknown,
        .mode = if (object.get("mode")) |item| try parseVehicleMode(try expectString(item)) else .unknown,
        .arm_state = if (object.get("arm_state")) |item| try parseArmState(try expectString(item)) else .unknown,
        .position = if (object.get("position")) |item| try parseGeoPointJson(item) else null,
        .velocity = if (object.get("velocity")) |item| try parseVelocityJson(item) else null,
        .battery_state = if (object.get("battery")) |item| try parseBatteryJson(item) else null,
        .control_authority = if (object.get("control_authority")) |item| try parseControlAuthority(try expectString(item)) else .unknown,
        .home_position = if (object.get("home_position")) |item| try parseGeoPointJson(item) else null,
        .timestamp = .{
            .value = try expectInteger(object.get("timestamp_ms") orelse return error.InvalidVehicleState),
            .source = if (object.get("timestamp_source")) |source| try parseTimestampSource(try expectString(source)) else .monotonic,
        },
        .state_freshness = if (object.get("state_freshness")) |item| try parseStateFreshness(try expectString(item)) else .unknown,
        .provenance = if (object.get("provenance")) |item| try parseProvenance(try expectString(item)) else .unknown,
    };
}

fn parseCommandParametersJson(action: domain.commands.CommandAction, value: std.json.Value) !domain.commands.CommandParameters {
    const object = try expectObject(value);
    if (object.get("waypoint")) |item| return .{ .waypoint = try parseGeoPointJson(item) };
    if (object.get("velocity")) |item| return .{ .velocity = try parseVelocityJson(item) };
    if (object.get("altitude")) |item| {
        const alt = try expectObject(item);
        return .{ .altitude = .{
            .altitude_m = try expectNumber(alt.get("altitude_m") orelse return error.InvalidCommandRequest),
            .altitude_reference = try parseAltitudeReference(try expectString(alt.get("altitude_reference") orelse return error.InvalidCommandRequest)),
        } };
    }
    if (object.get("heading")) |item| return .{ .heading = try parseHeadingJson(item) };
    if (object.get("mode")) |item| return .{ .mode = try parseVehicleMode(try expectString(item)) };
    if (object.get("mission_ref")) |item| return .{ .mission_ref = try expectString(item) };
    _ = action;
    return .none;
}

fn parseHeadingJson(value: std.json.Value) !domain.coordinates.Heading {
    const object = try expectObject(value);
    try rejectUnknownKeys(object, &.{ "value", "unit" });
    return .{
        .value = try expectNumber(object.get("value") orelse return error.InvalidCommandRequest),
        .unit = std.meta.stringToEnum(domain.coordinates.AngleUnit, try expectString(object.get("unit") orelse return error.InvalidCommandRequest)) orelse return error.InvalidCommandRequest,
    };
}

fn parseGeoPointJson(value: std.json.Value) !domain.coordinates.GeoPoint {
    const object = try expectObject(value);
    try rejectUnknownKeys(object, &.{ "latitude_deg", "longitude_deg", "altitude_m", "altitude_reference" });
    return .{
        .latitude_deg = try expectNumber(object.get("latitude_deg") orelse return error.InvalidPolicy),
        .longitude_deg = try expectNumber(object.get("longitude_deg") orelse return error.InvalidPolicy),
        .altitude_m = try expectNumber(object.get("altitude_m") orelse return error.InvalidPolicy),
        .altitude_reference = try parseAltitudeReference(try expectString(object.get("altitude_reference") orelse return error.InvalidPolicy)),
    };
}

fn parseVelocityJson(value: std.json.Value) !domain.coordinates.Velocity3D {
    const object = try expectObject(value);
    try rejectUnknownKeys(object, &.{ "vx_mps", "vy_mps", "vz_mps", "frame" });
    return .{
        .vx_mps = try expectNumber(object.get("vx_mps") orelse return error.InvalidCommandRequest),
        .vy_mps = try expectNumber(object.get("vy_mps") orelse return error.InvalidCommandRequest),
        .vz_mps = try expectNumber(object.get("vz_mps") orelse return error.InvalidCommandRequest),
        .frame = try parseCoordinateFrame(try expectString(object.get("frame") orelse return error.InvalidCommandRequest)),
    };
}

fn parseBatteryJson(value: std.json.Value) !domain.battery.BatteryState {
    const object = try expectObject(value);
    try rejectUnknownKeys(object, &.{ "percent_remaining", "voltage_v", "current_a", "source" });
    return .{
        .percent_remaining = try expectNumber(object.get("percent_remaining") orelse return error.InvalidVehicleState),
        .voltage_v = try expectNumber(object.get("voltage_v") orelse return error.InvalidVehicleState),
        .current_a = try expectNumber(object.get("current_a") orelse return error.InvalidVehicleState),
        .source = if (object.get("source")) |item| try parseTimestampSource(try expectString(item)) else .unknown,
    };
}

fn parseVehicleKind(value: []const u8) !domain.vehicle.VehicleKind {
    return std.meta.stringToEnum(domain.vehicle.VehicleKind, value) orelse error.UnknownVehicleKind;
}

fn parseAutopilot(value: []const u8) !domain.vehicle.AutopilotKind {
    return std.meta.stringToEnum(domain.vehicle.AutopilotKind, value) orelse error.UnknownAutopilotKind;
}

fn parseAdapter(value: []const u8) !domain.vehicle.AdapterKind {
    return std.meta.stringToEnum(domain.vehicle.AdapterKind, value) orelse error.UnknownAdapterKind;
}

fn parseVehicleMode(value: []const u8) !domain.vehicle.VehicleMode {
    return std.meta.stringToEnum(domain.vehicle.VehicleMode, value) orelse error.UnknownVehicleMode;
}

fn parseArmState(value: []const u8) !domain.vehicle.ArmState {
    return std.meta.stringToEnum(domain.vehicle.ArmState, value) orelse error.UnknownStateIsUnsafe;
}

fn parseControlAuthority(value: []const u8) !domain.vehicle.ControlAuthority {
    return std.meta.stringToEnum(domain.vehicle.ControlAuthority, value) orelse error.UnknownStateIsUnsafe;
}

fn parseCommandAction(value: []const u8) !domain.commands.CommandAction {
    return std.meta.stringToEnum(domain.commands.CommandAction, value) orelse error.UnknownCommandAction;
}

fn parseAltitudeReference(value: []const u8) !domain.coordinates.AltitudeReference {
    const parsed = std.meta.stringToEnum(domain.coordinates.AltitudeReference, value) orelse return error.UnknownAltitudeReference;
    if (parsed == .unknown) return error.UnknownAltitudeReference;
    return parsed;
}

fn parseCoordinateFrame(value: []const u8) !domain.coordinates.CoordinateFrame {
    const parsed = std.meta.stringToEnum(domain.coordinates.CoordinateFrame, value) orelse return error.UnknownCoordinateFrame;
    if (parsed == .unknown) return error.UnknownCoordinateFrame;
    return parsed;
}

fn parseBoundaryAction(value: []const u8) !domain.geofence.BoundaryAction {
    return std.meta.stringToEnum(domain.geofence.BoundaryAction, value) orelse error.InvalidGeofenceBoundaryAction;
}

fn parseTimestampSource(value: []const u8) !domain.coordinates.TimestampSource {
    return std.meta.stringToEnum(domain.coordinates.TimestampSource, value) orelse error.UnknownTimestampSource;
}

fn parseProvenance(value: []const u8) !domain.state.StateProvenance {
    return std.meta.stringToEnum(domain.state.StateProvenance, value) orelse error.UnknownStateIsUnsafe;
}

fn parseStateFreshness(value: []const u8) !domain.state.StateFreshness {
    return std.meta.stringToEnum(domain.state.StateFreshness, value) orelse error.UnknownStateIsUnsafe;
}

fn stripComment(line: []const u8) []const u8 {
    const index = std.mem.indexOfScalar(u8, line, '#') orelse return line;
    return line[0..index];
}

fn countIndent(line: []const u8) usize {
    var count: usize = 0;
    while (count < line.len and line[count] == ' ') count += 1;
    return count;
}

const KeyValue = struct { key: []const u8, value: []const u8 };

fn splitKeyValue(line: []const u8) !KeyValue {
    const index = std.mem.indexOfScalar(u8, line, ':') orelse return error.InvalidPolicy;
    return .{
        .key = std.mem.trim(u8, line[0..index], " \t"),
        .value = cleanScalar(std.mem.trim(u8, line[index + 1 ..], " \t")),
    };
}

fn cleanScalar(value: []const u8) []const u8 {
    if (value.len >= 2 and ((value[0] == '"' and value[value.len - 1] == '"') or (value[0] == '\'' and value[value.len - 1] == '\''))) {
        return value[1 .. value.len - 1];
    }
    return value;
}

fn parseBool(value: []const u8) !bool {
    if (std.mem.eql(u8, value, "true")) return true;
    if (std.mem.eql(u8, value, "false")) return false;
    return error.InvalidPolicy;
}

fn parseU32(value: []const u8) !u32 {
    return std.fmt.parseInt(u32, value, 10) catch return error.InvalidPolicy;
}

fn parseU64(value: []const u8) !u64 {
    return std.fmt.parseInt(u64, value, 10) catch return error.InvalidPolicy;
}

fn parseU8(value: []const u8) !u8 {
    return std.fmt.parseInt(u8, value, 10) catch return error.InvalidPolicy;
}

fn parseF64(value: []const u8) !f64 {
    return std.fmt.parseFloat(f64, value) catch return error.InvalidPolicy;
}

fn parseDegradedBehavior(value: []const u8) !health_watchdog.DegradedBehavior {
    return health_watchdog.DegradedBehavior.parse(value) orelse error.UnknownDegradedBehavior;
}

fn parseEmergencyAllowance(value: []const u8) !health_watchdog.EmergencyAllowance {
    return health_watchdog.EmergencyAllowance.parse(value) orelse error.UnknownDegradedBehavior;
}

fn expectObject(value: std.json.Value) !std.json.ObjectMap {
    if (value != .object) return error.InvalidPolicy;
    return value.object;
}

fn expectString(value: std.json.Value) ![]const u8 {
    if (value != .string) return error.InvalidPolicy;
    return value.string;
}

fn expectBool(value: std.json.Value) !bool {
    if (value != .bool) return error.InvalidPolicy;
    return value.bool;
}

fn expectInteger(value: std.json.Value) !i128 {
    if (value == .integer) return value.integer;
    return error.InvalidPolicy;
}

fn expectPositiveU64(value: std.json.Value) !u64 {
    const integer = try expectInteger(value);
    if (integer <= 0) return error.InvalidWatchdogPolicy;
    return @intCast(integer);
}

fn expectPositiveU8(value: std.json.Value) !u8 {
    const integer = try expectInteger(value);
    if (integer <= 0 or integer > 255) return error.InvalidWatchdogPolicy;
    return @intCast(integer);
}

fn expectNumber(value: std.json.Value) !f64 {
    return switch (value) {
        .integer => |integer| @floatFromInt(integer),
        .float => |float| float,
        else => error.InvalidPolicy,
    };
}

fn rejectUnknownKeys(object: std.json.ObjectMap, allowed: []const []const u8) !void {
    var iterator = object.iterator();
    while (iterator.next()) |entry| {
        var ok = false;
        for (allowed) |candidate| {
            if (std.mem.eql(u8, entry.key_ptr.*, candidate)) {
                ok = true;
                break;
            }
        }
        if (!ok) return error.InvalidPolicy;
    }
}
