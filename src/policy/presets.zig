const std = @import("std");

pub const Preset = enum {
    observe,
    ask,
    strict,
    ci,
    redteam,
    trusted,

    pub fn parse(value: []const u8) ?Preset {
        inline for (@typeInfo(Preset).@"enum".fields) |field| {
            if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
        }
        return null;
    }
};

pub fn text(preset: Preset) []const u8 {
    return switch (preset) {
        .observe => observe_policy,
        .ask => ask_policy,
        .strict => strict_policy,
        .ci => ci_policy,
        .redteam => redteam_policy,
        .trusted => trusted_policy,
    };
}

pub fn defaultPreset() Preset {
    return .strict;
}

const common_strict_rules =
    \\workspace:
    \\  root: "."
    \\  write_mode: staged
    \\
    \\env:
    \\  inherit: false
    \\  allow:
    \\    - PATH
    \\    - HOME
    \\    - LANG
    \\    - TERM
    \\  deny_patterns:
    \\    - "*TOKEN*"
    \\    - "*SECRET*"
    \\    - "*KEY*"
    \\    - "AWS_*"
    \\
    \\files:
    \\  read:
    \\    allow:
    \\      - "./**"
    \\    deny:
    \\      - "./.env"
    \\      - "./.env.*"
    \\      - "~/.ssh/**"
    \\      - "~/.aws/**"
    \\  write:
    \\    allow:
    \\      - "./**"
    \\    deny:
    \\      - "./.git/**"
    \\      - "./.aegis/**"
    \\    mode: staged
    \\
    \\commands:
    \\  default: ask
    \\  allow:
    \\    - "git status"
    \\    - "git diff *"
    \\  deny:
    \\    - "rm -rf *"
    \\    - "curl * | sh"
    \\    - "sudo *"
    \\
    \\network:
    \\  default: deny
    \\  allow:
    \\    - "api.github.com"
    \\    - "registry.npmjs.org"
    \\
    \\mcp:
    \\  default: ask
    \\  deny:
    \\    - "*.shell"
    \\    - "*.run_command"
    \\
    \\audit:
    \\  level: full
    \\  redact_secrets: true
    \\  tamper_evident: true
    \\
;

pub const strict_policy =
    \\version: 1
    \\mode: strict
    \\
++ common_strict_rules;

pub const ci_policy =
    \\version: 1
    \\mode: ci
    \\
++ common_strict_rules;

pub const ask_policy =
    \\version: 1
    \\mode: ask
    \\
++ common_strict_rules;

pub const observe_policy =
    \\version: 1
    \\mode: observe
    \\
    \\workspace:
    \\  root: "."
    \\  write_mode: staged
    \\
    \\env:
    \\  inherit: true
    \\  deny_patterns:
    \\    - "*TOKEN*"
    \\    - "*SECRET*"
    \\    - "*KEY*"
    \\    - "AWS_*"
    \\
    \\files:
    \\  read:
    \\    default: observe
    \\    deny:
    \\      - "~/.ssh/**"
    \\      - "~/.aws/**"
    \\      - "./.env"
    \\      - "./.env.*"
    \\  write:
    \\    default: observe
    \\    mode: staged
    \\
    \\commands:
    \\  default: observe
    \\  deny:
    \\    - "rm -rf *"
    \\
    \\network:
    \\  default: observe
    \\
    \\mcp:
    \\  default: observe
    \\
    \\audit:
    \\  level: full
    \\  redact_secrets: true
    \\  tamper_evident: true
    \\
;

pub const redteam_policy =
    \\version: 1
    \\mode: redteam
    \\
++ common_strict_rules;

pub const trusted_policy =
    \\version: 1
    \\mode: trusted
    \\
    \\workspace:
    \\  root: "."
    \\  write_mode: staged
    \\
    \\env:
    \\  inherit: true
    \\  deny_patterns:
    \\    - "*TOKEN*"
    \\    - "*SECRET*"
    \\    - "*KEY*"
    \\
    \\files:
    \\  read:
    \\    allow:
    \\      - "./**"
    \\    deny:
    \\      - "~/.ssh/**"
    \\      - "~/.aws/**"
    \\      - "./.env"
    \\      - "./.env.*"
    \\  write:
    \\    allow:
    \\      - "./**"
    \\    deny:
    \\      - "./.git/**"
    \\      - "./.aegis/**"
    \\    mode: staged
    \\
    \\commands:
    \\  default: allow
    \\  deny:
    \\    - "rm -rf *"
    \\    - "curl * | sh"
    \\    - "sudo *"
    \\
    \\network:
    \\  default: ask
    \\  allow:
    \\    - "api.github.com"
    \\    - "registry.npmjs.org"
    \\
    \\mcp:
    \\  default: ask
    \\
    \\audit:
    \\  level: full
    \\  redact_secrets: true
    \\  tamper_evident: true
    \\
;

test "built-in presets expose required phase 07 policies" {
    try std.testing.expect(std.mem.indexOf(u8, text(.observe), "mode: observe") != null);
    try std.testing.expect(std.mem.indexOf(u8, text(.ask), "mode: ask") != null);
    try std.testing.expect(std.mem.indexOf(u8, text(.strict), "mode: strict") != null);
    try std.testing.expect(std.mem.indexOf(u8, text(.ci), "mode: ci") != null);
}
