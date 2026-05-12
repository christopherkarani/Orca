# Edge Architecture

## Fake Adapter

```text
Agent / Planner
    |
    v
Aegis Edge policy + safety runtime
    |
    v
Fake Adapter
```

The fake adapter is deterministic and local. It does not open real hardware, serial links, radio links, or aircraft endpoints.

## MAVLink Gateway

```text
Agent / Companion Planner
    |
    v
Aegis Edge MAVLink Gateway
    |
    v
Autopilot or SITL
```

Aegis Edge mediates selected MAVLink commands before they reach a bridge. It does not replace the autopilot. PX4 and ArduPilot remain responsible for flight-control behavior in their own environments.

## Evaluation Flow

```text
Command Request
    -> Policy
    -> Safety Evaluator
    -> Approval / Emergency / Data Guard / Health
    -> Decision
    -> Audit / Replay
```

Deny decisions win over allow decisions. Unknown, stale, unsupported, skipped, and inconclusive results are not counted as successful safety proof.

## Safety-Case Evidence Flow

```text
Scenario
    -> Events
    -> Findings
    -> Replay
    -> Safety Report
    -> Evidence Bundle
```

Evidence bundles are local customer-evaluation artifacts. They are not certification material and do not prove real-world flight safety.
