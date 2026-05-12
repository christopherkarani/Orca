# Simulation/SITL Evaluation Plan

## Fake Adapter Evaluation

Fake adapter runs use deterministic local state and command fixtures. They validate policy shape, deny/allow behavior, audit/replay generation, red-team fixtures, and report formatting without simulator or hardware dependencies.

## PX4 SITL Evaluation

PX4 SITL runs are opt-in local simulator checks. They must be labeled as PX4 SITL evidence and kept separate from fake-PX4 fixtures.

## ArduPilot SITL Evaluation

ArduPilot SITL runs are opt-in local simulator checks. They must be labeled as ArduPilot SITL evidence and kept separate from fake-ArduPilot fixtures.

## Bench-preparation

Bench-preparation is no-actuation review of policy, gateway, data guard, health, audit, and evidence outputs. It is not a hardware operation guide.

## Real Flight

Real flight is out of scope. The pilot does not provide real-flight instructions or live aircraft control.

## Scenario Selection

Scenarios are selected from agreed customer risks: geofence, mission upload, stale state, high-risk command denial, emergency behavior, data/telemetry egress, and watchdog findings.

## Evidence Generation

Each run records local audit events. Replay verifies the hash chain. Safety-case reports and evidence bundles are generated from local artifacts. Skipped, unsupported, or inconclusive results are documented separately and do not count as passes.

## Evidence Review

The review checks policy intent, decision output, audit/replay verification, red-team results, data guard findings, health findings, and limitations.
