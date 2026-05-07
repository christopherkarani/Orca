const vehicle = @import("vehicle.zig");
const coordinates = @import("coordinates.zig");
const state = @import("state.zig");

pub const CommandCategory = enum {
    read_only,
    normal_control,
    sensitive_high_risk,
};

pub const RiskCategory = enum {
    low,
    medium,
    high,
    critical,
    emergency_safe,
    unknown,
};

pub const CommandAction = enum {
    read_telemetry,
    read_mission_status,
    read_vehicle_state,
    read_camera_frame,
    arm,
    disarm,
    takeoff,
    land,
    return_to_home,
    hold_position,
    set_waypoint,
    set_velocity,
    set_altitude,
    set_heading,
    start_mission,
    pause_mission,
    resume_mission,
    upload_mission,
    change_geofence,
    disable_geofence,
    disable_failsafe,
    set_mode,
    override_operator,
    raw_actuator_output,
    payload_release,
    firmware_update,
    companion_computer_reboot,
    telemetry_stream_external,

    pub fn all() []const CommandAction {
        return &.{
            .read_telemetry,
            .read_mission_status,
            .read_vehicle_state,
            .read_camera_frame,
            .arm,
            .disarm,
            .takeoff,
            .land,
            .return_to_home,
            .hold_position,
            .set_waypoint,
            .set_velocity,
            .set_altitude,
            .set_heading,
            .start_mission,
            .pause_mission,
            .resume_mission,
            .upload_mission,
            .change_geofence,
            .disable_geofence,
            .disable_failsafe,
            .set_mode,
            .override_operator,
            .raw_actuator_output,
            .payload_release,
            .firmware_update,
            .companion_computer_reboot,
            .telemetry_stream_external,
        };
    }

    pub fn category(self: CommandAction) CommandCategory {
        return switch (self) {
            .read_telemetry,
            .read_mission_status,
            .read_vehicle_state,
            .read_camera_frame,
            => .read_only,
            .arm,
            .disarm,
            .takeoff,
            .land,
            .return_to_home,
            .hold_position,
            .set_waypoint,
            .set_velocity,
            .set_altitude,
            .set_heading,
            .start_mission,
            .pause_mission,
            .resume_mission,
            .upload_mission,
            => .normal_control,
            .change_geofence,
            .disable_geofence,
            .disable_failsafe,
            .set_mode,
            .override_operator,
            .raw_actuator_output,
            .payload_release,
            .firmware_update,
            .companion_computer_reboot,
            .telemetry_stream_external,
            => .sensitive_high_risk,
        };
    }
};

pub const CommandParameters = union(enum) {
    none,
    waypoint: coordinates.GeoPoint,
    velocity: coordinates.Velocity3D,
    altitude: struct {
        altitude_m: f64,
        altitude_reference: coordinates.AltitudeReference,
    },
    heading: coordinates.Heading,
    mode: vehicle.VehicleMode,
    mission_ref: []const u8,
};

pub const RawProtocolReference = struct {
    protocol: []const u8,
    message_name: []const u8,
    message_id: ?u32 = null,
};

pub const CommandRequestInit = struct {
    command_id: []const u8,
    vehicle_id: vehicle.VehicleId,
    action: CommandAction,
    parameters: CommandParameters = .none,
    actor: []const u8,
    timestamp: coordinates.Timestamp,
    source: state.StateProvenance,
    mission_id: ?[]const u8 = null,
    correlation_id: ?[]const u8 = null,
    operator_approval_id: ?[]const u8 = null,
    risk_classification: ?RiskCategory = null,
    raw_protocol_reference: ?RawProtocolReference = null,
};

pub const CommandRequest = struct {
    command_id: []const u8,
    vehicle_id: vehicle.VehicleId,
    action: CommandAction,
    parameters: CommandParameters = .none,
    actor: []const u8,
    timestamp: coordinates.Timestamp,
    source: state.StateProvenance,
    mission_id: ?[]const u8 = null,
    correlation_id: ?[]const u8 = null,
    operator_approval_id: ?[]const u8 = null,
    risk_classification: RiskCategory = .unknown,
    raw_protocol_reference: ?RawProtocolReference = null,

    pub fn init(args: CommandRequestInit) CommandRequest {
        return .{
            .command_id = args.command_id,
            .vehicle_id = args.vehicle_id,
            .action = args.action,
            .parameters = args.parameters,
            .actor = args.actor,
            .timestamp = args.timestamp,
            .source = args.source,
            .mission_id = args.mission_id,
            .correlation_id = args.correlation_id,
            .operator_approval_id = args.operator_approval_id,
            .risk_classification = args.risk_classification orelse @import("risk.zig").classifyCommand(args.action),
            .raw_protocol_reference = args.raw_protocol_reference,
        };
    }

    pub fn validate(self: CommandRequest) !void {
        if (self.command_id.len == 0) return error.MissingCommandId;
        try self.vehicle_id.validate();
        if (self.actor.len == 0) return error.MissingActor;
        try self.timestamp.validate();
        if (self.source == .unknown) return error.UnknownStateIsUnsafe;
        try validateParameterShape(self.action, self.parameters);
        switch (self.parameters) {
            .none => {},
            .waypoint => |point| try point.validate(),
            .velocity => |velocity| try velocity.validateKnownFrame(),
            .altitude => |altitude| if (altitude.altitude_reference == .unknown) return error.UnknownAltitudeReference,
            .heading => {},
            .mode => |mode| if (mode == .unknown) return error.UnknownStateIsUnsafe,
            .mission_ref => |mission_ref| if (mission_ref.len == 0) return error.MissingMissionId,
        }
    }
};

fn validateParameterShape(action: CommandAction, parameters: CommandParameters) !void {
    switch (action) {
        .set_waypoint => try requireParameter(parameters, .waypoint),
        .set_velocity => try requireParameter(parameters, .velocity),
        .set_altitude, .takeoff => try requireParameter(parameters, .altitude),
        .set_heading => try requireParameter(parameters, .heading),
        .set_mode => try requireParameter(parameters, .mode),
        else => {},
    }
}

const RequiredParameter = enum {
    waypoint,
    velocity,
    altitude,
    heading,
    mode,
};

fn requireParameter(parameters: CommandParameters, required: RequiredParameter) !void {
    if (parameters == .none) return error.MissingCommandParameters;
    const matches = switch (required) {
        .waypoint => parameters == .waypoint,
        .velocity => parameters == .velocity,
        .altitude => parameters == .altitude,
        .heading => parameters == .heading,
        .mode => parameters == .mode,
    };
    if (!matches) return error.InvalidCommandParameters;
}
