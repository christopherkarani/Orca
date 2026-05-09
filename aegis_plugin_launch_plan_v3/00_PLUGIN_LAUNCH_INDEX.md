# Aegis Plugin Launch Plan v3

**Project:** Aegis CLI plugin surface + Codex plugin + Claude Code plugin  
**Starting point:** Current Aegis repository state, not the old Phase 22 assumption  
**Important context:** A separate drone workstream exists or may exist in the repo  
**Goal:** Make Aegis usable as a plugin-native tool inside Codex and Claude Code  
**Scope:** Local-first CLI/plugin integration only; no SaaS, telemetry, monetization, hosted dashboards, MCP dependency, or drone plugin features.

---

## What Changed in v3

This version removes the over-scoped assumptions from v2.

The plugin plan **does not depend on MCP**.

The plugin plan **does not add drone features**.

Drone-related work is treated only as a separate safety-sensitive workstream that the plugin phases must not break, expose, or weaken.

---

## Product Shape

Aegis should have three layers:

```text
Aegis CLI/Core
  The source of truth for policy, redaction, audit, replay, and runtime safety.

Aegis CLI Plugin Surface
  Stable commands and schemas used by host plugins:
  plugin doctor, plugin manifest, plugin install, decide, hook.

Host Plugins
  Codex and Claude Code plugin packages that call the Aegis CLI.
```

The host plugins must not duplicate policy logic.

---

## Explicit Non-goals

Do not build in this plugin plan:

- SaaS
- telemetry by default
- monetization
- hosted dashboards
- hosted control plane
- MCP server mode
- MCP gateway
- drone plugin features
- drone demos
- drone actuation tools
- drone-control instructions
- new sandboxing systems
- major core Aegis refactors

---

## Drone Workstream Rule

Drone-related functionality is out of scope for the plugin build.

Plugin work must:

- not modify drone modules unless required to preserve build/test compatibility
- not expose drone commands in plugins
- not add drone skills
- not add drone demos
- not operate drone hardware
- not weaken drone tests, policies, or safety checks
- not include operational drone-control instructions

If drone work exists, the only acceptable plugin-plan behavior is documentation such as:

```text
Separate drone workstream detected. Plugin phases do not modify or expose drone functionality.
```

---

## Phase List

| Phase | File | Goal | Effort |
|---:|---|---|---|
| P00 | `P00_CURRENT_BASELINE_AND_SAFEPOINT.md` | Already completed: inspect current repo and protect separate workstreams | High |
| P01 | `P01_AEGIS_CLI_PLUGIN_SURFACE.md` | Already completed or in progress: minimal `aegis plugin` namespace | High |
| P02 | `P02_AGENT_HOST_INTEGRATION_API.md` | Add `aegis decide` and `aegis hook` for Codex/Claude | High |
| P03 | `P03_CODEX_PLUGIN.md` | Build Codex plugin package | Medium-High |
| P04 | `P04_CLAUDE_CODE_PLUGIN.md` | Build Claude Code plugin package | High |
| P05 | `P05_PLUGIN_SECURITY_AND_COMPATIBILITY.md` | Test hooks, plugin artifacts, secrets, docs, and separate-workstream non-regression | High |
| P06 | `P06_PLUGIN_DISTRIBUTION_AND_MARKETPLACE.md` | Package plugins, install docs, release artifacts | Medium |
| P07 | `P07_PLUGIN_LAUNCH_AND_POSTLAUNCH.md` | Launch, triage, and first patch process | Medium |

---

## Desired Repository Layout

```text
integrations/
  README.md
  common/
    schemas/
      aegis-plugin-doctor-v1.json
      aegis-plugin-manifest-status-v1.json
      aegis-plugin-install-plan-v1.json
      hook-request-v1.json
      hook-response-v1.json
      host-capabilities-v1.json
    docs/
      integration-api.md
      host-output-mapping.md
      separate-workstream-guardrails.md
  codex-plugin/
    .codex-plugin/
      plugin.json
    skills/
      aegis-doctor/
        SKILL.md
      aegis-init/
        SKILL.md
      aegis-protect/
        SKILL.md
      aegis-redteam/
        SKILL.md
      aegis-replay/
        SKILL.md
    hooks/
      hooks.json
    README.md
  claude-code-plugin/
    .claude-plugin/
      plugin.json
    skills/
      doctor/
        SKILL.md
      init/
        SKILL.md
      protect/
        SKILL.md
      redteam/
        SKILL.md
      replay/
        SKILL.md
    hooks/
      hooks.json
    README.md
  claude-marketplace/
    .claude-plugin/
      marketplace.json
    README.md

docs/
  integrations/
    aegis-cli-plugin.md
    codex.md
    claude-code.md
    plugin-security-model.md
    plugin-troubleshooting.md
    separate-workstream-guardrails.md
```

---

## Success Criteria

The plugin project is complete when:

### Aegis CLI Plugin Surface

- `aegis plugin doctor` works.
- `aegis plugin manifest codex` reports Codex plugin status.
- `aegis plugin manifest claude` reports Claude plugin status.
- `aegis plugin install codex --dry-run` works.
- `aegis plugin install claude --dry-run` works.
- `aegis decide` exposes stable JSON decisions for commands, files, prompts, and host tool calls.
- `aegis hook codex <event>` works with fake Codex payloads.
- `aegis hook claude <event>` works with fake Claude payloads.

### Codex Plugin

- Plugin manifest exists at `.codex-plugin/plugin.json`.
- Skills exist for doctor, init, protect, redteam, and replay.
- Hooks call `aegis hook codex`.
- Local install docs work.
- Limitations are clear.

### Claude Code Plugin

- Plugin manifest exists at `.claude-plugin/plugin.json`.
- Skills exist for doctor, init, protect, redteam, and replay.
- Hooks call `aegis hook claude`.
- Claude marketplace file exists.
- Local and marketplace install docs work.
- Limitations are clear.

### Safety

- Fake secrets do not leak.
- CI never prompts.
- Host hooks do not claim more enforcement than the host supports.
- Separate drone workstream, if present, is not modified or exposed by plugins.
- Existing Aegis tests still pass.
- Existing drone tests, if present, still pass or safe skip reasons are documented.

---

## Recommended Execution

Since P00 and P01 are already done, continue with:

```text
P02_AGENT_HOST_INTEGRATION_API.md
```

Before starting P02, confirm P01 did **not** add MCP server behavior or drone plugin features. If it did, remove or isolate that scope before moving on.
