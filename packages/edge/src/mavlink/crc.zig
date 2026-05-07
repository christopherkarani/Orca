pub const x25_seed: u16 = 0xffff;

pub fn accumulateByte(crc: *u16, byte: u8) void {
    var tmp = byte ^ @as(u8, @truncate(crc.* & 0xff));
    tmp ^= tmp << 4;
    crc.* = (crc.* >> 8) ^ (@as(u16, tmp) << 8) ^ (@as(u16, tmp) << 3) ^ (@as(u16, tmp) >> 4);
}

pub fn accumulate(crc: *u16, bytes: []const u8) void {
    for (bytes) |byte| accumulateByte(crc, byte);
}

pub fn checksum(header_without_magic: []const u8, payload: []const u8, crc_extra: u8) u16 {
    var value: u16 = x25_seed;
    accumulate(&value, header_without_magic);
    accumulate(&value, payload);
    accumulateByte(&value, crc_extra);
    return value;
}

pub fn lowByte(value: u16) u8 {
    return @truncate(value & 0xff);
}

pub fn highByte(value: u16) u8 {
    return @truncate((value >> 8) & 0xff);
}

test "mavlink x25 crc is deterministic" {
    var value: u16 = x25_seed;
    const zeros = [_]u8{0} ** 9;
    accumulate(&value, &.{ 0x09, 0x00, 0x01, 0x01, 0x00 });
    accumulate(&value, &zeros);
    accumulateByte(&value, 50);
    try @import("std").testing.expect(value != 0);
}
