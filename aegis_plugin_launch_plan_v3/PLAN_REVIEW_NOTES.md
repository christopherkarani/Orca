# Plan Review Notes

## Why v3 Exists

The v2 plan accidentally treated MCP and drone work as plugin dependencies. That was wrong.

The plugin work should stay focused on:

- Aegis CLI plugin namespace
- host hook/decision API
- Codex plugin
- Claude Code plugin
- plugin tests
- plugin packaging
- launch

MCP is optional future work.

Drone work is a separate workstream and only appears as a non-regression guardrail.

---

## What to Check Before Starting P02

Confirm P01 did not add:

- `aegis plugin mcp-server`
- `aegis decide drone`
- drone plugin skills
- drone plugin docs
- drone demos

If any were added, either remove them or isolate them behind clearly documented future-work stubs before P02.

---

## Next Phase

Start:

```text
P02_AGENT_HOST_INTEGRATION_API.md
```

Recommended effort:

```text
High
```
