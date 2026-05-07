# Schemas

Versioned v1 JSON Schemas:

- `policy-v1.json`: Aegis policy file shape for `version: 1`.
- `event-v1.json`: audit `events.jsonl` record shape for `version: 1`.
- `mcp-manifest-v1.json`: stdio MCP manifest shape for `version: 1`.

The runtime parsers reject unknown keys for these v1 formats. Future breaking schema changes require a new version and migration notes.
