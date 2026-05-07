# Edge State Freshness

State freshness is explicit: `fresh`, `stale`, `expired`, or `unknown`. Unknown, stale, and expired state are not treated as safe.

The policy configures `max_state_age_ms`, `deny_commands_on_stale_state`, and emergency exceptions. A stale-state policy that does not deny normal commands is ambiguous and invalid.

Movement and high-risk commands require fresh enough vehicle state. Evaluation explanations include state age and timestamp source.

Emergency `land` can be allowed on stale state only when `allow_emergency_land_on_stale_state` is true and `land` is not denied. `return_to_home` can be allowed on stale state only when `allow_return_home_on_stale_state` is true and a home position is available.

