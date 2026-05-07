# Aegis Edge Safety Policy

Phase 26 defines safety policy data structures and validation. It does not enforce flight safety, mediate real drone commands, or integrate MAVLink, PX4, ArduPilot, ROS2, or real hardware. Aegis Edge is not ready for real flight and must not be used for real flight.

## Safety Envelope

The safety envelope can describe:

- geofence shape and boundary action
- altitude limits with explicit altitude reference
- horizontal and vertical velocity limits
- battery thresholds
- mode constraints
- command allow, ask, deny, and operator-approval lists
- network constraints
- emergency behavior constraints
- stale-state constraints

Geofence validation is schema/domain validation only. It catches malformed radius, polygon, and altitude limit inputs. It does not perform full geospatial containment or flight-path enforcement in Phase 26.

## Validation Rules

Validation catches:

- latitude outside `[-90, 90]`
- longitude outside `[-180, 180]`
- negative geofence radius
- max altitude lower than min altitude
- negative speed limits
- battery thresholds outside `[0, 100]`
- inconsistent battery thresholds
- unknown coordinate frame where known frame is required
- unknown altitude reference where known reference is required
- stale or expired state when fresh state is required
- missing vehicle id
- missing timestamp source
- duplicate command entries across allow/ask/deny/operator-approval lists

Deny priority is documented for fail-closed policy resolution. Validation still rejects duplicate entries across command lists so policy authors cannot hide a deny/allow conflict.

## Provenance

State provenance distinguishes fake adapter, PX4 SITL, ArduPilot SITL, bench, customer adapter, and unknown. Fake adapter state must remain fake. Unknown provenance is not safe for fresh-known validation.
