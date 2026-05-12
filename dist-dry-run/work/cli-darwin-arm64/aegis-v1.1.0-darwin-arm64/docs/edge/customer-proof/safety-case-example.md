# Safety-Case Example

Run:

```sh
./zig-out/bin/aegis-edge proof generate --demo geofence-deny
```

The generated report should show:

- Provenance: fake adapter or explicit SITL/bench context.
- Policy hash.
- Command decision.
- Findings.
- Limitations.
- Non-certification disclaimer.
- Replay verification result.

Checked-in sample: `examples/edge/customer-proof/geofence-deny-safety-report.md`.
