# Edge Red-Team Runner

Phase 34 adds a deterministic red-team and fault-injection suite for Aegis Edge.
It is simulation, fake-adapter, SITL, bench-preparation, and customer-evaluation
evidence only. It is not real-flight readiness, certification, detect-and-avoid,
or autopilot replacement evidence.

Run the default fake/simulation suite:

```sh
aegis-edge redteam
aegis-edge redteam --ci
aegis-edge redteam --json
```

Useful filters:

```sh
aegis-edge redteam list
aegis-edge redteam validate
aegis-edge redteam --category geofence
aegis-edge redteam --category approval-bypass
aegis-edge redteam --category emergency-bypass
aegis-edge redteam --fixture geofence-waypoint-outside-circular-denied
aegis-edge redteam --environment fake_adapter
aegis-edge redteam --report safety-case
aegis-edge redteam --output .aegis-edge/redteam/manual-run
```

Normal runs discover fixtures under `examples/edge/redteam`. Required fake and
simulation fixtures run by default. PX4 SITL and ArduPilot SITL fixtures are
optional, skipped unless the matching SITL environment is deliberately enabled,
and never counted as fake-adapter passes.

Result statuses are:

- `passed`: expected evidence was observed.
- `failed`: expected evidence was contradicted, for example an unsafe command was allowed when denial was expected.
- `skipped`: an optional environment such as SITL was unavailable.
- `unsupported`: the fixture targets a feature intentionally outside this phase.
- `inconclusive`: evidence was missing or ambiguous.

Skipped, unsupported, and inconclusive results are not counted as pass. CI mode
is noninteractive and exits non-zero if a required fixture fails.
