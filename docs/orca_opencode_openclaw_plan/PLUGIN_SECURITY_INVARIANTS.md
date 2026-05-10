# Plugin Security Invariants

These invariants apply to OpenCode and OpenClaw plugin work.

## Do Not Add

Do not add:

- SaaS
- telemetry by default
- hosted dashboards
- monetization
- MCP server behavior
- `.mcp.json`
- drone plugin behavior
- drone skills
- drone demos
- operational drone-control instructions
- broad core Orca refactors
- Zig binary bundling inside npm packages
- npm install scripts that compile Zig
- npm install scripts that download and execute binaries

---

## Secret Safety

Plugins must not persist:

- API keys
- private keys
- tokens
- raw environment variables
- raw hook payloads containing secrets
- raw tool outputs by default

Synthetic/fake secrets are allowed only in tests.

All persistent logs must pass through Orca redaction.

---

## Distribution Safety

Plugin packages must not include:

- real secrets
- `.env`
- build artifacts not required for runtime
- planning files
- drone workstream files
- unrelated source trees
- generated local caches
- node_modules

---

## Host Safety

If the host supports blocking, use it carefully.

If the host only supports advisory hooks, document that limitation clearly.

CI mode must never prompt.

Install commands must not silently mutate user config unless the command is explicitly an install command and confirms the change.

---

## Drone Workstream Boundary

Drone work is out of scope.

The plugins must not:

- expose drone commands
- include drone demos
- add drone plugin skills
- contain operational drone-control instructions
- modify drone modules unless necessary to preserve tests

If drone tests exist, run them only if they are safe and do not operate hardware.
