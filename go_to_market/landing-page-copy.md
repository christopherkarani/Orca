# Landing Page Copy

## Headline

Aegis Edge

## Subheadline

Safety-policy and audit runtime for autonomous drone agent evaluation in simulation, SITL, and bench-preparation workflows.

## Problem

Autonomy teams need to know what happens when an agent or planner asks for an unsafe command: outside-geofence movement, unsafe mission upload, failsafe modification, stale-state movement, or unknown telemetry egress.

## Demo

An agent attempts an unsafe command. Aegis Edge evaluates the request, denies it under policy, records replayable audit evidence, and generates a local safety-case report with limitations.

## How It Works

- Place Aegis Edge between an autonomy agent/planner and a supported command bridge.
- Define geofence, altitude, velocity, battery, approval, data, and health policies.
- Run fake adapter, PX4 SITL, ArduPilot SITL, or no-actuation bench scenarios.
- Generate audit/replay, red-team, and safety-case artifacts.

## What It Proves

- Policy decisions in supported scenarios.
- Replayable audit evidence for evaluated commands.
- Red-team findings and unsupported/skipped case visibility.
- Evidence quality for customer or internal technical review.

## What It Does Not Prove

- Aircraft airworthiness.
- Regulatory acceptance.
- Production deployment readiness.
- Complete MAVLink or customer-mode coverage.
- Replacement of autopilot failsafes or customer safety process.

## Supported Environments

- Fake adapter.
- PX4 SITL.
- ArduPilot SITL.
- Bench-preparation/no-actuation review.

## Pilot Offer

Two-week Simulation/SITL Safety Pilot for one autonomy workflow, including command surface inventory, baseline policy, scenario list, red-team run, safety-case report, audit/replay evidence, limitations, and next-step plan.

## CTA

Looking for 3 drone/autonomy design partners. Book a 20-minute technical call to see whether the demo maps to your stack.

## FAQ

Q: Is this certification?
A: No. It is customer-evaluation evidence only.

Q: Do we need aircraft hardware?
A: No. The first evaluation should run in fake adapter, SITL, or no-actuation bench-preparation mode.

Q: What if we use ROS2 or custom messages?
A: The first call maps the command surface and decides whether a pilot can be scoped around a supported bridge or bounded adapter.

Q: What if we already use PX4 or ArduPilot failsafes?
A: Aegis Edge is an additional policy and evidence layer for planner/agent commands; it does not replace those failsafes.

## Safety Boundary

Aegis Edge is customer-evaluation material only. It is limited to simulation/SITL/bench-preparation evaluation and does not include real flight, live aircraft control, certification, regulatory approval, detect-and-avoid, or replacement of autopilot safety functions.
