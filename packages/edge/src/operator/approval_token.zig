const std = @import("std");

const domain = @import("../domain/mod.zig");
const schema = @import("../schema/mod.zig");

pub fn requestId(allocator: std.mem.Allocator, parts: []const []const u8) ![]u8 {
    const digest = try hashParts(allocator, parts);
    defer allocator.free(digest);
    return std.fmt.allocPrint(allocator, "apr_{s}", .{digest[0..16]});
}

pub fn decisionId(allocator: std.mem.Allocator, request_id: []const u8, operator_id: []const u8, timestamp_ms: i128, decision: []const u8) ![]u8 {
    const timestamp = try std.fmt.allocPrint(allocator, "{d}", .{timestamp_ms});
    defer allocator.free(timestamp);
    const digest = try hashParts(allocator, &.{ request_id, operator_id, timestamp, decision });
    defer allocator.free(digest);
    return std.fmt.allocPrint(allocator, "apd_{s}", .{digest[0..16]});
}

pub fn hashPolicy(allocator: std.mem.Allocator, policy: *const schema.edge_policy_schema.EdgePolicyV1) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);
    const writer = list.writer(allocator);
    try writer.print("v={d};vehicle={s}/{s}/{s};", .{ policy.version, @tagName(policy.vehicle.kind), @tagName(policy.vehicle.autopilot), @tagName(policy.vehicle.adapter) });
    try writeCommandList(writer, "allow", policy.commands.allow);
    try writeCommandList(writer, "ask", policy.commands.ask);
    try writeCommandList(writer, "deny", policy.commands.deny);
    try writeCommandList(writer, "approval", policy.commands.require_operator_approval);
    if (policy.safety.geofence) |geofence| {
        try writer.print("geofence={s}:{d:.6}:{d:.6}:{d:.2}:{d:.2}:{s};", .{ @tagName(geofence.boundary_action), geofence.altitude_floor_m, geofence.altitude_ceiling_m, geofence.shape.circle.center.latitude_deg, geofence.shape.circle.center.longitude_deg, @tagName(geofence.altitude_reference) });
    }
    if (policy.safety.state_freshness) |freshness| try writer.print("fresh={d}:{}:{}:{};", .{ freshness.max_state_age_ms, freshness.deny_commands_on_stale_state, freshness.allow_emergency_land_on_stale_state, freshness.allow_return_home_on_stale_state });
    try writer.print("approval={d}:{d}:{}:{}:{}:{}:{};", .{ policy.safety.approval.approval_ttl_ms, policy.safety.approval.max_uses_default, policy.safety.approval.require_operator_identity, policy.safety.approval.require_state_hash, policy.safety.approval.allow_broad_scopes, policy.safety.approval.allow_non_overridable_override, policy.safety.approval.allow_compatible_policy_hash });
    try writeCommandList(writer, "fallback", policy.safety.emergency.fallback_order);
    return hashBytes(allocator, list.items);
}

pub fn hashSafetyConstraints(allocator: std.mem.Allocator, policy: *const schema.edge_policy_schema.EdgePolicyV1) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);
    const writer = list.writer(allocator);
    if (policy.safety.geofence) |geofence| try writer.print("geo={d:.6}:{d:.6}:{d:.2}:{d:.2};", .{ geofence.shape.circle.center.latitude_deg, geofence.shape.circle.center.longitude_deg, geofence.altitude_floor_m, geofence.altitude_ceiling_m });
    if (policy.safety.altitude) |alt| try writer.print("alt={d:.2}:{d:.2}:{s};", .{ alt.min_altitude_m, alt.max_altitude_m, @tagName(alt.altitude_reference) });
    if (policy.safety.velocity) |vel| try writer.print("vel={d:.2}:{d:.2};", .{ vel.max_horizontal_mps, vel.max_vertical_mps });
    if (policy.safety.battery) |battery| try writer.print("battery={d:.2}:{d:.2}:{d:.2}:{};", .{ battery.deny_takeoff_below_percent, battery.return_home_below_percent, battery.land_below_percent, battery.require_fresh_battery_state });
    if (policy.safety.state_freshness) |freshness| try writer.print("fresh={d}:{}:{}:{};", .{ freshness.max_state_age_ms, freshness.deny_commands_on_stale_state, freshness.allow_emergency_land_on_stale_state, freshness.allow_return_home_on_stale_state });
    return hashBytes(allocator, list.items);
}

