# Phase 04 — CLI Skeleton

## Objective

Build the full command-line skeleton for Aegis.

At the end of this phase, all planned commands should exist, parse basic options, print useful help, and return correct exit codes even if most commands still use placeholder behavior.

---

## Scope

Implement CLI dispatch for:

- `aegis run`
- `aegis init`
- `aegis doctor`
- `aegis policy`
- `aegis replay`
- `aegis diff`
- `aegis apply`
- `aegis discard`
- `aegis mcp`
- `aegis redteam`
- `aegis version`
- `aegis help`

---

## Non-goals

Do not implement actual process supervision, policy matching, MCP proxying, staging, or red-team execution yet.

---

## CLI Design

### General

```bash
aegis <command> [options]
aegis help
aegis help <command>
aegis --help
aegis --version
```

All commands should support `--help`.

### Exit Codes

Use simple conventional exit codes:

| Code | Meaning |
|---:|---|
| 0 | Success |
| 1 | General error |
| 2 | CLI usage error |
| 3 | Policy/security denial |
| 4 | Unsupported platform feature |
| 5 | Child process failure |
| 6 | Test/redteam failure |

Create named constants in a CLI module.

### Command Stubs

Each command should be structured for future implementation.

Example:

```zig
pub fn runCommand(allocator: Allocator, args: []const []const u8) !i32 {
    // parse options
    // call core/supervisor later
    // currently print "not implemented"
}
```

A placeholder command must be honest:

```text
aegis replay: not implemented yet
```

It must not pretend to enforce security.

---

## `aegis init`

For this phase, `init` can create `.aegis/policy.yaml` from a built-in minimal template.

Support:

```bash
aegis init
aegis init --mode strict
aegis init --mode ask
aegis init --mode observe
aegis init --ci
```

Acceptance for `init`:

- Creates `.aegis/`.
- Creates `.aegis/policy.yaml`.
- Does not overwrite existing policy unless `--force` is provided.
- Writes a minimal valid-looking policy file.

---

## `aegis doctor`

For this phase, `doctor` should print platform and capability stubs from `core/platform.zig`.

Example:

```text
Aegis Doctor

OS: linux
Version: 0.0.0-dev

Capabilities:
  process supervision: planned
  env filtering: planned
  staged writes: planned
  mcp stdio proxy: planned
  network enforcement: planned
  strong sandbox: planned
```

Later phases will replace `planned` with real capability statuses.

---

## Tests

Add tests or golden fixtures for:

- Top-level help.
- Version output.
- Unknown command.
- Command-specific help.
- `init` creates policy.
- `init` refuses overwrite without `--force`.
- `doctor` prints OS and capabilities.

If direct CLI integration tests are hard in Zig, create testable pure functions for command parsing and output rendering.

---

## Acceptance Criteria

- `zig build` succeeds.
- `zig build test` succeeds.
- `aegis --help` works.
- `aegis help run` works.
- `aegis version` works.
- `aegis init --mode strict` creates `.aegis/policy.yaml`.
- `aegis doctor` reports OS and planned capabilities.
- Unknown commands return usage error.

---

## Codex Execution Prompt

```text
Implement Phase 04: CLI Skeleton.

Build command dispatch and help for all planned Aegis commands. Add basic option parsing, exit code constants, command-specific help, `init` policy creation, and `doctor` capability reporting. Keep unimplemented commands honest. Do not implement real enforcement yet.

Run:
- zig build
- zig build test
- manual CLI smoke tests for help/version/init/doctor

Provide a handoff with files changed, tests run, known limitations, and next-phase notes.
```

---

## Handoff Notes for Next Phase

The session supervisor phase will replace the placeholder `run` implementation. Ensure `run` command option parsing is easy to extend.


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
