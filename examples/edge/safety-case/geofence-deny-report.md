# Aegis Edge Safety Case: geofence-deny

Aegis Edge safety reports are engineering audit artifacts only. They are not regulatory approval, certification, airworthiness approval, or real-flight readiness claims.

| Field | Value |
|---|---|
| Scenario | geofence-deny |
| Environment | fake_adapter |
| Result | passed |
| Real flight | Not performed |

## Commands

| Command | Decision | Reason | Rule | Finding |
|---|---|---|---|---|
| waypoint_outside_geofence | deny | waypoint outside geofence | commands.ask[set_waypoint] | geofence |

## Safety Findings

| Category | Severity | Observed | Limit | Decision |
|---|---|---|---|---|
| geofence | high | waypoint outside circular geofence | configured radius | deny |

## Evidence

| Evidence | Status |
|---|---|
| Audit hash chain | Verified in generated session |
| Scenario environment | fake_adapter |
| Real flight | Not performed |

## Limitations

- Fake adapter evidence is not SITL or real-flight evidence.
- No detect-and-avoid, autopilot replacement, regulatory approval, or certification is claimed.
