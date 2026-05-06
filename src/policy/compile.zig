const schema = @import("schema.zig");
const validate = @import("validate.zig");

pub const CompiledPolicy = schema.Policy;

pub fn policy(value: *const schema.Policy) !void {
    try validate.policy(value);
}
