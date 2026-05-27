# Edge Red-Team Runner

Phase 34 adds a deterministic red-team and fault-injection suite for Edge.
It is simulation, fake-adapter, SITL, bench-preparation, and customer-evaluation
evidence only. It is not real-flight readiness, certification, detect-and-avoid,
or autopilot replacement evidence.

Run the default fake/simulation suite:

```sh
edge redteam
edge redteam --ci
edge redteam --json
```

Useful filters:

```sh
edge redteam list
edge redteam validate
edge redteam --category geofence
edge redteam --category data-guard
edge redteam --category audit-redaction
edge redteam --category approval-bypass
edge redteam --category emergency-bypass
edge redteam --fixture geofence-waypoint-outside-circular-denied
edge redteam --environment fake_adapter
edge redteam --report safety-case
edge redteam --output .edge/redteam/manual-run
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

Phase 35 adds data guard fixtures under `examples/edge/redteam/data-guard`.
They exercise mission-data egress denial, exact geolocation denial/redaction,
fake-secret redaction/denial, video-stream denial, direct-IP denial, webhook,
tunnel and paste endpoint denial, long-query detection, high-entropy endpoint
label detection, unknown endpoint denial, safety-report allow to an explicit
simulated customer endpoint, and telemetry allow to an explicit local
ground-control endpoint. The fixtures use synthetic payloads only, make no
external network calls, do not require real hardware, and preserve the
simulation/SITL boundary.
