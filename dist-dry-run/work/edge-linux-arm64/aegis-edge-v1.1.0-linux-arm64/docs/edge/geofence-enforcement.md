# Geofence Enforcement

Phase 31 supports circular geofences with WGS84 latitude/longitude and radius in meters. Horizontal distance uses the haversine formula with Earth radius `6,371,000 m`. Altitude is checked separately and requires an explicit matching altitude reference.

Behavior:

- waypoint inside the circle proceeds according to command policy
- waypoint outside the circle is denied
- mission item outside the circle denies the mission upload
- current position outside the circle is flagged as a finding
- invalid latitude/longitude rejects the input
- unknown coordinate frames or unsupported conversions fail closed

Unsupported:

- polygon geofences
- WGS84/local frame conversion
- NED/ENU conversion
- AMSL/AGL/home-relative/terrain-relative conversion

Unsupported shapes and mismatched references are reported honestly; they are not silently allowed.
