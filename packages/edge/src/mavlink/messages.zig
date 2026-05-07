const std = @import("std");

const dialect = @import("dialect.zig");
const framing = @import("framing.zig");

pub const MAV_FRAME_GLOBAL: u8 = 0;
pub const MAV_FRAME_GLOBAL_RELATIVE_ALT: u8 = 3;
pub const MAV_FRAME_GLOBAL_INT: u8 = 5;
pub const MAV_FRAME_GLOBAL_RELATIVE_ALT_INT: u8 = 6;
pub const MAV_FRAME_GLOBAL_TERRAIN_ALT: u8 = 10;
pub const MAV_FRAME_GLOBAL_TERRAIN_ALT_INT: u8 = 11;
pub const MAV_FRAME_LOCAL_NED: u8 = 1;

pub const position_mask_velocity_ignored: u16 = (1 << 3) | (1 << 4) | (1 << 5) | (1 << 6) | (1 << 7) | (1 << 8) | (1 << 10) | (1 << 11);
pub const position_mask_position_ignored: u16 = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 6) | (1 << 7) | (1 << 8) | (1 << 10) | (1 << 11);

pub const Heartbeat = struct {
    vehicle_type: u8,
    autopilot: u8,
    base_mode: u8,
    system_status: u8,
};

pub const CommandLong = struct {
    params: [7]f32,
    command: u16,
    target_system: u8,
    target_component: u8,
    confirmation: u8,
};

pub const CommandInt = struct {
    params: [4]f32,
    x: i32,
    y: i32,
    z: f32,
    command: u16,
    target_system: u8,
    target_component: u8,
    frame: u8,
    current: u8,
    autocontinue: u8,
};

pub const SetMode = struct {
    custom_mode: u32,
    target_system: u8,
    base_mode: u8,
};

pub const ParamSet = struct {
    param_value: f32,
    target_system: u8,
    target_component: u8,
    param_id: [16]u8,
    param_type: u8,

    pub fn idSlice(self: *const ParamSet) []const u8 {
        var end: usize = 0;
        while (end < self.param_id.len and self.param_id[end] != 0) : (end += 1) {}
        return self.param_id[0..end];
    }
};

pub const SetPositionTargetGlobalInt = struct {
    time_boot_ms: u32,
    lat_int: i32,
    lon_int: i32,
    alt_m: f32,
    vx: f32,
    vy: f32,
    vz: f32,
    type_mask: u16,
    target_system: u8,
    target_component: u8,
    coordinate_frame: u8,
};

pub const SetPositionTargetLocalNed = struct {
    time_boot_ms: u32,
    x: f32,
    y: f32,
    z: f32,
    vx: f32,
    vy: f32,
    vz: f32,
    type_mask: u16,
    target_system: u8,
    target_component: u8,
    coordinate_frame: u8,
};

pub const MissionCount = struct {
    target_system: u8,
    target_component: u8,
    count: u16,
    mission_type: u8 = 0,
};

pub const MissionItemInt = struct {
    params: [4]f32,
    x: i32,
    y: i32,
    z: f32,
    seq: u16,
    command: u16,
    target_system: u8,
    target_component: u8,
    frame: u8,
    current: u8,
    autocontinue: u8,
    mission_type: u8 = 0,
};

pub const MissionItem = struct {
    params: [4]f32,
    x: f32,
    y: f32,
    z: f32,
    seq: u16,
    command: u16,
    target_system: u8,
    target_component: u8,
    frame: u8,
    current: u8,
    autocontinue: u8,
    mission_type: u8 = 0,
};

pub const MissionAck = struct {
    target_system: u8,
    target_component: u8,
    ack_type: u8,
    mission_type: u8 = 0,
};

pub const MissionClearAll = struct {
    target_system: u8,
    target_component: u8,
    mission_type: u8 = 0,
};

pub const MissionSetCurrent = struct {
    target_system: u8,
    target_component: u8,
    seq: u16,
};

pub const MissionCurrent = struct {
    seq: u16,
};

pub const SupportedMessage = union(enum) {
    heartbeat: Heartbeat,
    command_long: CommandLong,
    command_int: CommandInt,
    set_mode: SetMode,
    param_set: ParamSet,
    set_position_target_global_int: SetPositionTargetGlobalInt,
    set_position_target_local_ned: SetPositionTargetLocalNed,
    mission_count: MissionCount,
    mission_item: MissionItem,
    mission_item_int: MissionItemInt,
    mission_ack: MissionAck,
    mission_clear_all: MissionClearAll,
    mission_set_current: MissionSetCurrent,
    mission_current: MissionCurrent,
    telemetry_state,
    unknown,
};

