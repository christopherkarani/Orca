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

pub const AgentPreset = enum {
    generic_agent,
    claude_code,
    codex,
    cursor_agent,
    opencode,
    cline_roo,
    mcp_dev,
    github_actions,
    solo_dev,
    strict_local,
    team_ci,
    openclaw_hermes,
    trusted_local,

    pub fn parse(value: []const u8) ?AgentPreset {
        for (agent_preset_infos) |info| {
            if (std.mem.eql(u8, value, info.name)) return info.preset;
        }
        return null;
    }
};

pub const AgentPresetInfo = struct {
    preset: AgentPreset,
    name: []const u8,
    experimental: bool,
    warning: []const u8,
};

pub const agent_preset_infos = [_]AgentPresetInfo{
    .{ .preset = .generic_agent, .name = "generic-agent", .experimental = false, .warning = "" },
    .{ .preset = .claude_code, .name = "claude-code", .experimental = true, .warning = "claude-code is a generic/experimental preset; review assumptions before trusting it." },
    .{ .preset = .codex, .name = "codex", .experimental = true, .warning = "codex is a generic/experimental preset; review assumptions before trusting it." },
    .{ .preset = .cursor_agent, .name = "cursor-agent", .experimental = true, .warning = "cursor-agent is a generic/experimental preset; review assumptions before trusting it." },
    .{ .preset = .opencode, .name = "opencode", .experimental = true, .warning = "opencode is a generic/experimental preset; review assumptions before trusting it." },
    .{ .preset = .cline_roo, .name = "cline-roo", .experimental = true, .warning = "cline-roo is a generic/experimental preset; review assumptions before trusting it." },
    .{ .preset = .mcp_dev, .name = "mcp-dev", .experimental = false, .warning = "" },
    .{ .preset = .github_actions, .name = "github-actions", .experimental = false, .warning = "" },
    .{ .preset = .solo_dev, .name = "solo-dev", .experimental = false, .warning = "" },
    .{ .preset = .strict_local, .name = "strict-local", .experimental = false, .warning = "" },
    .{ .preset = .team_ci, .name = "team-ci", .experimental = false, .warning = "" },
    .{ .preset = .openclaw_hermes, .name = "openclaw-hermes", .experimental = false, .warning = "" },
    .{ .preset = .trusted_local, .name = "trusted-local", .experimental = false, .warning = "" },
};

pub fn agentPresetName(preset: AgentPreset) []const u8 {
    return agentPresetInfo(preset).name;
}

pub fn agentPresetInfo(preset: AgentPreset) AgentPresetInfo {
    for (agent_preset_infos) |info| {
        if (info.preset == preset) return info;
    }
    unreachable;
}

pub fn agentPresetText(preset: AgentPreset) []const u8 {
    return switch (preset) {
        .generic_agent => generic_agent_policy,
        .claude_code => claude_code_policy,
        .codex => codex_policy,
        .cursor_agent => cursor_agent_policy,
        .opencode => opencode_policy,
        .cline_roo => cline_roo_policy,
        .mcp_dev => mcp_dev_policy,
        .github_actions => github_actions_policy,
        .solo_dev => solo_dev_policy,
        .strict_local => strict_local_policy,
        .team_ci => team_ci_policy,
        .openclaw_hermes => openclaw_hermes_policy,
        .trusted_local => trusted_local_policy,
    };
}

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

const generic_agent_policy =
    \\# Orca preset: generic-agent
    \\# Conservative starting point for local coding agents with no proprietary assumptions.
    \\# Edit allowlists for your repository before switching broad actions from ask to allow.
    \\
++ ask_policy;

const claude_code_policy =
    \\# Orca preset: claude-code
    \\# Generic/experimental: assumes a normal local coding-agent workflow, not private Claude Code internals.
    \\
++ ask_policy;

const codex_policy =
    \\# Orca preset: codex
    \\# Generic/experimental: designed for local Codex-style coding tasks without model-provider secrets.
    \\
++ ask_policy;

const cursor_agent_policy =
    \\# Orca preset: cursor-agent
    \\# Generic/experimental: conservative local editor-agent policy, not a claim about Cursor internals.
    \\
++ ask_policy;

const opencode_policy =
    \\# Orca preset: opencode
    \\# Generic/experimental: tuned for local coding-agent workflows and editable allowlists.
    \\
++ ask_policy;

const cline_roo_policy =
    \\# Orca preset: cline-roo
    \\# Generic/experimental: conservative policy for local editor agents with MCP-style extensions.
    \\
++ ask_policy;

const mcp_dev_policy =
    \\# Orca preset: mcp-dev
    \\# Conservative preset for developing stdio MCP servers through Orca.
    \\# Manifests still need explicit command/hash binding; this policy does not trust servers by name alone.
    \\
