# Phase Dependency Matrix

Use this matrix to understand what each phase consumes and produces.

| Phase | Consumes | Produces | Must Not Break |
|---:|---|---|---|
| 02 | none | buildable Zig repo, module tree, initial docs | future module paths |
| 03 | repo scaffold | core types, errors, platform utilities | CLI build |
| 04 | core types | full CLI skeleton, init, doctor | command names and exit code meanings |
| 05 | CLI, core types | session supervisor, `aegis run` process launch | child stdout/stderr flow |
| 06 | supervisor, core events | audit JSONL, hash chain, replay | run exit propagation |
| 07 | audit, CLI | policy parser/evaluator/explainer | audit schema and run behavior |
| 08 | policy, audit, supervisor | env filtering, redaction | no-secret logging invariant |
| 09 | policy, audit, redaction | path guard, staging, diff/apply/discard | session layout and audit integrity |
| 10 | policy, audit, staging | command guard, approvals, shims | CI non-interactive behavior |
| 11 | policy, audit, approval, redaction | stdio MCP proxy | stdout/stderr protocol separation |
| 12 | policy, audit, redaction | network policy and heuristics | honest capability reporting |
| 13 | all core guards | red-team fixtures and runner | deterministic local tests |
| 14 | backend interface, redteam | Linux backend | non-Linux builds |
| 15 | backend interface, redteam | macOS backend | Linux behavior |
| 16 | backend interface, redteam | Windows backend | Unix behavior |
| 17 | MCP proxy, policy | advanced MCP, manifests | stdio compatibility |
| 18 | policy, MCP, docs | presets, CI examples, completions | preset validation |
| 19 | build system, docs | installers, packages, release pipeline | local build/test |
| 20 | all security surfaces | fuzz/regression hardening | production behavior |
| 21 | working product | docs and demos | accurate claims |
| 22 | all phases | v1.0 stabilization and release readiness | schema stability |

## Handoff Rule

Every phase must leave a handoff note describing:

- changed APIs;
- changed schemas;
- new tests;
- known limitations;
- assumptions for the next phase.

If a phase changes an API consumed by later phases, update `ARCHITECTURE_CONTRACTS.md`.
