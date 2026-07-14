# Orca OpenClaw Plugin

OpenClaw plugin wrapper for Orca runtime guardrails.

## Protection first (read this)

| Path | Grade | Blocks tools? |
|------|-------|---------------|
| `orca run -- openclaw` | **`wrapper`** (supported) | Yes — process launched under Orca |
| npm / ClawHub / CLI-metadata plugin install | **`unprotected`** | **No** — OpenClaw wires `api.on` to a no-op; hooks never fire |
| Local / bundled plugin path | **unverified `hook`** | Only if the host actually registers and honors hooks (not proven by install alone) |

**Never treat “plugin installed” as protection.** For mediation you can rely on today, use:

```bash
orca run -- openclaw
```

Grades: see the main README [protection grades](../../README.md#protection-grades) and `docs/compatibility.md`.

## What this plugin does

This plugin adds Orca-native lifecycle hooks to OpenClaw when the host exposes real `api.on` registration. It calls the Orca CLI for policy checks, audit logging, and runtime safety decisions without duplicating policy logic.

The Orca CLI remains the source of truth for all policy decisions. When hooks do not fire (npm/ClawHub), this package cannot enforce anything.

## Prerequisites

- Orca CLI built and available in PATH (run `orca doctor` to verify)
- OpenClaw host installed

Orca is not bundled into this plugin package. Fast setup (install plumbing, not enforcement proof):

```bash
./scripts/install-orca-plugin.sh openclaw project
```

Windows:

```powershell
.\scripts\install-orca-plugin.ps1 openclaw project
```

## Supported protection path

```bash
orca run -- openclaw
```

This is the primary recommended path (grade **`wrapper`**). It does not depend on OpenClaw plugin hooks firing.

## Install from local path (optional plumbing)

If you have OpenClaw installed locally:

```bash
openclaw plugins install ./integrations/openclaw-plugin
```

Or:

```bash
orca plugin install openclaw
```

Local install is still **not** a claim of live **`hook`** enforcement. Prefer `orca run -- openclaw`. Confirm with `orca plugin doctor openclaw` (installed ≠ protected).

## Install from npm / ClawHub — unprotected

These paths install metadata and may look successful, but in current OpenClaw **CLI-metadata** mode `api.on` is a no-op. Lifecycle hooks **do not fire**. Classification: **`unprotected`**.

```bash
# NOT recommended for security — unprotected (hooks no-op)
openclaw plugins install npm:orca-openclaw-plugin
openclaw plugins install clawhub:orca-openclaw-plugin
```

`--dangerously-force-unsafe-install` only bypasses OpenClaw’s security scanner so the package can load; it does **not** enable hook enforcement. Do not use it as a security install step.

For submission details (packaging only), see `docs/integrations/openclaw-clawhub.md`.

## Verify install (honest doctor)

```bash
orca plugin doctor openclaw
```

Doctor reports host binary, extension paths, and whether a host plugin appears installed. **Installed does not mean protected.** Expect an enforcement note that npm/ClawHub is **`unprotected`** and that the preferred path is `orca run -- openclaw`.

## Hooks included

When hooks actually register (not npm CLI-metadata), the plugin calls `orca hook openclaw <event>`:

| Event | When it fires | Behavior |
|-------|---------------|----------|
| `session.start` | At the start of an OpenClaw session | Informational (readiness log) |
| `tool.before` | Before OpenClaw invokes a tool | **Blocking when hooks fire** — empty/malformed/`ask` fail closed to block |
| `tool.after` | After OpenClaw finishes using a tool | Informational (audit only) |
| `session.end` | When the session ends | Informational (audit only) |

OpenClaw does not currently expose dedicated permission lifecycle hooks to this plugin. Permission-like blocking is handled through `tool.before` **only if** `before_tool_call` runs.

**Do not claim `tool.before` is blocking for npm/ClawHub installs** — those installs are **`unprotected`**.

## How hooks call Orca

Each hook sends a JSON payload to `orca hook openclaw <event>` via stdin and reads a JSON decision from stdout. On the blocking path (`tool.before`):

- empty or whitespace-only stdout → **block**
- JSON parse failure or missing `decision` → **block**
- `decision: "ask"` or unrecognized → **block** (no OpenClaw ask UX)
- `decision: "block"` → block
- `decision: "allow"` / `"warn"` → allow (warn logs only)

Human-readable logs go to stderr.

Example payload for `tool.before`:

```json
{
  "version": 1,
  "host": "openclaw",
  "event": "tool.before",
  "payload": {
    "tool": "shell",
    "command": "git status"
  },
  "session_id": "session-uuid",
  "timestamp": "2026-01-01T00:00:00Z"
}
```

Example response:

```json
{
  "version": 1,
  "decision": "allow",
  "risk": "low",
  "category": "command",
  "reason": "policy_allow",
  "message": "Allowed by policy"
}
```

If the decision is `block` (including fail-closed cases), the plugin returns a block result that prevents the tool from executing **when the host honors the hook**.

## Run redteam

```bash
orca redteam --ci
```

## Replay sessions

```bash
orca replay --session last --verify
```

## Uninstall

Remove the plugin from your OpenClaw configuration:

```bash
openclaw plugins uninstall orca
```

This plugin does not mutate host configuration, so uninstalling is safe.

## Known limitations

- **npm/ClawHub/global installs are `unprotected`.** OpenClaw loads them with `registrationMode: "cli-metadata"`, where `api.on` is a no-op. Hooks never fire; the plugin cannot block tools. Supported protection: `orca run -- openclaw` (**`wrapper`**).
- Local/bundled install does not by itself prove **`hook`** grade without live-host E2E.
- Hooks are advisory for informational events; blocking depends on OpenClaw honoring hook return values.
- Plugin installation depends on OpenClaw version and plugin loading mechanism.
- No telemetry is collected.
- npm package name prepared: `orca-openclaw-plugin`. ClawHub package published for distribution — distribution ≠ enforcement.

## Security model

- This plugin calls the Orca CLI; it does not reimplement policy logic.
- No raw secrets are persisted in plugin files.
- Secrets are redacted from payloads before sending to Orca (keys matching `password`, `token`, `secret`, `api_key`, etc. are replaced with `[REDACTED]`).
- Blocking hooks fail closed on empty/malformed/`ask` responses.
- Human logs go to stderr.
- CI mode never prompts.
- This plugin does not claim stronger enforcement than OpenClaw hooks actually provide.
- Non-enforcing installs are labeled **`unprotected`**, not soft-warned “green” installs.

## No MCP server behavior

The OpenClaw plugin does not add MCP server behavior or drone-specific plugin features.

## OpenClaw Security Scan Notice

OpenClaw’s plugin security scanner may block packages that use `child_process`. The Orca plugin needs that only to call the local `orca` binary.

Bypassing the scanner (for example with `--dangerously-force-unsafe-install`) is **not** a security recommendation and does **not** turn an npm install into an enforcing install. Prefer `orca run -- openclaw`.
