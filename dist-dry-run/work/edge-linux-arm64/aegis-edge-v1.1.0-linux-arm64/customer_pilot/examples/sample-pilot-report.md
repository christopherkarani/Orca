# Sample Pilot Final Report

Example data only. Customer placeholder: ExampleCo Robotics. Environment: fake adapter. This is not real flight.

## Executive Summary

The sample pilot demonstrated local policy evaluation, command denial, emergency command logging, data guard findings, runtime health findings, red-team execution, and audit/replay verification.

## Scope

- fake adapter scenarios.
- No PX4 SITL in this sample.
- No ArduPilot SITL in this sample.
- No bench-preparation in this sample.

## Evidence Summary

- Baseline policy: `policies/example-baseline.yaml`
- Safety report: `reports/sample-safety-report.md`
- Red-team report: `reports/sample-redteam-report.md`
- Evidence bundle index: `bundle/index.md`

## Findings

- Unsafe waypoint denied.
- Emergency LAND allowed/logged according to policy.
- Stale telemetry denied movement.
- Data egress denied/redacted.
- Audit/replay hash verification succeeded.

## Limitations

- fake adapter evidence only.
- MAVLink coverage bounded to example commands.
- non-certification customer-evaluation evidence.
- not real flight.

## Decision Options

- Continue to deeper SITL.
- Prepare bench/no-actuation evaluation.
- Expand policy coverage.
- Defer due to unsupported needs.
