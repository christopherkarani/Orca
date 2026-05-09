const std = @import("std");

pub const PromptChoice = enum {
    allow_once,
    deny,
    explain,
    abort,
};

pub const PromptPolicy = struct {
    non_interactive: bool,
    ci: bool,
};

pub fn mayPrompt(policy: PromptPolicy) bool {
    return !policy.non_interactive and !policy.ci;
}

pub fn parseChoice(value: []const u8) ?PromptChoice {
    if (std.mem.eql(u8, value, "allow once") or std.mem.eql(u8, value, "allow_once")) return .allow_once;
    if (std.mem.eql(u8, value, "deny")) return .deny;
    if (std.mem.eql(u8, value, "explain")) return .explain;
    if (std.mem.eql(u8, value, "abort")) return .abort;
    return null;
}
