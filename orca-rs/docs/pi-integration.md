# Pi Integration

Last updated: 2026-06-01

This document shows how to connect orca to the [Pi coding agent](https://github.com/earendil-works/pi)
(`earendil-works/pi`). Pi is not auto-configured by orca's installer — Pi's
guardrails are deliberately user-authored as small TypeScript *extensions* — so
this is the official "directed implementation" recipe requested in
[issue #133](https://github.com/christopherkarani/Orca/issues/133).
Drop in the extension below and Pi will route every shell command through orca
before it runs.

## How Pi interception works

Pi extensions register handlers with `pi.on("tool_call", …)`. The handler runs
*before* the tool executes, receives the tool name and (mutable) input, and can
veto execution by returning `{ block: true, reason }`:

```ts
export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    // event.toolName === "bash", event.input.command === "<the command>"
    // return { block: true, reason } to deny
  });
}
```

Extensions auto-load from `~/.pi/agent/extensions/*.ts` (global) or
`.pi/extensions/*.ts` (project-local). See Pi's
[extensions docs](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md).

## Which orca entrypoint to call

orca exposes a stable, agent-friendly decision API via **robot mode**, which is
the right fit for an extension because the decision is carried by the **exit
code** and a machine-readable JSON payload — no hook-protocol envelope to
construct:

```bash
orca --robot test "<command>"
```

- **exit 0** → allowed
- **exit 1** → denied (JSON on stdout carries `reason`, `rule_id`, `pack_id`,
  `explanation`, `remediation`, …)
- **exit ≥ 3** → a orca error (config/parse/IO). Treat these as *fail-open* (let
  the command proceed) or *fail-closed* (block) per your risk tolerance; the
  example below fails open so a broken orca install never wedges Pi, matching the
  default posture of the other orca integrations.

(See [`docs/adr-002-robot-mode-api.md`](adr-002-robot-mode-api.md) for the full
exit-code contract.)

> Why not pipe a hook JSON payload to bare `orca`? You can — `printf
> '{"tool_name":"Bash","tool_input":{"command":"…"}}' | orca` works too — but in
> that mode orca always exits 0 and puts the decision inside
> `hookSpecificOutput.permissionDecision`, so the extension would have to parse
> JSON just to learn allow vs. deny. `--robot test` makes the exit code
> authoritative, which is simpler and less error-prone.

## The extension

Save this as `~/.pi/agent/extensions/orca-guard.ts` (global) or
`<repo>/.pi/extensions/orca-guard.ts` (per project):

```ts
// orca-guard.ts — block destructive shell commands with orca
// https://github.com/christopherkarani/Orca
import { spawn } from "node:child_process";

const ORCA_BIN = process.env.ORCA_BIN ?? "orca";

function orcaDecision(command: string): Promise<{ deny: boolean; reason: string }> {
  return new Promise((resolve) => {
    const child = spawn(ORCA_BIN, ["--robot", "test", command], {
      stdio: ["ignore", "pipe", "ignore"],
    });

    let stdout = "";
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });

    // Fail open if orca can't be found / spawned, so a broken install never
    // wedges Pi. Flip this to resolve({ deny: true, ... }) to fail closed.
    child.on("error", () => resolve({ deny: false, reason: "" }));

    child.on("close", (code) => {
      if (code === 1) {
        // Denied. The reason lives in the robot-mode JSON.
        let reason = "Blocked by orca (destructive command).";
        try {
          const parsed = JSON.parse(stdout);
          if (parsed?.reason) reason = parsed.reason;
          if (parsed?.rule_id) reason += ` [${parsed.rule_id}]`;
        } catch {
          /* keep the default reason */
        }
        resolve({ deny: true, reason });
      } else {
        // 0 = allowed; >=3 = orca error -> fail open.
        resolve({ deny: false, reason: "" });
      }
    });
  });
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event) => {
    if (event.toolName !== "bash") return;
    const command = String(event.input?.command ?? "");
    if (!command.trim()) return;

    const { deny, reason } = await orcaDecision(command);
    if (deny) {
      return { block: true, reason };
    }
  });
}
```

Adjust the tool-name check (`event.toolName !== "bash"`) if your Pi build names
its shell tool differently, and set `ORCA_BIN` if `orca` is not on Pi's `PATH`
(e.g. `~/.local/bin/orca`).

## Verifying it works

1. Install orca (`curl … | bash`) and confirm `orca --version` works in the same
   shell environment Pi runs in.
2. Drop `orca-guard.ts` into one of the discovery paths above (or pass it
   explicitly: `pi -e ./orca-guard.ts`).
3. Ask Pi to run a known-destructive command, e.g. `git reset --hard HEAD~1`.
   Pi should refuse with the orca reason instead of executing it.
4. Sanity-check the underlying decision directly:

   ```bash
   orca --robot test "git reset --hard HEAD~1"; echo "exit=$?"   # exit=1 (denied)
   orca --robot test "ls -la"; echo "exit=$?"                    # exit=0 (allowed)
   ```

## Limitations

Like every PreToolUse-style guardrail (Claude Code, Codex, Gemini, …), this
gates the *tool call*. A sufficiently determined model can still write a script
to disk and execute that, or use a tool other than `bash`. For a hard boundary,
run Pi inside a container or sandbox. orca's pre-commit `scan` mode
([`docs/scan-precommit-guide.md`](scan-precommit-guide.md)) is a useful
second layer for the git path.