pub fn decode(frame: framing.Frame) !SupportedMessage {
    const p = frame.payload;
    return switch (frame.msgid) {
        dialect.HEARTBEAT => .{ .heartbeat = .{ .vehicle_type = p[4], .autopilot = p[5], .base_mode = p[6], .system_status = p[7] } },
        dialect.SYS_STATUS,
        dialect.GPS_RAW_INT,
        dialect.GLOBAL_POSITION_INT,
        dialect.LOCAL_POSITION_NED,
        dialect.ATTITUDE,
        dialect.BATTERY_STATUS,
        => .telemetry_state,
        dialect.COMMAND_LONG => .{ .command_long = decodeCommandLong(p) },
        dialect.COMMAND_INT => .{ .command_int = decodeCommandInt(p) },
        dialect.SET_MODE => .{ .set_mode = .{ .custom_mode = framing.readU32LE(p[0..4]), .target_system = p[4], .base_mode = p[5] } },
        dialect.PARAM_SET => .{ .param_set = decodeParamSet(p) },
        dialect.SET_POSITION_TARGET_GLOBAL_INT => .{ .set_position_target_global_int = decodeGlobalSetpoint(p) },
        dialect.SET_POSITION_TARGET_LOCAL_NED => .{ .set_position_target_local_ned = decodeLocalSetpoint(p) },
        dialect.MISSION_COUNT => .{ .mission_count = .{ .target_system = p[2], .target_component = p[3], .count = framing.readU16LE(p[0..2]), .mission_type = if (p.len > 4) p[4] else 0 } },
        dialect.MISSION_ITEM => .{ .mission_item = decodeMissionItem(p) },
        dialect.MISSION_ITEM_INT => .{ .mission_item_int = decodeMissionItemInt(p) },
        dialect.MISSION_ACK => .{ .mission_ack = .{ .target_system = p[0], .target_component = p[1], .ack_type = p[2], .mission_type = if (p.len > 3) p[3] else 0 } },
        dialect.MISSION_CLEAR_ALL => .{ .mission_clear_all = .{ .target_system = p[0], .target_component = p[1], .mission_type = if (p.len > 2) p[2] else 0 } },
        dialect.MISSION_SET_CURRENT => .{ .mission_set_current = .{ .target_system = p[2], .target_component = p[3], .seq = framing.readU16LE(p[0..2]) } },
        dialect.MISSION_CURRENT => .{ .mission_current = .{ .seq = framing.readU16LE(p[0..2]) } },
        else => .unknown,
    };
}

pub fn targetSystem(frame: framing.Frame) ?u8 {
    const message = decode(frame) catch return null;
    return switch (message) {
        .command_long => |m| m.target_system,
        .command_int => |m| m.target_system,
        .set_mode => |m| m.target_system,
        .param_set => |m| m.target_system,
        .set_position_target_global_int => |m| m.target_system,
        .set_position_target_local_ned => |m| m.target_system,
        .mission_count => |m| m.target_system,
        .mission_item => |m| m.target_system,
        .mission_item_int => |m| m.target_system,
        .mission_ack => |m| m.target_system,
        .mission_clear_all => |m| m.target_system,
        .mission_set_current => |m| m.target_system,
        else => null,
    };
}

pub fn targetComponent(frame: framing.Frame) ?u8 {
    const message = decode(frame) catch return null;
    return switch (message) {
        .command_long => |m| m.target_component,
        .command_int => |m| m.target_component,
        .param_set => |m| m.target_component,
        .set_position_target_global_int => |m| m.target_component,
        .set_position_target_local_ned => |m| m.target_component,
        .mission_count => |m| m.target_component,
        .mission_item => |m| m.target_component,
        .mission_item_int => |m| m.target_component,
        .mission_ack => |m| m.target_component,
        .mission_clear_all => |m| m.target_component,
        .mission_set_current => |m| m.target_component,
        else => null,
    };
}

pub fn positionIgnored(type_mask: u16) bool {
    return (type_mask & 0b0000_0000_0000_0111) == 0b0000_0000_0000_0111;
}

pub fn velocityIgnored(type_mask: u16) bool {
    return (type_mask & 0b0000_0000_0011_1000) == 0b0000_0000_0011_1000;
}

