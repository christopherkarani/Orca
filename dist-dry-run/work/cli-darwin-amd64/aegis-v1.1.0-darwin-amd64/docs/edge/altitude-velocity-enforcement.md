# Altitude And Velocity Enforcement

Altitude limits apply to takeoff targets, set-altitude targets, waypoint targets, and mission waypoint altitudes. Ceiling violations deny. Floor violations deny for normal movement; LAND can proceed only through explicit LAND policy and emergency behavior.

Altitude references must match the policy exactly. Aegis Edge does not convert between AMSL, AGL, terrain-relative, and home-relative altitude.

Velocity limits apply to `set_velocity` commands and mapped MAVLink velocity setpoints. Horizontal speed is `sqrt(vx^2 + vy^2)` and vertical speed is `abs(vz)`. Unknown, WGS84, body-frame, or ambiguous velocity frames are not treated as safe for high-risk movement.

Velocity limits must be positive. Non-positive configured limits reject the policy.
