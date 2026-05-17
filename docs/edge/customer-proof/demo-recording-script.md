# Demo Recording Script

## Opening Line

"This is Edge, a local policy and evidence runtime for drone autonomy evaluation in fake, SITL, and bench-preparation contexts."

## Commands

```sh
zig build
./zig-out/bin/edge demo list
./zig-out/bin/edge demo run all
./zig-out/bin/edge proof generate --demo geofence-deny
./zig-out/bin/edge replay --session last --verify
```

## Expected Terminal Summary

- Geofence waypoint: denied.
- Disable failsafe: denied.
- LAND: allowed/logged according to policy.
- Webhook-like data egress: denied/redacted without network access.
- Stale telemetry: conservative deny.
- Safety report: generated.
- Replay: hash chain verified.

## What To Say

After each step, point to the policy decision, environment label, audit/replay path, and limitation text.

## Claims To Avoid

Do not say real aircraft are safe, the system is certified, the system provides detect-and-avoid, or the system replaces PX4/ArduPilot.

## Explain Limitations

Say that fake adapter tests prove deterministic product behavior, SITL tests prove local simulator behavior, and bench-preparation is no-actuation preparation.

## Closing CTA

"The next step is a simulation/SITL design-partner evaluation using your policies, scenarios, and evidence requirements."
