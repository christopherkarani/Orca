# Safety Envelope

The safety envelope is compiled from the Edge policy before command evaluation. Compilation validates the policy once, normalizes rule references, detects unsupported features, and exposes matched rule IDs such as `commands.ask[0]`.

Supported Phase 31 envelope blocks:

- `safety.geofence`: circular WGS84 geofence only.
- `safety.altitude`: floor, ceiling, and explicit altitude reference.
- `safety.velocity`: positive horizontal and vertical speed limits.
- `safety.battery`: takeoff, return-home, and land thresholds.
- `safety.state_freshness`: state age and stale-state behavior.
- `safety.emergency`: policy switches for LAND and return-to-home recommendations.
- `commands`: allow, ask, deny, and require-operator-approval lists.

Validation is fail-closed. Invalid radius, invalid altitude limits, non-positive velocity limits, invalid battery thresholds, duplicate command entries, unknown altitude references, and unsupported geofence shapes reject the policy.

Explicit deny beats allow. Explicit allow still must pass the safety envelope.
