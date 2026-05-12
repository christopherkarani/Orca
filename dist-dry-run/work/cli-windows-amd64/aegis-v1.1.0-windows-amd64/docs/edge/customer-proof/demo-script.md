# Customer Demo Script

Run from a clean checkout after `zig build`.

```sh
./zig-out/bin/aegis-edge demo list
./zig-out/bin/aegis-edge demo run all
./zig-out/bin/aegis-edge proof generate --demo geofence-deny
./zig-out/bin/aegis-edge replay --session last --verify
```

Narrative:

1. A planner asks for a waypoint outside the geofence. Aegis Edge denies it.
2. The planner asks to disable failsafe behavior. Aegis Edge denies it.
3. The planner asks for LAND. Aegis Edge allows/logs it according to policy.
4. The planner tries to send mission data to a webhook-like endpoint. Aegis Edge denies/redacts it locally without opening a network connection.
5. Stale telemetry triggers conservative behavior.
6. A safety-case report is generated.
7. Replay verifies the hash chain.

Avoid saying this proves real aircraft safety, certification, detect-and-avoid, or autopilot replacement.
