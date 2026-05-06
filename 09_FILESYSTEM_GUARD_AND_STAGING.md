# Phase 09 — Filesystem Guard and Staged Writes

## Objective

Implement the filesystem protection and staged-write workflow.

At the end of this phase, Aegis should normalize paths, decide file read/write permissions using policy, block sensitive path access where feasible, stage workspace writes, and expose `aegis diff`, `aegis apply`, and `aegis discard`.

---

## Scope

Implement:

- Path normalization.
- Workspace-relative path handling.
- Sensitive path policy decisions.
- Staged write layout.
- Original-file capture.
- Diff command.
- Apply command.
- Discard command.
- Symlink escape checks.
- Filesystem audit events.
- Tests for path bypasses.

---

## Important Reality Check

Full transparent interception of arbitrary file reads/writes is platform-specific and will mature in later sandbox phases.

This phase should implement the filesystem policy/staging engine and use it wherever Aegis-controlled operations can route through it. Shell/PATH shims and platform backends will later increase coverage.

Do not overclaim that all file IO is intercepted on every OS yet.

---

## Staging Layout

```text
.aegis/
  sessions/
    <session-id>/
      events.jsonl
      summary.json
      summary.md
      staged/
        relative/path/to/file
      original/
        relative/path/to/file
      staging-index.json
```

`staging-index.json` should track:

- original path
- staged path
- original hash
- staged hash
- operation: create/update/delete
- timestamp
- actor/process if known

---

## Commands

### `aegis diff`

```bash
aegis diff
aegis diff --session last
aegis diff --file src/main.zig
```

Show unified diffs for staged changes.

### `aegis apply`

```bash
aegis apply
aegis apply --session last
aegis apply --file src/main.zig
```

Apply staged writes to the real workspace after safety checks.

### `aegis discard`

```bash
aegis discard
aegis discard --session last
```

Discard staged writes.

---

## Path Normalization Requirements

For each path decision:

1. Resolve relative path against process cwd or workspace root.
2. Normalize separators.
3. Resolve symlinks where possible.
4. Normalize case on case-insensitive platforms where feasible.
5. Normalize Unicode where feasible or document limitation.
6. Reject `..` traversal that escapes workspace.
7. Check whether final path is inside workspace.
8. Match policy rules.

---

## Default Protected Paths

Block reads by default:

- `.env`
- `.env.*`
- `~/.ssh/**`
- `~/.aws/**`
- `~/.gcloud/**`
- `~/.azure/**`
- `~/.config/gh/**`
- browser profile directories
- known private key filenames
- credential files

Block writes by default:

- `.git/**`
- `.aegis/**`
- shell startup files outside workspace
- executable/system paths outside workspace
- lockfiles may be ask-only depending on policy

---

## Audit Events

Emit:

- `file_read_attempt`
- `file_read_allowed`
- `file_read_denied`
- `file_write_attempt`
- `file_write_staged`
- `file_write_denied`
- `file_apply`
- `file_discard`

Include matched rule and reason.

---

## Tests

Add tests for:

- Relative path normalization.
- Absolute path normalization.
- Workspace containment.
- `..` traversal.
- Symlink to protected path.
- Deny `.env`.
- Deny `~/.ssh/id_ed25519`.
- Stage create.
- Stage update.
- Stage delete if implemented.
- Diff output.
- Apply output.
- Discard output.
- Staging index integrity.

---

## Acceptance Criteria

- `zig build` succeeds.
- `zig build test` succeeds.
- `aegis diff` works for staged files.
- `aegis apply` safely applies staged files.
- `aegis discard` removes staged files.
- Symlink escape test is blocked.
- Path policy decisions include explanations.
- Audit logs record file/staging decisions.
- Docs clearly state current interception coverage limitations.

---

## Codex Execution Prompt

```text
Implement Phase 09: Filesystem Guard and Staged Writes.

Build the path policy engine, staged write storage, staging index, diff/apply/discard commands, and filesystem audit events. Add path normalization and bypass tests, including symlink and traversal cases. Be honest about current interception coverage.

Run:
- zig build
- zig build test
- manual smoke: create a staged file, run aegis diff, apply, and discard

Provide a handoff with files changed, tests run, known limitations, and security notes.
```

---

## Handoff Notes for Next Phase

The command guard and shims will route file-affecting commands into this staging engine where possible. Keep staging APIs ergonomic.


---

## Review Addendum — Staging API and Enforcement Claims

This phase should create the staging engine even if transparent interception is incomplete. All user-facing output must distinguish:

- policy decision available;
- staging engine available;
- transparent filesystem enforcement active;
- wrapper-level or backend-limited coverage.

Do not claim arbitrary file writes are staged unless the current backend/shim actually routes them through the staging engine.


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
