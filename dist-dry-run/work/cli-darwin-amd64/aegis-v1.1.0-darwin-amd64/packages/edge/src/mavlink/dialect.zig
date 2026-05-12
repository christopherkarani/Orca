pub const HEARTBEAT: u32 = 0;
pub const SYS_STATUS: u32 = 1;
pub const SET_MODE: u32 = 11;
pub const PARAM_SET: u32 = 23;
pub const GPS_RAW_INT: u32 = 24;
pub const ATTITUDE: u32 = 30;
pub const LOCAL_POSITION_NED: u32 = 32;
pub const GLOBAL_POSITION_INT: u32 = 33;
pub const MISSION_ITEM: u32 = 39;
pub const MISSION_REQUEST: u32 = 40;
pub const MISSION_SET_CURRENT: u32 = 41;
pub const MISSION_CURRENT: u32 = 42;
pub const MISSION_COUNT: u32 = 44;
pub const MISSION_CLEAR_ALL: u32 = 45;
pub const MISSION_ACK: u32 = 47;
pub const MISSION_REQUEST_INT: u32 = 51;
pub const MISSION_ITEM_INT: u32 = 73;
pub const COMMAND_INT: u32 = 75;
pub const COMMAND_LONG: u32 = 76;
pub const COMMAND_ACK: u32 = 77;
pub const SET_POSITION_TARGET_LOCAL_NED: u32 = 84;
pub const SET_POSITION_TARGET_GLOBAL_INT: u32 = 86;
pub const BATTERY_STATUS: u32 = 147;

pub const MessageMeta = struct {
    id: u32,
    name: []const u8,
    min_len: u8,
    max_len: u8,
    crc_extra: u8,
};

pub fn metaFor(msgid: u32) ?MessageMeta {
    return switch (msgid) {
        HEARTBEAT => .{ .id = HEARTBEAT, .name = "HEARTBEAT", .min_len = 9, .max_len = 9, .crc_extra = 50 },
        SYS_STATUS => .{ .id = SYS_STATUS, .name = "SYS_STATUS", .min_len = 31, .max_len = 43, .crc_extra = 124 },
        SET_MODE => .{ .id = SET_MODE, .name = "SET_MODE", .min_len = 6, .max_len = 6, .crc_extra = 89 },
        PARAM_SET => .{ .id = PARAM_SET, .name = "PARAM_SET", .min_len = 23, .max_len = 23, .crc_extra = 168 },
        GPS_RAW_INT => .{ .id = GPS_RAW_INT, .name = "GPS_RAW_INT", .min_len = 30, .max_len = 52, .crc_extra = 24 },
        ATTITUDE => .{ .id = ATTITUDE, .name = "ATTITUDE", .min_len = 28, .max_len = 28, .crc_extra = 39 },
        LOCAL_POSITION_NED => .{ .id = LOCAL_POSITION_NED, .name = "LOCAL_POSITION_NED", .min_len = 28, .max_len = 28, .crc_extra = 185 },
        GLOBAL_POSITION_INT => .{ .id = GLOBAL_POSITION_INT, .name = "GLOBAL_POSITION_INT", .min_len = 28, .max_len = 28, .crc_extra = 104 },
        MISSION_ITEM => .{ .id = MISSION_ITEM, .name = "MISSION_ITEM", .min_len = 37, .max_len = 38, .crc_extra = 254 },
        MISSION_REQUEST => .{ .id = MISSION_REQUEST, .name = "MISSION_REQUEST", .min_len = 4, .max_len = 5, .crc_extra = 230 },
        MISSION_SET_CURRENT => .{ .id = MISSION_SET_CURRENT, .name = "MISSION_SET_CURRENT", .min_len = 4, .max_len = 4, .crc_extra = 28 },
        MISSION_CURRENT => .{ .id = MISSION_CURRENT, .name = "MISSION_CURRENT", .min_len = 2, .max_len = 18, .crc_extra = 28 },
        MISSION_COUNT => .{ .id = MISSION_COUNT, .name = "MISSION_COUNT", .min_len = 4, .max_len = 9, .crc_extra = 221 },
        MISSION_CLEAR_ALL => .{ .id = MISSION_CLEAR_ALL, .name = "MISSION_CLEAR_ALL", .min_len = 2, .max_len = 3, .crc_extra = 232 },
        MISSION_ACK => .{ .id = MISSION_ACK, .name = "MISSION_ACK", .min_len = 3, .max_len = 8, .crc_extra = 153 },
        MISSION_REQUEST_INT => .{ .id = MISSION_REQUEST_INT, .name = "MISSION_REQUEST_INT", .min_len = 4, .max_len = 5, .crc_extra = 196 },
        MISSION_ITEM_INT => .{ .id = MISSION_ITEM_INT, .name = "MISSION_ITEM_INT", .min_len = 37, .max_len = 38, .crc_extra = 38 },
        COMMAND_INT => .{ .id = COMMAND_INT, .name = "COMMAND_INT", .min_len = 35, .max_len = 35, .crc_extra = 158 },
        COMMAND_LONG => .{ .id = COMMAND_LONG, .name = "COMMAND_LONG", .min_len = 33, .max_len = 33, .crc_extra = 152 },
        COMMAND_ACK => .{ .id = COMMAND_ACK, .name = "COMMAND_ACK", .min_len = 3, .max_len = 10, .crc_extra = 143 },
        SET_POSITION_TARGET_LOCAL_NED => .{ .id = SET_POSITION_TARGET_LOCAL_NED, .name = "SET_POSITION_TARGET_LOCAL_NED", .min_len = 53, .max_len = 53, .crc_extra = 143 },
        SET_POSITION_TARGET_GLOBAL_INT => .{ .id = SET_POSITION_TARGET_GLOBAL_INT, .name = "SET_POSITION_TARGET_GLOBAL_INT", .min_len = 53, .max_len = 53, .crc_extra = 5 },
        BATTERY_STATUS => .{ .id = BATTERY_STATUS, .name = "BATTERY_STATUS", .min_len = 36, .max_len = 54, .crc_extra = 154 },
        else => null,
    };
}

pub fn nameFor(msgid: u32) []const u8 {
    if (metaFor(msgid)) |meta| return meta.name;
    return "UNKNOWN";
}

pub fn isMission(msgid: u32) bool {
    return switch (msgid) {
        MISSION_COUNT,
        MISSION_ITEM,
        MISSION_ITEM_INT,
        MISSION_REQUEST,
        MISSION_REQUEST_INT,
        MISSION_ACK,
        MISSION_CLEAR_ALL,
        MISSION_SET_CURRENT,
        MISSION_CURRENT,
        => true,
        else => false,
    };
}
