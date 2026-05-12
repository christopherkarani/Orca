# Orca Launch Posts

Pre-written launch copy for distribution across platforms. These are templates—adapt tone and length to each community before posting.

---

## GitHub Release Announcement

**Orca v1.1.0 — Runtime guardrails and plugins for AI agents**

Orca 1.1.0 is now available with native plugins for Codex and Claude Code.

What is Orca?
Orca is an open-source local runtime that adds policy checks, secret redaction, audit logs, replay, and red-team fixtures to AI agent sessions. It is not a SaaS, hosted dashboard, or telemetry service. Everything runs locally.

What is new in 1.1.0?
- Native Codex plugin with lifecycle hooks and skills
- Native Claude Code plugin with lifecycle hooks and skills
- `orca plugin doctor` for diagnosing installation and host compatibility
- `orca plugin install` with dry-run-by-default safety
- Release artifacts with checksum verification

Installation

From a release artifact:
1. Download the plugin zip for your host from the release assets.
2. Verify the checksum: `sha256sum -c orca-plugin-checksums.txt`
3. Extract and point your host at the plugin directory.

From source:
```sh
zig build
./zig-out/bin/orca doctor
./zig-out/bin/orca plugin doctor codex
./zig-out/bin/orca plugin doctor claude
```

The strongest protection remains running the agent through `orca run`; plugins provide native commands, hooks, and guardrails inside supported agent hosts.

Known limitations
- Hooks are advisory and depend on host support.
- Official marketplace availability is not yet implemented.
- Plugin installation is preview/dry-run by default.
- No telemetry is collected.
- The plugins do not protect sessions that are not launched through Orca.
- These plugins do not add MCP server functionality or drone-specific plugin features.

Report security issues privately through SECURITY.md.

Full release notes: https://github.com/christopherkarani/Aegis/releases/tag/v1.1.0

---

## Hacker News

Title: Show HN: Orca — Local runtime guardrails and plugins for AI agents

Orca is an open-source local CLI that adds policy checks, secret redaction, audit logs, replay, and red-team fixtures to AI agent sessions. It is not a SaaS, hosted dashboard, or telemetry service.

The 1.1.0 release adds native plugins for Codex and Claude Code. The plugins add host-native skills and lifecycle hooks that call the Orca CLI for policy decisions, so host integrations do not duplicate policy logic or add MCP behavior.

Key design choices:
- Everything is local. No accounts, no cloud, no telemetry.
- Dry-run by default. `orca plugin install` previews changes before mutating anything.
- Checksum-verified releases. Every plugin artifact ships with a SHA-256 checksum file.
- Honest capability reporting. `orca doctor` tells you exactly what enforcement is active, limited, or unavailable on your platform.

The strongest protection remains running the agent through `orca run`; plugins provide native commands, hooks, and guardrails inside supported agent hosts.

Orca does not claim perfect sandboxing, universal file/network enforcement, or protection against agents launched outside Orca.

Repo: https://github.com/christopherkarani/Aegis
Release: https://github.com/christopherkarani/Aegis/releases/tag/v1.1.0

---

## Reddit (r/programming, r/coding, r/ChatGPT, r/ClaudeAI)

Title: Orca v1.1.0 — Local runtime guardrails and plugins for Codex and Claude Code

I built Orca, an open-source local CLI that adds policy checks, secret redaction, audit logs, replay, and red-team fixtures to AI agent sessions. It is not a SaaS, hosted dashboard, or telemetry service.

The 1.1.0 release ships native plugins for Codex and Claude Code. The plugins add host-native skills and lifecycle hooks that call the Orca CLI for policy decisions.

Key points:
- Everything runs locally. No cloud dependency, no accounts, no telemetry.
- `orca plugin doctor` diagnoses your installation and host compatibility.
- `orca plugin install` defaults to dry-run so you preview changes first.
- Release artifacts include SHA-256 checksums.
- `orca doctor` reports honest capability states for your platform.

The strongest protection remains running the agent through `orca run`; plugins provide native commands, hooks, and guardrails inside supported agent hosts.

Orca does not claim perfect sandboxing, universal file/network enforcement, or protection for agents launched outside Orca.

Links:
- Repo: https://github.com/christopherkarani/Aegis
- Release: https://github.com/christopherkarani/Aegis/releases/tag/v1.1.0
- Docs: https://github.com/christopherkarani/Aegis/tree/main/docs

---

## X / LinkedIn

Orca v1.1.0 is out.

Local runtime guardrails and plugins for AI agents. Native Codex and Claude Code integrations. Policy checks, secret redaction, audit logs, replay, and red-team fixtures. No SaaS. No telemetry. No accounts.

The strongest protection remains running the agent through `orca run`; plugins provide native commands, hooks, and guardrails inside supported agent hosts.

Release: https://github.com/christopherkarani/Aegis/releases/tag/v1.1.0

---

## DevTools / Security Community Post

Title: Orca v1.1.0 — Local policy and host plugins for AI agent runtimes

Orca is an open-source local CLI that wraps AI agent sessions with policy checks, secret redaction, tamper-evident audit logs, replay, and red-team fixtures. It is not a SaaS, hosted dashboard, or telemetry service.

The 1.1.0 release introduces native plugins for Codex and Claude Code. The plugins are thin host integrations: they add skills and lifecycle hooks that call the Orca CLI for policy decisions. They do not duplicate policy logic, add MCP server behavior, or introduce drone-specific plugin features.

Security model
- Orca reduces blast radius through environment filtering, command checks, and audit logging for child sessions it launches.
- Orca is not a perfect sandbox. It works within OS constraints and honest capability reporting.
- Host hooks are advisory and limited by host capabilities.
- Orca only protects sessions routed through Orca or host hooks.

The strongest protection remains running the agent through `orca run`; plugins provide native commands, hooks, and guardrails inside supported agent hosts.

Installation and verification
- Release artifacts: https://github.com/christopherkarani/Aegis/releases/tag/v1.1.0
- Verify checksums before installing: `sha256sum -c orca-plugin-checksums.txt`
- Run diagnostics: `./zig-out/bin/orca plugin doctor codex` and `./zig-out/bin/orca plugin doctor claude`

Known limitations
- Hooks are advisory and depend on host support.
- Official marketplace availability is not yet implemented.
- Plugin installation is preview/dry-run by default.
- No telemetry is collected.
- The plugins do not protect sessions that are not launched through Orca.
- These plugins do not add MCP server functionality or drone-specific plugin features.

Report security issues privately through SECURITY.md.

---

## Posting Guidelines

- Do not claim perfect sandboxing, universal file/network enforcement, or MCP server behavior.
- Always include the required sentence about `orca run` being the strongest protection.
- Adapt length and tone to each platform. X/LinkedIn should be short; HN and Reddit can be longer.
- Do not post identical copy across platforms. Rewrite for the audience.
- Monitor replies for the first 24 hours and respond to questions or corrections promptly.
