# Mission Safety

Mission upload is high risk. Phase 31 evaluates every mission waypoint with position data against the same geofence and altitude limits used for direct movement commands.

Behavior:

- complete safe missions proceed according to command policy
- a mission item outside the geofence denies the mission upload
- a mission item above the altitude ceiling denies the mission upload
- duplicate item sequence numbers are deterministic safety findings
- missing or reordered sequence numbers are not treated as safe
- unsupported mission item types are flagged by MAVLink mapping and are not silently allowed
- mission start is denied unless an auditable safe mission status is available

Mission findings are emitted as structured safety findings and prepared audit events. This is simulation/SITL evidence only, not flight approval.
