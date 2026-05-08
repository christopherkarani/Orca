const std = @import("std");

const domain = @import("../domain/mod.zig");
const mavlink = @import("../mavlink/mod.zig");

const MAV_TYPE_QUADROTOR: u8 = 2;
const MAV_AUTOPILOT_PX4: u8 = 12;
const MAV_STATE_ACTIVE: u8 = 4;
const MAVLINK_VERSION: u8 = 3;

pub const Options = struct {
    sysid: u8 = 42,
    compid: u8 = 1,
};

pub const HeartbeatOptions = struct {
    armed: bool = false,
    base_mode: u8 = 0x08,
};

pub const GlobalPositionOptions = struct {
    lat_int: i32,
    lon_int: i32,
    alt_mm: i32,
    relative_alt_mm: i32 = 0,
    vx_cms: i16 = 0,
    vy_cms: i16 = 0,
    vz_cms: i16 = 0,
    heading_cdeg: u16 = 65535,
};

pub const LocalPositionOptions = struct {
    x: f32,
    y: f32,
    z: f32,
    vx: f32 = 0,
    vy: f32 = 0,
    vz: f32 = 0,
};

pub const AttitudeOptions = struct {
    roll: f32 = 0,
    pitch: f32 = 0,
    yaw: f32 = 0,
    rollspeed: f32 = 0,
    pitchspeed: f32 = 0,
    yawspeed: f32 = 0,
};

pub const BatteryOptions = struct {
    percent_remaining: i8,
    voltage_mv: u16,
    current_ca: i16,
};

pub const CommandAction = enum {
    arm,
    disarm,
    takeoff,
    land,
    return_to_home,
    hold,
    set_waypoint,
    set_velocity,
    disable_failsafe,
    disable_geofence,
    raw_actuator_output,
    start_mission,
    set_mode,
    unknown,
};

pub const CommandOptions = struct {
    action: CommandAction,
    lat_int: i32 = 370000000,
    lon_int: i32 = -1220000000,
    alt_m: f32 = 20,
    vx: f32 = 0,
    vy: f32 = 0,
    vz: f32 = 0,
};

