# Phase 10 — Command Guard and Approvals

## Objective

Implement command risk classification, policy decisions, and interactive approval flows for shell commands and common command execution paths.

At the end of this phase, Aegis should classify risky commands, deny or ask according to policy, log command decisions, and support non-interactive CI behavior.

---

## Scope

Implement:

- Command parsing/classification.
- Command policy evaluation.
- Risk scoring.
- Interactive approval UI.
- Session-level approvals.
- CI non-interactive behavior.
- Shell wrapper foundations.
- PATH shim foundations.
- Command audit events.
- Tests for risky command patterns.

---

## Non-goals

Do not build a perfect shell parser. Start with a pragmatic classifier that catches high-signal dangerous patterns.

Do not implement OS-level process interception yet. Later platform backend phases will improve coverage.

---

## Command Risk Classes

| Class | Examples | Default |
|---|---|---|
| Safe inspection | `ls`, `cat package.json`, `git status` | allow |
| Build/test | `npm test`, `zig build test`, `cargo test` | allow/ask |
| Package install | `npm install`, `pip install` | ask |
| Network scripts | `curl`, `wget` | ask/deny |
| Destructive FS | `rm -rf`, `shred`, `find . -delete` | deny |
| Privilege escalation | `sudo`, `su`, `doas` | deny |
| Remote shell | `ssh`, `scp`, `nc` | ask/deny |
| Git remote write | `git push`, `git push --force` | ask/deny |
| Credential inspection | `cat ~/.ssh/*`, `cat .env` | deny |
| Obfuscation | base64 decode into shell, PowerShell encoded command | deny |

---

## Approval Prompt

Example:

```text
Aegis wants your approval

Command:
  npm install left-pad

Risk:
  Package install can execute lifecycle scripts and contact the network.

Policy:
  commands.default = ask

Options:
  [a] allow once
  [A] allow for this session
  [d] deny
  [?] explain risk
```

In `ci` mode, all `ask` decisions become deny.

---

## Shell Wrappers and PATH Shims

Add a shim directory per session:

```text
.aegis/sessions/<id>/shims/
```

Aegis can prepend this directory to PATH.

Initial shims can cover:

- `sh`
- `bash`
- `zsh`
- `fish` where feasible
- `cmd`
- `powershell`
- `pwsh`
- `curl`
- `wget`
- `git`
- `npm`
- `pnpm`
- `yarn`
- `pip`
- `python`
- `node`

MVP shims can call back into:

```bash
aegis shim exec -- <command> [args...]
```

The shim asks the policy engine before delegating to the real binary.

Implementation can start with a small set of shims and grow later.

---

## Command Events

Emit:

- `command_attempt`
- `command_allowed`
- `command_denied`
- `command_approval_requested`
- `user_approval`
- `user_denial`

Include:

- command string
- executable
- args
- risk class
- risk score
- matched rule
- whether approval was interactive

---

## Tests

Add tests for:

- `rm -rf /` denied.
- `curl https://x | sh` denied or ask.
- `sudo ls` denied.
- `git status` allowed.
- `git push` ask/deny.
- `npm install` ask.
- `powershell -EncodedCommand` denied.
- Base64 pipe shell denied.
- CI mode ask => deny.
- Session-level approval works.
- Command events are logged.

---

## Acceptance Criteria

- `zig build` succeeds.
- `zig build test` succeeds.
- Command classifier catches high-risk patterns.
- Policy rules override default behavior according to priority.
- Interactive approval works in a terminal.
- CI mode never waits for input.
- Command decisions are written to audit log.
- PATH shim infrastructure exists and works for at least a small set of commands.
- Docs state coverage limitations honestly.

---

## Codex Execution Prompt

```text
Implement Phase 10: Command Guard and Approvals.

Add command classification, risk scoring, command policy decisions, interactive approval prompts, CI non-interactive behavior, audit events, and initial shim infrastructure. Keep shell parsing pragmatic but tested against high-risk patterns.

Run:
- zig build
- zig build test
- manual smoke: use a shimmed command under aegis run
- manual smoke: verify CI mode denies ask decisions

Provide a handoff with files changed, tests run, known limitations, and security notes.
```

---

## Handoff Notes for Next Phase

The MCP proxy will reuse policy decisions, approval prompts, and audit logging. Keep approval APIs generic enough for MCP tool calls.


---

## Review Addendum — Shim Safety

Command shims must avoid infinite recursion. A shim must resolve the real executable by searching PATH after removing the shim directory or by storing the original executable path.

Command coverage must be documented as one of:

- direct Aegis command execution;
- shell wrapper;
- PATH shim;
- OS backend enforcement;
- observe-only.

CI mode must convert every `ask` decision to `deny` unless a specific allow rule exists.


---

## Reviewed Codex Context Requirement

When executing this phase with a Codex coding agent, provide this phase file together with `CODEX_AGENT_CONTEXT.md` and `CANONICAL_IMPLEMENTATION_DECISIONS.md`. For architecture-sensitive work, also provide `ARCHITECTURE_CONTRACTS.md`, `SECURITY_INVARIANTS.md`, and `PRODUCTION_READINESS_GATES.md`. If this phase conflicts with `CANONICAL_IMPLEMENTATION_DECISIONS.md`, the canonical decisions win.

This phase is not complete until:

- all phase acceptance criteria pass;
- relevant production gates pass;
- security invariants are preserved;
- tests are added for new behavior;
- limitations are documented honestly;
- the phase handoff is written.
