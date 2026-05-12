const std = @import("std");

const domain = @import("../domain/mod.zig");
const mavlink = @import("../mavlink/mod.zig");
const vehicle_kind = @import("vehicle_kind.zig");

const MAV_AUTOPILOT_ARDUPILOTMEGA: u8 = 3;
const MAV_MODE_FLAG_SAFETY_ARMED: u8 = 0x80;

pub const copter_mode_stabilize: u32 = 0;
pub const copter_mode_auto: u32 = 3;
pub const copter_mode_guided: u32 = 4;
pub const copter_mode_loiter: u32 = 5;
pub const copter_mode_rtl: u32 = 6;
pub const copter_mode_land: u32 = 9;

pub const MapperOptions = struct {
    vehicle_id: []const u8,
    vehicle: vehicle_kind.VehicleKind = .copter,
    provenance: domain.state.StateProvenance,
    now_ms: i128,
    stale_after_ms: u64 = 1_000,
    expire_after_ms: u64 = 5_000,
};

pub const StateMapper = struct {
    options: MapperOptions,
    current: domain.state.VehicleState,
    last_update_ms: ?i128 = null,

    pub fn init(options: MapperOptions) StateMapper {
        return .{
            .options = options,
            .current = .{
                .vehicle_id = .{ .value = options.vehicle_id },
                .vehicle_kind = options.vehicle.toDomainKind(),
                .autopilot_kind = .ardupilot,
                .mode = .unknown,
                .arm_state = .unknown,
                .control_authority = .onboard_agent,
                .timestamp = .{ .value = options.now_ms, .source = .autopilot },
                .state_freshness = .unknown,
                .provenance = options.provenance,
            },
        };
    }

    pub fn observeFrame(self: *StateMapper, frame: mavlink.framing.Frame) !void {
        switch (frame.msgid) {
            mavlink.dialect.HEARTBEAT => try self.observeHeartbeat(frame),
            mavlink.dialect.GLOBAL_POSITION_INT => self.observeGlobalPosition(frame),
            mavlink.dialect.GPS_RAW_INT => self.observeGpsRaw(frame),
            mavlink.dialect.LOCAL_POSITION_NED => self.observeLocalPosition(frame),
            mavlink.dialect.ATTITUDE => self.observeAttitude(frame),
            mavlink.dialect.SYS_STATUS => self.observeSysStatus(frame),
            mavlink.dialect.BATTERY_STATUS => self.observeBatteryStatus(frame),
            else => {},
        }
    }

    pub fn state(self: StateMapper) domain.state.VehicleState {
        return self.current;
    }

    pub fn refreshFreshness(self: *StateMapper, now_ms: i128) void {
        const last = self.last_update_ms orelse {
            self.current.state_freshness = .unknown;
            return;
        };
        const age_ms: u64 = if (now_ms <= last) 0 else @intCast(now_ms - last);
        if (age_ms > self.options.expire_after_ms) {
            self.current.state_freshness = .expired;
        } else if (age_ms > self.options.stale_after_ms) {
            self.current.state_freshness = .stale;
        } else {
            self.current.state_freshness = .fresh;
        }
    }

    fn markUpdated(self: *StateMapper) void {
        self.last_update_ms = self.options.now_ms;
        self.current.timestamp = .{ .value = self.options.now_ms, .source = .autopilot };
        self.current.state_freshness = .fresh;
        self.current.provenance = self.options.provenance;
    }

    fn observeHeartbeat(self: *StateMapper, frame: mavlink.framing.Frame) !void {
        const message = try mavlink.messages.decode(frame);
        const heartbeat = switch (message) {
            .heartbeat => |value| value,
            else => return,
        };
        const heartbeat_vehicle = vehicle_kind.fromHeartbeatType(heartbeat.vehicle_type);
        const selected_vehicle = if (heartbeat_vehicle == .unknown) self.options.vehicle else heartbeat_vehicle;
        self.current.vehicle_kind = selected_vehicle.toDomainKind();
        self.current.autopilot_kind = if (heartbeat.autopilot == MAV_AUTOPILOT_ARDUPILOTMEGA) .ardupilot else .unknown;
        self.current.arm_state = if ((heartbeat.base_mode & MAV_MODE_FLAG_SAFETY_ARMED) != 0) .armed else .disarmed;
        self.current.mode = modeFromCustomMode(selected_vehicle, heartbeat.custom_mode);
        self.current.link_state = .{
            .connected = true,
            .last_heartbeat = .{ .value = self.options.now_ms, .source = .autopilot },
            .packet_loss_percent = 0,
            .source = .autopilot,
        };
        self.markUpdated();
    }

    fn observeGlobalPosition(self: *StateMapper, frame: mavlink.framing.Frame) void {
        const p = frame.payload;
        const lat = mavlink.framing.readI32LE(p[4..8]);
        const lon = mavlink.framing.readI32LE(p[8..12]);
        const alt_mm = mavlink.framing.readI32LE(p[12..16]);
        const vx = mavlink.framing.readI16LE(p[20..22]);
        const vy = mavlink.framing.readI16LE(p[22..24]);
        const vz = mavlink.framing.readI16LE(p[24..26]);
        const hdg = mavlink.framing.readU16LE(p[26..28]);
        self.current.position = .{
            .latitude_deg = @as(f64, @floatFromInt(lat)) / 10_000_000.0,
            .longitude_deg = @as(f64, @floatFromInt(lon)) / 10_000_000.0,
            .altitude_m = @as(f64, @floatFromInt(alt_mm)) / 1_000.0,
            .altitude_reference = .amsl,
        };
        self.current.velocity = .{
            .vx_mps = @as(f64, @floatFromInt(vx)) / 100.0,
            .vy_mps = @as(f64, @floatFromInt(vy)) / 100.0,
            .vz_mps = @as(f64, @floatFromInt(vz)) / 100.0,
            .frame = .local_ned,
        };
        if (hdg != 65535) self.current.heading = .{ .value = @as(f64, @floatFromInt(hdg)) / 100.0, .unit = .degrees };
        self.markUpdated();
    }

    fn observeGpsRaw(self: *StateMapper, frame: mavlink.framing.Frame) void {
        const p = frame.payload;
        const fix_type = p[28];
        const satellites = if (p.len > 29) p[29] else 0;
        self.current.gps_state = .{
            .fix_type = gpsFix(fix_type),
            .satellites_visible = satellites,
            .is_valid = fix_type >= 3,
            .source = .gps,
        };
        if (self.current.position == null and fix_type >= 2) {
            self.current.position = .{
                .latitude_deg = @as(f64, @floatFromInt(mavlink.framing.readI32LE(p[8..12]))) / 10_000_000.0,
                .longitude_deg = @as(f64, @floatFromInt(mavlink.framing.readI32LE(p[12..16]))) / 10_000_000.0,
                .altitude_m = @as(f64, @floatFromInt(mavlink.framing.readI32LE(p[16..20]))) / 1_000.0,
                .altitude_reference = .amsl,
            };
        }
        self.markUpdated();
    }

    fn observeLocalPosition(self: *StateMapper, frame: mavlink.framing.Frame) void {
        const p = frame.payload;
        self.current.local_position = .{
            .x_m = mavlink.framing.readF32LE(p[4..8]),
            .y_m = mavlink.framing.readF32LE(p[8..12]),
            .z_m = mavlink.framing.readF32LE(p[12..16]),
            .frame = .local_ned,
        };
        self.current.velocity = .{
            .vx_mps = mavlink.framing.readF32LE(p[16..20]),
            .vy_mps = mavlink.framing.readF32LE(p[20..24]),
            .vz_mps = mavlink.framing.readF32LE(p[24..28]),
            .frame = .local_ned,
        };
        self.markUpdated();
    }

    fn observeAttitude(self: *StateMapper, frame: mavlink.framing.Frame) void {
        const p = frame.payload;
        self.current.attitude = .{
            .roll_rad = mavlink.framing.readF32LE(p[4..8]),
            .pitch_rad = mavlink.framing.readF32LE(p[8..12]),
            .yaw_rad = mavlink.framing.readF32LE(p[12..16]),
        };
        self.markUpdated();
    }

    fn observeSysStatus(self: *StateMapper, frame: mavlink.framing.Frame) void {
        const p = frame.payload;
        const voltage_mv = mavlink.framing.readU16LE(p[14..16]);
        const current_ca = mavlink.framing.readI16LE(p[16..18]);
        const remaining_i8: i8 = @bitCast(p[30]);
        if (remaining_i8 >= 0) {
            self.current.battery_state = .{
                .percent_remaining = @floatFromInt(remaining_i8),
                .voltage_v = @as(f64, @floatFromInt(voltage_mv)) / 1000.0,
                .current_a = @as(f64, @floatFromInt(current_ca)) / 100.0,
                .is_low = remaining_i8 <= 25,
                .is_critical = remaining_i8 <= 15,
                .source = .autopilot,
            };
        }
        self.markUpdated();
    }

    fn observeBatteryStatus(self: *StateMapper, frame: mavlink.framing.Frame) void {
        const p = frame.payload;
        const voltage_mv = mavlink.framing.readU16LE(p[10..12]);
        const current_ca = mavlink.framing.readI16LE(p[30..32]);
        const remaining_i8: i8 = @bitCast(p[35]);
        if (remaining_i8 >= 0) {
            self.current.battery_state = .{
                .percent_remaining = @floatFromInt(remaining_i8),
                .voltage_v = @as(f64, @floatFromInt(voltage_mv)) / 1000.0,
                .current_a = @as(f64, @floatFromInt(current_ca)) / 100.0,
                .is_low = remaining_i8 <= 25,
                .is_critical = remaining_i8 <= 15,
                .source = .autopilot,
            };
        }
        self.markUpdated();
    }
};

