# Aegis CLI Plugin Contract v3

## Purpose

This document defines what it means for the Aegis CLI to become a plugin surface.

Aegis is not only a binary that host plugins call. It provides stable plugin commands and schemas so Codex, Claude Code, and future agent hosts can integrate with it.

---

## Required Commands

P01:

```bash
aegis plugin doctor
aegis plugin manifest <host>
aegis plugin install <host>
```

P02:

```bash
aegis decide <kind>
aegis hook <host> <event>
```

---

## Not Required for This Plugin Plan

This plan does not require:

```bash
aegis plugin mcp-server
aegis decide drone
```

Those can be future work if explicitly needed.

---

## Plugin Invariants

1. The Aegis CLI is the source of truth.
2. Host plugins do not duplicate the policy engine.
3. All plugin input is untrusted.
4. All plugin output is bounded.
5. Redaction happens before persistence.
6. Hook stdout must be valid for the host.
7. Human logs go to stderr.
8. CI mode never prompts.
9. Separate safety-sensitive workstreams, including drone work, are not exposed by plugins.
10. Plugins never claim stronger enforcement than the host supports.

---

## Host Plugins

Host plugins should call:

```bash
aegis plugin doctor <host>
aegis hook <host> <event>
aegis decide <kind>
aegis redteam
aegis replay
```

They should not reimplement:

- policy matching
- secret redaction
- command classification
- file/path risk classification
- audit persistence
