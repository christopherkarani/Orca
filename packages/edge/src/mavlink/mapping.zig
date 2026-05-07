const std = @import("std");

const domain = @import("../domain/mod.zig");
const classifier = @import("classifier.zig");
const mav_commands = @import("commands.zig");
const dialect = @import("dialect.zig");
const framing = @import("framing.zig");
const messages = @import("messages.zig");

pub const MapContext = struct {
    vehicle_id: []const u8,
    now_ms: i128,
    source: domain.state.StateProvenance = .fake_adapter,
};

pub const UnsupportedCommand = struct {
    message_id: u32,
    command_id: ?u16 = null,
    risk: domain.commands.RiskCategory,
    reason: []const u8,
};

pub const CommandMapping = struct {
    allocator: std.mem.Allocator,
    classification: classifier.Classification,
    request: ?domain.commands.CommandRequest = null,
    unsupported: ?UnsupportedCommand = null,
    command_id_storage: ?[]u8 = null,
    actor_storage: ?[]u8 = null,
    mission_id_storage: ?[]u8 = null,

    pub fn deinit(self: *CommandMapping) void {
        if (self.command_id_storage) |value| self.allocator.free(value);
        if (self.actor_storage) |value| self.allocator.free(value);
        if (self.mission_id_storage) |value| self.allocator.free(value);
        self.* = undefined;
    }
};

pub fn mapFrameToCommand(allocator: std.mem.Allocator, frame: framing.Frame, context: MapContext) !CommandMapping {
    const class = try classifier.classifyFrame(frame);
    var result: CommandMapping = .{ .allocator = allocator, .classification = class };
    errdefer result.deinit();

    const decoded = try messages.decode(frame);
    switch (decoded) {
        .command_long => |message| try mapMavCommand(allocator, &result, frame, context, message.command, message.params, null, null, null),
        .command_int => |message| try mapMavCommand(allocator, &result, frame, context, message.command, .{ message.params[0], message.params[1], message.params[2], message.params[3], 0, 0, message.z }, message.x, message.y, message.frame),
        .set_mode => |message| try buildRequest(allocator, &result, frame, context, .set_mode, .{ .mode = modeFromMav(message.base_mode, message.custom_mode) }, null),
        .param_set => |message| try mapParamSet(allocator, &result, frame, context, message),
        .set_position_target_global_int => |message| try mapGlobalSetpoint(allocator, &result, frame, context, message),
        .set_position_target_local_ned => |message| try mapLocalSetpoint(allocator, &result, frame, context, message),
        .mission_count => |_| try buildRequest(allocator, &result, frame, context, .upload_mission, .none, "mission-upload"),
        .mission_item => |message| try mapMissionItemFloat(allocator, &result, frame, context, message),
        .mission_item_int => |message| try mapMissionItem(allocator, &result, frame, context, message),
        else => {
            if (class.safety_sensitive) {
                result.unsupported = .{ .message_id = frame.msgid, .command_id = class.command_id, .risk = .unknown, .reason = "unsupported safety-sensitive MAVLink message" };
            }
        },
    }
    return result;
}

fn mapMavCommand(
    allocator: std.mem.Allocator,
    result: *CommandMapping,
    frame: framing.Frame,
    context: MapContext,
    command_id: u16,
    params: [7]f32,
    x: ?i32,
    y: ?i32,
    command_frame: ?u8,
) !void {
    switch (command_id) {
        mav_commands.MAV_CMD_COMPONENT_ARM_DISARM => {
            const action: domain.commands.CommandAction = if (params[0] >= 0.5) .arm else .disarm;
            try buildRequest(allocator, result, frame, context, action, .none, null);
        },
        mav_commands.MAV_CMD_NAV_TAKEOFF => {
            const altitude = if (params[6] > 0) params[6] else 20;
            try buildRequest(allocator, result, frame, context, .takeoff, .{ .altitude = .{ .altitude_m = @floatCast(altitude), .altitude_reference = .amsl } }, null);
        },
        mav_commands.MAV_CMD_NAV_LAND => try buildRequest(allocator, result, frame, context, .land, .none, null),
        mav_commands.MAV_CMD_NAV_RETURN_TO_LAUNCH => try buildRequest(allocator, result, frame, context, .return_to_home, .none, null),
        mav_commands.MAV_CMD_MISSION_START => try buildRequest(allocator, result, frame, context, .start_mission, .none, "mission-start"),
        mav_commands.MAV_CMD_DO_PAUSE_CONTINUE => {
            const action: domain.commands.CommandAction = if (params[0] == 0) .pause_mission else .resume_mission;
            try buildRequest(allocator, result, frame, context, action, .none, null);
        },
        mav_commands.MAV_CMD_DO_SET_MODE => try buildRequest(allocator, result, frame, context, .set_mode, .{ .mode = modeFromMav(@intFromFloat(params[0]), @intFromFloat(params[1])) }, null),
        mav_commands.MAV_CMD_DO_SET_SERVO, mav_commands.MAV_CMD_DO_SET_ACTUATOR => try buildRequest(allocator, result, frame, context, .raw_actuator_output, .none, null),
        mav_commands.MAV_CMD_PREFLIGHT_REBOOT_SHUTDOWN => try buildRequest(allocator, result, frame, context, .companion_computer_reboot, .none, null),
        mav_commands.MAV_CMD_DO_GRIPPER, mav_commands.MAV_CMD_PAYLOAD_PREPARE_DEPLOY, mav_commands.MAV_CMD_PAYLOAD_CONTROL_DEPLOY => try buildRequest(allocator, result, frame, context, .payload_release, .none, null),
        mav_commands.MAV_CMD_NAV_WAYPOINT => {
            if (x != null and y != null and command_frame != null) {
                try buildRequest(allocator, result, frame, context, .set_waypoint, .{ .waypoint = geoPointFromInt(x.?, y.?, params[6], command_frame.?) }, null);
            } else {
                result.unsupported = .{ .message_id = frame.msgid, .command_id = command_id, .risk = .high, .reason = "waypoint command lacks integer target fields" };
            }
        },
        else => result.unsupported = .{ .message_id = frame.msgid, .command_id = command_id, .risk = .unknown, .reason = "unsupported MAVLink command id" },
    }
}

