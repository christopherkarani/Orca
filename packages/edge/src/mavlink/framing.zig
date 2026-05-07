const std = @import("std");

const crc = @import("crc.zig");
const dialect = @import("dialect.zig");

pub const magic_v1: u8 = 0xfe;
pub const magic_v2: u8 = 0xfd;
pub const mavlink2_signed_flag: u8 = 0x01;
pub const max_payload_len: usize = 255;
pub const mavlink2_signature_len: usize = 13;
pub const max_frame_len: usize = 10 + max_payload_len + 2 + mavlink2_signature_len;

pub const Version = enum { v1, v2 };

pub const Frame = struct {
    version: Version,
    bytes: []const u8,
    payload: []const u8,
    sequence: u8,
    sysid: u8,
    compid: u8,
    msgid: u32,
    incompat_flags: u8 = 0,
    compat_flags: u8 = 0,
    checksum: u16,
    checksum_valid: ?bool,
    signature_present: bool = false,
    signature: ?[]const u8 = null,

    pub fn targetSystem(self: Frame) ?u8 {
        return @import("messages.zig").targetSystem(self);
    }

    pub fn targetComponent(self: Frame) ?u8 {
        return @import("messages.zig").targetComponent(self);
    }
};

pub fn isMagic(byte: u8) bool {
    return byte == magic_v1 or byte == magic_v2;
}

pub fn frameTotalLengthPrefix(input: []const u8) !usize {
    if (input.len == 0) return error.TruncatedFrame;
    return switch (input[0]) {
        magic_v1 => {
            if (input.len < 2) return error.TruncatedFrame;
            const len = input[1];
            return 8 + @as(usize, len);
        },
        magic_v2 => {
            if (input.len < 3) return error.TruncatedFrame;
            const len = input[1];
            const signature_len: usize = if ((input[2] & mavlink2_signed_flag) != 0) mavlink2_signature_len else 0;
            return 10 + @as(usize, len) + 2 + signature_len;
        },
        else => error.InvalidMagic,
    };
}

pub fn parseFrame(input: []const u8) !Frame {
    if (input.len > max_frame_len) return error.OversizedFrame;
    if (input.len == 0) return error.TruncatedFrame;
    const total = try frameTotalLengthPrefix(input);
    if (total > max_frame_len) return error.OversizedFrame;
    if (input.len < total) return error.TruncatedFrame;
    if (input.len != total) return error.ExtraBytes;

    return switch (input[0]) {
        magic_v1 => parseV1(input),
        magic_v2 => parseV2(input),
        else => error.InvalidMagic,
    };
}

fn parseV1(input: []const u8) !Frame {
    if (input.len < 8) return error.TruncatedFrame;
    const payload_len: usize = input[1];
    if (payload_len > max_payload_len) return error.OversizedFrame;
    const payload = input[6 .. 6 + payload_len];
    const msgid = input[5];
    const checksum_offset = 6 + payload_len;
    const received = readU16LE(input[checksum_offset .. checksum_offset + 2]);
    const valid = try validateChecksum(input[1..6], payload, msgid, received);
    return .{
        .version = .v1,
        .bytes = input,
        .payload = payload,
        .sequence = input[2],
        .sysid = input[3],
        .compid = input[4],
        .msgid = msgid,
        .checksum = received,
        .checksum_valid = valid,
    };
}

fn parseV2(input: []const u8) !Frame {
    if (input.len < 12) return error.TruncatedFrame;
    const payload_len: usize = input[1];
    if (payload_len > max_payload_len) return error.OversizedFrame;
    const signature_present = (input[2] & mavlink2_signed_flag) != 0;
    const payload = input[10 .. 10 + payload_len];
    const msgid = readU24LE(input[7..10]);
    const checksum_offset = 10 + payload_len;
    const received = readU16LE(input[checksum_offset .. checksum_offset + 2]);
    const valid = try validateChecksum(input[1..10], payload, msgid, received);
    const signature = if (signature_present) input[checksum_offset + 2 .. checksum_offset + 2 + mavlink2_signature_len] else null;
    return .{
        .version = .v2,
        .bytes = input,
        .payload = payload,
        .sequence = input[4],
        .sysid = input[5],
        .compid = input[6],
        .msgid = msgid,
        .incompat_flags = input[2],
        .compat_flags = input[3],
        .checksum = received,
        .checksum_valid = valid,
        .signature_present = signature_present,
        .signature = signature,
    };
}

fn validateChecksum(header_without_magic: []const u8, payload: []const u8, msgid: u32, received: u16) !?bool {
    const meta = dialect.metaFor(msgid) orelse return null;
    if (payload.len < meta.min_len or payload.len > meta.max_len) return error.InvalidPayloadLength;
    const computed = crc.checksum(header_without_magic, payload, meta.crc_extra);
    if (computed != received) return error.InvalidChecksum;
    return true;
}

