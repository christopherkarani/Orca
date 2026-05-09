# Prompts for Revised Plugin Phases v3

## General Prefix

```text
You are implementing Aegis plugin work.

Important context:
- Do not assume we are continuing from the original Phase 22 roadmap.
- Use the current repository state and P00/P01 handoffs.
- Aegis CLI itself should become a plugin-capable surface.
- Host plugins must call the Aegis CLI and must not duplicate policy logic.
- The plugin plan does not depend on MCP.
- Do not add MCP server behavior unless explicitly requested in a later plan.
- Drone or other safety-sensitive workstreams are out of scope for plugins.
- Do not expose drone commands, drone skills, drone demos, or operational drone-control instructions.
- Do not add SaaS, telemetry by default, monetization, hosted dashboards, or unrelated features.
- Plugins must not claim stronger enforcement than the host supports.
```

## P02

```text
[General Prefix]

Implement P02 using P02_AGENT_HOST_INTEGRATION_API.md.

Recommended effort: High.
```

## P03

```text
[General Prefix]

Implement P03 using P03_CODEX_PLUGIN.md.

Recommended effort: Medium-High.
```

## P04

```text
[General Prefix]

Implement P04 using P04_CLAUDE_CODE_PLUGIN.md.

Recommended effort: High.
```

## P05

```text
[General Prefix]

Implement P05 using P05_PLUGIN_SECURITY_AND_COMPATIBILITY.md.

Recommended effort: High.
```

## P06

```text
[General Prefix]

Implement P06 using P06_PLUGIN_DISTRIBUTION_AND_MARKETPLACE.md.

Recommended effort: Medium.
```

## P07

```text
[General Prefix]

Implement P07 using P07_PLUGIN_LAUNCH_AND_POSTLAUNCH.md.

Recommended effort: Medium.
```