fn modeFromCustomMode(vehicle: vehicle_kind.VehicleKind, custom_mode: u32) domain.vehicle.VehicleMode {
    return switch (vehicle) {
        .copter => switch (custom_mode) {
            copter_mode_stabilize => .stabilized,
            copter_mode_auto => .auto,
            copter_mode_guided => .guided,
            copter_mode_loiter => .hold,
            copter_mode_rtl => .return_to_home,
            copter_mode_land => .land,
            else => .unknown,
        },
        .plane => switch (custom_mode) {
            0 => .manual,
            2 => .stabilized,
            10 => .auto,
            11 => .return_to_home,
            12 => .hold,
            15 => .guided,
            else => .unknown,
        },
        .rover => switch (custom_mode) {
            0 => .manual,
            4, 5 => .hold,
            10 => .auto,
            11, 12 => .return_to_home,
            15 => .guided,
            else => .unknown,
        },
        .sub => switch (custom_mode) {
            0 => .stabilized,
            3 => .auto,
            4 => .guided,
            9 => .land,
            16 => .hold,
            19 => .manual,
            else => .unknown,
        },
        .unknown => .unknown,
    };
}

fn gpsFix(value: u8) domain.sensors.GpsFixType {
    return switch (value) {
        0 => .none,
        2 => .two_d,
        3 => .three_d,
        4 => .differential,
        5 => .rtk_float,
        6 => .rtk_fixed,
        else => .unknown,
    };
}
