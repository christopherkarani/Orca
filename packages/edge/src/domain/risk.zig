const commands = @import("commands.zig");

pub const RiskCategory = commands.RiskCategory;

pub fn classifyCommand(action: commands.CommandAction) RiskCategory {
    return switch (action) {
        .read_telemetry,
        .read_mission_status,
        .read_vehicle_state,
        .read_camera_frame,
        => .low,
        .land,
        .return_to_home,
        => .emergency_safe,
        .hold_position,
        => .medium,
        .arm,
        .disarm,
        .takeoff,
        .set_waypoint,
        .set_velocity,
        .set_altitude,
        .set_heading,
        .start_mission,
        .pause_mission,
        .resume_mission,
        .upload_mission,
        .set_mode,
        .change_geofence,
        .companion_computer_reboot,
        .telemetry_stream_external,
        => .high,
        .disable_geofence,
        .disable_failsafe,
        .override_operator,
        .raw_actuator_output,
        .payload_release,
        .firmware_update,
        => .critical,
    };
}
