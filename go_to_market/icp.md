# Ideal Customer Profile

## Primary ICP

- Commercial drone/autonomy company.
- 10-300 employees.
- Engineering-led culture.
- Uses or evaluates PX4, ArduPilot, MAVLink, ROS2/MAVROS, companion computers, or agentic mission planning.
- Has a simulation/SITL environment.
- Has customer pressure around safety, audit, operational evidence, or internal review.
- Does not depend on immediate certified aircraft deployment.
- Open to design-partner evaluation.

## Best First Segments

- Utility and infrastructure inspection.
- Warehouse or indoor inventory drones.
- Agriculture and ranching drones.
- Public-safety drone operations with clear compliance workflows.
- Autonomous drone fleets.
- Drone data/analytics companies with an autonomy layer.
- Robotics companies using MAVLink-like command bridges.

## Avoid as first customers

- weapons/kinetic systems.
- Weapons/kinetic systems.
- Classified or export-controlled engagements.
- Teams demanding certified aircraft behavior immediately.
- Teams with no simulation/SITL process.
- Teams expecting Aegis to replace autopilot failsafes.
- Teams expecting regulatory approval from the tool.

## Buyer Personas

- CTO: owns technical risk, customer proof, and build-vs-buy.
- Head of Autonomy: owns command generation, planner safety, and simulation workflows.
- Robotics Lead: owns bridge integration, coordinate frames, and scenario coverage.
- Safety Lead: owns constraints, audit evidence, and review gates.
- Platform/Infrastructure Lead: owns SITL, CI, logs, and reproducibility.
- Founding Engineer: owns first integration and pilot execution.
- VP Engineering: owns budget, schedule, and cross-team risk.

## Strong Fit Signals

- Public mention of PX4, ArduPilot, MAVLink, ROS2, MAVROS, companion computers, autonomy, mission planning, geofencing, fleet operations, safety case, audit, simulation, or SITL.
- Hiring for autonomy, robotics, platform, simulation, safety, field reliability, or customer proof.
- Customer-facing claims that require evidence but do not yet require formal approval workflows.

## Weak Fit Signals

- No simulator.
- No autonomy command surface.
- Pure manual piloting.
- Need for immediate airworthiness approval.
- Refusal to start with local evaluation evidence.
