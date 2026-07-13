# @orca-sec/pi-orca

Official Orca integration package for Pi. It intercepts built-in Pi tool calls:

| Tool | Path |
|------|------|
| `bash` | `orca evaluate --json --stdin` (daemon shell Evaluate; fail-closed when unavailable) |
| `write` / `edit` | `orca decide file` with `operation: write` (Zig `files.write`; path only) |
| `read` | `orca decide file` with `operation: read` (Zig `files.read`; path only) |
| `grep` / `find` / `ls` | Root preflight via `orca decide file`, followed by explicit per-call approval because descendant files are not individually evaluated |

Safe actions proceed. Denied actions are blocked before Pi runs them. Orca errors follow the configured unavailable-mode policy. Custom/MCP tools are **not** intercepted. Tool hooks alone do **not** provide process-level env isolation, network policy, or secretless execution — use `orca run` for that.

It also provides **Pi-only** credential capture from chat input: when you paste an API key into a prompt, the extension can store it under `.orca/dev-secrets.env` (with consent) and rewrite the prompt so the model never receives the raw secret. This is not a multi-host feature; Claude, Codex, OpenCode, Hermes, and OpenClaw adapters are out of scope for this package.

## Prerequisites

- Pi installed.
- Node.js 22.19 or newer.

## Install

```bash
pi install npm:@orca-sec/pi-orca
```

This installs the matching `@orca-sec/orca` CLI and daemon dependency. Do not mix `pi install ./orca-pi` with `pi install npm:@orca-sec/pi-orca`; remove one source before switching to avoid duplicate extension registration and binary ambiguity.

Local development or validation:

```bash
pi install ./orca-pi
pi -e ./orca-pi
```

## First Run

1. Install the package: `pi install npm:@orca-sec/pi-orca` (creates workspace policy via extension bootstrap).
2. **Recommended launch** for process-level env/network/secretless:

```bash
orca run -- pi
# or:
orca run --secretless --network ask -- pi
```

Extension hooks alone protect tool calls; they do **not** wrap the Pi process for env/network/secretless. Prefer `orca run` whenever you need those controls.

No per-session command is required after install. On session start, the extension quietly creates `.orca/policy.yaml` with the `generic-agent` preset when it is missing, then probes Orca health. The first protected tool call waits for this bootstrap while Pi startup remains non-blocking.

Run `/orca-setup` to repeat the Pi-only policy and health setup manually. It does
not run `orca start` or install plugins for other agent hosts.

Use `/orca-stop` to disable Orca protection for the current Pi session, and
`/orca-start` to re-enable it and verify Pi-only policy/health setup. These
commands only affect the in-memory Pi session; they do not uninstall the package,
remove policies, or start/stop other host plugins.

## Behavior

- Policy-protected built-in tools: `bash`, `write`, `edit`, and direct `read`. `grep`, `find`, and `ls` are approval-gated after root preflight because a root-only check cannot prove every descendant safe. Custom/MCP tools are not intercepted.
- `bash` is sent to `orca evaluate` as JSON over stdin (daemon shell path; `source.host=pi`).
- `write` / `edit` send the resolved path to `orca decide file` with `operation: write` (Zig policy; path only — content is not sent).
- `read` requires a non-empty `path` and uses `operation: read`.
- `grep` / `find` / `ls` preflight the tool's `path` (or cwd) as `operation: read`; even an allow requires explicit user approval, and noninteractive sessions block, because descendant files are not individually evaluated.
- Orca allow lets the tool proceed.
- Orca deny/block renders an inline Orca decision card (includes **rule id** when the policy match returns one) and returns `{ block: true, reason }` to Pi before the action can run.
- Orca error, malformed JSON, spawn failures, or timeouts use the configured unavailable mode (same fail-closed modes for bash and file tools).
- Session bypass (`/orca-stop`, `/orca-mode bypass on`) applies to all protected tools for the session.

### Credential capture from prompt (Pi only)

When interactive Pi receives user input that looks like a secret (for example an OpenAI-style `sk-…` key, Anthropic `sk-ant-…`, GitHub `ghp_` / `github_pat_`, or a secret-like `NAME=value` assignment), the extension:

