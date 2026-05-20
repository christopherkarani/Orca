# Orca v1.0 Phased Project Plan

**Project:** Orca — local-first runtime firewall for AI agents  
**Implementation language:** Zig  
**Execution model:** Each phase is designed to be executed by a Codex coding agent as an isolated implementation task.  
**End state:** A complete v1.0 open-source product: local CLI, policy engine, audit/replay, secret protection, staged writes, command guard, MCP proxy, network guard, red-team suite, platform backends, installers, docs, and release readiness.

---


## Reviewed Context Additions

This phase pack has been reviewed for autonomous Codex execution. In addition to the numbered phase files, use these shared context documents:

| File | Purpose |
|---|---|
| `CODEX_AGENT_CONTEXT.md` | Short context pack to paste into every Codex phase prompt |
| `CODEX_MASTER_PROMPT.md` | Copy/paste master prompt template for assigning phases to Codex |
| `CANONICAL_IMPLEMENTATION_DECISIONS.md` | Binding final decisions for module layout, v1.0 baseline, I/O, approvals, MCP, red-team, and docs |
| `ARCHITECTURE_CONTRACTS.md` | Cross-phase API/module/data contracts |
| `SECURITY_INVARIANTS.md` | Non-negotiable security rules for all phases |
| `PRODUCTION_READINESS_GATES.md` | Per-phase and v1.0 production gates |
| `PHASE_DEPENDENCY_MATRIX.md` | Inputs/outputs for each phase |
| `REVIEW_SUMMARY.md` | Deep review findings and gaps closed |

For best results, every Codex execution should include the assigned phase file plus `CODEX_AGENT_CONTEXT.md`. For architecture-sensitive or security-sensitive phases, include `CANONICAL_IMPLEMENTATION_DECISIONS.md` and `ARCHITECTURE_CONTRACTS.md` as well. If an older phase file conflicts with `CANONICAL_IMPLEMENTATION_DECISIONS.md`, the canonical decisions win.

---

## Product Definition

Orca is a Zig-based, local-first runtime firewall for AI agents. It launches existing agent tools inside a policy-controlled session, strips secrets, blocks dangerous file access, stages writes, mediates shell commands, controls network egress, proxies MCP servers, records tamper-evident audit logs, and ships with red-team fixtures that prove the protection works.

Primary promise:

> Run your AI coding agent without giving it your whole laptop.

This plan deliberately excludes monetization, SaaS, enterprise dashboards, commercial licensing, paid support, and hosted services. Those belong in a later business phase after v1.0 of the open-source product exists.

---

## How to Use This Plan With Codex

Run phases in order. Each phase has:

- Objective
- Scope
- Non-goals
- Implementation tasks
- Expected files/modules
- Tests
- Acceptance criteria
- Codex execution prompt
- Handoff notes for the next phase

The Codex agent should not skip acceptance criteria. A phase is not complete until its tests pass and its handoff notes are updated.

Recommended workflow:

```bash
git checkout -b phase-XX-short-name
# Give Codex the phase file.
# Let Codex implement.
zig build test
zig build
git status
git diff
# Review and merge.
```

Each phase should leave the repository in a working state.

---

## Phase List