++ ask_policy;

const github_actions_policy =
    \\# Orca preset: github-actions
    \\# CI-safe preset. CI mode never prompts; ask-class decisions are denied unless explicitly allowed.
    \\# Do not put workflow tokens or repository secrets in this policy.
    \\
++ ci_policy;

const solo_dev_policy =
    \\# Orca policy pack: solo-dev
    \\# Ask-mode local development pack for one developer. Keeps secret and destructive-action denies active.
    \\
++ ask_policy;

const strict_local_policy =
    \\# Orca preset: strict-local
    \\# Local strict mode. Unknown actions are denied or staged; add narrow allow rules as needed.
    \\
++ strict_policy;

const team_ci_policy =
    \\# Orca policy pack: team-ci
    \\# CI-safe team baseline. Ask-class decisions deny in CI; core safety and redteam commands are allowed.
    \\
++ ci_policy;

const openclaw_hermes_policy =
    \\# Orca policy pack: openclaw-hermes
    \\# Local plugin workflow pack for OpenClaw and Hermes hook development.
    \\
++ ask_policy;

const trusted_local_policy =
    \\# Orca preset: trusted-local
    \\# Less restrictive local preset for trusted repositories. Secret redaction and deny rules remain enabled.
    \\
++ trusted_policy;

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
    \\    - "*PASSWORD*"
    \\    - "*PASSWD*"
    \\    - "*PRIVATE*"
    \\    - "*KEY*"
    \\    - "AWS_*"
    \\    - "AZURE_*"
    \\    - "GITHUB_TOKEN"
    \\    - "GH_TOKEN"
    \\    - "OPENAI_API_KEY"
    \\    - "ANTHROPIC_API_KEY"
    \\    - "GOOGLE_API_KEY"
    \\    - "GOOGLE_APPLICATION_CREDENTIALS"
    \\    - "NPM_TOKEN"
    \\    - "PYPI_TOKEN"
    \\    - "SSH_AUTH_SOCK"
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
    \\      - "~/.gcloud/**"
    \\      - "~/.azure/**"
    \\      - "~/.config/gh/**"
    \\      - "~/Library/Keychains/**"
    \\      - "./Library/Keychains/**"
    \\      - "~/Library/Application Support/**/Cookies*"
    \\      - "./Library/Application Support/**/Cookies*"
    \\      - "~/Library/Application Support/**/Login Data*"
    \\      - "./Library/Application Support/**/Login Data*"
    \\      - "~/Library/Application Support/Google/Chrome/**"
    \\      - "./Library/Application Support/Google/Chrome/**"
    \\      - "~/Library/Application Support/BraveSoftware/**"
    \\      - "./Library/Application Support/BraveSoftware/**"
    \\      - "~/Library/Application Support/Firefox/**"
    \\      - "./Library/Application Support/Firefox/**"
    \\      - "~/Library/Mobile Documents/**"
    \\      - "./Library/Mobile Documents/**"
    \\      - "~/.zsh_history"
    \\      - "~/.bash_history"
    \\      - "~/.zshrc"
    \\      - "~/.bashrc"
    \\      - "~/.profile"
    \\      - "**/id_rsa"
    \\      - "**/id_ed25519"
    \\      - "**/*credentials*"
    \\      - "**/*credential*"
    \\      - "**/*secret*"
    \\      - "**/*token*"
    \\  write:
    \\    allow:
    \\      - "./**"
    \\    deny:
    \\      - "./.git/**"
    \\      - "./.orca/**"
    \\    mode: staged
    \\
    \\commands:
    \\  default: ask
    \\  allow:
    \\    - "git status"
    \\    - "git diff"
    \\    - "git diff *"
    \\    - "git log *"
    \\    - "git branch *"
    \\    - "git ls-files"
    \\    - "git ls-files *"
    \\    - "ls"
    \\    - "ls *"
    \\    - "pwd"
    \\    - "echo *"
    \\    - "/usr/bin/env"
    \\    - "true"
    \\    - "false"
    \\    - "rg *"
    \\    - "wc *"
    \\    - "sort *"
    \\    - "uniq *"
    \\    - "sed -n *"
    \\    - "mkdir -p *"
    \\    - "zig version"
    \\    - "zig build *"
    \\    - "npm test*"
    \\    - "pnpm test*"
    \\    - "yarn test*"
    \\    - "go test *"
    \\    - "cargo test *"
    \\    - "swift test*"
    \\    - "python -m pytest*"
    \\    - "pytest *"
    \\  deny:
    \\    - "rm -rf *"
    \\    - "find * -delete"
    \\    - "shred *"
    \\    - "curl * | sh"
    \\    - "wget * | bash"
    \\    - "sudo *"
    \\    - "su *"
    \\    - "doas *"
    \\    - "powershell *EncodedCommand*"
    \\    - "powershell *-enc*"
    \\    - "cat .env"
    \\    - "cat ~/.ssh/*"
    \\  ask:
    \\    - "npm install*"
    \\    - "pnpm install*"
    \\    - "yarn install*"
    \\    - "pip install*"
    \\    - "git push*"
    \\
    \\network:
    \\  mode: allowlist
    \\  default: deny
    \\  allow:
    \\    - "api.github.com"
    \\    - "*.github.com"
    \\    - "registry.npmjs.org"
    \\    - "pypi.org"
    \\  ask:
    \\    - "*.githubusercontent.com"
    \\  deny:
    \\    - "pastebin.com"
    \\    - "*.ngrok.io"
    \\    - "*.requestbin.net"
    \\  detect_exfiltration:
    \\    dns: true
    \\    long_query_strings: true
    \\    secret_patterns: true
    \\
    \\mcp:
    \\  default: ask
    \\  allow:
    \\    - "*.search_*"
    \\    - "*.list_*"
    \\    - "*.get_*"
    \\  deny:
    \\    - "*.delete_*"
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
    \\    - "*PASSWORD*"
    \\    - "*PASSWD*"
    \\    - "*PRIVATE*"
    \\    - "*KEY*"
    \\    - "AWS_*"
    \\    - "AZURE_*"
    \\    - "GITHUB_TOKEN"
    \\    - "GH_TOKEN"
    \\    - "OPENAI_API_KEY"
    \\    - "ANTHROPIC_API_KEY"
    \\    - "GOOGLE_API_KEY"
    \\    - "GOOGLE_APPLICATION_CREDENTIALS"
    \\    - "NPM_TOKEN"
    \\    - "PYPI_TOKEN"
    \\    - "SSH_AUTH_SOCK"
    \\
    \\files:
    \\  read:
    \\    default: observe
    \\    deny:
    \\      - "~/.ssh/**"
    \\      - "~/.aws/**"
    \\      - "~/.gcloud/**"
    \\      - "~/.azure/**"
    \\      - "~/.config/gh/**"
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
    \\  mode: observe
    \\  default: observe
    \\  deny:
    \\    - "pastebin.com"
    \\    - "*.ngrok.io"
    \\    - "*.requestbin.net"
    \\  detect_exfiltration:
    \\    dns: true
    \\    long_query_strings: true
    \\    secret_patterns: true
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
    \\    - "*PASSWORD*"
    \\    - "*PASSWD*"
    \\    - "*PRIVATE*"
    \\    - "*KEY*"
    \\    - "AWS_*"
    \\    - "AZURE_*"
    \\    - "GITHUB_TOKEN"
    \\    - "GH_TOKEN"
    \\    - "OPENAI_API_KEY"
    \\    - "ANTHROPIC_API_KEY"
    \\    - "GOOGLE_API_KEY"
    \\    - "GOOGLE_APPLICATION_CREDENTIALS"
    \\    - "NPM_TOKEN"
    \\    - "PYPI_TOKEN"
    \\    - "SSH_AUTH_SOCK"
    \\
    \\files:
    \\  read:
    \\    allow:
    \\      - "./**"
    \\    deny:
    \\      - "~/.ssh/**"
    \\      - "~/.aws/**"
    \\      - "~/.gcloud/**"
    \\      - "~/.azure/**"
    \\      - "~/.config/gh/**"
    \\      - "./.env"
    \\      - "./.env.*"
    \\  write:
    \\    allow:
    \\      - "./**"
    \\    deny:
    \\      - "./.git/**"
    \\      - "./.orca/**"
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

test "phase 18 agent presets are exposed with stable names" {
    try std.testing.expectEqual(@as(usize, 13), agent_preset_infos.len);
    try std.testing.expectEqual(AgentPreset.generic_agent, AgentPreset.parse("generic-agent").?);
    try std.testing.expectEqual(AgentPreset.github_actions, AgentPreset.parse("github-actions").?);
    try std.testing.expectEqual(AgentPreset.solo_dev, AgentPreset.parse("solo-dev").?);
    try std.testing.expectEqual(AgentPreset.strict_local, AgentPreset.parse("strict-local").?);
    try std.testing.expectEqual(AgentPreset.team_ci, AgentPreset.parse("team-ci").?);
    try std.testing.expectEqual(AgentPreset.openclaw_hermes, AgentPreset.parse("openclaw-hermes").?);
    try std.testing.expect(AgentPreset.parse("not-a-preset") == null);
    for (agent_preset_infos) |info| {
        const source = agentPresetText(info.preset);
        try std.testing.expect(std.mem.indexOf(u8, source, "version: 1") != null);
        try std.testing.expect(std.mem.indexOf(u8, source, "redact_secrets: true") != null);
    }
}
