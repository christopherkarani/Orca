pub const audit = @import("audit.zig");
pub const classifier = @import("classifier.zig");
pub const commands = @import("commands.zig");
pub const crc = @import("crc.zig");
pub const dialect = @import("dialect.zig");
pub const fake_transport = @import("fake_transport.zig");
pub const framing = @import("framing.zig");
pub const gateway = @import("gateway.zig");
pub const mapping = @import("mapping.zig");
pub const messages = @import("messages.zig");
pub const mission = @import("mission.zig");
pub const parser = @import("parser.zig");
pub const signing = @import("signing.zig");

pub const phase = "28-mavlink-gateway-production";

test {
    _ = audit;
    _ = classifier;
    _ = commands;
    _ = crc;
    _ = dialect;
    _ = fake_transport;
    _ = framing;
    _ = gateway;
    _ = mapping;
    _ = messages;
    _ = mission;
    _ = parser;
    _ = signing;
}
