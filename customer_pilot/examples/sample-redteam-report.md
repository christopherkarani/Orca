# Sample Red-team Report

Example data only. Customer placeholder: ExampleCo Robotics. Environment: fake adapter. This is not real flight.

## Run Metadata

- Run ID: example-redteam-001
- Policy hash: `sha256:example-policy-hash`
- Evidence source: fake adapter

## Summary

| Category | Passed | Failed | Skipped | Unsupported | Inconclusive |
| --- | ---: | ---: | ---: | ---: | ---: |
| geofence | 3 | 0 | 0 | 0 | 0 |
| command-risk | 4 | 0 | 0 | 1 | 0 |
| data guard | 2 | 0 | 0 | 0 | 0 |
| health | 2 | 0 | 0 | 0 | 0 |

## Findings

- Unsafe geofence command denied.
- Disable-failsafe request denied.
- Mission data egress denied/redacted.
- Stale telemetry denied movement.

## Limitations

- fake adapter evidence only.
- Skipped, unsupported, and inconclusive results are not passes.
- non-certification customer-evaluation evidence.
- not real flight.
