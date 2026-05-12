# Emergency Fallbacks

Emergency fallback selection is policy-controlled. The default example ladder is:

1. `land`
2. `hold_position`
3. `return_to_home`
4. deny with no safe fallback

The first policy-valid command is selected. `return_to_home` requires a valid home position. `hold_position` requires valid local or global position context. `land` on stale state is allowed only when policy explicitly allows emergency land on stale state.

`disarm` is not treated as a default in-flight emergency-safe command. Unknown state is not treated as safe. Unknown commands are denied. Fallback evaluation preserves fake/PX4 SITL/ArduPilot SITL provenance and records structured emergency audit events.
