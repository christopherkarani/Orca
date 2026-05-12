const std = @import("std");
const vehicle_kind = @import("vehicle_kind.zig");

pub const Protocol = enum {
    udp,
    tcp,

    pub fn parse(value: []const u8) !Protocol {
        return std.meta.stringToEnum(Protocol, value) orelse error.UnsupportedProtocol;
    }

    pub fn toString(self: Protocol) []const u8 {
        return @tagName(self);
    }
};

pub const Mode = enum {
    observe,
    enforce,
    simulation,
    ci,
    redteam,
    bench,

    pub fn parse(value: []const u8) !Mode {
        return std.meta.stringToEnum(Mode, value) orelse error.UnsupportedArduPilotMode;
    }

    pub fn toString(self: Mode) []const u8 {
        return @tagName(self);
    }
};

pub const Environment = enum {
    fake_ardupilot,
    ardupilot_sitl,

    pub fn parse(value: []const u8) !Environment {
        return std.meta.stringToEnum(Environment, value) orelse error.UnsupportedArduPilotEnvironment;
    }

    pub fn toString(self: Environment) []const u8 {
        return @tagName(self);
    }
};

pub const Endpoint = struct {
    host: []const u8,
    port: u16,

    pub fn parse(value: []const u8) !Endpoint {
        const colon = std.mem.lastIndexOfScalar(u8, value, ':') orelse return error.InvalidEndpoint;
        const host = std.mem.trim(u8, value[0..colon], " \t\r\n");
        const port_text = std.mem.trim(u8, value[colon + 1 ..], " \t\r\n");
        if (host.len == 0 or port_text.len == 0) return error.InvalidEndpoint;
        const port = try std.fmt.parseInt(u16, port_text, 10);
        return .{ .host = host, .port = port };
    }

    pub fn format(self: Endpoint, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{s}:{d}", .{ self.host, self.port });
    }
};

pub const Config = struct {
    enabled: bool = true,
    protocol: Protocol = .udp,
    endpoint: Endpoint = .{ .host = "127.0.0.1", .port = 14550 },
    local_bind: Endpoint = .{ .host = "127.0.0.1", .port = 14551 },
    vehicle: vehicle_kind.VehicleKind = .copter,
    mode: Mode = .observe,
    required: bool = false,
    sysid_allow: ?u8 = null,
    compid_allow: ?u8 = null,
    timeout_ms: u64 = 2_000,
    tested_version: []const u8 = "documented-by-phase-30",
};

pub const ConnectionStatus = enum {
    active,
    partial,
    unavailable,
    skipped,

    pub fn toString(self: ConnectionStatus) []const u8 {
        return @tagName(self);
    }
};

pub const HealthReport = struct {
    support: ConnectionStatus,
    endpoint_reachable: ?bool,
    reason: []const u8,
};

pub const IntegrationAvailability = enum {
    skipped,
    configured,
    unavailable,
};

pub const IntegrationEnv = struct {
    run_ardupilot_sitl_tests: ?[]const u8,
    endpoint: ?[]const u8,
    vehicle: ?[]const u8,
};

pub const IntegrationGate = struct {
    enabled: bool,
    availability: IntegrationAvailability,
    endpoint: ?Endpoint = null,
    vehicle: vehicle_kind.VehicleKind = .copter,
    reason: []const u8,
    owned_endpoint_host: ?[]u8 = null,

    pub fn deinit(self: *IntegrationGate, allocator: std.mem.Allocator) void {
        if (self.owned_endpoint_host) |host| allocator.free(host);
        self.* = undefined;
    }
};

pub fn defaultConfig() Config {
    return .{};
}

