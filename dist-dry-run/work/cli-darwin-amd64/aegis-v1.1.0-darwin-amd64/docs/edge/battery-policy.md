# Edge Battery Policy

Battery policy is decision-only. It does not trigger real emergency behavior.

Rules:

- Takeoff is denied below `deny_takeoff_below_percent`.
- Return-to-home is recommended or selected below `return_home_below_percent`.
- Land is recommended or selected below `land_below_percent`.
- If `require_fresh_battery_state` is true and battery state is missing or unknown, high-risk commands deny.
- Explanations include observed percentage and policy thresholds when available.

Thresholds must be ordered: takeoff threshold >= return-home threshold >= land threshold.