fn decodeCommandLong(p: []const u8) CommandLong {
    return .{
        .params = .{
            framing.readF32LE(p[0..4]),
            framing.readF32LE(p[4..8]),
            framing.readF32LE(p[8..12]),
            framing.readF32LE(p[12..16]),
            framing.readF32LE(p[16..20]),
            framing.readF32LE(p[20..24]),
            framing.readF32LE(p[24..28]),
        },
        .command = framing.readU16LE(p[28..30]),
        .target_system = p[30],
        .target_component = p[31],
        .confirmation = p[32],
    };
}

fn decodeCommandInt(p: []const u8) CommandInt {
    return .{
        .params = .{
            framing.readF32LE(p[0..4]),
            framing.readF32LE(p[4..8]),
            framing.readF32LE(p[8..12]),
            framing.readF32LE(p[12..16]),
        },
        .x = framing.readI32LE(p[16..20]),
        .y = framing.readI32LE(p[20..24]),
        .z = framing.readF32LE(p[24..28]),
        .command = framing.readU16LE(p[28..30]),
        .target_system = p[30],
        .target_component = p[31],
        .frame = p[32],
        .current = p[33],
        .autocontinue = p[34],
    };
}

fn decodeParamSet(p: []const u8) ParamSet {
    var id: [16]u8 = undefined;
    @memcpy(id[0..], p[6..22]);
    return .{
        .param_value = framing.readF32LE(p[0..4]),
        .target_system = p[4],
        .target_component = p[5],
        .param_id = id,
        .param_type = p[22],
    };
}

fn decodeGlobalSetpoint(p: []const u8) SetPositionTargetGlobalInt {
    return .{
        .time_boot_ms = framing.readU32LE(p[0..4]),
        .lat_int = framing.readI32LE(p[4..8]),
        .lon_int = framing.readI32LE(p[8..12]),
        .alt_m = framing.readF32LE(p[12..16]),
        .vx = framing.readF32LE(p[16..20]),
        .vy = framing.readF32LE(p[20..24]),
        .vz = framing.readF32LE(p[24..28]),
        .type_mask = framing.readU16LE(p[48..50]),
        .target_system = p[50],
        .target_component = p[51],
        .coordinate_frame = p[52],
    };
}

fn decodeLocalSetpoint(p: []const u8) SetPositionTargetLocalNed {
    return .{
        .time_boot_ms = framing.readU32LE(p[0..4]),
        .x = framing.readF32LE(p[4..8]),
        .y = framing.readF32LE(p[8..12]),
        .z = framing.readF32LE(p[12..16]),
        .vx = framing.readF32LE(p[16..20]),
        .vy = framing.readF32LE(p[20..24]),
        .vz = framing.readF32LE(p[24..28]),
        .type_mask = framing.readU16LE(p[48..50]),
        .target_system = p[50],
        .target_component = p[51],
        .coordinate_frame = p[52],
    };
}

fn decodeMissionItemInt(p: []const u8) MissionItemInt {
    return .{
        .params = .{
            framing.readF32LE(p[0..4]),
            framing.readF32LE(p[4..8]),
            framing.readF32LE(p[8..12]),
            framing.readF32LE(p[12..16]),
        },
        .x = framing.readI32LE(p[16..20]),
        .y = framing.readI32LE(p[20..24]),
        .z = framing.readF32LE(p[24..28]),
        .seq = framing.readU16LE(p[28..30]),
        .command = framing.readU16LE(p[30..32]),
        .target_system = p[32],
        .target_component = p[33],
        .frame = p[34],
        .current = p[35],
        .autocontinue = p[36],
        .mission_type = if (p.len > 37) p[37] else 0,
    };
}

fn decodeMissionItem(p: []const u8) MissionItem {
    return .{
        .params = .{
            framing.readF32LE(p[0..4]),
            framing.readF32LE(p[4..8]),
            framing.readF32LE(p[8..12]),
            framing.readF32LE(p[12..16]),
        },
        .x = framing.readF32LE(p[16..20]),
        .y = framing.readF32LE(p[20..24]),
        .z = framing.readF32LE(p[24..28]),
        .seq = framing.readU16LE(p[28..30]),
        .command = framing.readU16LE(p[30..32]),
        .target_system = p[32],
        .target_component = p[33],
        .frame = p[34],
        .current = p[35],
        .autocontinue = p[36],
        .mission_type = if (p.len > 37) p[37] else 0,
    };
}