pub const FakePx4Adapter = struct {
    allocator: std.mem.Allocator,
    options: Options,
    seq: u8 = 0,
    accepted: std.ArrayList([]u8) = .empty,
    blocked: std.ArrayList([]u8) = .empty,

    pub fn init(allocator: std.mem.Allocator, options: Options) FakePx4Adapter {
        return .{ .allocator = allocator, .options = options };
    }

    pub fn deinit(self: *FakePx4Adapter) void {
        for (self.accepted.items) |bytes| self.allocator.free(bytes);
        for (self.blocked.items) |bytes| self.allocator.free(bytes);
        self.accepted.deinit(self.allocator);
        self.blocked.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn recordAccepted(self: *FakePx4Adapter, frame: mavlink.framing.Frame) !void {
        try self.accepted.append(self.allocator, try self.allocator.dupe(u8, frame.bytes));
    }

    pub fn recordBlocked(self: *FakePx4Adapter, frame: mavlink.framing.Frame) !void {
        try self.blocked.append(self.allocator, try self.allocator.dupe(u8, frame.bytes));
    }

    pub fn heartbeatFrame(self: *FakePx4Adapter, options: HeartbeatOptions) ![]u8 {
        var payload = [_]u8{0} ** 9;
        payload[4] = MAV_TYPE_QUADROTOR;
        payload[5] = MAV_AUTOPILOT_PX4;
        payload[6] = options.base_mode | if (options.armed) @as(u8, 0x80) else 0;
        payload[7] = MAV_STATE_ACTIVE;
        payload[8] = MAVLINK_VERSION;
        return self.encode(mavlink.dialect.HEARTBEAT, &payload);
    }

    pub fn globalPositionFrame(self: *FakePx4Adapter, options: GlobalPositionOptions) ![]u8 {
        var payload = [_]u8{0} ** 28;
        mavlink.framing.writeU32LE(payload[0..4], 100);
        mavlink.framing.writeI32LE(payload[4..8], options.lat_int);
        mavlink.framing.writeI32LE(payload[8..12], options.lon_int);
        mavlink.framing.writeI32LE(payload[12..16], options.alt_mm);
        mavlink.framing.writeI32LE(payload[16..20], options.relative_alt_mm);
        mavlink.framing.writeI16LE(payload[20..22], options.vx_cms);
        mavlink.framing.writeI16LE(payload[22..24], options.vy_cms);
        mavlink.framing.writeI16LE(payload[24..26], options.vz_cms);
        mavlink.framing.writeU16LE(payload[26..28], options.heading_cdeg);
        return self.encode(mavlink.dialect.GLOBAL_POSITION_INT, &payload);
    }

    pub fn localPositionFrame(self: *FakePx4Adapter, options: LocalPositionOptions) ![]u8 {
        var payload = [_]u8{0} ** 28;
        mavlink.framing.writeU32LE(payload[0..4], 100);
        mavlink.framing.writeF32LE(payload[4..8], options.x);
        mavlink.framing.writeF32LE(payload[8..12], options.y);
        mavlink.framing.writeF32LE(payload[12..16], options.z);
        mavlink.framing.writeF32LE(payload[16..20], options.vx);
        mavlink.framing.writeF32LE(payload[20..24], options.vy);
        mavlink.framing.writeF32LE(payload[24..28], options.vz);
        return self.encode(mavlink.dialect.LOCAL_POSITION_NED, &payload);
    }

    pub fn attitudeFrame(self: *FakePx4Adapter, options: AttitudeOptions) ![]u8 {
        var payload = [_]u8{0} ** 28;
        mavlink.framing.writeU32LE(payload[0..4], 100);
        mavlink.framing.writeF32LE(payload[4..8], options.roll);
        mavlink.framing.writeF32LE(payload[8..12], options.pitch);
        mavlink.framing.writeF32LE(payload[12..16], options.yaw);
        mavlink.framing.writeF32LE(payload[16..20], options.rollspeed);
        mavlink.framing.writeF32LE(payload[20..24], options.pitchspeed);
        mavlink.framing.writeF32LE(payload[24..28], options.yawspeed);
        return self.encode(mavlink.dialect.ATTITUDE, &payload);
    }

    pub fn sysStatusFrame(self: *FakePx4Adapter, options: BatteryOptions) ![]u8 {
        var payload = [_]u8{0} ** 31;
        mavlink.framing.writeU16LE(payload[14..16], options.voltage_mv);
        mavlink.framing.writeI16LE(payload[16..18], options.current_ca);
        payload[30] = @bitCast(options.percent_remaining);
        return self.encode(mavlink.dialect.SYS_STATUS, &payload);
    }

    pub fn batteryStatusFrame(self: *FakePx4Adapter, options: BatteryOptions) ![]u8 {
        var payload = [_]u8{0} ** 36;
        payload[0] = 0;
        mavlink.framing.writeU16LE(payload[10..12], options.voltage_mv);
        mavlink.framing.writeI16LE(payload[30..32], options.current_ca);
        payload[35] = @bitCast(options.percent_remaining);
        return self.encode(mavlink.dialect.BATTERY_STATUS, &payload);
    }

    pub fn commandFrame(self: *FakePx4Adapter, options: CommandOptions) ![]u8 {
        return switch (options.action) {
            .arm => mavlink.fake_transport.frameCommandLongV2(self.allocator, self.fakeHeader(), mavlink.commands.MAV_CMD_COMPONENT_ARM_DISARM, 1, .{ .target_system = 1, .target_component = 1 }),
            .disarm => mavlink.fake_transport.frameCommandLongV2(self.allocator, self.fakeHeader(), mavlink.commands.MAV_CMD_COMPONENT_ARM_DISARM, 0, .{ .target_system = 1, .target_component = 1 }),
            .takeoff => mavlink.fake_transport.frameCommandLongV2(self.allocator, self.fakeHeader(), mavlink.commands.MAV_CMD_NAV_TAKEOFF, 0, .{ .param7 = options.alt_m, .target_system = 1, .target_component = 1 }),
            .land => mavlink.fake_transport.frameCommandLongV2(self.allocator, self.fakeHeader(), mavlink.commands.MAV_CMD_NAV_LAND, 0, .{ .target_system = 1, .target_component = 1 }),
            .return_to_home => mavlink.fake_transport.frameCommandLongV2(self.allocator, self.fakeHeader(), mavlink.commands.MAV_CMD_NAV_RETURN_TO_LAUNCH, 0, .{ .target_system = 1, .target_component = 1 }),
            .hold => mavlink.fake_transport.frameCommandLongV2(self.allocator, self.fakeHeader(), mavlink.commands.MAV_CMD_NAV_LOITER_UNLIM, 0, .{ .target_system = 1, .target_component = 1 }),
            .disable_failsafe => mavlink.fake_transport.frameParamSetV2(self.allocator, self.fakeHeader(), "COM_FAIL_ACT", 0),
            .disable_geofence => mavlink.fake_transport.frameParamSetV2(self.allocator, self.fakeHeader(), "GF_ACTION", 0),
            .raw_actuator_output => mavlink.fake_transport.frameCommandLongV2(self.allocator, self.fakeHeader(), mavlink.commands.MAV_CMD_DO_SET_SERVO, 0, .{ .param1 = 1, .param2 = 1500, .target_system = 1, .target_component = 1 }),
            .start_mission => mavlink.fake_transport.frameCommandLongV2(self.allocator, self.fakeHeader(), mavlink.commands.MAV_CMD_MISSION_START, 0, .{ .target_system = 1, .target_component = 1 }),
            .set_mode => mavlink.fake_transport.frameCommandLongV2(self.allocator, self.fakeHeader(), mavlink.commands.MAV_CMD_DO_SET_MODE, 0, .{ .param1 = 0x80, .param2 = 0, .target_system = 1, .target_component = 1 }),
            .set_waypoint => mavlink.fake_transport.frameSetPositionTargetGlobalIntV2(self.allocator, self.fakeHeader(), .{
                .target_system = 1,
                .target_component = 1,
                .lat_int = options.lat_int,
                .lon_int = options.lon_int,
                .alt_m = options.alt_m,
                .type_mask = mavlink.messages.position_mask_velocity_ignored,
                .coordinate_frame = mavlink.messages.MAV_FRAME_GLOBAL_INT,
            }),
            .set_velocity => mavlink.fake_transport.frameSetPositionTargetGlobalIntV2(self.allocator, self.fakeHeader(), .{
                .target_system = 1,
                .target_component = 1,
                .lat_int = options.lat_int,
                .lon_int = options.lon_int,
                .alt_m = options.alt_m,
                .vx = options.vx,
                .vy = options.vy,
                .vz = options.vz,
                .type_mask = mavlink.messages.position_mask_position_ignored,
                .coordinate_frame = mavlink.messages.MAV_FRAME_GLOBAL_INT,
            }),
            .unknown => mavlink.fake_transport.frameCommandLongV2(self.allocator, self.fakeHeader(), 65_000, 0, .{ .target_system = 1, .target_component = 1 }),
        };
    }

    pub fn missionWaypointFrame(self: *FakePx4Adapter, lat_int: i32, lon_int: i32, alt_m: f32) ![]u8 {
        return mavlink.fake_transport.frameMissionItemIntV2(self.allocator, self.fakeHeader(), .{
            .seq = 0,
            .command = mavlink.commands.MAV_CMD_NAV_WAYPOINT,
            .frame = mavlink.messages.MAV_FRAME_GLOBAL_INT,
            .x = lat_int,
            .y = lon_int,
            .z = alt_m,
        });
    }

    pub fn ackFrame(self: *FakePx4Adapter, command: u16, result: u8) ![]u8 {
        var payload = [_]u8{0} ** 10;
        mavlink.framing.writeU16LE(payload[0..2], command);
        payload[2] = result;
        return self.encode(mavlink.dialect.COMMAND_ACK, &payload);
    }

    fn encode(self: *FakePx4Adapter, msgid: u32, payload: []const u8) ![]u8 {
        return mavlink.framing.encodeV2(self.allocator, self.header(), msgid, payload, null);
    }

    fn header(self: *FakePx4Adapter) mavlink.framing.Header {
        const seq = self.seq;
        self.seq +%= 1;
        return .{ .seq = seq, .sysid = self.options.sysid, .compid = self.options.compid };
    }

    fn fakeHeader(self: *FakePx4Adapter) mavlink.fake_transport.HeaderOptions {
        const seq = self.seq;
        self.seq +%= 1;
        return .{ .seq = seq, .sysid = self.options.sysid, .compid = self.options.compid };
    }
};

pub fn actionFromName(value: []const u8) !CommandAction {
    return std.meta.stringToEnum(CommandAction, value) orelse error.UnknownPx4FixtureCommand;
}

pub fn provenanceName() []const u8 {
    return @tagName(domain.state.StateProvenance.fake_adapter);
}
