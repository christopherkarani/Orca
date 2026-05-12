const std = @import("std");

const commands = @import("commands.zig");
const dialect = @import("dialect.zig");
const framing = @import("framing.zig");
const messages = @import("messages.zig");

pub const HeaderOptions = struct {
    seq: u8 = 0,
    sysid: u8 = 1,
    compid: u8 = 1,
};

pub const CommandLongOverrides = struct {
    param1: ?f32 = null,
    param2: f32 = 0,
    param3: f32 = 0,
    param4: f32 = 0,
    param5: f32 = 0,
    param6: f32 = 0,
    param7: f32 = 0,
    target_system: u8 = 1,
    target_component: u8 = 1,
};

pub const GlobalSetpoint = struct {
    target_system: u8 = 1,
    target_component: u8 = 1,
    lat_int: i32,
    lon_int: i32,
    alt_m: f32,
    vx: f32 = 0,
    vy: f32 = 0,
    vz: f32 = 0,
    type_mask: u16 = messages.position_mask_velocity_ignored,
    coordinate_frame: u8 = messages.MAV_FRAME_GLOBAL_INT,
};

pub const MissionItemInt = struct {
    target_system: u8 = 1,
    target_component: u8 = 1,
    seq: u16,
    command: u16 = commands.MAV_CMD_NAV_WAYPOINT,
    frame: u8 = messages.MAV_FRAME_GLOBAL_INT,
    x: i32,
    y: i32,
    z: f32,
};

pub const MissionItem = struct {
    target_system: u8 = 1,
    target_component: u8 = 1,
    seq: u16,
    command: u16 = commands.MAV_CMD_NAV_WAYPOINT,
    frame: u8 = messages.MAV_FRAME_GLOBAL,
    x: f32,
    y: f32,
    z: f32,
};

pub const FakeTransport = struct {
    allocator: std.mem.Allocator,
    forwarded: std.ArrayList([]u8) = .empty,
    blocked: std.ArrayList([]u8) = .empty,

    pub fn init(allocator: std.mem.Allocator) FakeTransport {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *FakeTransport) void {
        for (self.forwarded.items) |bytes| self.allocator.free(bytes);
        for (self.blocked.items) |bytes| self.allocator.free(bytes);
        self.forwarded.deinit(self.allocator);
        self.blocked.deinit(self.allocator);
    }

    pub fn recordForwarded(self: *FakeTransport, frame: framing.Frame) !void {
        try self.forwarded.append(self.allocator, try self.allocator.dupe(u8, frame.bytes));
    }

    pub fn recordBlocked(self: *FakeTransport, frame: framing.Frame) !void {
        try self.blocked.append(self.allocator, try self.allocator.dupe(u8, frame.bytes));
    }
};

pub fn frameHeartbeatV1(allocator: std.mem.Allocator, header: HeaderOptions) ![]u8 {
    var payload = [_]u8{0} ** 9;
    payload[4] = 2;
    payload[5] = 12;
    payload[6] = 0;
    payload[7] = 4;
    payload[8] = 3;
    return framing.encodeV1(allocator, toHeader(header), @intCast(dialect.HEARTBEAT), &payload);
}

pub fn frameSignedHeartbeatV2(allocator: std.mem.Allocator, header: HeaderOptions) ![]u8 {
    var payload = [_]u8{0} ** 9;
    payload[4] = 2;
    payload[5] = 12;
    payload[8] = 3;
    const signature = [_]u8{ 7, 1, 2, 3, 4, 5, 6, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff };
    return framing.encodeV2(allocator, toHeader(header), dialect.HEARTBEAT, &payload, &signature);
}

pub fn frameCommandLongV2(allocator: std.mem.Allocator, header: HeaderOptions, command: u16, param1: f32, overrides: CommandLongOverrides) ![]u8 {
    var payload = [_]u8{0} ** 33;
    framing.writeF32LE(payload[0..4], overrides.param1 orelse param1);
    framing.writeF32LE(payload[4..8], overrides.param2);
    framing.writeF32LE(payload[8..12], overrides.param3);
    framing.writeF32LE(payload[12..16], overrides.param4);
    framing.writeF32LE(payload[16..20], overrides.param5);
    framing.writeF32LE(payload[20..24], overrides.param6);
    framing.writeF32LE(payload[24..28], overrides.param7);
    framing.writeU16LE(payload[28..30], command);
    payload[30] = overrides.target_system;
    payload[31] = overrides.target_component;
    payload[32] = 0;
    return framing.encodeV2(allocator, toHeader(header), dialect.COMMAND_LONG, &payload, null);
}

