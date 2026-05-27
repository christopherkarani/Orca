# Edge Safety Case: mission-outside-geofence

Illustrative fake/simulation report. No real hardware was connected and no real flight was performed.

| Field | Value |
|---|---|
| Scenario | mission-outside-geofence-deny |
| Environment | fake_adapter |
| Result | passed |
| Real flight | Not performed |

## Commands

| Command | Decision | Reason | Rule | Finding |
|---|---|---|---|---|
| upload_mission | deny | mission item outside geofence | mission.safety | mission |

## Safety Findings

| Category | Severity | Observed | Limit | Decision |
|---|---|---|---|---|
| mission | high | mission item outside configured geofence | all mission items must pass envelope | deny |

## Limitations

- Fake mission evidence is not PX4 SITL, ArduPilot SITL, bench, hardware, or real-flight evidence.
- This report is not regulatory approval or certification.
