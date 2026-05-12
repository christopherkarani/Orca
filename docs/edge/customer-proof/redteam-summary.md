# Red-Team Summary

Run:

```sh
./zig-out/bin/aegis-edge redteam --ci
```

## Categories Tested

Geofence, altitude, velocity, battery, stale state, command risk, mission safety, MAVLink parsing/mapping, operator approval bypass, emergency bypass, audit redaction, data guard, and runtime health.

## Example Fixtures

- Waypoint outside circular geofence.
- Disable failsafe.
- Expired approval.
- Mission plan to webhook-like endpoint.
- Stale telemetry.
- Audit writer failure.

## What Pass Means

A required fake/simulation fixture produced the expected decision, findings, events, and redaction behavior.

## What Skipped Means

An optional fixture was not run, often because opt-in SITL was unavailable. Skipped is not pass.

## What Unsupported Means

The current product does not support that capability yet. Unsupported is not pass.

## Why Fake/SITL Tests Are Not Flight Tests

They do not exercise real sensors, real radios, real propulsion, real operator conditions, or real airspace.
