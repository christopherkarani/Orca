pub const max_session_id_len = 64;
pub const max_event_id_len = 64;
pub const max_short_suffix_bytes = 8;

pub const max_command_len = 16 * 1024;
pub const max_path_len = 16 * 1024;
pub const max_env_name_len = 1024;
pub const max_url_len = 8192;
pub const max_event_field_len = 64 * 1024;
pub const max_mcp_message_len = 1024 * 1024;
pub const max_policy_file_len = 1024 * 1024;
pub const max_fixture_file_len = 2 * 1024 * 1024;
pub const max_json_depth = 64;
pub const max_mcp_schema_depth = 64;
pub const max_mcp_tool_count = 512;

test "limits expose bounded untrusted input sizes" {
    const std = @import("std");
    try std.testing.expect(max_command_len > 0);
    try std.testing.expect(max_mcp_message_len >= max_command_len);
    try std.testing.expect(max_session_id_len == 64);
}