pub fn hashCommandRequest(allocator: std.mem.Allocator, request: domain.commands.CommandRequest) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);
    const writer = list.writer(allocator);
    try writer.print("id={s};vehicle={s};action={s};actor={s};source={s};mission=", .{ request.command_id, request.vehicle_id.value, @tagName(request.action), request.actor, @tagName(request.source) });
    if (request.mission_id) |mission| try writer.writeAll(mission);
    try writer.writeByte(';');
    try writeParameters(writer, request.parameters);
    return hashBytes(allocator, list.items);
}

pub fn hashVehicleState(allocator: std.mem.Allocator, state: domain.state.VehicleState) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);
    const writer = list.writer(allocator);
    try writer.print("vehicle={s};kind={s};autopilot={s};mode={s};arm={s};fresh={s};prov={s};ts={d};auth={s};", .{ state.vehicle_id.value, @tagName(state.vehicle_kind), @tagName(state.autopilot_kind), @tagName(state.mode), @tagName(state.arm_state), @tagName(state.state_freshness), @tagName(state.provenance), state.timestamp.value, @tagName(state.control_authority) });
    if (state.position) |point| try writer.print("pos={d:.6},{d:.6},{d:.2},{s};", .{ point.latitude_deg, point.longitude_deg, point.altitude_m, @tagName(point.altitude_reference) });
    if (state.home_position) |home| try writer.print("home={d:.6},{d:.6},{d:.2},{s};", .{ home.latitude_deg, home.longitude_deg, home.altitude_m, @tagName(home.altitude_reference) });
    if (state.battery_state) |battery| try writer.print("battery={d:.2},{s};", .{ battery.percent_remaining, @tagName(battery.source) });
    return hashBytes(allocator, list.items);
}

pub fn hashSafetyEvaluation(allocator: std.mem.Allocator, evaluation: anytype) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);
    const writer = list.writer(allocator);
    try writer.print("decision={s};reason={s};", .{ evaluation.decision.result.toString(), evaluation.explanation });
    if (comptime @hasField(@TypeOf(evaluation), "matched_rule")) {
        if (evaluation.matched_rule) |rule| try writer.print("rule={s};", .{rule.id});
    }
    return hashBytes(allocator, list.items);
}

fn hashParts(allocator: std.mem.Allocator, parts: []const []const u8) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);
    const writer = list.writer(allocator);
    for (parts) |part| {
        try writer.writeAll(part);
        try writer.writeByte('|');
    }
    return hashBytes(allocator, list.items);
}

fn hashBytes(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    return allocator.dupe(u8, &hex);
}

fn writeCommandList(writer: anytype, label: []const u8, list: []const domain.commands.CommandAction) !void {
    try writer.print("{s}=", .{label});
    for (list) |action| try writer.print("{s},", .{@tagName(action)});
    try writer.writeByte(';');
}

fn writeParameters(writer: anytype, params: domain.commands.CommandParameters) !void {
    switch (params) {
        .none => try writer.writeAll("params=none;"),
        .waypoint => |point| try writer.print("waypoint={d:.6},{d:.6},{d:.2},{s};", .{ point.latitude_deg, point.longitude_deg, point.altitude_m, @tagName(point.altitude_reference) }),
        .velocity => |velocity| try writer.print("velocity={d:.2},{d:.2},{d:.2},{s};", .{ velocity.vx_mps, velocity.vy_mps, velocity.vz_mps, @tagName(velocity.frame) }),
        .altitude => |altitude| try writer.print("altitude={d:.2},{s};", .{ altitude.altitude_m, @tagName(altitude.altitude_reference) }),
        .heading => |heading| try writer.print("heading={d:.2},{s};", .{ heading.value, @tagName(heading.unit) }),
        .mode => |mode| try writer.print("mode={s};", .{@tagName(mode)}),
        .mission_ref => |mission| try writer.print("mission={s};", .{mission}),
    }
}
