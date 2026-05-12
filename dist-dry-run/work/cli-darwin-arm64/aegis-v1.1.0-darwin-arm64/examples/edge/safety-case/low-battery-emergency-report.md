# Aegis Edge Safety Case: low-battery-emergency

Illustrative fake/simulation report. No real hardware was connected and no real flight was performed.

| Field | Value |
|---|---|
| Scenario | low-battery-emergency |
| Environment | fake_px4_adapter |
| Result | passed |
| Real flight | Not performed |

## Commands

| Command | Decision | Reason | Rule | Finding |
|---|---|---|---|---|
| land | allow | critical battery selected policy-valid fallback | safety.emergency.allow_land | battery |

## Evidence

| Evidence | Status |
|---|---|
| Emergency fallback | LAND recommended |
| Audit hash chain | Verified in generated session |
| Real flight | Not performed |

## Limitations

- Emergency mode is policy evaluation only and does not send real hardware commands.
- This is not certification, detect-and-avoid, autopilot replacement, or real-flight approval.
