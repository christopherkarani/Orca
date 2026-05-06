# Phase 02 — Repository Bootstrap

## Objective

Create the initial Zig repository structure for Aegis.

At the end of this phase, the repository should build, run a minimal CLI, run tests, and contain the directory/module layout needed by future phases.

---

## Scope

Implement:

- `build.zig`
- `build.zig.zon`
- `src/main.zig`
- Initial module directories
- Basic test target
- Initial README
- Initial docs directory
- Initial policies and fixtures directories
- `.gitignore`
- `SECURITY.md`
- `CONTRIBUTING.md`
- CI skeleton if repository host supports it

---

## Non-goals

Do not implement real sandboxing, policy enforcement, MCP proxying, network control, or filesystem staging yet.

This phase is scaffolding only.

---

## Desired Repository Layout

Create the repository using the canonical layout from `CANONICAL_IMPLEMENTATION_DECISIONS.md`. The initial scaffold should include these top-level areas:

```text
aegis/
  build.zig
  build.zig.zon
  README.md
  LICENSE
  SECURITY.md
  CONTRIBUTING.md
  .gitignore
  docs/
  schemas/
  src/
    main.zig
    cli/
    core/
    policy/
    audit/
    intercept/
    mcp/
    sandbox/
    redteam/
  fixtures/
  policies/
  tests/
  scripts/
  packaging/
```

Within `src/`, use the canonical module ownership:

- `src/cli/` for command parsing and user-facing output.
- `src/core/` for shared types, errors, session, event, decision, platform, supervisor, and limits.
- `src/policy/` for policy load/validate/compile/evaluate/explain.
- `src/audit/` for event writing, replay, hash chain, summaries, and redaction bridge.
- `src/intercept/` for env, files, commands, network, and approvals.
- `src/mcp/` for JSON-RPC, transports, proxy, tools, resources, prompts, sampling, and manifests.
- `src/sandbox/` for platform backends.
- `src/redteam/` for fixture execution and reports.

If some files are empty placeholders, they should still compile or be clearly marked as future modules without pretending to implement behavior.

---

## Minimal CLI Behavior

`aegis --help` should print:

```text
Aegis — local runtime firewall for AI agents

Usage:
  aegis <command> [options]

Commands:
  run       Run a command under Aegis
  init      Create an Aegis policy
  doctor    Show platform capabilities
  policy    Validate and explain policies
  replay    Replay an audit session
  diff      Show staged writes
  apply     Apply staged writes
  discard   Discard staged writes
  mcp       MCP proxy and inspection commands
  redteam   Run red-team fixtures
  version   Print version
  help      Show help
```

`aegis version` should print a version string such as:

```text
aegis 0.0.0-dev
```

Unknown commands should return a non-zero exit code and a useful message.

---

## Implementation Tasks

1. Create the Zig project.
2. Define the binary target.
3. Define the test target.
4. Implement minimal `main.zig`.
5. Implement minimal command dispatch.
6. Create module directories and placeholder files.
7. Add README with project summary and development instructions.
8. Add security and contributing files.
9. Add placeholder docs.
10. Add sample policy files.
11. Add basic tests for help/version/unknown command if feasible.

---

## Acceptance Criteria

- `zig build` succeeds.
- `zig build test` succeeds.
- `zig build run -- --help` prints useful help.
- `zig build run -- version` prints a version.
- Unknown command exits non-zero.
- Repository layout matches the intended architecture.
- README explains that Aegis is pre-release and not yet enforcing security.

---

## Codex Execution Prompt

```text
Implement Phase 02: Repository Bootstrap.

Create the Zig repository skeleton for Aegis. Add a minimal CLI with help/version/unknown-command behavior. Add the directory/module structure needed for future phases. Add README, SECURITY.md, CONTRIBUTING.md, placeholder docs, sample policies, and fixture directories.

Do not implement real security enforcement yet. Keep placeholders honest.

Run:
- zig build
- zig build test

Provide a handoff with files changed, tests run, known limitations, and next-phase notes.
```

---

## Handoff Notes for Next Phase

The next phase will define core types, errors, allocators, and platform helpers. Leave the repository structured so those modules can be filled in without reorganizing the tree.


---

## Review Addendum — Bootstrap Must Include Production Context

Phase 02 should also create a `docs/dev/` directory in the future repository and copy or summarize these planning contracts there:

- architecture contracts;
- security invariants;
- production readiness gates;
- phase handoff format.

Also pin or document the Zig toolchain version used for development. If the exact version is not pinned yet, add a visible TODO in README and release docs. Do not leave the project ambiguous about compiler expectations by v1.0.

Create a place for dependency notes, for example:

```text
docs/dev/dependencies.md
```

Every future dependency should be recorded there.


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