1. **Detects** the span in the submitted input.
2. **Asks for consent** (`select`): store as an inferred env name, scrub without storing, or block the turn.
3. **Stores** (only on accept) by appending or updating `NAME=value` in workspace `.orca/dev-secrets.env` (create `.orca/` as needed; file mode `0600` when the platform allows). This path matches Orca’s env-file-dev broker validation (under `.orca/`, contains `dev`, ends with `.env`).
4. **Rewrites** the prompt so the raw secret is replaced with `$ENV_NAME` and short guidance to use the environment variable. The model must not receive the raw value.

Name inference:

| Pattern | Default env name |
|---------|------------------|
| `sk-…` (not `sk-ant-`) | `OPENAI_API_KEY` |
| `sk-ant-…` | `ANTHROPIC_API_KEY` |
| `ghp_` / `gho_` / `ghu_` / `ghs_` / `ghr_` / `github_pat_` | `GITHUB_TOKEN` |
| Secret-like `NAME=value` | `NAME` (uppercased) |

**Accept:** secret written; transformed text continues to the agent.  
**Decline (scrub only):** nothing written; secret spans still removed from the text sent to the model.  
**Block / dismiss:** turn is `handled` (no LLM); nothing stored.  
**Noninteractive** (`print` / `json` / `noninteractive`, or `hasUI !== true`): **fail closed** — no silent store; return `handled` with a clear message that interactive capture is required.

**Session bash bypass** (`/orca-stop`): bash evaluation is skipped, but secret capture still scrubs or blocks secrets so they are not leaked to the model by default.

**Disable:** set `ORCA_PI_SECRET_CAPTURE=false` to turn off capture and context scrubbing.

**What the agent process actually receives:**

- The rewritten prompt references `$OPENAI_API_KEY` (or the chosen name); it does not include the raw secret.
- On store success, the extension sets `process.env[NAME]` for the **current Pi/extension Node process only**. Child tool environments are not automatically rewritten. Load `.orca/dev-secrets.env` into the shell before launching Pi, or use an Orca secretless/env-broker workflow when you need tools to resolve credentials without pasting them into chat.
- Defense in depth: the `context` hook scrubs any remaining secret-like spans in user messages before each LLM call (no re-prompt to store on history).

Unavailable modes (`ORCA_PI_MODE`):

- `auto` (**default**): interactive Pi sessions ask; noninteractive/json/print sessions block. Does not silently fail open.
- `ask`: prompt with Block, Run once anyway, Disable Orca for this session, or Show repair instructions.
- `noninteractive-block`: block and show repair guidance.
- `strict`: always block on Orca errors, and disables interactive "Run once anyway" by default. **Recommended for production.**
- `allow-with-warning`: allow but warn that Orca is degraded. **Never the default.**

Once-bypass (`Run once anyway`) is an interactive escape hatch. It is disabled when `ORCA_PI_MODE=strict` (unless `ORCA_PI_ALLOW_ONCE=true`) or when `ORCA_PI_ALLOW_ONCE=false`. Every once-bypass emits a redacted `orca.audit` transcript event (`event: orca_once_bypass`) and a warning notification. If the host cannot record that audit event, Orca keeps the action blocked.

Change mode in Pi:

```text
/orca-mode
/orca-mode strict
/orca-mode allow-with-warning
/orca-mode bypass on
/orca-mode bypass off
```

Session bypass is in-memory only. It is cleared when the Pi session shuts down or
reloads. `/orca-stop` turns this bypass on; `/orca-start` turns it off and reruns
the Pi health check.

Interactive `ask` mode pauses the bash tool call until the user chooses an
explicit action. Its decision card remains visible while the prompt is open.

The status line reports only Orca state: `orca ready`, `orca missing`,
`orca degraded`, or `orca bypass`.

Set `ORCA_PI_AUTO_SETUP=false` to disable session bootstrap. The package-managed runtime is used by default; set `ORCA_PI_USE_PATH=true` only when you explicitly trust a compatible PATH installation. `ORCA_BIN=/absolute/path/to/orca` remains the highest-priority override when the file is executable.

## Troubleshooting

Orca not found:

- Reinstall `npm:@orca-sec/pi-orca` so its version-locked runtime dependency can provision both binaries.
- If overriding package resolution, confirm `ORCA_BIN` points to an executable Orca binary.

Daemon unavailable:

- Run `/orca-setup`, then `/orca-doctor`.
- The daemon normally starts automatically on the first `orca evaluate` call.

