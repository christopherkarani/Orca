# Edge Geofence Policy

Phase 27 enforces circular WGS84 geofences only. The policy must include a center latitude/longitude, radius in meters, altitude floor/ceiling, explicit altitude reference, and boundary action.

Rules:

- A waypoint outside the circle denies or asks according to `boundary_action`.
- A waypoint above the altitude ceiling denies.
- A waypoint below the altitude floor denies unless the command is an explicit landing action.
- Current position outside the geofence is flagged.
- Unknown coordinate frames deny high-risk movement commands.
- Mismatched altitude references fail explicitly. Aegis Edge does not convert AMSL, AGL, home-relative, or terrain-relative altitude in Phase 27.
- Polygon support is reserved in the schema but unavailable for enforcement. Polygon policies fail clearly as unsupported.

No external geospatial dependency is used. Circular distance uses local haversine math and is intended for deterministic policy decisions, not flight validation.

