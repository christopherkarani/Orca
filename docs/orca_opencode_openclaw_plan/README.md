# Orca OpenCode and OpenClaw Plan

This is a lean plan pack for extending Orca beyond Codex and Claude Code.

Start with:

1. `00_INDEX.md`
2. `HOST_PLUGIN_CONTRACT.md`
3. `PLUGIN_SECURITY_INVARIANTS.md`

Then run:

```text
P08B_OPENCODE_NPM_PACKAGE.md
P09_OPENCLAW_PLUGIN.md
P10_OPENCLAW_NPM_PACKAGE.md
P11_CLAWHUB_SUBMISSION.md
```

The goal is to make:

```text
@orca/opencode-plugin
@orca/openclaw-plugin
```

without bundling or reimplementing the Zig Orca CLI.
