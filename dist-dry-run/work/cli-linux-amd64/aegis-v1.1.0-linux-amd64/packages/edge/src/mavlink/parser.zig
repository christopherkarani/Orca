const std = @import("std");

const framing = @import("framing.zig");

pub const FeedStats = struct {
    frames: usize = 0,
    invalid_bytes: usize = 0,
    invalid_frames: usize = 0,
    partial: bool = false,
};

pub const Parser = struct {
    buffer: [framing.max_frame_len]u8 = undefined,
    len: usize = 0,

    pub fn init() Parser {
        return .{};
    }

    pub fn reset(self: *Parser) void {
        self.len = 0;
    }

    pub fn feed(self: *Parser, allocator: std.mem.Allocator, input: []const u8, out: *std.ArrayList(framing.Frame)) !FeedStats {
        var stats: FeedStats = .{};
        if (input.len > framing.max_frame_len * 4) return error.OversizedInput;

        var consumed: usize = 0;
        while (consumed < input.len or (input.len == 0 and consumed == 0)) {
            if (consumed < input.len) {
                if (self.len == self.buffer.len) {
                    self.reset();
                    return error.OversizedFrame;
                }
                const available = self.buffer.len - self.len;
                const take = @min(available, input.len - consumed);
                @memcpy(self.buffer[self.len .. self.len + take], input[consumed .. consumed + take]);
                self.len += take;
                consumed += take;
            }

            try self.drain(allocator, out, &stats);
            if (consumed >= input.len) break;
            if (self.len == self.buffer.len) {
                self.reset();
                return error.OversizedFrame;
            }
        }
        stats.partial = self.len > 0;
        return stats;
    }

    fn drain(self: *Parser, allocator: std.mem.Allocator, out: *std.ArrayList(framing.Frame), stats: *FeedStats) !void {
        var offset: usize = 0;
        while (offset < self.len) {
            if (!framing.isMagic(self.buffer[offset])) {
                offset += 1;
                stats.invalid_bytes += 1;
                continue;
            }
            const candidate = self.buffer[offset..self.len];
            const total = framing.frameTotalLengthPrefix(candidate) catch |err| switch (err) {
                error.TruncatedFrame => {
                    break;
                },
                error.InvalidMagic => {
                    offset += 1;
                    stats.invalid_bytes += 1;
                    continue;
                },
                else => return err,
            };
            if (total > framing.max_frame_len) return error.OversizedFrame;
            if (candidate.len < total) break;
            const frame_slice = candidate[0..total];
            const parsed = framing.parseFrame(frame_slice) catch |err| switch (err) {
                error.InvalidChecksum, error.InvalidPayloadLength, error.ExtraBytes => {
                    stats.invalid_frames += 1;
                    offset += 1;
                    continue;
                },
                else => return err,
            };
            try out.append(allocator, parsed);
            stats.frames += 1;
            offset += total;
        }

        if (offset > 0) {
            const remaining = self.len - offset;
            if (remaining > 0) std.mem.copyForwards(u8, self.buffer[0..remaining], self.buffer[offset..self.len]);
            self.len = remaining;
        }
    }
};
