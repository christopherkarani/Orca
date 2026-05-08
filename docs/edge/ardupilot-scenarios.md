# ArduPilot Scenarios

ArduPilot scenarios are run with:

```bash
./zig-out/bin/aegis-edge ardupilot scenario run --policy <policy> --scenario <scenario> [--artifacts <dir>]
```

Checked-in deterministic scenarios live under `examples/edge/ardupilot/scenarios/`:

- `waypoint-outside-geofence-deny.yaml`
- `land-allow.yaml`
- `rtl-allow.yaml`
- `disable-failsafe-deny.yaml`
- `mission-outside-geofence-deny.yaml`
- `raw-actuator-deny.yaml`
- `takeoff-low-battery-deny.yaml`

Artifacts include scenario id, environment, provenance, vehicle type, endpoint metadata, command requests, policy decisions, forwarded/blocked status, safety findings, limitations, and redacted notes. `events.jsonl` and `replay.json` are written through the redaction path before persistence.

Fake scenarios use `environment: fake_ardupilot` and `fake_ardupilot_adapter` provenance. SITL scenarios use `environment: ardupilot_sitl`, `requires_ardupilot_sitl: true`, and `sitl_ardupilot` provenance.

Missing ArduPilot SITL produces a skip/unavailable result for SITL scenarios. It must not silently fall back to fake-ArduPilot and claim SITL success.
