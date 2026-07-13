---
name: orca
description: Use when Pi bash tool calls are protected by Orca runtime guardrails, or when secrets were captured from a Pi prompt.
---

# Orca Guardrails For Pi

Orca evaluates Pi bash tool calls before they run. Treat an Orca block as a security decision, not as a formatting problem to route around.

When Orca blocks a command:

- Explain the block reason to the user without restating sensitive command contents.
- Ask the user how they want to proceed.
- Do not bypass Orca by obfuscating, splitting, encoding, rewriting, or indirectly executing the same dangerous command.
- Use `/orca-doctor` for setup or daemon issues.
- Use Orca allowlist or allow-once workflows when they are available and explicitly approved by the user.
- Never advise disabling Orca casually. Session bypass is only for informed, user-approved exceptions.

## Credential capture from prompt (Pi only)

If the user pastes an API key or other secret into chat, the Orca Pi extension may intercept the input, ask for consent, store the value under `.orca/dev-secrets.env`, and rewrite the prompt to reference `$ENV_NAME` instead of the raw secret.

When you see a rewritten prompt that mentions `$OPENAI_API_KEY`, `$ANTHROPIC_API_KEY`, `$GITHUB_TOKEN`, or similar:

- Use the environment variable name. Do **not** ask the user to re-paste the raw secret.
- Do **not** print, log, or echo secret values.
- Prefer tools and workflows that already load workspace/dev secrets or Orca secretless execution when available.
- This behavior is **Pi only**. Do not assume the same capture exists on Claude, Codex, OpenCode, Hermes, or OpenClaw.

If capture is blocked in noninteractive mode, tell the user to re-run in interactive Pi or to set the env var outside chat.

Installation requires one command: `pi install npm:@orca-sec/pi-orca`. Do not mix that npm install with `pi install ./orca-pi`, which can register duplicate extensions and create binary ambiguity.

If Orca is unavailable, prefer repair first: run `/orca-setup`, then `/orca-doctor`. `/orca-setup` only ensures the workspace policy and probes health; it never installs plugins for other hosts. The daemon starts automatically on the first protected evaluation.
