# Founder Email 1

Subject: Safety firewall for autonomous drone agents

Hey {{name}},

I'm building Aegis Edge - a policy and audit runtime that sits between autonomous agents and MAVLink/PX4/ArduPilot-style control bridges.

It helps teams test whether an agent/planner can:

- fly outside geofence
- exceed altitude/velocity limits
- disable failsafes
- upload unsafe missions
- stream mission/telemetry data to unknown endpoints

We have a simulation/SITL demo where an agent tries to send an unsafe command, Aegis denies it, and the safety-case report shows the exact rule and replayable audit trail.

This is not flight certification or a flight controller - it's a safety-policy and evidence layer for simulation/SITL/bench-prep workflows.

Would it be worth a 20-minute call to see if this maps to your autonomy stack?

{{sender}}
