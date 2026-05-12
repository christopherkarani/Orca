# Pilot Boundaries

This pilot is an engineering evaluation package. It is not a flight program.
The allowed scope is simulation/SITL/customer-evaluation and bench-preparation only.

## Explicit Non-Goals

- No real-flight deployment.
- No live aircraft control.
- No propellers, motors, or actuation procedures.
- No certification claim.
- No regulatory approval claim.
- No BVLOS approval claim.
- No detect-and-avoid claim.
- No autopilot replacement claim.
- No safety guarantee.
- No replacement for the customer safety process.
- No replacement for PX4, ArduPilot, or autopilot failsafes.
- No proof of real-world airworthiness.
- No guarantee of full MAVLink coverage.
- No guarantee that all customer-specific modes or commands are covered.
- No external network required for normal evaluation.
- No real secrets required for evaluation.

## Evidence Meaning

Fake adapter evidence means Aegis Edge processed deterministic local inputs with fake vehicle state. It is useful for policy, audit/replay, report, and red-team workflow evaluation.

SITL evidence means Aegis Edge processed local simulator inputs from PX4 SITL or ArduPilot SITL when explicitly configured. SITL evidence is simulator evidence, not real flight evidence.

Bench-preparation evidence means the team reviewed no-actuation policy, gateway, health, data guard, and audit behavior before any hardware discussion. It does not include motor or aircraft operation.

## Evidence Not Yet Produced

The pilot does not produce airworthiness evidence, certification evidence, regulatory acceptance evidence, real hardware reliability evidence, radio-link reliability evidence, detect-and-avoid evidence, or proof that the customer integration is complete.
