const std = @import("std");

const domain = @import("../domain/mod.zig");
const schema = @import("../schema/mod.zig");

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
        if (self.source_path) |source| self.allocator.free(source);
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
    emergency,
    commands,
    network,
    audit,
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
    emergency: domain.safety_envelope.EmergencyBehaviorConstraints = .{},
    commands_allow: std.ArrayList(domain.commands.CommandAction) = .empty,
    commands_ask: std.ArrayList(domain.commands.CommandAction) = .empty,
    commands_deny: std.ArrayList(domain.commands.CommandAction) = .empty,
    commands_approval: std.ArrayList(domain.commands.CommandAction) = .empty,
    network: domain.safety_envelope.NetworkConstraints = .{},
    audit: schema.edge_policy_schema.AuditPolicy = .{},

    fn deinit(self: *PolicyBuilder) void {
        self.commands_allow.deinit(self.allocator);
        self.commands_ask.deinit(self.allocator);
        self.commands_deny.deinit(self.allocator);
        self.commands_approval.deinit(self.allocator);
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
                    .emergency = self.emergency,
                },
                .commands = command_policy,
                .network = self.network,
                .audit = self.audit,
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
            } else {
                return error.InvalidPolicy;
            }
            continue;
        }

        switch (section) {
            .vehicle => try parseYamlVehicle(&builder, key, value),
            .safety, .state_freshness, .geofence, .geofence_center, .geofence_home_position, .velocity, .altitude, .battery, .emergency => {
                try parseYamlSafety(&builder, &section, indent, key, value);
            },
            .commands => try parseYamlCommands(&command_list, key),
            .network => try parseYamlNetwork(&builder, key, value),
            .audit => try parseYamlAudit(&builder, key, value),
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
        if (std.mem.eql(u8, key, "state_freshness")) section.* = .state_freshness else if (std.mem.eql(u8, key, "geofence")) section.* = .geofence else if (std.mem.eql(u8, key, "velocity")) section.* = .velocity else if (std.mem.eql(u8, key, "altitude")) section.* = .altitude else if (std.mem.eql(u8, key, "battery")) section.* = .battery else if (std.mem.eql(u8, key, "emergency")) section.* = .emergency else return error.InvalidPolicy;
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
        .emergency => {
            if (std.mem.eql(u8, key, "allow_land")) builder.emergency.allow_land = try parseBool(value) else if (std.mem.eql(u8, key, "allow_return_to_home")) builder.emergency.allow_return_to_home = try parseBool(value) else return error.UnknownEmergencyBehaviorDefault;
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

fn parseJsonPolicy(allocator: std.mem.Allocator, text: []const u8, source_path: ?[]const u8, options: LoadOptions) !LoadedPolicy {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, text, .{}) catch return error.InvalidPolicy;
    defer parsed.deinit();
    const object = try expectObject(parsed.value);
    try rejectUnknownKeys(object, &.{ "version", "vehicle", "safety", "commands", "network", "audit" });

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
    return builder.build();
}

fn parseJsonSafety(builder: *PolicyBuilder, safety: std.json.ObjectMap) !void {
    try rejectUnknownKeys(safety, &.{ "state_freshness", "geofence", "velocity", "altitude", "battery", "emergency" });
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
    const object = try expectObject(parsed.value);
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
    const object = try expectObject(parsed.value);
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

fn parseF64(value: []const u8) !f64 {
    return std.fmt.parseFloat(f64, value) catch return error.InvalidPolicy;
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
