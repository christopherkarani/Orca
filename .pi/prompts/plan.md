---
description: "Spawn the Orca Planning Agent to break down work before implementation."
argument-hint: "<goal or feature description>"
---

# Planning Mode

Restate the requirements, identify affected modules, and create a phased implementation plan.

## Requirements Restatement
- Clarify what needs to be built
- Identify stakeholders (Zig core, TS plugins, dashboard, policies, docs, tests)

## Module Impact
- Which `src/` modules change?
- Which `integrations/` change?
- Which `schemas/` or `policies/` change?
- Which `tests/` need new fixtures?

## Phases
Break into explicit phases with file-level tasks:
1. Phase 1: ...
2. Phase 2: ...

## Risks
- Public/private boundary leaks?
- Security regressions?
- Test coverage gaps?
- Cross-platform issues (macOS/Linux/Windows)?

## Wait for Confirmation
Do NOT write implementation code. Present the plan and wait for user approval.

Goal: $@