Protocol incompatible:

- Update Orca and rerun `/orca-doctor`.
- The extension fails closed by default in noninteractive mode.

Command unexpectedly blocked:

- Read the Orca reason.
- Do not rewrite the command to bypass Orca.
- Ask the user whether to use an Orca allowlist or an explicit allow-once flow.

## Security Notes

- The extension does not execute the agent's bash command while evaluating it.
- Orca is invoked with `spawn(file, args, { shell: false })`; no shell interpolation is used.
- Request JSON is passed through stdin.
- Raw commands are not logged by default.
- Block messages use Orca's redacted reason and basic token redaction (including common API key shapes).
- Noninteractive mode fails closed by default.
- Session bypass is not persisted.
- Session bypass is keyed to the Pi session id when Pi exposes one.
- Malformed `bash` tool-call payloads fail closed.
- Child process output is bounded before parsing.
- Unlisted tools are not blocked by the evaluate/decide paths.
- Credential capture never writes raw secrets into `policy.yaml`, decision cards, or notify text.
- Credential capture never auto-stores without interactive consent.
- Capture is **Pi only**; other agent hosts are not covered by this package.

## Version Compatibility

This package targets Pi packages using `pi.extensions` / `pi.skills` manifests and Pi extension APIs with `tool_call`, `registerCommand`, `ctx.cwd`, `ctx.mode`, and `ctx.hasUI`.

It targets Orca CLI builds exposing `orca evaluate --json --stdin` with schema version `1` and decisions `allow`, `deny`, or `error`.

## Known Limitations

- Slash commands (`/orca-setup`, `/orca-start`, `/orca-stop`, `/orca-doctor`,
  `/orca-mode`) are registered at extension load time. In Pi noninteractive,
  print, or json modes, command output may not be visible even when registration
  succeeds. Validate slash commands in an interactive Pi session or via unit
  tests.
- Session bypass is in-memory only and clears when the Pi session ends or reloads.
- Built-in Pi `bash`, `write`, `edit`, and direct `read` are policy-protected. `grep`, `find`, and `ls` require explicit approval after root preflight; custom/MCP tools are not intercepted.
- File protection uses Zig policy.yaml (`files.read` / `files.write`); it is not the same engine as daemon pack rules for shell.
- Process-level env isolation, network policy, and secretless require `orca run [--secretless] [--network …] -- pi …`; the extension alone does not provide them.
- Pi hosts without the transcript `sendMessage` API fall back to a docked deny
  card. Supported Pi versions use the inline conversation surface.
- **Credential capture is Pi only.** Other hosts (Claude, Codex, OpenCode, Hermes, OpenClaw) are not implemented here.
- Prior session history already on disk may still contain secrets pasted before capture was available or before a transform ran; capture does not rewrite old transcript files.
- Detection is pattern-based and can miss unusual secret formats or produce rare false positives; users can block the turn or set `ORCA_PI_SECRET_CAPTURE=false`.
- Storing into `.orca/dev-secrets.env` does not by itself inject that file into every tool’s environment; see Behavior above.

## Smoke Test Checklist

1. `./zig-out/bin/orca evaluate --json --stdin` allows `git status`.
2. `./zig-out/bin/orca evaluate --json --stdin` denies `rm -rf /`.
3. `./zig-out/bin/orca evaluate --json --stdin` returns exit `64` for invalid schema.
4. `cd orca-pi && npm test`.
5. `cd orca-pi && npm pack --dry-run`.
6. `pi -e ./orca-pi`.
7. Safe bash tool call proceeds.
8. Dangerous bash tool call blocks.
9. Orca unavailable interactive mode asks.
10. Orca unavailable noninteractive mode blocks.
11. `/orca-setup`, `/orca-start`, `/orca-stop`, `/orca-doctor`, and `/orca-mode` work.
12. Paste a synthetic key (e.g. `sk-fakeSyntheticOpenAIKey1234567890`) into interactive Pi → confirm store → prompt is scrubbed; `.orca/dev-secrets.env` contains `OPENAI_API_KEY=…` without the raw key appearing in UI notifications.
13. Same paste → decline store → nothing written; model text has no raw key.
14. Same paste in `print`/`json` mode → fail closed (no store, turn handled).
12. `pi install ./orca-pi`.
13. `pi list` shows `@orca-sec/pi-orca` or the local package source.
