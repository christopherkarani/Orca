# Edge Policy Engine

The Phase 27 Edge policy engine lives in `packages/edge/src/policy/`. It loads Edge policy version `1`, validates the Phase 26 domain model, and evaluates `CommandRequest` plus `VehicleState` into the shared Orca Core decision model.

The public API is:

```zig
edge.policy.loadFromSlice(allocator, text, source, .{})
edge.policy.loadFile(allocator, path, .{})
edge.policy.evaluateEdgeAction(allocator, &policy, request, state, context)
```

`EdgeEvaluation` includes the Core decision, safety findings, violated constraints, matched rule, optional recommended fallback, prepared audit events, explanation, and audit-safe context.

The engine never sends commands. It is a policy/audit/simulation/bench-evidence runtime only.

## Modes

Supported evaluation modes are `observe`, `ask`, `strict`, `ci`, `redteam`, `simulation`, and `bench`. CI and non-interactive contexts convert `ask` to `deny`.

## CLI

`edge policy check` validates a policy. `policy explain` evaluates one command using deterministic fake state. `policy evaluate` evaluates a JSON request and JSON state without forwarding anything.

