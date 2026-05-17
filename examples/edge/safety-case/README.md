# Edge Safety-Case Examples

These reports are deterministic illustrative outputs from fake/simulation scenarios. They are customer-demo artifacts only and do not claim real flight, certification, detect-and-avoid, autopilot replacement, or hardware approval.

Generate a fresh report:

```sh
edge safety-case generate \
  --scenario examples/edge/safety/scenarios/geofence-deny.yaml \
  --policy examples/edge/safety/policies/safety-strict.yaml
```

Included examples:

- `geofence-deny-report.md`
- `geofence-deny-report.json`
- `low-battery-emergency-report.md`
- `mission-outside-geofence-report.md`
