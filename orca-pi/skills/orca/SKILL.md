---
name: orca
description: Use when Pi bash tool calls are protected by Orca runtime guardrails.
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

Installation requires one command: `pi install npm:@orca-sec/pi-orca`. Do not mix that npm install with `pi install ./orca-pi`, which can register duplicate extensions and create binary ambiguity.

If Orca is unavailable, prefer repair first: run `/orca-setup`, then `/orca-doctor`. `/orca-setup` only ensures the workspace policy and probes health; it never installs plugins for other hosts. The daemon starts automatically on the first protected evaluation.
