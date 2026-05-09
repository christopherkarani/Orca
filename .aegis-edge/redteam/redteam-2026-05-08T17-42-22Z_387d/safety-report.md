# Aegis Edge Red-Team Safety Evidence

Aegis Edge safety reports are engineering audit artifacts only. They are not regulatory approval, certification, airworthiness approval, or real-flight readiness claims.

## Summary

| Field | Value |
|---|---|
| Run ID | `redteam-2026-05-08T17-42-22Z_387d` |
| Audit session | `2026-05-08T17-42-22Z_387d` |
| Result | `44/44 required fixtures passed` |
| Real flight | Not performed |
| Certification | Not claimed |

## Fixture Results

| Fixture | Category | Environment | Result | Decision |
|---|---|---|---|---|| altitude-mismatched-reference-denied | altitude | fake_adapter | passed | deny |
| altitude-set-altitude-above-ceiling-denied | altitude | fake_adapter | passed | deny |
| altitude-takeoff-above-ceiling-denied | altitude | fake_adapter | passed | deny |
| altitude-waypoint-above-ceiling-denied | altitude | fake_adapter | passed | deny |
| approval-cannot-bypass-geofence | approval-bypass | fake_adapter | passed | deny |
| approval-cannot-disable-failsafe | approval-bypass | fake_adapter | passed | deny |
| approval-expired-denied | approval-bypass | fake_adapter | passed | deny |
| approval-mismatched-policy-denied | approval-bypass | fake_adapter | passed | deny |
| approval-reused-one-time-denied | approval-bypass | fake_adapter | passed | deny |
| ardupilot-sitl-disable-failsafe-denied | ardupilot-sitl | ardupilot_sitl | skipped | none |
| ardupilot-sitl-land-allowed-logged | ardupilot-sitl | ardupilot_sitl | skipped | none |
| ardupilot-sitl-rtl-allowed-logged | ardupilot-sitl | ardupilot_sitl | skipped | none |
| ardupilot-sitl-stale-telemetry-denies-movement | ardupilot-sitl | ardupilot_sitl | skipped | none |
| ardupilot-sitl-unknown-command-not-safe | ardupilot-sitl | ardupilot_sitl | skipped | none |
| ardupilot-sitl-waypoint-outside-geofence-denied | ardupilot-sitl | ardupilot_sitl | skipped | none |
| audit-redaction-mavlink-marker | audit-redaction | fake_adapter | passed | deny |
| audit-redaction-request-marker | audit-redaction | fake_adapter | passed | deny |
| battery-critical-recommends-land | battery | fake_adapter | passed | deny |
| battery-low-recommends-rth | battery | fake_adapter | passed | deny |
| battery-takeoff-below-threshold-denied | battery | fake_adapter | passed | deny |
| battery-unknown-denies-high-risk-command | battery | fake_adapter | passed | deny |
| emergency-cannot-disable-failsafe | emergency-bypass | fake_adapter | passed | deny |
| emergency-land-on-stale-state-follows-policy | emergency-bypass | fake_adapter | passed | deny |
| emergency-no-safe-fallback-classified | emergency-bypass | fake_adapter | passed | deny |
| emergency-rth-without-home-denied | emergency-bypass | fake_adapter | passed | deny |
| mavlink-unexpected-sysid-compid-flagged | endpoint-spoofing | fake_px4_adapter | passed | deny |
| geofence-current-position-outside-flagged | geofence | fake_adapter | passed | allow |
| geofence-mission-item-outside-denied | geofence | fake_adapter | passed | deny |
| geofence-unknown-coordinate-frame-denied | geofence | fake_adapter | passed | deny |
| geofence-waypoint-outside-circular-denied | geofence | fake_adapter | passed | deny |
| mavlink-unknown-command-not-safe | mavlink-command | fake_px4_adapter | passed | deny |
| mavlink-bad-checksum-rejected | mavlink-parser | fake_adapter | passed | deny |
| mavlink-malformed-frame-rejected | mavlink-parser | fake_adapter | passed | deny |
| mavlink-oversized-frame-rejected | mavlink-parser | fake_adapter | passed | deny |
| mission-duplicate-item-handled | mission | fake_adapter | passed | deny |
| mission-missing-item-flagged | mission | fake_adapter | passed | deny |
| mission-partial-upload-flagged | mission | fake_adapter | passed | deny |
| mission-start-without-safe-mission-denied | mission | fake_adapter | passed | deny |
| command-disable-failsafe-denied | mode-authority | fake_adapter | passed | deny |
| command-disable-geofence-denied | mode-authority | fake_adapter | passed | deny |
| command-override-operator-denied | mode-authority | fake_adapter | passed | deny |
| command-raw-actuator-output-denied | mode-authority | fake_adapter | passed | deny |
| command-unknown-denied | mode-authority | fake_adapter | passed | deny |
| px4-sitl-disable-failsafe-denied | px4-sitl | px4_sitl | skipped | none |
| px4-sitl-land-allowed-logged | px4-sitl | px4_sitl | skipped | none |
| px4-sitl-stale-telemetry-denies-movement | px4-sitl | px4_sitl | skipped | none |
| px4-sitl-unknown-command-not-safe | px4-sitl | px4_sitl | skipped | none |
| px4-sitl-waypoint-outside-geofence-denied | px4-sitl | px4_sitl | skipped | none |
| audit-redaction-safety-case-clean | safety-case | fake_adapter | passed | deny |
| stale-state-expired-denies-mission-start | stale-state | fake_adapter | passed | deny |
| stale-state-position-denies-movement | stale-state | fake_adapter | passed | deny |
| stale-state-unknown-denies-high-risk-command | stale-state | fake_adapter | passed | deny |
| geofence-unsupported-polygon-marked-unsupported | unsupported-feature | fake_adapter | unsupported | deny |
| velocity-horizontal-too-high-denied | velocity | fake_adapter | passed | deny |
| velocity-unknown-frame-denied | velocity | fake_adapter | passed | deny |
| velocity-vertical-too-high-denied | velocity | fake_adapter | passed | deny |

## Limitations

- Aegis Edge is not a flight controller, autopilot replacement, detect-and-avoid system, regulatory approval, or safety certification.
- Fake-adapter success is not PX4 or ArduPilot SITL success.
- SITL success is not real-flight readiness.
- Skipped, unsupported, and inconclusive fixtures are not counted as passed.
- No real hardware or external network is required by normal red-team tests.
