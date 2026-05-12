# Pilot Overview

Aegis Edge is a local simulation/SITL/bench-preparation safety-policy runtime for drone autonomy evaluation. It can mediate a bounded MAVLink command surface, evaluate safety envelopes, record audit/replay evidence, run deterministic red-team and fault-injection scenarios, and generate customer-readable safety-case evidence.

## What The Pilot Evaluates

- Whether Aegis Edge can run in a customer-like fake adapter or SITL evaluation environment.
- Whether a customer baseline policy can express geofence, altitude, velocity, battery, operator approval, emergency, data guard, and runtime health expectations.
- Whether unsafe commands are denied and emergency-safe commands are allowed/logged according to policy.
- Whether audit/replay, red-team scorecards, and safety reports create useful engineering evidence.
- Whether limitations are documented clearly enough for the customer safety process.

## What The Pilot Does Not Evaluate

- Real flight; real flight is out of scope.
- Live aircraft control.
- Flight certification.
- Regulatory approval.
- BVLOS approval.
- Detect-and-avoid.
- Autopilot replacement behavior.
- Full coverage of all MAVLink commands or customer-specific modes.

## Supported Environments

- `fake adapter`: deterministic local evidence with no simulator or hardware.
- `PX4 SITL`: opt-in local simulator evidence, separate from fake PX4 fixtures.
- `ArduPilot SITL`: opt-in local simulator evidence, separate from fake ArduPilot fixtures.
- `bench-preparation/no-actuation`: review of policy, command mediation, health, data guard, and evidence packaging before any actuation workflow.

## Unsupported Environments

- Real flight.
- Flight certification.
- Detect-and-avoid.
- Autopilot replacement.
- Real aircraft control.

## Duration And Inputs

The default pilot is two weeks after a short pre-pilot discovery step. Customer input usually includes autonomy stack details, MAVLink command usage, simulator availability, baseline safety constraints, telemetry/data handling expectations, and desired evaluation outcomes. No real secrets are requested.

## Deliverables

Expected deliverables include a stack map, command surface inventory, baseline policy, scenario list, red-team scorecard, safety-case report, audit/replay evidence bundle, known limitations, and recommended next integration steps.

## Evidence Flow

Scenarios produce local audit events. Replay verifies hash-chain continuity. Safety reports summarize evaluated commands, decisions, findings, red-team results, data guard findings, runtime health findings, and limitations. Red-team scenarios exercise hostile or faulty inputs to show how the policy runtime responds in fake/SITL/bench-preparation contexts.
