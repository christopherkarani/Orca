# Buyer FAQ

## Is this a flight controller?

No. Edge mediates policy and evidence around commands. It is not a flight controller.

## Is this an autopilot?

No. PX4 or ArduPilot remain the autopilot in simulator contexts.

## Does this replace PX4 or ArduPilot?

No. Edge sits between agents/planners and bridges; it does not replace PX4 or ArduPilot.

## Does this provide certification?

No. It provides customer-evaluation evidence only.

## Does this work with real drones?

Phase 38 does not support real flight or live aircraft control.

## What does the current version prove?

It proves local policy decisions, safety-envelope decisions, replayable audit evidence, red-team fixtures, data guard behavior, and runtime-health findings in fake/SITL/bench-preparation contexts.

## What does SITL prove?

SITL proves local simulator integration behavior, not real-world aircraft safety.

## What does fake adapter testing prove?

It proves deterministic Edge product behavior without simulator or hardware dependency.

## What does bench-preparation mean?

Bench-preparation means no-actuation checks and evidence gathering before any real aircraft operation.

## How does this help a drone company?

It gives autonomy teams a repeatable way to show command mediation, policy denial, auditability, red-team coverage, and evidence generation before deeper integration work.

## What would a design-partner pilot look like?

A bounded simulation/SITL evaluation using customer scenarios, policies, logs, and proof artifacts.

## What logs/evidence do we get?

Hash-chained audit logs, replay output, safety reports, traceability rows, red-team scorecards, and proof bundles.

## Can this help with internal safety reviews?

Yes, as supporting evaluation evidence with clear limitations.

## Can this help with customer security/safety questionnaires?

Yes, by showing documented controls, evidence paths, limitations, and repeatable demos.

## Does it require sending data to a cloud service?

No. Normal demos and tests run locally.

## Does it require real network access?

No. Data guard demos classify endpoint records without making external calls.

## Does it store secrets?

Raw secrets must not be persisted. Redaction happens before persistent outputs.

## Does it work with PX4?

It supports fake-PX4 fixtures and opt-in PX4 SITL simulation evidence.

## Does it work with ArduPilot?

It supports fake-ArduPilot fixtures and opt-in ArduPilot SITL simulation evidence.

## What are the limitations?

No real flight, no certification, no detect-and-avoid, no autopilot replacement, no proof of hardware reliability, and only covered command/message/policy surfaces are demonstrated.
