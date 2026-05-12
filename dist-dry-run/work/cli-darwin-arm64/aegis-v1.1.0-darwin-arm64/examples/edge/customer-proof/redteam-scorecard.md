# Red-Team Scorecard

Provenance: fake_adapter plus optional SITL-gated fixtures
policy_hash: sha256:example-redteam-policy-hash

| Category | Required | Passed | Skipped | Unsupported |
| --- | ---: | ---: | ---: | ---: |
| geofence | 4 | 4 | 0 | 1 |
| command-risk | 5 | 5 | 0 | 0 |
| data-guard | 8 | 8 | 0 | 0 |
| health | 6 | 6 | 0 | 0 |
| px4-sitl | 0 | 0 | 5 | 0 |
| ardupilot-sitl | 0 | 0 | 6 | 0 |

## Limitations

Skipped and unsupported are not passes. This is simulation/SITL/bench-preparation evidence only and a non-certification example.
