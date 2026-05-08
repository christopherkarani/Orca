# Battery Enforcement

Battery policy contains three thresholds:

- `deny_takeoff_below_percent`
- `return_home_below_percent`
- `land_below_percent`

Takeoff below the takeoff threshold is denied. Movement commands below the return-home threshold are denied with `return_to_home` as the recommended fallback. Commands below the land threshold are denied with `land` as the recommended fallback unless the command is LAND and emergency landing is allowed.

Battery state is never fabricated. When policy requires fresh battery state, missing or unknown battery source denies high-risk movement commands. Findings include observed percent and threshold.

LAND under critical battery remains a policy decision, not an emergency runtime implementation.
