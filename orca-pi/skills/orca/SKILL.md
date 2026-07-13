---
name: orca
description: Use when Pi bash/write/edit/read/discovery tool calls are protected by Orca runtime guardrails, or when secrets were captured from a Pi prompt.
---

# Orca Guardrails For Pi

Orca evaluates Pi **built-in** tools before they run:

| Tool | Path |
|------|------|
| `bash` | daemon Evaluate (`orca evaluate --json --stdin`, `source.host=pi`) |
| `write` / `edit` | Zig `orca decide file` with `operation: write` |
| `read` | Zig `orca decide file` with `operation: read` |
| `grep` / `find` / `ls` | Root preflight plus explicit approval; descendants are not individually evaluated |

Custom/MCP tools are **not** intercepted. Treat an Orca block as a security decision, not as a formatting problem to route around.

`grep`, `find`, and `ls` remain approval-gated even when the root preflight allows them. Do not describe a broad root check as proof that every traversed file is safe.

**Process-level env/network/secretless** are **not** provided by the extension alone. Launch Pi under Orca:

```bash
orca run -- pi
orca run --secretless --network ask -- pi
```

Install: `pi install npm:@orca-sec/pi-orca`. Do not mix that with `pi install ./orca-pi`.

When Orca blocks a command or file action:

- Explain the block reason to the user without restating sensitive command or path contents.
- Surface the **rule id** when present (decision cards include `rule …`).
- Ask the user how they want to proceed.
- Do not bypass Orca by obfuscating, splitting, encoding, rewriting, or indirectly executing the same dangerous action.
- Use `/orca-doctor` for setup or daemon issues (output includes coverage).
- Use Orca allowlist or allow-once workflows when they are available and explicitly approved by the user.
- Never advise disabling Orca casually. Session bypass is only for informed, user-approved exceptions.

## Defaults

- Default unavailable mode: `ORCA_PI_MODE=auto` (interactive ask; noninteractive block). Does not silently fail open.
- Production: prefer `ORCA_PI_MODE=strict` or `/orca-mode strict`.
- `allow-with-warning` is never the default.

## Credential capture from prompt (Pi only)

If the user pastes an API key or other secret into chat, the Orca Pi extension may intercept the input, ask for consent, store the value under `.orca/dev-secrets.env`, and rewrite the prompt to reference `$ENV_NAME` instead of the raw secret.

When you see a rewritten prompt that mentions `$OPENAI_API_KEY`, `$ANTHROPIC_API_KEY`, `$GITHUB_TOKEN`, or similar:

- Use the environment variable name. Do **not** ask the user to re-paste the raw secret.
- Do **not** print, log, or echo secret values.
- Prefer tools and workflows that already load workspace/dev secrets or Orca secretless execution when available (`orca run --secretless -- pi …`).
- This behavior is **Pi only**. Do not assume the same capture exists on Claude, Codex, OpenCode, Hermes, or OpenClaw.

If capture is blocked in noninteractive mode, tell the user to re-run in interactive Pi or to set the env var outside chat.

If Orca is unavailable, prefer repair first: run `/orca-setup`, then `/orca-doctor`. `/orca-setup` only ensures the workspace policy and probes health; it never installs plugins for other hosts. The daemon starts automatically on the first protected shell evaluation.
