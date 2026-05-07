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

## Current Status

Phase 23 defines this package as a contract layer over the stable v1.0 source modules. The existing implementation remains in `src/` to preserve CLI behavior while future phases separate code physically where it is safe.

## Future Phases

Later phases may move implementation files into this package after dependency cycles are deliberately removed and regression tests prove the CLI behavior remains unchanged.
