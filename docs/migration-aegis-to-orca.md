# Migration: Aegis to Orca

Orca is the current CLI name for the local agent guardrail runtime that older
project notes may still call Aegis. This migration note is for repository
metadata and local workspace paths only.

## Local Workspace Paths

- New Orca sessions should use `.orca/` for policy, audit, replay, and runtime
  artifacts.
- Older `.aegis/` session directories may remain for historical replay or
  migration reference.
- Do not copy old secrets, raw payloads, or unredacted logs into new Orca
  workspaces.

## Command Mapping

- `aegis --help` is no longer installed in the hard-break release; use `orca --help`.
- Use `orca --help`, `orca doctor`, `orca run`, `orca replay`, and
  `orca redteam` in new documentation and integrations.

## Safety Boundary

This document does not change the Edge boundary. Edge evidence remains
simulation, SITL, bench-preparation, and customer-evaluation evidence only. It
is not real-flight readiness, certification, regulatory approval,
detect-and-avoid, or autopilot replacement.
