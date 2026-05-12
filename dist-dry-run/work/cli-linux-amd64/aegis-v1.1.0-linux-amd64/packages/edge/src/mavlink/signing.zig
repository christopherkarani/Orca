const framing = @import("framing.zig");

pub const SigningInspection = struct {
    present: bool,
    verification_available: bool = false,
    link_id: ?u8 = null,
    timestamp_truncated: ?u64 = null,
    note: []const u8,
};

pub fn inspect(frame: framing.Frame) SigningInspection {
    if (!frame.signature_present) {
        return .{
            .present = false,
            .verification_available = false,
            .note = "MAVLink2 signing absent; signing verification is unsupported in Phase 28.",
        };
    }
    const signature = frame.signature orelse return .{
        .present = true,
        .verification_available = false,
        .note = "MAVLink2 signing flag present but signature bytes are unavailable to verifier.",
    };
    var timestamp: u64 = 0;
    var shift: u6 = 0;
    for (signature[1..7]) |byte| {
        timestamp |= @as(u64, byte) << shift;
        shift += 8;
    }
    return .{
        .present = true,
        .verification_available = false,
        .link_id = signature[0],
        .timestamp_truncated = timestamp,
        .note = "MAVLink2 signing block detected; key management and verification are unsupported in Phase 28.",
    };
}
