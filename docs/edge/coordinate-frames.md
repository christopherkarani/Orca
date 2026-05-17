# Edge Coordinate Frames

Edge requires explicit units, coordinate frames, altitude references, and timestamp sources. It is not ready for real flight and must not be used for real flight.

## Units

- distance: meters
- speed: meters per second
- angle: degrees or radians, carried explicitly by the type
- altitude: meters plus an explicit altitude reference

## Frames

Supported domain frame labels are:

- `wgs84`: geographic latitude/longitude.
- `local_ned`: local north-east-down.
- `local_enu`: local east-north-up.
- `body_frame`: vehicle-relative body frame.
- `home_relative`: local frame relative to home metadata.
- `unknown`: invalid when a known frame is required.

NED and ENU are not silently interchangeable. Phase 26 intentionally returns an unsupported conversion error for local-frame conversion unless the source and target frame already match. Later phases must add explicit transform metadata and tests before any conversion is used for policy decisions.

## Altitude References

Altitude always carries one of:

- `amsl`
- `agl`
- `home_relative`
- `terrain_relative`
- `unknown`

Unknown altitude reference is invalid for `GeoPoint`, geofence, altitude limits, and altitude command parameters. AGL, AMSL, and home-relative altitude are never mixed silently.

## Timestamps

Timestamp source is explicit:

- monotonic
- GPS
- system clock
- autopilot
- unknown

Unknown timestamp source is invalid where a timestamp is required for audit or freshness validation.
