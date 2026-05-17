# Discovery Call Script

## Opener

"Thanks for taking the time. I want to understand your autonomy stack and whether Edge maps to a real evaluation pain. This is not a certification or aircraft-control pitch. The current scope is simulation/SITL/bench-preparation evidence."

## Safety Boundary Statement

"Edge evaluates supported commands and evidence workflows in fake adapter, PX4 SITL, ArduPilot SITL, or no-actuation bench-preparation contexts. It does not replace your safety process, autopilot failsafes, regulatory work, or aircraft validation."

## Current Stack Questions

- Where does autonomy live in your stack?
- What planner, agent, or mission layer issues commands?
- What sits between the autonomy layer and the vehicle/control bridge?
- Do you use companion computers?
- Which parts are internal versus vendor-provided?

## Autonomy Command Surface Questions

- What commands can autonomy issue today?
- What commands are forbidden?
- Which commands require operator approval?
- Do agents/planners upload missions, change modes, arm/disarm, land, return home, or modify failsafes?
- Where are command denials recorded today?

## MAVLink/PX4/ArduPilot/SITL Questions

- Do you use PX4, ArduPilot, MAVLink, ROS2, MAVROS, or a custom bridge?
- Do you run SITL?
- Is SITL part of CI, release validation, customer demos, or safety review?
- Do you use custom MAVLink messages or vendor-specific modes?
- Which coordinate frames and altitude references matter?

## Safety Envelope Questions

- Do you have geofence/altitude/velocity limits independent of the planner?
- How do you define home position and allowed operating area?
- What happens when telemetry is stale or missing?
- What battery or link-health constraints gate movement?
- Which emergency commands are allowed and under what policy?

## Audit/Evidence Questions

- Do you have replayable evidence for unsafe commands being blocked?
- Can you show the exact rule, state, input command, and decision after a failed test?
- Do skipped or unsupported scenarios get tracked separately from passes?
- What artifacts are useful to engineering, operators, customers, or internal safety teams?

## Customer/Regulatory Pressure Questions

- Do customers ask for safety evidence before deployment?
- Do internal reviewers ask for traceability or scenario proof?
- Are you preparing for external safety review without needing Aegis to provide approval?
- What evidence would reduce buyer friction?

## Current Workflow Questions

- How do you test unsafe commands today?
- How do you red-team planner behavior?
- Where do mission, telemetry, and safety logs live?
- What is hard to reproduce after an incident or failed simulation?

## Pilot Fit Questions

- What would make a simulation/SITL pilot valuable?
- Can one autonomy workflow be isolated for a two-week pilot?
- Who owns SITL, policy constraints, and success criteria?
- What would block adoption?

## Next-Step Close

"If we can scope one workflow, one command surface, and one simulator or fake-adapter path, the next step is a technical validation call and then a two-week pilot proposal."
