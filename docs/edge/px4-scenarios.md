# PX4 Scenarios

PX4 scenarios are run with:

```bash
./zig-out/bin/edge px4 scenario run --policy <policy> --scenario <scenario> [--artifacts <dir>]
```

Checked-in deterministic scenarios live under `examples/edge/px4/scenarios/`:

- `waypoint-outside-geofence-deny.yaml`
- `land-allow.yaml`
- `disable-failsafe-deny.yaml`
- `mission-outside-geofence-deny.yaml`
- `raw-actuator-deny.yaml`
- `takeoff-low-battery-deny.yaml`

Artifacts include scenario id, environment, endpoint metadata, command requests, policy decisions, forwarded/blocked status, safety findings, limitations, and redacted notes. `events.jsonl` and `replay.json` are written through the redaction path before persistence.

Phase 32 scenarios can include `approval: valid_once`, `approval: expired`, or another bounded approval seed to prove operator approvals are consumed by the same policy and safety path as normal fake-PX4 command mediation.

Missing PX4 SITL produces a skip/unavailable result for SITL scenarios. It must not silently fall back to fake-PX4 and claim SITL success.