fn mapParamSet(allocator: std.mem.Allocator, result: *CommandMapping, frame: framing.Frame, context: MapContext, message: messages.ParamSet) !void {
    var end: usize = 0;
    while (end < message.param_id.len and message.param_id[end] != 0) : (end += 1) {}
    const id = message.param_id[0..end];
    if (containsInsensitive(id, "FENCE")) {
        try buildRequest(allocator, result, frame, context, .disable_geofence, .none, null);
        return;
    }
    if (containsInsensitive(id, "FAIL") or containsInsensitive(id, "FS_")) {
        try buildRequest(allocator, result, frame, context, .disable_failsafe, .none, null);
        return;
    }
    result.unsupported = .{ .message_id = frame.msgid, .risk = .unknown, .reason = "unsupported PARAM_SET safety effect" };
}

fn mapGlobalSetpoint(allocator: std.mem.Allocator, result: *CommandMapping, frame: framing.Frame, context: MapContext, message: messages.SetPositionTargetGlobalInt) !void {
    if (!messages.positionIgnored(message.type_mask)) {
        try buildRequest(allocator, result, frame, context, .set_waypoint, .{ .waypoint = geoPointFromInt(message.lat_int, message.lon_int, message.alt_m, message.coordinate_frame) }, null);
        return;
    }
    if (!messages.velocityIgnored(message.type_mask)) {
        try buildRequest(allocator, result, frame, context, .set_velocity, .{ .velocity = .{ .vx_mps = @floatCast(message.vx), .vy_mps = @floatCast(message.vy), .vz_mps = @floatCast(message.vz), .frame = .local_ned } }, null);
        return;
    }
    result.unsupported = .{ .message_id = frame.msgid, .risk = .unknown, .reason = "setpoint ignores position and velocity" };
}

fn mapLocalSetpoint(allocator: std.mem.Allocator, result: *CommandMapping, frame: framing.Frame, context: MapContext, message: messages.SetPositionTargetLocalNed) !void {
    if (!messages.velocityIgnored(message.type_mask)) {
        try buildRequest(allocator, result, frame, context, .set_velocity, .{ .velocity = .{ .vx_mps = @floatCast(message.vx), .vy_mps = @floatCast(message.vy), .vz_mps = @floatCast(message.vz), .frame = .local_ned } }, null);
        return;
    }
    result.unsupported = .{ .message_id = frame.msgid, .risk = .high, .reason = "local position setpoints are detected but not mapped to a Phase 27 command parameter" };
}

fn mapMissionItem(allocator: std.mem.Allocator, result: *CommandMapping, frame: framing.Frame, context: MapContext, message: messages.MissionItemInt) !void {
    if (message.command == mav_commands.MAV_CMD_NAV_WAYPOINT) {
        try buildRequest(allocator, result, frame, context, .set_waypoint, .{ .waypoint = geoPointFromInt(message.x, message.y, message.z, message.frame) }, "mission-upload");
        return;
    }
    if (message.command == mav_commands.MAV_CMD_NAV_TAKEOFF) {
        try buildRequest(allocator, result, frame, context, .takeoff, .{ .altitude = .{ .altitude_m = @floatCast(message.z), .altitude_reference = altitudeRefForFrame(message.frame) } }, "mission-upload");
        return;
    }
    if (message.command == mav_commands.MAV_CMD_NAV_LAND) {
        try buildRequest(allocator, result, frame, context, .land, .none, "mission-upload");
        return;
    }
    result.unsupported = .{ .message_id = frame.msgid, .command_id = message.command, .risk = .unknown, .reason = "unsupported mission item command" };
}

