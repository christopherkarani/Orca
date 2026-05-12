# Prompts for OpenCode and OpenClaw Phases

Use these prompts with your coding agent.

---

## General Prefix

```text
You are implementing Orca host-plugin work.

Important context:
- Orca CLI is the source of truth.
- Host plugins are thin wrappers.
- Plugins must call `orca decide`, `orca hook`, or `orca plugin doctor`.
- Do not duplicate Orca policy logic.
- Do not bundle or compile the Zig CLI inside npm plugin packages yet.
- Require `orca` on PATH.
- Do not add MCP server behavior.
- Do not add `.mcp.json`.
- Do not add drone plugin behavior.
- Do not expose drone commands, drone skills, drone demos, or operational drone-control instructions.
- Do not add SaaS, telemetry, monetization, or hosted dashboards.
```

---

## P08B Prompt

```text
[General Prefix]

Implement P08B using P08B_OPENCODE_NPM_PACKAGE.md.

Recommended effort: Medium.
```

---

## P09 Prompt

```text
[General Prefix]

Implement P09 using P09_OPENCLAW_PLUGIN.md.

Recommended effort: High.
```

---

## P10 Prompt

```text
[General Prefix]

Implement P10 using P10_OPENCLAW_NPM_PACKAGE.md.

Recommended effort: Medium-High.
```

---

## P11 Prompt

```text
[General Prefix]

Implement P11 using P11_CLAWHUB_SUBMISSION.md.

Recommended effort: Medium.
```
