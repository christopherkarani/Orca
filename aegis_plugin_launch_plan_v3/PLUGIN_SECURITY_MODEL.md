# Plugin Security Model v3

## Core Statement

Aegis plugins are integration layers. They are not replacements for the Aegis runtime.

The strongest local protection remains:

```bash
aegis run -- <agent-command>
```

The plugin system adds:

- host-native skills
- slash commands
- lifecycle hooks
- Aegis CLI plugin commands
- policy explanations
- red-team shortcuts
- replay shortcuts

---

## Trust Boundaries

| Component | Trust Level | Notes |
|---|---:|---|
| Aegis core CLI | trusted | source of truth |
| Aegis plugin commands | trusted if built from Aegis | stable integration layer |
| Host plugin manifest | trusted if intentionally installed | should be reviewed |
| Hook input | untrusted | comes from agent/tool context |
| Prompt content | untrusted | may contain secrets or injection |
| Tool call | untrusted | may be model-generated |
| Host hook system | partial trust | only enforces what host supports |
| Separate repo workstreams | out of scope | must not be exposed by plugins |

---

## Security Invariants

1. Plugins call Aegis; they do not reimplement Aegis.
2. Raw secrets are never persisted.
3. Hook input is bounded.
4. Hook stdout is host-valid.
5. Human logs go to stderr.
6. CI mode never prompts.
7. Deny is not silently downgraded.
8. Separate safety-sensitive workstreams are not exposed.
9. Plugin demos do not require real LLMs, real secrets, or external network.
10. Docs do not overclaim.

---

## Required Warning

Every plugin README should include:

```text
The Aegis plugin adds native commands and lifecycle hooks for this agent host. For the strongest local protection, run the agent itself under Aegis with `aegis run -- <agent-command>`.
```
