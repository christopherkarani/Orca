const fixture = @import("fixture.zig");

pub const parser_faults = [_]fixture.FaultType{ .malformed_frame, .truncated_frame, .oversized_frame, .bad_checksum, .binary_payload_with_fake_secret };
pub const command_faults = [_]fixture.FaultType{ .unknown_message_id, .unknown_command_id, .unexpected_sysid, .unexpected_compid, .signing_absent_when_required };

test {
    _ = parser_faults;
    _ = command_faults;
}
