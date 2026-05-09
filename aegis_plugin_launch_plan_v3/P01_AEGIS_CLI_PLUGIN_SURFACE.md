# P01 — Aegis CLI Plugin Surface

## Status

This phase is already complete if the repo now has a minimal `aegis plugin` namespace.

---

## Objective

Add the minimal Aegis CLI plugin namespace needed before building host plugins.

---

## Correct Scope

P01 should include:

```bash
aegis plugin doctor
aegis plugin doctor codex
aegis plugin doctor claude
aegis plugin manifest codex
aegis plugin manifest claude
aegis plugin manifest all
aegis plugin install codex --dry-run
aegis plugin install claude --dry-run
aegis plugin install all --dry-run
```

P01 should not include:

```bash
aegis plugin mcp-server
aegis decide
aegis hook
drone plugin features
Codex plugin package
Claude Code plugin package
```

`aegis decide` and `aegis hook` come in P02.

---

## Drone Handling

P01 should not add drone features.

If drone files were detected in P00, plugin doctor may include a simple note:

```text
Separate drone workstream detected; plugin phase does not modify drone functionality.
```

No operational drone-control instructions should appear.

---

## P01 Completion Checklist

- `aegis plugin doctor` works.
- `aegis plugin doctor --json` works.
- `aegis plugin manifest codex` works.
- `aegis plugin manifest claude` works.
- `aegis plugin install codex --dry-run` works.
- `aegis plugin install claude --dry-run` works.
- No MCP server behavior was added.
- No drone plugin behavior was added.
- No secrets leak.
- Existing Aegis tests pass.
- Existing drone tests, if present, pass or safe reasons are documented.