fn mapMissionItemFloat(allocator: std.mem.Allocator, result: *CommandMapping, frame: framing.Frame, context: MapContext, message: messages.MissionItem) !void {
    if (message.command == mav_commands.MAV_CMD_NAV_WAYPOINT) {
        try buildRequest(allocator, result, frame, context, .set_waypoint, .{ .waypoint = geoPointFromFloat(message.x, message.y, message.z, message.frame) }, "mission-upload");
        return;
    }
    if (message.command == mav_commands.MAV_CMD_NAV_TAKEOFF) {
        try buildRequest(allocator, result, frame, context, .takeoff, .{ .altitude = .{ .altitude_m = @floatCast(message.z), .altitude_reference = altitudeRefForFrame(message.frame) } }, "mission-upload");
        return;
    }
    if (message.command == mav_commands.MAV_CMD_NAV_LAND) {
        try buildRequest(allocator, result, frame, context, .land, .none, "mission-upload");
        return;
    }
    result.unsupported = .{ .message_id = frame.msgid, .command_id = message.command, .risk = .unknown, .reason = "unsupported mission item command" };
}

fn buildRequest(
    allocator: std.mem.Allocator,
    result: *CommandMapping,
    frame: framing.Frame,
    context: MapContext,
    action: domain.commands.CommandAction,
    params: domain.commands.CommandParameters,
    mission_id: ?[]const u8,
) !void {
    result.command_id_storage = try std.fmt.allocPrint(allocator, "mavlink-{d}-{d}-{d}-{d}", .{ frame.sequence, frame.sysid, frame.compid, frame.msgid });
    result.actor_storage = try std.fmt.allocPrint(allocator, "mavlink:sysid={d}:compid={d}", .{ frame.sysid, frame.compid });
    if (mission_id) |id| result.mission_id_storage = try allocator.dupe(u8, id);
    result.request = domain.commands.CommandRequest.init(.{
        .command_id = result.command_id_storage.?,
        .vehicle_id = .{ .value = context.vehicle_id },
        .action = action,
        .parameters = params,
        .actor = result.actor_storage.?,
        .timestamp = .{ .value = context.now_ms, .source = .monotonic },
        .source = context.source,
        .mission_id = result.mission_id_storage,
        .risk_classification = domain.risk.classifyCommand(action),
        .raw_protocol_reference = .{
            .protocol = "mavlink",
            .message_name = dialect.nameFor(frame.msgid),
            .message_id = frame.msgid,
        },
    });
}

fn geoPointFromInt(lat_int: i32, lon_int: i32, alt: f32, frame: u8) domain.coordinates.GeoPoint {
    return .{
        .latitude_deg = @as(f64, @floatFromInt(lat_int)) / 10_000_000.0,
        .longitude_deg = @as(f64, @floatFromInt(lon_int)) / 10_000_000.0,
        .altitude_m = @floatCast(alt),
        .altitude_reference = altitudeRefForFrame(frame),
    };
}

fn geoPointFromFloat(lat_deg: f32, lon_deg: f32, alt: f32, frame: u8) domain.coordinates.GeoPoint {
    return .{
        .latitude_deg = @floatCast(lat_deg),
        .longitude_deg = @floatCast(lon_deg),
        .altitude_m = @floatCast(alt),
        .altitude_reference = altitudeRefForFrame(frame),
    };
}

fn altitudeRefForFrame(frame: u8) domain.coordinates.AltitudeReference {
    return switch (frame) {
        messages.MAV_FRAME_GLOBAL, messages.MAV_FRAME_GLOBAL_INT => .amsl,
        messages.MAV_FRAME_GLOBAL_RELATIVE_ALT, messages.MAV_FRAME_GLOBAL_RELATIVE_ALT_INT => .home_relative,
        messages.MAV_FRAME_GLOBAL_TERRAIN_ALT, messages.MAV_FRAME_GLOBAL_TERRAIN_ALT_INT => .terrain_relative,
        else => .unknown,
    };
}

fn modeFromMav(base_mode: u8, custom_mode: u32) domain.vehicle.VehicleMode {
    _ = custom_mode;
    if ((base_mode & 0x10) != 0) return .auto;
    if ((base_mode & 0x80) != 0) return .guided;
    return .guided;
}

fn containsInsensitive(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0 or haystack.len < needle.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        var matched = true;
        for (needle, 0..) |needle_byte, j| {
            if (std.ascii.toUpper(haystack[i + j]) != std.ascii.toUpper(needle_byte)) {
                matched = false;
                break;
            }
        }
        if (matched) return true;
    }
    return false;
}
