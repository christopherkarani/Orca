# Orca Host Plugin Contract

## Core Contract

Every Orca host plugin must be a thin wrapper around the Orca CLI.

Plugins call:

```bash
orca decide ...
orca hook ...
orca plugin doctor ...
```

Plugins must not reimplement:

- policy evaluation
- secret redaction
- audit logging
- replay
- command classification
- path/file risk classification
- host-independent security logic

---

## Required Runtime Assumption

The plugin package assumes the Orca CLI is installed and available on `PATH`:

```bash
orca --help
orca doctor
```

If `orca` is missing, the plugin must fail gracefully and tell the user to install Orca.

Do not compile Orca from Zig during plugin installation.

Do not download binaries during plugin installation in this phase.

Do not bundle the Orca Zig binary inside npm plugin packages yet.

---

## Required Host Commands

### OpenCode

```bash
orca plugin doctor opencode
orca plugin install opencode --dry-run
orca hook opencode tool.execute.before
orca hook opencode permission.asked
orca decide command --json ...
```

### OpenClaw

```bash
orca plugin doctor openclaw
orca plugin install openclaw --dry-run
orca hook openclaw <event>
orca decide command --json ...
```

---

## Output Rules

- Machine-readable outputs must be valid JSON.
- Human/debug messages must not pollute host protocol stdout.
- Secrets must be redacted before logging.
- CI/non-interactive behavior must never prompt.
- Dangerous or unsupported host capabilities must be reported honestly.

---

## Host Limitation Rule

The plugin must not claim stronger enforcement than the host supports.

Acceptable:

```text
The OpenCode plugin hooks call Orca before selected tool executions.
```

Not acceptable:

```text
The OpenCode plugin fully sandboxes OpenCode.
```

Acceptable:

```text
The OpenClaw plugin is a runtime guardrail wrapper around Orca CLI decisions.
```

Not acceptable:

```text
The OpenClaw plugin prevents all risky OpenClaw behavior.
```
