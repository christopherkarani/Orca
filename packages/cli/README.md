# Aegis CLI

Aegis CLI is the desktop and CI AI-agent runtime firewall product from Aegis v1.0.

## What Belongs Here

- `aegis` command parsing, help, version, doctor, policy, replay, run, MCP, red-team, and staging commands.
- Desktop and CI process supervision behavior for Aegis-managed child sessions.
- Desktop file, network, command, MCP, installer, release, and CLI documentation surfaces.
- CLI examples and CI recipes.

## What Does Not Belong Here

- Drone or robotics command mediation.
- MAVLink, PX4, ArduPilot, flight-controller, autopilot, or detect-and-avoid behavior.
- SaaS, telemetry, monetization, hosted dashboards, or product claims outside local CLI behavior.

## Current Status

Phase 23 keeps the existing `aegis` binary and CLI behavior intact. This package is a product boundary around the v1.0 CLI implementation.

## Future Phases

Future phases can continue to improve CLI packaging and desktop/CI behavior without coupling those changes to Aegis Edge runtime work.
