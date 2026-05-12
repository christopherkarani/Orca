# Edge Scenario Results

Scenario status values:

- `passed`: expected fake/SITL safety behavior occurred and evidence was produced
- `failed`: expected safety behavior did not occur
- `skipped`: required local SITL was not enabled or not configured
- `unsupported`: the requested feature is outside the supported Phase 33 evidence surface
- `inconclusive`: evidence is insufficient

Rules:

- fake adapter success is not SITL success
- PX4 SITL success is not ArduPilot SITL success
- SITL success is not real-flight success
- missing SITL is not pass
- unsupported features are not pass
- deny beats allow
- CI mode must not prompt