pub fn frameParamSetV2(allocator: std.mem.Allocator, header: HeaderOptions, param_id: []const u8, value: f32) ![]u8 {
    var payload = [_]u8{0} ** 23;
    framing.writeF32LE(payload[0..4], value);
    payload[4] = 1;
    payload[5] = 1;
    const n = @min(param_id.len, 16);
    @memcpy(payload[6 .. 6 + n], param_id[0..n]);
    payload[22] = 9;
    return framing.encodeV2(allocator, toHeader(header), dialect.PARAM_SET, &payload, null);
}

pub fn frameSetPositionTargetGlobalIntV2(allocator: std.mem.Allocator, header: HeaderOptions, setpoint: GlobalSetpoint) ![]u8 {
    var payload = [_]u8{0} ** 53;
    framing.writeU32LE(payload[0..4], 100);
    framing.writeI32LE(payload[4..8], setpoint.lat_int);
    framing.writeI32LE(payload[8..12], setpoint.lon_int);
    framing.writeF32LE(payload[12..16], setpoint.alt_m);
    framing.writeF32LE(payload[16..20], setpoint.vx);
    framing.writeF32LE(payload[20..24], setpoint.vy);
    framing.writeF32LE(payload[24..28], setpoint.vz);
    framing.writeU16LE(payload[48..50], setpoint.type_mask);
    payload[50] = setpoint.target_system;
    payload[51] = setpoint.target_component;
    payload[52] = setpoint.coordinate_frame;
    return framing.encodeV2(allocator, toHeader(header), dialect.SET_POSITION_TARGET_GLOBAL_INT, &payload, null);
}

pub fn frameMissionCountV2(allocator: std.mem.Allocator, header: HeaderOptions, count: u16) ![]u8 {
    var payload = [_]u8{0} ** 9;
    framing.writeU16LE(payload[0..2], count);
    payload[2] = 1;
    payload[3] = 1;
    payload[4] = 0;
    return framing.encodeV2(allocator, toHeader(header), dialect.MISSION_COUNT, &payload, null);
}

pub fn frameMissionItemIntV2(allocator: std.mem.Allocator, header: HeaderOptions, item: MissionItemInt) ![]u8 {
    var payload = [_]u8{0} ** 38;
    framing.writeI32LE(payload[16..20], item.x);
    framing.writeI32LE(payload[20..24], item.y);
    framing.writeF32LE(payload[24..28], item.z);
    framing.writeU16LE(payload[28..30], item.seq);
    framing.writeU16LE(payload[30..32], item.command);
    payload[32] = item.target_system;
    payload[33] = item.target_component;
    payload[34] = item.frame;
    payload[35] = 0;
    payload[36] = 1;
    payload[37] = 0;
    return framing.encodeV2(allocator, toHeader(header), dialect.MISSION_ITEM_INT, &payload, null);
}

pub fn frameMissionItemV2(allocator: std.mem.Allocator, header: HeaderOptions, item: MissionItem) ![]u8 {
    var payload = [_]u8{0} ** 38;
    framing.writeF32LE(payload[16..20], item.x);
    framing.writeF32LE(payload[20..24], item.y);
    framing.writeF32LE(payload[24..28], item.z);
    framing.writeU16LE(payload[28..30], item.seq);
    framing.writeU16LE(payload[30..32], item.command);
    payload[32] = item.target_system;
    payload[33] = item.target_component;
    payload[34] = item.frame;
    payload[35] = 0;
    payload[36] = 1;
    payload[37] = 0;
    return framing.encodeV2(allocator, toHeader(header), dialect.MISSION_ITEM, &payload, null);
}

pub fn toHexAlloc(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const out = try allocator.alloc(u8, bytes.len * 2);
    const alphabet = "0123456789abcdef";
    for (bytes, 0..) |byte, index| {
        out[index * 2] = alphabet[byte >> 4];
        out[index * 2 + 1] = alphabet[byte & 0x0f];
    }
    return out;
}

fn toHeader(options: HeaderOptions) framing.Header {
    return .{ .seq = options.seq, .sysid = options.sysid, .compid = options.compid };
}
