# State Freshness

State freshness is explicit: `fresh`, `stale`, `expired`, or `unknown`. Unknown, stale, and expired state are not treated as safe.

The policy configures `max_state_age_ms`, `deny_commands_on_stale_state`, and emergency exceptions. A stale-state policy that does not deny normal commands is ambiguous and invalid.

Movement and high-risk commands require fresh enough vehicle state. Evaluation explanations include state age and timestamp source.

LAND can be allowed on stale state only when `allow_emergency_land_on_stale_state` is true, `safety.emergency.allow_land` is true, and LAND is not denied. `return_to_home` can be allowed on stale state only when `allow_return_home_on_stale_state` is true, `safety.emergency.allow_return_to_home` is true, and a home position is available.

Fake, PX4 SITL, and ArduPilot SITL provenance labels remain distinct in findings and audit output.