pub const Header = struct {
    seq: u8,
    sysid: u8,
    compid: u8,
    incompat_flags: u8 = 0,
    compat_flags: u8 = 0,
};

pub fn encodeV1(allocator: std.mem.Allocator, header: Header, msgid: u8, payload: []const u8) ![]u8 {
    if (payload.len > max_payload_len) return error.OversizedFrame;
    const meta = dialect.metaFor(msgid) orelse return error.UnsupportedMessage;
    var out = try allocator.alloc(u8, 8 + payload.len);
    errdefer allocator.free(out);
    out[0] = magic_v1;
    out[1] = @intCast(payload.len);
    out[2] = header.seq;
    out[3] = header.sysid;
    out[4] = header.compid;
    out[5] = msgid;
    @memcpy(out[6 .. 6 + payload.len], payload);
    const sum = crc.checksum(out[1..6], payload, meta.crc_extra);
    out[6 + payload.len] = crc.lowByte(sum);
    out[7 + payload.len] = crc.highByte(sum);
    return out;
}

pub fn encodeV2(allocator: std.mem.Allocator, header: Header, msgid: u32, payload: []const u8, signature: ?[]const u8) ![]u8 {
    if (payload.len > max_payload_len) return error.OversizedFrame;
    const meta = dialect.metaFor(msgid) orelse return error.UnsupportedMessage;
    const sig_len: usize = if (signature) |sig| blk: {
        if (sig.len != mavlink2_signature_len) return error.InvalidSignatureLength;
        break :blk mavlink2_signature_len;
    } else 0;
    var out = try allocator.alloc(u8, 12 + payload.len + sig_len);
    errdefer allocator.free(out);
    out[0] = magic_v2;
    out[1] = @intCast(payload.len);
    out[2] = if (sig_len > 0) header.incompat_flags | mavlink2_signed_flag else header.incompat_flags;
    out[3] = header.compat_flags;
    out[4] = header.seq;
    out[5] = header.sysid;
    out[6] = header.compid;
    writeU24LE(out[7..10], msgid);
    @memcpy(out[10 .. 10 + payload.len], payload);
    const sum = crc.checksum(out[1..10], payload, meta.crc_extra);
    out[10 + payload.len] = crc.lowByte(sum);
    out[11 + payload.len] = crc.highByte(sum);
    if (signature) |sig| @memcpy(out[12 + payload.len ..], sig);
    return out;
}

pub fn readU16LE(bytes: []const u8) u16 {
    return @as(u16, bytes[0]) | (@as(u16, bytes[1]) << 8);
}

pub fn readI16LE(bytes: []const u8) i16 {
    return @bitCast(readU16LE(bytes));
}

pub fn readU24LE(bytes: []const u8) u32 {
    return @as(u32, bytes[0]) | (@as(u32, bytes[1]) << 8) | (@as(u32, bytes[2]) << 16);
}

pub fn readU32LE(bytes: []const u8) u32 {
    return @as(u32, bytes[0]) | (@as(u32, bytes[1]) << 8) | (@as(u32, bytes[2]) << 16) | (@as(u32, bytes[3]) << 24);
}

pub fn readI32LE(bytes: []const u8) i32 {
    return @bitCast(readU32LE(bytes));
}

pub fn readF32LE(bytes: []const u8) f32 {
    return @bitCast(readU32LE(bytes));
}

pub fn writeU16LE(bytes: []u8, value: u16) void {
    bytes[0] = @truncate(value & 0xff);
    bytes[1] = @truncate((value >> 8) & 0xff);
}

pub fn writeI16LE(bytes: []u8, value: i16) void {
    writeU16LE(bytes, @bitCast(value));
}

pub fn writeU24LE(bytes: []u8, value: u32) void {
    bytes[0] = @truncate(value & 0xff);
    bytes[1] = @truncate((value >> 8) & 0xff);
    bytes[2] = @truncate((value >> 16) & 0xff);
}

pub fn writeU32LE(bytes: []u8, value: u32) void {
    bytes[0] = @truncate(value & 0xff);
    bytes[1] = @truncate((value >> 8) & 0xff);
    bytes[2] = @truncate((value >> 16) & 0xff);
    bytes[3] = @truncate((value >> 24) & 0xff);
}

pub fn writeI32LE(bytes: []u8, value: i32) void {
    writeU32LE(bytes, @bitCast(value));
}

pub fn writeF32LE(bytes: []u8, value: f32) void {
    writeU32LE(bytes, @bitCast(value));
}
