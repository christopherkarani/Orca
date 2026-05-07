# Aegis Core

Aegis Core is the shared policy, audit, event, replay, redaction, schema, fixture, capability, and decision contract used by Aegis products.

## What Belongs Here

- Policy loading, validation, evaluation, and explanations.
- Decision types, action types, sessions, events, and platform-independent utilities.
- Audit event persistence, redaction before persistence, hash-chain replay, and summaries.
- Shared fixture and red-team support that is not tied to one product UI.
- Capability model types and honest capability-state vocabulary.

## What Does Not Belong Here

- CLI command parsing, desktop process supervision commands, installers, or shell completions.
- Drone hardware adapters, MAVLink, PX4, ArduPilot, or real-flight behavior.
- SaaS, telemetry, monetization, hosted dashboards, or network services.

## Phase 24 API Surface

Phase 24 hardens this package as the shared engine facade for Aegis CLI and Aegis Edge:

- `api`: policy parsing, validation, action evaluation, decision creation, audit event creation/writing, replay loading, replay verification, and redaction helpers.
- `actions`: shared CLI and Edge placeholder action types.
- `schemas`: schema registry for policy, event, MCP manifest, and reserved Edge/safety-report placeholders.
- `abi`: experimental C ABI skeleton.
- `redteam`: shared red-team fixture and report helpers from the v1 implementation.

The existing implementation remains in `src/` to preserve CLI behavior while future phases separate code physically where it is safe.

## ABI Status

The C ABI skeleton is experimental and not stable v1. See `ABI.md` for ownership, limits, return-code, and scope rules.

## Future Phases

Later phases may move implementation files into this package after dependency cycles are deliberately removed and regression tests prove the CLI behavior remains unchanged.
