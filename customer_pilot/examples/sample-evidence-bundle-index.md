# Sample Evidence Bundle Index

Example data only. Customer placeholder: ExampleCo Robotics. Environment: fake adapter. This is not real flight.

| Artifact | Path | Hash | Evidence Source | Notes |
| --- | --- | --- | --- | --- |
| Baseline policy | `policies/example-baseline.yaml` | `sha256:example-policy-hash` | fake adapter | Example data only |
| Geofence scenario | `scenarios/geofence-deny.yaml` | `sha256:example-scenario-hash` | fake adapter | Unsafe command denied |
| Replay output | `replay/replay.md` | `sha256:example-replay-hash` | fake adapter | Hash verification succeeded |
| Safety report | `reports/sample-safety-report.md` | `sha256:example-report-hash` | fake adapter | non-certification |
| Red-team report | `reports/sample-redteam-report.md` | `sha256:example-redteam-hash` | fake adapter | Skipped not counted as pass |

## Limitations

- fake adapter evidence only.
- PX4 SITL, ArduPilot SITL, and bench-preparation evidence are listed separately when run.
- non-certification customer-evaluation evidence.
- not real flight.