| Phase | File | Goal |
|---:|---|---|
| 00 | `00_PROJECT_INDEX.md` | Master index and product endpoint |
| 01 | `01_CODEX_EXECUTION_PROTOCOL.md` | Rules for Codex agents implementing phases |
| 02 | `02_REPO_BOOTSTRAP.md` | Initialize the Zig repository and module structure |
| 03 | `03_CORE_TYPES_AND_ALLOCATORS.md` | Define core domain types, errors, allocators, and utilities |
| 04 | `04_CLI_SKELETON.md` | Build the command-line skeleton and help system |
| 05 | `05_SESSION_SUPERVISOR.md` | Implement session lifecycle and child process supervision |
| 06 | `06_AUDIT_LOG_AND_REPLAY.md` | Implement JSONL audit logs, hash chain, and replay |
| 07 | `07_POLICY_ENGINE.md` | Implement policy parsing, validation, matching, and explanations |
| 08 | `08_ENV_AND_SECRET_PROTECTION.md` | Implement environment filtering, secret detection, and redaction |
| 09 | `09_FILESYSTEM_GUARD_AND_STAGING.md` | Implement path policy, staged writes, diff/apply/discard |
| 10 | `10_COMMAND_GUARD_AND_APPROVALS.md` | Implement command risk classification and approvals |
| 11 | `11_MCP_STDIO_PROXY.md` | Implement stdio MCP proxy, JSON-RPC, and tool-call policy |
| 12 | `12_NETWORK_EGRESS_GUARD.md` | Implement network policy, observation, allowlists, and exfiltration heuristics |
| 13 | `13_REDTEAM_BENCHMARK_SUITE.md` | Implement red-team fixtures, runner, scorecard, and regression tests |
| 14 | `14_LINUX_SANDBOX_BACKEND.md` | Implement stronger Linux backend and capability reporting |
| 15 | `15_MACOS_BACKEND.md` | Implement macOS backend and honest capability reporting |
| 16 | `16_WINDOWS_BACKEND.md` | Implement Windows backend and PowerShell/cmd support |
| 17 | `17_ADVANCED_MCP_AND_MANIFESTS.md` | Add remote/HTTP MCP compatibility, sampling controls, and server manifests |
| 18 | `18_AGENT_PRESETS_AND_INTEGRATIONS.md` | Add presets for common agent workflows and CI integrations |
| 19 | `19_INSTALLERS_RELEASE_PIPELINE.md` | Build cross-platform release, packaging, signing, SBOM, and distribution |
| 20 | `20_SECURITY_HARDENING_AND_FUZZING.md` | Harden security-sensitive surfaces and add fuzz/regression tests |
| 21 | `21_DOCUMENTATION_AND_DEMO.md` | Build launch docs, scary demo, examples, and compatibility matrix |
| 22 | `22_V1_STABILIZATION_AND_ACCEPTANCE.md` | Final v1.0 stabilization, schema lock, performance, and release checklist |

---

## v1.0 Product Completion Criteria

Orca v1.0 is complete when all of the following are true:

### Core CLI

- `orca run` launches arbitrary commands.
- `orca init` creates a working policy.
- `orca doctor` reports platform capabilities.
- `orca replay` replays sessions.
- `orca diff`, `orca apply`, and `orca discard` manage staged writes.
- `orca policy check` validates policy files.
- `orca mcp proxy` proxies stdio MCP servers.
- `orca redteam` runs security fixtures.

### Protection

- Secrets are stripped from the environment by default.
- Secret-like values are redacted from logs.
- Sensitive paths are denied by policy.
- Workspace writes can be staged before applying.
- Dangerous shell commands are denied or require approval.
- Unknown network destinations are denied or require approval in strict mode.
- MCP tool calls are mediated by policy.
- Session events are logged with a tamper-evident hash chain.

### Platform

- Linux has the strongest backend.
- macOS has a useful developer backend with clear capability reporting.
- Windows has useful process/env/shell support with clear capability reporting.
- The CLI builds and runs on all three platforms.

### Security

- The threat model is documented.
- Known bypass attempts are tested.
- Red-team fixtures run in CI.
- Policy and event schemas are stable.
- The project has `SECURITY.md`, vulnerability disclosure guidance, and release signing/checksum support.

### Launch

- The README includes a compelling secret-exfiltration demo.
- Install instructions exist for macOS, Linux, and Windows.
- Release artifacts are generated.
- Documentation explains limitations honestly.
- v1.0 release checklist is complete.

---

## Deliberate Deferrals After v1.0

These are intentionally not part of the open-source v1.0 execution plan:

- SaaS dashboard
- Enterprise policy sync
- SSO/SCIM/RBAC
- Paid MCP gateway
- Hosted telemetry
- Commercial licensing
- Enterprise sales collateral
- Cloud audit retention
- Managed policy registry

The v1.0 product should be strong enough to create developer adoption and prove the technical wedge. Monetization can be layered on afterward.
