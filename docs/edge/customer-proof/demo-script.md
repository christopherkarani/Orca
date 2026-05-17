# Customer Demo Script

Run from a clean checkout after `zig build`.

```sh
./zig-out/bin/edge demo list
./zig-out/bin/edge demo run all
./zig-out/bin/edge proof generate --demo geofence-deny
./zig-out/bin/edge replay --session last --verify
```

Narrative:

1. A planner asks for a waypoint outside the geofence. Edge denies it.
2. The planner asks to disable failsafe behavior. Edge denies it.
3. The planner asks for LAND. Edge allows/logs it according to policy.
4. The planner tries to send mission data to a webhook-like endpoint. Edge denies/redacts it locally without opening a network connection.
5. Stale telemetry triggers conservative behavior.
6. A safety-case report is generated.
7. Replay verifies the hash chain.

Avoid saying this proves real aircraft safety, certification, detect-and-avoid, or autopilot replacement.