pub fn integrationTestGate(env: IntegrationEnv) IntegrationGate {
    const enabled = env.run_ardupilot_sitl_tests != null and std.mem.eql(u8, env.run_ardupilot_sitl_tests.?, "1");
    const vehicle = if (env.vehicle) |value| vehicle_kind.VehicleKind.parse(value) catch .unknown else .copter;
    if (!enabled) {
        return .{
            .enabled = false,
            .availability = .skipped,
            .vehicle = vehicle,
            .reason = "AEGIS_EDGE_RUN_ARDUPILOT_SITL_TESTS is not 1; ArduPilot SITL integration tests are skipped",
        };
    }
    if (vehicle == .unknown) {
        return .{
            .enabled = true,
            .availability = .unavailable,
            .vehicle = .unknown,
            .reason = "AEGIS_EDGE_ARDUPILOT_VEHICLE is unsupported; expected copter, plane, rover, sub, or unknown",
        };
    }
    const endpoint_text = env.endpoint orelse {
        return .{
            .enabled = true,
            .availability = .unavailable,
            .vehicle = vehicle,
            .reason = "AEGIS_EDGE_ARDUPILOT_ENDPOINT is required when ArduPilot SITL tests are enabled",
        };
    };
    const endpoint = Endpoint.parse(endpoint_text) catch {
        return .{
            .enabled = true,
            .availability = .unavailable,
            .vehicle = vehicle,
            .reason = "AEGIS_EDGE_ARDUPILOT_ENDPOINT is invalid",
        };
    };
    return .{
        .enabled = true,
        .availability = .configured,
        .endpoint = endpoint,
        .vehicle = vehicle,
        .reason = "ArduPilot SITL tests are opt-in and endpoint is configured; runtime reachability must still be checked by the integration test",
    };
}

pub fn integrationTestGateOwned(allocator: std.mem.Allocator, env: IntegrationEnv) !IntegrationGate {
    var gate = integrationTestGate(env);
    errdefer gate.deinit(allocator);
    if (gate.endpoint) |endpoint| {
        const owned_host = try allocator.dupe(u8, endpoint.host);
        gate.endpoint = .{ .host = owned_host, .port = endpoint.port };
        gate.owned_endpoint_host = owned_host;
    }
    return gate;
}

pub fn integrationTestGateFromEnv(allocator: std.mem.Allocator) !IntegrationGate {
    const run = std.process.getEnvVarOwned(allocator, "AEGIS_EDGE_RUN_ARDUPILOT_SITL_TESTS") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    defer if (run) |value| allocator.free(value);
    const endpoint = std.process.getEnvVarOwned(allocator, "AEGIS_EDGE_ARDUPILOT_ENDPOINT") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    defer if (endpoint) |value| allocator.free(value);
    const vehicle = std.process.getEnvVarOwned(allocator, "AEGIS_EDGE_ARDUPILOT_VEHICLE") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    defer if (vehicle) |value| allocator.free(value);
    return integrationTestGateOwned(allocator, .{ .run_ardupilot_sitl_tests = run, .endpoint = endpoint, .vehicle = vehicle });
}

pub fn testedVersionFromEnv(allocator: std.mem.Allocator) ![]u8 {
    return std.process.getEnvVarOwned(allocator, "AEGIS_EDGE_ARDUPILOT_TESTED_VERSION") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => try allocator.dupe(u8, "documented-by-phase-30"),
        else => return err,
    };
}

pub fn health(config: Config, gate: IntegrationGate) HealthReport {
    if (!config.enabled) return .{ .support = .unavailable, .endpoint_reachable = null, .reason = "ArduPilot SITL support disabled by config" };
    if (gate.enabled and gate.availability == .configured) {
        return .{ .support = .partial, .endpoint_reachable = null, .reason = "ArduPilot SITL endpoint is configured; live reachability is checked only in opt-in integration runs" };
    }
    if (gate.enabled and gate.availability == .unavailable) {
        return .{ .support = .unavailable, .endpoint_reachable = false, .reason = gate.reason };
    }
    return .{ .support = .partial, .endpoint_reachable = null, .reason = "ArduPilot SITL adapter, fake-ArduPilot tests, and scenario harness are available; live SITL is optional" };
}
