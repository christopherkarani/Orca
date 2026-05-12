const messages = @import("messages.zig");

pub const max_mission_items: usize = 128;

pub const MissionTracker = struct {
    active: bool = false,
    expected_count: ?u16 = null,
    received: [max_mission_items]bool = [_]bool{false} ** max_mission_items,
    received_count: u16 = 0,
    duplicate_seen: bool = false,
    missing_seen: bool = false,
    denied: bool = false,
    completed: bool = false,
    ack_seen: bool = false,
    clear_seen: bool = false,
    current_seq: ?u16 = null,

    pub fn init() MissionTracker {
        return .{};
    }

    pub fn observe(self: *MissionTracker, message: messages.SupportedMessage) !void {
        switch (message) {
            .mission_count => |count| {
                if (count.count > max_mission_items) return error.MissionTooLarge;
                self.active = true;
                self.expected_count = count.count;
                self.received = [_]bool{false} ** max_mission_items;
                self.received_count = 0;
                self.duplicate_seen = false;
                self.missing_seen = false;
                self.denied = false;
                self.completed = false;
                self.ack_seen = false;
            },
            .mission_item => |item| try self.observeMissionItemSeq(item.seq),
            .mission_item_int => |item| try self.observeMissionItemSeq(item.seq),
            .mission_ack => |_| {
                self.ack_seen = true;
                if (self.expected_count) |expected| self.completed = self.received_count == expected and !self.denied;
            },
            .mission_clear_all => |_| {
                self.clear_seen = true;
                self.active = false;
                self.expected_count = null;
                self.received = [_]bool{false} ** max_mission_items;
                self.received_count = 0;
            },
            .mission_set_current => |current| self.current_seq = current.seq,
            else => {},
        }
    }

    pub fn markDenied(self: *MissionTracker) void {
        self.denied = true;
        self.completed = false;
    }

    pub fn partialUploadFlagged(self: MissionTracker) bool {
        if (!self.active) return false;
        if (self.expected_count) |expected| return self.received_count < expected or self.missing_seen or self.denied;
        return true;
    }

    fn observeMissionItemSeq(self: *MissionTracker, seq: u16) !void {
        if (!self.active) self.active = true;
        if (seq >= max_mission_items) return error.MissionTooLarge;
        if (self.received[seq]) {
            self.duplicate_seen = true;
        } else {
            self.received[seq] = true;
            self.received_count += 1;
        }
        if (self.expected_count) |expected| {
            if (seq >= expected) self.missing_seen = true;
            self.completed = self.received_count == expected and !self.denied;
        }
    }
};
