const dialect = @import("dialect.zig");
const framing = @import("framing.zig");
const messages = @import("messages.zig");

pub const MessageCategory = enum {
    telemetry_state,
    command_control,
    mission_protocol,
    safety_configuration,
    acknowledgement,
    unknown,
};

pub const Classification = struct {
    message_id: u32,
    message_name: []const u8,
    category: MessageCategory,
    known: bool,
    safety_sensitive: bool,
    command_id: ?u16 = null,
};

pub fn classifyFrame(frame: framing.Frame) !Classification {
    const decoded = try messages.decode(frame);
    var command_id: ?u16 = null;
    switch (decoded) {
        .command_long => |m| command_id = m.command,
        .command_int => |m| command_id = m.command,
        .mission_item => |m| command_id = m.command,
        .mission_item_int => |m| command_id = m.command,
        else => {},
    }
    const category: MessageCategory = switch (frame.msgid) {
        dialect.HEARTBEAT,
        dialect.SYS_STATUS,
        dialect.GPS_RAW_INT,
        dialect.GLOBAL_POSITION_INT,
        dialect.LOCAL_POSITION_NED,
        dialect.ATTITUDE,
        dialect.BATTERY_STATUS,
        => .telemetry_state,
        dialect.COMMAND_LONG,
        dialect.COMMAND_INT,
        dialect.SET_MODE,
        dialect.SET_POSITION_TARGET_GLOBAL_INT,
        dialect.SET_POSITION_TARGET_LOCAL_NED,
        => .command_control,
        dialect.PARAM_SET => .safety_configuration,
        dialect.MISSION_COUNT,
        dialect.MISSION_ITEM,
        dialect.MISSION_ITEM_INT,
        dialect.MISSION_REQUEST,
        dialect.MISSION_REQUEST_INT,
        dialect.MISSION_ACK,
        dialect.MISSION_CLEAR_ALL,
        dialect.MISSION_SET_CURRENT,
        dialect.MISSION_CURRENT,
        => .mission_protocol,
        dialect.COMMAND_ACK => .acknowledgement,
        else => .unknown,
    };
    return .{
        .message_id = frame.msgid,
        .message_name = dialect.nameFor(frame.msgid),
        .category = category,
        .known = dialect.metaFor(frame.msgid) != null,
        .safety_sensitive = category == .command_control or category == .safety_configuration or category == .mission_protocol,
        .command_id = command_id,
    };
}
